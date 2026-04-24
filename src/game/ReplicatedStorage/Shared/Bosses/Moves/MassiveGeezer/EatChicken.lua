local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local CombatMoveUtil = require(ReplicatedStorage.Shared.Combat.CombatMoveUtil)
local CombatProjectileUtil = require(ReplicatedStorage.Shared.Combat.CombatProjectileUtil)
local Knockback = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Knockback)

local DAMAGE = 420
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "MassiveGeezer"
local ANIMATION_NAME = "EatChicken"
local PROJECTILE_COUNT = 16
local PROJECTILES_PER_HAND = math.floor(PROJECTILE_COUNT / 2)
local BASE_PROJECTILE_SPEED_STUDS_PER_SECOND = 170
local PROJECTILE_DISTANCE_STUDS = 185
local FALLBACK_PROJECTILE_RADIUS = 10
local PROJECTILE_MAX_PARTS = 64
local THROW_YAW_STEP_DEGREES = 15
local SHOTGUN_SCATTER_YAW_DEGREES = 10
local SHOTGUN_MIN_DISTANCE_SCALAR = 0.72
local SHOTGUN_MAX_DISTANCE_SCALAR = 1.0
local SHOTGUN_MIN_SPEED_SCALAR = 0.82
local SHOTGUN_MAX_SPEED_SCALAR = 1.18
local KNOCKBACK_SPEED = 48
local KNOCKBACK_UPWARD_SPEED = 18
local KNOCKBACK_DURATION = 0.2
local RAGDOLL_DURATION = 0.55
local STUN_DURATION = 0.35
local IFRAME_DURATION = 0.2
local ANTI_STUN_DURATION = 0.45

local CHICKEN_SPAWN_MARKER_NAME = "ChickenSpawn"
local ATE_CHICKEN_MARKER_NAME = "AteChicken"
local TURN_TO_PLAYER_MARKER_NAME = "TurnToPlayer"
local CHICKEN_THROW_MARKER_NAME = "ChickenThrow"

local VFX_FOLDER_NAME = "MassiveGeezer"
local EAT_CHICKEN_VFX_NAME = "EatChicken"
local CHICKEN_LEG_VFX_NAME = "ChickenLeg"
local CHICKEN_MEAT_NAME = "ChickenMeat"
local CHICKEN_VISUAL_SCALE_FACTOR = 0.5
local CHICKEN_FLIGHT_FORWARD_YAW_DEGREES = -90
local CHICKEN_HOLD_PITCH_DEGREES = -20
local CHICKEN_HOLD_ROLL_DEGREES = 90
local CHICKEN_RELEASE_BLEND_ALPHA = 0.2
local CHICKEN_PRIMARY_SPIN_MAX_DEGREES_PER_SECOND = 1080
local CHICKEN_PRIMARY_SPIN_MIN_DEGREES_PER_SECOND = 540
local CHICKEN_SECONDARY_SPIN_MAX_DEGREES_PER_SECOND = 220
local CHICKEN_SECONDARY_SPIN_MIN_DEGREES_PER_SECOND = 60

local FLIGHT_ROTATION_OFFSET = CFrame.Angles(0, math.rad(CHICKEN_FLIGHT_FORWARD_YAW_DEGREES), 0)
local HOLD_ROTATION_OFFSET = FLIGHT_ROTATION_OFFSET
	* CFrame.Angles(math.rad(CHICKEN_HOLD_PITCH_DEGREES), 0, math.rad(CHICKEN_HOLD_ROLL_DEGREES))

local stub = CreateExplicitBossMoveStub({
	bossId = "Massive Geezer",
	moveLabel = "Eat Chicken",
	targetMode = "all_players",
	summaryTemplate = "{moveLabel} throws chicken bones through the arena",
	description = "Massive Geezer eats chicken and throws a spread of bones across the arena.",
})

local EatChicken = {
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

	local bossFolder = animations:FindFirstChild(ANIMATION_FOLDER_NAME)
	if not (bossFolder and bossFolder:IsA("Folder")) then
		return nil
	end

	local animationInstance = bossFolder:FindFirstChild(ANIMATION_NAME)
	if animationInstance and animationInstance:IsA("Animation") then
		return animationInstance
	end

	return nil
end

local function resolveChickenLegModel(): Model?
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	if not (gameAssets and gameAssets:IsA("Folder")) then
		return nil
	end

	local vfxFolder = gameAssets:FindFirstChild("VFX")
	if not (vfxFolder and vfxFolder:IsA("Folder")) then
		return nil
	end

	local bossFolder = vfxFolder:FindFirstChild(VFX_FOLDER_NAME)
	if not (bossFolder and bossFolder:IsA("Folder")) then
		return nil
	end

	local effectFolder = bossFolder:FindFirstChild(EAT_CHICKEN_VFX_NAME)
	if not (effectFolder and effectFolder:IsA("Folder")) then
		return nil
	end

	local chickenLeg = effectFolder:FindFirstChild(CHICKEN_LEG_VFX_NAME)
	if chickenLeg and chickenLeg:IsA("Model") then
		return chickenLeg
	end

	return nil
end

local function resolveChickenVisualScale(scaleMultiplier: number?): number
	return math.max(0.1, (tonumber(scaleMultiplier) or 1) * CHICKEN_VISUAL_SCALE_FACTOR)
end

local function destroyChickenMeat(chickenModel: Model)
	for _, descendant in ipairs(chickenModel:GetDescendants()) do
		if descendant.Name == CHICKEN_MEAT_NAME then
			descendant:Destroy()
		end
	end
end

local function resolveBoneProjectileHitboxGeometry(scaleMultiplier: number?): (Vector3?, CFrame?)
	local chickenLegSource = resolveChickenLegModel()
	if chickenLegSource == nil then
		return nil, nil
	end

	local chickenClone = chickenLegSource:Clone()
	local scaleOk = pcall(function()
		chickenClone:ScaleTo(resolveChickenVisualScale(scaleMultiplier))
	end)
	if not scaleOk then
		chickenClone:Destroy()
		return nil, nil
	end

	destroyChickenMeat(chickenClone)
	local boundsCFrame, boundsSize = chickenClone:GetBoundingBox()
	local boundsOffset = chickenClone:GetPivot():ToObjectSpace(boundsCFrame)
	chickenClone:Destroy()

	if boundsSize.X <= 0.001 or boundsSize.Y <= 0.001 or boundsSize.Z <= 0.001 then
		return nil, nil
	end

	return boundsSize, boundsOffset
end

local function resolveRootPart(model: Model?): BasePart?
	return CombatMoveUtil.ResolveRootPart(model)
end

local function resolveHumanoid(model: Model?): Humanoid?
	return CombatMoveUtil.ResolveHumanoid(model)
end

local function resolveHandPart(bossModel: Model, handName: string): BasePart?
	return CombatMoveUtil.ResolveNamedPart(bossModel, { handName })
end

local function resolvePlanarDirection(vector: Vector3): Vector3?
	local direction = CombatMoveUtil.ResolvePlanarDirection(Vector3.zero, vector, nil)
	if direction == Vector3.new(0, 0, -1) and Vector3.new(vector.X, 0, vector.Z).Magnitude <= 0.001 then
		return nil
	end
	return direction
end

local function resolveNearestAliveTargetRootPart(context, bossRootPart: BasePart): BasePart?
	local nearestTarget = CombatMoveUtil.ResolveNearestAliveTarget(bossRootPart.Position, context.aliveTargets or {})
	return if nearestTarget then nearestTarget.rootPart else nil
end

local function resolveAimTargetRootPart(context, bossRootPart: BasePart): BasePart?
	local targetRootPart = context.targetRootPart
	local targetHumanoid = context.targetHumanoid
	if targetRootPart and targetRootPart.Parent ~= nil and targetHumanoid and targetHumanoid.Health > 0 then
		return targetRootPart
	end

	return resolveNearestAliveTargetRootPart(context, bossRootPart)
end

local function resolveForwardDirection(context, bossRootPart: BasePart, aimTargetRootPart: BasePart?): Vector3
	if aimTargetRootPart and aimTargetRootPart.Parent ~= nil then
		local targetDirection = resolvePlanarDirection(aimTargetRootPart.Position - bossRootPart.Position)
		if targetDirection then
			return targetDirection
		end
	end

	local targetRootPart = context.targetRootPart
	if targetRootPart and targetRootPart.Parent ~= nil then
		local targetDirection = resolvePlanarDirection(targetRootPart.Position - bossRootPart.Position)
		if targetDirection then
			return targetDirection
		end
	end

	local lookDirection = resolvePlanarDirection(bossRootPart.CFrame.LookVector)
	if lookDirection then
		return lookDirection
	end

	return Vector3.new(0, 0, -1)
end

local function faceBossTowardDirection(bossRootPart: BasePart, forwardDirection: Vector3)
	local position = bossRootPart.Position
	bossRootPart.CFrame = CFrame.lookAt(position, position + forwardDirection)
end

local function resolveProjectileStartPosition(bossModel: Model, index: number, bossRootPart: BasePart): Vector3
	local handName = if index <= PROJECTILES_PER_HAND then "LeftHand" else "RightHand"
	local handPart = resolveHandPart(bossModel, handName)
	if handPart and handPart.Parent ~= nil then
		return handPart.Position
	end

	return bossRootPart.Position
end

local function resolveProjectileEndHeight(bossRootPart: BasePart, aimTargetRootPart: BasePart?): number
	if aimTargetRootPart and aimTargetRootPart.Parent ~= nil then
		return aimTargetRootPart.Position.Y
	end

	return bossRootPart.Position.Y
end

local function resolveProjectileBaseYawDegrees(index: number): number
	local localSlotIndex = if index <= PROJECTILES_PER_HAND then index else index - PROJECTILES_PER_HAND
	return (localSlotIndex - ((PROJECTILES_PER_HAND + 1) / 2)) * THROW_YAW_STEP_DEGREES
end

local function rotatePlanarDirection(forwardDirection: Vector3, yawDegrees: number): Vector3
	local rotatedDirection = CFrame.Angles(0, math.rad(yawDegrees), 0):VectorToWorldSpace(forwardDirection)
	local planarDirection = Vector3.new(rotatedDirection.X, 0, rotatedDirection.Z)
	if planarDirection.Magnitude > 0.001 then
		return planarDirection.Unit
	end

	return forwardDirection
end

local function resolveHeldChickenCFrame(handPart: BasePart, yawOffset: number): CFrame
	return handPart.CFrame * CFrame.Angles(0, yawOffset, 0) * HOLD_ROTATION_OFFSET
end

local function resolveProjectileLaunchCFrame(bossModel: Model, index: number): CFrame?
	local handName = if index <= PROJECTILES_PER_HAND then "LeftHand" else "RightHand"
	local handPart = resolveHandPart(bossModel, handName)
	if handPart == nil or handPart.Parent == nil then
		return nil
	end

	return resolveHeldChickenCFrame(handPart, math.rad(resolveProjectileBaseYawDegrees(index)))
end

local function quantizeSeedComponent(value: number): number
	return math.floor((value * 100) + if value >= 0 then 0.5 else -0.5)
end

local function mixSeed(seed: number, value: number): number
	return (seed * 1103515245 + value + 12345) % 2147483647
end

local function buildProjectileSpinSeed(index: number, startPosition: Vector3, endPosition: Vector3): number
	local seed = mixSeed(17, index)
	seed = mixSeed(seed, quantizeSeedComponent(startPosition.X))
	seed = mixSeed(seed, quantizeSeedComponent(startPosition.Y))
	seed = mixSeed(seed, quantizeSeedComponent(startPosition.Z))
	seed = mixSeed(seed, quantizeSeedComponent(endPosition.X))
	seed = mixSeed(seed, quantizeSeedComponent(endPosition.Y))
	seed = mixSeed(seed, quantizeSeedComponent(endPosition.Z))
	return math.max(1, seed)
end

local function resolveSignedSpinRadiansPerSecond(
	randomGenerator: Random,
	minDegreesPerSecond: number,
	maxDegreesPerSecond: number
): number
	local speedDegreesPerSecond = randomGenerator:NextNumber(minDegreesPerSecond, maxDegreesPerSecond)
	local directionSign = if randomGenerator:NextInteger(0, 1) == 0 then -1 else 1
	return math.rad(speedDegreesPerSecond * directionSign)
end

local function resolveProjectileSpinMotion(index: number, startPosition: Vector3, endPosition: Vector3): { [string]: number }
	local randomGenerator = Random.new(buildProjectileSpinSeed(index, startPosition, endPosition))
	return {
		primarySpinRadiansPerSecond = resolveSignedSpinRadiansPerSecond(
			randomGenerator,
			CHICKEN_PRIMARY_SPIN_MIN_DEGREES_PER_SECOND,
			CHICKEN_PRIMARY_SPIN_MAX_DEGREES_PER_SECOND
		),
		secondarySpinRadiansPerSecond = resolveSignedSpinRadiansPerSecond(
			randomGenerator,
			CHICKEN_SECONDARY_SPIN_MIN_DEGREES_PER_SECOND,
			CHICKEN_SECONDARY_SPIN_MAX_DEGREES_PER_SECOND
		),
		primaryPhaseRadians = math.rad(randomGenerator:NextNumber(0, 360)),
		secondaryPhaseRadians = math.rad(randomGenerator:NextNumber(0, 360)),
	}
end

local function resolveProjectileSpinCFrame(
	motion: { [string]: any },
	elapsedFlightSeconds: number,
	spinBlendAlpha: number
): CFrame
	local spinWeight = math.clamp(spinBlendAlpha, 0, 1)
	local primarySpinAngle = (
		(tonumber(motion.primarySpinRadiansPerSecond) or 0) * math.max(0, elapsedFlightSeconds)
		+ (tonumber(motion.primaryPhaseRadians) or 0)
	) * spinWeight
	local secondarySpinAngle = (
		(tonumber(motion.secondarySpinRadiansPerSecond) or 0) * math.max(0, elapsedFlightSeconds)
		+ (tonumber(motion.secondaryPhaseRadians) or 0)
	) * spinWeight
	return CFrame.Angles(primarySpinAngle, 0, 0) * CFrame.Angles(0, 0, secondarySpinAngle)
end

local function buildProjectilePlans(
	context,
	bossModel: Model,
	bossRootPart: BasePart,
	projectileSpeedStudsPerSecond: number,
	randomGenerator: Random
): { { [string]: any } }
	local aimTargetRootPart = resolveAimTargetRootPart(context, bossRootPart)
	local forwardDirection = resolveForwardDirection(context, bossRootPart, aimTargetRootPart)
	local endHeight = resolveProjectileEndHeight(bossRootPart, aimTargetRootPart)
	local plans = {}

	for index = 1, PROJECTILE_COUNT do
		local startPosition = resolveProjectileStartPosition(bossModel, index, bossRootPart)
		local baseYawDegrees = resolveProjectileBaseYawDegrees(index)
		local scatterYawDegrees = randomGenerator:NextNumber(
			-SHOTGUN_SCATTER_YAW_DEGREES,
			SHOTGUN_SCATTER_YAW_DEGREES
		)
		local projectileDirection = rotatePlanarDirection(forwardDirection, baseYawDegrees + scatterYawDegrees)
		local projectileDistance = PROJECTILE_DISTANCE_STUDS
			* randomGenerator:NextNumber(SHOTGUN_MIN_DISTANCE_SCALAR, SHOTGUN_MAX_DISTANCE_SCALAR)
		local projectileSpeed = projectileSpeedStudsPerSecond
			* randomGenerator:NextNumber(SHOTGUN_MIN_SPEED_SCALAR, SHOTGUN_MAX_SPEED_SCALAR)
		local endPlanarPosition = startPosition + (projectileDirection * projectileDistance)
		local endPosition = Vector3.new(endPlanarPosition.X, endHeight, endPlanarPosition.Z)
		local spinMotion = resolveProjectileSpinMotion(index, startPosition, endPosition)
		table.insert(plans, {
			index = index,
			startPosition = startPosition,
			endPosition = endPosition,
			launchCFrame = resolveProjectileLaunchCFrame(bossModel, index),
			primaryPhaseRadians = spinMotion.primaryPhaseRadians,
			primarySpinRadiansPerSecond = spinMotion.primarySpinRadiansPerSecond,
			secondaryPhaseRadians = spinMotion.secondaryPhaseRadians,
			secondarySpinRadiansPerSecond = spinMotion.secondarySpinRadiansPerSecond,
			travelDuration = CombatProjectileUtil.ResolveTravelDuration(
				startPosition,
				endPosition,
				projectileSpeed
			),
		})
	end

	return plans
end

local function buildPresentationProjectilePlans(projectilePlans: { { [string]: any } }): { { [string]: any } }
	local presentationPlans = {}
	for _, plan in ipairs(projectilePlans) do
		table.insert(presentationPlans, {
			index = plan.index,
			startPosition = plan.startPosition,
			endPosition = plan.endPosition,
			travelDuration = plan.travelDuration,
		})
	end

	return presentationPlans
end

local function getProjectilePosition(plan: { [string]: any }, startedAt: number): Vector3
	local startPosition = plan.startPosition
	local endPosition = plan.endPosition
	if typeof(startPosition) ~= "Vector3" or typeof(endPosition) ~= "Vector3" then
		return Vector3.zero
	end

	return CombatProjectileUtil.ResolveMotionPosition({
		startPosition = startPosition,
		impactPosition = endPosition,
		startedAt = startedAt,
		travelDuration = math.max(0.001, tonumber(plan.travelDuration) or 0),
	})
end

local function getProjectileAlpha(plan: { [string]: any }, startedAt: number): number
	return math.clamp((os.clock() - startedAt) / math.max(0.001, tonumber(plan.travelDuration) or 0), 0, 1)
end

local function getProjectileVisualCFrame(plan: { [string]: any }, startedAt: number): CFrame?
	local startPosition = plan.startPosition
	local endPosition = plan.endPosition
	if typeof(startPosition) ~= "Vector3" or typeof(endPosition) ~= "Vector3" then
		return nil
	end

	local alpha = getProjectileAlpha(plan, startedAt)
	local elapsedFlightSeconds = math.max(0, os.clock() - startedAt)
	local thrownCFrame = CombatProjectileUtil.ResolveProjectileCFrame(startPosition, endPosition, alpha)
		* FLIGHT_ROTATION_OFFSET
	local launchCFrame = plan.launchCFrame
	if typeof(launchCFrame) == "CFrame" then
		local blendAlpha = math.clamp(alpha / CHICKEN_RELEASE_BLEND_ALPHA, 0, 1)
		return launchCFrame:Lerp(thrownCFrame, blendAlpha)
			* resolveProjectileSpinCFrame(plan, elapsedFlightSeconds, blendAlpha)
	end

	return thrownCFrame * resolveProjectileSpinCFrame(plan, elapsedFlightSeconds, 1)
end

local function getProjectileHitboxCFrame(
	plan: { [string]: any },
	startedAt: number,
	boundsOffset: CFrame
): CFrame?
	local visualCFrame = getProjectileVisualCFrame(plan, startedAt)
	if visualCFrame == nil then
		return nil
	end

	return visualCFrame * boundsOffset
end

local function buildKnockbackDirection(
	impactPosition: Vector3,
	bossRootPart: BasePart,
	targetRootPart: BasePart?
): Vector3
	return CombatMoveUtil.BuildRadialKnockbackDirection({
		impactPosition = impactPosition,
		targetRootPart = targetRootPart,
		fallbackPosition = bossRootPart.Position,
		speed = KNOCKBACK_SPEED,
		upwardSpeed = KNOCKBACK_UPWARD_SPEED,
	})
end

function EatChicken.GetSelectionWeight(context)
	local aliveTargetCount = if typeof(context.aliveTargets) == "table" then #context.aliveTargets else 0
	if aliveTargetCount <= 0 then
		return 0
	end

	local distance = tonumber(context.distanceToTarget)
	if distance == nil then
		return 1
	end

	if distance <= 18 then
		return 0.5
	elseif distance <= 85 then
		return 1.1
	end

	return 0.85
end

function EatChicken.StartCast(context)
	local bossModel = context.bossModel
	local bossRootPart = context.bossRootPart
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return nil
	end

	local animationInstance = resolveAnimationInstance()
	if animationInstance == nil then
		warn("[EatChicken] Missing animation at ReplicatedStorage.GameAssets.Animations.MassiveGeezer.EatChicken.")
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[EatChicken] Failed to create animation profile:", profileOrError)
		return nil
	end

	local profile = profileOrError
	local track = nil :: AnimationTrack?
	local stoppedConnection = nil :: RBXScriptConnection?
	local projectileConnection = nil :: RBXScriptConnection?
	local activeHitboxes = {}
	local markersHit = {}
	local projectilePlans = {}
	local projectileStartedAt = 0
	local completed = false
	local cancelled = false
	local cleanedUp = false
	local stoppedPresentation = false
	local recoveryEndsAt = nil :: number?
	local projectileSpeedStudsPerSecond =
		BASE_PROJECTILE_SPEED_STUDS_PER_SECOND * CombatProjectileUtil.ResolveBasicProjectileSpeedScalar()
	local bossDefinition = context.bossDefinition
	local boneHitboxSize, boneHitboxOffset = resolveBoneProjectileHitboxGeometry(
		if bossDefinition then bossDefinition.scaleMultiplier else 1
	)
	if boneHitboxSize == nil or boneHitboxOffset == nil then
		warn("[EatChicken] Missing ChickenLeg bone bounds; falling back to radius projectile hitboxes.")
	end
	local shotgunRandom = Random.new()

	local function disconnectStoppedConnection()
		if stoppedConnection and stoppedConnection.Connected then
			stoppedConnection:Disconnect()
		end
		stoppedConnection = nil
	end

	local function disconnectProjectileConnection()
		if projectileConnection and projectileConnection.Connected then
			projectileConnection:Disconnect()
		end
		projectileConnection = nil
	end

	local function destroyActiveHitboxes()
		for _, hitbox in ipairs(activeHitboxes) do
			hitbox:Destroy()
		end
		table.clear(activeHitboxes)
	end

	local function stopPresentation()
		if stoppedPresentation then
			return
		end

		stoppedPresentation = true
		context.EmitPresentation("stop")
	end

	local function markComplete()
		if completed then
			return
		end

		completed = true
		recoveryEndsAt = os.clock() + (tonumber(context.move and context.move.recoverySeconds) or 0)
		disconnectProjectileConnection()
		destroyActiveHitboxes()
		stopPresentation()
	end

	local function cleanup(stopAnimation: boolean)
		if cleanedUp then
			return
		end

		cleanedUp = true
		disconnectStoppedConnection()
		disconnectProjectileConnection()
		destroyActiveHitboxes()
		stopPresentation()

		if stopAnimation and track then
			profile:StopAnimation(animationInstance, ANIMATION_FADE_SECONDS)
		end
	end

	local function handleChickenSpawn()
		if cancelled then
			return
		end

		markersHit[CHICKEN_SPAWN_MARKER_NAME] = true
		context.EmitPresentation("spawnChicken", {
			countPerHand = PROJECTILE_COUNT / 2,
			scaleMultiplier = context.bossDefinition.scaleMultiplier,
		})
	end

	local function handleAteChicken()
		if cancelled then
			return
		end

		markersHit[ATE_CHICKEN_MARKER_NAME] = true
		context.EmitPresentation("ateChicken")
	end

	local function handleTurnToPlayer()
		if cancelled or bossRootPart.Parent == nil then
			return
		end

		markersHit[TURN_TO_PLAYER_MARKER_NAME] = true
		local aimTargetRootPart = resolveAimTargetRootPart(context, bossRootPart)
		faceBossTowardDirection(bossRootPart, resolveForwardDirection(context, bossRootPart, aimTargetRootPart))
	end

	local function handleChickenThrow()
		if cancelled or bossModel.Parent == nil or bossRootPart.Parent == nil then
			return
		end

		markersHit[CHICKEN_THROW_MARKER_NAME] = true
		projectilePlans =
			buildProjectilePlans(context, bossModel, bossRootPart, projectileSpeedStudsPerSecond, shotgunRandom)
		projectileStartedAt = os.clock()

		context.EmitPresentation("throwBones", {
			projectiles = buildPresentationProjectilePlans(projectilePlans),
			projectileSpeed = projectileSpeedStudsPerSecond,
			scaleMultiplier = context.bossDefinition.scaleMultiplier,
		})

		local longestTravelDuration = 0
		for _, plan in ipairs(projectilePlans) do
			longestTravelDuration = math.max(longestTravelDuration, tonumber(plan.travelDuration) or 0)
			local hitPlayersForProjectile = {}
			local hitboxOptions: { [string]: any } = {
				debugVisibilityAttribute = "BossHitboxesVisible",
				hitboxOwner = bossModel,
				duration = plan.travelDuration,
				maxParts = PROJECTILE_MAX_PARTS,
			}

			if boneHitboxSize ~= nil and boneHitboxOffset ~= nil then
				hitboxOptions.getCFrame = function()
					if cancelled then
						return nil
					end

					return getProjectileHitboxCFrame(plan, projectileStartedAt, boneHitboxOffset)
				end
				hitboxOptions.size = boneHitboxSize
			else
				hitboxOptions.getPosition = function()
					if cancelled then
						return nil
					end

					return getProjectilePosition(plan, projectileStartedAt)
				end
				hitboxOptions.radius = FALLBACK_PROJECTILE_RADIUS
			end

			local hitbox
			hitboxOptions.onHit = function(targetModel: Model)
				local targetInfo = CombatMoveUtil.ResolveDamageTarget(targetModel)
				if targetInfo == nil then
					return
				end

				local player = targetInfo.player
				if player == nil or hitPlayersForProjectile[player] == true then
					return
				end

				hitPlayersForProjectile[player] = true
				targetInfo.humanoid:TakeDamage(CombatMoveUtil.ResolveScaledBossDamage(context, DAMAGE))

				Knockback(targetInfo.character, "Default", {
					Direction = buildKnockbackDirection(
						getProjectilePosition(plan, projectileStartedAt),
						bossRootPart,
						targetInfo.rootPart
					),
					Duration = KNOCKBACK_DURATION,
					RagdollDuration = RAGDOLL_DURATION,
					Stun = STUN_DURATION,
					IFrames = IFRAME_DURATION,
					AntiStun = ANTI_STUN_DURATION,
					GroundMode = "DeterministicMap",
				})
			end
			hitboxOptions.onDestroy = function()
				for activeIndex, activeHitbox in ipairs(activeHitboxes) do
					if activeHitbox == hitbox then
						table.remove(activeHitboxes, activeIndex)
						break
					end
				end
			end
			hitbox = CombatProjectileUtil.CreateTrackingHitbox(hitboxOptions)
			table.insert(activeHitboxes, hitbox)
		end

		projectileConnection = RunService.Heartbeat:Connect(function()
			if cancelled then
				disconnectProjectileConnection()
				return
			end

			if os.clock() - projectileStartedAt >= longestTravelDuration then
				markComplete()
			end
		end)
	end

	track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, {
		[CHICKEN_SPAWN_MARKER_NAME] = handleChickenSpawn,
		[ATE_CHICKEN_MARKER_NAME] = handleAteChicken,
		[TURN_TO_PLAYER_MARKER_NAME] = handleTurnToPlayer,
		[CHICKEN_THROW_MARKER_NAME] = handleChickenThrow,
	}, ANIMATION_FADE_SECONDS)
	if track == nil then
		warn("[EatChicken] Failed to play EatChicken animation.")
		return nil
	end

	context.EmitPresentation("start", {
		scaleMultiplier = context.bossDefinition.scaleMultiplier,
	})
	track.Looped = false
	stoppedConnection = track.Stopped:Connect(function()
		disconnectStoppedConnection()
		if cancelled or completed then
			return
		end

		if not markersHit[CHICKEN_THROW_MARKER_NAME] then
			warn(string.format(
				"[EatChicken] Animation '%s' completed without firing the '%s' marker.",
				animationInstance.Name,
				CHICKEN_THROW_MARKER_NAME
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

return table.freeze(EatChicken)
