local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local CombatMoveUtil = require(ReplicatedStorage.Shared.Combat.CombatMoveUtil)
local CombatProjectileUtil = require(ReplicatedStorage.Shared.Combat.CombatProjectileUtil)

local DAMAGE = 18
local CANNON_FIRE_SECONDS = 2.65
local CANNON_EMIT_SECONDS = 162 / 60
local PROJECTILE_FLY_VFX_SECONDS = 181 / 60
local ANIMATION_FADE_SECONDS = 0.08
local PROJECTILE_SPEED_STUDS_PER_SECOND = 75
local PROJECTILE_RADIUS = 5
local EXPLOSION_RADIUS = 16
local EXPLOSION_LIFETIME_SECONDS = 0.08
local DEFAULT_FORWARD_SHOT_DISTANCE = 70
local ANIMATION_FOLDER_NAME = "CaptainSquid"
local ANIMATION_NAME = "SquidCall"
local VFX_FOLDER_NAME = "VFX"
local CAPTAIN_SQUID_VFX_FOLDER_NAME = "CaptainSquid"
local SQUID_CALL_VFX_FOLDER_NAME = "SquidCall"
local CANNON_MODEL_NAME = "Cannon"
local CANNON_MIDDLE_NAME = "Middle"
local CANNON_MUZZLE_ATTACHMENT_NAME = "CannonBall"
local CANNON_ASSET_YAW_OFFSET_RADIANS = math.rad(90)

local stub = CreateExplicitBossMoveStub({
	bossId = "Captain Squid",
	moveLabel = "Squid Call",
	targetMode = "single",
	summaryTemplate = "{moveLabel} locks a cannon onto {target}",
	description = "Captain Squid summons a giant cannon that locks onto a player and shoots an explosive cannonball.",
})

local SquidCall = {
	CanUse = stub.CanUse,
	GetTargeting = stub.GetTargeting,
	ExecuteStub = stub.ExecuteStub,
}

local function resolveHumanoid(model: Model?): Humanoid?
	return CombatMoveUtil.ResolveHumanoid(model)
end

local function resolveRootPart(model: Model?): BasePart?
	return CombatMoveUtil.ResolveRootPart(model)
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

	local captainSquidFolder = animations:FindFirstChild(ANIMATION_FOLDER_NAME)
	if not (captainSquidFolder and captainSquidFolder:IsA("Folder")) then
		return nil
	end

	local animationInstance = captainSquidFolder:FindFirstChild(ANIMATION_NAME)
	if animationInstance and animationInstance:IsA("Animation") then
		return animationInstance
	end

	return nil
end

local function resolveCannonSourceModel(): Model?
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	if not (gameAssets and gameAssets:IsA("Folder")) then
		return nil
	end

	local vfxFolder = gameAssets:FindFirstChild(VFX_FOLDER_NAME)
	if not (vfxFolder and vfxFolder:IsA("Folder")) then
		return nil
	end

	local captainSquidFolder = vfxFolder:FindFirstChild(CAPTAIN_SQUID_VFX_FOLDER_NAME)
	if not (captainSquidFolder and captainSquidFolder:IsA("Folder")) then
		return nil
	end

	local squidCallFolder = captainSquidFolder:FindFirstChild(SQUID_CALL_VFX_FOLDER_NAME)
	if not (squidCallFolder and squidCallFolder:IsA("Folder")) then
		return nil
	end

	local cannonModel = squidCallFolder:FindFirstChild(CANNON_MODEL_NAME)
	if cannonModel and cannonModel:IsA("Model") then
		return cannonModel
	end

	return nil
end

local function resolvePlanarDirection(fromPosition: Vector3, toPosition: Vector3?): Vector3
	return CombatMoveUtil.ResolvePlanarDirection(fromPosition, toPosition, nil)
end

local function resolveCannonBaseCFrame(originPosition: Vector3, targetPosition: Vector3?): CFrame
	local planarDirection = resolvePlanarDirection(originPosition, targetPosition)
	return CFrame.lookAt(originPosition, originPosition + planarDirection) * CFrame.Angles(0, CANNON_ASSET_YAW_OFFSET_RADIANS, 0)
end

local function resolveCannonBarrelCFrame(middleBaseCFrame: CFrame, targetPosition: Vector3?): CFrame
	if typeof(targetPosition) ~= "Vector3" then
		return middleBaseCFrame
	end

	local offset = targetPosition - middleBaseCFrame.Position
	if offset.Magnitude <= 0.001 then
		return middleBaseCFrame
	end

	local rightVector = -offset.Unit
	local upVector = middleBaseCFrame.UpVector - (rightVector * middleBaseCFrame.UpVector:Dot(rightVector))
	if upVector.Magnitude <= 0.001 then
		upVector = Vector3.yAxis - (rightVector * Vector3.yAxis:Dot(rightVector))
	end
	if upVector.Magnitude <= 0.001 then
		upVector = middleBaseCFrame.LookVector - (rightVector * middleBaseCFrame.LookVector:Dot(rightVector))
	end
	if upVector.Magnitude <= 0.001 then
		return middleBaseCFrame
	end

	return CFrame.fromMatrix(middleBaseCFrame.Position, rightVector, upVector.Unit)
end

local function resolveModelPrimaryPart(model: Model?): BasePart?
	if model == nil then
		return nil
	end

	local primaryPart = model.PrimaryPart
	if primaryPart then
		return primaryPart
	end

	local basePart = model:FindFirstChildWhichIsA("BasePart", true)
	if basePart then
		pcall(function()
			model.PrimaryPart = basePart
		end)
	end

	return basePart
end

local function probeCannonMuzzlePosition(
	scaleMultiplier: number,
	bossRootPart: BasePart,
	impactPosition: Vector3
): Vector3?
	local cannonSource = resolveCannonSourceModel()
	if cannonSource == nil then
		warn("[SquidCall] Missing cannon VFX model at ReplicatedStorage.GameAssets.VFX.CaptainSquid.SquidCall.Cannon.")
		return nil
	end

	local cannonModel = cannonSource:Clone()
	local probePivot = resolveModelPrimaryPart(cannonModel)
	local middle = cannonModel:FindFirstChild(CANNON_MIDDLE_NAME, true)
	if probePivot == nil or not (middle and middle:IsA("BasePart")) then
		cannonModel:Destroy()
		warn("[SquidCall] Cannon VFX model is missing a Primary/BasePart or Middle part.")
		return nil
	end

	local muzzleAttachment = middle:FindFirstChild(CANNON_MUZZLE_ATTACHMENT_NAME)
	if not (muzzleAttachment and muzzleAttachment:IsA("Attachment")) then
		cannonModel:Destroy()
		warn("[SquidCall] Cannon VFX model is missing Middle.CannonBall attachment.")
		return nil
	end

	local scaleOk, scaleError = pcall(function()
		cannonModel:ScaleTo(scaleMultiplier)
	end)
	if not scaleOk then
		cannonModel:Destroy()
		warn("[SquidCall] Failed to scale cannon VFX probe:", scaleError)
		return nil
	end

	local pivotCFrame = resolveCannonBaseCFrame(bossRootPart.Position, impactPosition)
	cannonModel:PivotTo(pivotCFrame)
	middle.CFrame = resolveCannonBarrelCFrame(middle.CFrame, impactPosition)

	local muzzlePosition = muzzleAttachment.WorldPosition
	cannonModel:Destroy()
	return muzzlePosition
end

local function resolveLockedTargetState(
	context,
	lockedTargetUserId: number?,
	lastKnownTargetPosition: Vector3?
): (Player?, BasePart?, Vector3?)
	local player = if lockedTargetUserId then Players:GetPlayerByUserId(lockedTargetUserId) else nil
	local character = if player then player.Character else nil
	local humanoid = resolveHumanoid(character)
	local rootPart = resolveRootPart(character)

	if player and humanoid and humanoid.Health > 0 and rootPart and rootPart.Parent ~= nil then
		return player, rootPart, rootPart.Position
	end

	return player, nil, lastKnownTargetPosition
end

local function applyExplosionDamage(
	bossModel: Model,
	impactPosition: Vector3,
	damagedTargets: { [Model]: boolean }
)
	return CombatProjectileUtil.CreateRadiusDamageHitbox({
		debugVisibilityAttribute = "BossHitboxesVisible",
		hitboxOwner = bossModel,
		impactPosition = impactPosition,
		radius = EXPLOSION_RADIUS,
		duration = EXPLOSION_LIFETIME_SECONDS,
		maxParts = 128,
		damage = DAMAGE,
		requirePlayerCharacter = false,
		onHit = function(targetInfo)
			damagedTargets[targetInfo.character] = true
		end,
	})
end

function SquidCall.StartCast(context)
	local bossModel = context.bossModel
	local bossRootPart = context.bossRootPart
	local animationInstance = resolveAnimationInstance()
	if bossModel == nil
		or bossModel.Parent == nil
		or bossRootPart == nil
		or bossRootPart.Parent == nil
		or animationInstance == nil then
		if animationInstance == nil then
			warn("[SquidCall] Missing animation at ReplicatedStorage.GameAssets.Animations.CaptainSquid.SquidCall.")
		end
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[SquidCall] Failed to create animation profile:", profileOrError)
		return nil
	end

	local profile = profileOrError
	local track = nil :: AnimationTrack?
	local stoppedConnection = nil :: RBXScriptConnection?
	local aimHeartbeat = nil :: RBXScriptConnection?
	local activeProjectileHitbox = nil
	local activeExplosionHitbox = nil
	local damagedTargets = {}
	local completed = false
	local cancelled = false
	local cleanedUp = false
	local recoveryEndsAt = nil :: number?
	local presentationStopped = false
	local lockedTargetUserId = if context.targetPlayer then context.targetPlayer.UserId else nil
	local lastKnownTargetPosition = if context.targetRootPart then context.targetRootPart.Position else nil
	local castStartedAt = os.clock()
	local projectileMotion = nil
	local projectileImpactPosition = nil :: Vector3?
	local aimSequenceStarted = false
	local fireTriggered = false

	local function stopPresentation()
		if presentationStopped then
			return
		end

		presentationStopped = true
		context.EmitPresentation("stop")
	end

	local function disconnectStoppedConnection()
		if stoppedConnection and stoppedConnection.Connected then
			stoppedConnection:Disconnect()
		end
		stoppedConnection = nil
	end

	local function disconnectAimHeartbeat()
		if aimHeartbeat and aimHeartbeat.Connected then
			aimHeartbeat:Disconnect()
		end
		aimHeartbeat = nil
	end

	local function destroyProjectileHitbox()
		if activeProjectileHitbox == nil then
			return
		end

		activeProjectileHitbox:Destroy()
		activeProjectileHitbox = nil
	end

	local function destroyExplosionHitbox()
		if activeExplosionHitbox == nil then
			return
		end

		activeExplosionHitbox:Destroy()
		activeExplosionHitbox = nil
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
		disconnectStoppedConnection()
		disconnectAimHeartbeat()
		destroyProjectileHitbox()
		destroyExplosionHitbox()

		if stopAnimation and track then
			profile:StopAnimation(animationInstance, ANIMATION_FADE_SECONDS)
		end
	end

	local function getCurrentProjectilePosition(): Vector3
		if projectileMotion == nil then
			return projectileImpactPosition or bossRootPart.Position
		end

		return CombatProjectileUtil.ResolveMotionPosition(projectileMotion)
	end

	local exploded = false
	local function explodeAt(impactPosition: Vector3)
		if cancelled or exploded then
			return
		end

		exploded = true
		destroyProjectileHitbox()
		context.EmitPresentation("impact", {
			impactPosition = impactPosition,
			explosionRadius = EXPLOSION_RADIUS,
			scaleMultiplier = context.bossDefinition.scaleMultiplier,
		})
		activeExplosionHitbox = applyExplosionDamage(bossModel, impactPosition, damagedTargets)
	end

	local function fireProjectile()
		if cancelled or fireTriggered or bossModel.Parent == nil or bossRootPart.Parent == nil then
			return
		end
		fireTriggered = true

		local _, liveTargetRootPart, resolvedTargetPosition = resolveLockedTargetState(
			context,
			lockedTargetUserId,
			lastKnownTargetPosition
		)
		lastKnownTargetPosition = resolvedTargetPosition

		local forwardDirection = Vector3.new(bossRootPart.CFrame.LookVector.X, 0, bossRootPart.CFrame.LookVector.Z)
		if forwardDirection.Magnitude <= 0.001 then
			forwardDirection = Vector3.new(0, 0, -1)
		else
			forwardDirection = forwardDirection.Unit
		end

		local fallbackImpactPosition = bossRootPart.Position + (forwardDirection * DEFAULT_FORWARD_SHOT_DISTANCE)
		local resolvedImpactPosition = resolvedTargetPosition or fallbackImpactPosition
		local resolvedStartPosition = probeCannonMuzzlePosition(
			context.bossDefinition.scaleMultiplier,
			bossRootPart,
			resolvedImpactPosition
		) or bossRootPart.Position
		projectileMotion = CombatProjectileUtil.CreateLinearMotion(
			resolvedStartPosition,
			resolvedImpactPosition,
			PROJECTILE_SPEED_STUDS_PER_SECOND
		)
		projectileImpactPosition = resolvedImpactPosition

		context.EmitPresentation("fire", {
			targetUserId = lockedTargetUserId,
			startPosition = resolvedStartPosition,
			impactPosition = resolvedImpactPosition,
			travelDuration = projectileMotion.travelDuration,
			projectileSpeed = PROJECTILE_SPEED_STUDS_PER_SECOND,
			explosionRadius = EXPLOSION_RADIUS,
			scaleMultiplier = context.bossDefinition.scaleMultiplier,
			flyDelaySeconds = math.max(0, PROJECTILE_FLY_VFX_SECONDS - CANNON_FIRE_SECONDS),
		})

		if liveTargetRootPart and liveTargetRootPart.Parent ~= nil then
			lastKnownTargetPosition = liveTargetRootPart.Position
		end

		if projectileMotion.travelDuration <= 0 then
			explodeAt(resolvedImpactPosition)
			markComplete()
			return
		end

		local projectileHitbox
		projectileHitbox = CombatProjectileUtil.CreateTrackingHitbox({
			debugVisibilityAttribute = "BossHitboxesVisible",
			hitboxOwner = bossModel,
			getPosition = getCurrentProjectilePosition,
			radius = PROJECTILE_RADIUS,
			duration = projectileMotion.travelDuration,
			maxParts = 64,
			onHit = function(_targetModel: Model)
				explodeAt(getCurrentProjectilePosition())
			end,
			onDestroy = function()
				if activeProjectileHitbox == projectileHitbox then
					activeProjectileHitbox = nil
				end

				if not exploded and not cancelled and projectileImpactPosition then
					explodeAt(projectileImpactPosition)
				end
			end,
		})

		activeProjectileHitbox = projectileHitbox
		markComplete()
	end

	local function beginAimSequence()
		if cancelled or aimSequenceStarted then
			return
		end
		aimSequenceStarted = true

		local _, lockedRootPart, lockedPosition = resolveLockedTargetState(context, lockedTargetUserId, lastKnownTargetPosition)
		lastKnownTargetPosition = lockedPosition
		local elapsedSeconds = math.max(0, os.clock() - castStartedAt)
		local aimDuration = math.max(0.05, CANNON_FIRE_SECONDS - elapsedSeconds)
		context.EmitPresentation("summon", {
			targetUserId = lockedTargetUserId,
			aimDuration = aimDuration,
			cannonEmitDelaySeconds = math.max(0, CANNON_EMIT_SECONDS - elapsedSeconds),
			scaleMultiplier = context.bossDefinition.scaleMultiplier,
		})

		disconnectAimHeartbeat()
		aimHeartbeat = RunService.Heartbeat:Connect(function()
			if cancelled then
				disconnectAimHeartbeat()
				return
			end

			local _, updatedRootPart, updatedPosition = resolveLockedTargetState(context, lockedTargetUserId, lastKnownTargetPosition)
			if updatedPosition then
				lastKnownTargetPosition = updatedPosition
			end
			lockedRootPart = updatedRootPart
		end)

		task.delay(aimDuration, function()
			disconnectAimHeartbeat()
			fireProjectile()
		end)
	end

	track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, nil, ANIMATION_FADE_SECONDS)
	if track == nil then
		warn("[SquidCall] Failed to play SquidCall animation.")
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

		beginAimSequence()
	end)

	return {
		Cancel = function()
			if cancelled then
				return
			end

			cancelled = true
			completed = true
			recoveryEndsAt = os.clock()
			stopPresentation()
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

return table.freeze(SquidCall)
