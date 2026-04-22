local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local Knockback = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Knockback)

local DAMAGE = 22
local BASE_EXPLOSION_RADIUS = 22
local EXPLOSION_SCALE_MULTIPLIER = 2
local EXPLOSION_VISUAL_SCALE_MULTIPLIER = 0.45
local EXPLOSION_RADIUS = BASE_EXPLOSION_RADIUS * EXPLOSION_SCALE_MULTIPLIER
local EXPLOSION_HITBOX_DURATION_SECONDS = 0.12
local PROJECTILE_SPEED_STUDS_PER_SECOND = 100
local PROJECTILE_RADIUS = 5
local BALL_START_SCALE = 0.075
local BALL_END_SCALE = 6.25
local BALL_RISE_HEIGHT_STUDS = 42
local THROW_MARKER_TIME_SECONDS = 2.5333333015441895
local FALLBACK_THROW_DISTANCE_STUDS = 120
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "MerfinTheGreat"
local ANIMATION_NAME = "WaterBomb"
local THROW_MARKER_NAME = "Throw"
local FLOOR_RAYCAST_START_HEIGHT = 20
local FLOOR_RAYCAST_DISTANCE = 350

local stub = CreateExplicitBossMoveStub({
	bossId = "Merfin the Great",
	moveLabel = "Water Bomb",
	targetMode = "single",
	summaryTemplate = "{moveLabel} hurls a crashing water sphere at {target}",
	description = "Merfin the Great conjures a giant ball of water above his head and throws it toward a player, exploding in a large radius on impact.",
})

local WaterBomb = {
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

local function resolveBossHeadPosition(bossModel: Model, bossHumanoid: Humanoid?, bossRootPart: BasePart): Vector3
	local head = bossModel:FindFirstChild("Head", true)
	if head and head:IsA("BasePart") then
		return head.Position + Vector3.new(0, head.Size.Y * 0.7, 0)
	end

	local standingHeight = resolveStandingHeight(bossHumanoid, bossRootPart)
	return bossRootPart.Position + Vector3.new(0, standingHeight * 0.45, 0)
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

local function raycastGroundNear(position: Vector3, bossModel: Model): Vector3?
	local raycastParams = buildFloorRaycastParams(bossModel)
	local rayOrigin = position + Vector3.new(0, FLOOR_RAYCAST_START_HEIGHT, 0)
	local rayDirection = Vector3.new(0, -(FLOOR_RAYCAST_START_HEIGHT + FLOOR_RAYCAST_DISTANCE), 0)
	local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	if raycastResult == nil then
		return nil
	end

	return raycastResult.Position
end

local function resolveNearestAliveTarget(bossRootPart: BasePart)
	local nearestTarget = nil

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = resolveHumanoid(character)
		local rootPart = resolveRootPart(character)
		if character == nil or humanoid == nil or humanoid.Health <= 0 or rootPart == nil then
			continue
		end

		local distance = (rootPart.Position - bossRootPart.Position).Magnitude
		if nearestTarget == nil or distance < nearestTarget.distance then
			nearestTarget = {
				player = player,
				character = character,
				humanoid = humanoid,
				rootPart = rootPart,
				distance = distance,
			}
		end
	end

	return nearestTarget
end

local function resolvePlanarForwardDirection(bossRootPart: BasePart): Vector3
	local direction = Vector3.new(bossRootPart.CFrame.LookVector.X, 0, bossRootPart.CFrame.LookVector.Z)
	if direction.Magnitude <= 0.001 then
		return Vector3.new(0, 0, -1)
	end

	return direction.Unit
end

local function resolveImpactPosition(bossModel: Model, bossRootPart: BasePart, targetData): Vector3
	if targetData and targetData.rootPart and targetData.rootPart.Parent ~= nil then
		return raycastGroundNear(targetData.rootPart.Position, bossModel) or targetData.rootPart.Position
	end

	local fallbackPosition = bossRootPart.Position + (resolvePlanarForwardDirection(bossRootPart) * FALLBACK_THROW_DISTANCE_STUDS)
	return raycastGroundNear(fallbackPosition, bossModel) or fallbackPosition
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

	return (direction * 48) + Vector3.new(0, 18, 0)
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
		MaxParts = 256,
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
				Duration = 0.2,
				RagdollDuration = 0.55,
				Stun = 0.35,
				IFrames = 0.2,
				AntiStun = 0.45,
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

function WaterBomb.GetSelectionWeight(context)
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

function WaterBomb.CanUse(context)
	local canUse, reason = stub.CanUse(context)
	if canUse ~= true then
		return false, reason
	end

	return true
end

function WaterBomb.StartCast(context)
	local bossModel = context.bossModel
	local bossHumanoid = context.bossHumanoid
	local bossRootPart = context.bossRootPart
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return nil
	end

	local animationInstance = resolveAnimationInstance()
	if animationInstance == nil then
		warn("[WaterBomb] Missing animation at ReplicatedStorage.GameAssets.Animations.MerfinTheGreat.WaterBomb.")
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[WaterBomb] Failed to create animation profile:", profileOrError)
		return nil
	end

	local profile = profileOrError
	local track = nil :: AnimationTrack?
	local stoppedConnection = nil :: RBXScriptConnection?
	local projectileConnection = nil :: RBXScriptConnection?
	local activeProjectileHitbox = nil
	local completed = false
	local cancelled = false
	local cleanedUp = false
	local throwTriggered = false
	local presentationStopped = false
	local recoveryEndsAt = nil :: number?
	local projectileStartPosition = nil :: Vector3?
	local projectileImpactPosition = nil :: Vector3?
	local projectileStartTime = 0
	local projectileTravelDuration = 0

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

		if stopAnimation and track then
			profile:StopAnimation(animationInstance, ANIMATION_FADE_SECONDS)
		end
	end

	local function getCurrentProjectilePosition(): Vector3?
		if projectileStartPosition == nil or projectileImpactPosition == nil then
			return nil
		end

		local alpha = math.clamp((os.clock() - projectileStartTime) / math.max(0.001, projectileTravelDuration), 0, 1)
		return projectileStartPosition:Lerp(projectileImpactPosition, alpha)
	end

	local function explodeAt(impactPosition: Vector3)
		if cancelled or completed then
			return
		end

		context.EmitPresentation("impact", {
			impactPosition = impactPosition,
			explosionRadius = EXPLOSION_RADIUS,
			scaleMultiplier = context.bossDefinition.scaleMultiplier * EXPLOSION_VISUAL_SCALE_MULTIPLIER,
		})
		applyExplosionDamage(bossModel, impactPosition)
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
		local targetData = resolveNearestAliveTarget(bossRootPart)
		local impactPosition = resolveImpactPosition(bossModel, bossRootPart, targetData)
		local startPosition = resolveBossHeadPosition(bossModel, bossHumanoid, bossRootPart)
			+ Vector3.new(0, BALL_RISE_HEIGHT_STUDS, 0)
		local travelDistance = (impactPosition - startPosition).Magnitude
		projectileTravelDuration = travelDistance / PROJECTILE_SPEED_STUDS_PER_SECOND
		projectileStartPosition = startPosition
		projectileImpactPosition = impactPosition
		projectileStartTime = os.clock()

		context.EmitPresentation("throw", {
			startPosition = startPosition,
			impactPosition = impactPosition,
			travelDuration = projectileTravelDuration,
			projectileSpeed = PROJECTILE_SPEED_STUDS_PER_SECOND,
			ballScale = BALL_END_SCALE,
			targetUserId = if targetData then targetData.player.UserId else nil,
		})

		if projectileTravelDuration <= 0 then
			explodeAt(impactPosition)
			return
		end

		activeProjectileHitbox = Hitbox.new({
			Character = bossModel,
			HitboxCFrame = function()
				local currentPosition = getCurrentProjectilePosition()
				if currentPosition == nil then
					return nil
				end
				return CFrame.new(currentPosition)
			end,
			HitboxRadius = PROJECTILE_RADIUS,
			HitboxType = "SpacialQuery",
			Time = projectileTravelDuration,
			MaxParts = 64,
		}, {
			HitTarget = function() end,
			HitboxDestroy = function()
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
			if os.clock() - projectileStartTime >= projectileTravelDuration then
				explodeAt(impactPosition)
			end
		end)
	end

	track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, {
		[THROW_MARKER_NAME] = throwProjectile,
	}, ANIMATION_FADE_SECONDS)
	if track == nil then
		warn("[WaterBomb] Failed to play WaterBomb animation.")
		return nil
	end

	local headPosition = resolveBossHeadPosition(bossModel, bossHumanoid, bossRootPart)
	local standingHeight = resolveStandingHeight(bossHumanoid, bossRootPart)
	context.EmitPresentation("start", {
		floorPosition = bossRootPart.Position - Vector3.new(0, standingHeight, 0),
		chargeStartPosition = headPosition,
		chargeEndPosition = headPosition + Vector3.new(0, BALL_RISE_HEIGHT_STUDS, 0),
		chargeDurationSeconds = THROW_MARKER_TIME_SECONDS,
		ballStartScale = BALL_START_SCALE,
		ballEndScale = BALL_END_SCALE,
		scaleMultiplier = context.bossDefinition.scaleMultiplier,
	})

	track.Looped = false
	stoppedConnection = track.Stopped:Connect(function()
		disconnectStoppedConnection()
		if cancelled then
			return
		end
		if not throwTriggered then
			warn(string.format("[WaterBomb] Animation '%s' completed without firing the '%s' marker.", animationInstance.Name, THROW_MARKER_NAME))
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

return table.freeze(WaterBomb)
