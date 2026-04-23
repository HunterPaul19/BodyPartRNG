local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local Knockback = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Knockback)

local DAMAGE = 35
local IMPACT_RADIUS = 55
local IMPACT_HITBOX_HEIGHT = 36
local IMPACT_HITBOX_DURATION_SECONDS = 0.16
local MAX_HITBOX_PARTS = 256
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "MassiveGeezer"
local JUMP_ANIMATION_NAME = "Jump"
local JUMP_MARKER_NAME = "Jump"
local FALLING_ANIMATION_NAME = "Falling"
local LAND_ANIMATION_NAME = "Land"
local MIN_JUMP_DURATION_SECONDS = 0.45
local FALLING_ANIMATION_SPEED = 1
local ASCENT_HEIGHT = 170
local MIN_FALL_START_HEIGHT = 120
local INITIAL_FALL_SPEED = 125
local FALL_ACCELERATION = 420
local MAX_FALL_SPEED = 360
local FLOOR_RAYCAST_START_HEIGHT = 40
local FLOOR_RAYCAST_DISTANCE = 700
local KNOCKBACK_SPEED = 78
local KNOCKBACK_UPWARD_SPEED = 34
local RAGDOLL_DURATION_SECONDS = 0.8
local STUN_SECONDS = 0.45
local LANDED_RECOVERY_FALLBACK_SECONDS = 0.75

local stub = CreateExplicitBossMoveStub({
	bossId = "Massive Geezer RECOLORABLE",
	moveLabel = "Body Slam",
	targetMode = "single",
	summaryTemplate = "{moveLabel} crashes down onto {target}",
	description = "Massive Geezer RECOLORABLE jumps into the sky and slams his body onto a player.",
})

local BodySlam = {
	CanUse = stub.CanUse,
	GetTargeting = stub.GetTargeting,
	ExecuteStub = stub.ExecuteStub,
}

local function resolveAnimationInstance(animationName: string): Animation?
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

	local animationInstance = bossFolder:FindFirstChild(animationName)
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

local function resolveStandingHeight(humanoid: Humanoid, rootPart: BasePart): number
	return math.max((rootPart.Size.Y * 0.5) + humanoid.HipHeight, rootPart.Size.Y)
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
	raycastParams.IgnoreWater = false

	return raycastParams
end

local function raycastGroundAt(position: Vector3, bossModel: Model): RaycastResult?
	local rayOrigin = position + Vector3.new(0, FLOOR_RAYCAST_START_HEIGHT, 0)
	local rayDirection = Vector3.new(0, -(FLOOR_RAYCAST_START_HEIGHT + FLOOR_RAYCAST_DISTANCE), 0)
	return Workspace:Raycast(rayOrigin, rayDirection, buildFloorRaycastParams(bossModel))
end

local function resolveGroundPosition(position: Vector3, bossModel: Model): Vector3
	local result = raycastGroundAt(position, bossModel)
	if result then
		return result.Position
	end

	return position
end

local function resolveNearestAliveTarget(context, referencePosition: Vector3)
	local nearestTarget = nil

	for _, targetContext in ipairs(context.aliveTargets or {}) do
		local player = targetContext.player
		local character = player and (player.Character or targetContext.character)
		local humanoid = resolveHumanoid(character)
		local rootPart = resolveRootPart(character)
		if player ~= nil and character ~= nil and humanoid ~= nil and humanoid.Health > 0 and rootPart ~= nil then
			local distance = (rootPart.Position - referencePosition).Magnitude
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
	end

	return nearestTarget
end

local function resolveCurrentTargetRootPart(context, fallbackPosition: Vector3): BasePart?
	local targetRootPart = context.targetRootPart
	local targetHumanoid = context.targetHumanoid
	if targetRootPart and targetRootPart.Parent ~= nil and targetHumanoid and targetHumanoid.Health > 0 then
		return targetRootPart
	end

	local nearestTarget = resolveNearestAliveTarget(context, fallbackPosition)
	return if nearestTarget then nearestTarget.rootPart else nil
end

local function resolvePlanarDirection(fromPosition: Vector3, toPosition: Vector3, fallbackCFrame: CFrame): Vector3
	local offset = toPosition - fromPosition
	local planarOffset = Vector3.new(offset.X, 0, offset.Z)
	if planarOffset.Magnitude > 0.001 then
		return planarOffset.Unit
	end

	local fallback = Vector3.new(fallbackCFrame.LookVector.X, 0, fallbackCFrame.LookVector.Z)
	if fallback.Magnitude > 0.001 then
		return fallback.Unit
	end

	return Vector3.new(0, 0, -1)
end

local function pivotBossToRootPosition(bossModel: Model, bossRootPart: BasePart, rootPosition: Vector3, direction: Vector3)
	local lookAtPosition = rootPosition + direction
	local rootOffsetFromPivot = bossModel:GetPivot():ToObjectSpace(bossRootPart.CFrame)
	local targetRootCFrame = CFrame.lookAt(rootPosition, lookAtPosition)
	bossModel:PivotTo(targetRootCFrame * rootOffsetFromPivot:Inverse())
	bossRootPart.AssemblyLinearVelocity = Vector3.zero
	bossRootPart.AssemblyAngularVelocity = Vector3.zero
end

local function resolveJumpDuration(track: AnimationTrack?, context): number
	if track and track.Length > 0 then
		return math.max(MIN_JUMP_DURATION_SECONDS, track.Length)
	end

	return math.max(MIN_JUMP_DURATION_SECONDS, tonumber(context.move and context.move.castTimeSeconds) or 0)
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

	return (direction * KNOCKBACK_SPEED) + Vector3.new(0, KNOCKBACK_UPWARD_SPEED, 0)
end

local function forceHumanoidRecovery(humanoid: Humanoid)
	if humanoid.Health <= 0 then
		return
	end

	humanoid.Sit = false
	humanoid.PlatformStand = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

	task.defer(function()
		if humanoid.Parent ~= nil and humanoid.Health > 0 then
			humanoid.PlatformStand = false
			humanoid.Sit = false
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
		end
	end)
end

local function spawnImpactHitbox(context, impactPosition: Vector3)
	local bossModel = context.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		return
	end

	local hitTargets = {}
	local hitbox
	hitbox = Hitbox.new({
		Character = bossModel,
		HitboxCFrame = CFrame.new(impactPosition + Vector3.new(0, IMPACT_HITBOX_HEIGHT * 0.5, 0)),
		HitboxSize = Vector3.new(IMPACT_RADIUS * 2, IMPACT_HITBOX_HEIGHT, IMPACT_RADIUS * 2),
		HitboxType = "SpacialQuery",
		Time = IMPACT_HITBOX_DURATION_SECONDS,
		MaxParts = MAX_HITBOX_PARTS,
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
				Duration = 0.25,
				RagdollDuration = RAGDOLL_DURATION_SECONDS,
				Stun = STUN_SECONDS,
				IFrames = 0.2,
				AntiStun = STUN_SECONDS,
				GroundMode = "DeterministicMap",
			})
		end,
		HitboxDestroy = function()
			hitbox = nil
		end,
	})

	hitbox:Visible(true)
end

function BodySlam.GetSelectionWeight(context)
	local distance = tonumber(context.distanceToTarget)
	if distance == nil then
		return 1
	end

	if distance <= 28 then
		return 1.45
	elseif distance <= 55 then
		return 1
	elseif distance <= 90 then
		return 0.45
	end

	return 0.15
end

function BodySlam.StartCast(context)
	local bossModel = context.bossModel
	local bossHumanoid = context.bossHumanoid
	local bossRootPart = context.bossRootPart
	if bossModel == nil or bossModel.Parent == nil or bossHumanoid == nil or bossHumanoid.Parent == nil then
		return nil
	end
	if bossRootPart == nil or bossRootPart.Parent == nil then
		return nil
	end

	local jumpAnimation = resolveAnimationInstance(JUMP_ANIMATION_NAME)
	local fallingAnimation = resolveAnimationInstance(FALLING_ANIMATION_NAME)
	local landAnimation = resolveAnimationInstance(LAND_ANIMATION_NAME)
	if jumpAnimation == nil or fallingAnimation == nil or landAnimation == nil then
		warn("[BodySlam] Missing Jump/Falling/Land animations in ReplicatedStorage.GameAssets.Animations.MassiveGeezer.")
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[BodySlam] Failed to create animation profile:", profileOrError)
		return nil
	end

	local profile = profileOrError
	local completed = false
	local cancelled = false
	local cleanedUp = false
	local didImpact = false
	local jumpVfxTriggered = false
	local presentationStopped = false
	local phase = "Jump"
	local heartbeatConnection = nil :: RBXScriptConnection?
	local jumpStoppedConnection = nil :: RBXScriptConnection?
	local landStoppedConnection = nil :: RBXScriptConnection?
	local jumpTrack = nil :: AnimationTrack?
	local fallingTrack = nil :: AnimationTrack?
	local landTrack = nil :: AnimationTrack?
	local recoveryEndsAt = nil :: number?
	local jumpStartedAt = os.clock()
	local jumpDuration = MIN_JUMP_DURATION_SECONDS
	local fallSpeed = INITIAL_FALL_SPEED
	local standingHeight = resolveStandingHeight(bossHumanoid, bossRootPart)
	local originalAnchored = bossRootPart.Anchored
	local originalWalkSpeed = bossHumanoid.WalkSpeed
	local originalAutoRotate = bossHumanoid.AutoRotate
	local originalPlatformStand = bossHumanoid.PlatformStand
	local originalSit = bossHumanoid.Sit
	local startRootCFrame = bossRootPart.CFrame
	local startRootPosition = startRootCFrame.Position
	local startGroundPosition = resolveGroundPosition(startRootPosition, bossModel)
	local landingPosition = startGroundPosition
	local facingDirection = resolvePlanarDirection(startRootPosition, startRootPosition + startRootCFrame.LookVector, startRootCFrame)
	local apexRootY = startRootPosition.Y + ASCENT_HEIGHT

	local function disconnect(connection: RBXScriptConnection?)
		if connection and connection.Connected then
			connection:Disconnect()
		end
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

	local function restoreBossState()
		if bossRootPart.Parent ~= nil then
			bossRootPart.Anchored = originalAnchored
			bossRootPart.AssemblyLinearVelocity = Vector3.zero
			bossRootPart.AssemblyAngularVelocity = Vector3.zero
		end

		if bossHumanoid.Parent ~= nil then
			bossHumanoid.WalkSpeed = originalWalkSpeed
			bossHumanoid.AutoRotate = originalAutoRotate
			bossHumanoid.PlatformStand = originalPlatformStand
			bossHumanoid.Sit = originalSit
			forceHumanoidRecovery(bossHumanoid)
		end
	end

	local function cleanup(stopAnimations: boolean)
		if cleanedUp then
			return
		end

		cleanedUp = true
		disconnect(heartbeatConnection)
		disconnect(jumpStoppedConnection)
		disconnect(landStoppedConnection)
		heartbeatConnection = nil
		jumpStoppedConnection = nil
		landStoppedConnection = nil
		stopPresentation()
		restoreBossState()

		if stopAnimations then
			profile:StopAnimation(jumpAnimation, ANIMATION_FADE_SECONDS)
			profile:StopAnimation(fallingAnimation, ANIMATION_FADE_SECONDS)
			profile:StopAnimation(landAnimation, ANIMATION_FADE_SECONDS)
		end
	end

	local function finishAfterLand()
		if cancelled then
			return
		end

		profile:StopAnimation(fallingAnimation, ANIMATION_FADE_SECONDS)
		restoreBossState()
		stopPresentation()
		markComplete()
	end

	local function performImpact(impactGroundPosition: Vector3)
		if cancelled or didImpact or bossModel.Parent == nil or bossRootPart.Parent == nil then
			return
		end

		didImpact = true
		phase = "Land"
		disconnect(heartbeatConnection)
		heartbeatConnection = nil
		profile:StopAnimation(fallingAnimation, ANIMATION_FADE_SECONDS)

		local impactRootPosition = impactGroundPosition + Vector3.new(0, standingHeight, 0)
		pivotBossToRootPosition(bossModel, bossRootPart, impactRootPosition, facingDirection)
		context.EmitPresentation("impact", {
			impactCFrame = CFrame.new(impactGroundPosition),
			impactPosition = impactGroundPosition,
			radius = IMPACT_RADIUS,
			scaleMultiplier = context.bossDefinition.scaleMultiplier,
		})
		spawnImpactHitbox(context, impactGroundPosition)

		landTrack = profile:PlayAnimation(landAnimation, Enum.AnimationPriority.Action, 1, nil, ANIMATION_FADE_SECONDS)
		if landTrack == nil then
			task.delay(LANDED_RECOVERY_FALLBACK_SECONDS, finishAfterLand)
			return
		end

		landTrack.Looped = false
		disconnect(landStoppedConnection)
		landStoppedConnection = landTrack.Stopped:Connect(function()
			disconnect(landStoppedConnection)
			landStoppedConnection = nil
			finishAfterLand()
		end)

		task.delay(math.max(LANDED_RECOVERY_FALLBACK_SECONDS, landTrack.Length + 0.1), function()
			if not cancelled and not completed and phase == "Land" then
				finishAfterLand()
			end
		end)
	end

	local function beginFall()
		if cancelled or completed or phase ~= "Jump" or bossModel.Parent == nil or bossRootPart.Parent == nil then
			return
		end

		phase = "Fall"
		disconnect(heartbeatConnection)
		heartbeatConnection = nil
		profile:StopAnimation(jumpAnimation, ANIMATION_FADE_SECONDS)
		fallingTrack = profile:PlayAnimation(fallingAnimation, Enum.AnimationPriority.Action, FALLING_ANIMATION_SPEED, nil, ANIMATION_FADE_SECONDS)
		if fallingTrack then
			fallingTrack.Looped = true
		end

		local currentRootPosition = bossRootPart.Position
		local fallStartY = math.max(currentRootPosition.Y, landingPosition.Y + standingHeight + MIN_FALL_START_HEIGHT)
		pivotBossToRootPosition(
			bossModel,
			bossRootPart,
			Vector3.new(landingPosition.X, fallStartY, landingPosition.Z),
			facingDirection
		)

		local lastUpdateAt = os.clock()
		heartbeatConnection = RunService.Heartbeat:Connect(function()
			if cancelled or bossModel.Parent == nil or bossRootPart.Parent == nil then
				return
			end

			local now = os.clock()
			local deltaTime = math.clamp(now - lastUpdateAt, 0, 0.05)
			lastUpdateAt = now
			fallSpeed = math.min(MAX_FALL_SPEED, fallSpeed + (FALL_ACCELERATION * deltaTime))

			local rootPosition = bossRootPart.Position
			local groundPosition = resolveGroundPosition(Vector3.new(landingPosition.X, rootPosition.Y, landingPosition.Z), bossModel)
			landingPosition = Vector3.new(landingPosition.X, groundPosition.Y, landingPosition.Z)
			local nextY = rootPosition.Y - (fallSpeed * deltaTime)
			local landedRootY = landingPosition.Y + standingHeight
			if nextY <= landedRootY then
				performImpact(landingPosition)
				return
			end

			pivotBossToRootPosition(
				bossModel,
				bossRootPart,
				Vector3.new(landingPosition.X, nextY, landingPosition.Z),
				facingDirection
			)
		end)
	end

	local function updateJumpMotion()
		if cancelled or completed or phase ~= "Jump" or bossModel.Parent == nil or bossRootPart.Parent == nil then
			return
		end

		local now = os.clock()
		local alpha = math.clamp((now - jumpStartedAt) / jumpDuration, 0, 1)
		local targetRootPart = resolveCurrentTargetRootPart(context, bossRootPart.Position)
		local desiredLanding = if targetRootPart
			then resolveGroundPosition(targetRootPart.Position, bossModel)
			else landingPosition

		landingPosition = desiredLanding
		facingDirection = resolvePlanarDirection(bossRootPart.Position, desiredLanding, bossRootPart.CFrame)

		local easedAlpha = 1 - ((1 - alpha) * (1 - alpha))
		local rootX = startRootPosition.X + ((desiredLanding.X - startRootPosition.X) * easedAlpha)
		local rootZ = startRootPosition.Z + ((desiredLanding.Z - startRootPosition.Z) * easedAlpha)
		local rootY = startRootPosition.Y + ((apexRootY - startRootPosition.Y) * easedAlpha)
		pivotBossToRootPosition(bossModel, bossRootPart, Vector3.new(rootX, rootY, rootZ), facingDirection)

		if alpha >= 1 then
			beginFall()
		end
	end

	local function handleJumpVfx()
		if cancelled or jumpVfxTriggered then
			return
		end

		jumpVfxTriggered = true
		context.EmitPresentation("jump", {
			floorCFrame = CFrame.new(startGroundPosition),
			scaleMultiplier = context.bossDefinition.scaleMultiplier,
		})
	end

	bossHumanoid.WalkSpeed = 0
	bossHumanoid.AutoRotate = false
	bossHumanoid.PlatformStand = false
	bossRootPart.Anchored = true
	bossRootPart.AssemblyLinearVelocity = Vector3.zero
	bossRootPart.AssemblyAngularVelocity = Vector3.zero

	jumpTrack = profile:PlayAnimation(jumpAnimation, Enum.AnimationPriority.Action, 1, {
		[JUMP_MARKER_NAME] = handleJumpVfx,
	}, ANIMATION_FADE_SECONDS)
	if jumpTrack == nil then
		cleanup(false)
		return nil
	end

	jumpTrack.Looped = false
	jumpDuration = resolveJumpDuration(jumpTrack, context)
	jumpStartedAt = os.clock()
	context.EmitPresentation("start", {
		floorCFrame = CFrame.new(startGroundPosition),
		scaleMultiplier = context.bossDefinition.scaleMultiplier,
	})

	jumpStoppedConnection = jumpTrack.Stopped:Connect(function()
		disconnect(jumpStoppedConnection)
		jumpStoppedConnection = nil
		beginFall()
	end)
	heartbeatConnection = RunService.Heartbeat:Connect(updateJumpMotion)

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

return table.freeze(BodySlam)
