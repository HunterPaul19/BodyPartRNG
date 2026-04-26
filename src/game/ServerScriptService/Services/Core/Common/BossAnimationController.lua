local RunService = game:GetService("RunService")

local BossAnimationController = {}
BossAnimationController.__index = BossAnimationController

type WeightedAnimationEntry = {
	animation: Animation,
	weight: number,
}

type TrackBundle = {
	channelName: string,
	entries: { WeightedAnimationEntry },
	looped: boolean,
	priority: Enum.AnimationPriority,
}

type AttachOptions = {
	scaleMultiplier: number?,
}

local LOOPED_CHANNELS = {
	idle = true,
	walk = true,
	run = true,
	fall = true,
	climb = true,
	swim = true,
	swimidle = true,
}

local PRIORITY_BY_CHANNEL = {
	idle = Enum.AnimationPriority.Core,
	walk = Enum.AnimationPriority.Movement,
	run = Enum.AnimationPriority.Movement,
	jump = Enum.AnimationPriority.Movement,
	fall = Enum.AnimationPriority.Movement,
	climb = Enum.AnimationPriority.Movement,
	swim = Enum.AnimationPriority.Movement,
	swimidle = Enum.AnimationPriority.Movement,
}

local SUPPORTED_CHANNELS = {
	idle = true,
	walk = true,
	run = true,
	jump = true,
	fall = true,
	climb = true,
	swim = true,
	swimidle = true,
}

local MOVEMENT_SPEED_EPSILON = 0.5
local RUN_SPEED_THRESHOLD_RATIO = 0.66
local ABSOLUTE_RUN_SPEED_THRESHOLD = 8
local UPDATE_INTERVAL_SECONDS = 0.1
local TRACK_FADE_SECONDS = 0.15
local JUMP_HOLD_SECONDS = 0.2
local MIN_MOVEMENT_TRACK_SPEED = 0.1
local MAX_MOVEMENT_TRACK_SPEED = 1.35

local SCALE_AWARE_MOVEMENT_CHANNELS = {
	walk = true,
	run = true,
	climb = true,
	swim = true,
}

local function normalizeChannelName(value: any): string
	if typeof(value) ~= "string" then
		return ""
	end

	local trimmed = string.match(value, "%S.*")
	if not trimmed then
		return ""
	end

	return string.lower(trimmed)
end

local function getAnimator(humanoid: Humanoid): Animator
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end

	local createdAnimator = Instance.new("Animator")
	createdAnimator.Parent = humanoid
	return createdAnimator
end

local function getAnimationWeight(animation: Animation): number
	local weightValue = animation:FindFirstChild("Weight")
	if weightValue and weightValue:IsA("NumberValue") then
		return math.max(0.01, weightValue.Value)
	end

	return 1
end

local function normalizeScaleMultiplier(value: any): number
	local resolvedValue = tonumber(value)
	if resolvedValue == nil then
		return 1
	end

	return math.max(0.1, resolvedValue)
end

local function buildTrackBundle(channelValue: Instance): TrackBundle?
	local channelName = normalizeChannelName(channelValue.Name)
	if SUPPORTED_CHANNELS[channelName] ~= true then
		return nil
	end

	local entries = {}
	for _, child in ipairs(channelValue:GetChildren()) do
		if child:IsA("Animation") then
			table.insert(entries, {
				animation = child,
				weight = getAnimationWeight(child),
			})
		end
	end

	if #entries <= 0 then
		return nil
	end

	return {
		channelName = channelName,
		entries = entries,
		looped = LOOPED_CHANNELS[channelName] == true,
		priority = PRIORITY_BY_CHANNEL[channelName] or Enum.AnimationPriority.Movement,
	}
end

local function parseAnimateBundles(bossModel: Model): { [string]: TrackBundle }
	local animateScript = bossModel:FindFirstChild("Animate")
	if not animateScript then
		return {}
	end

	local bundles = {}
	for _, child in ipairs(animateScript:GetChildren()) do
		local bundle = buildTrackBundle(child)
		if bundle then
			bundles[bundle.channelName] = bundle
		end
	end

	return bundles
end

local function chooseWeightedAnimation(entries: { WeightedAnimationEntry }, rng: Random): Animation
	local totalWeight = 0
	for _, entry in ipairs(entries) do
		totalWeight += entry.weight
	end

	if totalWeight <= 0 then
		return entries[1].animation
	end

	local threshold = rng:NextNumber(0, totalWeight)
	local accumulatedWeight = 0

	for _, entry in ipairs(entries) do
		accumulatedWeight += entry.weight
		if threshold <= accumulatedWeight then
			return entry.animation
		end
	end

	return entries[#entries].animation
end

function BossAnimationController:_stopActiveTrack()
	if self._activeTrack then
		self._activeTrack:Stop(TRACK_FADE_SECONDS)
		self._activeTrack:Destroy()
		self._activeTrack = nil
	end

	self._activeChannel = nil
end

function BossAnimationController:_resolveMovementSpeedScale(channelName: string, planarSpeed: number): number
	local motionSpeed = planarSpeed
	if channelName == "climb" and self._rootPart and self._rootPart.Parent then
		motionSpeed = math.abs(self._rootPart.AssemblyLinearVelocity.Y)
	end

	local baseSpeed = motionSpeed / math.max(1, self._humanoid.WalkSpeed)
	local scaledSpeed = baseSpeed / self._locomotionScale
	return math.clamp(scaledSpeed, MIN_MOVEMENT_TRACK_SPEED, MAX_MOVEMENT_TRACK_SPEED)
end

function BossAnimationController:_resolveDesiredChannel(now: number): string?
	local humanoid = self._humanoid
	local rootPart = self._rootPart

	if rootPart == nil or rootPart.Parent == nil then
		return nil
	end
	if humanoid.Health <= 0 then
		return nil
	end

	if self._locomotionSuppressed == true then
		return nil
	end

	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Dead then
		return nil
	end
	if state == Enum.HumanoidStateType.Jumping then
		self._jumpUntil = now + JUMP_HOLD_SECONDS
		return if self._bundles.jump then "jump" else nil
	end

	if self._jumpUntil > now and self._bundles.jump then
		return "jump"
	end

	if state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.FallingDown then
		if self._bundles.fall then
			return "fall"
		end
	end

	if state == Enum.HumanoidStateType.Climbing and self._bundles.climb then
		return "climb"
	end

	if state == Enum.HumanoidStateType.Swimming then
		local planarSwimSpeed = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z).Magnitude
		if planarSwimSpeed > MOVEMENT_SPEED_EPSILON and self._bundles.swim then
			return "swim"
		end
		if self._bundles.swimidle then
			return "swimidle"
		end
	end

	local planarSpeed = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z).Magnitude
	if planarSpeed <= MOVEMENT_SPEED_EPSILON then
		if self._bundles.idle then
			return "idle"
		end
		if self._bundles.walk then
			return "walk"
		end
		if self._bundles.run then
			return "run"
		end
		return nil
	end

	local runThreshold = math.max(ABSOLUTE_RUN_SPEED_THRESHOLD, humanoid.WalkSpeed * RUN_SPEED_THRESHOLD_RATIO)
	if planarSpeed >= runThreshold then
		if self._bundles.run then
			return "run"
		end
		if self._bundles.walk then
			return "walk"
		end
	end

	if self._bundles.walk then
		return "walk"
	end
	if self._bundles.run then
		return "run"
	end

	return "idle"
end

function BossAnimationController:_playChannel(channelName: string, planarSpeed: number)
	local bundle = self._bundles[channelName]
	if bundle == nil then
		self:_stopActiveTrack()
		return
	end

	local animation = chooseWeightedAnimation(bundle.entries, self._rng)
	local track = self._animator:LoadAnimation(animation)
	track.Looped = bundle.looped
	track.Priority = bundle.priority
	track:Play(TRACK_FADE_SECONDS)

	if SCALE_AWARE_MOVEMENT_CHANNELS[channelName] == true then
		local speedScale = self:_resolveMovementSpeedScale(channelName, planarSpeed)
		track:AdjustSpeed(speedScale)
	end

	if self._activeTrack then
		self._activeTrack:Stop(TRACK_FADE_SECONDS)
		self._activeTrack:Destroy()
	end

	self._activeTrack = track
	self._activeChannel = channelName
end

function BossAnimationController:_refresh()
	local now = os.clock()
	local desiredChannel = self:_resolveDesiredChannel(now)
	local rootPart = self._rootPart
	local planarSpeed = 0

	if rootPart and rootPart.Parent then
		planarSpeed = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z).Magnitude
	end

	if desiredChannel == nil then
		self:_stopActiveTrack()
		return
	end

	if self._activeChannel ~= desiredChannel or self._activeTrack == nil or self._activeTrack.IsPlaying ~= true then
		self:_playChannel(desiredChannel, planarSpeed)
		return
	end

	if SCALE_AWARE_MOVEMENT_CHANNELS[desiredChannel] == true then
		local speedScale = self:_resolveMovementSpeedScale(desiredChannel, planarSpeed)
		self._activeTrack:AdjustSpeed(speedScale)
	end
end

function BossAnimationController:SetLocomotionSuppressed(isSuppressed: boolean)
	self._locomotionSuppressed = isSuppressed == true
	if self._locomotionSuppressed then
		self:_stopActiveTrack()
	else
		self:_refresh()
	end
end

function BossAnimationController:Destroy()
	if self._heartbeatConnection then
		self._heartbeatConnection:Disconnect()
		self._heartbeatConnection = nil
	end

	self:_stopActiveTrack()
end

function BossAnimationController.Attach(bossModel: Model, humanoid: Humanoid, options: AttachOptions?)
	assert(typeof(bossModel) == "Instance" and bossModel:IsA("Model"), "BossAnimationController.Attach requires a boss model.")
	assert(typeof(humanoid) == "Instance" and humanoid:IsA("Humanoid"), "BossAnimationController.Attach requires a humanoid.")

	local rootPart = bossModel:FindFirstChild("HumanoidRootPart")
	if not (rootPart and rootPart:IsA("BasePart")) then
		rootPart = bossModel.PrimaryPart or bossModel:FindFirstChildWhichIsA("BasePart", true)
	end

	local resolvedScaleMultiplier = nil
	local getScaleOk, getScaleResult = pcall(function()
		return bossModel:GetScale()
	end)
	if getScaleOk and typeof(getScaleResult) == "number" and getScaleResult > 0 then
		resolvedScaleMultiplier = getScaleResult
	elseif typeof(options) == "table" then
		resolvedScaleMultiplier = options.scaleMultiplier
	end

	local controller = setmetatable({
		_bossModel = bossModel,
		_humanoid = humanoid,
		_rootPart = rootPart,
		_animator = getAnimator(humanoid),
		_bundles = parseAnimateBundles(bossModel),
		_locomotionScale = normalizeScaleMultiplier(resolvedScaleMultiplier),
		_rng = Random.new(),
		_activeTrack = nil :: AnimationTrack?,
		_activeChannel = nil :: string?,
		_locomotionSuppressed = false,
		_jumpUntil = 0,
		_lastRefreshAt = 0,
		_heartbeatConnection = nil :: RBXScriptConnection?,
	}, BossAnimationController)

	controller._heartbeatConnection = RunService.Heartbeat:Connect(function()
		if controller._bossModel.Parent == nil or controller._humanoid.Parent == nil then
			controller:Destroy()
			return
		end

		if os.clock() - controller._lastRefreshAt < UPDATE_INTERVAL_SECONDS then
			return
		end

		controller._lastRefreshAt = os.clock()
		controller:_refresh()
	end)

	controller:_refresh()
	return controller
end

return BossAnimationController
