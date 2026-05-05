local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Schema = require(ReplicatedStorage.Lists.Schema)
local PlayerStatsPresentation = require(ReplicatedStorage.Shared.UI.PlayerStatsPresentation)
local RemoteFunctionTimeout = require(ReplicatedStorage.Shared.Remotes.RemoteFunctionTimeout)
local DataController = require(script.Parent.DataController)

local ROLLS_KEY = Schema.SuccessfulRollCount and Schema.SuccessfulRollCount.key or nil
local TIME_PLAYED_KEY = Schema.TimePlayed and Schema.TimePlayed.key or nil
local STATS_KEY = Schema.Stats and Schema.Stats.key or nil

local BOARD_NAME = "PlayerStats"
local REMOTE_WAIT_TIMEOUT_SECONDS = 10
local ROLLING_STATE_INVOKE_TIMEOUT_SECONDS = 5

local STAT_KEYS_BY_PREFIX = {
	["Rolls"] = "rolls",
	["Luck"] = "luck",
	["Play Time"] = "playTime",
	["Rarest RNG"] = "rarestRng",
	["Rarest Part"] = "rarestPart",
	["Session Time"] = "sessionTime",
}

local PlayerStatsBoardController = {}

local function getTextPrefix(text: string): string?
	local prefix = string.match(tostring(text or ""), "^%s*([^:]+):")
	if prefix == nil then
		return nil
	end

	return string.match(prefix, "^%s*(.-)%s*$")
end

local function setStatLabel(label: TextLabel?, prefix: string, valueText: string)
	if not (label and label.Parent) then
		return
	end

	label.Text = string.format("%s: %s", prefix, valueText)
end

local function findPlayerStatsScrollingFrame(): ScrollingFrame?
	local board = Workspace:FindFirstChild(BOARD_NAME)
	local scoreBlock = board and board:FindFirstChild("ScoreBlock")
	local surfaceGui = scoreBlock and scoreBlock:FindFirstChild("SurfaceGui")
	local leaderboard = surfaceGui and surfaceGui:FindFirstChild("Leaderboard")
	local inner = leaderboard and leaderboard:FindFirstChild("Inner")
	local scrollingFrame = inner and inner:FindFirstChild("ScrollingFrame")

	if scrollingFrame and scrollingFrame:IsA("ScrollingFrame") then
		return scrollingFrame
	end

	return nil
end

local function getBestEver(statsState: any): any
	if typeof(statsState) ~= "table" then
		return nil
	end

	local rolls = statsState.rolls
	if typeof(rolls) ~= "table" then
		return nil
	end

	return rolls.bestEver
end

function PlayerStatsBoardController:_ensureState()
	if self._started then
		return
	end

	self._started = true
	self._sessionStartedAt = os.clock()
	self._timePlayedBaseSeconds = 0
	self._timePlayedBaseClock = os.clock()
	self._effectiveLuck = 1
	self._statLabels = {}
	self._statPrefixes = {}
	self._connections = {}
end

function PlayerStatsBoardController:_cacheBoard()
	local scrollingFrame = findPlayerStatsScrollingFrame()
	if not scrollingFrame then
		return false
	end

	local labelsByKey = {}
	local prefixesByKey = {}
	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if not child:IsA("TextLabel") then
			continue
		end

		local prefix = getTextPrefix(child.Text)
		local statKey = if prefix then STAT_KEYS_BY_PREFIX[prefix] else nil
		if statKey and labelsByKey[statKey] == nil then
			labelsByKey[statKey] = child
			prefixesByKey[statKey] = prefix
		end
	end

	self._statLabels = labelsByKey
	self._statPrefixes = prefixesByKey
	return true
end

function PlayerStatsBoardController:_syncTimePlayedBase()
	local timePlayed = if TIME_PLAYED_KEY then tonumber(DataController:Get(TIME_PLAYED_KEY)) else nil
	self._timePlayedBaseSeconds = math.max(0, math.floor(timePlayed or 0))
	self._timePlayedBaseClock = os.clock()
end

function PlayerStatsBoardController:_getSmoothedTimePlayed(): number
	local baseSeconds = math.max(0, tonumber(self._timePlayedBaseSeconds) or 0)
	local baseClock = tonumber(self._timePlayedBaseClock) or os.clock()
	return baseSeconds + math.max(0, os.clock() - baseClock)
end

function PlayerStatsBoardController:_getStatsState(): any
	return if STATS_KEY then DataController:Get(STATS_KEY) else nil
end

function PlayerStatsBoardController:_render()
	if not self._statLabels or next(self._statLabels) == nil then
		if not self:_cacheBoard() then
			return
		end
	end

	local labels = self._statLabels
	local prefixes = self._statPrefixes
	local statsState = self:_getStatsState()
	local bestEver = getBestEver(statsState)
	local rollCount = if ROLLS_KEY then DataController:Get(ROLLS_KEY) else 0

	setStatLabel(labels.rolls, prefixes.rolls or "Rolls", PlayerStatsPresentation.FormatBoardWholeNumber(rollCount))
	setStatLabel(labels.luck, prefixes.luck or "Luck", PlayerStatsPresentation.FormatBoardLuckMultiplier(self._effectiveLuck))
	setStatLabel(
		labels.playTime,
		prefixes.playTime or "Play Time",
		PlayerStatsPresentation.FormatBoardClockDuration(self:_getSmoothedTimePlayed())
	)
	setStatLabel(
		labels.rarestRng,
		prefixes.rarestRng or "Rarest RNG",
		PlayerStatsPresentation.FormatBoardRarestRng(bestEver)
	)
	setStatLabel(
		labels.rarestPart,
		prefixes.rarestPart or "Rarest Part",
		PlayerStatsPresentation.FormatBoardRarestPart(bestEver)
	)
	setStatLabel(
		labels.sessionTime,
		prefixes.sessionTime or "Session Time",
		PlayerStatsPresentation.FormatBoardClockDuration(os.clock() - self._sessionStartedAt)
	)
end

function PlayerStatsBoardController:_applyRollingState(state: any)
	if typeof(state) ~= "table" then
		return
	end

	local luckValue = tonumber(state.totalLuck) or tonumber(state.rawLuck)
	if luckValue == nil then
		return
	end

	self._effectiveLuck = math.max(0, luckValue)
	self:_render()
end

function PlayerStatsBoardController:_loadRollingState(getRollingStateRemote: RemoteFunction)
	local ok, result = RemoteFunctionTimeout.Invoke(getRollingStateRemote, nil, ROLLING_STATE_INVOKE_TIMEOUT_SECONDS)
	if not ok then
		return
	end

	if typeof(result) == "table" and result.ok == true and typeof(result.state) == "table" then
		self:_applyRollingState(result.state)
	elseif typeof(result) == "table" then
		self:_applyRollingState(result)
	end
end

function PlayerStatsBoardController:_bindRollingState()
	task.spawn(function()
		local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", REMOTE_WAIT_TIMEOUT_SECONDS)
		if not remotesFolder then
			return
		end

		local rollingFolder = remotesFolder:WaitForChild("Rolling", REMOTE_WAIT_TIMEOUT_SECONDS)
		if not rollingFolder then
			return
		end

		local getRollingStateRemote = rollingFolder:WaitForChild("GetRollingState", REMOTE_WAIT_TIMEOUT_SECONDS)
		if getRollingStateRemote and getRollingStateRemote:IsA("RemoteFunction") then
			self:_loadRollingState(getRollingStateRemote)
		end

		local rollingUpdatedRemote = rollingFolder:WaitForChild("RollingUpdated", REMOTE_WAIT_TIMEOUT_SECONDS)
		if rollingUpdatedRemote and rollingUpdatedRemote:IsA("RemoteEvent") then
			table.insert(self._connections, rollingUpdatedRemote.OnClientEvent:Connect(function(state)
				self:_applyRollingState(state)
			end))
		end
	end)
end

function PlayerStatsBoardController:_bindData()
	self:_syncTimePlayedBase()

	table.insert(self._connections, DataController.DataReceived:Connect(function()
		self:_syncTimePlayedBase()
		self:_render()
	end))

	table.insert(self._connections, DataController.DataUpdated:Connect(function(key)
		if key == TIME_PLAYED_KEY then
			self:_syncTimePlayedBase()
		end

		if key == TIME_PLAYED_KEY or key == ROLLS_KEY or key == STATS_KEY then
			self:_render()
		end
	end))
end

function PlayerStatsBoardController:_startTicker()
	task.spawn(function()
		while self._started do
			self:_render()
			task.wait(1)
		end
	end)
end

function PlayerStatsBoardController:OnStart()
	self:_ensureState()
	self:_cacheBoard()
	self:_bindData()
	self:_bindRollingState()
	self:_startTicker()
	self:_render()

	task.delay(5, function()
		if not self._statLabels or next(self._statLabels) == nil then
			Logger.Warn("[PlayerStatsBoardController] Workspace.PlayerStats board UI was not found.")
		end
	end)
end

return PlayerStatsBoardController
