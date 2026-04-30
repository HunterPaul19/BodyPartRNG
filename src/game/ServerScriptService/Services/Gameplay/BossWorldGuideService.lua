local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BodyPartService = require(script.Parent.BodyPartService)
local DataService = require(script.Parent.DataService)
local PlayerLoadoutStatsService = require(script.Parent.PlayerLoadoutStatsService)
local TutorialAnalyticsService = require(script.Parent.TutorialAnalyticsService)
local BossWorldGuideState = require(ReplicatedStorage.Shared.Character.BossWorldGuideState)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)
local Schema = require(ReplicatedStorage.Lists.Schema)

local COMBAT_SCORE_THRESHOLD = 1000
local MAIN_PROFILE_ID = "main"
local BOSS_PROFILE_IDS = table.freeze({
	boss_lobby = true,
	boss_arena = true,
})
local BOSS_WORLD_GUIDE_KEY = Schema.BossWorldGuide and Schema.BossWorldGuide.key or nil
local TUTORIAL_KEY = Schema.Tutorial and Schema.Tutorial.key or nil

local BossWorldGuideService = {
	_started = false,
	_loadoutConnection = nil :: RBXScriptConnection?,
	_dataLoadedConnection = nil :: RBXScriptConnection?,
	_dataChangedConnection = nil :: RBXScriptConnection?,
}

local function getActiveProfileId(): string
	return PlaceProfile.GetActiveProfile().id
end

local function isBossWorldProfile(): boolean
	return BOSS_PROFILE_IDS[getActiveProfileId()] == true
end

local function getState(player: Player): BossWorldGuideState.BossWorldGuideStateValue
	if not BOSS_WORLD_GUIDE_KEY then
		return BossWorldGuideState.CreateEmptyState()
	end

	return BossWorldGuideState.Normalize(DataService:Get(player, BOSS_WORLD_GUIDE_KEY))
end

local function setState(player: Player, state: BossWorldGuideState.BossWorldGuideStateValue)
	if not BOSS_WORLD_GUIDE_KEY then
		return
	end

	DataService:Set(player, BOSS_WORLD_GUIDE_KEY, BossWorldGuideState.Normalize(state))
end

local function hasCompletedTutorial(player: Player): boolean
	return DataService:GetTutorialState(player).completed == true
end

function BossWorldGuideService:_markPrompted(player: Player)
	if player.Parent ~= Players or not BOSS_WORLD_GUIDE_KEY then
		return
	end

	local state = getState(player)
	if state.completed == true or state.prompted == true then
		return
	end

	state.prompted = true
	state.promptedAtUnix = os.time()
	setState(player, state)
	TutorialAnalyticsService:LogBossWorldGuidePrompted(player)
end

function BossWorldGuideService:MarkBossWorldEntered(player: Player)
	if player.Parent ~= Players or not BOSS_WORLD_GUIDE_KEY then
		return
	end

	local state = getState(player)
	if state.completed == true or state.prompted ~= true then
		return
	end

	state.completed = true
	state.completedAtUnix = os.time()
	setState(player, state)
	TutorialAnalyticsService:LogBossWorldGuideCompleted(player)
end

function BossWorldGuideService:ShouldRouteToBossTutorial(player: Player): boolean
	if player.Parent ~= Players or not BOSS_WORLD_GUIDE_KEY then
		return false
	end

	local state = getState(player)
	return state.prompted == true and state.completed ~= true and state.tutorialArenaEntered ~= true
end

function BossWorldGuideService:MarkBossTutorialArenaEntered(player: Player)
	if player.Parent ~= Players or not BOSS_WORLD_GUIDE_KEY then
		return
	end

	local state = getState(player)
	if state.tutorialArenaEntered == true and state.completed == true then
		return
	end

	local now = os.time()
	state.prompted = true
	state.completed = true
	state.tutorialArenaEntered = true
	if state.promptedAtUnix <= 0 then
		state.promptedAtUnix = now
	end
	state.completedAtUnix = now
	state.tutorialArenaEnteredAtUnix = now
	setState(player, state)
	TutorialAnalyticsService:LogBossWorldGuideCompleted(player)
end

function BossWorldGuideService:ArmBossTutorialForAdmin(player: Player): (boolean, string?)
	if player.Parent ~= Players or not BOSS_WORLD_GUIDE_KEY then
		return false, "Boss world guide state is unavailable."
	end
	if DataService:IsPlayerDataLoaded(player) ~= true then
		return false, "Player data is not loaded yet."
	end

	local state = getState(player)
	state.prompted = true
	state.completed = false
	state.tutorialArenaEntered = false
	state.promptedAtUnix = os.time()
	state.completedAtUnix = 0
	state.tutorialArenaEnteredAtUnix = 0
	setState(player, state)

	return true, nil
end

function BossWorldGuideService:_evaluatePlayer(player: Player)
	if player.Parent ~= Players or not BOSS_WORLD_GUIDE_KEY then
		return
	end
	if DataService:IsPlayerDataLoaded(player) ~= true then
		return
	end

	if isBossWorldProfile() then
		self:MarkBossWorldEntered(player)
		return
	end
	if getActiveProfileId() ~= MAIN_PROFILE_ID then
		return
	end
	if not hasCompletedTutorial(player) then
		return
	end

	local state = getState(player)
	if state.completed == true or state.prompted == true then
		return
	end

	local ok, combatScore = pcall(function()
		return PlayerLoadoutStatsService:GetCombatScore(player)
	end)
	if not ok or (tonumber(combatScore) or 0) <= COMBAT_SCORE_THRESHOLD then
		return
	end

	self:_markPrompted(player)
end

function BossWorldGuideService:_scheduleEvaluate(player: Player)
	task.defer(function()
		self:_evaluatePlayer(player)
	end)
end

function BossWorldGuideService:OnStart()
	if self._started then
		return
	end

	self._started = true
	if not BOSS_WORLD_GUIDE_KEY then
		return
	end

	self._loadoutConnection = BodyPartService.LoadoutChanged:Connect(function(player: Player)
		self:_scheduleEvaluate(player)
	end)
	self._dataLoadedConnection = DataService.PlayerDataLoaded:Connect(function(player: Player)
		self:_scheduleEvaluate(player)
	end)
	self._dataChangedConnection = DataService.DataChanged:Connect(function(player: Player, key: string)
		if key == TUTORIAL_KEY then
			self:_scheduleEvaluate(player)
		end
	end)
end

function BossWorldGuideService:OnPlayerAdded(player: Player)
	self:_scheduleEvaluate(player)
end

return BossWorldGuideService
