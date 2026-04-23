local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local CombatMoveUtil = require(ReplicatedStorage.Shared.Combat.CombatMoveUtil)
local CombatProjectileUtil = require(ReplicatedStorage.Shared.Combat.CombatProjectileUtil)

local DAMAGE = 150
local AOE_RADIUS = 14
local HITBOX_DURATION_SECONDS = 0.12
local MAX_HITBOX_PARTS = 128
local FIRE_INTERVAL_SECONDS = 0.3
local MAX_MISSILES = 18
local BASE_PROJECTILE_TRAVEL_SECONDS = 94 / 60
local POST_FINAL_IMPACT_PRESENTATION_HOLD_SECONDS = 0.35
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
	return CombatMoveUtil.ResolveHumanoid(model)
end

local function resolveRootPart(model: Model?): BasePart?
	return CombatMoveUtil.ResolveRootPart(model)
end

local function resolveAttachment(model: Model, attachmentName: string): Attachment?
	return CombatMoveUtil.ResolveNamedAttachment(model, attachmentName)
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

local function collectAliveTargets(context): { any }
	return CombatMoveUtil.CollectAliveTargets(context.aliveTargets or {})
end

local function resolveImpactPosition(targetRootPart: BasePart, targetCharacter: Model?, bossModel: Model, rng: Random): Vector3
	local angle = rng:NextNumber(0, math.pi * 2)
	local radius = rng:NextNumber(0, TARGET_OFFSET_RADIUS)
	local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	local targetPosition = targetRootPart.Position + offset
	return raycastGroundNear(targetPosition, bossModel, targetCharacter) or targetPosition
end

local function resolveArcControlPosition(startPosition: Vector3, impactPosition: Vector3): Vector3
	return CombatProjectileUtil.ResolveArcControlPosition(startPosition, impactPosition, MIN_ARC_HEIGHT, MAX_ARC_HEIGHT)
end

local function applyImpactDamage(context, bossModel: Model, impactPosition: Vector3)
	CombatProjectileUtil.CreateRadiusDamageHitbox({
		debugVisibilityAttribute = "BossHitboxesVisible",
		hitboxOwner = bossModel,
		impactPosition = impactPosition,
		radius = AOE_RADIUS,
		duration = HITBOX_DURATION_SECONDS,
		maxParts = MAX_HITBOX_PARTS,
		damage = CombatMoveUtil.ResolveScaledBossDamage(context, DAMAGE),
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
	local completionHoldToken = nil :: any
	local projectileTravelSeconds =
		BASE_PROJECTILE_TRAVEL_SECONDS / CombatProjectileUtil.ResolveBasicProjectileSpeedScalar()

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

		completionHoldToken = nil
		completed = true
		isShooting = false
		recoveryEndsAt = os.clock() + (tonumber(context.move and context.move.recoverySeconds) or 0)
		stopPresentation()
	end

	local function markCompleteAfterFinalImpactHold()
		if completed or completionHoldToken ~= nil then
			return
		end

		local token = {}
		completionHoldToken = token
		task.delay(POST_FINAL_IMPACT_PRESENTATION_HOLD_SECONDS, function()
			if completionHoldToken ~= token or cancelled then
				return
			end

			markComplete()
		end)
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
		completionHoldToken = nil
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
		local impactPosition = resolveImpactPosition(target.rootPart, target.character, bossModel, rng)
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
			travelDuration = projectileTravelSeconds,
			scaleMultiplier = context.bossDefinition.scaleMultiplier,
			targetUserId = target.player.UserId,
		})

		task.delay(projectileTravelSeconds, function()
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

			applyImpactDamage(context, bossModel, impactPosition)
			context.EmitPresentation("impact", {
				index = missileIndex,
				impactPosition = impactPosition,
				scaleMultiplier = context.bossDefinition.scaleMultiplier,
				explosionRadius = AOE_RADIUS,
			})

			if shootingFinished and pendingImpactCount <= 0 then
				markCompleteAfterFinalImpactHold()
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

	context.EmitPresentation("start", {
		scaleMultiplier = context.bossDefinition.scaleMultiplier,
	})
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
