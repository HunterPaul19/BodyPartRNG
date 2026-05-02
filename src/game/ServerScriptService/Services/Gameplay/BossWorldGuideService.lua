local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.DataService)
local QuestService = require(script.Parent.QuestService)
local TutorialAnalyticsService = require(script.Parent.TutorialAnalyticsService)
local BossWorldGuideState = require(ReplicatedStorage.Shared.Character.BossWorldGuideState)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)
local Schema = require(ReplicatedStorage.Lists.Schema)

local MAIN_PROFILE_ID = "main"
local BOSS_PROFILE_IDS = table.freeze({
	boss_lobby = true,
	boss_arena = true,
})
local BOSS_WORLD_GUIDE_KEY = Schema.BossWorldGuide and Schema.BossWorldGuide.key or nil
local STAN_BOSS_INTRO_QUEST_ID = "stan_boss_intro"

local BossWorldGuideService = {
	_started = false,
	_dataLoadedConnection = nil :: RBXScriptConnection?,
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

local function isStanBossIntroActive(player: Player): boolean
	if DataService:IsPlayerDataLoaded(player) ~= true then
		return false
	end

	local questState = DataService:GetQuestState(player)
	local activeByQuestId = questState.activeByQuestId
	local activeQuest = activeByQuestId[STAN_BOSS_INTRO_QUEST_ID]
	return typeof(activeQuest) == "table" and activeQuest.status == "active"
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
	if player.Parent ~= Players then
		return false
	end

	return isStanBossIntroActive(player)
end

function BossWorldGuideService:RecordBossWorldEntered(player: Player, payload: any?)
	if player.Parent ~= Players then
		return false
	end

	return QuestService:RecordEvent(player, "boss_world_entered", payload)
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

	self._dataLoadedConnection = DataService.PlayerDataLoaded:Connect(function(player: Player)
		self:_scheduleEvaluate(player)
	end)
end

function BossWorldGuideService:OnPlayerAdded(player: Player)
	self:_scheduleEvaluate(player)
end

return BossWorldGuideService
