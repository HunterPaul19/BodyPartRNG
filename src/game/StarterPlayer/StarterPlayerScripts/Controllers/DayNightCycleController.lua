local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DayNightCycleConfig = require(ReplicatedStorage.Shared.Config.DayNightCycleConfig)

local LABEL_TWEEN = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PULSE_OUT_TWEEN = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PULSE_IN_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local DayNightCycleController = {}

local function ensureScale(label: TextLabel): UIScale
	local existing = label:FindFirstChild("DayNightScale")
	if existing and existing:IsA("UIScale") then
		return existing
	end

	local scale = Instance.new("UIScale")
	scale.Name = "DayNightScale"
	scale.Scale = 1
	scale.Parent = label
	return scale
end

function DayNightCycleController:_getLabel(): TextLabel?
	if self._label and self._label.Parent then
		return self._label
	end

	for _, container in { Players.LocalPlayer:FindFirstChildOfClass("PlayerGui"), StarterGui } do
		if container then
			local mainInterface = container:FindFirstChild("MainInterface")
			if mainInterface then
				local label = mainInterface:FindFirstChild("CurrentTime", true)
				if label and label:IsA("TextLabel") then
					self._label = label
					self._scale = ensureScale(label)
					return label
				end
			end
		end
	end

	return nil
end

function DayNightCycleController:_cancelTweens()
	if self._labelTween then
		self._labelTween:Cancel()
		self._labelTween = nil
	end

	if self._pulseOutTween then
		self._pulseOutTween:Cancel()
		self._pulseOutTween = nil
	end

	if self._pulseInTween then
		self._pulseInTween:Cancel()
		self._pulseInTween = nil
	end
end

function DayNightCycleController:_pulseLabel()
	if not self._scale then
		return
	end

	self._scale.Scale = 0.96
	self._pulseOutTween = TweenService:Create(self._scale, PULSE_OUT_TWEEN, { Scale = 1.08 })
	self._pulseInTween = TweenService:Create(self._scale, PULSE_IN_TWEEN, { Scale = 1.0 })

	self._pulseOutTween.Completed:Once(function()
		if self._pulseInTween then
			self._pulseInTween:Play()
		end
	end)

	self._pulseOutTween:Play()
end

function DayNightCycleController:_applyPresentation(presentation, animate: boolean)
	local label = self:_getLabel()
	if not label then
		return
	end

	local targetProperties = {
		TextColor3 = presentation.TextColor3,
		TextStrokeColor3 = presentation.TextStrokeColor3,
		TextStrokeTransparency = 0.35,
		TextTransparency = 0,
	}

	if label.Text ~= presentation.Text then
		label.Text = presentation.Text
	end

	if animate then
		self:_cancelTweens()
		label.TextTransparency = 0.18
		self._labelTween = TweenService:Create(label, LABEL_TWEEN, targetProperties)
		self._labelTween:Play()
		self:_pulseLabel()
	else
		for propertyName, value in pairs(targetProperties) do
			label[propertyName] = value
		end
	end

	self._currentPhase = presentation.Phase
end

function DayNightCycleController:_refreshFromLighting(animate: boolean)
	local presentation = DayNightCycleConfig.GetLabelPresentationForClockTime(Lighting.ClockTime)
	if self._currentPhase == presentation.Phase and self._label then
		return
	end

	self:_applyPresentation(presentation, animate)
end

function DayNightCycleController:OnStart()
	task.spawn(function()
		local timeoutAt = os.clock() + 10
		repeat
			if self:_getLabel() then
				break
			end
			task.wait(0.1)
		until os.clock() >= timeoutAt

		if not self:_getLabel() then
			return
		end

		self:_refreshFromLighting(false)

		self._clockTimeConnection = Lighting:GetPropertyChangedSignal("ClockTime"):Connect(function()
			self:_refreshFromLighting(true)
		end)

		self._phaseAttributeConnection = Lighting:GetAttributeChangedSignal("DayNightPhase"):Connect(function()
			self:_refreshFromLighting(true)
		end)
	end)
end

return DayNightCycleController
