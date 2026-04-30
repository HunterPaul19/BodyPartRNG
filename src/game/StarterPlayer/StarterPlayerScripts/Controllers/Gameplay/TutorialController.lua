local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Logger = require(ReplicatedStorage.Shared.Diagnostics.Logger)
local ChestOpeningSequence = require(ReplicatedStorage.Shared.UI.ChestOpeningSequence)
local ConfirmationWarning = require(ReplicatedStorage.Shared.UI.ConfirmationWarning)
local AppraisalController = require(script.Parent.AppraisalController)
local FrameController = require(script.Parent.FrameController)
local CraftingController = require(script.Parent.CraftingController)
local DailyChestConfig = require(ReplicatedStorage.Shared.Config.DailyChestConfig)
local InventoryController = require(script.Parent.InventoryController)
local ObjectiveGuideController = require(script.Parent.ObjectiveGuideController)
local PotionController = require(script.Parent.PotionController)
local RollController = require(script.Parent.RollController)
local DataController = require(script.Parent.DataController)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)
local ScreenDarkener = require(ReplicatedStorage.Shared.UI.ScreenDarkener)
local CraftingRecipeConfig = require(ReplicatedStorage.Shared.Config.CraftingRecipeConfig)
local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
local CraftingProgress = require(ReplicatedStorage.Shared.Character.CraftingProgress)
local TutorialState = require(ReplicatedStorage.Shared.Character.TutorialState)
local TutorialTextGui = require(ReplicatedStorage.Shared.UI.TutorialTextGui)

local LOCAL_PLAYER = Players.LocalPlayer
local REMOTE_TIMEOUT = 30
local OBJECTIVE_ID = "new_player_tutorial"
local APPRAISER_DIALOGUE_ID = "appraiser_default"
local APPRAISAL_FRAME_NAME = "AppraisalUI"
local MAIN_INTERFACE_GUI_NAME = "MainInterface"
local DIALOGUE_ROOT_NAME = "DialogueUI"
local DIALOGUE_ID_ATTRIBUTE = "DialogueId"
local DIALOGUE_ACTION_TYPE_ATTRIBUTE = "DialogueActionType"
local DIALOGUE_FRAME_NAME_ATTRIBUTE = "DialogueFrameName"
local APPRAISER_SPEAKER_NAME = "Appraiser"
local APPRAISE_CHOICE_BUTTON_NAME = "Choice_appraise"
local APPRAISAL_DIALOGUE_TEXT_TOKEN = "appraisal table"
local APPRAISAL_CHOICE_TEXT_TOKEN = "open the appraisal"

local TutorialController = {
	_started = false,
	_currentStepId = nil,
	_claimingChest = false,
	_chestOpeningActive = false,
	_chestReturnTextActive = false,
	_chestRetryScheduled = false,
	_pendingPostChestState = nil,
	_pendingPostRollState = nil,
	_refreshingAdvance = false,
	_lastAdvanceRefreshStepId = nil,
	_activeState = nil,
	_holidayCrownReadyRollHoldActive = false,
	_spotlightLoopStarted = false,
	_darkener = nil,
	_spotlightTarget = nil,
	_spotlightActive = false,
	_lastText = nil,
	_welcomeInputConnections = {},
	_welcomeIntentListening = false,
	_welcomeAdvanceRequested = false,
}

local function getLocalUtcOffsetMinutes(): number
	local now = os.time()
	local localDate = os.date("*t", now)
	local utcDate = os.date("!*t", now)
	if typeof(localDate) ~= "table" or typeof(utcDate) ~= "table" then
		return 0
	end

	localDate.isdst = false
	utcDate.isdst = false

	local ok, diffSeconds = pcall(function()
		return os.difftime(os.time(localDate), os.time(utcDate))
	end)
	if not ok then
		return 0
	end

	return math.clamp(math.floor((tonumber(diffSeconds) or 0) / 60), -14 * 60, 14 * 60)
end

local function waitForLoadingScreenDismissed()
	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	local loadingScreen = playerGui:FindFirstChild("LoadingScreen")
	while loadingScreen and loadingScreen.Parent do
		loadingScreen.AncestryChanged:Wait()
	end
end

local function waitForPlayerData()
	if DataController.Loaded == true then
		return
	end

	DataController.DataReceived:Wait()
end

local function resolveTutorialRemote(remoteName: string): RemoteFunction?
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", REMOTE_TIMEOUT)
	local tutorialFolder = remotesFolder and remotesFolder:WaitForChild("Tutorial", REMOTE_TIMEOUT)
	local remote = tutorialFolder and tutorialFolder:WaitForChild(remoteName, REMOTE_TIMEOUT)
	if remote and remote:IsA("RemoteFunction") then
		return remote
	end

	return nil
end

local function resolveTutorialUpdatedRemote(): RemoteEvent?
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", REMOTE_TIMEOUT)
	local tutorialFolder = remotesFolder and remotesFolder:WaitForChild("Tutorial", REMOTE_TIMEOUT)
	local remote = tutorialFolder and tutorialFolder:WaitForChild("TutorialUpdated", REMOTE_TIMEOUT)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end

	return nil
end

local function openChestPackagesSequentially(chests: { any })
	local openedAny = false
	for _, package in ipairs(chests) do
		if typeof(package) ~= "table" then
			continue
		end

		local visualChestId = if typeof(package.visualChestId) == "string" and package.visualChestId ~= ""
			then package.visualChestId
			else package.chestId
		local rewards = if typeof(package.rewards) == "table" then package.rewards else {}
		if typeof(visualChestId) == "string" and #rewards > 0 then
			openedAny = ChestOpeningSequence.OpenChestAsync(visualChestId, rewards) or openedAny
		end
	end

	return openedAny
end

local function getFirstChestReturnMessage(chests: { any }): string
	for _, package in ipairs(chests) do
		if typeof(package) == "table" then
			return DailyChestConfig.GetReturnMessage(package.chestId)
		end
	end

	return DailyChestConfig.GetReturnMessage(TutorialConfig.TutorialChestId)
end

local function waitForChestRewardOverlayReady(timeoutSeconds: number): (boolean, string?)
	local timeout = math.max(0, tonumber(timeoutSeconds) or 0)
	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui", timeout)
	if not playerGui then
		return false, "PlayerGui was not ready."
	end

	local overlay = playerGui:WaitForChild("ChestRewardOverlay", timeout)
	if not (overlay and overlay:IsA("ScreenGui")) then
		return false, "PlayerGui.ChestRewardOverlay is missing."
	end

	local requiredChildren = {
		ItemHolder = "Frame",
		ConfirmButton = "GuiButton",
		Prompt = "TextLabel",
	}
	for childName, className in pairs(requiredChildren) do
		local child = overlay:WaitForChild(childName, timeout)
		if not (child and child:IsA(className)) then
			return false, string.format("ChestRewardOverlay.%s is missing.", childName)
		end
	end

	return true, nil
end

local function isGuiTreeVisible(target: GuiObject, playerGui: PlayerGui): boolean
	local current: Instance? = target
	while current and current ~= playerGui do
		if current:IsA("GuiObject") and current.Visible ~= true then
			return false
		end
		if current:IsA("ScreenGui") and current.Enabled ~= true then
			return false
		end
		current = current.Parent
	end

	return current == playerGui
end

local function isGuiObjectOnScreen(target: GuiObject): boolean
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end

	local viewportSize = camera.ViewportSize
	local absolutePosition = target.AbsolutePosition
	local absoluteSize = target.AbsoluteSize

	return absolutePosition.X < viewportSize.X
		and absolutePosition.Y < viewportSize.Y
		and absolutePosition.X + absoluteSize.X > 0
		and absolutePosition.Y + absoluteSize.Y > 0
end

local function getVisibleSizedGuiObject(target: Instance?): GuiObject?
	if not (target and target:IsA("GuiObject")) then
		return nil
	end

	if target.Parent ~= nil and target.Visible == true and target.AbsoluteSize.X > 0 and target.AbsoluteSize.Y > 0 then
		return target
	end

	return nil
end

local function getNormalizedText(value: any): string
	if typeof(value) ~= "string" then
		return ""
	end

	return string.lower(value)
end

local function textContains(value: any, token: string): boolean
	return string.find(getNormalizedText(value), token, 1, true) ~= nil
end

local function getChildTextLabelText(root: Instance, childName: string): string?
	local child = root:FindFirstChild(childName, true)
	if child and child:IsA("TextLabel") then
		return child.Text
	end

	return nil
end

local function hasDescendantText(root: Instance, token: string): boolean
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("TextLabel") and textContains(descendant.Text, token) then
			return true
		end
	end

	return false
end

local function getButtonContentText(button: GuiButton): string?
	local content = button:FindFirstChild("Content")
	if content and content:IsA("TextLabel") then
		return content.Text
	end

	for _, descendant in ipairs(button:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			return descendant.Text
		end
	end

	return nil
end

local function hasAppraisalChoiceButton(root: Instance): boolean
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiButton") and textContains(getButtonContentText(descendant), APPRAISAL_CHOICE_TEXT_TOKEN) then
			return true
		end
	end

	return false
end

local function isAppraisalChoiceButton(button: GuiButton): boolean
	if button:GetAttribute(DIALOGUE_ACTION_TYPE_ATTRIBUTE) == "openFrame"
		and button:GetAttribute(DIALOGUE_FRAME_NAME_ATTRIBUTE) == APPRAISAL_FRAME_NAME
	then
		return true
	end

	if button.Name == APPRAISE_CHOICE_BUTTON_NAME then
		return true
	end

	return textContains(getButtonContentText(button), APPRAISAL_CHOICE_TEXT_TOKEN)
end

local function getAppraiserDialogueRoot(): GuiObject?
	local playerGui = LOCAL_PLAYER:FindFirstChildOfClass("PlayerGui")
	local mainInterface = playerGui and playerGui:FindFirstChild(MAIN_INTERFACE_GUI_NAME)
	local dialogueRoot = mainInterface and mainInterface:FindFirstChild(DIALOGUE_ROOT_NAME)
	if not (dialogueRoot and dialogueRoot:IsA("GuiObject")) then
		return nil
	end

	if dialogueRoot.Visible ~= true then
		return nil
	end

	if dialogueRoot:GetAttribute(DIALOGUE_ID_ATTRIBUTE) == APPRAISER_DIALOGUE_ID then
		return dialogueRoot
	end

	if getChildTextLabelText(dialogueRoot, "ItemName") == APPRAISER_SPEAKER_NAME then
		return dialogueRoot
	end

	if hasDescendantText(dialogueRoot, APPRAISAL_DIALOGUE_TEXT_TOKEN) then
		return dialogueRoot
	end

	if hasAppraisalChoiceButton(dialogueRoot) then
		return dialogueRoot
	end

	return nil
end

local function getChoiceTarget(button: GuiButton): GuiObject?
	local buttonTarget = getVisibleSizedGuiObject(button)
	if buttonTarget then
		return buttonTarget
	end

	return getVisibleSizedGuiObject(button:FindFirstChild("Content"))
end

local function resolveAppraiserDialogueChoiceTarget(): (GuiObject?, boolean)
	local dialogueRoot = getAppraiserDialogueRoot()
	if not dialogueRoot then
		return nil, false
	end

	for _, descendant in ipairs(dialogueRoot:GetDescendants()) do
		if not descendant:IsA("GuiButton") then
			continue
		end
		if not isAppraisalChoiceButton(descendant) then
			continue
		end

		return getChoiceTarget(descendant), true
	end

	return nil, true
end

local function isWelcomeInput(input: InputObject): boolean
	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.Touch
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseButton3
	then
		return true
	end

	return inputType.Name:match("^Gamepad") ~= nil
end

local function formatPaidRollText(state: any): string
	local paidRollCount = if typeof(state) == "table" then tonumber(state.paidRollCount) or 0 else 0
	local remaining = math.max(1, TutorialConfig.PaidRollGoal - math.floor(paidRollCount))
	local unit = if remaining == 1 then "time" else "times"
	return string.format("Roll %d %s", remaining, unit)
end

function TutorialController:_claimTutorialChest()
	if self._claimingChest == true then
		return
	end
	local activeState = self._activeState
	if typeof(activeState) ~= "table"
		or activeState.stepId ~= TutorialConfig.Steps.ClaimDailyChest
		or activeState.tutorialChestClaimed == true
	then
		return
	end

	self._claimingChest = true
	task.spawn(function()
		local overlayReady, overlayMessage = waitForChestRewardOverlayReady(10)
		if overlayReady ~= true then
			Logger.Warn(string.format("[TutorialController] Tutorial chest overlay is not ready: %s", tostring(overlayMessage)))
			self._claimingChest = false
			self:_scheduleTutorialChestRetry()
			return
		end

		local claimRemote = resolveTutorialRemote("ClaimTutorialChest")
		if not claimRemote then
			self._claimingChest = false
			self:_scheduleTutorialChestRetry()
			return
		end

		local stateBeforeClaim = self._activeState
		if typeof(stateBeforeClaim) ~= "table"
			or stateBeforeClaim.stepId ~= TutorialConfig.Steps.ClaimDailyChest
			or stateBeforeClaim.tutorialChestClaimed == true
		then
			self._claimingChest = false
			return
		end

		local ok, result = pcall(function()
			return claimRemote:InvokeServer({
				localUtcOffsetMinutes = getLocalUtcOffsetMinutes(),
			})
		end)
		if not ok or typeof(result) ~= "table" or result.ok ~= true then
			self._claimingChest = false
			Logger.Warn(string.format(
				"[TutorialController] Tutorial chest claim failed: %s",
				if ok and typeof(result) == "table" then tostring(result.message) else tostring(result)
			))
			self:_scheduleTutorialChestRetry()
			return
		end

		self._chestRetryScheduled = false
		local chests = if typeof(result.chests) == "table" then result.chests else {}
		self._chestOpeningActive = true
		self._claimingChest = false
		self:_syncSpotlight()

		local openedChest = openChestPackagesSequentially(chests)
		local shouldShowReturnText = openedChest == true
		if shouldShowReturnText then
			self._chestReturnTextActive = true
		end
		self._chestOpeningActive = false
		if shouldShowReturnText then
			self:_clearSpotlight()
			TutorialTextGui.ShowTemporaryTextAsync(getFirstChestReturnMessage(chests))
		end

		if openedChest ~= true then
			Logger.Warn("[TutorialController] Tutorial chest rewards were granted, but the chest presentation did not open.")
		end

		local okRefresh = pcall(function()
			PotionController:RequestState()
		end)
		if not okRefresh then
			Logger.Warn("[TutorialController] Failed to refresh potion state after tutorial chest.")
		end

		local nextState = self._pendingPostChestState
		self._pendingPostChestState = nil
		if typeof(nextState) ~= "table" then
			nextState = result.state
		end
		if shouldShowReturnText then
			self._chestReturnTextActive = false
		end
		if typeof(nextState) == "table" then
			self:_applyState(nextState)
		end
	end)
end

function TutorialController:_scheduleTutorialChestRetry()
	if self._chestRetryScheduled == true then
		return
	end

	self._chestRetryScheduled = true
	task.delay(3, function()
		self._chestRetryScheduled = false
		local state = self._activeState
		if self._started == true
			and typeof(state) == "table"
			and state.stepId == TutorialConfig.Steps.ClaimDailyChest
			and state.tutorialChestClaimed ~= true
		then
			self:_claimTutorialChest()
		end
	end)
end

function TutorialController:_requestAdvanceRefresh(stepId: string)
	if self._refreshingAdvance == true then
		return
	end
	if self._lastAdvanceRefreshStepId == stepId then
		return
	end
	self._lastAdvanceRefreshStepId = stepId

	self._refreshingAdvance = true
	task.delay(0.2, function()
		local advanceRemote = resolveTutorialRemote("AdvanceTutorialStep")
		self._refreshingAdvance = false
		if not advanceRemote then
			return
		end

		local ok, result = pcall(function()
			return advanceRemote:InvokeServer({
				stepId = stepId,
			})
		end)
		if ok and typeof(result) == "table" and typeof(result.state) == "table" then
			self:_applyState(result.state)
		end
	end)
end

function TutorialController:_disconnectWelcomeIntentListeners()
	for _, connection in ipairs(self._welcomeInputConnections) do
		if connection and typeof(connection.Disconnect) == "function" then
			connection:Disconnect()
		end
	end
	table.clear(self._welcomeInputConnections)
	self._welcomeIntentListening = false
end

function TutorialController:_requestWelcomeAdvance()
	if self._welcomeAdvanceRequested == true then
		return
	end

	local state = self._activeState
	if typeof(state) ~= "table" or state.stepId ~= TutorialConfig.Steps.Welcome then
		return
	end

	self._welcomeAdvanceRequested = true
	self:_disconnectWelcomeIntentListeners()
	task.spawn(function()
		local advanceRemote = resolveTutorialRemote("AdvanceTutorialStep")
		if not advanceRemote then
			self._welcomeAdvanceRequested = false
			self:_startWelcomeIntentListeners()
			return
		end

		local ok, result = pcall(function()
			return advanceRemote:InvokeServer({
				stepId = TutorialConfig.Steps.RollFree,
			})
		end)
		self._welcomeAdvanceRequested = false
		if ok and typeof(result) == "table" and typeof(result.state) == "table" then
			self:_applyState(result.state)
		else
			self:_startWelcomeIntentListeners()
		end
	end)
end

function TutorialController:_connectWelcomeMovementForCharacter(character: Model?)
	local state = self._activeState
	if typeof(state) ~= "table" or state.stepId ~= TutorialConfig.Steps.Welcome then
		return
	end

	if character == nil then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		task.spawn(function()
			local resolvedHumanoid = character:WaitForChild("Humanoid", 10)
			if resolvedHumanoid and resolvedHumanoid:IsA("Humanoid") then
				self:_connectWelcomeMovementForCharacter(character)
			end
		end)
		return
	end

	local function checkMovement()
		if humanoid.MoveDirection.Magnitude > 0.05 then
			self:_requestWelcomeAdvance()
		end
	end

	table.insert(self._welcomeInputConnections, humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(checkMovement))
	checkMovement()
end

function TutorialController:_startWelcomeIntentListeners()
	if self._welcomeIntentListening == true then
		return
	end

	local state = self._activeState
	if typeof(state) ~= "table" or state.stepId ~= TutorialConfig.Steps.Welcome then
		return
	end

	self._welcomeIntentListening = true
	table.insert(self._welcomeInputConnections, UserInputService.InputBegan:Connect(function(input: InputObject, _gameProcessedEvent: boolean)
		if isWelcomeInput(input) then
			self:_requestWelcomeAdvance()
		end
	end))
	table.insert(self._welcomeInputConnections, LOCAL_PLAYER.CharacterAdded:Connect(function(character: Model)
		self:_connectWelcomeMovementForCharacter(character)
	end))
	self:_connectWelcomeMovementForCharacter(LOCAL_PLAYER.Character)
end

function TutorialController:_setTutorialText(text: string?)
	local resolvedText = if typeof(text) == "string" then text else ""
	if self._lastText == resolvedText then
		return
	end

	self._lastText = resolvedText
	if resolvedText ~= "" then
		TutorialTextGui.SetText(resolvedText)
	else
		TutorialTextGui.HideText()
	end
end

function TutorialController:_ensureDarkener()
	if self._darkener ~= nil then
		return self._darkener
	end

	self._darkener = ScreenDarkener.New(10, 0.12)
	return self._darkener
end

function TutorialController:_setDarkenerInputCapture(enabled: boolean)
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

function TutorialController:_clearSpotlight()
	if self._spotlightActive ~= true and self._spotlightTarget == nil then
		return
	end

	self._spotlightTarget = nil
	self._spotlightActive = false
	self:_setDarkenerInputCapture(false)
	if self._darkener then
		self._darkener:Deactivate()
	end
end

function TutorialController:_activateSpotlight(target: GuiObject, captureInput: boolean)
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

	if self._spotlightActive == true and self._spotlightTarget == target then
		darkener:Switch(target, 10)
	else
		darkener:Activate(target, 10)
	end
	self._spotlightTarget = target
	self._spotlightActive = true
	self:_setDarkenerInputCapture(captureInput)
end

function TutorialController:_isTargetUsable(target: any): boolean
	if not (target and typeof(target) == "Instance" and target:IsA("GuiObject")) then
		return false
	end

	if target.Visible ~= true or target.AbsoluteSize.X <= 0 or target.AbsoluteSize.Y <= 0 then
		return false
	end

	local playerGui = LOCAL_PLAYER:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil or not target:IsDescendantOf(playerGui) then
		return false
	end

	return isGuiTreeVisible(target, playerGui) and isGuiObjectOnScreen(target)
end

function TutorialController:_isInventoryOpen(): boolean
	return FrameController:IsOpen("Inventory")
end

function TutorialController:_isCraftingOpen(): boolean
	if typeof(CraftingController.IsOpen) == "function" then
		return CraftingController:IsOpen()
	end

	return FrameController:IsOpen("CraftingMenu")
end

function TutorialController:_isAppraisalOpen(): boolean
	if typeof(AppraisalController.IsOpen) == "function" then
		return AppraisalController:IsOpen()
	end

	return FrameController:IsOpen("AppraisalUI")
end

function TutorialController:_isHolidayCrownAutoCraftEnabled(): boolean
	local progress = DataController:Get("craftingProgress")
	local autoRecipeIds = if typeof(progress) == "table" then progress.autoRecipeIds else nil
	return typeof(autoRecipeIds) == "table" and autoRecipeIds[TutorialConfig.TargetRecipeId] == true
end

function TutorialController:_isHolidayCrownReadyToCraft(): boolean
	local recipe = CraftingRecipeConfig.Get(TutorialConfig.TargetRecipeId)
	if not recipe then
		return false
	end

	local progressState = CraftingProgress.NormalizeState(DataController:Get("craftingProgress"))
	local recipeProgress = CraftingProgress.GetRecipeProgress(progressState, recipe.id)
	for _, ingredient in ipairs(if typeof(recipe.bodyParts) == "table" then recipe.bodyParts else {}) do
		local ingredientKey = CraftingProgress.GetBodyPartIngredientKey(ingredient)
		local requiredAmount = math.max(1, math.floor(tonumber(ingredient.amount) or 1))
		if (recipeProgress.bodyPartsByIngredientKey[ingredientKey] or 0) < requiredAmount then
			return false
		end
	end
	for _, ingredient in ipairs(if typeof(recipe.materials) == "table" then recipe.materials else {}) do
		local requiredAmount = math.max(1, math.floor(tonumber(ingredient.amount) or 1))
		if (recipeProgress.materialsByMaterialId[ingredient.materialId] or 0) < requiredAmount then
			return false
		end
	end

	return true
end

function TutorialController:_isChestPresentationActive(): boolean
	if self._claimingChest == true or self._chestOpeningActive == true or self._chestReturnTextActive == true then
		return true
	end

	return typeof(ChestOpeningSequence.IsActive) == "function" and ChestOpeningSequence.IsActive() == true
end

function TutorialController:_isRollPresentationPending(): boolean
	return typeof(RollController.IsRollPresentationPending) == "function"
		and RollController:IsRollPresentationPending() == true
end

function TutorialController:_showRollPresentationHold()
	self:_setTutorialText("Finish your roll.")
	self:_clearSpotlight()
end

function TutorialController:_shouldHoldHolidayCrownReadyForRollReveal(stateOrStepId: any): boolean
	local stepId = if typeof(stateOrStepId) == "table" then stateOrStepId.stepId else stateOrStepId
	if stepId ~= TutorialConfig.Steps.CraftHolidayCrown then
		return false
	end
	if not self:_isRollPresentationPending() then
		return false
	end

	return self:_isHolidayCrownAutoCraftEnabled() and self:_isHolidayCrownReadyToCraft()
end

function TutorialController:_shouldHoldPostRollState(state: any): boolean
	if typeof(state) ~= "table" or state.stepId ~= TutorialConfig.Steps.EquipBodyPart then
		return false
	end
	if not self:_isRollPresentationPending() then
		return false
	end

	local activeState = self._activeState
	local activeStepId = if typeof(activeState) == "table" then activeState.stepId else self._currentStepId
	return activeStepId == TutorialConfig.Steps.RollFree
end

function TutorialController:_releasePendingPostRollStateIfReady(): boolean
	local pendingState = self._pendingPostRollState
	if typeof(pendingState) ~= "table" then
		return false
	end
	if self:_isRollPresentationPending() then
		return false
	end

	self._pendingPostRollState = nil
	self:_applyState(pendingState)
	return true
end

function TutorialController:_shouldHoldPostChestState(state: any): boolean
	if typeof(state) ~= "table" or state.stepId ~= TutorialConfig.Steps.UseLuckPotion then
		return false
	end
	if not self:_isChestPresentationActive() then
		return false
	end

	local activeState = self._activeState
	return typeof(activeState) == "table" and activeState.stepId == TutorialConfig.Steps.ClaimDailyChest
end

function TutorialController:_resolveChestOpeningSpotlight(): (GuiObject?, string, boolean)
	if self:_isChestPresentationActive() then
		return nil, "Open your chest.", false
	end

	return nil, TutorialConfig.TextByStepId[TutorialConfig.Steps.ClaimDailyChest] or "", false
end

function TutorialController:_resolveEquipBodyPartSpotlight(): (GuiObject?, string, boolean)
	local skipButton = RollController:GetTutorialTarget("rollResultSkipButton")
	if skipButton then
		return skipButton, "Close the roll result.", true
	end

	if not self:_isInventoryOpen() then
		return InventoryController:GetTutorialTarget("inventoryButton"), "Open Inventory.", true
	end

	if typeof(InventoryController.PrepareTutorialTarget) == "function" then
		InventoryController:PrepareTutorialTarget("bodyPart")
	end

	local actionButton = InventoryController:GetTutorialTarget("bodyPartAction")
	if actionButton then
		return actionButton, "Press Equip.", true
	end

	local row = InventoryController:GetTutorialTarget("bodyPartRow")
	if row then
		return row, "Select your new body part.", true
	end

	return nil, "Loading your new body part.", false
end

function TutorialController:_resolveEquipAccessorySpotlight(): (GuiObject?, string, boolean)
	if self:_isCraftingOpen() then
		local closeButton = CraftingController:GetTutorialTarget("closeButton")
		return closeButton, "Close Crafting.", closeButton ~= nil
	end

	if not self:_isInventoryOpen() then
		return InventoryController:GetTutorialTarget("inventoryButton"), "Open Inventory.", true
	end

	local actionButton = InventoryController:GetTutorialTarget("headAccessoryAction")
	if actionButton then
		return actionButton, "Equip Holiday Crown.", true
	end

	local row = InventoryController:GetTutorialTarget("holidayCrownRow")
	if row then
		return row, "Select Holiday Crown.", true
	end

	return InventoryController:GetTutorialTarget("headAccessoryFilter"), "Open Head Accessories.", true
end

function TutorialController:_resolveUsePotionSpotlight(): (GuiObject?, string, boolean)
	if not self:_isInventoryOpen() then
		return InventoryController:GetTutorialTarget("inventoryButton"), "Open Inventory.", true
	end

	if typeof(InventoryController.PrepareTutorialTarget) == "function" then
		InventoryController:PrepareTutorialTarget("luckPotion")
	end

	local actionButton = InventoryController:GetTutorialTarget("potionAction")
	if actionButton then
		return actionButton, "Use Luck Potion I.", true
	end

	local row = InventoryController:GetTutorialTarget("luckPotionRow")
	if row then
		return row, "Select Luck Potion I.", true
	end

	local potionFilter = InventoryController:GetTutorialTarget("potionFilter")
	if potionFilter then
		return potionFilter, "Open Potions.", true
	end

	return nil, "Finding Luck Potion I.", false
end

function TutorialController:_resolveRoll2Spotlight(): (GuiObject?, string, boolean)
	if self:_isInventoryOpen() then
		return InventoryController:GetTutorialTarget("closeButton"), "Close Inventory.", true
	end

	if typeof(RollController.PrepareTutorialTarget) == "function" then
		RollController:PrepareTutorialTarget("roll2Selection")
	end

	local roll2Entry = RollController:GetTutorialTarget("roll2Entry")
	if roll2Entry then
		return roll2Entry, "Choose Roll 2.", true
	end

	return RollController:GetTutorialTarget("rollDropdownButton"), "Open the roll menu.", true
end

function TutorialController:_resolveAppraisalSpotlight(): (GuiObject?, string, boolean)
	if not self:_isAppraisalOpen() then
		local appraisalOpenChoice, appraiserDialogueOpen = resolveAppraiserDialogueChoiceTarget()
		if appraisalOpenChoice then
			return appraisalOpenChoice, "Open the appraisal table.", true
		end
		if appraiserDialogueOpen then
			return nil, "Open the appraisal table.", false
		end

		return nil, TutorialConfig.TextByStepId[TutorialConfig.Steps.GoAppraise] or "", false
	end

	local confirmationFrame = ConfirmationWarning.GetTutorialTarget("frame")
	if confirmationFrame then
		return confirmationFrame, "Confirm appraisal.", false
	end

	local confirmButton = ConfirmationWarning.GetTutorialTarget("confirmButton")
	if confirmButton then
		return confirmButton, "Confirm appraisal.", true
	end

	local messageRoot = AppraisalController:GetTutorialTarget("messageRoot")
	if messageRoot then
		return messageRoot, "Close the appraisal result.", false
	end

	local messageClose = AppraisalController:GetTutorialTarget("messageClose")
	if messageClose then
		return messageClose, "Close the appraisal result.", true
	end

	local appraiseButton = AppraisalController:GetTutorialTarget("appraiseButton")
	if appraiseButton then
		return appraiseButton, "Appraise your body part.", true
	end

	return AppraisalController:GetTutorialTarget("firstEquippedSlot"), "Select an equipped body part.", true
end

function TutorialController:_resolveBlockingAppraisalResultSpotlight(): (GuiObject?, string, boolean)
	local confirmationFrame = ConfirmationWarning.GetTutorialTarget("frame")
	if confirmationFrame then
		return confirmationFrame, "Confirm appraisal.", false
	end

	local confirmButton = ConfirmationWarning.GetTutorialTarget("confirmButton")
	if confirmButton then
		return confirmButton, "Confirm appraisal.", true
	end

	local messageRoot = AppraisalController:GetTutorialTarget("messageRoot")
	if messageRoot then
		return messageRoot, "Close the appraisal result.", false
	end

	local messageClose = AppraisalController:GetTutorialTarget("messageClose")
	if messageClose then
		return messageClose, "Close the appraisal result.", true
	end

	if self:_isAppraisalOpen() then
		local closeButton = AppraisalController:GetTutorialTarget("closeButton")
		return closeButton, "Close Appraisal.", closeButton ~= nil
	end

	return nil, "", false
end

function TutorialController:_resolveCraftingSpotlight(stepId: string): (GuiObject?, string, boolean)
	if self:_isHolidayCrownAutoCraftEnabled() then
		if self:_isHolidayCrownReadyToCraft() then
			if not self:_isCraftingOpen() then
				return nil, "Holiday Crown is ready. Go back to Crafting and press Craft.", false
			end

			local recipeRow = CraftingController:GetTutorialTarget("holidayCrownRecipe")
			if recipeRow then
				return recipeRow, "Select Holiday Crown.", true
			end

			local openRecipeButton = CraftingController:GetTutorialTarget("openRecipe")
			if openRecipeButton then
				return openRecipeButton, "Open Holiday Crown recipe.", true
			end

			local craftButton = CraftingController:GetTutorialTarget("craftButton")
			if craftButton then
				return craftButton, "Press Craft.", true
			end

			return CraftingController:GetTutorialTarget("accessoriesFilter"), "Show accessories.", true
		end

		if self:_isCraftingOpen() then
			local closeButton = CraftingController:GetTutorialTarget("closeButton")
			return closeButton, "Close Crafting, then keep rolling.", closeButton ~= nil
		end
		return nil, TutorialConfig.TextByStepId[stepId] or "", false
	end

	if not self:_isCraftingOpen() then
		return nil, TutorialConfig.TextByStepId[stepId] or "", false
	end

	local autoCraftButton = CraftingController:GetTutorialTarget("autoCraft")
	if autoCraftButton then
		return autoCraftButton, "Turn on Auto Craft.", true
	end

	local recipeRow = CraftingController:GetTutorialTarget("holidayCrownRecipe")
	if recipeRow then
		return recipeRow, "Select Holiday Crown.", true
	end

	return CraftingController:GetTutorialTarget("accessoriesFilter"), "Show accessories.", true
end

function TutorialController:_resolveSpotlight(state: any): (GuiObject?, string, boolean)
	local stepId = state.stepId
	if stepId == TutorialConfig.Steps.Welcome then
		return nil, TutorialConfig.TextByStepId[stepId] or "", false
	elseif stepId == TutorialConfig.Steps.RollFree then
		return RollController:GetTutorialTarget("rollButton"), "Press Roll.", true
	elseif stepId == TutorialConfig.Steps.EquipBodyPart then
		return self:_resolveEquipBodyPartSpotlight()
	elseif stepId == TutorialConfig.Steps.SelectRoll2 then
		return self:_resolveRoll2Spotlight()
	elseif stepId == TutorialConfig.Steps.PaidRolls then
		return RollController:GetTutorialTarget("rollButton"), formatPaidRollText(state), true
	elseif stepId == TutorialConfig.Steps.GoAppraise then
		return self:_resolveAppraisalSpotlight()
	elseif stepId == TutorialConfig.Steps.GoCrafting or stepId == TutorialConfig.Steps.CraftHolidayCrown then
		local target, text, captureInput = self:_resolveBlockingAppraisalResultSpotlight()
		if target or text ~= "" then
			return target, text, captureInput
		end
		return self:_resolveCraftingSpotlight(stepId)
	elseif stepId == TutorialConfig.Steps.EquipHolidayCrown then
		return self:_resolveEquipAccessorySpotlight()
	elseif stepId == TutorialConfig.Steps.ClaimDailyChest then
		return self:_resolveChestOpeningSpotlight()
	elseif stepId == TutorialConfig.Steps.UseLuckPotion then
		return self:_resolveUsePotionSpotlight()
	end

	return nil, TutorialConfig.TextByStepId[stepId] or "", false
end

function TutorialController:_syncSpotlight()
	if typeof(self._pendingPostRollState) == "table" then
		if self:_releasePendingPostRollStateIfReady() then
			return
		end

		self:_showRollPresentationHold()
		return
	end

	if self._chestReturnTextActive == true then
		self:_clearSpotlight()
		return
	end

	local state = self._activeState
	if typeof(state) ~= "table" or state.completed == true then
		self._holidayCrownReadyRollHoldActive = false
		self:_clearSpotlight()
		return
	end
	if self:_shouldHoldHolidayCrownReadyForRollReveal(state) then
		self._holidayCrownReadyRollHoldActive = true
		self:_showRollPresentationHold()
		return
	elseif self._holidayCrownReadyRollHoldActive == true then
		self._holidayCrownReadyRollHoldActive = false
		self:_applyObjective(state.stepId)
	end

	local ok, target, text, captureInput = pcall(function()
		return self:_resolveSpotlight(state)
	end)
	if not ok then
		local fallbackText = if state.stepId == TutorialConfig.Steps.PaidRolls
			then formatPaidRollText(state)
			else TutorialConfig.TextByStepId[state.stepId] or ""
		self:_setTutorialText(fallbackText)
		self:_clearSpotlight()
		return
	end

	self:_setTutorialText(text)
	if self:_isTargetUsable(target) then
		self:_activateSpotlight(target, captureInput == true)
	else
		self:_clearSpotlight()
	end
end

function TutorialController:_startSpotlightLoop()
	if self._spotlightLoopStarted == true then
		return
	end

	self._spotlightLoopStarted = true
	task.spawn(function()
		while self._started == true do
			self:_syncSpotlight()
			task.wait(0.2)
		end
	end)
end

function TutorialController:_applyObjective(stepId: string)
	if self:_shouldHoldHolidayCrownReadyForRollReveal(stepId) then
		ObjectiveGuideController.ClearObjective(OBJECTIVE_ID)
	elseif stepId == TutorialConfig.Steps.GoAppraise then
		ObjectiveGuideController.ShowObjective(OBJECTIVE_ID, "Workspace.Appraiser.Appraiser.HumanoidRootPart", {
			fallbackTargetPaths = {
				"Workspace.Appraiser",
				"Workspace.Merchant.Appraiser.HumanoidRootPart",
			},
			projectTargetToGround = false,
		})
	elseif stepId == TutorialConfig.Steps.GoCrafting
		or (
			stepId == TutorialConfig.Steps.CraftHolidayCrown
			and (not self:_isHolidayCrownAutoCraftEnabled() or self:_isHolidayCrownReadyToCraft())
		)
	then
		ObjectiveGuideController.ShowObjective(OBJECTIVE_ID, "Workspace.Crafting.Craftsman.HumanoidRootPart", {
			fallbackTargetPath = "Workspace.Crafting",
			projectTargetToGround = false,
		})
	else
		ObjectiveGuideController.ClearObjective(OBJECTIVE_ID)
	end
end

function TutorialController:_applyState(rawState: any)
	local state = TutorialState.Normalize(rawState)
	if self:_shouldHoldPostRollState(state) then
		self._pendingPostRollState = state
		self:_showRollPresentationHold()
		return
	end
	if self:_shouldHoldPostChestState(state) then
		self._pendingPostChestState = state
		self:_syncSpotlight()
		return
	end
	self._pendingPostRollState = nil

	if state.completed == true then
		self._activeState = state
		self._currentStepId = state.stepId
		self._pendingPostRollState = nil
		self._pendingPostChestState = nil
		self:_setTutorialText("")
		ObjectiveGuideController.ClearObjective(OBJECTIVE_ID)
		self:_clearSpotlight()
		return
	end

	local stepId = state.stepId
	self._activeState = state
	self._currentStepId = stepId
	self:_applyObjective(stepId)
	if stepId == TutorialConfig.Steps.Welcome then
		self:_startWelcomeIntentListeners()
	else
		self:_disconnectWelcomeIntentListeners()
		self:_requestAdvanceRefresh(stepId)
	end
	self:_syncSpotlight()

	if stepId == TutorialConfig.Steps.ClaimDailyChest then
		self:_claimTutorialChest()
	end
end

function TutorialController:_refreshFromServer()
	local getStateRemote = resolveTutorialRemote("GetTutorialState")
	if not getStateRemote then
		return
	end

	local ok, result = pcall(function()
		return getStateRemote:InvokeServer()
	end)
	if ok and typeof(result) == "table" and typeof(result.state) == "table" then
		self:_applyState(result.state)
	end
end

function TutorialController:OnStart()
	if self._started == true then
		return
	end
	self._started = true

	if PlaceProfile.GetActiveProfile().id ~= "main" then
		return
	end

	task.spawn(function()
		waitForPlayerData()
		waitForLoadingScreenDismissed()
		TutorialTextGui.Init(LOCAL_PLAYER:WaitForChild("PlayerGui"))
		self:_startSpotlightLoop()
		self:_applyState(DataController:Get("tutorial"))
		self:_refreshFromServer()

		DataController.DataUpdated:Connect(function(key: string)
			if key == "tutorial" then
				self:_applyState(DataController:Get("tutorial"))
			elseif key == "craftingProgress" and self._currentStepId == TutorialConfig.Steps.CraftHolidayCrown then
				self:_applyObjective(self._currentStepId)
				self:_syncSpotlight()
			end
		end)

		local updatedRemote = resolveTutorialUpdatedRemote()
		if updatedRemote then
			updatedRemote.OnClientEvent:Connect(function(state: any)
				self:_applyState(state)
			end)
		end
	end)
end

return TutorialController
