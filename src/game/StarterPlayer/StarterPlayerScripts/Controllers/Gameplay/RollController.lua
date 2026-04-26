local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")

local LOCAL_PLAYER = Players.LocalPlayer

local RollController = {}

function RollController:OnStart()
	if self._started then
		return
	end

	self._started = true

	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	local mainInterface = playerGui:WaitForChild("MainInterface", 30)
	if not (mainInterface and mainInterface:IsA("ScreenGui")) then
		Logger.Error("[RollController] PlayerGui.MainInterface is missing.", 0)
	end

	local rollPanel = mainInterface:WaitForChild("Roll", 30)
	if not (rollPanel and rollPanel:IsA("Frame")) then
		Logger.Error("[RollController] PlayerGui.MainInterface.Roll is missing.", 0)
	end

	local guiControlsModule = rollPanel:WaitForChild("GUIControls", 30)
	if not (guiControlsModule and guiControlsModule:IsA("ModuleScript")) then
		Logger.Error("[RollController] PlayerGui.MainInterface.Roll.GUIControls is missing.", 0)
	end

	self._guiControls = require(guiControlsModule)

	Logger.Print(string.format(
		"[RollController] Initialized rolling HUD from %s",
		guiControlsModule:GetFullName()
	))
end

return RollController
