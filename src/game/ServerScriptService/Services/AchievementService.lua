local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Schema = require(ReplicatedStorage.Lists.Schema)
local Notify = require(ReplicatedStorage.Shared.UI.Notify)
local BodyPartCollection = require(ReplicatedStorage.Shared.Character.BodyPartCollection)
local AchievementConfig = require(ReplicatedStorage.Shared.Config.AchievementConfig)
local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)
local AchievementState = require(ReplicatedStorage.Shared.Titles.AchievementState)
local DataService = require(script.Parent.DataService)

local ACHIEVEMENTS_KEY = Schema.Achievements and Schema.Achievements.key or "achievements"
local TRIGGERS: { [string]: { AchievementConfig.AchievementConfigEntry } } = {}
local initializedPlayers: { [Player]: boolean } = {}

for _, achievement in ipairs(AchievementConfig.GetOrdered()) do
	TRIGGERS[achievement.triggerType] = TRIGGERS[achievement.triggerType] or {}
	table.insert(TRIGGERS[achievement.triggerType], achievement)
end

local function cloneBooleanMap(value: any): { [string]: boolean }
	local copy = {}
	if typeof(value) ~= "table" then
		return copy
	end

	for key, child in pairs(value) do
		if child == true and typeof(key) == "string" and key ~= "" then
			copy[key] = true
		end
	end

	return copy
end

local function getCompletedSetIds(bodyPartsState: any): { [string]: boolean }
	local completedSetIds = {}
	for _, summary in ipairs(BodyPartCollection.GetAllSetSummaries(bodyPartsState)) do
		if summary.ownsFullSet then
			completedSetIds[summary.setId] = true
		end
	end

	return completedSetIds
end

local function appendUnlock(unlockedAchievementIds: { string }, state: AchievementState.AchievementsState, achievementId: string)
	if state.completedIds[achievementId] == true then
		return
	end

	state.completedIds[achievementId] = true
	table.insert(unlockedAchievementIds, achievementId)
end

local function notifyUnlocks(player: Player, unlockedAchievementIds: { string })
	for _, achievementId in ipairs(unlockedAchievementIds) do
		local title = TitleConfig.GetByAchievementId(achievementId)
		if title then
			Notify.Send(player, string.format('Unlocked title "%s".', title.label), {
				title = "Titles",
				duration = 5,
			})
		end
	end
end

local function waitForPlayerData(player: Player, timeoutSeconds: number?): boolean
	local timeoutAt = os.clock() + (timeoutSeconds or 20)

	while os.clock() < timeoutAt do
		if player.Parent ~= Players then
			return false
		end

		if DataService:Get(player) ~= nil then
			return true
		end

		task.wait(0.25)
	end

	return false
end

local AchievementService = {}

function AchievementService:_seedPlayerProgress(player: Player)
	if initializedPlayers[player] then
		return true
	end
	if not waitForPlayerData(player, 20) then
		return false
	end

	local currentState = DataService:GetAchievementsState(player)
	if currentState.initialized then
		initializedPlayers[player] = true
		return true
	end

	local bodyPartsState = DataService:GetBodyPartsState(player)
	local seededState = AchievementState.Normalize(currentState)
	seededState.initialized = true
	seededState.completedIds = cloneBooleanMap(seededState.completedIds)
	seededState.rollsSinceInit = 0
	seededState.playTimeSinceInit = 0
	seededState.seenDiscoveredPieceIds = cloneBooleanMap(bodyPartsState.discoveredPieceIds)
	seededState.seenCompletedSetIds = getCompletedSetIds(bodyPartsState)
	seededState.newDiscoveredCountSinceInit = 0
	seededState.newCompletedSetCountSinceInit = 0

	DataService:Set(player, ACHIEVEMENTS_KEY, seededState)
	initializedPlayers[player] = true
	return true
end

function AchievementService:_handleRollIncremented(player: Player)
	if not self:_seedPlayerProgress(player) then
		return
	end

	local unlockedAchievementIds = {}
	DataService:Set(player, ACHIEVEMENTS_KEY, function(currentValue)
		local state = AchievementState.Normalize(currentValue)
		if not state.initialized then
			return state
		end

		state.rollsSinceInit += 1
		for _, achievement in ipairs(TRIGGERS.successful_rolls or {}) do
			if state.rollsSinceInit >= achievement.targetValue then
				appendUnlock(unlockedAchievementIds, state, achievement.id)
			end
		end

		return state
	end)

	notifyUnlocks(player, unlockedAchievementIds)
end

function AchievementService:_handleMoneyChanged(player: Player, previousValue: number, newValue: number)
	if newValue <= previousValue then
		return
	end
	if not self:_seedPlayerProgress(player) then
		return
	end

	local unlockedAchievementIds = {}
	DataService:Set(player, ACHIEVEMENTS_KEY, function(currentValue)
		local state = AchievementState.Normalize(currentValue)
		if not state.initialized then
			return state
		end

		for _, achievement in ipairs(TRIGGERS.current_money or {}) do
			if previousValue < achievement.targetValue and newValue >= achievement.targetValue then
				appendUnlock(unlockedAchievementIds, state, achievement.id)
			end
		end

		return state
	end)

	notifyUnlocks(player, unlockedAchievementIds)
end

function AchievementService:_handleTimePlayedFlushed(player: Player, deltaSeconds: number)
	if deltaSeconds <= 0 then
		return
	end
	if not self:_seedPlayerProgress(player) then
		return
	end

	local unlockedAchievementIds = {}
	DataService:Set(player, ACHIEVEMENTS_KEY, function(currentValue)
		local state = AchievementState.Normalize(currentValue)
		if not state.initialized then
			return state
		end

		state.playTimeSinceInit += deltaSeconds
		for _, achievement in ipairs(TRIGGERS.play_time_seconds or {}) do
			if state.playTimeSinceInit >= achievement.targetValue then
				appendUnlock(unlockedAchievementIds, state, achievement.id)
			end
		end

		return state
	end)

	notifyUnlocks(player, unlockedAchievementIds)
end

function AchievementService:_handleOwnedBodyPartAdded(player: Player, _record: any, bodyPartsState: any)
	if not self:_seedPlayerProgress(player) then
		return
	end

	local unlockedAchievementIds = {}
	DataService:Set(player, ACHIEVEMENTS_KEY, function(currentValue)
		local state = AchievementState.Normalize(currentValue)
		if not state.initialized then
			return state
		end

		for pieceId, isDiscovered in pairs(bodyPartsState.discoveredPieceIds or {}) do
			if isDiscovered == true and state.seenDiscoveredPieceIds[pieceId] ~= true then
				state.seenDiscoveredPieceIds[pieceId] = true
				state.newDiscoveredCountSinceInit += 1
			end
		end

		for setId in pairs(getCompletedSetIds(bodyPartsState)) do
			if state.seenCompletedSetIds[setId] ~= true then
				state.seenCompletedSetIds[setId] = true
				state.newCompletedSetCountSinceInit += 1
			end
		end

		for _, achievement in ipairs(TRIGGERS.new_discovered_pieces or {}) do
			if state.newDiscoveredCountSinceInit >= achievement.targetValue then
				appendUnlock(unlockedAchievementIds, state, achievement.id)
			end
		end

		for _, achievement in ipairs(TRIGGERS.new_completed_sets or {}) do
			if state.newCompletedSetCountSinceInit >= achievement.targetValue then
				appendUnlock(unlockedAchievementIds, state, achievement.id)
			end
		end

		return state
	end)

	notifyUnlocks(player, unlockedAchievementIds)
end

function AchievementService:OnStart()
	DataService.PlayerDataLoaded:Connect(function(player: Player)
		self:_seedPlayerProgress(player)
	end)

	DataService.SuccessfulRollIncremented:Connect(function(player: Player)
		self:_handleRollIncremented(player)
	end)

	DataService.MoneyChanged:Connect(function(player: Player, previousValue: number, newValue: number)
		self:_handleMoneyChanged(player, previousValue, newValue)
	end)

	DataService.TimePlayedFlushed:Connect(function(player: Player, deltaSeconds: number)
		self:_handleTimePlayedFlushed(player, deltaSeconds)
	end)

	DataService.OwnedBodyPartAdded:Connect(function(player: Player, record: any, bodyPartsState: any)
		self:_handleOwnedBodyPartAdded(player, record, bodyPartsState)
	end)
end

function AchievementService:OnPlayerAdded(player: Player)
	task.defer(function()
		self:_seedPlayerProgress(player)
	end)
end

function AchievementService:OnPlayerRemoving(player: Player)
	initializedPlayers[player] = nil
end

return AchievementService
