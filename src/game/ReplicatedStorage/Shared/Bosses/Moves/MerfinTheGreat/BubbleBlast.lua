local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
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

local function resolveStandingHeight(bossHumanoid: Humanoid?, bossRootPart: BasePart): number
	if bossHumanoid == nil then
		return bossRootPart.Size.Y
	end

	return math.max((bossRootPart.Size.Y * 0.5) + bossHumanoid.HipHeight, bossRootPart.Size.Y)
end

local function resolveProjectileStartPosition(bossModel: Model, bossHumanoid: Humanoid?, bossRootPart: BasePart): Vector3
	local head = bossModel:FindFirstChild("Head", true)
	if head and head:IsA("BasePart") then
		return head.Position + Vector3.new(0, head.Size.Y * 0.65, 0)
	end

	return bossRootPart.Position + Vector3.new(0, resolveStandingHeight(bossHumanoid, bossRootPart) * START_HEIGHT_SCALE, 0)
end

local function buildFloorRaycastParams(bossModel: Model): RaycastParams
	local includeInstances = {}
	local activeBossArena = Workspace:FindFirstChild("ActiveBossArena")
	if activeBossArena then
		table.insert(includeInstances, activeBossArena)
	end

	local map = Workspace:FindFirstChild("Map")
	if map then
		table.insert(includeInstances, map)
	end

	local world = Workspace:FindFirstChild("World")
	local worldMap = world and world:FindFirstChild("Map")
	if worldMap then
		table.insert(includeInstances, worldMap)
	end

	if Workspace.Terrain then
		table.insert(includeInstances, Workspace.Terrain)
	end

	local raycastParams = RaycastParams.new()
	if #includeInstances > 0 then
		raycastParams.FilterType = Enum.RaycastFilterType.Include
		raycastParams.FilterDescendantsInstances = includeInstances
	else
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = { bossModel }
	end
	return raycastParams
end

local function raycastGroundNear(position: Vector3, bossModel: Model): Vector3
	local raycastParams = buildFloorRaycastParams(bossModel)
	local rayOrigin = position + Vector3.new(0, FLOOR_RAYCAST_START_HEIGHT, 0)
	local rayDirection = Vector3.new(0, -(FLOOR_RAYCAST_START_HEIGHT + FLOOR_RAYCAST_DISTANCE), 0)
	local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	if raycastResult then
		return raycastResult.Position
	end

	return position
end

local function resolvePlanarBasis(bossRootPart: BasePart, targetPosition: Vector3?): (Vector3, Vector3)
	local forward = Vector3.new(bossRootPart.CFrame.LookVector.X, 0, bossRootPart.CFrame.LookVector.Z)
	if typeof(targetPosition) == "Vector3" then
		local offset = targetPosition - bossRootPart.Position
		local planarOffset = Vector3.new(offset.X, 0, offset.Z)
		if planarOffset.Magnitude > 0.001 then
			forward = planarOffset
		end
	end

	if forward.Magnitude <= 0.001 then
		forward = Vector3.new(0, 0, -1)
	else
		forward = forward.Unit
	end

	local right = forward:Cross(Vector3.yAxis)
	if right.Magnitude <= 0.001 then
		right = Vector3.xAxis
	else
		right = right.Unit
	end

	return right, forward
end

local function buildKnockbackDirection(impactPosition: Vector3, targetRootPart: BasePart?): Vector3
	local direction = Vector3.new(0, 0, -1)
	if targetRootPart and targetRootPart.Parent ~= nil then
		local offset = targetRootPart.Position - impactPosition
		local planarOffset = Vector3.new(offset.X, 0, offset.Z)
		if planarOffset.Magnitude > 0.001 then
			direction = planarOffset.Unit
		end
	end

	return (direction * 32) + Vector3.new(0, 12, 0)
end

local function applyExplosionDamage(bossModel: Model, impactPosition: Vector3)
	local hitTargets = {}
	local explosionHitbox
	explosionHitbox = Hitbox.new({
		Character = bossModel,
		HitboxCFrame = CFrame.new(impactPosition),
		HitboxRadius = EXPLOSION_RADIUS,
		HitboxType = "SpacialQuery",
		Time = EXPLOSION_HITBOX_DURATION_SECONDS,
		MaxParts = 128,
	}, {
		HitTarget = function(targetModel: Model)
			if hitTargets[targetModel] == true then
				return
			end

			local player = Players:GetPlayerFromCharacter(targetModel)
			if player == nil then
				return
			end

			local humanoid = resolveHumanoid(targetModel)
			if humanoid == nil or humanoid.Health <= 0 then
				return
			end

			hitTargets[targetModel] = true
			humanoid:TakeDamage(DAMAGE)

			Knockback(targetModel, "Default", {
				Direction = buildKnockbackDirection(impactPosition, resolveRootPart(targetModel)),
				Duration = 0.18,
				RagdollDuration = 0.35,
				Stun = 0.25,
				IFrames = 0.15,
				AntiStun = 0.3,
				GroundMode = "DeterministicMap",
			})
		end,
		HitboxDestroy = function()
			if explosionHitbox then
				explosionHitbox = nil
			end
		end,
	})
end

local function collectAliveTargets(context)
	local targets = {}
	for _, targetContext in ipairs(context.aliveTargets or {}) do
		if targetContext.player
			and targetContext.humanoid
			and targetContext.humanoid.Health > 0
			and targetContext.rootPart
			and targetContext.rootPart.Parent ~= nil then
			table.insert(targets, targetContext)
		end
	end

	return targets
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
