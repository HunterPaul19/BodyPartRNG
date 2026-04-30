local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Common.Signal)

local LOCAL_PLAYER = Players.LocalPlayer
local MODAL_ROOT_NAME = "ModalRoot"
local SYSTEM_OVERLAYS_NAME = "SystemOverlays"
local FRAME_NAME = "ConfirmationFrame"
local WARNING_TEXT_NAME = "WarningText"
local CONFIRM_BUTTON_NAME = "Confirm"
local NEVERMIND_BUTTON_NAME = "Nevermind"
local MIN_MODAL_Z_INDEX = 20

type ConfirmationRequest = {
	resultSignal: any,
}

type CachedUi = {
	frame: GuiObject,
	warningText: TextLabel,
	confirmButton: GuiButton,
	nevermindButton: GuiButton,
}

local ConfirmationWarning = {
	_ui = nil :: CachedUi?,
	_currentRequest = nil :: ConfirmationRequest?,
	_boundFrame = nil :: GuiObject?,
	_authoredWarningText = nil :: string?,
}

local function shiftGuiTreeZIndex(root: Instance, delta: number)
	if delta == 0 then
		return
	end

	if root:IsA("GuiObject") then
		root.ZIndex += delta
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex += delta
		end
	end
end

function ConfirmationWarning:_getPlayerGui(): PlayerGui?
	if not LOCAL_PLAYER then
		return nil
	end

	return LOCAL_PLAYER:FindFirstChildOfClass("PlayerGui") or LOCAL_PLAYER:WaitForChild("PlayerGui", 5)
end

function ConfirmationWarning:_cacheUi(): CachedUi?
	if self._ui and self._ui.frame.Parent then
		return self._ui
	end

	local playerGui = self:_getPlayerGui()
	if not playerGui then
		return nil
	end

	local modalRoot = playerGui:FindFirstChild(MODAL_ROOT_NAME) or playerGui:WaitForChild(MODAL_ROOT_NAME, 5)
	if not (modalRoot and modalRoot:IsA("ScreenGui")) then
		return nil
	end

	local overlays = modalRoot:FindFirstChild(SYSTEM_OVERLAYS_NAME) or modalRoot:WaitForChild(SYSTEM_OVERLAYS_NAME, 5)
	if not (overlays and overlays:IsA("Folder")) then
		return nil
	end

	local frame = overlays:FindFirstChild(FRAME_NAME) or overlays:WaitForChild(FRAME_NAME, 5)
	if not (frame and frame:IsA("GuiObject")) then
		return nil
	end

	local warningText = frame:FindFirstChild(WARNING_TEXT_NAME) or frame:WaitForChild(WARNING_TEXT_NAME, 5)
	local confirmButton = frame:FindFirstChild(CONFIRM_BUTTON_NAME) or frame:WaitForChild(CONFIRM_BUTTON_NAME, 5)
	local nevermindButton = frame:FindFirstChild(NEVERMIND_BUTTON_NAME) or frame:WaitForChild(NEVERMIND_BUTTON_NAME, 5)
	if not (
		warningText
		and warningText:IsA("TextLabel")
		and confirmButton
		and confirmButton:IsA("GuiButton")
		and nevermindButton
		and nevermindButton:IsA("GuiButton")
	) then
		return nil
	end

	if frame.ZIndex < MIN_MODAL_Z_INDEX then
		shiftGuiTreeZIndex(frame, MIN_MODAL_Z_INDEX - frame.ZIndex)
	end

	self._authoredWarningText = warningText.Text
	frame.Visible = false

	self._ui = {
		frame = frame,
		warningText = warningText,
		confirmButton = confirmButton,
		nevermindButton = nevermindButton,
	}

	return self._ui
end

function ConfirmationWarning:_restoreAuthoredText()
	local ui = self:_cacheUi()
	if not ui then
		return
	end

	ui.warningText.Text = if typeof(self._authoredWarningText) == "string" then self._authoredWarningText else ""
end

function ConfirmationWarning:_resolveCurrent(result: boolean)
	local request = self._currentRequest
	if not request then
		return
	end

	self._currentRequest = nil

	local ui = self:_cacheUi()
	if ui then
		ui.frame.Visible = false
	end
	self:_restoreAuthoredText()

	request.resultSignal:Fire(result == true)
end

function ConfirmationWarning:_bindUi()
	local ui = self:_cacheUi()
	if not ui then
		return
	end

	if self._boundFrame == ui.frame then
		return
	end

	self._boundFrame = ui.frame

	ui.confirmButton.Activated:Connect(function()
		self:_resolveCurrent(true)
	end)

	ui.nevermindButton.Activated:Connect(function()
		self:_resolveCurrent(false)
	end)
end

function ConfirmationWarning.Prompt(message: string?): boolean
	local self = ConfirmationWarning

	self:_bindUi()

	local ui = self:_cacheUi()
	if not ui then
		return false
	end

	if self._currentRequest ~= nil then
		local previousRequest = self._currentRequest
		self._currentRequest = nil
		previousRequest.resultSignal:Fire(false)
	end

	local request = {
		resultSignal = Signal.new(),
	}
	self._currentRequest = request

	ui.warningText.Text = if typeof(message) == "string" and message ~= "" then message else (self._authoredWarningText or "")
	ui.frame.Visible = true

	return request.resultSignal:Wait() == true
end

function ConfirmationWarning.GetTutorialTarget(targetId: string): GuiObject?
	local self = ConfirmationWarning
	local ui = self:_cacheUi()
	if not ui or self._currentRequest == nil or ui.frame.Visible ~= true then
		return nil
	end

	if targetId == "frame" then
		return ui.frame
	end
	if targetId == "confirmButton" and ui.confirmButton.Visible == true and ui.confirmButton.Active == true then
		return ui.confirmButton
	end

	return nil
end

return ConfirmationWarning
