local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataController = require(script.Parent.DataController)
local FrameController = require(script.Parent.FrameController)
local UIController = require(script.Parent.UIController)
local RollingConfig = require(ReplicatedStorage.Shared.Config.RollingConfig)
local ToggleSoundUtil = require(ReplicatedStorage.Shared.Audio.ToggleSoundUtil)

local LOCAL_PLAYER = Players.LocalPlayer
local WINDOW_NAME = "AutoSell"
local AUTO_SELL_DATA_KEY = "autoSellRarities"
local CUTSCENE_DATA_KEY = "cutsceneRarities"
local REMOTES_FOLDER_NAME = "Remotes"
local ROLLING_FOLDER_NAME = "Rolling"
local TOGGLE_AUTO_SELL_RARITY_REMOTE_NAME = "ToggleAutoSellRarity"
local TOGGLE_CUTSCENE_RARITY_REMOTE_NAME = "ToggleCutsceneRarity"

type RarityButtonSet = {
	disabled: GuiButton,
	enabled: GuiButton,
	cutsceneOff: GuiButton,
	cutsceneOn: GuiButton,
}

local AutoSellController = {}

function AutoSellController:_ensureState()
	if self._started then
		return
	end

	self._started = true
	self._ui = {
		openButton = nil,
		rarityButtons = {},
	}
	self._autoSellToggleRemote = nil :: RemoteFunction?
	self._cutsceneToggleRemote = nil :: RemoteFunction?
end

function AutoSellController:_getAutoSellState(): { [string]: boolean }
	return RollingConfig.NormalizeAutoSellState(DataController:Get(AUTO_SELL_DATA_KEY))
end

function AutoSellController:_getCutsceneState(): { [string]: boolean }
	return RollingConfig.NormalizeCutsceneState(DataController:Get(CUTSCENE_DATA_KEY))
end

function AutoSellController:_ensureRemotes(): boolean
	if self._autoSellToggleRemote and self._cutsceneToggleRemote then
		return true
	end

	local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if not (remotesFolder and remotesFolder:IsA("Folder")) then
		return false
	end

	local rollingFolder = remotesFolder:FindFirstChild(ROLLING_FOLDER_NAME)
	if not (rollingFolder and rollingFolder:IsA("Folder")) then
		return false
	end

	local toggleRemote = rollingFolder:FindFirstChild(TOGGLE_AUTO_SELL_RARITY_REMOTE_NAME)
	local cutsceneToggleRemote = rollingFolder:FindFirstChild(TOGGLE_CUTSCENE_RARITY_REMOTE_NAME)
	if not (toggleRemote and toggleRemote:IsA("RemoteFunction")) then
		return false
	end
	if not (cutsceneToggleRemote and cutsceneToggleRemote:IsA("RemoteFunction")) then
		return false
	end

	self._autoSellToggleRemote = toggleRemote
	self._cutsceneToggleRemote = cutsceneToggleRemote
	return true
end

function AutoSellController:_syncRarityButtons()
	local autoSellState = self:_getAutoSellState()
	local cutsceneState = self:_getCutsceneState()

	for rarity, buttonSet: RarityButtonSet in pairs(self._ui.rarityButtons) do
		local isEnabled = autoSellState[rarity] == true
		local cutscenesEnabled = cutsceneState[rarity] ~= false
		buttonSet.enabled.Visible = isEnabled
		buttonSet.enabled.Active = isEnabled
		buttonSet.disabled.Visible = not isEnabled
		buttonSet.disabled.Active = not isEnabled
		buttonSet.cutsceneOn.Visible = cutscenesEnabled
		buttonSet.cutsceneOn.Active = cutscenesEnabled
		buttonSet.cutsceneOff.Visible = not cutscenesEnabled
		buttonSet.cutsceneOff.Active = not cutscenesEnabled
	end
end

function AutoSellController:_toggleRarity(rarity: string, enabled: boolean)
	if not self:_ensureRemotes() then
		return
	end

	local ok, result = pcall(function()
		return self._autoSellToggleRemote:InvokeServer({
			rarity = rarity,
			enabled = enabled == true,
		})
	end)

	if not ok then
		Logger.Warn(string.format("[AutoSellController] Failed to toggle %s auto-sell: %s", rarity, tostring(result)))
		return
	end

	if typeof(result) ~= "table" then
		return
	end

	if result.ok ~= true then
		Logger.Warn(string.format("[AutoSellController] Failed to toggle %s auto-sell: %s", rarity, tostring(result.message)))
		return
	end

	ToggleSoundUtil.PlayToggle(enabled == true)
end

function AutoSellController:_toggleCutsceneRarity(rarity: string, enabled: boolean)
	if not self:_ensureRemotes() then
		return
	end

	local ok, result = pcall(function()
		return self._cutsceneToggleRemote:InvokeServer({
			rarity = rarity,
			enabled = enabled ~= false,
		})
	end)

	if not ok then
		Logger.Warn(string.format("[AutoSellController] Failed to toggle %s cutscenes: %s", rarity, tostring(result)))
		return
	end

	if typeof(result) ~= "table" then
		return
	end

	if result.ok ~= true then
		Logger.Warn(string.format("[AutoSellController] Failed to toggle %s cutscenes: %s", rarity, tostring(result.message)))
		return
	end

	ToggleSoundUtil.PlayToggle(enabled == true)
end

function AutoSellController:_bindOpenButton(openButton: GuiButton)
	UIController:CreateButton(openButton, function()
		FrameController:ToggleFrame(WINDOW_NAME)
	end)
end

function AutoSellController:_bindRarityButtons()
	for rarity, buttonSet: RarityButtonSet in pairs(self._ui.rarityButtons) do
		ToggleSoundUtil.MarkToggleButton(buttonSet.disabled)
		ToggleSoundUtil.MarkToggleButton(buttonSet.enabled)
		ToggleSoundUtil.MarkToggleButton(buttonSet.cutsceneOff)
		ToggleSoundUtil.MarkToggleButton(buttonSet.cutsceneOn)

		UIController:CreateButton(buttonSet.disabled, function()
			self:_toggleRarity(rarity, true)
		end)

		UIController:CreateButton(buttonSet.enabled, function()
			self:_toggleRarity(rarity, false)
		end)

		UIController:CreateButton(buttonSet.cutsceneOff, function()
			self:_toggleCutsceneRarity(rarity, true)
		end)

		UIController:CreateButton(buttonSet.cutsceneOn, function()
			self:_toggleCutsceneRarity(rarity, false)
		end)
	end
end

function AutoSellController:_cacheUi(playerGui: PlayerGui)
	local mainInterface = playerGui:WaitForChild("MainInterface", 30)
	local modalRoot = playerGui:WaitForChild("ModalRoot", 30)
	if not (mainInterface and mainInterface:IsA("ScreenGui")) then
		Logger.Error("PlayerGui.MainInterface is missing.")
	end
	if not (modalRoot and modalRoot:IsA("ScreenGui")) then
		Logger.Error("PlayerGui.ModalRoot is missing.")
	end

	local autoSellRoot = modalRoot:WaitForChild(WINDOW_NAME, 30)
	local main = mainInterface:WaitForChild("Main", 30)
	local buttonHolder = main:FindFirstChild("ButtonHolder")
	local openButton = if buttonHolder then buttonHolder:FindFirstChild("AutoSellButton") else nil
	if openButton == nil then
		openButton = main:WaitForChild("AutoSellButton", 30)
	end
	local scrollingFrame = autoSellRoot:WaitForChild("ScrollingFrame", 30)

	if not (
		autoSellRoot:IsA("GuiObject")
		and openButton:IsA("GuiButton")
		and scrollingFrame:IsA("ScrollingFrame")
	) then
		Logger.Error("Auto-sell UI hierarchy is missing required instances.")
	end

	local rarityButtons = {}
	for _, rarity in ipairs(RollingConfig.DisplayRarityOrder) do
		local row = scrollingFrame:WaitForChild(rarity, 30)
		if row and row:IsA("GuiObject") then
			local disabledButton = row:WaitForChild("Disabled", 30)
			local enabledButton = row:WaitForChild("Enabled", 30)
			local cutsceneOffButton = row:WaitForChild("CutsceneToggleOFF", 30)
			local cutsceneOnButton = row:WaitForChild("CutsceneToggleON", 30)
			if
				disabledButton:IsA("GuiButton")
				and enabledButton:IsA("GuiButton")
				and cutsceneOffButton:IsA("GuiButton")
				and cutsceneOnButton:IsA("GuiButton")
			then
				rarityButtons[rarity] = {
					disabled = disabledButton,
					enabled = enabledButton,
					cutsceneOff = cutsceneOffButton,
					cutsceneOn = cutsceneOnButton,
				}
			end
		end
	end

	self._ui = {
		openButton = openButton,
		rarityButtons = rarityButtons,
	}
end

function AutoSellController:OnStart()
	self:_ensureState()

	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	self:_cacheUi(playerGui)
	self:_bindOpenButton(self._ui.openButton)
	self:_bindRarityButtons()
	self:_syncRarityButtons()

	DataController.DataReceived:Connect(function()
		self:_syncRarityButtons()
	end)

	DataController.DataUpdated:Connect(function(key)
		if key == AUTO_SELL_DATA_KEY or key == CUTSCENE_DATA_KEY then
			self:_syncRarityButtons()
		end
	end)

	task.spawn(function()
		while not self:_ensureRemotes() do
			task.wait(1)
		end
	end)
end

return AutoSellController
