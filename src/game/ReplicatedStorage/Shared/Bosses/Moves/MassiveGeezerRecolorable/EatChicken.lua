local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local CombatMoveUtil = require(ReplicatedStorage.Shared.Combat.CombatMoveUtil)
local CombatProjectileUtil = require(ReplicatedStorage.Shared.Combat.CombatProjectileUtil)

local DAMAGE = 15
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "MassiveGeezer"
local ANIMATION_NAME = "EatChicken"
local PROJECTILE_COUNT = 16
local PROJECTILE_SPEED_STUDS_PER_SECOND = 170
local PROJECTILE_DISTANCE_STUDS = 185
local PROJECTILE_SPACING_STUDS = 9
local PROJECTILE_RADIUS = 6
local PROJECTILE_MAX_PARTS = 64

local CHICKEN_SPAWN_MARKER_NAME = "ChickenSpawn"
local ATE_CHICKEN_MARKER_NAME = "AteChicken"
local TURN_TO_PLAYER_MARKER_NAME = "TurnToPlayer"
local CHICKEN_THROW_MARKER_NAME = "ChickenThrow"

local stub = CreateExplicitBossMoveStub({
	bossId = "Massive Geezer RECOLORABLE",
	moveLabel = "Eat Chicken",
	targetMode = "all_players",
	summaryTemplate = "{moveLabel} throws chicken bones through the arena",
	description = "Massive Geezer RECOLORABLE eats chicken and throws a spread of bones across the arena.",
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

local function resolveRightDirection(forwardDirection: Vector3): Vector3
	return Vector3.new(forwardDirection.Z, 0, -forwardDirection.X).Unit
end

local function faceBossTowardDirection(bossRootPart: BasePart, forwardDirection: Vector3)
	local position = bossRootPart.Position
	bossRootPart.CFrame = CFrame.lookAt(position, position + forwardDirection)
end

local function resolveProjectileStartPosition(bossModel: Model, index: number, bossRootPart: BasePart): Vector3
	local handName = if index <= PROJECTILE_COUNT / 2 then "LeftHand" else "RightHand"
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

local function buildProjectilePlans(context, bossModel: Model, bossRootPart: BasePart): { { [string]: any } }
	local aimTargetRootPart = resolveAimTargetRootPart(context, bossRootPart)
	local forwardDirection = resolveForwardDirection(context, bossRootPart, aimTargetRootPart)
	local rightDirection = resolveRightDirection(forwardDirection)
	local endHeight = resolveProjectileEndHeight(bossRootPart, aimTargetRootPart)
	local origin = bossRootPart.Position
	local plans = {}

	for index = 1, PROJECTILE_COUNT do
		local laneOffset = (index - ((PROJECTILE_COUNT + 1) / 2)) * PROJECTILE_SPACING_STUDS
		local startPosition = resolveProjectileStartPosition(bossModel, index, bossRootPart)
		local endPlanarPosition = origin
			+ (forwardDirection * PROJECTILE_DISTANCE_STUDS)
			+ (rightDirection * laneOffset)
		local endPosition = Vector3.new(endPlanarPosition.X, endHeight, endPlanarPosition.Z)
		table.insert(plans, {
			index = index,
			startPosition = startPosition,
			endPosition = endPosition,
			travelDuration = CombatProjectileUtil.ResolveTravelDuration(
				startPosition,
				endPosition,
				PROJECTILE_SPEED_STUDS_PER_SECOND
			),
		})
	end

	return plans
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
	local hitPlayers = {}
	local markersHit = {}
	local projectilePlans = {}
	local projectileStartedAt = 0
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
		projectilePlans = buildProjectilePlans(context, bossModel, bossRootPart)
		projectileStartedAt = os.clock()

		context.EmitPresentation("throwBones", {
			projectiles = projectilePlans,
			projectileSpeed = PROJECTILE_SPEED_STUDS_PER_SECOND,
			scaleMultiplier = context.bossDefinition.scaleMultiplier,
		})

		local longestTravelDuration = 0
		for _, plan in ipairs(projectilePlans) do
			longestTravelDuration = math.max(longestTravelDuration, tonumber(plan.travelDuration) or 0)

			local hitbox
			hitbox = CombatProjectileUtil.CreateTrackingHitbox({
				debugVisibilityAttribute = "BossHitboxesVisible",
				hitboxOwner = bossModel,
				getPosition = function()
					if cancelled then
						return nil
					end

					return getProjectilePosition(plan, projectileStartedAt)
				end,
				radius = PROJECTILE_RADIUS,
				duration = plan.travelDuration,
				maxParts = PROJECTILE_MAX_PARTS,
				onHit = function(targetModel: Model)
					local targetInfo = CombatMoveUtil.ResolveDamageTarget(targetModel)
					if targetInfo == nil then
						return
					end

					local player = targetInfo.player
					if player == nil or hitPlayers[player] == true then
						return
					end

					hitPlayers[player] = true
					targetInfo.humanoid:TakeDamage(DAMAGE)
				end,
				onDestroy = function()
					for activeIndex, activeHitbox in ipairs(activeHitboxes) do
						if activeHitbox == hitbox then
							table.remove(activeHitboxes, activeIndex)
							break
						end
					end
				end,
			})
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
