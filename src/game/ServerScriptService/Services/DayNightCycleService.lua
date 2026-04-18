local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DayNightCycleConfig = require(ReplicatedStorage.Shared.Config.DayNightCycleConfig)

local EFFECT_DEFINITIONS = {
	Atmosphere = "Atmosphere",
	ColorCorrection = "ColorCorrectionEffect",
	Bloom = "BloomEffect",
	SunRays = "SunRaysEffect",
}

local DayNightCycleService = {}
local SERVER_START_TIME_ATTRIBUTE = "DayNightServerStartTime"
local INITIAL_NORMALIZED_TIME_ATTRIBUTE = "DayNightInitialNormalizedTime"
local LOOP_DURATION_ATTRIBUTE = "DayNightLoopDuration"
local RUNTIME_PLACE_VERSION_ATTRIBUTE = "RuntimePlaceVersion"
local heartbeatConnection: RBXScriptConnection? = nil

local function lerpNumber(fromValue: number, toValue: number, alpha: number): number
	return fromValue + (toValue - fromValue) * alpha
end

local function lerpColor(fromValue: Color3, toValue: Color3, alpha: number): Color3
	return fromValue:Lerp(toValue, alpha)
end

local function interpolateValue(fromValue: any, toValue: any, alpha: number)
	local valueType = typeof(fromValue)
	if valueType == "Color3" and typeof(toValue) == "Color3" then
		return lerpColor(fromValue, toValue, alpha)
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

function DayNightCycleService:_ensureEffects()
	if self._effects then
		return
	end

	self._effects = {}

	for effectName, className in pairs(EFFECT_DEFINITIONS) do
		self._effects[effectName] = ensureEffect(effectName, className)
	end

	Lighting.GlobalShadows = false
end

function DayNightCycleService:_applyKeyframePair(currentKeyframe, nextKeyframe, alpha: number)
	self:_ensureEffects()

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

	Lighting.ClockTime = DayNightCycleConfig.WrapClockTime(
		lerpNumber(currentKeyframe.ClockTime, nextClockTime, clampedAlpha)
	)
	Lighting:SetAttribute("DayNightPhase", currentKeyframe.Phase)
	Lighting:SetAttribute("DayNightNormalizedTime", self._normalizedTime)
end

function DayNightCycleService:ApplyNormalizedTime(normalizedTime: number)
	self._normalizedTime = DayNightCycleConfig.NormalizeCycleTime(normalizedTime)

	local currentKeyframe, nextKeyframe, alpha =
		DayNightCycleConfig.GetKeyframePairForNormalizedTime(self._normalizedTime)
	self:_applyKeyframePair(currentKeyframe, nextKeyframe, alpha)
end

function DayNightCycleService:_getCurrentNormalizedTime(): number
	local serverStartTime = tonumber(Lighting:GetAttribute(SERVER_START_TIME_ATTRIBUTE))
	local initialNormalizedTime = tonumber(Lighting:GetAttribute(INITIAL_NORMALIZED_TIME_ATTRIBUTE))
	local loopDurationSeconds = tonumber(Lighting:GetAttribute(LOOP_DURATION_ATTRIBUTE))
	if serverStartTime == nil or initialNormalizedTime == nil or loopDurationSeconds == nil or loopDurationSeconds <= 0 then
		return DayNightCycleConfig.InitialNormalizedTime
	end

	local elapsedTime = math.max(0, Workspace:GetServerTimeNow() - serverStartTime)
	return DayNightCycleConfig.NormalizeCycleTime(initialNormalizedTime + (elapsedTime / loopDurationSeconds))
end

function DayNightCycleService:GetCurrentPhase(): string
	local currentKeyframe = DayNightCycleConfig.GetPhaseForNormalizedTime(self._normalizedTime)
	return currentKeyframe.Phase
end

function DayNightCycleService:OnStart()
	if self._started then
		return
	end

	self._started = true
	self._normalizedTime = DayNightCycleConfig.InitialNormalizedTime
	self:_ensureEffects()
	self:ApplyNormalizedTime(self._normalizedTime)
	Lighting:SetAttribute(RUNTIME_PLACE_VERSION_ATTRIBUTE, game.PlaceVersion)
	Lighting:SetAttribute(SERVER_START_TIME_ATTRIBUTE, Workspace:GetServerTimeNow())
	Lighting:SetAttribute(INITIAL_NORMALIZED_TIME_ATTRIBUTE, self._normalizedTime)
	Lighting:SetAttribute(LOOP_DURATION_ATTRIBUTE, DayNightCycleConfig.LoopDurationSeconds)

	heartbeatConnection = RunService.Heartbeat:Connect(function()
		self:ApplyNormalizedTime(self:_getCurrentNormalizedTime())
	end)
end

return DayNightCycleService
