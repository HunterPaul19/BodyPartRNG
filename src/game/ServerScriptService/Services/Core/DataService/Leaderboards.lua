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

local GLOBAL_FETCH_POLL_INTERVAL_SECONDS = 30
local GLOBAL_FETCH_INTERVAL_SECONDS = 3600
local GLOBAL_FETCH_JITTER_SECONDS = 120
local GLOBAL_FETCH_ENTRY_LIMIT = 100
local GLOBAL_FETCH_BOARD_SPACING_SECONDS = 5
local ORDERED_LIST_BUDGET_FLOOR = 3
local STARTUP_FETCH_RETRY_SECONDS = 30
local TIMER_UPDATE_INTERVAL_SECONDS = 1
local ROLLS_FLUSH_TIME = 60
local LEGACY_SYNC_REFRESH_TIME = 120
local MONEY_MIN_FLUSH_DELTA = 100
local ENTRY_NAME_PREFIX = "Entry_"
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
		modelPaths = { "RollsLeaderboard" },
		deprecatedModelPaths = { "Map.RollsLeaderboard" },
		rowValueLabelNames = { "Rolls", "Value", "Money" },
	},
	MoneyLeaderboard = {
		key = MONEY_KEY,
		format = "Money",
		minFlushIntervalSeconds = LEGACY_SYNC_REFRESH_TIME,
		minFlushDelta = MONEY_MIN_FLUSH_DELTA,
		modelPaths = { "MoneyLeaderboard" },
		deprecatedModelPaths = { "Map.MoneyLeaderboard" },
		rowValueLabelNames = { "Rolls", "Money", "Value" },
	},
	PlaytimeLeaderboard = {
		key = TIME_PLAYED_KEY,
		format = "Playtime",
		minFlushIntervalSeconds = LEGACY_SYNC_REFRESH_TIME,
		modelPaths = { "PlaytimeLeaderboard" },
		deprecatedModelPaths = { "Map.PlaytimeLeaderboard" },
		rowValueLabelNames = { "Playtime", "TimePlayed", "Time", "Rolls", "Value", "Money" },
	},
}

local usernameCache = {}
local usernameRequests = {}
local orderedStores = {}
local orderedStoreNames = {}
local orderedEntryCaches = {}
local boardRenderStates = setmetatable({}, { __mode = "k" })
local boardTimerLabels = setmetatable({}, { __mode = "k" })
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

local function getEntryDisplayName(entry)
	if typeof(entry) ~= "table" then
		return ""
	end

	if typeof(entry.name) == "string" and entry.name ~= "" then
		return entry.name
	end

	local userId = tonumber(entry.userId)
	if userId and usernameCache[userId] then
		return usernameCache[userId]
	end

	return if userId then "Player " .. tostring(userId) else ""
end

local function getSurfaceGui(boardModel)
	local fallbackSurfaceGui = nil

	for _, descendant in ipairs(boardModel:GetDescendants()) do
		if descendant:IsA("SurfaceGui") then
			fallbackSurfaceGui = fallbackSurfaceGui or descendant
			if descendant:FindFirstChild("Leaderboard") then
				return descendant
			end
		end
	end

	return fallbackSurfaceGui
end

local function getBoardTimerLabel(boardModel)
	local cachedLabel = boardTimerLabels[boardModel]
	if cachedLabel and cachedLabel.Parent and cachedLabel:IsA("TextLabel") then
		return cachedLabel
	end

	local timerPart = boardModel:FindFirstChild("UpdateBoardTimer")
	local timerGui = timerPart and timerPart:FindFirstChild("Timer")
	local label = timerGui and timerGui:FindFirstChild("TextLabel")
	if label and label:IsA("TextLabel") then
		boardTimerLabels[boardModel] = label
		return label
	end

	for _, descendant in ipairs(boardModel:GetDescendants()) do
		if descendant:IsA("TextLabel") and descendant.Parent and descendant.Parent.Name == "Timer" then
			boardTimerLabels[boardModel] = descendant
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
	local playerInfo = inner and inner:FindFirstChild("PlayerInfo")
	if not (leaderboardFrame and inner and scrollingFrame and template) then
		return nil
	end
	if not (scrollingFrame:IsA("ScrollingFrame") and template:IsA("GuiObject")) then
		return nil
	end

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
		templateSize = templateSize,
		listLayout = scrollingFrame:FindFirstChildWhichIsA("UIListLayout"),
		playerInfo = if playerInfo and playerInfo:IsA("GuiObject") then playerInfo else nil,
		rowRankLabelNames = { "LeaderboardPlace" },
		rowPlayerNameLabelNames = { "PlayerName" },
		rowValueLabelNames = config.rowValueLabelNames or { "Value" },
	}
end

local function disableBoardScripts(boardModel)
	for _, descendant in ipairs(boardModel:GetDescendants()) do
		if descendant:IsA("SurfaceGui") then
			for _, guiDescendant in ipairs(descendant:GetDescendants()) do
				if guiDescendant:IsA("Script") or guiDescendant:IsA("LocalScript") then
					guiDescendant.Disabled = true
				end
			end
		end
	end
end

local function disableDeprecatedBoardScripts()
	for _, config in pairs(BOARD_CONFIGS) do
		for _, path in ipairs(config.deprecatedModelPaths or {}) do
			local boardModel = resolveWorkspacePath(path)
			if boardModel then
				disableBoardScripts(boardModel)
			end
		end
	end
end

local function ensureScrollingFrameLayout(widgets)
	local scrollingFrame = widgets.scrollingFrame
	scrollingFrame.ScrollingEnabled = true
	scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollingFrame.ClipsDescendants = true

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

local function setGuiText(instance, text)
	if instance and instance:IsA("TextLabel") then
		if instance.Text ~= text then
			instance.Text = text
		end
	end
end

local function setGuiVisible(instance, visible)
	if not (instance and instance:IsA("GuiObject")) then
		return
	end

	if instance.Visible ~= visible then
		instance.Visible = visible
	end
	if instance:IsA("GuiButton") then
		instance.Active = visible
		instance.AutoButtonColor = false
	end
end

local function getBoardRenderState(boardModel)
	local state = boardRenderStates[boardModel]
	if not state then
		state = {
			rowsByRank = {},
			userIdsByRank = {},
			lastSignature = nil,
			renderedEntryCount = 0,
		}
		boardRenderStates[boardModel] = state
	end

	return state
end

local function buildEntriesSignature(entries)
	local entryCount = math.min(#entries, GLOBAL_FETCH_ENTRY_LIMIT)
	local parts = table.create(entryCount)
	for rank = 1, entryCount do
		local entry = entries[rank]
		parts[rank] = string.format(
			"%d:%d",
			math.floor(tonumber(entry and entry.userId) or 0),
			normalizeBoardValue(entry and entry.value)
		)
	end

	return table.concat(parts, "|")
end

local function updateRenderedEntryNames(userId, resolvedName)
	for _, state in pairs(boardRenderStates) do
		for rank, row in pairs(state.rowsByRank) do
			if state.userIdsByRank[rank] == userId and row and row.Parent then
				setGuiText(findFirstChildByNames(row, state.rowPlayerNameLabelNames or { "PlayerName" }), resolvedName)
			end
		end
	end
end

local function requestUsernameHydration(userId)
	userId = tonumber(userId)
	if not userId or usernameCache[userId] or usernameRequests[userId] then
		return
	end

	usernameRequests[userId] = true
	task.spawn(function()
		getUsernameForUserId(userId)
		usernameRequests[userId] = nil

		local resolvedName = usernameCache[userId]
		if not resolvedName then
			return
		end

		for _, cache in pairs(orderedEntryCaches) do
			for _, entry in ipairs(cache.entries or {}) do
				if tonumber(entry.userId) == userId then
					entry.name = resolvedName
				end
			end
		end

		updateRenderedEntryNames(userId, resolvedName)
	end)
end

local function getPooledBoardEntry(widgets, state, rank)
	local row = state.rowsByRank[rank]
	if row and row.Parent then
		return row
	end

	local rowName = ENTRY_NAME_PREFIX .. tostring(rank)
	local existingRow = widgets.scrollingFrame:FindFirstChild(rowName)
	if existingRow and existingRow:IsA("GuiObject") then
		row = existingRow
	else
		row = widgets.template:Clone()
		row.Name = rowName
		row.Parent = widgets.scrollingFrame
	end

	state.rowsByRank[rank] = row
	return row
end

local function updateBoardEntry(widgets, state, rank, entryData, formatName)
	local row = getPooledBoardEntry(widgets, state, rank)
	if row.LayoutOrder ~= rank then
		row.LayoutOrder = rank
	end
	if row.Size ~= widgets.templateSize then
		row.Size = widgets.templateSize
	end
	setGuiVisible(row, true)

	local userId = tonumber(entryData.userId)
	state.userIdsByRank[rank] = userId
	if userId then
		requestUsernameHydration(userId)
	end

	setGuiText(findFirstChildByNames(row, widgets.rowRankLabelNames), string.format("#%d", rank))
	setGuiText(findFirstChildByNames(row, widgets.rowPlayerNameLabelNames), getEntryDisplayName(entryData))
	setGuiText(findFirstChildByNames(row, widgets.rowValueLabelNames), formatValue(formatName, entryData.value))
end

local function renderBoard(boardModel, config, entries, signature, forceRender)
	local widgets = getBoardWidgets(boardModel, config)
	if not widgets then
		return false
	end

	local state = getBoardRenderState(boardModel)
	local boardSignature = signature or buildEntriesSignature(entries)
	if not forceRender and state.lastSignature == boardSignature then
		return false
	end

	disableBoardScripts(boardModel)
	ensureScrollingFrameLayout(widgets)

	widgets.template.Visible = false
	if widgets.template.Size ~= widgets.templateSize then
		widgets.template.Size = widgets.templateSize
	end
	if widgets.template.LayoutOrder ~= GLOBAL_FETCH_ENTRY_LIMIT + 2 then
		widgets.template.LayoutOrder = GLOBAL_FETCH_ENTRY_LIMIT + 2
	end
	setGuiVisible(widgets.playerInfo, false)

	local entryCount = math.min(#entries, GLOBAL_FETCH_ENTRY_LIMIT)
	state.rowPlayerNameLabelNames = widgets.rowPlayerNameLabelNames

	for rank = 1, entryCount do
		local entryData = entries[rank]
		if entryData then
			updateBoardEntry(widgets, state, rank, entryData, config.format)
		end
	end

	for rank, row in pairs(state.rowsByRank) do
		if rank > entryCount then
			setGuiVisible(row, false)
			state.userIdsByRank[rank] = nil
		end
	end

	state.lastSignature = boardSignature
	state.renderedEntryCount = entryCount
	return true
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
			lastFetchedSignature = nil,
			lastSuccessfulFetchAt = 0,
			nextAllowedFetchAt = 0,
			inFlight = false,
			lastError = nil,
			hasRenderedStartupFallback = false,
			hasRenderedSuccessfulFetch = false,
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

local function scheduleRetryFetch(cache, delaySeconds)
	cache.nextAllowedFetchAt = os.clock() + math.max(1, tonumber(delaySeconds) or STARTUP_FETCH_RETRY_SECONDS)
end

local function scheduleInitialFetch(cache)
	cache.nextAllowedFetchAt = os.clock()
end

local function getBoardRefreshCountdownSeconds(boardName)
	if not shouldUseOrderedStores() then
		return 0
	end

	local cache = orderedEntryCaches[boardName]
	if not cache then
		return 0
	end

	return math.max(0, math.ceil((tonumber(cache.nextAllowedFetchAt) or 0) - os.clock()))
end

local function updateBoardTimers()
	for boardName, config in pairs(BOARD_CONFIGS) do
		local text = string.format(
			"Updating the board in %d seconds!",
			getBoardRefreshCountdownSeconds(boardName)
		)
		for _, boardModel in ipairs(getBoardModels(config)) do
			setGuiText(getBoardTimerLabel(boardModel), text)
		end
	end
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

local function renderBoardEntries(config, entries, signature, forceRender)
	local boardModels = getBoardModels(config)
	if #boardModels == 0 then
		return
	end

	local boardSignature = signature or buildEntriesSignature(entries)
	for _, boardModel in ipairs(boardModels) do
		renderBoard(boardModel, config, entries, boardSignature, forceRender)
	end
end

local function updateOrderedEntriesCache(boardName, config, storeName, store, options)
	local cache = getOrderedEntryCache(boardName)
	local isStartupFetch = typeof(options) == "table" and options.startup == true
	local retryDelaySeconds = if typeof(options) == "table" then options.retryDelaySeconds else nil
	if cache.inFlight then
		RateLimitTelemetry.Increment("leaderboard", "ordered_list_fetch_in_flight_skip", 1)
		if isStartupFetch then
			Logger.Warn(string.format("[Leaderboards] Startup fetch skipped for board=%s because a fetch is already in flight.", boardName))
			scheduleRetryFetch(cache, retryDelaySeconds)
		end
		return false, 0
	end

	local orderedListBudget = getOrderedListBudget()
	if orderedListBudget < ORDERED_LIST_BUDGET_FLOOR then
		RateLimitTelemetry.Increment("leaderboard", "ordered_list_fetch_budget_skip", 1)
		if isStartupFetch then
			Logger.Warn(string.format(
				"[Leaderboards] Startup fetch skipped for board=%s because ordered read budget is %d.",
				boardName,
				orderedListBudget
			))
			scheduleRetryFetch(cache, retryDelaySeconds)
		else
			scheduleNextFetch(cache, GLOBAL_FETCH_INTERVAL_SECONDS)
		end
		return false, 0
	end

	cache.inFlight = true
	local entries, errorMessage = getOrderedStoreEntries(boardName, storeName, store)
	cache.inFlight = false

	if entries then
		if config.useDirtySync then
			entries = overlayLiveRollEntries(entries)
		end

		local signature = buildEntriesSignature(entries)
		local shouldRender = signature ~= cache.lastFetchedSignature or not cache.hasRenderedSuccessfulFetch
		cache.entries = cloneEntries(entries)
		cache.lastFetchedSignature = signature
		cache.lastSuccessfulFetchAt = os.clock()
		cache.lastError = nil
		cache.hasRenderedSuccessfulFetch = true
		RateLimitTelemetry.Increment("leaderboard", "ordered_list_fetch_success", 1)
		if shouldRender then
			renderBoardEntries(config, cache.entries, signature)
		end
		scheduleNextFetch(cache, GLOBAL_FETCH_INTERVAL_SECONDS)
		return true, #cache.entries
	else
		cache.lastError = tostring(errorMessage)
		if isStartupFetch then
			scheduleRetryFetch(cache, retryDelaySeconds)
		else
			scheduleNextFetch(cache, GLOBAL_FETCH_INTERVAL_SECONDS)
		end
		return false, 0
	end
end

local function renderStartupFallback(dataService, boardName, config)
	local cache = getOrderedEntryCache(boardName)
	if cache.hasRenderedStartupFallback then
		return
	end

	local fallbackEntries = getCurrentPlayerEntries(dataService, config.key)
	if #fallbackEntries == 0 then
		return
	end

	cache.hasRenderedStartupFallback = true
	renderBoardEntries(
		config,
		fallbackEntries,
		"startup-fallback:" .. boardName .. ":" .. buildEntriesSignature(fallbackEntries),
		true
	)
end

local function fetchStartupOrderedEntries(dataService)
	if not shouldUseOrderedStores() then
		return
	end

	for boardName, config in pairs(BOARD_CONFIGS) do
		local boardModels = getBoardModels(config)
		if #boardModels > 0 then
			local store = orderedStores[boardName]
			local storeName = orderedStoreNames[boardName]
			if store and storeName then
				local fetched, entryCount = updateOrderedEntriesCache(boardName, config, storeName, store, {
					retryDelaySeconds = STARTUP_FETCH_RETRY_SECONDS,
					startup = true,
				})
				if not fetched or entryCount <= 0 then
					renderStartupFallback(dataService, boardName, config)
				end
				task.wait(GLOBAL_FETCH_BOARD_SPACING_SECONDS)
			else
				renderStartupFallback(dataService, boardName, config)
			end
		end
	end
end

local function refreshOrderedEntryCaches()
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
				updateOrderedEntriesCache(boardName, config, storeName, store)
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

function Leaderboards.refresh(dataService, options)
	local forceRender = typeof(options) == "table" and options.force == true

	for boardName, config in pairs(BOARD_CONFIGS) do
		local boardModels = getBoardModels(config)
		if #boardModels > 0 then
			if shouldUseOrderedStores() then
				local cache = getOrderedEntryCache(boardName)
				if cache.lastSuccessfulFetchAt > 0 then
					if forceRender then
						renderBoardEntries(config, cloneEntries(cache.entries), cache.lastFetchedSignature, true)
					elseif #cache.entries == 0 then
						renderStartupFallback(dataService, boardName, config)
					end
				elseif not cache.hasRenderedStartupFallback then
					local fallbackEntries = getCurrentPlayerEntries(dataService, config.key)
					if #fallbackEntries > 0 or forceRender then
						cache.hasRenderedStartupFallback = true
						renderBoardEntries(
							config,
							fallbackEntries,
							"fallback:" .. buildEntriesSignature(fallbackEntries),
							forceRender
						)
					end
				end
			else
				local entries = getCurrentPlayerEntries(dataService, config.key)
				renderBoardEntries(config, entries, buildEntriesSignature(entries), forceRender)
			end
		end
	end
end

function Leaderboards.start(dataService)
	disableDeprecatedBoardScripts()

	local foundAnyBoard = false
	for _, config in pairs(BOARD_CONFIGS) do
		if #getBoardModels(config) > 0 then
			foundAnyBoard = true
			break
		end
	end

	if not foundAnyBoard then
		Logger.Warn("[Leaderboards] Missing global leaderboard models in Workspace")
		return
	end

	if started then
		Leaderboards.refresh(dataService, {
			force = true,
		})
		updateBoardTimers()
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
	updateBoardTimers()

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

	if shouldUseOrderedStores() then
		fetchStartupOrderedEntries(dataService)
	else
		Leaderboards.refresh(dataService)
	end
	updateBoardTimers()

	task.spawn(function()
		while true do
			refreshOrderedEntryCaches()
			task.wait(GLOBAL_FETCH_POLL_INTERVAL_SECONDS)
		end
	end)
	task.spawn(function()
		while true do
			updateBoardTimers()
			task.wait(TIMER_UPDATE_INTERVAL_SECONDS)
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
