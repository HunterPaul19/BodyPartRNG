local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local FrameController = require(script.Parent.FrameController)
local InventoryController = require(script.Parent.InventoryController)
local ObjectiveGuideController = require(script.Parent.ObjectiveGuideController)
local RollController = require(script.Parent.RollController)
local DataController = require(script.Parent.DataController)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)
local ScreenDarkener = require(ReplicatedStorage.Shared.UI.ScreenDarkener)
local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
local TutorialState = require(ReplicatedStorage.Shared.Character.TutorialState)
local TutorialTextGui = require(ReplicatedStorage.Shared.UI.TutorialTextGui)

local LOCAL_PLAYER = Players.LocalPlayer
local REMOTE_TIMEOUT = 30
local OBJECTIVE_ID = "new_player_tutorial"

local TutorialController = {
	_started = false,
	_currentStepId = nil,
	_pendingPostRollState = nil,
	_refreshingAdvance = false,
	_lastAdvanceRefreshStepId = nil,
	_activeState = nil,
	_spotlightLoopStarted = false,
	_darkener = nil,
	_spotlightTarget = nil,
	_spotlightActive = false,
	_lastText = nil,
	_welcomeInputConnections = {},
	_welcomeIntentListening = false,
	_welcomeAdvanceRequested = false,
}

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

function TutorialController:_isRollPresentationPending(): boolean
	return typeof(RollController.IsRollPresentationPending) == "function"
		and RollController:IsRollPresentationPending() == true
end

function TutorialController:_showRollPresentationHold()
	self:_setTutorialText("Finish your roll.")
	self:_clearSpotlight()
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

function TutorialController:_resolveSpotlight(state: any): (GuiObject?, string, boolean)
	local stepId = state.stepId
	if stepId == TutorialConfig.Steps.Welcome then
		return nil, TutorialConfig.TextByStepId[stepId] or "", false
	elseif stepId == TutorialConfig.Steps.RollFree then
		return RollController:GetTutorialTarget("rollButton"), "Press Roll.", true
	elseif stepId == TutorialConfig.Steps.EquipBodyPart then
		return self:_resolveEquipBodyPartSpotlight()
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

	local state = self._activeState
	if typeof(state) ~= "table" or state.completed == true then
		self:_clearSpotlight()
		return
	end

	local ok, target, text, captureInput = pcall(function()
		return self:_resolveSpotlight(state)
	end)
	if not ok then
		self:_setTutorialText(TutorialConfig.TextByStepId[state.stepId] or "")
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

function TutorialController:_applyState(rawState: any)
	local state = TutorialState.Normalize(rawState)
	if self:_shouldHoldPostRollState(state) then
		self._pendingPostRollState = state
		self:_showRollPresentationHold()
		return
	end
	self._pendingPostRollState = nil

	if state.completed == true then
		self._activeState = state
		self._currentStepId = state.stepId
		self:_disconnectWelcomeIntentListeners()
		self:_setTutorialText("")
		ObjectiveGuideController.ClearObjective(OBJECTIVE_ID)
		self:_clearSpotlight()
		return
	end

	local stepId = state.stepId
	self._activeState = state
	self._currentStepId = stepId
	ObjectiveGuideController.ClearObjective(OBJECTIVE_ID)
	if stepId == TutorialConfig.Steps.Welcome then
		self:_startWelcomeIntentListeners()
	else
		self:_disconnectWelcomeIntentListeners()
		self:_requestAdvanceRefresh(stepId)
	end
	self:_syncSpotlight()
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
