local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)

local DAMAGE = 18
local AOE_RADIUS = 14
local HITBOX_DURATION_SECONDS = 0.12
local MAX_HITBOX_PARTS = 128
local FIRE_INTERVAL_SECONDS = 0.3
local MAX_MISSILES = 12
local PROJECTILE_TRAVEL_SECONDS = 1.1
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "Destroyer3000"
local ANIMATION_NAME = "MissileBarrage"
local START_SHOOT_MARKER_NAME = "StartShooting"
local STOP_SHOOT_MARKER_NAME = "StopShooting"
local LEFT_SHOULDER_ATTACHMENT_NAME = "LeftShoulderRigAttachment"
local RIGHT_SHOULDER_ATTACHMENT_NAME = "RightShoulderRigAttachment"
local TARGET_OFFSET_RADIUS = 16
local FLOOR_RAYCAST_START_HEIGHT = 30
local FLOOR_RAYCAST_DISTANCE = 450
local MIN_ARC_HEIGHT = 70
local MAX_ARC_HEIGHT = 190

local stub = CreateExplicitBossMoveStub({
	bossId = "Destroyer 3000",
	moveLabel = "Missile Barrage",
	targetMode = "all_players",
	summaryTemplate = "{moveLabel} rains missiles near {targets}",
	description = "Destroyer 3000 alternates shoulder missiles that arc upward before striking near players.",
})

local MissileBarrage = {
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

	local destroyerFolder = animations:FindFirstChild(ANIMATION_FOLDER_NAME)
	if not (destroyerFolder and destroyerFolder:IsA("Folder")) then
		return nil
	end

	local animationInstance = destroyerFolder:FindFirstChild(ANIMATION_NAME)
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

local function resolveAttachment(model: Model, attachmentName: string): Attachment?
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Attachment") and descendant.Name == attachmentName then
			return descendant
		end
	end

	return nil
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

local function collectAliveTargets(context): { any }
	local aliveTargets = {}

	for _, targetContext in ipairs(context.aliveTargets or {}) do
		local player = targetContext.player
		local character = player and (player.Character or targetContext.character)
		local humanoid = resolveHumanoid(character)
		local rootPart = resolveRootPart(character)
		if player ~= nil and character ~= nil and humanoid ~= nil and humanoid.Health > 0 and rootPart ~= nil then
			table.insert(aliveTargets, {
				player = player,
				character = character,
				humanoid = humanoid,
				rootPart = rootPart,
			})
		end
	end

	return aliveTargets
end

local function resolveImpactPosition(targetRootPart: BasePart, bossModel: Model, rng: Random): Vector3
	local angle = rng:NextNumber(0, math.pi * 2)
	local radius = rng:NextNumber(0, TARGET_OFFSET_RADIUS)
	local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	local targetPosition = targetRootPart.Position + offset
	return raycastGroundNear(targetPosition, bossModel) or targetPosition
end

local function resolveArcControlPosition(startPosition: Vector3, impactPosition: Vector3): Vector3
	local midpoint = startPosition:Lerp(impactPosition, 0.5)
	local distance = (impactPosition - startPosition).Magnitude
	local arcHeight = math.clamp(distance * 0.65, MIN_ARC_HEIGHT, MAX_ARC_HEIGHT)
	return midpoint + Vector3.new(0, arcHeight, 0)
end

local function applyImpactDamage(bossModel: Model, impactPosition: Vector3)
	local hitTargets = {}
	local hitbox
	hitbox = Hitbox.new({
		Character = bossModel,
		HitboxCFrame = CFrame.new(impactPosition),
		HitboxRadius = AOE_RADIUS,
		HitboxType = "SpacialQuery",
		Time = HITBOX_DURATION_SECONDS,
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
		end,
		HitboxDestroy = function()
			hitbox = nil
		end,
	})
end

local function resolveSelectionRangeScale(context): number
	local scaleMultiplier = tonumber(context.bossDefinition and context.bossDefinition.scaleMultiplier) or 1
	return math.clamp(math.sqrt(math.max(1, scaleMultiplier)), 1, 4)
end

function MissileBarrage.GetSelectionWeight(context)
	local distance = tonumber(context.distanceToTarget)
	if distance == nil then
		return 1
	end

	local rangeScale = resolveSelectionRangeScale(context)
	if distance <= 35 * rangeScale then
		return 0.35
	elseif distance <= 80 * rangeScale then
		return 0.85
	end

	return 1.15
end

function MissileBarrage.StartCast(context)
	local bossModel = context.bossModel
	local bossRootPart = context.bossRootPart
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return nil
	end

	local animationInstance = resolveAnimationInstance()
	if animationInstance == nil then
		warn("[MissileBarrage] Missing animation at ReplicatedStorage.GameAssets.Animations.Destroyer3000.MissileBarrage.")
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[MissileBarrage] Failed to create animation profile:", profileOrError)
		return nil
	end

	local profile = profileOrError
	local rng = Random.new()
	local track = nil :: AnimationTrack?
	local stoppedConnection = nil :: RBXScriptConnection?
	local completed = false
	local cancelled = false
	local cleanedUp = false
	local isShooting = false
	local shootingFinished = false
	local startMarkerTriggered = false
	local stopPresentationSent = false
	local missileCount = 0
	local pendingImpactCount = 0
	local recoveryEndsAt = nil :: number?
	local pendingImpactTokens = {}

	local leftShoulderAttachment = resolveAttachment(bossModel, LEFT_SHOULDER_ATTACHMENT_NAME)
	local rightShoulderAttachment = resolveAttachment(bossModel, RIGHT_SHOULDER_ATTACHMENT_NAME)
	if leftShoulderAttachment == nil then
		warn("[MissileBarrage] Missing LeftShoulderRigAttachment; falling back to HumanoidRootPart.")
	end
	if rightShoulderAttachment == nil then
		warn("[MissileBarrage] Missing RightShoulderRigAttachment; falling back to HumanoidRootPart.")
	end

	local function disconnectStoppedConnection()
		if stoppedConnection and stoppedConnection.Connected then
			stoppedConnection:Disconnect()
		end
		stoppedConnection = nil
	end

	local function stopPresentation()
		if stopPresentationSent then
			return
		end

		stopPresentationSent = true
		context.EmitPresentation("stop")
	end

	local function markComplete()
		if completed then
			return
		end

		completed = true
		isShooting = false
		recoveryEndsAt = os.clock() + (tonumber(context.move and context.move.recoverySeconds) or 0)
		stopPresentation()
	end

	local function finishShooting()
		if shootingFinished then
			return
		end

		isShooting = false
		shootingFinished = true
		if pendingImpactCount <= 0 then
			markComplete()
		end
	end

	local function cleanup(stopAnimation: boolean)
		if cleanedUp then
			return
		end

		cleanedUp = true
		isShooting = false
		for token in pairs(pendingImpactTokens) do
			pendingImpactTokens[token] = nil
		end
		stopPresentation()
		disconnectStoppedConnection()

		if stopAnimation and track then
			profile:StopAnimation(animationInstance, ANIMATION_FADE_SECONDS)
		end
	end

	local function resolveLaunchCFrame(useLeftShoulder: boolean): CFrame
		local attachment = if useLeftShoulder then leftShoulderAttachment else rightShoulderAttachment
		if attachment and attachment.Parent ~= nil then
			return attachment.WorldCFrame
		end
		if bossRootPart.Parent ~= nil then
			return bossRootPart.CFrame
		end
		return bossModel:GetPivot()
	end

	local function fireMissile()
		if cancelled or not isShooting or completed or bossModel.Parent == nil or bossRootPart.Parent == nil then
			return
		end
		if missileCount >= MAX_MISSILES then
			finishShooting()
			return
		end

		local aliveTargets = collectAliveTargets(context)
		if #aliveTargets <= 0 then
			finishShooting()
			return
		end

		missileCount += 1
		local target = aliveTargets[rng:NextInteger(1, #aliveTargets)]
		local useLeftShoulder = missileCount % 2 == 1
		local launchCFrame = resolveLaunchCFrame(useLeftShoulder)
		local startPosition = launchCFrame.Position
		local impactPosition = resolveImpactPosition(target.rootPart, bossModel, rng)
		local controlPosition = resolveArcControlPosition(startPosition, impactPosition)
		local missileIndex = missileCount
		local impactToken = {}
		pendingImpactTokens[impactToken] = true
		pendingImpactCount += 1

		context.EmitPresentation("launch", {
			index = missileIndex,
			shoulder = if useLeftShoulder then "Left" else "Right",
			startCFrame = launchCFrame,
			startPosition = startPosition,
			controlPosition = controlPosition,
			impactPosition = impactPosition,
			travelDuration = PROJECTILE_TRAVEL_SECONDS,
			scaleMultiplier = context.bossDefinition.scaleMultiplier,
			targetUserId = target.player.UserId,
		})

		task.delay(PROJECTILE_TRAVEL_SECONDS, function()
			if pendingImpactTokens[impactToken] ~= true then
				return
			end

			pendingImpactTokens[impactToken] = nil
			pendingImpactCount = math.max(0, pendingImpactCount - 1)

			if cancelled or bossModel.Parent == nil then
				if shootingFinished and pendingImpactCount <= 0 then
					markComplete()
				end
				return
			end

			applyImpactDamage(bossModel, impactPosition)
			context.EmitPresentation("impact", {
				index = missileIndex,
				impactPosition = impactPosition,
				scaleMultiplier = context.bossDefinition.scaleMultiplier,
				explosionRadius = AOE_RADIUS,
			})

			if shootingFinished and pendingImpactCount <= 0 then
				markComplete()
			end
		end)

		task.delay(FIRE_INTERVAL_SECONDS, function()
			if missileCount >= MAX_MISSILES then
				finishShooting()
				return
			end

			fireMissile()
		end)
	end

	local function startShooting()
		if cancelled or startMarkerTriggered or bossModel.Parent == nil then
			return
		end

		startMarkerTriggered = true
		isShooting = true
		context.EmitPresentation("start", {
			scaleMultiplier = context.bossDefinition.scaleMultiplier,
		})
		fireMissile()
	end

	local function stopShooting()
		if cancelled then
			return
		end

		finishShooting()
	end

	track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, {
		[START_SHOOT_MARKER_NAME] = startShooting,
		[STOP_SHOOT_MARKER_NAME] = stopShooting,
	}, ANIMATION_FADE_SECONDS)
	if track == nil then
		warn("[MissileBarrage] Failed to play MissileBarrage animation.")
		return nil
	end

	track.Looped = false
	stoppedConnection = track.Stopped:Connect(function()
		disconnectStoppedConnection()
		if cancelled then
			return
		end
		if not startMarkerTriggered then
			warn(string.format(
				"[MissileBarrage] Animation '%s' completed without firing the '%s' marker.",
				animationInstance.Name,
				START_SHOOT_MARKER_NAME
			))
		end
		finishShooting()
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

return table.freeze(MissileBarrage)
