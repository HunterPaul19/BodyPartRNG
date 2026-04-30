local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")

local FrameController = require(script.Parent.FrameController)
local UIController = require(script.Parent.UIController)

local LOCAL_PLAYER = Players.LocalPlayer
local WINDOW_NAME = "RobuxStore"

local StoreController = {}

function StoreController:_ensureState()
	if self._started then
		return
	end

	self._started = true
	self._root = nil
	self._playerGui = nil
	self._ui = {}
	self._openButtonBound = false
	self._fullUiReady = false
end

function StoreController:_bindOpenButton(openButton: GuiButton)
	UIController:CreateButton(openButton, function()
		self:_ensureFullUi(self._playerGui or LOCAL_PLAYER:WaitForChild("PlayerGui"))
		FrameController:ToggleFrame(WINDOW_NAME)
	end)
end

function StoreController:_cacheOpenButton(playerGui: PlayerGui)
	local mainInterface = playerGui:WaitForChild("MainInterface", 30)
	if not (mainInterface and mainInterface:IsA("ScreenGui")) then
		Logger.Error("PlayerGui.MainInterface is missing.")
	end

	local openButton = mainInterface:WaitForChild("Main", 30):WaitForChild("ExtraButtons", 30):WaitForChild("Store", 30)
	if not (openButton and openButton:IsA("GuiButton")) then
		Logger.Error("Store open button is missing.")
	end

	self._ui.openButton = openButton
end

function StoreController:_cacheUi(playerGui: PlayerGui)
	local mainInterface = playerGui:WaitForChild("MainInterface", 30)
	local modalRoot = playerGui:WaitForChild("ModalRoot", 30)
	if not (mainInterface and mainInterface:IsA("ScreenGui")) then
		Logger.Error("PlayerGui.MainInterface is missing.")
	end
	if not (modalRoot and modalRoot:IsA("ScreenGui")) then
		Logger.Error("PlayerGui.ModalRoot is missing.")
	end

	local storeRoot = modalRoot:WaitForChild(WINDOW_NAME, 30)
	local openButton = mainInterface:WaitForChild("Main", 30):WaitForChild("ExtraButtons", 30):WaitForChild("Store", 30)
	if not (storeRoot and storeRoot:IsA("GuiObject") and openButton and openButton:IsA("GuiButton")) then
		Logger.Error("Store UI hierarchy is missing required instances.")
	end

	self._root = storeRoot
	self._ui = {
		openButton = openButton,
	}
end

function StoreController:_ensureFullUi(playerGui: PlayerGui)
	if self._fullUiReady then
		return
	end

	self:_cacheUi(playerGui)
	self._fullUiReady = true
end

function StoreController:OnStart()
	self:_ensureState()

	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	self._playerGui = playerGui
	self:_cacheOpenButton(playerGui)

	if not self._openButtonBound then
		self:_bindOpenButton(self._ui.openButton)
		self._openButtonBound = true
	end
end

return StoreController
