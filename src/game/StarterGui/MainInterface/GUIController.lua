local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local FrameController = require(
	Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Controllers"):WaitForChild("FrameController")
)

local GUIController = {}

local OpenTwinf = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CloseTwinf = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local Main = script.Parent
local Black = Main.Black

local Blur = Instance.new("BlurEffect")
Blur.Parent = game.Lighting
Blur.Name = "PanelBlur"
Blur.Size = 0

local Panels = {
	["Main"] = Main:WaitForChild("Main"),
	["Appraisal"] = Main:WaitForChild("AppraisalUI"),
	["Dialogue"] = Main:WaitForChild("DialogueUI"),
	["Leaderboard"] = Main:WaitForChild("Leaderboard"),
	["PlayerInfo"] = Main:WaitForChild("PlayerInfo"),
	["RobuxStore"] = Main:WaitForChild("RobuxStore"),
	["Shop"] = Main:WaitForChild("ShopUI"),
	["Roll"] = Main:WaitForChild("Roll"),
} :: { Frame }

local PanelInfo = {}

for key, panel in Panels do
	PanelInfo[key] = { Frame = panel, Position = panel.Position, Size = panel.Size, currentlyTransitioning = false }
end

local function GetPanel(panelName: string)
	local found = PanelInfo[panelName]
	assert(found, "panel " .. panelName .. " not found")
	if not found then
		return
	end
	return found
end

function GUIController:OpenPanel(panelName: string, forceOpen: boolean?)
	TweenService:Create(Black, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { BackgroundTransparency = 0.7 }):Play()
	TweenService:Create(Blur, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Size = 10 }):Play()
	task.spawn(function()
		local found = GetPanel(panelName)

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

		found.Frame.Visible = true

		local offsetPosition = UDim2.fromScale(found.Position.X.Scale, found.Position.Y.Scale * 1.1)
		found.Frame.Position = offsetPosition

		local offsetSize = UDim2.fromScale(found.Size.X.Scale * 0.8, found.Size.Y.Scale * 0.8)
		found.Frame.Size = offsetSize

		TweenService:Create(found.Frame, OpenTwinf, { Position = found.Position, Size = found.Size }):Play()

		task.delay(OpenTwinf.Time, function()
			found.currentlyTransitioning = false
		end)
	end)
end

function GUIController:ClosePanel(panelName: string, forceClose: boolean?)
	TweenService:Create(Black, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(Blur, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Size = 0 }):Play()
	task.spawn(function()
		local found = GetPanel(panelName)

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

		found.Frame.Visible = true

		local offsetPosition = UDim2.fromScale(found.Position.X.Scale, found.Position.Y.Scale * 1.1)
		found.Frame.Position = found.Position

		local offsetSize = UDim2.fromScale(found.Size.X.Scale * 0.8, found.Size.Y.Scale * 0.8)
		found.Frame.Size = found.Size

		TweenService:Create(found.Frame, CloseTwinf, { Position = offsetPosition, Size = offsetSize }):Play()

		task.delay(CloseTwinf.Time, function()
			found.Frame.Visible = false
			found.currentlyTransitioning = false
		end)
	end)
end

function GUIController:TogglePanel(panelName: string, forceToggle: boolean)
	local found = GetPanel(panelName)
	if not found.Frame.Visible then
		GUIController:OpenPanel(panelName, forceToggle)
	else
		GUIController:ClosePanel(panelName, forceToggle)
	end
end

function GUIController:CloseAll()
	for key in PanelInfo do
		GUIController:ClosePanel(key)
	end
end

function GUIController:HideMain()
	Main.Enabled = false
end

function GUIController:OpenMain()
	Main.Enabled = true
end

function GUIController:GetPanelModule(panelName: string): ModuleScript
	local Panel = GetPanel(panelName)
	assert(Panel, "panel " .. panelName .. " not found")
	if not Panel then
		return nil :: any
	end

	local GUIControls = Panel.Frame:FindFirstChild("GUIControls")
	assert(GUIControls, "GUIControls not found for panel " .. panelName)
	return GUIControls :: ModuleScript
end

for key in PanelInfo do
	require(GUIController:GetPanelModule(key))
end

local PlayerInfoMod = require(GUIController:GetPanelModule("PlayerInfo"))
PlayerInfoMod.Opened.Changed:Connect(function()
	if PlayerInfoMod.Opened.Value == true then
		GUIController:OpenPanel("PlayerInfo", true)
	else
		GUIController:ClosePanel("PlayerInfo", true)
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == Enum.KeyCode.T then
		GUIController:TogglePanel("Main")
	elseif input.KeyCode == Enum.KeyCode.E then
		GUIController:TogglePanel("Appraisal")
	elseif input.KeyCode == Enum.KeyCode.G then
		FrameController:ToggleFrame("Inventory")
	elseif input.KeyCode == Enum.KeyCode.B then
		GUIController:TogglePanel("Dialogue")
	end
end)

return GUIController
