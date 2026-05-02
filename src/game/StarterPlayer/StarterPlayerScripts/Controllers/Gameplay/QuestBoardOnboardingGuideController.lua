local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AppraisalController = require(script.Parent.AppraisalController)
local DataController = require(script.Parent.DataController)
local FrameController = require(script.Parent.FrameController)
local ObjectiveGuideController = require(script.Parent.ObjectiveGuideController)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)
local QuestConfig = require(ReplicatedStorage.Shared.Config.QuestConfig)
local RollController = require(script.Parent.RollController)
local Schema = require(ReplicatedStorage.Lists.Schema)
local ScreenDarkener = require(ReplicatedStorage.Shared.UI.ScreenDarkener)
local TutorialTextGui = require(ReplicatedStorage.Shared.UI.TutorialTextGui)

local LOCAL_PLAYER = Players.LocalPlayer
local MAIN_PROFILE_ID = "main"
local QUESTS_KEY = Schema.Quests and Schema.Quests.key or "quests"
local TUTORIAL_KEY = Schema.Tutorial and Schema.Tutorial.key or "tutorial"
local BOARD_OPENED_FLAG = "onboarding_quest_board_opened"
local QUEST_BOARD_TEXT = "Go to the quest board!"
local QUEST_READY_TO_CLAIM_TEXT = "Go back to quest board to claim rewards!"
local DIALOGUE_ID_ATTRIBUTE = "DialogueId"
local PAID_ROLL_QUEST_ID = "stan_paid_roll_intro"
local APPRAISAL_QUEST_ID = "stan_appraisal_intro"
local PAID_ROLL_TYPE_ID = "roll_2"
local SYNC_INTERVAL_SECONDS = 0.2
local STEP_TEXT_DURATION_SECONDS = TutorialTextGui.DefaultTemporaryDurationSeconds or 3

local ONBOARDING_QUEST_IDS = table.freeze({
	PAID_ROLL_QUEST_ID,
	APPRAISAL_QUEST_ID,
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
	_darkener = nil :: any,
	_activeTarget = nil :: GuiObject?,
	_ownsText = false,
	_lastText = nil :: string?,
	_questSnapshotsById = {} :: { [string]: { status: string?, currentPartIndex: number } },
	_temporaryText = nil :: string?,
	_temporaryTextToken = 0,
}

type AssistTarget = {
	target: GuiObject,
	text: string,
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

local function hasReadyToClaimQuest(rawQuestState: any): boolean
	if typeof(rawQuestState) ~= "table" then
		return false
	end

	local activeByQuestId = rawQuestState.activeByQuestId
	if typeof(activeByQuestId) ~= "table" then
		return false
	end

	for _, activeQuest in pairs(activeByQuestId) do
		if typeof(activeQuest) == "table" and activeQuest.status == "readyToClaim" then
			return true
		end
	end

	return false
end

local function getQuestPartIndex(activeQuest: any): number
	return math.max(1, math.floor(tonumber(activeQuest and activeQuest.currentPartIndex) or 1))
end

local function getQuestStepText(questId: string, partIndex: number): string?
	local definition = QuestConfig.Get(questId)
	if not definition then
		return nil
	end

	local description = QuestConfig.GetPartDescription(definition, partIndex)
	return if typeof(description) == "string" and description ~= "" then description else nil
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

local function isQuestPartActive(rawQuestState: any, questId: string, partIndex: number): boolean
	if typeof(rawQuestState) ~= "table" then
		return false
	end

	local activeByQuestId = rawQuestState.activeByQuestId
	local activeQuest = if typeof(activeByQuestId) == "table" then activeByQuestId[questId] else nil
	if typeof(activeQuest) ~= "table" or activeQuest.status ~= "active" then
		return false
	end

	return math.floor(tonumber(activeQuest.currentPartIndex) or 1) == partIndex
end

local function isGuiTargetUsable(target: GuiObject?): boolean
	return target ~= nil
		and target.Visible == true
		and target.AbsoluteSize.X > 0
		and target.AbsoluteSize.Y > 0
end

local function isHudAssistBlocked(): boolean
	return FrameController:GetOpenFrame() ~= nil
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

local function syncTalkStepGuides(rawQuestState: any)
	for _, guide in ipairs(GUIDE_TARGETS) do
		syncGuide(guide, isTalkStepActive(rawQuestState, guide.questId))
	end
end

function QuestBoardOnboardingGuideController:_ensureDarkener()
	if self._darkener ~= nil then
		return self._darkener
	end

	self._darkener = ScreenDarkener.New(10, 0.12)
	return self._darkener
end

function QuestBoardOnboardingGuideController:_setDarkenerInputCapture(enabled: boolean)
	local darkener = self._darkener
	if darkener == nil then
		return
	end

	local shouldCaptureInput = enabled == true and UserInputService.TouchEnabled ~= true
	for _, frame in ipairs({ darkener.TopFrame, darkener.BottomFrame, darkener.LeftFrame, darkener.RightFrame }) do
		if frame and frame:IsA("GuiObject") then
			frame.Active = shouldCaptureInput
		end
	end
end

function QuestBoardOnboardingGuideController:_clearDarkener()
	if self._activeTarget == nil and self._darkener == nil then
		return
	end

	self._activeTarget = nil
	self:_setDarkenerInputCapture(false)
	if self._darkener then
		self._darkener:Deactivate()
	end
end

function QuestBoardOnboardingGuideController:_showDarkener(target: GuiObject)
	local darkener = self:_ensureDarkener()
	if not darkener then
		return
	end

	if typeof(darkener.LayerAbove) == "function" then
		darkener:LayerAbove(target)
	end
	if typeof(darkener.GetDisplayOrder) == "function" then
		TutorialTextGui.LayerAboveDisplayOrder(darkener:GetDisplayOrder())
	end

	if self._activeTarget == target then
		darkener:Switch(target, 10)
	else
		darkener:Activate(target, 10)
	end
	self._activeTarget = target
	self:_setDarkenerInputCapture(true)
end

function QuestBoardOnboardingGuideController:_setOwnedText(text: string?)
	local resolvedText = if typeof(text) == "string" then text else nil
	if resolvedText ~= nil and resolvedText ~= "" then
		if self._lastText ~= resolvedText then
			TutorialTextGui.SetText(resolvedText)
			self._lastText = resolvedText
		end
		self._ownsText = true
		return
	end

	if self._ownsText then
		TutorialTextGui.HideText()
	end
	self._ownsText = false
	self._lastText = nil
end

function QuestBoardOnboardingGuideController:_resolvePaidRollAssist(rawQuestState: any): AssistTarget?
	if not isQuestPartActive(rawQuestState, PAID_ROLL_QUEST_ID, 1) then
		return nil
	end
	if RollController:GetSelectedRollTypeId() == PAID_ROLL_TYPE_ID then
		return nil
	end
	if isHudAssistBlocked() then
		return nil
	end
	if not RollController:PrepareTutorialTarget("roll2Selection") then
		return nil
	end

	local roll2Entry = RollController:GetTutorialTarget("roll2Entry")
	if isGuiTargetUsable(roll2Entry) then
		return {
			target = roll2Entry :: GuiObject,
			text = "Choose Roll 2.",
		}
	end

	local dropdownButton = RollController:GetTutorialTarget("rollDropdownButton")
	if isGuiTargetUsable(dropdownButton) then
		return {
			target = dropdownButton :: GuiObject,
			text = "Open Rolls.",
		}
	end

	return nil
end

function QuestBoardOnboardingGuideController:_resolveAppraisalAssist(rawQuestState: any): AssistTarget?
	if not isQuestPartActive(rawQuestState, APPRAISAL_QUEST_ID, 2) then
		return nil
	end
	if not AppraisalController:IsOpen() then
		return nil
	end

	local appraiseButton = AppraisalController:GetTutorialTarget("appraiseButton")
	if isGuiTargetUsable(appraiseButton) then
		return {
			target = appraiseButton :: GuiObject,
			text = "Press Appraise.",
		}
	end

	local firstEquippedSlot = AppraisalController:GetTutorialTarget("firstEquippedSlot")
	if isGuiTargetUsable(firstEquippedSlot) then
		return {
			target = firstEquippedSlot :: GuiObject,
			text = "Select a body part.",
		}
	end

	return nil
end

function QuestBoardOnboardingGuideController:_resolvePersistentText(rawQuestState: any, data: any): string?
	if hasReadyToClaimQuest(rawQuestState) then
		return QUEST_READY_TO_CLAIM_TEXT
	end
	if shouldShowBoardGuide(data, self._boardOpenedThisSession) then
		return QUEST_BOARD_TEXT
	end

	return nil
end

function QuestBoardOnboardingGuideController:_showTemporaryStepText(text: string)
	if typeof(text) ~= "string" or text == "" then
		return
	end

	self._temporaryTextToken += 1
	local token = self._temporaryTextToken
	self._temporaryText = text
	self:_syncAssistFromData(DataController:Get())

	task.delay(STEP_TEXT_DURATION_SECONDS, function()
		if self._temporaryTextToken ~= token then
			return
		end

		self._temporaryText = nil
		self:_syncAssistFromData(DataController:Get())
	end)
end

function QuestBoardOnboardingGuideController:_processQuestStateTransitions(rawQuestState: any)
	if typeof(rawQuestState) ~= "table" then
		self._questSnapshotsById = {}
		return
	end

	local activeByQuestId = rawQuestState.activeByQuestId
	if typeof(activeByQuestId) ~= "table" then
		self._questSnapshotsById = {}
		return
	end

	local nextSnapshots = {}
	local stepTextToShow = nil :: string?
	for questId, activeQuest in pairs(activeByQuestId) do
		if typeof(questId) ~= "string" or typeof(activeQuest) ~= "table" then
			continue
		end

		local status = if typeof(activeQuest.status) == "string" then activeQuest.status else nil
		local currentPartIndex = getQuestPartIndex(activeQuest)
		local previousSnapshot = self._questSnapshotsById[questId]
		if previousSnapshot
			and previousSnapshot.status == "active"
			and status == "active"
			and currentPartIndex > previousSnapshot.currentPartIndex
		then
			stepTextToShow = getQuestStepText(questId, currentPartIndex) or stepTextToShow
		end

		nextSnapshots[questId] = {
			status = status,
			currentPartIndex = currentPartIndex,
		}
	end

	self._questSnapshotsById = nextSnapshots
	if stepTextToShow then
		self:_showTemporaryStepText(stepTextToShow)
	end
end

function QuestBoardOnboardingGuideController:_syncAssist(rawQuestState: any, data: any)
	if DataController.Loaded ~= true then
		self:_clearDarkener()
		self:_setOwnedText(nil)
		return
	end

	local assist = self:_resolvePaidRollAssist(rawQuestState) or self:_resolveAppraisalAssist(rawQuestState)
	if assist then
		self:_showDarkener(assist.target)
		self:_setOwnedText(assist.text)
		return
	end

	self:_clearDarkener()
	self:_setOwnedText(self._temporaryText or self:_resolvePersistentText(rawQuestState, data))
end

function QuestBoardOnboardingGuideController:_syncAssistFromData(data: any)
	local rawQuestState = if typeof(data) == "table" then data[QUESTS_KEY] else nil
	self:_syncAssist(rawQuestState, data)
end

function QuestBoardOnboardingGuideController:_syncFromData(data: any)
	local rawQuestState = if typeof(data) == "table" then data[QUESTS_KEY] else nil
	self:_processQuestStateTransitions(rawQuestState)
	syncGuide(BOARD_GUIDE, shouldShowBoardGuide(data, self._boardOpenedThisSession))
	syncTalkStepGuides(rawQuestState)
	self:_syncAssist(rawQuestState, data)
end

function QuestBoardOnboardingGuideController.SyncQuestState(rawQuestState: any)
	if not shouldRunForPlace() then
		return
	end

	QuestBoardOnboardingGuideController:_processQuestStateTransitions(rawQuestState)
	syncTalkStepGuides(rawQuestState)
	QuestBoardOnboardingGuideController:_syncAssist(rawQuestState, DataController:Get())
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

	TutorialTextGui.Init(LOCAL_PLAYER:WaitForChild("PlayerGui"))

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

	task.spawn(function()
		while self._started == true do
			self:_syncAssistFromData(DataController:Get())
			task.wait(SYNC_INTERVAL_SECONDS)
		end
	end)
end

return QuestBoardOnboardingGuideController
