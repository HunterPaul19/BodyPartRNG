local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LEADERBOARD_OPEN_POSITION = UDim2.fromScale(0.5, 0.5)
local LEADERBOARD_CLOSED_POSITION = UDim2.fromScale(1.5, 0.5)

local GUIControls = {}

local main = script.Parent
local inner = main:WaitForChild("Inner")
local rotateButton = inner:WaitForChild("TopFrame"):WaitForChild("RotateButton")
local rotateIcon = rotateButton:WaitForChild("Icon")

local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local openTween = TweenService:Create(inner, tweenInfo, { Position = LEADERBOARD_OPEN_POSITION })
local closeTween = TweenService:Create(inner, tweenInfo, { Position = LEADERBOARD_CLOSED_POSITION })
local rotateOpenTween = TweenService:Create(rotateIcon, tweenInfo, { Rotation = 0 })
local rotateCloseTween = TweenService:Create(rotateIcon, tweenInfo, { Rotation = 180 })

GUIControls.Opened = inner.Position ~= LEADERBOARD_CLOSED_POSITION

local function syncCoreGuiVisibility()
	for _ = 1, 8 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
		end)
		if ok then
			return
		end

		task.wait(0.25)
	end
end

function GUIControls:Open()
	GUIControls.Opened = true
	openTween:Play()
	rotateOpenTween:Play()
end

function GUIControls:Close()
	GUIControls.Opened = false
	closeTween:Play()
	rotateCloseTween:Play()
end

function GUIControls:Toggle()
	if GUIControls.Opened then
		self:Close()
	else
		self:Open()
	end
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
	if gameProcessedEvent then
		return
	end

	if input.KeyCode == Enum.KeyCode.Tab then
		GUIControls:Toggle()
	end
end)

rotateButton.MouseButton1Down:Connect(function()
	GUIControls:Toggle()
end)

task.spawn(syncCoreGuiVisibility)

return GUIControls
