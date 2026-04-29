local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DayNightCycleConfig = require(ReplicatedStorage.Shared.Config.DayNightCycleConfig)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local EFFECT_DEFINITIONS = {
	Atmosphere = "Atmosphere",
	ColorCorrection = "ColorCorrectionEffect",
	Bloom = "BloomEffect",
	SunRays = "SunRaysEffect",
}
local LABEL_TWEEN = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PULSE_OUT_TWEEN = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PULSE_IN_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SERVER_START_TIME_ATTRIBUTE = "DayNightServerStartTime"
local INITIAL_NORMALIZED_TIME_ATTRIBUTE = "DayNightInitialNormalizedTime"
local LOOP_DURATION_ATTRIBUTE = "DayNightLoopDuration"
local RUNTIME_PLACE_VERSION_ATTRIBUTE = "RuntimePlaceVersion"
local DAY_NIGHT_CYCLE_FEATURE_ID = "day_night_cycle"
local LOCAL_PLAYER = Players.LocalPlayer
local DEFAULT_GAME_VERSION_TEXT = "v0.00"

local DayNightCycleController = {}

local function lerpNumber(fromValue: number, toValue: number, alpha: number): number
	return fromValue + (toValue - fromValue) * alpha
end

local function interpolateValue(fromValue: any, toValue: any, alpha: number)
	local valueType = typeof(fromValue)
	if valueType == "Color3" and typeof(toValue) == "Color3" then
		return fromValue:Lerp(toValue, alpha)
	end

	if valueType == "number" and typeof(toValue) == "number" then
		return lerpNumber(fromValue, toValue, alpha)
	end

	return if alpha < 1 then fromValue else toValue
end

local function ensureEffect(name: string, className: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end

	for _, child in ipairs(Lighting:GetChildren()) do
		if child.ClassName == className then
			child.Name = name
			return child
		end
	end

	local effect = Instance.new(className)
	effect.Name = name
	effect.Parent = Lighting
	return effect
end

local function applyPropertyGroup(target: Instance, currentValues: { [string]: any }, nextValues: { [string]: any }, alpha: number)
	for propertyName, value in pairs(currentValues) do
		local nextValue = nextValues[propertyName]
		if nextValue ~= nil then
			target[propertyName] = interpolateValue(value, nextValue, alpha)
		else
			target[propertyName] = value
		end
	end
end

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

local function getGameVersionText(): string
	local placeVersion = tonumber(Lighting:GetAttribute(RUNTIME_PLACE_VERSION_ATTRIBUTE))
	if placeVersion and placeVersion > 0 then
		return string.format("v%.2f", placeVersion / 100)
	end

	return DEFAULT_GAME_VERSION_TEXT
end

local function applyGameVersionText(label: TextLabel?)
	if not label then
		return
	end

	local gameVersionLabel = label:FindFirstChild("GameVersion")
	local gameVersionText = getGameVersionText()
	if gameVersionLabel and gameVersionLabel:IsA("TextLabel") and gameVersionLabel.Text ~= gameVersionText then
		gameVersionLabel.Text = gameVersionText
	end
end

function DayNightCycleController:_getLabel(): TextLabel?
	local playerGui = LOCAL_PLAYER:FindFirstChildOfClass("PlayerGui")

	if self._label then
		if self._label.Parent == nil or playerGui == nil or not self._label:IsDescendantOf(playerGui) then
			self:_cancelTweens()
			self._label = nil
			self._scale = nil
		else
			self._scale = ensureScale(self._label)
			applyGameVersionText(self._label)
			return self._label
		end
	end

	if playerGui then
		local mainInterface = playerGui:FindFirstChild("MainInterface")
		if mainInterface then
			local label = mainInterface:FindFirstChild("CurrentTime", true)
			if label and label:IsA("TextLabel") then
				self._label = label
				self._scale = ensureScale(label)
				applyGameVersionText(label)
				return label
			end
		end
	end

	local starterMainInterface = StarterGui:FindFirstChild("MainInterface")
	if starterMainInterface then
		local label = starterMainInterface:FindFirstChild("CurrentTime", true)
		if label and label:IsA("TextLabel") then
			self._scale = ensureScale(label)
			applyGameVersionText(label)
			return label
		end
	end

	self._scale = nil
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

function DayNightCycleController:_ensureEffects()
	if self._effects then
		return
	end

	self._effects = {}
	for effectName, className in pairs(EFFECT_DEFINITIONS) do
		self._effects[effectName] = ensureEffect(effectName, className)
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
	local label = self:_getLabel()
	if not label then
		return
	end

	if self._currentPhase == presentation.Phase and self._label == label then
		return
	end

	self:_applyPresentation(presentation, animate)
end

function DayNightCycleController:_applyNormalizedTime(normalizedTime: number)
	self:_ensureEffects()

	local currentKeyframe, nextKeyframe, alpha =
		DayNightCycleConfig.GetKeyframePairForNormalizedTime(DayNightCycleConfig.NormalizeCycleTime(normalizedTime))
	local clampedAlpha = math.clamp(alpha, 0, 1)

	applyPropertyGroup(Lighting, currentKeyframe.Lighting, nextKeyframe.Lighting, clampedAlpha)
	for effectName in pairs(EFFECT_DEFINITIONS) do
		local effect = self._effects[effectName]
		local currentValues = currentKeyframe[effectName]
		local nextValues = nextKeyframe[effectName]
		if effect and currentValues and nextValues then
			applyPropertyGroup(effect, currentValues, nextValues, clampedAlpha)
		end
	end

	local nextClockTime = nextKeyframe.ClockTime
	if nextClockTime <= currentKeyframe.ClockTime then
		nextClockTime += 24
	end

	Lighting.ClockTime = DayNightCycleConfig.WrapClockTime(lerpNumber(currentKeyframe.ClockTime, nextClockTime, clampedAlpha))
	self:_refreshFromLighting(currentKeyframe.Phase ~= self._currentPhase)
end

function DayNightCycleController:_getCurrentNormalizedTime(): number
	local serverStartTime = tonumber(Lighting:GetAttribute(SERVER_START_TIME_ATTRIBUTE))
	local initialNormalizedTime = tonumber(Lighting:GetAttribute(INITIAL_NORMALIZED_TIME_ATTRIBUTE))
	local loopDurationSeconds = tonumber(Lighting:GetAttribute(LOOP_DURATION_ATTRIBUTE))
	if serverStartTime == nil or initialNormalizedTime == nil or loopDurationSeconds == nil or loopDurationSeconds <= 0 then
		return DayNightCycleConfig.InitialNormalizedTime
	end

	local elapsedTime = math.max(0, Workspace:GetServerTimeNow() - serverStartTime)
	return DayNightCycleConfig.NormalizeCycleTime(initialNormalizedTime + (elapsedTime / loopDurationSeconds))
end

function DayNightCycleController:OnStart()
	if not PlaceProfile.IsFeatureEnabled(DAY_NIGHT_CYCLE_FEATURE_ID) then
		return
	end

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

		self:_applyNormalizedTime(self:_getCurrentNormalizedTime())
		self._heartbeatConnection = RunService.Heartbeat:Connect(function()
			self:_applyNormalizedTime(self:_getCurrentNormalizedTime())
		end)
	end)
end

return DayNightCycleController
