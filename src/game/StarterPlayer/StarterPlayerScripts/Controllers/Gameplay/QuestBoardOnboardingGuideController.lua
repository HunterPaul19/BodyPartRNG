local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DataController = require(script.Parent.DataController)
local ObjectiveGuideController = require(script.Parent.ObjectiveGuideController)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)
local Schema = require(ReplicatedStorage.Lists.Schema)

local MAIN_PROFILE_ID = "main"
local QUESTS_KEY = Schema.Quests and Schema.Quests.key or "quests"
local TUTORIAL_KEY = Schema.Tutorial and Schema.Tutorial.key or "tutorial"
local BOARD_OPENED_FLAG = "onboarding_quest_board_opened"
local DIALOGUE_ID_ATTRIBUTE = "DialogueId"

local ONBOARDING_QUEST_IDS = table.freeze({
	"stan_paid_roll_intro",
	"stan_appraisal_intro",
	"stan_crafting_intro",
	"stan_boss_intro",
})

local BOARD_GUIDE = table.freeze({
	objectiveId = "onboarding_quest_board_guide",
	targetPath = "Workspace.Quest Board.PromptPart",
	fallbackTargetPaths = {
		"Workspace.Quest Board",
	},
	projectTargetToGround = true,
})

local GUIDE_TARGETS = table.freeze({
	{
		questId = "stan_appraisal_intro",
		objectiveId = "stan_appraisal_intro_guide",
		dialogueId = "appraiser_default",
		targetPath = "Workspace.Appraiser.Appraiser",
		fallbackTargetPaths = {
			"Workspace.Appraiser.Appraiser.HumanoidRootPart",
			"Workspace.Appraiser",
		},
		projectTargetToGround = false,
	},
	{
		questId = "stan_crafting_intro",
		objectiveId = "stan_crafting_intro_guide",
		dialogueId = "crafter_default",
		targetPath = "Workspace.Crafting.Craftsman",
		fallbackTargetPaths = {
			"Workspace.Crafting.Craftsman.HumanoidRootPart",
			"Workspace.Crafting.Craftsman.Crafting",
			"Workspace.Crafting",
		},
		projectTargetToGround = false,
	},
})

local QuestBoardOnboardingGuideController = {
	_started = false,
	_boardOpenedThisSession = false,
}

local function shouldRunForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == MAIN_PROFILE_ID
end

local function isTutorialComplete(rawTutorialState: any): boolean
	return typeof(rawTutorialState) == "table" and rawTutorialState.completed == true
end

local function isQuestClaimed(rawQuestState: any, questId: string): boolean
	if typeof(rawQuestState) ~= "table" then
		return false
	end

	local completedByQuestId = rawQuestState.completedByQuestId
	if typeof(completedByQuestId) == "table" and completedByQuestId[questId] == true then
		return true
	end

	local claimedByQuestId = rawQuestState.claimedByQuestId
	if typeof(claimedByQuestId) == "table" and claimedByQuestId[questId] == true then
		return true
	end

	local activeByQuestId = rawQuestState.activeByQuestId
	local activeQuest = if typeof(activeByQuestId) == "table" then activeByQuestId[questId] else nil
	return typeof(activeQuest) == "table" and activeQuest.status == "claimed"
end

local function areAllOnboardingQuestsClaimed(rawQuestState: any): boolean
	for _, questId in ipairs(ONBOARDING_QUEST_IDS) do
		if not isQuestClaimed(rawQuestState, questId) then
			return false
		end
	end

	return true
end

local function wasQuestBoardOpened(rawQuestState: any): boolean
	if typeof(rawQuestState) ~= "table" then
		return false
	end

	local unlockFlags = rawQuestState.unlockFlags
	return typeof(unlockFlags) == "table" and unlockFlags[BOARD_OPENED_FLAG] == true
end

local function shouldShowBoardGuide(data: any, boardOpenedThisSession: boolean): boolean
	if typeof(data) ~= "table" then
		return false
	end

	local rawQuestState = data[QUESTS_KEY]
	return isTutorialComplete(data[TUTORIAL_KEY])
		and boardOpenedThisSession ~= true
		and not wasQuestBoardOpened(rawQuestState)
		and not areAllOnboardingQuestsClaimed(rawQuestState)
end

local function isTalkStepActive(rawQuestState: any, questId: string): boolean
	if typeof(rawQuestState) ~= "table" then
		return false
	end

	local activeByQuestId = rawQuestState.activeByQuestId
	local activeQuest = if typeof(activeByQuestId) == "table" then activeByQuestId[questId] else nil
	if typeof(activeQuest) ~= "table" or activeQuest.status ~= "active" then
		return false
	end

	return math.floor(tonumber(activeQuest.currentPartIndex) or 1) == 1
end

local function readStringAttributeFromAncestors(source: Instance?, attributeName: string): string?
	local current = source
	while current do
		local value = current:GetAttribute(attributeName)
		if typeof(value) == "string" and value ~= "" then
			return value
		end
		current = current.Parent
	end

	return nil
end

local function resolveDialoguePromptPart(dialogueId: string): Instance?
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("ProximityPrompt")
			and readStringAttributeFromAncestors(descendant, DIALOGUE_ID_ATTRIBUTE) == dialogueId
		then
			local promptParent = descendant.Parent
			return if promptParent and promptParent:IsA("BasePart") then promptParent else descendant
		end
	end

	return nil
end

local function showGuide(guide: any, target: any)
	ObjectiveGuideController.ShowObjective(guide.objectiveId, target, {
		fallbackTargetPaths = guide.fallbackTargetPaths,
		projectTargetToGround = guide.projectTargetToGround,
	})
end

local function syncGuide(guide: any, shouldShow: boolean)
	if not shouldShow then
		ObjectiveGuideController.ClearObjective(guide.objectiveId)
		return
	end

	local target = if typeof(guide.dialogueId) == "string"
		then resolveDialoguePromptPart(guide.dialogueId)
		else nil
	showGuide(guide, target or guide.targetPath)
end

function QuestBoardOnboardingGuideController:_syncFromData(data: any)
	local rawQuestState = if typeof(data) == "table" then data[QUESTS_KEY] else nil
	syncGuide(BOARD_GUIDE, shouldShowBoardGuide(data, self._boardOpenedThisSession))

	for _, guide in ipairs(GUIDE_TARGETS) do
		syncGuide(guide, isTalkStepActive(rawQuestState, guide.questId))
	end
end

function QuestBoardOnboardingGuideController.MarkQuestBoardOpened()
	QuestBoardOnboardingGuideController._boardOpenedThisSession = true
	ObjectiveGuideController.ClearObjective(BOARD_GUIDE.objectiveId)
	QuestBoardOnboardingGuideController:_syncFromData(DataController:Get())
end

function QuestBoardOnboardingGuideController:OnStart()
	if self._started then
		return
	end

	self._started = true
	if not shouldRunForPlace() then
		return
	end

	if DataController.Loaded == true then
		self:_syncFromData(DataController:Get())
	end
	DataController.DataReceived:Connect(function(data: any)
		self:_syncFromData(data)
	end)
	DataController.DataUpdated:Connect(function(key: string)
		if key == QUESTS_KEY or key == TUTORIAL_KEY then
			self:_syncFromData(DataController:Get())
		end
	end)
end

return QuestBoardOnboardingGuideController
