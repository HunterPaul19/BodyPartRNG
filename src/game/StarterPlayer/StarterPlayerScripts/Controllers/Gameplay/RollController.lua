local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")

local LOCAL_PLAYER = Players.LocalPlayer
local GUI_BIND_TIMEOUT_SECONDS = 30
local GUI_BIND_RETRY_DELAY_SECONDS = 1

local RollController = {}

local function resolveGuiControlsModule(): ModuleScript?
	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	local mainInterface = playerGui:WaitForChild("MainInterface", GUI_BIND_TIMEOUT_SECONDS)
	if not (mainInterface and mainInterface:IsA("ScreenGui")) then
		return nil
	end

	local rollPanel = mainInterface:WaitForChild("Roll", GUI_BIND_TIMEOUT_SECONDS)
	if not (rollPanel and rollPanel:IsA("Frame")) then
		return nil
	end

	local guiControlsModule = rollPanel:WaitForChild("GUIControls", GUI_BIND_TIMEOUT_SECONDS)
	if not (guiControlsModule and guiControlsModule:IsA("ModuleScript")) then
		return nil
	end

	return guiControlsModule
end

function RollController:_bindGuiControlsAsync()
	while self._started and not self._guiControls do
		local guiControlsModule = resolveGuiControlsModule()
		if guiControlsModule then
			local ok, guiControls = pcall(require, guiControlsModule)
			if ok and typeof(guiControls) == "table" then
				self._guiControls = guiControls
				Logger.Print(string.format(
					"[RollController] Initialized rolling HUD from %s",
					guiControlsModule:GetFullName()
				))
				return
			end

			Logger.Warn(string.format(
				"[RollController] Failed to require rolling HUD controls: %s",
				tostring(guiControls)
			))
		else
			Logger.Warn("[RollController] Rolling HUD controls are not available yet; retrying.")
		end

		task.wait(GUI_BIND_RETRY_DELAY_SECONDS)
	end
end

function RollController:OnStart()
	if self._started then
		return
	end

	self._started = true
	task.spawn(function()
		self:_bindGuiControlsAsync()
	end)
end

function RollController:GetTutorialTarget(targetId: string): GuiObject?
	if not self._guiControls then
		return nil
	end
	if typeof(self._guiControls.GetTutorialTarget) ~= "function" then
		return nil
	end

	return self._guiControls:GetTutorialTarget(targetId)
end

function RollController:PrepareTutorialTarget(targetId: string): boolean
	if not self._guiControls then
		return false
	end
	if typeof(self._guiControls.PrepareTutorialTarget) ~= "function" then
		return false
	end

	return self._guiControls:PrepareTutorialTarget(targetId) == true
end

function RollController:IsRollPresentationPending(): boolean
	if not self._guiControls then
		return false
	end
	if typeof(self._guiControls.IsRollPresentationPending) ~= "function" then
		return false
	end

	return self._guiControls:IsRollPresentationPending() == true
end

function RollController:GetSelectedRollTypeId(): string?
	if not self._guiControls then
		return nil
	end
	if typeof(self._guiControls.GetSelectedRollTypeId) ~= "function" then
		return nil
	end

	local rollTypeId = self._guiControls:GetSelectedRollTypeId()
	return if typeof(rollTypeId) == "string" then rollTypeId else nil
end

return RollController
