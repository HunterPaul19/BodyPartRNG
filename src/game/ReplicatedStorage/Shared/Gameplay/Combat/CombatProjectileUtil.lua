local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatMoveUtil = require(ReplicatedStorage.Shared.Combat.CombatMoveUtil)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)

local CombatProjectileUtil = {}

local BASIC_PROJECTILE_SPEED_SCALAR_ATTRIBUTE = "BasicProjectileSpeedScalar"
local BASIC_PROJECTILE_SPEED_SCALAR_FALLBACK = 1.5
local BASIC_PROJECTILE_SPEED_SCALAR_MINIMUM = 0.001

export type ProjectileMotion = {
	startPosition: Vector3,
	impactPosition: Vector3,
	controlPosition: Vector3?,
	startedAt: number,
	travelDuration: number,
}

function CombatProjectileUtil.ResolveBasicProjectileSpeedScalar(): number
	local scalar = tonumber(Workspace:GetAttribute(BASIC_PROJECTILE_SPEED_SCALAR_ATTRIBUTE))
	if scalar == nil or scalar ~= scalar then
		return BASIC_PROJECTILE_SPEED_SCALAR_FALLBACK
	end

	return math.max(BASIC_PROJECTILE_SPEED_SCALAR_MINIMUM, scalar)
end

function CombatProjectileUtil.ResolveTravelDuration(
	startPosition: Vector3,
	impactPosition: Vector3,
	speedStudsPerSecond: number
): number
	local speed = math.max(0.001, tonumber(speedStudsPerSecond) or 0)
	return (impactPosition - startPosition).Magnitude / speed
end

function CombatProjectileUtil.CreateLinearMotion(
	startPosition: Vector3,
	impactPosition: Vector3,
	speedStudsPerSecond: number,
	startedAt: number?
): ProjectileMotion
	return {
		startPosition = startPosition,
		impactPosition = impactPosition,
		startedAt = startedAt or os.clock(),
		travelDuration = CombatProjectileUtil.ResolveTravelDuration(startPosition, impactPosition, speedStudsPerSecond),
	}
end

function CombatProjectileUtil.GetMotionAlpha(motion: ProjectileMotion, now: number?): number
	return math.clamp(((now or os.clock()) - motion.startedAt) / math.max(0.001, motion.travelDuration), 0, 1)
end

function CombatProjectileUtil.ResolveLinearPosition(startPosition: Vector3, impactPosition: Vector3, alpha: number): Vector3
	return startPosition:Lerp(impactPosition, math.clamp(alpha, 0, 1))
end

function CombatProjectileUtil.ResolveQuadraticBezierPosition(
	startPosition: Vector3,
	controlPosition: Vector3,
	impactPosition: Vector3,
	alpha: number
): Vector3
	local clampedAlpha = math.clamp(alpha, 0, 1)
	local first = startPosition:Lerp(controlPosition, clampedAlpha)
	local second = controlPosition:Lerp(impactPosition, clampedAlpha)
	return first:Lerp(second, clampedAlpha)
end

function CombatProjectileUtil.ResolveMotionPosition(motion: ProjectileMotion, now: number?): Vector3
	local alpha = CombatProjectileUtil.GetMotionAlpha(motion, now)
	if motion.controlPosition ~= nil then
		return CombatProjectileUtil.ResolveQuadraticBezierPosition(
			motion.startPosition,
			motion.controlPosition,
			motion.impactPosition,
			alpha
		)
	end

	return CombatProjectileUtil.ResolveLinearPosition(motion.startPosition, motion.impactPosition, alpha)
end

function CombatProjectileUtil.ResolveProjectileCFrame(
	startPosition: Vector3,
	impactPosition: Vector3,
	alpha: number,
	controlPosition: Vector3?
): CFrame
	local position
	local lookAheadPosition
	if controlPosition ~= nil then
		position = CombatProjectileUtil.ResolveQuadraticBezierPosition(startPosition, controlPosition, impactPosition, alpha)
		lookAheadPosition = CombatProjectileUtil.ResolveQuadraticBezierPosition(
			startPosition,
			controlPosition,
			impactPosition,
			math.clamp(alpha + 0.03, 0, 1)
		)
	else
		position = CombatProjectileUtil.ResolveLinearPosition(startPosition, impactPosition, alpha)
		lookAheadPosition = CombatProjectileUtil.ResolveLinearPosition(startPosition, impactPosition, math.clamp(alpha + 0.03, 0, 1))
	end

	local travelVector = lookAheadPosition - position
	if travelVector.Magnitude > 0.001 then
		return CFrame.lookAt(position, position + travelVector.Unit)
	end

	local fullTravelVector = impactPosition - startPosition
	if fullTravelVector.Magnitude > 0.001 then
		return CFrame.lookAt(position, position + fullTravelVector.Unit)
	end

	return CFrame.new(position)
end

function CombatProjectileUtil.ResolveArcControlPosition(
	startPosition: Vector3,
	impactPosition: Vector3,
	minArcHeight: number,
	maxArcHeight: number,
	distanceHeightScale: number?
): Vector3
	local midpoint = startPosition:Lerp(impactPosition, 0.5)
	local distance = (impactPosition - startPosition).Magnitude
	local arcHeight = math.clamp(
		distance * (tonumber(distanceHeightScale) or 0.65),
		math.max(0, tonumber(minArcHeight) or 0),
		math.max(0, tonumber(maxArcHeight) or 0)
	)
	return midpoint + Vector3.new(0, arcHeight, 0)
end

function CombatProjectileUtil.ResolveGroundImpactPosition(
	targetPosition: Vector3,
	options: any
): Vector3
	return CombatMoveUtil.RaycastGroundNear(targetPosition, options) or targetPosition
end

function CombatProjectileUtil.ResolveFallbackImpactPosition(options: {
	sourceModel: Model?,
	sourceRootPart: BasePart,
	targetCharacter: Model?,
	targetRootPart: BasePart?,
	fallbackDistance: number,
	raycastStartHeight: number?,
	raycastDistance: number?,
}): Vector3
	if options.targetRootPart and options.targetRootPart.Parent ~= nil then
		return CombatProjectileUtil.ResolveGroundImpactPosition(options.targetRootPart.Position, {
			sourceModel = options.sourceModel,
			targetCharacter = options.targetCharacter,
			startHeight = options.raycastStartHeight,
			distance = options.raycastDistance,
		})
	end

	local fallbackPosition = options.sourceRootPart.Position
		+ (CombatMoveUtil.ResolvePlanarForward(options.sourceRootPart, nil) * math.max(0, tonumber(options.fallbackDistance) or 0))
	return CombatProjectileUtil.ResolveGroundImpactPosition(fallbackPosition, {
		sourceModel = options.sourceModel,
		targetCharacter = options.targetCharacter,
		startHeight = options.raycastStartHeight,
		distance = options.raycastDistance,
	})
end

function CombatProjectileUtil.CreateTrackingHitbox(options: {
	hitboxOwner: Model,
	getPosition: (() -> Vector3?)?,
	getCFrame: (() -> CFrame?)?,
	radius: number?,
	size: Vector3?,
	duration: number,
	maxParts: number?,
	debugVisibilityAttribute: string?,
	onHit: ((targetModel: Model) -> ())?,
	onDestroy: (() -> ())?,
})
	local hitbox
	local hitboxData: { [string]: any } = {
		Character = options.hitboxOwner,
		HitboxCFrame = function()
			if options.getCFrame then
				return options.getCFrame()
			end

			if not options.getPosition then
				return nil
			end

			local currentPosition = options.getPosition()
			if currentPosition == nil then
				return nil
			end
			return CFrame.new(currentPosition)
		end,
		HitboxType = "SpacialQuery",
		Time = math.max(0, tonumber(options.duration) or 0),
		MaxParts = math.max(1, tonumber(options.maxParts) or 64),
		DebugVisibilityAttribute = options.debugVisibilityAttribute,
	}
	if options.size ~= nil then
		hitboxData.HitboxSize = options.size
	else
		hitboxData.HitboxRadius = math.max(0, tonumber(options.radius) or 0)
	end

	hitbox = Hitbox.new(hitboxData, {
		HitTarget = function(targetModel: Model)
			if options.onHit then
				options.onHit(targetModel)
			end
		end,
		HitboxDestroy = function()
			hitbox = nil
			if options.onDestroy then
				options.onDestroy()
			end
		end,
	})

	return hitbox
end

function CombatProjectileUtil.CreateRadiusDamageHitbox(options: {
	hitboxOwner: Model,
	impactPosition: Vector3,
	radius: number,
	duration: number,
	maxParts: number?,
	damage: number,
	requirePlayerCharacter: boolean?,
	debugVisibilityAttribute: string?,
	onHit: ((targetInfo: any) -> ())?,
	onDestroy: (() -> ())?,
})
	local hitTargets = {}
	local hitbox
	hitbox = Hitbox.new({
		Character = options.hitboxOwner,
		HitboxCFrame = CFrame.new(options.impactPosition),
		HitboxRadius = math.max(0, tonumber(options.radius) or 0),
		HitboxType = "SpacialQuery",
		Time = math.max(0, tonumber(options.duration) or 0),
		MaxParts = math.max(1, tonumber(options.maxParts) or 128),
		DebugVisibilityAttribute = options.debugVisibilityAttribute,
	}, {
		HitTarget = function(targetModel: Model)
			local targetInfo = CombatMoveUtil.DamageOnce(
				hitTargets,
				targetModel,
				options.damage,
				options.requirePlayerCharacter
			)
			if targetInfo ~= nil and options.onHit then
				options.onHit(targetInfo)
			end
		end,
		HitboxDestroy = function()
			hitbox = nil
			if options.onDestroy then
				options.onDestroy()
			end
		end,
	})

	return hitbox
end

function CombatProjectileUtil.DestroyHitbox(hitbox)
	if hitbox ~= nil then
		hitbox:Destroy()
	end
end

return table.freeze(CombatProjectileUtil)
