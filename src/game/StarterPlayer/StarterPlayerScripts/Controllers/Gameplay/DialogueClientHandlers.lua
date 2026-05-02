local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local Registry = require(ReplicatedStorage.Shared.Gameplay.Dialogue.Registry)
local Schema = require(ReplicatedStorage.Lists.Schema)

local DataController = require(script.Parent.DataController)
local DialogueController = require(script.Parent.DialogueController)
local FrameController = require(script.Parent.FrameController)
local MerchantPresentationController = require(script.Parent.MerchantPresentationController)
local ObjectiveGuideController = require(script.Parent.ObjectiveGuideController)

local DEFAULT_SHOP_FRAME_NAME = "ShopUI"
local APPRAISAL_FRAME_NAME = "AppraisalUI"
local VIP_OWNED_KEY = Schema.VipOwned and Schema.VipOwned.key or nil
local QUESTS_KEY = Schema.Quests and Schema.Quests.key or "quests"
local STAN_PAID_ROLL_INTRO_QUEST_ID = "stan_paid_roll_intro"
local STAN_APPRAISAL_INTRO_QUEST_ID = "stan_appraisal_intro"
local STAN_CRAFTING_INTRO_QUEST_ID = "stan_crafting_intro"
local STAN_BOSS_INTRO_QUEST_ID = "stan_boss_intro"

local registered = false

local DialogueClientHandlers = {}

local function toBoolean(value: any): boolean
	return value == true
end

local function getContextInstance(context: { [string]: any }?, key: string): Instance?
	if typeof(context) ~= "table" then
		return nil
	end

	local value = context[key]
	if typeof(value) == "Instance" then
		return value
	end

	return nil
end

local function openFrameWithPresentation(session, frameName: string, context: { [string]: any }?)
	session.closeDialogue(function()
		local shouldUseMerchantPresentation = context ~= nil
			and typeof(context.dialogueFrameName) == "string"
			and context.dialogueFrameName ~= ""

		if shouldUseMerchantPresentation then
			local dialogueCameraPart = getContextInstance(context, "dialogueCameraPart")
			local sourceInstance = getContextInstance(context, "sourceInstance")
			local speakerModel = getContextInstance(context, "speakerModel")
			local opened = MerchantPresentationController:Open(frameName, {
				cameraPart = if dialogueCameraPart and dialogueCameraPart:IsA("BasePart") then dialogueCameraPart else nil,
				sourceInstance = sourceInstance,
				interactionType = if context and typeof(context.interactionType) == "string" then context.interactionType else nil,
				speakerModel = if speakerModel and speakerModel:IsA("Model") then speakerModel else nil,
			})
			if opened then
				return
			end
		end

		FrameController:OpenFrame(frameName)
	end)
end

local function getQuestStatus(questId: string): string
	local questState = DataController:Get(QUESTS_KEY)
	if typeof(questState) ~= "table" then
		return "available"
	end

	local activeByQuestId = questState.activeByQuestId
	local activeQuest = if typeof(activeByQuestId) == "table" then activeByQuestId[questId] else nil
	if typeof(activeQuest) == "table" then
		return if activeQuest.status == "readyToClaim" then "readyToClaim" else "active"
	end

	local completedByQuestId = questState.completedByQuestId
	local claimedByQuestId = questState.claimedByQuestId
	if (typeof(completedByQuestId) == "table" and completedByQuestId[questId] == true)
		or (typeof(claimedByQuestId) == "table" and claimedByQuestId[questId] == true)
	then
		return "completed"
	end

	return "available"
end

local function evaluateStanQuestCondition(_session, conditionId: string): boolean
	if conditionId == "stanPaidRollIntroAvailable" then
		return getQuestStatus(STAN_PAID_ROLL_INTRO_QUEST_ID) == "available"
	elseif conditionId == "stanPaidRollIntroActive" then
		return getQuestStatus(STAN_PAID_ROLL_INTRO_QUEST_ID) == "active"
	elseif conditionId == "stanPaidRollIntroReady" then
		return getQuestStatus(STAN_PAID_ROLL_INTRO_QUEST_ID) == "readyToClaim"
	elseif conditionId == "stanPaidRollIntroCompleted" then
		return getQuestStatus(STAN_PAID_ROLL_INTRO_QUEST_ID) == "completed"
	elseif conditionId == "stanAppraisalIntroAvailable" then
		return getQuestStatus(STAN_PAID_ROLL_INTRO_QUEST_ID) == "completed"
			and getQuestStatus(STAN_APPRAISAL_INTRO_QUEST_ID) == "available"
	elseif conditionId == "stanAppraisalIntroActive" then
		return getQuestStatus(STAN_APPRAISAL_INTRO_QUEST_ID) == "active"
	elseif conditionId == "stanAppraisalIntroReady" then
		return getQuestStatus(STAN_APPRAISAL_INTRO_QUEST_ID) == "readyToClaim"
	elseif conditionId == "stanAppraisalIntroCompleted" then
		return getQuestStatus(STAN_APPRAISAL_INTRO_QUEST_ID) == "completed"
	elseif conditionId == "stanCraftingIntroAvailable" then
		return getQuestStatus(STAN_APPRAISAL_INTRO_QUEST_ID) == "completed"
			and getQuestStatus(STAN_CRAFTING_INTRO_QUEST_ID) == "available"
	elseif conditionId == "stanCraftingIntroActive" then
		return getQuestStatus(STAN_CRAFTING_INTRO_QUEST_ID) == "active"
	elseif conditionId == "stanCraftingIntroReady" then
		return getQuestStatus(STAN_CRAFTING_INTRO_QUEST_ID) == "readyToClaim"
	elseif conditionId == "stanCraftingIntroCompleted" then
		return getQuestStatus(STAN_CRAFTING_INTRO_QUEST_ID) == "completed"
	elseif conditionId == "stanBossIntroAvailable" then
		return getQuestStatus(STAN_CRAFTING_INTRO_QUEST_ID) == "completed"
			and getQuestStatus(STAN_BOSS_INTRO_QUEST_ID) == "available"
	elseif conditionId == "stanBossIntroActive" then
		return getQuestStatus(STAN_BOSS_INTRO_QUEST_ID) == "active"
	elseif conditionId == "stanBossIntroReady" then
		return getQuestStatus(STAN_BOSS_INTRO_QUEST_ID) == "readyToClaim"
	elseif conditionId == "stanBossIntroCompleted" then
		return getQuestStatus(STAN_BOSS_INTRO_QUEST_ID) == "completed"
	end

	return false
end

function DialogueClientHandlers.Register()
	if registered then
		return
	end

	Registry.RegisterAction("gotoNode", function(session, choice, action)
		local nextNodeId = action.nextNodeId or choice.nextNodeId
		if typeof(nextNodeId) ~= "string" or nextNodeId == "" then
			return false
		end

		return session.setCurrentNode(nextNodeId)
	end)

	Registry.RegisterAction("closeDialogue", function(session)
		session.closeDialogue()
		return true
	end)

	Registry.RegisterAction("openFrame", function(session, _choice, action)
		local context = session.context
		local frameName = action.frameName or (context and context.dialogueFrameName)
		if typeof(frameName) ~= "string" or frameName == "" then
			return false
		end

		openFrameWithPresentation(session, frameName, context)
		if frameName == APPRAISAL_FRAME_NAME then
			ObjectiveGuideController.ClearObjective("stan_appraisal_intro_guide")
		end
		return true
	end)

	Registry.RegisterAction("openShopFrame", function(session, _choice, action)
		local context = session.context
		local frameName = action.frameName or (context and context.dialogueFrameName) or DEFAULT_SHOP_FRAME_NAME
		if typeof(frameName) ~= "string" or frameName == "" then
			return false
		end

		openFrameWithPresentation(session, frameName, context)
		return true
	end)

	Registry.RegisterCondition("vipOwned", function()
		if not VIP_OWNED_KEY then
			return false
		end

		return toBoolean(DataController:Get(VIP_OWNED_KEY))
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

	DialogueController.SetBeforeOpenHook(function()
		local openFrameName = FrameController:GetOpenFrame()
		if not openFrameName then
			return 0
		end

		FrameController:CloseFrame()
		return FrameController.CloseTween.Time
	end)

	DialogueController.SetPortraitResolver(function(context)
		if typeof(context) == "table" then
			local speakerModel = context.speakerModel
			if typeof(speakerModel) == "Instance" and speakerModel:IsA("Model") then
				return speakerModel
			end
		end

		return BodyPartsCatalog.GetDefaultBaseRig()
	end)

	DialogueController.RegisterRefreshSignal(DataController.DataReceived)
	DialogueController.RegisterRefreshSignal(DataController.DataUpdated)

	registered = true
	Logger.Print("[DialogueClientHandlers] Registered client dialogue handlers.")
end

return DialogueClientHandlers
