local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LOCAL_PLAYER = Players.LocalPlayer
local REMOTES_FOLDER_NAME = "Remotes"
local ROLLING_FOLDER_NAME = "Rolling"
local FINALIZE_AUTO_SELL_ROLL_REMOTE_NAME = "FinalizeAutoSellRoll"

local AutoSellRollController = {}

local function getFinalizeRemote(): RemoteFunction?
	local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if not (remotesFolder and remotesFolder:IsA("Folder")) then
		return nil
	end

	local rollingFolder = remotesFolder:FindFirstChild(ROLLING_FOLDER_NAME)
	if not (rollingFolder and rollingFolder:IsA("Folder")) then
		return nil
	end

	local finalizeRemote = rollingFolder:FindFirstChild(FINALIZE_AUTO_SELL_ROLL_REMOTE_NAME)
	if finalizeRemote and finalizeRemote:IsA("RemoteFunction") then
		return finalizeRemote
	end

	return nil
end

local function getRollGuiControls()
	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	local mainInterface = playerGui:WaitForChild("MainInterface", 30)
	if not (mainInterface and mainInterface:IsA("ScreenGui")) then
		return nil
	end

	local roll = mainInterface:WaitForChild("Roll", 30)
	if not (roll and roll:IsA("GuiObject")) then
		return nil
	end

	local guiControlsModule = roll:WaitForChild("GUIControls", 30)
	if not (guiControlsModule and guiControlsModule:IsA("ModuleScript")) then
		return nil
	end

	local ok, guiControls = pcall(require, guiControlsModule)
	if not ok or typeof(guiControls) ~= "table" then
		warn(string.format("[AutoSellRollController] Failed to require roll GUI controls: %s", tostring(guiControls)))
		return nil
	end

	return guiControls
end

local function getPendingAutoSellPayload(guiControls): ({ [string]: any }?)
	local rollResult = guiControls.CurrentRollResult
	if typeof(rollResult) ~= "table" or rollResult.pendingAutoSell ~= true or rollResult.skipPresentation == true then
		return nil
	end

	local ownedId = rollResult.ownedId
	if typeof(ownedId) ~= "string" or ownedId == "" then
		local ownedRecord = rollResult.ownedRecord
		if typeof(ownedRecord) == "table" then
			ownedId = ownedRecord.ownedId
		end
	end

	if typeof(ownedId) ~= "string" or ownedId == "" then
		return nil
	end

	return {
		ownedId = ownedId,
		keep = guiControls.CurrentRollResultEquipped == true,
	}
end

local function getEquipButton(): GuiButton?
	local playerGui = LOCAL_PLAYER:FindFirstChild("PlayerGui")
	if not playerGui then
		return nil
	end

	local mainInterface = playerGui:FindFirstChild("MainInterface")
	if not (mainInterface and mainInterface:IsA("ScreenGui")) then
		return nil
	end

	local roll = mainInterface:FindFirstChild("Roll")
	if not (roll and roll:IsA("GuiObject")) then
		return nil
	end

	local equipButton = roll:FindFirstChild("EquipButton")
	if equipButton and equipButton:IsA("GuiButton") then
		return equipButton
	end

	return nil
end

local function patchRollGuiControls(guiControls)
	if guiControls.__autoSellPatched == true then
		return
	end

	guiControls.__autoSellPatched = true
	guiControls.__autoSellFinalizeInFlight = false

	local originalRefreshEquipButton = guiControls.RefreshEquipButton
	local originalHideRollResults = guiControls.HideRollResults

	guiControls.RefreshEquipButton = function(self)
		originalRefreshEquipButton(self)

		local rollResult = self.CurrentRollResult
		if typeof(rollResult) ~= "table" or rollResult.pendingAutoSell ~= true or rollResult.skipPresentation == true then
			return
		end

		local equipButton = getEquipButton()
		if not (equipButton and equipButton.Visible) then
			return
		end

		if self.CurrentRollResultEquipped ~= true and type(self.SetEquipButtonText) == "function" then
			self:SetEquipButtonText("Equip to Keep")
		end
	end

	guiControls.HideRollResults = function(self)
		if self.__autoSellFinalizeInFlight == true then
			return
		end

		local payload = getPendingAutoSellPayload(self)
		if payload ~= nil then
			local finalizeRemote = getFinalizeRemote()
			if finalizeRemote then
				self.__autoSellFinalizeInFlight = true
				local ok, result = pcall(function()
					return finalizeRemote:InvokeServer(payload)
				end)
				self.__autoSellFinalizeInFlight = false

				if not ok then
					warn(string.format("[AutoSellRollController] Failed to finalize auto-sell roll: %s", tostring(result)))
				elseif typeof(result) == "table" then
					if type(self.ApplyRollingState) == "function" and typeof(result.state) == "table" then
						self:ApplyRollingState(result.state)
					end
					if result.ok ~= true then
						warn(string.format(
							"[AutoSellRollController] Auto-sell finalize returned an error: %s",
							tostring(result.message)
						))
					end
				end
			end
		end

		originalHideRollResults(self)
	end
end

function AutoSellRollController:OnStart()
	task.spawn(function()
		local guiControls = getRollGuiControls()
		if not guiControls then
			return
		end

		patchRollGuiControls(guiControls)
	end)
end

return AutoSellRollController
