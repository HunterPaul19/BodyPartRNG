local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)
local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)

local LOCAL_PLAYER = Players.LocalPlayer

local MainInterfaceController = {}

MainInterfaceController.OpenTwinf = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
MainInterfaceController.CloseTwinf = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
MainInterfaceController.PanelBlurName = "PanelBlur"
MainInterfaceController.PanelNames = {
	Main = "Main",
	Dialogue = "DialogueUI",
	Leaderboard = "Leaderboard",
	Roll = "Roll",
}

local MENU_OPEN_SOUND_NAME = "MenuOpen"
local MENU_CLOSE_SOUND_NAME = "MenuClose"

local function setGuiObjectEnabled(guiObject: GuiObject?, isEnabled: boolean)
	if not guiObject then
		return
	end

	guiObject.Visible = isEnabled
	guiObject.Active = isEnabled
	if guiObject:IsA("GuiButton") then
		guiObject.AutoButtonColor = isEnabled
	end
end

function MainInterfaceController:_ensureState()
	if self._started then
		return
	end

	self._playerGui = nil
	self._mainInterface = nil
	self._black = nil
	self._blur = nil
	self._panelInfo = {}
	self._started = true
end

function MainInterfaceController:_getPlayerGui(): PlayerGui
	self:_ensureState()

	if self._playerGui and self._playerGui.Parent == LOCAL_PLAYER then
		return self._playerGui
	end

	self._playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	return self._playerGui
end

function MainInterfaceController:_getBlur(): BlurEffect
	if self._blur and self._blur.Parent == game.Lighting then
		return self._blur
	end

	local existing = game.Lighting:FindFirstChild(self.PanelBlurName)
	if existing and existing:IsA("BlurEffect") then
		self._blur = existing
	else
		local blur = Instance.new("BlurEffect")
		blur.Parent = game.Lighting
		blur.Name = self.PanelBlurName
		blur.Size = 0
		self._blur = blur
	end

	return self._blur
end

function MainInterfaceController:_ensureUi()
	self:_ensureState()

	local playerGui = self:_getPlayerGui()
	local mainInterface = playerGui:WaitForChild("MainInterface", 30)
	if not (mainInterface and mainInterface:IsA("ScreenGui")) then
		Logger.Error("[MainInterfaceController] PlayerGui.MainInterface is missing.", 0)
	end

	if self._mainInterface == mainInterface and self._black and self._black.Parent == mainInterface then
		return
	end

	local black = mainInterface:WaitForChild("Black", 30)
	if not (black and black:IsA("Frame")) then
		Logger.Error("[MainInterfaceController] PlayerGui.MainInterface.Black is missing.", 0)
	end

	local panelInfo = {}
	for panelName, instanceName in pairs(self.PanelNames) do
		local panel = mainInterface:WaitForChild(instanceName, 30)
		if not (panel and panel:IsA("Frame")) then
			Logger.Error(string.format(
				"[MainInterfaceController] PlayerGui.MainInterface.%s is missing for panel '%s'.",
				instanceName,
				panelName
			), 0)
		end

		panelInfo[panelName] = {
			Frame = panel,
			Position = panel.Position,
			Size = panel.Size,
			currentlyTransitioning = false,
		}
	end

	self._mainInterface = mainInterface
	self._black = black
	self._panelInfo = panelInfo
	self:_getBlur()
	self:_applyProfileUiExclusions()
end

function MainInterfaceController:_applyProfileUiExclusions()
	for panelName, panel in pairs(self._panelInfo) do
		if not PlaceProfile.IsPanelEnabled(panelName) then
			panel.currentlyTransitioning = false
			panel.Frame.Visible = false
			panel.Frame.Active = false
		end
	end

	if not PlaceProfile.IsFeatureEnabled("rolling") then
		local mainPanel = self._panelInfo.Main and self._panelInfo.Main.Frame or nil
		if mainPanel then
			for _, childName in ipairs({ "RollButton", "QuickRoll", "AutoRoll", "AutoEquipBestButton", "AutoSellButton" }) do
				local child = mainPanel:FindFirstChild(childName, true)
				if child and child:IsA("GuiObject") then
					setGuiObjectEnabled(child, false)
				end
			end
		end

		local rollWarning = self._mainInterface and self._mainInterface:FindFirstChild("RollWarning")
		if rollWarning and rollWarning:IsA("GuiObject") then
			setGuiObjectEnabled(rollWarning, false)
		end
	end
end

function MainInterfaceController:_getPanel(panelName: string)
	self:_ensureUi()

	local found = self._panelInfo[panelName]
	assert(found, "panel " .. panelName .. " not found")
	return found
end

function MainInterfaceController:GetPanelVisibilitySnapshot(): { panels: { [string]: boolean }, blackTransparency: number, blurSize: number }
	self:_ensureUi()

	local snapshot = {
		panels = {},
		blackTransparency = self._black.BackgroundTransparency,
		blurSize = self:_getBlur().Size,
	}

	for key, panel in pairs(self._panelInfo) do
		snapshot.panels[key] = panel.Frame.Visible
	end

	return snapshot
end

function MainInterfaceController:RestorePanelVisibility(
	snapshot: { panels: { [string]: boolean }, blackTransparency: number, blurSize: number }?,
	excludedPanels: { [string]: boolean }?
)
	self:_ensureUi()

	if typeof(snapshot) ~= "table" then
		return
	end

	for key, isVisible in pairs(snapshot.panels) do
		if not PlaceProfile.IsPanelEnabled(key) or (excludedPanels and excludedPanels[key]) then
			continue
		end

		local panel = self._panelInfo[key]
		if panel then
			panel.currentlyTransitioning = false
			panel.Frame.Visible = isVisible
			panel.Frame.Position = panel.Position
			panel.Frame.Size = panel.Size
		end
	end

	self._black.BackgroundTransparency = snapshot.blackTransparency
	self:_getBlur().Size = snapshot.blurSize
end

function MainInterfaceController:OpenPanel(panelName: string, forceOpen: boolean?)
	self:_ensureUi()

	local black = self._black
	local blur = self:_getBlur()
	TweenService:Create(black, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { BackgroundTransparency = 0.7 }):Play()
	TweenService:Create(blur, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Size = 10 }):Play()

	task.spawn(function()
		local found = self:_getPanel(panelName)

		if found.currentlyTransitioning then
			if forceOpen then
				repeat
					task.wait()
				until not found.currentlyTransitioning
			else
				return
			end
		else
			found.currentlyTransitioning = true
		end

		if found.Frame.Visible and not forceOpen then
			found.currentlyTransitioning = false
			return
		end

		SoundUtil.Play(MENU_OPEN_SOUND_NAME)
		found.Frame.Visible = true

		local offsetPosition = UDim2.fromScale(found.Position.X.Scale, found.Position.Y.Scale * 1.1)
		found.Frame.Position = offsetPosition

		local offsetSize = UDim2.fromScale(found.Size.X.Scale * 0.8, found.Size.Y.Scale * 0.8)
		found.Frame.Size = offsetSize

		TweenService:Create(found.Frame, self.OpenTwinf, { Position = found.Position, Size = found.Size }):Play()

		task.delay(self.OpenTwinf.Time, function()
			found.currentlyTransitioning = false
		end)
	end)
end

function MainInterfaceController:ClosePanel(panelName: string, forceClose: boolean?)
	self:_ensureUi()

	local black = self._black
	local blur = self:_getBlur()
	TweenService:Create(black, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(blur, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Size = 0 }):Play()

	task.spawn(function()
		local found = self:_getPanel(panelName)

		if found.currentlyTransitioning then
			if forceClose then
				repeat
					task.wait()
				until not found.currentlyTransitioning
			else
				return
			end
		else
			found.currentlyTransitioning = true
		end

		if not found.Frame.Visible and not forceClose then
			found.currentlyTransitioning = false
			return
		end

		SoundUtil.Play(MENU_CLOSE_SOUND_NAME)
		found.Frame.Visible = true

		local offsetPosition = UDim2.fromScale(found.Position.X.Scale, found.Position.Y.Scale * 1.1)
		found.Frame.Position = found.Position

		local offsetSize = UDim2.fromScale(found.Size.X.Scale * 0.8, found.Size.Y.Scale * 0.8)
		found.Frame.Size = found.Size

		TweenService:Create(found.Frame, self.CloseTwinf, { Position = offsetPosition, Size = offsetSize }):Play()

		task.delay(self.CloseTwinf.Time, function()
			found.Frame.Visible = false
			found.currentlyTransitioning = false
		end)
	end)
end

function MainInterfaceController:TogglePanel(panelName: string, forceToggle: boolean)
	local found = self:_getPanel(panelName)
	if not found.Frame.Visible then
		self:OpenPanel(panelName, forceToggle)
	else
		self:ClosePanel(panelName, forceToggle)
	end
end

function MainInterfaceController:IsPanelVisible(panelName: string): boolean
	local found = self:_getPanel(panelName)
	return found.Frame.Visible
end

function MainInterfaceController:CloseAll()
	self:_ensureUi()

	for key in pairs(self._panelInfo) do
		self:ClosePanel(key)
	end
end

function MainInterfaceController:OpenExclusive(panelName: string)
	self:_ensureUi()

	local found = self:_getPanel(panelName)
	local hadOtherOpen = false

	for key, panel in pairs(self._panelInfo) do
		if key ~= panelName and panel.Frame.Visible then
			hadOtherOpen = true
			self:ClosePanel(key, true)
		end
	end

	if found.Frame.Visible and not hadOtherOpen then
		return
	end

	if hadOtherOpen then
		task.delay(self.CloseTwinf.Time, function()
			self:OpenPanel(panelName, true)
		end)
		return
	end

	self:OpenPanel(panelName, true)
end

function MainInterfaceController:HideMain()
	self:_ensureUi()
	self._mainInterface.Enabled = false
end

function MainInterfaceController:OpenMain()
	self:_ensureUi()
	self._mainInterface.Enabled = true
	self:_applyProfileUiExclusions()
end

function MainInterfaceController:OnStart()
	self:_ensureUi()

	local registeredPanels = {}
	for panelName in pairs(self._panelInfo) do
		table.insert(registeredPanels, panelName)
	end
	table.sort(registeredPanels)

	Logger.Print(string.format(
		"[MainInterfaceController] Bound core HUD for profile '%s' with panels: [%s]",
		PlaceProfile.GetActiveProfile().id,
		table.concat(registeredPanels, ", ")
	))
end

return MainInterfaceController
