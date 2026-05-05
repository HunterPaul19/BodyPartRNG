local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
local TutorialState = require(ReplicatedStorage.Shared.Character.TutorialState)
local DataService = require(script.Parent.DataService)
local RequestLimiter = require(script.Parent.Common.RequestLimiter)
local TutorialAnalyticsService = require(script.Parent.TutorialAnalyticsService)

local REMOTES_FOLDER_NAME = "Remotes"
local TUTORIAL_FOLDER_NAME = "Tutorial"
local GET_STATE_REMOTE_NAME = "GetTutorialState"
local ADVANCE_REMOTE_NAME = "AdvanceTutorialStep"
local UPDATED_REMOTE_NAME = "TutorialUpdated"
local OBSOLETE_REMOTE_NAMES = table.freeze({
	"ClaimTutorialChest",
})

local TutorialService = {}

local remotesFolder: Folder? = nil
local tutorialFolder: Folder? = nil
local getStateRemote: RemoteFunction? = nil
local advanceRemote: RemoteFunction? = nil
local updatedRemote: RemoteEvent? = nil

local function createOrGetFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = parent
	return created
end

local function createOrGetRemoteFunction(parent: Instance, name: string): RemoteFunction
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local created = Instance.new("RemoteFunction")
	created.Name = name
	created.Parent = parent
	return created
end

local function createOrGetRemoteEvent(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local created = Instance.new("RemoteEvent")
	created.Name = name
	created.Parent = parent
	return created
end

local function removeObsoleteRemotes(parent: Instance)
	for _, remoteName in ipairs(OBSOLETE_REMOTE_NAMES) do
		local existing = parent:FindFirstChild(remoteName)
		if existing then
			existing:Destroy()
		end
	end
end

local function ensureTutorialFolder(): Folder
	if tutorialFolder and tutorialFolder.Parent then
		return tutorialFolder
	end

	remotesFolder = createOrGetFolder(ReplicatedStorage, REMOTES_FOLDER_NAME)
	tutorialFolder = createOrGetFolder(remotesFolder, TUTORIAL_FOLDER_NAME)
	return tutorialFolder
end

local function response(ok: boolean, message: string, state: any?, extra: any?)
	local result = {
		ok = ok,
		message = message,
		state = TutorialState.CloneState(state),
	}
	if typeof(extra) == "table" then
		for key, value in pairs(extra) do
			result[key] = value
		end
	end
	return result
end

local function isActive(player: Player): boolean
	return player.Parent == Players and DataService:IsPlayerDataLoaded(player)
end

local function getStepIndex(stepId: string): number
	return TutorialConfig.GetStepIndex(stepId)
end

local function getState(player: Player): TutorialState.TutorialStateValue
	return DataService:GetTutorialState(player)
end

local function setState(player: Player, state: any): TutorialState.TutorialStateValue
	local normalized = DataService:SetTutorialState(player, TutorialState.Normalize(state))
	if updatedRemote then
		updatedRemote:FireClient(player, TutorialState.CloneState(normalized))
	end
	return normalized
end

local function hasAnyEquippedBodyPart(player: Player): boolean
	local equippedState = DataService:GetEquippedLoadout(player)
	for _, entry in pairs(equippedState) do
		if typeof(entry) == "table" and typeof(entry.ownedId) == "string" and entry.ownedId ~= "" then
			return true
		end
	end
	return false
end

local function completeTutorial(player: Player, state: TutorialState.TutorialStateValue): TutorialState.TutorialStateValue
	if state.completed == true then
		return state
	end

	state.completed = true
	state.stepId = TutorialConfig.Steps.Completed
	state.adminReplay = false
	local completedState = setState(player, state)

	task.defer(function()
		if isActive(player) then
			local QuestService = require(script.Parent.QuestService)
			QuestService:BeginTutorialQuestline(player)
		end
	end)

	return completedState
end

local function advanceTo(player: Player, nextStepId: string): TutorialState.TutorialStateValue
	local state = getState(player)
	if state.completed == true then
		return state
	end

	local normalizedNextStepId = TutorialConfig.NormalizeStepId(nextStepId)
	if getStepIndex(normalizedNextStepId) <= getStepIndex(state.stepId) then
		return state
	end

	state.stepId = normalizedNextStepId
	if normalizedNextStepId == TutorialConfig.Steps.Completed then
		state.completed = true
		state.adminReplay = false
	end
	return setState(player, state)
end

function TutorialService:IsTutorialIncomplete(player: Player): boolean
	if not isActive(player) then
		return false
	end
	return getState(player).completed ~= true
end

function TutorialService:GetState(player: Player): TutorialState.TutorialStateValue
	if not isActive(player) then
		return TutorialState.CreateCompletedState()
	end

	self:RefreshProgress(player)
	return getState(player)
end

function TutorialService:RefreshProgress(player: Player): TutorialState.TutorialStateValue
	if not isActive(player) then
		return TutorialState.CreateCompletedState()
	end

	local state = getState(player)
	if state.completed == true then
		return state
	end
	if state.adminReplay == true then
		return state
	end

	local changed = true
	while changed do
		changed = false
		local stepId = state.stepId

		if (stepId == TutorialConfig.Steps.Welcome or stepId == TutorialConfig.Steps.RollFree)
			and DataService:GetSuccessfulRollCount(player) > 0
		then
			state.stepId = TutorialConfig.Steps.EquipBodyPart
			changed = true
		elseif stepId == TutorialConfig.Steps.EquipBodyPart and hasAnyEquippedBodyPart(player) then
			state.completed = true
			state.stepId = TutorialConfig.Steps.Completed
			state.adminReplay = false
			changed = true
		end
	end

	return setState(player, state)
end

function TutorialService:RecordRollResult(player: Player, result: any)
	if not isActive(player) or typeof(result) ~= "table" then
		return
	end

	local state = getState(player)
	if state.completed == true then
		return
	end

	if state.stepId == TutorialConfig.Steps.Welcome or state.stepId == TutorialConfig.Steps.RollFree then
		advanceTo(player, TutorialConfig.Steps.EquipBodyPart)
		TutorialAnalyticsService:LogOnboardingStep(player, 3, state)
	end
end

function TutorialService:RecordBodyPartEquipped(player: Player, _payload: any?)
	if not isActive(player) then
		return
	end

	local state = getState(player)
	if state.completed == true then
		return
	end

	local shouldComplete = state.stepId == TutorialConfig.Steps.EquipBodyPart
		or (
			state.adminReplay ~= true
			and (state.stepId == TutorialConfig.Steps.Welcome or state.stepId == TutorialConfig.Steps.RollFree)
			and DataService:GetSuccessfulRollCount(player) > 0
		)
	if shouldComplete then
		state.stepId = TutorialConfig.Steps.EquipBodyPart
		TutorialAnalyticsService:LogOnboardingStep(player, 4, state)
		completeTutorial(player, state)
	else
		self:RefreshProgress(player)
	end
end

function TutorialService:StartTutorialForAdmin(player: Player, stepId: string?): TutorialState.TutorialStateValue
	if not isActive(player) then
		return TutorialState.CreateCompletedState()
	end

	local state = TutorialState.CreateEmptyState()
	if TutorialConfig.IsLegacyCompletedStepId(stepId) then
		state = TutorialState.CreateCompletedState()
	else
		state.stepId = TutorialConfig.NormalizeStepId(stepId)
	end

	if state.stepId == TutorialConfig.Steps.Completed then
		state = TutorialState.CreateCompletedState()
	else
		state.completed = false
		state.adminReplay = true
	end
	return setState(player, state)
end

function TutorialService:AdvanceTutorialStep(player: Player, payload: any)
	if not isActive(player) then
		return response(false, "Player data is not loaded.", TutorialState.CreateCompletedState())
	end
	if not RequestLimiter:Allow(player, "remote.tutorial.advance") then
		return response(false, "You're advancing tutorial too quickly.", getState(player))
	end

	local requestedStepId = if typeof(payload) == "table" then payload.stepId else nil
	local state = self:RefreshProgress(player)
	if state.stepId == TutorialConfig.Steps.Welcome and requestedStepId == TutorialConfig.Steps.RollFree then
		state = advanceTo(player, TutorialConfig.Steps.RollFree)
		TutorialAnalyticsService:LogOnboardingStep(player, 2, state)
		return response(true, "Tutorial started.", state)
	end

	if typeof(requestedStepId) == "string" and TutorialConfig.GetStepIndex(requestedStepId) <= TutorialConfig.GetStepIndex(state.stepId) then
		return response(true, "Tutorial state refreshed.", state)
	end

	return response(true, "Tutorial state refreshed.", state)
end

function TutorialService:OnStart()
	local folder = ensureTutorialFolder()
	removeObsoleteRemotes(folder)
	getStateRemote = createOrGetRemoteFunction(folder, GET_STATE_REMOTE_NAME)
	advanceRemote = createOrGetRemoteFunction(folder, ADVANCE_REMOTE_NAME)
	updatedRemote = createOrGetRemoteEvent(folder, UPDATED_REMOTE_NAME)

	getStateRemote.OnServerInvoke = function(player: Player)
		if not RequestLimiter:Allow(player, "remote.tutorial.get_state") then
			return response(false, "You're refreshing tutorial too quickly.", getState(player))
		end

		return response(true, "Loaded tutorial state.", self:GetState(player))
	end

	advanceRemote.OnServerInvoke = function(player: Player, payload: any)
		return self:AdvanceTutorialStep(player, payload)
	end
end

function TutorialService:OnPlayerAdded(player: Player)
	if not isActive(player) then
		return
	end
	local state = getState(player)
	if state.completed ~= true then
		TutorialAnalyticsService:LogOnboardingStep(player, 1, state)
	end
	self:RefreshProgress(player)
end

return TutorialService
