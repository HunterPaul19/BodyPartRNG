local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Globals = require(ReplicatedStorage.Lists.Globals)
local Schema = require(ReplicatedStorage.Lists.Schema)

local REFRESH_TIME = 30
local MAX_FETCH_ENTRIES = 1000
local ORDERED_STORE_PAGE_SIZE = 100
local DEFAULT_VISIBLE_ENTRY_COUNT = 10
local ENTRY_NAME_PREFIX = "Entry_"
local SPACER_NAME_PREFIX = "Spacer_"
local SCOPE = Globals.SCOPE

local MONEY_KEY = Schema.Money and Schema.Money.key or "money"
local ROLLS_KEY = Schema.SuccessfulRollCount and Schema.SuccessfulRollCount.key or "successfulRollCount"

local BOARD_CONFIGS = {
	RollsLeaderboard = {
		key = ROLLS_KEY,
		format = "Rolls",
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
local lastSyncedValues = {}
local started = false

local function formatMoney(value)
	return Globals.formatNumber(math.max(0, math.floor((tonumber(value) or 0) + 0.5)), false, true)
end

local function formatRolls(value)
	return tostring(math.max(0, math.floor(tonumber(value) or 0)))
end

local FORMATTERS = {
	Money = formatMoney,
	Rolls = formatRolls,
}

local function formatValue(formatName, value)
	local formatter = FORMATTERS[formatName] or tostring
	return formatter(value)
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

	return {
		surfaceGui = surfaceGui,
		scrollingFrame = scrollingFrame,
		template = template,
		templateAbsoluteHeight = template.AbsoluteSize.Y,
		templateSize = template.Size,
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
	widgets.template.Size = UDim2.new(widgets.templateSize.X.Scale, widgets.templateSize.X.Offset, 0, 0)
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

	table.sort(entries, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.userId < b.userId
	end)

	while #entries > MAX_FETCH_ENTRIES do
		table.remove(entries)
	end

	return entries
end

local function syncPlayerValueToStore(dataService, boardName, config, store, player)
	local userId = player.UserId
	local boardValues = lastSyncedValues[boardName]
	if not boardValues then
		boardValues = {}
		lastSyncedValues[boardName] = boardValues
	end

	local value = math.max(0, math.floor(tonumber(dataService:Get(player, config.key)) or 0))
	if boardValues[userId] == value then
		return
	end

	local success = pcall(function()
		store:SetAsync(userId, value)
	end)
	if success then
		boardValues[userId] = value
	end
end

local function pushChangedPlayerData(dataService, boardName, config, store)
	for _, player in ipairs(Players:GetPlayers()) do
		syncPlayerValueToStore(dataService, boardName, config, store, player)
	end
end

local function getOrderedStoreEntries(store)
	local pageSize = math.min(ORDERED_STORE_PAGE_SIZE, MAX_FETCH_ENTRIES)
	local success, pages = pcall(function()
		return store:GetSortedAsync(false, pageSize)
	end)
	if not success or not pages then
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

		local advanced = pcall(function()
			pages:AdvanceToNextPageAsync()
		end)
		if not advanced then
			break
		end
	end

	return entries
end

local Leaderboards = {}

function Leaderboards.flushPlayer(dataService, player)
	if RunService:IsStudio() then
		return
	end

	for boardName, config in pairs(BOARD_CONFIGS) do
		local store = orderedStores[boardName]
		if store then
			syncPlayerValueToStore(dataService, boardName, config, store, player)
		end
	end
end

function Leaderboards.refresh(dataService)
	for boardName, config in pairs(BOARD_CONFIGS) do
		local boardModels = getBoardModels(config)
		if #boardModels > 0 then
			local entries = nil
			if RunService:IsStudio() then
				entries = getCurrentPlayerEntries(dataService, config.key)
			else
				local store = orderedStores[boardName]
				if store then
					pushChangedPlayerData(dataService, boardName, config, store)
					entries = getOrderedStoreEntries(store)
				else
					entries = {}
				end
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

	if not RunService:IsStudio() then
		for boardName, config in pairs(BOARD_CONFIGS) do
			orderedStores[boardName] = DataStoreService:GetOrderedDataStore(config.key .. SCOPE)
		end
	end

	Leaderboards.refresh(dataService)
	task.spawn(function()
		while true do
			Leaderboards.refresh(dataService)
			task.wait(REFRESH_TIME)
		end
	end)
end

return Leaderboards
