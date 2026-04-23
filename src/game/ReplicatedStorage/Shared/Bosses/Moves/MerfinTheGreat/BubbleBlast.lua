local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local CombatMoveUtil = require(ReplicatedStorage.Shared.Combat.CombatMoveUtil)
local CombatProjectileUtil = require(ReplicatedStorage.Shared.Combat.CombatProjectileUtil)
local Knockback = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Knockback)

local DAMAGE = 16
local PROJECTILE_COUNT = 10
local PROJECTILE_SPEED_STUDS_PER_SECOND = 100
local EXPLOSION_RADIUS = 12
local EXPLOSION_HITBOX_DURATION_SECONDS = 0.1
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "MerfinTheGreat"
local ANIMATION_NAME = "BubbleBlast"
local BUBBLES_MARKER_NAME = "Bubbles"
local FLOOR_RAYCAST_START_HEIGHT = 80
local FLOOR_RAYCAST_DISTANCE = 450
local GRID_SPACING_STUDS = 14
local RANDOM_VARIANCE_STUDS = 5
local START_HEIGHT_SCALE = 0.75

local GRID_OFFSETS = table.freeze({
	Vector3.new(-2, 0, -0.5),
	Vector3.new(-1, 0, -0.5),
	Vector3.new(0, 0, -0.5),
	Vector3.new(1, 0, -0.5),
	Vector3.new(2, 0, -0.5),
	Vector3.new(-2, 0, 0.5),
	Vector3.new(-1, 0, 0.5),
	Vector3.new(0, 0, 0.5),
	Vector3.new(1, 0, 0.5),
	Vector3.new(2, 0, 0.5),
})

local stub = CreateExplicitBossMoveStub({
	bossId = "Merfin the Great",
	moveLabel = "Bubble Blast",
	targetMode = "all_players",
	summaryTemplate = "{moveLabel} peppers {targets} with water shots",
	description = "Merfin the Great shoots out 10 water ball projectiles at players.",
})

local BubbleBlast = {
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

	local merfinFolder = animations:FindFirstChild(ANIMATION_FOLDER_NAME)
	if not (merfinFolder and merfinFolder:IsA("Folder")) then
		return nil
	end

	local animationInstance = merfinFolder:FindFirstChild(ANIMATION_NAME)
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

local function resolveStandingHeight(bossHumanoid: Humanoid?, bossRootPart: BasePart): number
	return CombatMoveUtil.ResolveStandingHeight(bossHumanoid, bossRootPart)
end

local function resolveProjectileStartPosition(bossModel: Model, bossHumanoid: Humanoid?, bossRootPart: BasePart): Vector3
	local head = bossModel:FindFirstChild("Head", true)
	if head and head:IsA("BasePart") then
		return head.Position + Vector3.new(0, head.Size.Y * 0.65, 0)
	end

	return bossRootPart.Position + Vector3.new(0, resolveStandingHeight(bossHumanoid, bossRootPart) * START_HEIGHT_SCALE, 0)
end

local function buildFloorRaycastParams(bossModel: Model): RaycastParams
	return CombatMoveUtil.BuildFloorRaycastParams({
		sourceModel = bossModel,
	})
end

local function raycastGroundNear(position: Vector3, bossModel: Model): Vector3
	return CombatProjectileUtil.ResolveGroundImpactPosition(position, {
		sourceModel = bossModel,
		startHeight = FLOOR_RAYCAST_START_HEIGHT,
		distance = FLOOR_RAYCAST_DISTANCE,
	})
end

local function resolvePlanarBasis(bossRootPart: BasePart, targetPosition: Vector3?): (Vector3, Vector3)
	return CombatMoveUtil.ResolvePlanarBasis(bossRootPart, targetPosition)
end

local function buildKnockbackDirection(impactPosition: Vector3, targetRootPart: BasePart?): Vector3
	return CombatMoveUtil.BuildRadialKnockbackDirection({
		impactPosition = impactPosition,
		targetRootPart = targetRootPart,
		speed = 32,
		upwardSpeed = 12,
	})
end

local function applyExplosionDamage(bossModel: Model, impactPosition: Vector3)
	CombatProjectileUtil.CreateRadiusDamageHitbox({
		debugVisibilityAttribute = "BossHitboxesVisible",
		hitboxOwner = bossModel,
		impactPosition = impactPosition,
		radius = EXPLOSION_RADIUS,
		duration = EXPLOSION_HITBOX_DURATION_SECONDS,
		maxParts = 128,
		damage = DAMAGE,
		onHit = function(targetInfo)
			Knockback(targetInfo.character, "Default", {
				Direction = buildKnockbackDirection(impactPosition, targetInfo.rootPart),
				Duration = 0.18,
				RagdollDuration = 0.35,
				Stun = 0.25,
				IFrames = 0.15,
				AntiStun = 0.3,
				GroundMode = "DeterministicMap",
			})
		end,
	})
end

local function collectAliveTargets(context)
	return CombatMoveUtil.CollectAliveTargets(context.aliveTargets or {})
end

local function buildProjectilePlans(context, bossModel: Model, bossHumanoid: Humanoid?, bossRootPart: BasePart)
	local aliveTargets = collectAliveTargets(context)
	if #aliveTargets <= 0 then
		return {}
	end

	local plans = {}
	local startOrigin = resolveProjectileStartPosition(bossModel, bossHumanoid, bossRootPart)
	local rng = Random.new(math.floor(os.clock() * 1000000) % 2147483647)

	for index = 1, PROJECTILE_COUNT do
		local targetContext = aliveTargets[((index - 1) % #aliveTargets) + 1]
		local targetPosition = targetContext.rootPart.Position
		local right, forward = resolvePlanarBasis(bossRootPart, targetPosition)
		local gridOffset = GRID_OFFSETS[index] or Vector3.zero
		local randomOffset = Vector3.new(
			rng:NextNumber(-RANDOM_VARIANCE_STUDS, RANDOM_VARIANCE_STUDS),
			0,
			rng:NextNumber(-RANDOM_VARIANCE_STUDS, RANDOM_VARIANCE_STUDS)
		)
		local plannedPosition = targetPosition
			+ (right * (gridOffset.X * GRID_SPACING_STUDS))
			+ (forward * (gridOffset.Z * GRID_SPACING_STUDS))
			+ randomOffset
		local impactPosition = raycastGroundNear(plannedPosition, bossModel)
		local startPosition = startOrigin + Vector3.new(
			rng:NextNumber(-5, 5),
			rng:NextNumber(0, 8),
			rng:NextNumber(-5, 5)
		)
		local travelDistance = (impactPosition - startPosition).Magnitude

		table.insert(plans, {
			index = index,
			startPosition = startPosition,
			impactPosition = impactPosition,
			travelDuration = travelDistance / PROJECTILE_SPEED_STUDS_PER_SECOND,
			targetUserId = targetContext.player.UserId,
		})
	end

	return plans
end

function BubbleBlast.GetSelectionWeight(context)
	local aliveTargetCount = if typeof(context.aliveTargets) == "table" then #context.aliveTargets else 0
	if aliveTargetCount <= 0 then
		return 0
	end

	local distance = tonumber(context.distanceToTarget)
	if distance == nil then
		return 1
	end

	if distance <= 16 then
		return 0.45
	elseif distance <= 48 then
		return 0.9
	elseif distance <= 90 then
		return 1.15
	end

	return 0.45
end

function BubbleBlast.StartCast(context)
	local bossModel = context.bossModel
	local bossHumanoid = context.bossHumanoid
	local bossRootPart = context.bossRootPart
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return nil
	end

	local animationInstance = resolveAnimationInstance()
	if animationInstance == nil then
		warn("[BubbleBlast] Missing animation at ReplicatedStorage.GameAssets.Animations.MerfinTheGreat.BubbleBlast.")
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[BubbleBlast] Failed to create animation profile:", profileOrError)
		return nil
	end

	local profile = profileOrError
	local track = nil :: AnimationTrack?
	local stoppedConnection = nil :: RBXScriptConnection?
	local activeHitboxes = {}
	local impactTasksRemaining = 0
	local bubblesTriggered = false
	local warnedMissingBubbles = false
	local completed = false
	local cancelled = false
	local cleanedUp = false
	local stoppedPresentation = false
	local recoveryEndsAt = nil :: number?

	local function disconnectStoppedConnection()
		if stoppedConnection and stoppedConnection.Connected then
			stoppedConnection:Disconnect()
		end
		stoppedConnection = nil
	end

	local function stopPresentation()
		if stoppedPresentation then
			return
		end

		stoppedPresentation = true
		context.EmitPresentation("stop")
	end

	local function destroyActiveHitboxes()
		for _, hitbox in ipairs(activeHitboxes) do
			hitbox:Destroy()
		end
		table.clear(activeHitboxes)
	end

	local function markComplete()
		if completed then
			return
		end

		completed = true
		stopPresentation()
		recoveryEndsAt = os.clock() + (tonumber(context.move and context.move.recoverySeconds) or 0)
		destroyActiveHitboxes()
	end

	local function warnMissingBubbles()
		if warnedMissingBubbles or cancelled then
			return
		end

		warnedMissingBubbles = true
		warn(string.format(
			"[BubbleBlast] Animation '%s' completed without firing the '%s' marker.",
			animationInstance.Name,
			BUBBLES_MARKER_NAME
		))
	end

	local function cleanup(stopAnimation: boolean)
		if cleanedUp then
			return
		end

		cleanedUp = true
		stopPresentation()
		destroyActiveHitboxes()
		disconnectStoppedConnection()

		if stopAnimation and track then
			profile:StopAnimation(animationInstance, ANIMATION_FADE_SECONDS)
		end
	end

	local function explodeProjectile(projectilePlan)
		if cancelled or bossModel.Parent == nil then
			return
		end

		context.EmitPresentation("impact", {
			index = projectilePlan.index,
			impactPosition = projectilePlan.impactPosition,
			scaleMultiplier = context.bossDefinition.scaleMultiplier,
		})
		applyExplosionDamage(bossModel, projectilePlan.impactPosition)

		impactTasksRemaining -= 1
		if impactTasksRemaining <= 0 then
			markComplete()
		end
	end

	local function handleBubbles()
		if cancelled or bubblesTriggered or bossModel.Parent == nil or bossRootPart.Parent == nil then
			return
		end

		bubblesTriggered = true
		local projectilePlans = buildProjectilePlans(context, bossModel, bossHumanoid, bossRootPart)
		if #projectilePlans <= 0 then
			markComplete()
			return
		end

		impactTasksRemaining = #projectilePlans
		context.EmitPresentation("projectiles", {
			projectiles = projectilePlans,
			projectileSpeed = PROJECTILE_SPEED_STUDS_PER_SECOND,
			scaleMultiplier = context.bossDefinition.scaleMultiplier,
		})

		for _, projectilePlan in ipairs(projectilePlans) do
			task.delay(math.max(0, projectilePlan.travelDuration), function()
				explodeProjectile(projectilePlan)
			end)
		end
	end

	track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, {
		[BUBBLES_MARKER_NAME] = handleBubbles,
	}, ANIMATION_FADE_SECONDS)
	if track == nil then
		warn("[BubbleBlast] Failed to play BubbleBlast animation.")
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

		if not bubblesTriggered then
			warnMissingBubbles()
			markComplete()
			return
		end

		if impactTasksRemaining <= 0 then
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

return table.freeze(BubbleBlast)
