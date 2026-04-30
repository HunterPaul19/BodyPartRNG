local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GameAssetPaths = require(ReplicatedStorage.Shared.Assets.GameAssetPaths)
local GameAssetResolver = require(ReplicatedStorage.Shared.Assets.GameAssetResolver)

local ScreenDarkener = {}
ScreenDarkener.__index = ScreenDarkener

local RUNTIME_GUI_NAME = "Visuals"
local TEMPLATE_NAME = "Visuals"
local DEFAULT_DISPLAY_ORDER = 950

local function configureRuntimeGui(runtimeGui: ScreenGui, displayOrder: number?)
	runtimeGui.ResetOnSpawn = false
	runtimeGui.Enabled = true
	runtimeGui.IgnoreGuiInset = true
	runtimeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	runtimeGui.DisplayOrder = math.max(0, math.floor(displayOrder or DEFAULT_DISPLAY_ORDER))
end

local function findAncestorScreenGui(instance: Instance?): ScreenGui?
	local current = instance
	while current do
		if current:IsA("ScreenGui") then
			return current
		end
		current = current.Parent
	end

	return nil
end

local function resolveVisibleRect(minX: number, minY: number, maxX: number, maxY: number, screenWidth: number, screenHeight: number)
	local clampedMinX = math.clamp(math.floor(minX + 0.5), 0, screenWidth)
	local clampedMinY = math.clamp(math.floor(minY + 0.5), 0, screenHeight)
	local clampedMaxX = math.clamp(math.floor(maxX + 0.5), 0, screenWidth)
	local clampedMaxY = math.clamp(math.floor(maxY + 0.5), 0, screenHeight)

	if clampedMaxX <= clampedMinX or clampedMaxY <= clampedMinY then
		return nil
	end

	return clampedMinX, clampedMinY, clampedMaxX, clampedMaxY
end

local function getTemplate(): ScreenGui?
	local screenDarkenerFolder = GameAssetResolver.Find(GameAssetPaths.UI.ScreenDarkener)
	if not (screenDarkenerFolder and screenDarkenerFolder:IsA("Folder")) then
		return nil
	end

	local template = screenDarkenerFolder:FindFirstChild(TEMPLATE_NAME)
	if template and template:IsA("ScreenGui") then
		return template
	end

	return nil
end

local function getPlayerGui(): PlayerGui?
	local player = Players.LocalPlayer
	if not player then
		return nil
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		return playerGui
	end

	return nil
end

local function getCanvasGroupFromGui(visuals: Instance?): CanvasGroup?
	if not visuals then
		return nil
	end

	local canvasGroup = visuals:FindFirstChild("CanvasGroup")
	if canvasGroup and canvasGroup:IsA("CanvasGroup") then
		return canvasGroup
	end

	return nil
end

local function getGuiObjectChild(parent: Instance?, name: string): GuiObject?
	if not parent then
		return nil
	end

	local child = parent:FindFirstChild(name)
	if child and child:IsA("GuiObject") then
		return child
	end

	return nil
end

local function ensureRuntimeGui(): ScreenGui?
	local playerGui = getPlayerGui()
	if not playerGui then
		return nil
	end

	local existing = playerGui:FindFirstChild(RUNTIME_GUI_NAME)
	if existing then
		if existing:IsA("ScreenGui") and getCanvasGroupFromGui(existing) then
			configureRuntimeGui(existing)
			return existing
		end

		return nil
	end

	local template = getTemplate()
	if not template then
		return nil
	end

	local runtimeGui = template:Clone()
	runtimeGui.Name = RUNTIME_GUI_NAME
	configureRuntimeGui(runtimeGui)
	runtimeGui.Parent = playerGui

	return runtimeGui
end

local function refreshReferences(self)
	self.Player = Players.LocalPlayer
	self.Camera = workspace.CurrentCamera
	self.Visuals = ensureRuntimeGui()
	self.CanvasGroup = getCanvasGroupFromGui(self.Visuals)
	self.TopFrame = getGuiObjectChild(self.CanvasGroup, "Top")
	self.BottomFrame = getGuiObjectChild(self.CanvasGroup, "Bottom")
	self.LeftFrame = getGuiObjectChild(self.CanvasGroup, "Left")
	self.RightFrame = getGuiObjectChild(self.CanvasGroup, "Right")
end

function ScreenDarkener.New(padding: number?, tweenTime: number?)
	local self = setmetatable({}, ScreenDarkener)

	self.Player = nil
	self.Camera = nil
	self.Visuals = nil
	self.CanvasGroup = nil
	self.TopFrame = nil
	self.BottomFrame = nil
	self.LeftFrame = nil
	self.RightFrame = nil
	self.Padding = padding or 5
	self.TweenTime = tweenTime or 0.2
	self.Tweens = {}
	self.LastGoal = {}
	self.Target = nil
	self.Connection = nil

	refreshReferences(self)

	return self
end

function ScreenDarkener:IsReady(): boolean
	return self.CanvasGroup ~= nil
		and self.TopFrame ~= nil
		and self.BottomFrame ~= nil
		and self.LeftFrame ~= nil
		and self.RightFrame ~= nil
end

function ScreenDarkener:TweenFrame(frame: GuiObject, goal)
	local currentTween = self.Tweens[frame]
	if currentTween then
		currentTween:Cancel()
	end

	self.Tweens[frame] = TweenService:Create(frame, TweenInfo.new(self.TweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	self.Tweens[frame]:Play()
end

function ScreenDarkener:OffScreenGoals()
	if not self:IsReady() then
		return {}
	end

	local screenWidth = self.CanvasGroup.AbsoluteSize.X
	local screenHeight = self.CanvasGroup.AbsoluteSize.Y

	return {
		[self.TopFrame] = { Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(screenWidth, 0) },
		[self.BottomFrame] = { Position = UDim2.fromOffset(0, screenHeight), Size = UDim2.fromOffset(screenWidth, 0) },
		[self.LeftFrame] = { Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(0, screenHeight) },
		[self.RightFrame] = { Position = UDim2.fromOffset(screenWidth, 0), Size = UDim2.fromOffset(0, screenHeight) },
	}
end

function ScreenDarkener:UpdateLoop()
	if not self:IsReady() then
		return
	end

	self.Connection = RunService.RenderStepped:Connect(function()
		if not self.Target or not self:IsReady() then
			return
		end

		local screenWidth = self.CanvasGroup.AbsoluteSize.X
		local screenHeight = self.CanvasGroup.AbsoluteSize.Y
		local goals = {}
		local minX, minY, maxX, maxY
		local anyOnScreen = true

		if self.Target:IsA("GuiObject") then
			local canvasPosition = self.CanvasGroup.AbsolutePosition
			local absPos = self.Target.AbsolutePosition - canvasPosition
			local absSize = self.Target.AbsoluteSize

			minX = absPos.X - self.Padding
			minY = absPos.Y - self.Padding
			maxX = absPos.X + absSize.X + self.Padding
			maxY = absPos.Y + absSize.Y + self.Padding
		elseif self.Target:IsA("BasePart") then
			local part = self.Target
			local camera = workspace.CurrentCamera
			self.Camera = camera
			if not camera then
				goals = self:OffScreenGoals()
				anyOnScreen = false
				return
			end

			local corners = {
				part.Position + Vector3.new(part.Size.X / 2, part.Size.Y / 2, part.Size.Z / 2),
				part.Position + Vector3.new(-part.Size.X / 2, part.Size.Y / 2, part.Size.Z / 2),
				part.Position + Vector3.new(part.Size.X / 2, -part.Size.Y / 2, part.Size.Z / 2),
				part.Position + Vector3.new(-part.Size.X / 2, -part.Size.Y / 2, part.Size.Z / 2),
				part.Position + Vector3.new(part.Size.X / 2, part.Size.Y / 2, -part.Size.Z / 2),
				part.Position + Vector3.new(-part.Size.X / 2, part.Size.Y / 2, -part.Size.Z / 2),
				part.Position + Vector3.new(part.Size.X / 2, -part.Size.Y / 2, -part.Size.Z / 2),
				part.Position + Vector3.new(-part.Size.X / 2, -part.Size.Y / 2, -part.Size.Z / 2),
			}

			minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
			anyOnScreen = false

			for _, corner in ipairs(corners) do
				local screenPos, onScreen = camera:WorldToViewportPoint(corner)
				if onScreen then
					anyOnScreen = true
					minX = math.min(minX, screenPos.X)
					maxX = math.max(maxX, screenPos.X)
					minY = math.min(minY, screenPos.Y)
					maxY = math.max(maxY, screenPos.Y)
				end
			end

			if not anyOnScreen then
				goals = self:OffScreenGoals()
			end
		else
			goals = self:OffScreenGoals()
			anyOnScreen = false
		end

		if anyOnScreen then
			local clampedMinX, clampedMinY, clampedMaxX, clampedMaxY =
				resolveVisibleRect(minX, minY, maxX, maxY, screenWidth, screenHeight)

			if not clampedMinX then
				goals = self:OffScreenGoals()
			else
				goals[self.TopFrame] = {
					Position = UDim2.fromOffset(0, 0),
					Size = UDim2.fromOffset(screenWidth, clampedMinY),
				}
				goals[self.BottomFrame] = {
					Position = UDim2.fromOffset(0, clampedMaxY),
					Size = UDim2.fromOffset(screenWidth, screenHeight - clampedMaxY),
				}
				goals[self.LeftFrame] = {
					Position = UDim2.fromOffset(0, 0),
					Size = UDim2.fromOffset(clampedMinX, screenHeight),
				}
				goals[self.RightFrame] = {
					Position = UDim2.fromOffset(clampedMaxX, 0),
					Size = UDim2.fromOffset(screenWidth - clampedMaxX, screenHeight),
				}
			end
		end

		for frame, goal in pairs(goals) do
			local last = self.LastGoal[frame]
			if not last or last.Position ~= goal.Position or last.Size ~= goal.Size then
				self:TweenFrame(frame, goal)
				self.LastGoal[frame] = goal
			end
		end
	end)
end

function ScreenDarkener:LayerAbove(target: Instance?)
	if not self:IsReady() then
		refreshReferences(self)
	end

	local visuals = self.Visuals
	if not (visuals and visuals:IsA("ScreenGui")) then
		return
	end

	local targetGui = findAncestorScreenGui(target)
	local displayOrder = DEFAULT_DISPLAY_ORDER
	if targetGui then
		displayOrder = math.max(displayOrder, targetGui.DisplayOrder + 1)
	end

	configureRuntimeGui(visuals, displayOrder)
end

function ScreenDarkener:GetDisplayOrder(): number
	local visuals = self.Visuals
	if visuals and visuals:IsA("ScreenGui") then
		return visuals.DisplayOrder
	end

	return DEFAULT_DISPLAY_ORDER
end

function ScreenDarkener:Activate(target, padding: number?)
	if not self:IsReady() then
		refreshReferences(self)
	end

	if not self:IsReady() then
		return
	end

	self.CanvasGroup.Visible = true

	for frame, goal in pairs(self:OffScreenGoals()) do
		frame.Position = goal.Position
		frame.Size = goal.Size
	end

	if padding then
		self.Padding = padding
	end

	self.Target = target

	if self.Connection then
		self.Connection:Disconnect()
	end

	self:UpdateLoop()
end

function ScreenDarkener:Deactivate()
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end

	self.Target = nil
	for frame, goal in pairs(self:OffScreenGoals()) do
		frame.Active = false
		self:TweenFrame(frame, goal)
	end

	local canvasGroup = self.CanvasGroup
	task.delay(self.TweenTime, function()
		if self.Target == nil and canvasGroup and canvasGroup.Parent then
			canvasGroup.Visible = false
		end
	end)
end

function ScreenDarkener:Switch(newTarget, padding: number?)
	if padding then
		self.Padding = padding
	end

	self.Target = newTarget
end

return ScreenDarkener
