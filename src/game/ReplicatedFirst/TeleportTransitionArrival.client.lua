local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")

local ROOT_NAME = "Root"
local MESSAGE_LABEL_NAME = "MessageLabel"
local DEFAULT_TRANSITION_TEXT = "Teleporting..."
local ARRIVAL_FADE_SECONDS = 0.25
local PLAYER_GUI_TIMEOUT_SECONDS = 10

type TextGuiObject = TextLabel | TextButton | TextBox

type FadeTarget = {
	instance: Instance,
	property: string,
	visibleValue: number,
}

local function isTextGuiObject(instance: Instance): boolean
	return instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")
end

local function addFadeTarget(targets: { FadeTarget }, instance: Instance, property: string, visibleValue: number?)
	if typeof(visibleValue) ~= "number" then
		return
	end

	table.insert(targets, {
		instance = instance,
		property = property,
		visibleValue = visibleValue,
	})
end

local function collectFadeTargets(root: Instance): { FadeTarget }
	local targets = {}

	local function capture(instance: Instance)
		if instance:IsA("GuiObject") then
			addFadeTarget(targets, instance, "BackgroundTransparency", instance.BackgroundTransparency)
		end

		if isTextGuiObject(instance) then
			local textGui = instance :: TextGuiObject
			addFadeTarget(targets, textGui, "TextTransparency", textGui.TextTransparency)
			addFadeTarget(targets, textGui, "TextStrokeTransparency", textGui.TextStrokeTransparency)
		elseif instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
			addFadeTarget(targets, instance, "ImageTransparency", instance.ImageTransparency)
		elseif instance:IsA("UIStroke") then
			addFadeTarget(targets, instance, "Transparency", instance.Transparency)
		end
	end

	capture(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		capture(descendant)
	end

	return targets
end

local function forceArrivalVisible(screenGui: ScreenGui)
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.Enabled = true

	local root = screenGui:FindFirstChild(ROOT_NAME, true)
	if root and root:IsA("GuiObject") then
		root.Visible = true
		root.Active = true
		root.BackgroundColor3 = Color3.new(0, 0, 0)
		root.BackgroundTransparency = 0
	end

	local label = screenGui:FindFirstChild(MESSAGE_LABEL_NAME, true)
	if label and isTextGuiObject(label) then
		local textLabel = label :: TextGuiObject
		textLabel.Visible = true
		textLabel.Text = DEFAULT_TRANSITION_TEXT
		textLabel.TextTransparency = 0
		textLabel.TextStrokeTransparency = 0.45
	end
end

local function fadeOutAndDestroy(screenGui: ScreenGui)
	local fadeTargets = collectFadeTargets(screenGui)
	local tweenInfo = TweenInfo.new(ARRIVAL_FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	for _, target in ipairs(fadeTargets) do
		pcall(function()
			local tween = TweenService:Create(target.instance, tweenInfo, {
				[target.property] = 1,
			})
			tween:Play()
		end)
	end

	task.delay(ARRIVAL_FADE_SECONDS, function()
		if screenGui.Parent then
			screenGui:Destroy()
		end
	end)
end

local arrivingGui = nil
pcall(function()
	arrivingGui = TeleportService:GetArrivingTeleportGui()
end)

if not (arrivingGui and arrivingGui:IsA("ScreenGui")) then
	return
end

pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

local player = Players.LocalPlayer
if not player then
	return
end

local playerGui = player:WaitForChild("PlayerGui", PLAYER_GUI_TIMEOUT_SECONDS)
if not (playerGui and playerGui:IsA("PlayerGui")) then
	arrivingGui:Destroy()
	return
end

forceArrivalVisible(arrivingGui)
arrivingGui.Parent = playerGui
fadeOutAndDestroy(arrivingGui)
