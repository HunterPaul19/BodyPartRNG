local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local CombatMoveUtil = require(ReplicatedStorage.Shared.Combat.CombatMoveUtil)
local CombatProjectileUtil = require(ReplicatedStorage.Shared.Combat.CombatProjectileUtil)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local Knockback = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Knockback)

local IMPACT_DAMAGE = 150
local LAVA_DAMAGE_PER_TICK = 35
local LAVA_DURATION_SECONDS = 3
local LAVA_TICK_INTERVAL_SECONDS = 1
local LAVA_POOL_HEIGHT = 8
local BASE_EXPLOSION_RADIUS = 22
local EXPLOSION_SCALE_MULTIPLIER = 2
local EXPLOSION_RADIUS = BASE_EXPLOSION_RADIUS * EXPLOSION_SCALE_MULTIPLIER
local EXPLOSION_HITBOX_DURATION_SECONDS = 0.12
local BASE_PROJECTILE_SPEED_STUDS_PER_SECOND = 100
local PROJECTILE_RADIUS = 5
local FALLBACK_THROW_DISTANCE_STUDS = 120
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "MagmaFiend"
local ANIMATION_NAME = "MagmaThrow"
local THROW_MARKER_NAME = "Throw"
local FLOOR_RAYCAST_START_HEIGHT = 20
local FLOOR_RAYCAST_DISTANCE = 350
local MIN_PROJECTILE_ARC_HEIGHT = 1.5
local MAX_PROJECTILE_ARC_HEIGHT = 4
local PROJECTILE_ARC_DISTANCE_HEIGHT_SCALE = 0.04

local stub = CreateExplicitBossMoveStub({
	bossId = "Magma Fiend",
	moveLabel = "Magma Throw",
	targetMode = "single",
	summaryTemplate = "{moveLabel} lobs molten rock at {target}",
	description = "Magma Fiend throws a ball of magma at a player that leaves behind a damaging area of lava.",
})

local MagmaThrow = {
	GetTargeting = stub.GetTargeting,
	ExecuteStub = stub.ExecuteStub,
}

local function getWeightedValue(distance: number, points: { { distance: number, weight: number } }): number
	if distance <= points[1].distance then
		return points[1].weight
	end

	for index = 2, #points do
		local previousPoint = points[index - 1]
		local currentPoint = points[index]
		if distance <= currentPoint.distance then
			local alpha = (distance - previousPoint.distance) / math.max(0.001, currentPoint.distance - previousPoint.distance)
			return previousPoint.weight + ((currentPoint.weight - previousPoint.weight) * alpha)
		end
	end

	return points[#points].weight
end

local function resolveAnimationInstance(): Animation?
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	if not (gameAssets and gameAssets:IsA("Folder")) then
		return nil
	end

	local animations = gameAssets:FindFirstChild("Animations")
	if not (animations and animations:IsA("Folder")) then
		return nil
	end

	local magmaFiendFolder = animations:FindFirstChild(ANIMATION_FOLDER_NAME)
	if not (magmaFiendFolder and magmaFiendFolder:IsA("Folder")) then
		return nil
	end

	local animationInstance = magmaFiendFolder:FindFirstChild(ANIMATION_NAME)
	if animationInstance and animationInstance:IsA("Animation") then
		return animationInstance
	end

	return nil
end

local function resolveHumanoid(model: Model?): Humanoid?
	return CombatMoveUtil.ResolveHumanoid(model)
end

local function resolveRootPart(model: Model?): BasePart?
	return CombatMoveUtil.ResolveRootPart(model)
end

local function resolveLeftHandPart(model: Model?): BasePart?
	return CombatMoveUtil.ResolveNamedPart(model, {
		"LeftHand",
		"Left Hand",
	})
end

local function buildFloorRaycastParams(bossModel: Model): RaycastParams
	return CombatMoveUtil.BuildFloorRaycastParams({
		sourceModel = bossModel,
	})
end

local function raycastGroundNear(position: Vector3, bossModel: Model, targetCharacter: Model?): Vector3?
	return CombatMoveUtil.RaycastGroundNear(position, {
		sourceModel = bossModel,
		targetCharacter = targetCharacter,
		startHeight = FLOOR_RAYCAST_START_HEIGHT,
		distance = FLOOR_RAYCAST_DISTANCE,
	})
end

local function resolveNearestAliveTarget(context, bossRootPart: BasePart)
	return CombatMoveUtil.ResolveNearestAliveTarget(bossRootPart.Position, context.aliveTargets or {})
end

local function resolvePlanarForwardDirection(bossRootPart: BasePart): Vector3
	return CombatMoveUtil.ResolvePlanarForward(bossRootPart, nil)
end

local function resolveImpactPosition(bossModel: Model, bossRootPart: BasePart, targetData): Vector3
	if targetData and targetData.rootPart and targetData.rootPart.Parent ~= nil then
		return raycastGroundNear(targetData.rootPart.Position, bossModel, targetData.character) or targetData.rootPart.Position
	end

	local fallbackPosition = bossRootPart.Position + (resolvePlanarForwardDirection(bossRootPart) * FALLBACK_THROW_DISTANCE_STUDS)
	return raycastGroundNear(fallbackPosition, bossModel, targetData and targetData.character) or fallbackPosition
end

local function resolveProjectileControlPosition(startPosition: Vector3, impactPosition: Vector3): Vector3
	return CombatProjectileUtil.ResolveArcControlPosition(
		startPosition,
		impactPosition,
		MIN_PROJECTILE_ARC_HEIGHT,
		MAX_PROJECTILE_ARC_HEIGHT,
		PROJECTILE_ARC_DISTANCE_HEIGHT_SCALE
	)
end

local function buildKnockbackDirection(impactPosition: Vector3, targetRootPart: BasePart?): Vector3
	return CombatMoveUtil.BuildRadialKnockbackDirection({
		impactPosition = impactPosition,
		targetRootPart = targetRootPart,
		speed = 48,
		upwardSpeed = 18,
	})
end

local function applyExplosionDamage(context, bossModel: Model, impactPosition: Vector3)
	CombatProjectileUtil.CreateRadiusDamageHitbox({
		debugVisibilityAttribute = "BossHitboxesVisible",
		hitboxOwner = bossModel,
		impactPosition = impactPosition,
		radius = EXPLOSION_RADIUS,
		duration = EXPLOSION_HITBOX_DURATION_SECONDS,
		maxParts = 256,
		damage = CombatMoveUtil.ResolveScaledBossDamage(context, IMPACT_DAMAGE),
		onHit = function(targetInfo)
			Knockback(targetInfo.character, "Default", {
				Direction = buildKnockbackDirection(impactPosition, targetInfo.rootPart),
				Duration = 0.2,
				RagdollDuration = 0.55,
				Stun = 0.35,
				IFrames = 0.2,
				AntiStun = 0.45,
				GroundMode = "DeterministicMap",
			})
		end,
	})
end

local function spawnLavaPoolHitbox(context, bossModel: Model, impactPosition: Vector3)
	local lastDamagedAtByTarget = {}
	local hitbox
	hitbox = Hitbox.new({
		DebugVisibilityAttribute = "BossHitboxesVisible",
		Character = bossModel,
		HitboxCFrame = CFrame.new(impactPosition + Vector3.new(0, LAVA_POOL_HEIGHT * 0.5, 0)),
		HitboxSize = Vector3.new(EXPLOSION_RADIUS * 2, LAVA_POOL_HEIGHT, EXPLOSION_RADIUS * 2),
		HitboxType = "SpacialQuery",
		Time = LAVA_DURATION_SECONDS,
		TickTime = LAVA_TICK_INTERVAL_SECONDS,
		MaxParts = 256,
	}, {
		HitTarget = function(targetModel: Model)
			local targetInfo = CombatMoveUtil.ResolveDamageTarget(targetModel)
			if targetInfo == nil then
				return
			end

			local now = os.clock()
			local lastDamagedAt = lastDamagedAtByTarget[targetModel]
			if lastDamagedAt ~= nil and (now - lastDamagedAt) < (LAVA_TICK_INTERVAL_SECONDS * 0.85) then
				return
			end

			lastDamagedAtByTarget[targetModel] = now
			targetInfo.humanoid:TakeDamage(CombatMoveUtil.ResolveScaledBossDamage(context, LAVA_DAMAGE_PER_TICK))
		end,
		HitboxDestroy = function()
			hitbox = nil
			lastDamagedAtByTarget = {}
		end,
	})

	return hitbox
end

function MagmaThrow.GetSelectionWeight(context)
	local distance = tonumber(context.distanceToTarget)
	if distance == nil then
		return 1
	end

	return getWeightedValue(distance, {
		{ distance = 0, weight = 0.05 },
		{ distance = 16, weight = 0.35 },
		{ distance = 32, weight = 0.8 },
		{ distance = 58, weight = 1.25 },
		{ distance = 82, weight = 1.05 },
		{ distance = 105, weight = 0.5 },
	})
end

function MagmaThrow.CanUse(context)
	local canUse, reason = stub.CanUse(context)
	if canUse ~= true then
		return false, reason
	end

	return true
end

function MagmaThrow.StartCast(context)
	local bossModel = context.bossModel
	local bossRootPart = context.bossRootPart
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return nil
	end

	local animationInstance = resolveAnimationInstance()
	if animationInstance == nil then
		warn("[MagmaThrow] Missing animation at ReplicatedStorage.GameAssets.Animations.MagmaFiend.MagmaThrow.")
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[MagmaThrow] Failed to create animation profile:", profileOrError)
		return nil
	end

	local profile = profileOrError
	local track = nil :: AnimationTrack?
	local stoppedConnection = nil :: RBXScriptConnection?
	local projectileConnection = nil :: RBXScriptConnection?
	local activeProjectileHitbox = nil
	local activeLavaPoolHitbox = nil
	local completed = false
	local cancelled = false
	local cleanedUp = false
	local throwTriggered = false
	local presentationStopped = false
	local recoveryEndsAt = nil :: number?
	local projectileMotion = nil
	local projectileSpeedStudsPerSecond =
		BASE_PROJECTILE_SPEED_STUDS_PER_SECOND * CombatProjectileUtil.ResolveBasicProjectileSpeedScalar()

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

	local function destroyProjectileHitbox()
		if activeProjectileHitbox == nil then
			return
		end

		activeProjectileHitbox:Destroy()
		activeProjectileHitbox = nil
	end

	local function destroyLavaPoolHitbox()
		if activeLavaPoolHitbox == nil then
			return
		end

		activeLavaPoolHitbox:Destroy()
		activeLavaPoolHitbox = nil
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
	end

	local function cleanup(stopAnimation: boolean)
		if cleanedUp then
			return
		end

		cleanedUp = true
		stopPresentation()
		disconnectStoppedConnection()
		disconnectProjectileConnection()
		destroyProjectileHitbox()
		destroyLavaPoolHitbox()

		if stopAnimation and track then
			profile:StopAnimation(animationInstance, ANIMATION_FADE_SECONDS)
		end
	end

	local function getCurrentProjectilePosition(): Vector3?
		if projectileMotion == nil then
			return nil
		end

		return CombatProjectileUtil.ResolveMotionPosition(projectileMotion)
	end

	local function explodeAt(impactPosition: Vector3)
		if cancelled or completed then
			return
		end

		context.EmitPresentation("impact", {
			impactPosition = impactPosition,
			explosionRadius = EXPLOSION_RADIUS,
			scaleMultiplier = context.bossDefinition.scaleMultiplier * EXPLOSION_SCALE_MULTIPLIER,
		})
		applyExplosionDamage(context, bossModel, impactPosition)
		destroyLavaPoolHitbox()
		activeLavaPoolHitbox = spawnLavaPoolHitbox(context, bossModel, impactPosition)
		stopPresentation()
		disconnectProjectileConnection()
		destroyProjectileHitbox()
		markComplete()
	end

	local function throwProjectile()
		if cancelled or throwTriggered or bossModel.Parent == nil or bossRootPart.Parent == nil then
			return
		end

		throwTriggered = true
		local targetData = resolveNearestAliveTarget(context, bossRootPart)
		local impactPosition = resolveImpactPosition(bossModel, bossRootPart, targetData)
		local leftHand = resolveLeftHandPart(bossModel)
		local startPosition = if leftHand and leftHand.Parent ~= nil then leftHand.Position else bossRootPart.Position
		local controlPosition = resolveProjectileControlPosition(startPosition, impactPosition)
		projectileMotion = CombatProjectileUtil.CreateLinearMotion(
			startPosition,
			impactPosition,
			projectileSpeedStudsPerSecond
		)
		projectileMotion.controlPosition = controlPosition

		context.EmitPresentation("throw", {
			startPosition = startPosition,
			controlPosition = controlPosition,
			impactPosition = impactPosition,
			travelDuration = projectileMotion.travelDuration,
			projectileSpeed = projectileSpeedStudsPerSecond,
			targetUserId = if targetData then targetData.player.UserId else nil,
			scaleMultiplier = context.bossDefinition.scaleMultiplier,
		})

		if projectileMotion.travelDuration <= 0 then
			explodeAt(impactPosition)
			return
		end

		activeProjectileHitbox = CombatProjectileUtil.CreateTrackingHitbox({
			debugVisibilityAttribute = "BossHitboxesVisible",
			hitboxOwner = bossModel,
			getPosition = getCurrentProjectilePosition,
			radius = PROJECTILE_RADIUS,
			duration = projectileMotion.travelDuration,
			maxParts = 64,
			onDestroy = function()
				activeProjectileHitbox = nil
			end,
		})

		local previousPosition = startPosition
		local raycastParams = buildFloorRaycastParams(bossModel)
		projectileConnection = RunService.Heartbeat:Connect(function()
			if cancelled then
				disconnectProjectileConnection()
				return
			end

			local currentPosition = getCurrentProjectilePosition()
			if currentPosition == nil then
				explodeAt(impactPosition)
				return
			end

			local travelVector = currentPosition - previousPosition
			if travelVector.Magnitude > 0.001 then
				local raycastResult = Workspace:Raycast(previousPosition, travelVector, raycastParams)
				if raycastResult then
					explodeAt(raycastResult.Position)
					return
				end
			end

			previousPosition = currentPosition
			if CombatProjectileUtil.GetMotionAlpha(projectileMotion) >= 1 then
				explodeAt(impactPosition)
			end
		end)
	end

	track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, {
		[THROW_MARKER_NAME] = throwProjectile,
	}, ANIMATION_FADE_SECONDS)
	if track == nil then
		warn("[MagmaThrow] Failed to play MagmaThrow animation.")
		return nil
	end

	context.EmitPresentation("start", {
		scaleMultiplier = context.bossDefinition.scaleMultiplier,
	})
	track.Looped = false
	stoppedConnection = track.Stopped:Connect(function()
		disconnectStoppedConnection()
		if cancelled then
			return
		end
		if not throwTriggered then
			warn(string.format("[MagmaThrow] Animation '%s' completed without firing the '%s' marker.", animationInstance.Name, THROW_MARKER_NAME))
			markComplete()
			stopPresentation()
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

return table.freeze(MagmaThrow)
