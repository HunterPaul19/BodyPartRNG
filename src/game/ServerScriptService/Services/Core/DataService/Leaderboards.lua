local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Globals = require(ReplicatedStorage.Lists.Globals)
local Schema = require(ReplicatedStorage.Lists.Schema)
local NumberFormatter = require(ReplicatedStorage.Shared.Formatting.NumberFormatter)
local RateLimitTelemetry = require(script.Parent.Parent.Common.RateLimitTelemetry)

local RENDER_REFRESH_TIME = 10
local GLOBAL_FETCH_INTERVAL_SECONDS = 180
local GLOBAL_FETCH_JITTER_SECONDS = 90
local GLOBAL_FETCH_ENTRY_LIMIT = 50
local GLOBAL_FETCH_BOARD_SPACING_SECONDS = 5
local ORDERED_LIST_BUDGET_FLOOR = 3
local ROLLS_FLUSH_TIME = 60
local LEGACY_SYNC_REFRESH_TIME = 120
local MONEY_MIN_FLUSH_DELTA = 100
local DEFAULT_VISIBLE_ENTRY_COUNT = 10
local ENTRY_NAME_PREFIX = "Entry_"
local SPACER_NAME_PREFIX = "Spacer_"
local SCOPE = Globals.SCOPE
local USE_GLOBAL_LEADERBOARDS_IN_STUDIO = true
-- Studio leaderboard validation stays isolated in a tester-seeded namespace.
-- Only players who join Studio sessions after this is enabled will populate these stores.
local STUDIO_ORDERED_STORE_SUFFIX = "_Studio"

local MONEY_KEY = Schema.Money and Schema.Money.key or "money"
local ROLLS_KEY = Schema.SuccessfulRollCount and Schema.SuccessfulRollCount.key or "successfulRollCount"
local TIME_PLAYED_KEY = Schema.TimePlayed and Schema.TimePlayed.key or "timePlayed"

local BOARD_CONFIGS = {
	RollsLeaderboard = {
		key = ROLLS_KEY,
		format = "Rolls",
		useDirtySync = true,
		minFlushIntervalSeconds = ROLLS_FLUSH_TIME,
		modelPaths = { "Map.RollsLeaderboard" },
		infoTitle = "Rolls",
		headerValueLabelNames = { "Rolls", "Value" },
		rowValueLabelNames = { "Rolls", "Value", "Money" },
	},
	MoneyLeaderboard = {
		key = MONEY_KEY,
		format = "Money",
		minFlushIntervalSeconds = LEGACY_SYNC_REFRESH_TIME,
		minFlushDelta = MONEY_MIN_FLUSH_DELTA,
		modelPaths = { "Map.MoneyLeaderboard" },
		infoTitle = "Money",
		headerValueLabelNames = { "Money", "Value", "Rolls" },
		rowValueLabelNames = { "Rolls", "Money", "Value" },
	},
	PlaytimeLeaderboard = {
		key = TIME_PLAYED_KEY,
		format = "Playtime",
		minFlushIntervalSeconds = LEGACY_SYNC_REFRESH_TIME,
		modelPaths = { "Map.PlaytimeLeaderboard" },
		infoTitle = "Playtime",
		headerValueLabelNames = { "Playtime", "TimePlayed", "Time", "Rolls", "Value" },
		rowValueLabelNames = { "Playtime", "TimePlayed", "Time", "Rolls", "Value", "Money" },
	},
}

local usernameCache = {}
local thumbnailCache = {}
local orderedStores = {}
local orderedStoreNames = {}
local orderedEntryCaches = {}
local lastSyncedValues = {}
local lastSyncedAt = {}
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

local function formatPlaytime(value)
	local seconds = math.max(0, math.floor(tonumber(value) or 0))
	local days = math.floor(seconds / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	local minutes = math.floor((seconds % 3600) / 60)

	if days > 0 then
		return string.format("%dd %dh", days, hours)
	end
	if hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	end

	return string.format("%dm", minutes)
end

local FORMATTERS = {
	Money = formatMoney,
	Playtime = formatPlaytime,
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

local function resolveEntryName(entry)
	if typeof(entry) ~= "table" then
		return ""
	end

	if typeof(entry.name) == "string" and entry.name ~= "" then
		return entry.name
	end

	local userId = tonumber(entry.userId)
	if not userId then
		entry.name = ""
		return entry.name
	end

	entry.name = getUsernameForUserId(userId)
	return entry.name
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
	setGuiText(findFirstChildByNames(row, widgets.rowPlayerNameLabelNames), resolveEntryName(entryData))
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
	local topName = resolveEntryName(topEntry)
	setGuiText(widgets.playerInfoDisplayName, topName)
	setGuiText(widgets.playerInfoUsername, "@" .. topName)
	setGuiText(widgets.playerInfoRollInfoTitle, config.infoTitle or config.format)
	setGuiText(widgets.playerInfoRollInfoContext, formatValue(config.format, topEntry.value))

	if widgets.playerInfoIcon and widgets.playerInfoIcon:IsA("ImageLabel") then
		local thumbnail = getThumbnailForUserId(topEntry.userId)
		if thumbnail then
			widgets.playerInfoIcon.Image = thumbnail
		end
	end
end

local function hydrateVisibleEntryNames(entries, firstVisibleRank, lastVisibleRank)
	if entries[1] then
		resolveEntryName(entries[1])
	end

	for rank = firstVisibleRank, lastVisibleRank do
		local entry = entries[rank]
		if entry then
			resolveEntryName(entry)
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
	widgets.template.LayoutOrder = GLOBAL_FETCH_ENTRY_LIMIT + 2
	setGuiText(widgets.headerPlayerName, "Player")
	setGuiText(widgets.headerValue, config.infoTitle or config.format)

	local firstVisibleRank, lastVisibleRank = getVisibleWindow(widgets, #entries)
	hydrateVisibleEntryNames(entries, firstVisibleRank, lastVisibleRank)
	renderPlayerInfo(widgets, config, entries[1])

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

	while #entries > GLOBAL_FETCH_ENTRY_LIMIT do
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

local function cloneEntries(entries)
	local clonedEntries = {}
	if typeof(entries) ~= "table" then
		return clonedEntries
	end

	for index, entry in ipairs(entries) do
		clonedEntries[index] = {
			userId = entry.userId,
			name = entry.name,
			value = entry.value,
		}
	end

	return clonedEntries
end

local function getOrderedEntryCache(boardName)
	local cache = orderedEntryCaches[boardName]
	if not cache then
		cache = {
			entries = {},
			lastSuccessfulFetchAt = 0,
			nextAllowedFetchAt = 0,
			inFlight = false,
			lastError = nil,
		}
		orderedEntryCaches[boardName] = cache
	end

	return cache
end

local function getFetchJitterSeconds()
	if GLOBAL_FETCH_JITTER_SECONDS <= 0 then
		return 0
	end

	return math.random(0, GLOBAL_FETCH_JITTER_SECONDS)
end

local function scheduleNextFetch(cache, baseDelaySeconds)
	cache.nextAllowedFetchAt = os.clock() + math.max(1, baseDelaySeconds) + getFetchJitterSeconds()
end

local function scheduleInitialFetch(cache)
	cache.nextAllowedFetchAt = os.clock() + getFetchJitterSeconds()
end

local function getOrderedListBudget()
	local success, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetSortedAsync)
	end)
	if not success then
		return 0
	end

	return math.max(0, math.floor(tonumber(budget) or 0))
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

local function getBoardSyncMaps(boardName)
	local boardValues = lastSyncedValues[boardName]
	if not boardValues then
		boardValues = {}
		lastSyncedValues[boardName] = boardValues
	end

	local boardTimes = lastSyncedAt[boardName]
	if not boardTimes then
		boardTimes = {}
		lastSyncedAt[boardName] = boardTimes
	end

	return boardValues, boardTimes
end

local function syncRollsValueToStore(boardName, storeName, store, userId, value)
	local normalizedValue = normalizeBoardValue(value)
	local success, errorMessage = pcall(function()
		store:SetAsync(userId, normalizedValue)
	end)
	if not success then
		Logger.Warn(string.format(
			"[Leaderboards] Failed to write board=%s store=%s userId=%d value=%d: %s",
			boardName,
			storeName,
			userId,
			normalizedValue,
			tostring(errorMessage)
		))
		RateLimitTelemetry.Increment("data_store_error", "leaderboard_ordered_write", 1)
		return false
	end

	rollsLastFlushedValues[userId] = normalizedValue
	local boardValues, boardTimes = getBoardSyncMaps(boardName)
	boardValues[userId] = normalizedValue
	boardTimes[userId] = os.clock()
	if rollsDirtyValues[userId] == normalizedValue then
		rollsDirtyValues[userId] = nil
	end

	return true
end

local function syncPlayerValueToStore(dataService, boardName, config, storeName, store, player, options)
	local userId = player.UserId
	local boardValues, boardTimes = getBoardSyncMaps(boardName)

	local value = normalizeBoardValue(dataService:Get(player, config.key))
	if boardValues[userId] == value then
		return
	end

	local forceSync = typeof(options) == "table" and options.force == true
	local minFlushIntervalSeconds = tonumber(config.minFlushIntervalSeconds)
	if not forceSync and minFlushIntervalSeconds and minFlushIntervalSeconds > 0 then
		local lastSyncAtSeconds = tonumber(boardTimes[userId]) or 0
		if lastSyncAtSeconds > 0 and (os.clock() - lastSyncAtSeconds) < minFlushIntervalSeconds then
			return
		end
	end

	local minFlushDelta = tonumber(config.minFlushDelta)
	if not forceSync and minFlushDelta and minFlushDelta > 0 and boardValues[userId] ~= nil then
		if math.abs(value - boardValues[userId]) < minFlushDelta then
			return
		end
	end

	local success, errorMessage = pcall(function()
		store:SetAsync(userId, value)
	end)
	if not success then
		Logger.Warn(string.format(
			"[Leaderboards] Failed to write board=%s store=%s userId=%d value=%d: %s",
			boardName,
			storeName,
			userId,
			value,
			tostring(errorMessage)
		))
		RateLimitTelemetry.Increment("data_store_error", "leaderboard_ordered_write", 1)
		return
	end

	boardValues[userId] = value
	boardTimes[userId] = os.clock()
end

local function pushChangedPlayerData(dataService, boardName, config, storeName, store, options)
	for _, player in ipairs(Players:GetPlayers()) do
		syncPlayerValueToStore(dataService, boardName, config, storeName, store, player, options)
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
	local success, pages = pcall(function()
		return store:GetSortedAsync(false, GLOBAL_FETCH_ENTRY_LIMIT)
	end)
	if not success or not pages then
		Logger.Warn(string.format(
			"[Leaderboards] Failed to read board=%s store=%s via GetSortedAsync: %s",
			boardName,
			storeName,
			tostring(pages)
		))
		RateLimitTelemetry.Increment("leaderboard", "ordered_list_fetch_failure", 1)
		return nil, pages
	end

	local entries = {}
	local pageSuccess, currentPage = pcall(function()
		return pages:GetCurrentPage()
	end)
	if not pageSuccess or typeof(currentPage) ~= "table" then
		Logger.Warn(string.format(
			"[Leaderboards] Failed to read current page for board=%s store=%s: %s",
			boardName,
			storeName,
			tostring(currentPage)
		))
		RateLimitTelemetry.Increment("leaderboard", "ordered_list_fetch_failure", 1)
		return nil, currentPage
	end

	for _, item in ipairs(currentPage) do
		local userId = tonumber(item.key)
		local value = tonumber(item.value) or 0
		if userId and value > 0 then
			entries[#entries + 1] = {
				userId = userId,
				value = value,
			}
		end

		if #entries >= GLOBAL_FETCH_ENTRY_LIMIT then
			break
		end
	end

	return entries, nil
end

local function updateOrderedEntriesCache(dataService, boardName, config, storeName, store)
	local cache = getOrderedEntryCache(boardName)
	if cache.inFlight then
		RateLimitTelemetry.Increment("leaderboard", "ordered_list_fetch_in_flight_skip", 1)
		return
	end

	if getOrderedListBudget() < ORDERED_LIST_BUDGET_FLOOR then
		RateLimitTelemetry.Increment("leaderboard", "ordered_list_fetch_budget_skip", 1)
		scheduleNextFetch(cache, GLOBAL_FETCH_INTERVAL_SECONDS)
		return
	end

	cache.inFlight = true
	local entries, errorMessage = getOrderedStoreEntries(boardName, storeName, store)
	cache.inFlight = false

	if entries then
		if config.useDirtySync then
			entries = overlayLiveRollEntries(entries)
		end

		cache.entries = cloneEntries(entries)
		cache.lastSuccessfulFetchAt = os.clock()
		cache.lastError = nil
		RateLimitTelemetry.Increment("leaderboard", "ordered_list_fetch_success", 1)
	else
		cache.lastError = tostring(errorMessage)
	end

	scheduleNextFetch(cache, GLOBAL_FETCH_INTERVAL_SECONDS)
end

local function getCachedEntriesForBoard(dataService, boardName, config)
	local cache = getOrderedEntryCache(boardName)
	local entries = cloneEntries(cache.entries)
	if #entries == 0 then
		RateLimitTelemetry.Increment("leaderboard", "cache_render_fallback", 1)
		entries = getCurrentPlayerEntries(dataService, config.key)
	end

	if config.useDirtySync then
		return overlayLiveRollEntries(entries)
	end

	return entries
end

local function refreshOrderedEntryCaches(dataService)
	if not shouldUseOrderedStores() then
		return
	end

	for boardName, config in pairs(BOARD_CONFIGS) do
		local boardModels = getBoardModels(config)
		if #boardModels > 0 then
			local store = orderedStores[boardName]
			local storeName = orderedStoreNames[boardName]
			local cache = getOrderedEntryCache(boardName)
			if store and storeName and os.clock() >= cache.nextAllowedFetchAt then
				updateOrderedEntriesCache(dataService, boardName, config, storeName, store)
				task.wait(GLOBAL_FETCH_BOARD_SPACING_SECONDS)
			end
		end
	end
end

local function syncLegacyBoards(dataService, options)
	if not shouldUseOrderedStores() then
		return
	end

	for boardName, config in pairs(BOARD_CONFIGS) do
		if config.useDirtySync ~= true then
			local store = orderedStores[boardName]
			local storeName = orderedStoreNames[boardName]
			if store then
				pushChangedPlayerData(dataService, boardName, config, storeName, store, options)
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
				syncPlayerValueToStore(dataService, boardName, config, storeName, store, player, {
					force = true,
				})
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
				entries = getCachedEntriesForBoard(dataService, boardName, config)
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
		Logger.Warn("[Leaderboards] Missing global leaderboard models in Workspace.Map")
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
			scheduleInitialFetch(getOrderedEntryCache(boardName))
		end
	end

	syncLegacyBoards(dataService, {
		force = true,
	})
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
			refreshOrderedEntryCaches(dataService)
			task.wait(RENDER_REFRESH_TIME)
		end
	end)
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
