local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DefinitionUtil = require(ReplicatedStorage.Shared.Gameplay.Dialogue.DefinitionUtil)
local Registry = require(ReplicatedStorage.Shared.Gameplay.Dialogue.Registry)
local Schema = require(ReplicatedStorage.Lists.Schema)

local DataService = require(script.Parent.DataService)
local QuestService = require(script.Parent.QuestService)
local RequestLimiter = require(script.Parent.Common.RequestLimiter)

local REMOTES_FOLDER_NAME = "Remotes"
local DIALOGUE_FOLDER_NAME = "Dialogue"
local RUN_ACTION_REMOTE_NAME = "RunAction"
local VIP_OWNED_KEY = Schema.VipOwned and Schema.VipOwned.key or nil
local STAN_PAID_ROLL_INTRO_QUEST_ID = "stan_paid_roll_intro"
local STAN_APPRAISAL_INTRO_QUEST_ID = "stan_appraisal_intro"
local STAN_CRAFTING_INTRO_QUEST_ID = "stan_crafting_intro"
local STAN_BOSS_INTRO_QUEST_ID = "stan_boss_intro"

local dialogueFolder: Folder? = nil
local runActionRemote: RemoteFunction? = nil

local DialogueActionService = {
	_started = false,
	_registered = false,
}

local function response(ok: boolean, message: string, data: any?)
	return {
		ok = ok,
		message = message,
		data = data,
	}
end

local function ensureRemotesFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = REMOTES_FOLDER_NAME
	folder.Parent = ReplicatedStorage
	return folder
end

local function ensureDialogueFolder(): Folder
	local rootFolder = ensureRemotesFolder()
	if dialogueFolder and dialogueFolder.Parent == rootFolder then
		return dialogueFolder
	end

	local existing = rootFolder:FindFirstChild(DIALOGUE_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		dialogueFolder = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = DIALOGUE_FOLDER_NAME
	folder.Parent = rootFolder
	dialogueFolder = folder
	return folder
end

local function ensureRemoteFunction(cachedRemote: RemoteFunction?, remoteName: string): RemoteFunction
	local folder = ensureDialogueFolder()
	if cachedRemote and cachedRemote.Parent == folder then
		return cachedRemote
	end

	local existing = folder:FindFirstChild(remoteName)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = remoteName
	remote.Parent = folder
	return remote
end

local function normalizeActionPayload(payload: any): (string?, string?, string?, { [string]: any }?)
	if typeof(payload) ~= "table" then
		return nil, nil, nil, nil
	end

	local dialogueId = if typeof(payload.dialogueId) == "string" then payload.dialogueId else nil
	local nodeId = if typeof(payload.nodeId) == "string" then payload.nodeId else nil
	local choiceId = if typeof(payload.choiceId) == "string" then payload.choiceId else nil
	local context = if typeof(payload.context) == "table" then payload.context else {}
	return dialogueId, nodeId, choiceId, context
end

local function getActionPayload(action: any): { [string]: any }
	return if typeof(action) == "table" and typeof(action.payload) == "table" then action.payload else {}
end

local function getQuestIdFromAction(action: any): string?
	local payload = getActionPayload(action)
	return if typeof(payload.questId) == "string" and payload.questId ~= "" then payload.questId else nil
end

local function buildQuestPayload(action: any): any
	local payload = getActionPayload(action)
	return {
		questId = getQuestIdFromAction(action),
		providerId = if typeof(payload.providerId) == "string" then payload.providerId else nil,
	}
end

local function getQuestStatus(player: Player, questId: string): string
	local questState = QuestService:GetQuestState(player)
	if typeof(questState) ~= "table" or typeof(questState.quests) ~= "table" then
		return "unavailable"
	end

	for _, entry in ipairs(questState.quests) do
		local definition = if typeof(entry) == "table" then entry.definition else nil
		if typeof(definition) == "table" and definition.id == questId then
			local activeQuest = entry.activeQuest
			if entry.isClaimed == true or entry.isCompleted == true then
				return "completed"
			end
			if typeof(activeQuest) == "table" and activeQuest.status == "readyToClaim" then
				return "readyToClaim"
			end
			if entry.isActive == true then
				return "active"
			end
			if entry.isAvailable == true or entry.lockReason == "Talk to the quest giver to start this quest." then
				return "available"
			end
			return "unavailable"
		end
	end

	return "unavailable"
end

local function evaluateStanQuestCondition(session: any, conditionId: string): boolean
	local player = session and session.player
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end

	if conditionId == "stanPaidRollIntroAvailable" then
		return getQuestStatus(player, STAN_PAID_ROLL_INTRO_QUEST_ID) == "available"
	elseif conditionId == "stanPaidRollIntroActive" then
		return getQuestStatus(player, STAN_PAID_ROLL_INTRO_QUEST_ID) == "active"
	elseif conditionId == "stanPaidRollIntroReady" then
		return getQuestStatus(player, STAN_PAID_ROLL_INTRO_QUEST_ID) == "readyToClaim"
	elseif conditionId == "stanPaidRollIntroCompleted" then
		return getQuestStatus(player, STAN_PAID_ROLL_INTRO_QUEST_ID) == "completed"
	elseif conditionId == "stanAppraisalIntroAvailable" then
		return getQuestStatus(player, STAN_APPRAISAL_INTRO_QUEST_ID) == "available"
	elseif conditionId == "stanAppraisalIntroActive" then
		return getQuestStatus(player, STAN_APPRAISAL_INTRO_QUEST_ID) == "active"
	elseif conditionId == "stanAppraisalIntroReady" then
		return getQuestStatus(player, STAN_APPRAISAL_INTRO_QUEST_ID) == "readyToClaim"
	elseif conditionId == "stanAppraisalIntroCompleted" then
		return getQuestStatus(player, STAN_APPRAISAL_INTRO_QUEST_ID) == "completed"
	elseif conditionId == "stanCraftingIntroAvailable" then
		return getQuestStatus(player, STAN_CRAFTING_INTRO_QUEST_ID) == "available"
	elseif conditionId == "stanCraftingIntroActive" then
		return getQuestStatus(player, STAN_CRAFTING_INTRO_QUEST_ID) == "active"
	elseif conditionId == "stanCraftingIntroReady" then
		return getQuestStatus(player, STAN_CRAFTING_INTRO_QUEST_ID) == "readyToClaim"
	elseif conditionId == "stanCraftingIntroCompleted" then
		return getQuestStatus(player, STAN_CRAFTING_INTRO_QUEST_ID) == "completed"
	elseif conditionId == "stanBossIntroAvailable" then
		return getQuestStatus(player, STAN_BOSS_INTRO_QUEST_ID) == "available"
	elseif conditionId == "stanBossIntroActive" then
		return getQuestStatus(player, STAN_BOSS_INTRO_QUEST_ID) == "active"
	elseif conditionId == "stanBossIntroReady" then
		return getQuestStatus(player, STAN_BOSS_INTRO_QUEST_ID) == "readyToClaim"
	elseif conditionId == "stanBossIntroCompleted" then
		return getQuestStatus(player, STAN_BOSS_INTRO_QUEST_ID) == "completed"
	end

	return false
end

function DialogueActionService:_registerDefaultConditions()
	if self._registered then
		return
	end
	self._registered = true

	Registry.RegisterCondition("vipOwned", function(session)
		if not VIP_OWNED_KEY then
			return false
		end

		local player = session and session.player
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return false
		end

		return DataService:Get(player, VIP_OWNED_KEY) == true
	end)

	for _, conditionId in ipairs({
		"stanPaidRollIntroAvailable",
		"stanPaidRollIntroActive",
		"stanPaidRollIntroReady",
		"stanPaidRollIntroCompleted",
		"stanAppraisalIntroAvailable",
		"stanAppraisalIntroActive",
		"stanAppraisalIntroReady",
		"stanAppraisalIntroCompleted",
		"stanCraftingIntroAvailable",
		"stanCraftingIntroActive",
		"stanCraftingIntroReady",
		"stanCraftingIntroCompleted",
		"stanBossIntroAvailable",
		"stanBossIntroActive",
		"stanBossIntroReady",
		"stanBossIntroCompleted",
	}) do
		Registry.RegisterCondition(conditionId, evaluateStanQuestCondition)
	end

	Registry.RegisterAction("acceptQuest", function(session, _choice, action)
		local player = session and session.player
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return false
		end

		local result = QuestService:AcceptQuest(player, buildQuestPayload(action))
		if typeof(result) ~= "table" or result.ok ~= true then
			if typeof(session) == "table" then
				session.actionResultData = {
					message = if typeof(result) == "table" then result.message else nil,
				}
			end
			return false
		end

		local activeQuest = result.activeQuest
		if typeof(session) == "table" and typeof(activeQuest) == "table" and activeQuest.status == "readyToClaim" then
			local payload = getActionPayload(action)
			session.actionResultData = {
				nextNodeId = if typeof(payload.readyNodeId) == "string" and payload.readyNodeId ~= ""
					then payload.readyNodeId
					else "ready",
			}
		end

		return true
	end)

	Registry.RegisterAction("claimQuest", function(session, _choice, action)
		local player = session and session.player
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return false
		end

		local result = QuestService:ClaimQuest(player, buildQuestPayload(action))
		if typeof(result) ~= "table" or result.ok ~= true then
			if typeof(session) == "table" then
				session.actionResultData = {
					message = if typeof(result) == "table" then result.message else nil,
				}
			end
			return false
		end

		local payload = getActionPayload(action)
		if typeof(session) == "table" then
			local rewardPresentation = if typeof(result.rewardPresentation) == "table" then result.rewardPresentation else {}
			session.actionResultData = {
				closeDialogue = payload.closeDialogue == true,
				nextNodeId = action.nextNodeId,
				rewardPresentation = rewardPresentation,
			}
		end

		return true
	end)
end

function DialogueActionService:RunAction(player: Player, payload: any)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return response(false, "A valid player is required.", nil)
	end

	local dialogueId, nodeId, choiceId, context = normalizeActionPayload(payload)
	if not (dialogueId and nodeId and choiceId) then
		return response(false, "Dialogue action payload is incomplete.", nil)
	end

	local _node, choice = DefinitionUtil.GetChoice(dialogueId, nodeId, choiceId)
	if not choice then
		return response(false, "That dialogue choice is no longer valid.", nil)
	end

	local session = {
		player = player,
		dialogueId = dialogueId,
		nodeId = nodeId,
		context = context,
	}

	if not Registry.EvaluateConditions(session, choice.conditionIds) then
		return response(false, "That dialogue choice is unavailable.", nil)
	end

	local action = choice.action
	if not action and choice.nextNodeId then
		return response(true, "OK", {
			nextNodeId = choice.nextNodeId,
		})
	end
	if not action then
		return response(false, "That dialogue choice has no action.", nil)
	end

	if not Registry.HasAction(action.type) then
		Logger.Warn(string.format("[DialogueActionService] Unsupported server dialogue action '%s'.", tostring(action.type)))
		return response(false, "That dialogue action is not supported by the server.", nil)
	end

	local result = Registry.RunAction(session, choice, action)
	if result ~= true then
		return response(false, "That dialogue action could not be completed.", nil)
	end

	local data = {
		nextNodeId = action.nextNodeId or choice.nextNodeId,
		closeDialogue = action.type == "closeDialogue",
	}
	if typeof(session.actionResultData) == "table" then
		for key, value in pairs(session.actionResultData) do
			data[key] = value
		end
	end

	return response(true, "OK", data)
end

function DialogueActionService:OnStart()
	if self._started then
		return
	end

	self._started = true
	self:_registerDefaultConditions()

	runActionRemote = ensureRemoteFunction(runActionRemote, RUN_ACTION_REMOTE_NAME)
	runActionRemote.OnServerInvoke = function(player: Player, payload: any)
		local allowed = RequestLimiter:Allow(player, "remote.dialogue.run_action")
		if not allowed then
			return response(false, "You're using dialogue too quickly.", nil)
		end

		return self:RunAction(player, payload)
	end
end

return DialogueActionService
