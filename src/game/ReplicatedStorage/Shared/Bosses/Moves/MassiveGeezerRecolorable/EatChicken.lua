local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)

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
local TARGET_HEIGHT_OFFSET = 2

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

local function resolveHumanoid(model: Model?): Humanoid?
	if model == nil then
		return nil
	end

	return model:FindFirstChildOfClass("Humanoid")
end

local function resolveHandPart(bossModel: Model, handName: string): BasePart?
	local hand = bossModel:FindFirstChild(handName, true)
	if hand and hand:IsA("BasePart") then
		return hand
	end

	return nil
end

local function resolvePlanarDirection(vector: Vector3): Vector3?
	local planar = Vector3.new(vector.X, 0, vector.Z)
	if planar.Magnitude <= 0.001 then
		return nil
	end

	return planar.Unit
end

local function resolveForwardDirection(context, bossRootPart: BasePart): Vector3
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

local function resolveProjectileEndHeight(context, bossRootPart: BasePart): number
	local targetRootPart = context.targetRootPart
	if targetRootPart and targetRootPart.Parent ~= nil then
		return targetRootPart.Position.Y + TARGET_HEIGHT_OFFSET
	end

	return bossRootPart.Position.Y
end

local function buildProjectilePlans(context, bossModel: Model, bossRootPart: BasePart): { { [string]: any } }
	local forwardDirection = resolveForwardDirection(context, bossRootPart)
	local rightDirection = resolveRightDirection(forwardDirection)
	local endHeight = resolveProjectileEndHeight(context, bossRootPart)
	local origin = bossRootPart.Position
	local plans = {}

	for index = 1, PROJECTILE_COUNT do
		local laneOffset = (index - ((PROJECTILE_COUNT + 1) / 2)) * PROJECTILE_SPACING_STUDS
		local startPosition = resolveProjectileStartPosition(bossModel, index, bossRootPart)
		local endPlanarPosition = origin
			+ (forwardDirection * PROJECTILE_DISTANCE_STUDS)
			+ (rightDirection * laneOffset)
		local endPosition = Vector3.new(endPlanarPosition.X, endHeight, endPlanarPosition.Z)
		local travelDistance = (endPosition - startPosition).Magnitude

		table.insert(plans, {
			index = index,
			startPosition = startPosition,
			endPosition = endPosition,
			travelDuration = travelDistance / PROJECTILE_SPEED_STUDS_PER_SECOND,
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

	local travelDuration = math.max(0.001, tonumber(plan.travelDuration) or 0)
	local alpha = math.clamp((os.clock() - startedAt) / travelDuration, 0, 1)
	return startPosition:Lerp(endPosition, alpha)
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
		faceBossTowardDirection(bossRootPart, resolveForwardDirection(context, bossRootPart))
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
			hitbox = Hitbox.new({
				Character = bossModel,
				HitboxCFrame = function()
					if cancelled then
						return nil
					end

					return CFrame.new(getProjectilePosition(plan, projectileStartedAt))
				end,
				HitboxRadius = PROJECTILE_RADIUS,
				HitboxType = "SpacialQuery",
				Time = plan.travelDuration,
				MaxParts = PROJECTILE_MAX_PARTS,
			}, {
				HitTarget = function(targetModel: Model)
					local player = Players:GetPlayerFromCharacter(targetModel)
					if player == nil or hitPlayers[player] == true then
						return
					end

					local humanoid = resolveHumanoid(targetModel)
					if humanoid == nil or humanoid.Health <= 0 then
						return
					end

					hitPlayers[player] = true
					humanoid:TakeDamage(DAMAGE)
				end,
				HitboxDestroy = function()
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
