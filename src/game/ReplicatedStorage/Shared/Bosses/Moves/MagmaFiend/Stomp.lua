local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local CombatMoveUtil = require(ReplicatedStorage.Shared.Combat.CombatMoveUtil)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local Knockback = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Knockback)

local DAMAGE = 180
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "MagmaFiend"
local ANIMATION_NAME = "Stomp"
local STOMP_MARKER_NAME = "Stomp"
local HITBOX_SIZE = Vector3.new(20, 20, 20)
local HITBOX_VERTICAL_OFFSET = HITBOX_SIZE.Y * 0.5
local HITBOX_DURATION_SECONDS = 0.12
local MAX_HITBOX_PARTS = 96
local KNOCKBACK_SPEED = 60
local KNOCKBACK_UPWARD_SPEED = 22

local LEFT_FOOT_CANDIDATE_NAMES = {
	"LeftFoot",
	"Left Foot",
	"LeftLowerLeg",
	"HumanoidRootPart",
}

local stub = CreateExplicitBossMoveStub({
	bossId = "Magma Fiend",
	moveLabel = "Stomp",
	targetMode = "wide_area",
	summaryTemplate = "{moveLabel} cracks the floor around {target}",
	description = "Magma Fiend stomps when players get too close.",
})

local Stomp = {
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

local function resolveLeftFootPart(bossModel: Model): BasePart?
	return CombatMoveUtil.ResolveNamedPart(bossModel, LEFT_FOOT_CANDIDATE_NAMES)
end

local function resolveImpactCFrames(context, bossModel: Model, bossRootPart: BasePart): (CFrame, CFrame?)
	local footPart = resolveLeftFootPart(bossModel)
	local rawImpactCFrame = if footPart then footPart.CFrame else bossRootPart.CFrame
	if footPart == nil then
		warn("[MagmaStomp] Could not resolve left foot part. Falling back to boss root.")
	end

	return CombatMoveUtil.ResolveFloorImpactCFrames({
		rawImpactCFrame = rawImpactCFrame,
		sourceModel = bossModel,
		targetCharacter = context.targetCharacter,
		aliveTargets = context.aliveTargets,
		warnPrefix = "[MagmaStomp]",
		distance = 2048,
		visualOffsetY = 1,
	})
end

local function resolveHitboxCFrame(impactCFrame: CFrame): CFrame
	return CFrame.new(impactCFrame.Position + Vector3.new(0, HITBOX_VERTICAL_OFFSET, 0))
end

local function buildKnockbackDirection(impactPosition: Vector3, targetRootPart: BasePart?): Vector3
	return CombatMoveUtil.BuildRadialKnockbackDirection({
		impactPosition = impactPosition,
		targetRootPart = targetRootPart,
		speed = KNOCKBACK_SPEED,
		upwardSpeed = KNOCKBACK_UPWARD_SPEED,
	})
end

local function spawnStompHitbox(context, impactCFrame: CFrame, hitTargets: { [Model]: boolean })
	local bossModel = context.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		return nil
	end

	local impactPosition = impactCFrame.Position
	local hitbox
	hitbox = Hitbox.new({
		DebugVisibilityAttribute = "BossHitboxesVisible",
		Character = bossModel,
		HitboxCFrame = resolveHitboxCFrame(impactCFrame),
		HitboxSize = HITBOX_SIZE,
		HitboxType = "SpacialQuery",
		Time = HITBOX_DURATION_SECONDS,
		MaxParts = MAX_HITBOX_PARTS,
	}, {
		HitTarget = function(targetModel: Model)
		local targetInfo =
			CombatMoveUtil.DamageOnce(hitTargets, targetModel, CombatMoveUtil.ResolveScaledBossDamage(context, DAMAGE))
			if targetInfo == nil then
				return
			end

			Knockback(targetModel, "Default", {
				Direction = buildKnockbackDirection(impactPosition, targetInfo.rootPart),
				Duration = 0.25,
				RagdollDuration = 0.65,
				Stun = 0.45,
				IFrames = 0.2,
				AntiStun = 0.45,
				GroundMode = "DeterministicMap",
			})
		end,
		HitboxDestroy = function()
			if hitbox then
				hitbox = nil
			end
		end,
	})

	return hitbox
end

function Stomp.GetSelectionWeight(context)
	local distance = tonumber(context.distanceToTarget)
	if distance == nil then
		return 1
	end

	if distance <= 16 then
		return 1.6
	elseif distance <= 28 then
		return 0.75
	end

	return 0.2
end

function Stomp.StartCast(context)
	local bossModel = context.bossModel
	local bossRootPart = context.bossRootPart
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return nil
	end

	local animationInstance = resolveAnimationInstance()
	if animationInstance == nil then
		warn("[MagmaStomp] Missing animation at ReplicatedStorage.GameAssets.Animations.MagmaFiend.Stomp.")
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[MagmaStomp] Failed to create animation profile:", profileOrError)
		return nil
	end

	local profile = profileOrError
	local activeHitbox = nil
	local stompTriggered = false
	local warnedMissingStomp = false
	local completed = false
	local cancelled = false
	local cleanedUp = false
	local stoppedPresentation = false
	local stoppedConnection = nil :: RBXScriptConnection?
	local hitTargets = {}

	local function disconnectStoppedConnection()
		if stoppedConnection and stoppedConnection.Connected then
			stoppedConnection:Disconnect()
		end
		stoppedConnection = nil
	end

	local function destroyHitbox()
		if activeHitbox == nil then
			return
		end

		activeHitbox:Destroy()
		activeHitbox = nil
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
		stopPresentation()
		destroyHitbox()
	end

	local function warnMissingStomp()
		if warnedMissingStomp or cancelled then
			return
		end

		warnedMissingStomp = true
		warn(string.format(
			"[MagmaStomp] Animation '%s' completed without firing the '%s' marker.",
			animationInstance.Name,
			STOMP_MARKER_NAME
		))
	end

	local function cleanup(stopAnimation: boolean)
		if cleanedUp then
			return
		end

		cleanedUp = true
		stopPresentation()
		destroyHitbox()
		disconnectStoppedConnection()

		if stopAnimation then
			profile:StopAnimation(animationInstance, ANIMATION_FADE_SECONDS)
		end
	end

	local function handleStomp()
		if cancelled or stompTriggered or bossModel.Parent == nil or bossRootPart.Parent == nil then
			return
		end

		stompTriggered = true
		destroyHitbox()

		local impactCFrame, floorImpactCFrame = resolveImpactCFrames(context, bossModel, bossRootPart)
		if floorImpactCFrame ~= nil then
			context.EmitPresentation("stomp", {
				impactCFrame = floorImpactCFrame,
				scaleMultiplier = context.bossDefinition.scaleMultiplier,
			})
		end
		activeHitbox = spawnStompHitbox(context, impactCFrame, hitTargets)
	end

	local track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, {
		[STOMP_MARKER_NAME] = handleStomp,
		End = markComplete,
	}, ANIMATION_FADE_SECONDS)
	if track == nil then
		warn("[MagmaStomp] Failed to play Stomp animation.")
		return nil
	end

	context.EmitPresentation("start", {
		scaleMultiplier = context.bossDefinition.scaleMultiplier,
	})
	track.Looped = false
	stoppedConnection = track.Stopped:Connect(function()
		disconnectStoppedConnection()
		destroyHitbox()
		if not stompTriggered then
			warnMissingStomp()
		end
		markComplete()
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
	}
end

return table.freeze(Stomp)
