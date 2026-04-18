local Players = game:GetService("Players")

local FrameController = require(script.Parent.FrameController)
local UIController = require(script.Parent.UIController)

local LOCAL_PLAYER = Players.LocalPlayer
local WINDOW_NAME = "Help"

local HelpController = {}

function HelpController:_ensureState()
	if self._started then
		return
	end

	self._started = true
	self._root = nil
	self._ui = {
		openButton = nil,
		closeButton = nil,
	}
end

function HelpController:_cacheUi(playerGui: PlayerGui)
	local mainInterface = playerGui:WaitForChild("MainInterface", 30)
	local modalRoot = playerGui:WaitForChild("ModalRoot", 30)
	if not (mainInterface and mainInterface:IsA("ScreenGui")) then
		error("PlayerGui.MainInterface is missing.")
	end
	if not (modalRoot and modalRoot:IsA("ScreenGui")) then
		error("PlayerGui.ModalRoot is missing.")
	end

	local helpRoot = modalRoot:WaitForChild(WINDOW_NAME, 30)
	local openButton = mainInterface:WaitForChild("Main", 30):WaitForChild("ExtraButtons", 30):WaitForChild(WINDOW_NAME, 30)
	local closeButton = helpRoot:WaitForChild("Topbar", 30):WaitForChild("CloseButton", 30)

	if not (
		helpRoot:IsA("GuiObject")
		and openButton:IsA("GuiButton")
		and closeButton:IsA("GuiButton")
	) then
		error("Help UI hierarchy is missing required instances.")
	end

	self._root = helpRoot
	self._ui = {
		openButton = openButton,
		closeButton = closeButton,
	}
end

function HelpController:_bindOpenButton(openButton: GuiButton)
	UIController:CreateButton(openButton, function()
		FrameController:ToggleFrame(WINDOW_NAME)
	end)
end

function HelpController:_bindCloseButton(closeButton: GuiButton)
	closeButton.Activated:Connect(function()
		FrameController:CloseFrame(WINDOW_NAME)
	end)
end

function HelpController:OnStart()
	self:_ensureState()

	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	self:_cacheUi(playerGui)
	self:_bindOpenButton(self._ui.openButton)
	self:_bindCloseButton(self._ui.closeButton)
end

return HelpController
