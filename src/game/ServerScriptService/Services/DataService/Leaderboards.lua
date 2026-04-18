local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Globals = require(ReplicatedStorage.Lists.Globals)
local Schema = require(ReplicatedStorage.Lists.Schema)
local NumberFormatter = require(ReplicatedStorage.Shared.Formatting.NumberFormatter)

local RENDER_REFRESH_TIME = 10
local ROLLS_FLUSH_TIME = 10
local LEGACY_SYNC_REFRESH_TIME = 30
local MAX_FETCH_ENTRIES = 1000
local ORDERED_STORE_PAGE_SIZE = 100
local DEFAULT_VISIBLE_ENTRY_COUNT = 10
local ENTRY_NAME_PREFIX = "Entry_"
local SPACER_NAME_PREFIX = "Spacer_"
local SCOPE = Globals.SCOPE
local USE_GLOBAL_LEADERBOARDS_IN_STUDIO = true
local STUDIO_ORDERED_STORE_READ_RETRY_COUNT = 3
local STUDIO_ORDERED_STORE_READ_RETRY_DELAY = 1
-- Studio leaderboard validation stays isolated in a tester-seeded namespace.
-- Only players who join Studio sessions after this is enabled will populate these stores.
local STUDIO_ORDERED_STORE_SUFFIX = "_Studio"

local MONEY_KEY = Schema.Money and Schema.Money.key or "money"
local ROLLS_KEY = Schema.SuccessfulRollCount and Schema.SuccessfulRollCount.key or "successfulRollCount"

local BOARD_CONFIGS = {
	RollsLeaderboard = {
		key = ROLLS_KEY,
		format = "Rolls",
		useDirtySync = true,
		modelPaths = { "Map.RollsLeaderboard" },
		infoTitle = "Rolls",
		headerValueLabelNames = { "Rolls", "Value" },
		rowValueLabelNames = { "Rolls", "Value", "Money" },
	},
	MoneyLeaderboard = {
		key = MONEY_KEY,
		format = "Money",
		modelPaths = { "Map.MoneyLeaderboard" },
		infoTitle = "Money",
		headerValueLabelNames = { "Money", "Value", "Rolls" },
		rowValueLabelNames = { "Rolls", "Money", "Value" },
	},
}

local usernameCache = {}
local thumbnailCache = {}
local orderedStores = {}
local orderedStoreNames = {}
local lastSyncedValues = {}
local rollsLiveValues = {}
local rollsDirtyValues = {}
local rollsLastFlushedValues = {}
local started = false
local connectionsStarted = false

local TEMPLATE_SIZE_X_SCALE_ATTR = "LeaderboardTemplateSizeXScale"
local TEMPLATE_SIZE_X_OFFSET_ATTR = "LeaderboardTemplateSizeXOffset"
local TEMPLATE_SIZE_Y_SCALE_ATTR = "LeaderboardTemplateSizeYScale"
local TEMPLATE_SIZE_Y_OFFSET_ATTR = "LeaderboardTemplateSizeYOffset"

local function shouldUseOrderedStores(): boolean
	return not RunService:IsStudio() or USE_GLOBAL_LEADERBOARDS_IN_STUDIO
end

local function getOrderedStoreName(config): string
	local scopeSuffix = if RunService:IsStudio() then SCOPE .. STUDIO_ORDERED_STORE_SUFFIX else SCOPE
	return config.key .. scopeSuffix
end

local function isStudioRollsBoard(config): boolean
	return RunService:IsStudio() and config.key == ROLLS_KEY
end

local function readStoredTemplateSize(template)
	local xScale = template:GetAttribute(TEMPLATE_SIZE_X_SCALE_ATTR)
	local xOffset = template:GetAttribute(TEMPLATE_SIZE_X_OFFSET_ATTR)
	local yScale = template:GetAttribute(TEMPLATE_SIZE_Y_SCALE_ATTR)
	local yOffset = template:GetAttribute(TEMPLATE_SIZE_Y_OFFSET_ATTR)
	if typeof(xScale) ~= "number"
		or typeof(xOffset) ~= "number"
		or typeof(yScale) ~= "number"
		or typeof(yOffset) ~= "number"
	then
		return nil
	end

	return UDim2.new(xScale, xOffset, yScale, yOffset)
end

local function storeTemplateSize(template, templateSize)
	template:SetAttribute(TEMPLATE_SIZE_X_SCALE_ATTR, templateSize.X.Scale)
	template:SetAttribute(TEMPLATE_SIZE_X_OFFSET_ATTR, templateSize.X.Offset)
	template:SetAttribute(TEMPLATE_SIZE_Y_SCALE_ATTR, templateSize.Y.Scale)
	template:SetAttribute(TEMPLATE_SIZE_Y_OFFSET_ATTR, templateSize.Y.Offset)
end

local function formatMoney(value)
	return "$" .. NumberFormatter.Format(math.max(0, math.round(tonumber(value) or 0)))
end

local function formatRolls(value)
	return NumberFormatter.Format(math.max(0, math.floor(tonumber(value) or 0)))
end

local FORMATTERS = {
	Money = formatMoney,
	Rolls = formatRolls,
}

local function formatValue(formatName, value)
	local formatter = FORMATTERS[formatName] or tostring
	return formatter(value)
end

local function normalizeBoardValue(value)
	return math.max(0, math.floor(tonumber(value) or 0))
end

local function findFirstChildByNames(parent, names)
	if not parent then
		return nil
	end

	for _, childName in ipairs(names) do
		local child = parent:FindFirstChild(childName)
		if child then
			return child
		end
	end

	return nil
end

local function resolveWorkspacePath(path)
	local current = Workspace

	for segment in string.gmatch(path, "[^%.]+") do
		current = current and current:FindFirstChild(segment)
		if not current then
			return nil
		end
	end

	return current
end

local function getBoardModels(config)
	local boardModels = {}

	for _, path in ipairs(config.modelPaths or {}) do
		local boardModel = resolveWorkspacePath(path)
		if boardModel then
			boardModels[#boardModels + 1] = boardModel
		end
	end

	return boardModels
end

local function getUsernameForUserId(userId)
	if usernameCache[userId] then
		return usernameCache[userId]
	end

	local success, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if not success or typeof(result) ~= "string" or result == "" then
		return tostring(userId)
	end

	usernameCache[userId] = result
	return result
end

local function getThumbnailForUserId(userId)
	if thumbnailCache[userId] then
		return thumbnailCache[userId]
	end

	local success, content = pcall(function()
		local image, isReady = Players:GetUserThumbnailAsync(
			userId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size420x420
		)

		if isReady == false or typeof(image) ~= "string" or image == "" then
			return nil
		end

		return image
	end)
	if not success then
		return nil
	end

	thumbnailCache[userId] = content
	return content
end

local function getSurfaceGui(boardModel)
	for _, descendant in ipairs(boardModel:GetDescendants()) do
		if descendant:IsA("SurfaceGui") then
			return descendant
		end
	end

	return nil
end

local function getBoardWidgets(boardModel, config)
	if not boardModel then
		return nil
	end

	local surfaceGui = getSurfaceGui(boardModel)
	if not surfaceGui then
		return nil
	end

	local leaderboardFrame = surfaceGui:FindFirstChild("Leaderboard")
	local inner = leaderboardFrame and leaderboardFrame:FindFirstChild("Inner")
	local scrollingFrame = inner and inner:FindFirstChild("ScrollingFrame")
	local template = scrollingFrame and scrollingFrame:FindFirstChild("Template")
	local topFrame = inner and inner:FindFirstChild("TopFrame")
	local playerInfo = inner and inner:FindFirstChild("PlayerInfo")
	if not (leaderboardFrame and inner and scrollingFrame and template and topFrame and playerInfo) then
		return nil
	end

	local rollInfo = playerInfo:FindFirstChild("RollInfo")
	local playerIcon = playerInfo:FindFirstChild("PlayerIcon")
	local templateSize = template.Size
	if templateSize.Y.Scale > 0 or templateSize.Y.Offset > 0 then
		storeTemplateSize(template, templateSize)
	else
		local storedTemplateSize = readStoredTemplateSize(template)
		if storedTemplateSize then
			templateSize = storedTemplateSize
		else
			templateSize = UDim2.new(1, 0, 0.1, 0)
		end
	end

	return {
		surfaceGui = surfaceGui,
		scrollingFrame = scrollingFrame,
		template = template,
		templateAbsoluteHeight = template.AbsoluteSize.Y,
		templateSize = templateSize,
		listLayout = scrollingFrame:FindFirstChildWhichIsA("UIListLayout"),
		headerPlayerName = topFrame:FindFirstChild("PlayerName"),
		headerValue = findFirstChildByNames(topFrame, config.headerValueLabelNames or { "Value" }),
		playerInfo = playerInfo,
		playerInfoDisplayName = playerInfo:FindFirstChild("DisplayName"),
		playerInfoUsername = playerInfo:FindFirstChild("Username"),
		playerInfoRollInfo = rollInfo,
		playerInfoRollInfoTitle = rollInfo and rollInfo:FindFirstChild("Title") or nil,
		playerInfoRollInfoContext = rollInfo and rollInfo:FindFirstChild("Context") or nil,
		playerInfoIcon = playerIcon and playerIcon:FindFirstChild("Image") or nil,
		playerInfoButtons = {
			playerInfo:FindFirstChild("AddFriendButton"),
			playerInfo:FindFirstChild("BlockButton"),
			playerInfo:FindFirstChild("CloseButton"),
		},
		rowRankLabelNames = { "LeaderboardPlace", "Number" },
		rowPlayerNameLabelNames = { "PlayerName", "Username" },
		rowValueLabelNames = config.rowValueLabelNames or { "Value" },
	}
end

local function disableBoardScripts(boardModel)
	local surfaceGui = getSurfaceGui(boardModel)
	if not surfaceGui then
		return
	end

	for _, descendant in ipairs(surfaceGui:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant.Disabled = true
		end
	end
end

local function ensureScrollingFrameLayout(widgets)
	local scrollingFrame = widgets.scrollingFrame
	scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y

	local layout = widgets.listLayout
	if layout then
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		return
	end

	layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scrollingFrame
	widgets.listLayout = layout
end

local function clearRenderedEntries(widgets)
	for _, child in ipairs(widgets.scrollingFrame:GetChildren()) do
		if child:IsA("GuiObject")
			and (
				string.sub(child.Name, 1, #ENTRY_NAME_PREFIX) == ENTRY_NAME_PREFIX
				or string.sub(child.Name, 1, #SPACER_NAME_PREFIX) == SPACER_NAME_PREFIX
			)
		then
			child:Destroy()
		end
	end
end

local function getRowStride(widgets)
	local rowHeight = widgets.templateAbsoluteHeight or 0
	if rowHeight <= 0 then
		if widgets.templateSize.Y.Offset > 0 then
			rowHeight = widgets.templateSize.Y.Offset
		elseif widgets.templateSize.Y.Scale > 0 then
			local viewportHeight = widgets.scrollingFrame.AbsoluteWindowSize.Y
			if viewportHeight <= 0 then
				viewportHeight = widgets.scrollingFrame.AbsoluteSize.Y
			end
			if viewportHeight > 0 then
				rowHeight = math.floor(viewportHeight * widgets.templateSize.Y.Scale + 0.5)
			end
		end
	end

	local padding = 0
	if widgets.listLayout then
		padding = widgets.listLayout.Padding.Offset
	end

	return math.max(1, rowHeight), math.max(0, padding)
end

local function getVisibleWindow(widgets, totalEntries)
	local viewportHeight = widgets.scrollingFrame.AbsoluteWindowSize.Y
	if viewportHeight <= 0 then
		viewportHeight = widgets.scrollingFrame.AbsoluteSize.Y
	end

	local rowHeight, padding = getRowStride(widgets)
	if viewportHeight <= 0 then
		local visibleCountFromScale = 0
		if widgets.templateSize.Y.Scale > 0 then
			visibleCountFromScale = math.floor((1 / widgets.templateSize.Y.Scale) + 0.0001)
		end

		local fallbackVisibleCount = if visibleCountFromScale > 0 then visibleCountFromScale else DEFAULT_VISIBLE_ENTRY_COUNT
		return 1, math.min(totalEntries, fallbackVisibleCount)
	end

	local rowStride = math.max(1, rowHeight + padding)
	local firstVisibleRank = math.max(1, math.floor(widgets.scrollingFrame.CanvasPosition.Y / rowStride) + 1)
	local visibleCount = math.max(1, math.ceil((viewportHeight + padding) / rowStride))
	local lastVisibleRank = math.min(totalEntries, firstVisibleRank + visibleCount - 1)

	return firstVisibleRank, lastVisibleRank
end

local function setGuiText(instance, text)
	if instance and instance:IsA("TextLabel") then
		instance.Text = text
	end
end

local function setGuiVisible(instance, visible)
	if not (instance and instance:IsA("GuiObject")) then
		return
	end

	instance.Visible = visible
	if instance:IsA("GuiButton") then
		instance.Active = visible
		instance.AutoButtonColor = false
	end
end

local function createBoardEntry(widgets, rank, entryData, formatName)
	local row = widgets.template:Clone()
	row.Name = ENTRY_NAME_PREFIX .. tostring(rank)
	row.LayoutOrder = rank
	row.Size = widgets.templateSize
	row.Visible = true
	row.Parent = widgets.scrollingFrame

	setGuiText(findFirstChildByNames(row, widgets.rowRankLabelNames), string.format("#%d", rank))
	setGuiText(findFirstChildByNames(row, widgets.rowPlayerNameLabelNames), entryData.name)
	setGuiText(findFirstChildByNames(row, widgets.rowValueLabelNames), formatValue(formatName, entryData.value))
end

local function createSpacer(widgets, name, layoutOrder, height)
	if height <= 0 then
		return
	end

	local spacer = Instance.new("Frame")
	spacer.Name = name
	spacer.BackgroundTransparency = 1
	spacer.BorderSizePixel = 0
	spacer.Size = UDim2.new(1, 0, 0, height)
	spacer.LayoutOrder = layoutOrder
	spacer.Parent = widgets.scrollingFrame
end

local function renderPlayerInfo(widgets, config, topEntry)
	local playerInfo = widgets.playerInfo
	if not playerInfo then
		return
	end

	for _, button in ipairs(widgets.playerInfoButtons) do
		setGuiVisible(button, false)
	end

	if not topEntry then
		setGuiVisible(playerInfo, false)
		return
	end

	setGuiVisible(playerInfo, true)
	setGuiText(widgets.playerInfoDisplayName, topEntry.name)
	setGuiText(widgets.playerInfoUsername, "@" .. topEntry.name)
	setGuiText(widgets.playerInfoRollInfoTitle, config.infoTitle or config.format)
	setGuiText(widgets.playerInfoRollInfoContext, formatValue(config.format, topEntry.value))

	if widgets.playerInfoIcon and widgets.playerInfoIcon:IsA("ImageLabel") then
		local thumbnail = getThumbnailForUserId(topEntry.userId)
		if thumbnail then
			widgets.playerInfoIcon.Image = thumbnail
		end
	end
end

local function renderBoard(boardModel, config, entries)
	local widgets = getBoardWidgets(boardModel, config)
	if not widgets then
		return
	end

	disableBoardScripts(boardModel)
	ensureScrollingFrameLayout(widgets)
	clearRenderedEntries(widgets)

	widgets.template.Visible = false
	widgets.template.Size = widgets.templateSize
	widgets.template.LayoutOrder = MAX_FETCH_ENTRIES + 2
	setGuiText(widgets.headerPlayerName, "Player")
	setGuiText(widgets.headerValue, config.infoTitle or config.format)
	renderPlayerInfo(widgets, config, entries[1])

	local firstVisibleRank, lastVisibleRank = getVisibleWindow(widgets, #entries)
	local rowHeight, padding = getRowStride(widgets)
	local rowStride = math.max(1, rowHeight + padding)
	createSpacer(widgets, SPACER_NAME_PREFIX .. "Top", 0, (firstVisibleRank - 1) * rowStride)

	for rank = firstVisibleRank, lastVisibleRank do
		local entryData = entries[rank]
		if entryData then
			createBoardEntry(widgets, rank, entryData, config.format)
		end
	end

	createSpacer(
		widgets,
		SPACER_NAME_PREFIX .. "Bottom",
		math.max(lastVisibleRank, 0) + 1,
		math.max(0, #entries - lastVisibleRank) * rowStride
	)
end

local function sortEntriesDescending(entries)
	table.sort(entries, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.userId < b.userId
	end)

	while #entries > MAX_FETCH_ENTRIES do
		table.remove(entries)
	end
end

local function getCurrentPlayerEntries(dataService, key)
	local entries = {}

	for _, player in ipairs(Players:GetPlayers()) do
		local value = tonumber(dataService:Get(player, key)) or 0
		if value > 0 then
			entries[#entries + 1] = {
				userId = player.UserId,
				name = player.Name,
				value = value,
			}
		end
	end

	sortEntriesDescending(entries)
	return entries
end

local function overlayLiveRollEntries(orderedEntries)
	local mergedEntriesByUserId = {}

	for _, entry in ipairs(orderedEntries) do
		mergedEntriesByUserId[entry.userId] = {
			userId = entry.userId,
			name = entry.name,
			value = normalizeBoardValue(entry.value),
		}
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local userId = player.UserId
		local liveValue = normalizeBoardValue(rollsLiveValues[userId])
		if liveValue > 0 then
			mergedEntriesByUserId[userId] = {
				userId = userId,
				name = player.Name,
				value = liveValue,
			}
		else
			mergedEntriesByUserId[userId] = nil
		end
	end

	local mergedEntries = {}
	for _, entry in pairs(mergedEntriesByUserId) do
		if entry.value > 0 then
			mergedEntries[#mergedEntries + 1] = entry
		end
	end

	sortEntriesDescending(mergedEntries)
	return mergedEntries
end

local function getMissingVisibleEntries(localEntries, orderedEntries)
	local missingEntries = {}
	local orderedEntriesByUserId = {}
	for _, entry in ipairs(orderedEntries) do
		orderedEntriesByUserId[entry.userId] = true
	end

	local pageSize = math.min(ORDERED_STORE_PAGE_SIZE, MAX_FETCH_ENTRIES)
	local cutoffValue = if #orderedEntries > 0 then orderedEntries[#orderedEntries].value else nil
	for _, entry in ipairs(localEntries) do
		local shouldBeVisible = #orderedEntries < pageSize or cutoffValue == nil or entry.value > cutoffValue
		if entry.value > 0 and shouldBeVisible and not orderedEntriesByUserId[entry.userId] then
			missingEntries[#missingEntries + 1] = entry
		end
	end

	return missingEntries
end

local function setRollsLiveValue(userId: number, value: number)
	rollsLiveValues[userId] = normalizeBoardValue(value)
end

local function markRollsValueDirty(userId: number, value: number)
	local normalizedValue = normalizeBoardValue(value)
	setRollsLiveValue(userId, normalizedValue)
	if rollsLastFlushedValues[userId] ~= normalizedValue then
		rollsDirtyValues[userId] = normalizedValue
	else
		rollsDirtyValues[userId] = nil
	end
end

local function clearRollsTracking(userId: number)
	rollsLiveValues[userId] = nil
	rollsDirtyValues[userId] = nil
	rollsLastFlushedValues[userId] = nil
end

local function syncRollsValueToStore(boardName, storeName, store, userId, value)
	local normalizedValue = normalizeBoardValue(value)
	local success, errorMessage = pcall(function()
		store:SetAsync(userId, normalizedValue)
	end)
	if not success then
		warn(string.format(
			"[Leaderboards] Failed to write board=%s store=%s userId=%d value=%d: %s",
			boardName,
			storeName,
			userId,
			normalizedValue,
			tostring(errorMessage)
		))
		return false
	end

	rollsLastFlushedValues[userId] = normalizedValue
	if rollsDirtyValues[userId] == normalizedValue then
		rollsDirtyValues[userId] = nil
	end

	return true
end

local function syncPlayerValueToStore(dataService, boardName, config, storeName, store, player)
	local userId = player.UserId
	local boardValues = lastSyncedValues[boardName]
	if not boardValues then
		boardValues = {}
		lastSyncedValues[boardName] = boardValues
	end

	local value = normalizeBoardValue(dataService:Get(player, config.key))
	if boardValues[userId] == value then
		return
	end

	local success, errorMessage = pcall(function()
		store:SetAsync(userId, value)
	end)
	if not success then
		warn(string.format(
			"[Leaderboards] Failed to write board=%s store=%s userId=%d value=%d: %s",
			boardName,
			storeName,
			userId,
			value,
			tostring(errorMessage)
		))
		return
	end

	boardValues[userId] = value
end

local function pushChangedPlayerData(dataService, boardName, config, storeName, store)
	for _, player in ipairs(Players:GetPlayers()) do
		syncPlayerValueToStore(dataService, boardName, config, storeName, store, player)
	end
end

local function flushDirtyRollsData(boardName, storeName, store)
	local dirtyUserIds = {}
	for userId in pairs(rollsDirtyValues) do
		dirtyUserIds[#dirtyUserIds + 1] = userId
	end

	table.sort(dirtyUserIds)

	for _, userId in ipairs(dirtyUserIds) do
		local value = rollsDirtyValues[userId]
		if value ~= nil then
			syncRollsValueToStore(boardName, storeName, store, userId, value)
		end
	end
end

local function getOrderedStoreEntries(boardName, storeName, store)
	local pageSize = math.min(ORDERED_STORE_PAGE_SIZE, MAX_FETCH_ENTRIES)
	local success, pages = pcall(function()
		return store:GetSortedAsync(false, pageSize)
	end)
	if not success or not pages then
		warn(string.format(
			"[Leaderboards] Failed to read board=%s store=%s via GetSortedAsync: %s",
			boardName,
			storeName,
			tostring(pages)
		))
		return {}
	end

	local entries = {}
	while #entries < MAX_FETCH_ENTRIES do
		local currentPage = pages:GetCurrentPage()
		for _, item in ipairs(currentPage) do
			local userId = tonumber(item.key)
			local value = tonumber(item.value) or 0
			if userId and value > 0 then
				entries[#entries + 1] = {
					userId = userId,
					name = getUsernameForUserId(userId),
					value = value,
				}
			end

			if #entries >= MAX_FETCH_ENTRIES then
				break
			end
		end

		local isFinished = false
		local finishedSuccess, finishedResult = pcall(function()
			return pages.IsFinished
		end)
		if finishedSuccess and finishedResult == true then
			isFinished = true
		end

		if isFinished or #entries >= MAX_FETCH_ENTRIES then
			break
		end

		local advanced, advanceError = pcall(function()
			pages:AdvanceToNextPageAsync()
		end)
		if not advanced then
			warn(string.format(
				"[Leaderboards] Failed to advance page for board=%s store=%s: %s",
				boardName,
				storeName,
				tostring(advanceError)
			))
			break
		end
	end

	return entries
end

local function retryStudioRollEntries(dataService, boardName, config, storeName, store, entries)
	if not isStudioRollsBoard(config) then
		return entries
	end

	local localEntries = getCurrentPlayerEntries(dataService, config.key)
	local missingEntries = getMissingVisibleEntries(localEntries, entries)
	if #missingEntries == 0 then
		return entries
	end

	for _ = 1, STUDIO_ORDERED_STORE_READ_RETRY_COUNT do
		task.wait(STUDIO_ORDERED_STORE_READ_RETRY_DELAY)
		entries = getOrderedStoreEntries(boardName, storeName, store)
		missingEntries = getMissingVisibleEntries(localEntries, entries)
		if #missingEntries == 0 then
			return entries
		end
	end

	for _, entry in ipairs(missingEntries) do
		warn(string.format(
			"[Leaderboards] Studio rolls entry missing after retry board=%s store=%s userId=%d value=%d",
			boardName,
			storeName,
			entry.userId,
			entry.value
		))
	end

	return entries
end

local function getOrderedEntriesForBoard(dataService, boardName, config, storeName, store)
	local entries = getOrderedStoreEntries(boardName, storeName, store)
	if config.useDirtySync then
		return overlayLiveRollEntries(entries)
	end

	return retryStudioRollEntries(dataService, boardName, config, storeName, store, entries)
end

local function syncLegacyBoards(dataService)
	if not shouldUseOrderedStores() then
		return
	end

	for boardName, config in pairs(BOARD_CONFIGS) do
		if config.useDirtySync ~= true then
			local store = orderedStores[boardName]
			local storeName = orderedStoreNames[boardName]
			if store then
				pushChangedPlayerData(dataService, boardName, config, storeName, store)
			end
		end
	end
end

local Leaderboards = {}

function Leaderboards.connect(dataService)
	if connectionsStarted then
		return
	end
	connectionsStarted = true

	dataService.PlayerDataLoaded:Connect(function(player)
		local currentValue = normalizeBoardValue(dataService:Get(player, ROLLS_KEY))
		setRollsLiveValue(player.UserId, currentValue)
		if currentValue > 0 then
			markRollsValueDirty(player.UserId, currentValue)
		end
	end)

	dataService.SuccessfulRollIncremented:Connect(function(player, _previousValue, updatedValue)
		markRollsValueDirty(player.UserId, updatedValue)
	end)
end

function Leaderboards.flushPlayer(dataService, player)
	if not shouldUseOrderedStores() then
		clearRollsTracking(player.UserId)
		return
	end

	for boardName, config in pairs(BOARD_CONFIGS) do
		local store = orderedStores[boardName]
		local storeName = orderedStoreNames[boardName]
		if store then
			if config.useDirtySync then
				local liveValue = rollsLiveValues[player.UserId]
				local currentValue = if liveValue ~= nil then liveValue else dataService:Get(player, config.key)
				syncRollsValueToStore(boardName, storeName, store, player.UserId, currentValue)
			else
				syncPlayerValueToStore(dataService, boardName, config, storeName, store, player)
			end
		end
	end

	clearRollsTracking(player.UserId)
end

function Leaderboards.refresh(dataService)
	for boardName, config in pairs(BOARD_CONFIGS) do
		local boardModels = getBoardModels(config)
		if #boardModels > 0 then
			local entries = nil
			if shouldUseOrderedStores() then
				local store = orderedStores[boardName]
				local storeName = orderedStoreNames[boardName]
				if store then
					entries = getOrderedEntriesForBoard(dataService, boardName, config, storeName, store)
				else
					entries = {}
				end
			else
				entries = getCurrentPlayerEntries(dataService, config.key)
			end

			for _, boardModel in ipairs(boardModels) do
				renderBoard(boardModel, config, entries or {})
			end
		end
	end
end

function Leaderboards.start(dataService)
	local foundAnyBoard = false
	for _, config in pairs(BOARD_CONFIGS) do
		if #getBoardModels(config) > 0 then
			foundAnyBoard = true
			break
		end
	end

	if not foundAnyBoard then
		warn("[Leaderboards] Missing global leaderboard models in Workspace.Map")
		return
	end

	if started then
		Leaderboards.refresh(dataService)
		return
	end
	started = true

	if shouldUseOrderedStores() then
		for boardName, config in pairs(BOARD_CONFIGS) do
			local storeName = getOrderedStoreName(config)
			orderedStoreNames[boardName] = storeName
			orderedStores[boardName] = DataStoreService:GetOrderedDataStore(storeName)
		end
	end

	syncLegacyBoards(dataService)
	if shouldUseOrderedStores() then
		local rollsBoardName = "RollsLeaderboard"
		local rollsConfig = BOARD_CONFIGS[rollsBoardName]
		local rollsStore = orderedStores[rollsBoardName]
		local rollsStoreName = orderedStoreNames[rollsBoardName]
		if rollsConfig and rollsStore and rollsStoreName then
			flushDirtyRollsData(rollsBoardName, rollsStoreName, rollsStore)
		end
	end

	Leaderboards.refresh(dataService)
	task.spawn(function()
		while true do
			Leaderboards.refresh(dataService)
			task.wait(RENDER_REFRESH_TIME)
		end
	end)
	task.spawn(function()
		while true do
			if shouldUseOrderedStores() then
				local rollsBoardName = "RollsLeaderboard"
				local rollsStore = orderedStores[rollsBoardName]
				local rollsStoreName = orderedStoreNames[rollsBoardName]
				if rollsStore and rollsStoreName then
					flushDirtyRollsData(rollsBoardName, rollsStoreName, rollsStore)
				end
			end
			task.wait(ROLLS_FLUSH_TIME)
		end
	end)
	task.spawn(function()
		while true do
			syncLegacyBoards(dataService)
			task.wait(LEGACY_SYNC_REFRESH_TIME)
		end
	end)
end

return Leaderboards
