local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)

local DAMAGE_PER_TICK = 7
local BEAM_DURATION_SECONDS = 2
local BEAM_RADIUS_STUDS = 5.5
local BEAM_TICK_SECONDS = 0.25
local BEAM_MAX_PARTS = 128
local BEAM_MIN_LENGTH_STUDS = 4
local BEAM_MAX_LENGTH_STUDS = 500
local SPRING_DAMPING_RATIO = 0.95
local SPRING_FREQUENCY = 1
local SPRING_MAX_SPEED_STUDS_PER_SECOND = 45
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "CatMechElite"
local ANIMATION_NAME = "RainbowBlast"
local START_MARKER_NAME = "Start"
local BEAM_MARKER_NAME = "Beam"

local stub = CreateExplicitBossMoveStub({
	bossId = "Cat Mech Elite",
	moveLabel = "Rainbow Blast",
	targetMode = "single",
	summaryTemplate = "{moveLabel} sweeps a loose rainbow beam after {target}",
	description = "Cat Mech Elite fires a rainbow beam that loosely follows one player for 2 seconds.",
})

local RainbowBlast = {
	CanUse = stub.CanUse,
	GetTargeting = stub.GetTargeting,
	ExecuteStub = stub.ExecuteStub,
}

local function resolveAnimationInstance(): Animation?
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	if not (gameAssets and gameAssets:IsA("Folder")) then
		return nil
	end

	local animations = gameAssets:FindFirstChild("Animations")
	if not (animations and animations:IsA("Folder")) then
		return nil
	end

	local catMechFolder = animations:FindFirstChild(ANIMATION_FOLDER_NAME)
	if not (catMechFolder and catMechFolder:IsA("Folder")) then
		return nil
	end

	local animationInstance = catMechFolder:FindFirstChild(ANIMATION_NAME)
	if animationInstance and animationInstance:IsA("Animation") then
		return animationInstance
	end

	return nil
end

local function resolveHumanoid(model: Model?): Humanoid?
	if model == nil then
		return nil
	end

	return model:FindFirstChildOfClass("Humanoid")
end

local function resolveRootPart(model: Model?): BasePart?
	if model == nil then
		return nil
	end

	local rootPart = model:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	local primaryPart = model.PrimaryPart
	if primaryPart then
		return primaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function resolveRightHandPart(model: Model?): BasePart?
	if model == nil then
		return nil
	end

	local rightHand = model:FindFirstChild("RightHand", true)
	if rightHand and rightHand:IsA("BasePart") then
		return rightHand
	end

	local spacedRightHand = model:FindFirstChild("Right Hand", true)
	if spacedRightHand and spacedRightHand:IsA("BasePart") then
		return spacedRightHand
	end

	return nil
end

local function resolveHeadPart(model: Model?): BasePart?
	if model == nil then
		return nil
	end

	local head = model:FindFirstChild("Head", true)
	if head and head:IsA("BasePart") then
		return head
	end

	return nil
end

local function resolveBeamOriginPart(bossModel: Model, bossRootPart: BasePart): BasePart
	return resolveRightHandPart(bossModel) or resolveHeadPart(bossModel) or bossRootPart
end

local function buildBeamCFrameAndSize(originPosition: Vector3, endpoint: Vector3, radius: number): (CFrame, Vector3)
	local offset = endpoint - originPosition
	local length = math.clamp(offset.Magnitude, BEAM_MIN_LENGTH_STUDS, BEAM_MAX_LENGTH_STUDS)
	local direction = if offset.Magnitude > 0.001 then offset.Unit else Vector3.new(0, 0, -1)
	local center = originPosition + (direction * (length * 0.5))
	return CFrame.lookAt(center, center + direction), Vector3.new(radius * 2, radius * 2, length)
end

local function createVectorSpring(
	initialPosition: Vector3,
	dampingRatio: number,
	frequency: number,
	maxSpeedStudsPerSecond: number
)
	local self = {
		position = initialPosition,
		velocity = Vector3.zero,
		goal = initialPosition,
		dampingRatio = dampingRatio,
		frequency = frequency,
		maxSpeedStudsPerSecond = maxSpeedStudsPerSecond,
	}

	function self:SetGoal(goal: Vector3)
		self.goal = goal
	end

	function self:Step(dt: number): Vector3
		local clampedDt = math.clamp(dt, 0, 1 / 20)
		local previousPosition = self.position
		local angularFrequency = math.max(0.001, self.frequency) * 2 * math.pi
		local displacement = self.goal - self.position
		local acceleration = (displacement * angularFrequency * angularFrequency)
			- (self.velocity * 2 * self.dampingRatio * angularFrequency)

		self.velocity += acceleration * clampedDt
		self.position += self.velocity * clampedDt
		local movement = self.position - previousPosition
		local maxDistance = math.max(0, self.maxSpeedStudsPerSecond) * clampedDt
		if maxDistance > 0 and movement.Magnitude > maxDistance then
			self.position = previousPosition + (movement.Unit * maxDistance)
			self.velocity = if clampedDt > 0 then (self.position - previousPosition) / clampedDt else Vector3.zero
		end

		return self.position
	end

	return self
end

function RainbowBlast.GetSelectionWeight(context)
	local distance = tonumber(context.distanceToTarget)
	if distance == nil then
		return 1
	end

	if distance <= 18 then
		return 0.35
	elseif distance <= 95 then
		return 1.2
	elseif distance <= 135 then
		return 0.8
	end

	return 0.25
end

function RainbowBlast.StartCast(context)
	local bossModel = context.bossModel
	local bossRootPart = context.bossRootPart
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return nil
	end

	local targetRootPart = context.targetRootPart
	if targetRootPart == nil or targetRootPart.Parent == nil then
		return nil
	end

	local targetPlayer = context.targetPlayer
	local animationInstance = resolveAnimationInstance()
	if animationInstance == nil then
		warn("[RainbowBlast] Missing animation at ReplicatedStorage.GameAssets.Animations.CatMechElite.RainbowBlast.")
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[RainbowBlast] Failed to create animation profile:", profileOrError)
		return nil
	end

	local profile = profileOrError
	local scaleMultiplier = math.max(0.1, tonumber(context.bossDefinition and context.bossDefinition.scaleMultiplier) or 1)
	local beamRadius = BEAM_RADIUS_STUDS * math.clamp(math.sqrt(scaleMultiplier), 1, 2.5)
	local track = nil :: AnimationTrack?
	local stoppedConnection = nil :: RBXScriptConnection?
	local beamConnection = nil :: RBXScriptConnection?
	local activeHitbox = nil
	local endpointSpring = nil
	local initialAimPosition = nil :: Vector3?
	local completed = false
	local cancelled = false
	local cleanedUp = false
	local startTriggered = false
	local beamTriggered = false
	local presentationStopped = false
	local beamStartedAt = 0
	local recoveryEndsAt = nil :: number?

	local function disconnectStoppedConnection()
		if stoppedConnection and stoppedConnection.Connected then
			stoppedConnection:Disconnect()
		end
		stoppedConnection = nil
	end

	local function disconnectBeamConnection()
		if beamConnection and beamConnection.Connected then
			beamConnection:Disconnect()
		end
		beamConnection = nil
	end

	local function destroyHitbox()
		if activeHitbox == nil then
			return
		end

		activeHitbox:Destroy()
		activeHitbox = nil
	end

	local function stopPresentation()
		if presentationStopped then
			return
		end

		presentationStopped = true
		context.EmitPresentation("stop")
	end

	local function markComplete()
		if completed then
			return
		end

		completed = true
		recoveryEndsAt = os.clock() + (tonumber(context.move and context.move.recoverySeconds) or 0)
		disconnectBeamConnection()
		destroyHitbox()
		stopPresentation()
	end

	local function cleanup(stopAnimation: boolean)
		if cleanedUp then
			return
		end

		cleanedUp = true
		disconnectStoppedConnection()
		disconnectBeamConnection()
		destroyHitbox()
		stopPresentation()

		if stopAnimation and track then
			profile:StopAnimation(animationInstance, ANIMATION_FADE_SECONDS)
		end
	end

	local function getBeamOriginPosition(): Vector3?
		if bossModel.Parent == nil or bossRootPart.Parent == nil then
			return nil
		end

		local originPart = resolveBeamOriginPart(bossModel, bossRootPart)
		if originPart.Parent == nil then
			return nil
		end

		return originPart.Position
	end

	local function getBeamTargetPosition(): Vector3?
		if targetRootPart.Parent ~= nil then
			return targetRootPart.Position
		end

		if targetPlayer and targetPlayer.Character then
			local rootPart = resolveRootPart(targetPlayer.Character)
			if rootPart and rootPart.Parent ~= nil then
				targetRootPart = rootPart
				return rootPart.Position
			end
		end

		return nil
	end

	local function getBeamCFrameAndSize(): (CFrame?, Vector3?)
		local originPosition = getBeamOriginPosition()
		if originPosition == nil or endpointSpring == nil then
			return nil, nil
		end

		return buildBeamCFrameAndSize(originPosition, endpointSpring.position, beamRadius)
	end

	local function handleStart()
		if cancelled or startTriggered then
			return
		end

		startTriggered = true
		initialAimPosition = initialAimPosition or getBeamTargetPosition()
		context.EmitPresentation("start", {
			scaleMultiplier = scaleMultiplier,
			targetUserId = if targetPlayer then targetPlayer.UserId else nil,
			initialAimPosition = initialAimPosition,
			originPosition = getBeamOriginPosition(),
			springDampingRatio = SPRING_DAMPING_RATIO,
			springFrequency = SPRING_FREQUENCY,
			springMaxSpeedStudsPerSecond = SPRING_MAX_SPEED_STUDS_PER_SECOND,
			beamDurationSeconds = BEAM_DURATION_SECONDS,
			beamRadius = beamRadius,
			beamMaxLengthStuds = BEAM_MAX_LENGTH_STUDS,
		})
	end

	local function handleBeam()
		if cancelled or beamTriggered or bossModel.Parent == nil or bossRootPart.Parent == nil then
			return
		end

		beamTriggered = true
		local targetPosition = initialAimPosition or getBeamTargetPosition()
		if targetPosition == nil then
			markComplete()
			return
		end

		endpointSpring = createVectorSpring(
			targetPosition,
			SPRING_DAMPING_RATIO,
			SPRING_FREQUENCY,
			SPRING_MAX_SPEED_STUDS_PER_SECOND
		)
		beamStartedAt = os.clock()
		local originPosition = getBeamOriginPosition()
		context.EmitPresentation("beam", {
			scaleMultiplier = scaleMultiplier,
			targetUserId = if targetPlayer then targetPlayer.UserId else nil,
			initialAimPosition = targetPosition,
			initialTargetPosition = targetPosition,
			originPosition = originPosition,
			springDampingRatio = SPRING_DAMPING_RATIO,
			springFrequency = SPRING_FREQUENCY,
			springMaxSpeedStudsPerSecond = SPRING_MAX_SPEED_STUDS_PER_SECOND,
			beamDurationSeconds = BEAM_DURATION_SECONDS,
			beamRadius = beamRadius,
			beamMaxLengthStuds = BEAM_MAX_LENGTH_STUDS,
		})

		activeHitbox = Hitbox.new({
			DebugVisibilityAttribute = "BossHitboxesVisible",
			Character = bossModel,
			HitboxCFrame = function()
				local beamCFrame = getBeamCFrameAndSize()
				return beamCFrame
			end,
			HitboxSize = function()
				local _, beamSize = getBeamCFrameAndSize()
				return beamSize
			end,
			HitboxType = "SpacialQuery",
			Time = BEAM_DURATION_SECONDS,
			TickTime = BEAM_TICK_SECONDS,
			MaxParts = BEAM_MAX_PARTS,
		}, {
			HitTarget = function(targetModel: Model)
				local player = Players:GetPlayerFromCharacter(targetModel)
				if player == nil then
					return
				end

				local humanoid = resolveHumanoid(targetModel)
				if humanoid == nil or humanoid.Health <= 0 then
					return
				end

				humanoid:TakeDamage(DAMAGE_PER_TICK)
			end,
			HitboxDestroy = function()
				activeHitbox = nil
			end,
		})

		local previousStepAt = os.clock()
		beamConnection = RunService.Heartbeat:Connect(function()
			if cancelled or completed or endpointSpring == nil then
				disconnectBeamConnection()
				return
			end
			if bossModel.Parent == nil or bossRootPart.Parent == nil then
				markComplete()
				return
			end

			local now = os.clock()
			local goalPosition = getBeamTargetPosition()
			if goalPosition ~= nil then
				endpointSpring:SetGoal(goalPosition)
			end
			endpointSpring:Step(now - previousStepAt)
			previousStepAt = now

			if now - beamStartedAt >= BEAM_DURATION_SECONDS then
				markComplete()
			end
		end)
	end

	track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, {
		[START_MARKER_NAME] = handleStart,
		[BEAM_MARKER_NAME] = handleBeam,
	}, ANIMATION_FADE_SECONDS)
	if track == nil then
		warn("[RainbowBlast] Failed to play RainbowBlast animation.")
		return nil
	end

	handleStart()
	track.Looped = false
	stoppedConnection = track.Stopped:Connect(function()
		disconnectStoppedConnection()
		if cancelled then
			return
		end

		if not startTriggered then
			handleStart()
		end
		if not beamTriggered then
			warn(string.format(
				"[RainbowBlast] Animation '%s' completed without firing the '%s' marker.",
				animationInstance.Name,
				BEAM_MARKER_NAME
			))
			markComplete()
		end
	end)

	return {
		Cancel = function()
			if cancelled then
				return
			end

			cancelled = true
			completed = true
			recoveryEndsAt = os.clock()
			cleanup(true)
		end,
		IsComplete = function()
			return completed
		end,
		GetRecoveryEndsAt = function()
			return recoveryEndsAt
		end,
	}
end

return table.freeze(RainbowBlast)
