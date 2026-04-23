local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local CombatMoveUtil = require(ReplicatedStorage.Shared.Combat.CombatMoveUtil)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local Knockback = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Knockback)

local DAMAGE = 22
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "FlameGuardGeneral"
local ANIMATION_NAME = "FlameBurst"
local IMPACT_MARKER_NAME = "Impact"
local HITBOX_SIZE = Vector3.new(150, 48, 150)
local HITBOX_VERTICAL_OFFSET = HITBOX_SIZE.Y * 0.5
local HITBOX_DURATION_SECONDS = 0.12
local MAX_HITBOX_PARTS = 128
local KNOCKBACK_SPEED = 46
local KNOCKBACK_UPWARD_SPEED = 14

local stub = CreateExplicitBossMoveStub({
	bossId = "Flame Guard General",
	moveLabel = "Fire Burst",
	targetMode = "wide_area",
	summaryTemplate = "{moveLabel} slams a fiery burst into the ground around {target}",
	description = "Flame Guard General stabs his sword into the ground and erupts a fiery blast around himself.",
})

local FireBurst = {
	CanUse = stub.CanUse,
	GetTargeting = stub.GetTargeting,
	ExecuteStub = stub.ExecuteStub,
}

local function getWeightedValue(distance: number, points: { { distance: number, weight: number } }): number
	if #points <= 0 then
		return 0
	end
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

local function resolveImpactCFrames(context, bossModel: Model, bossRootPart: BasePart): (CFrame, CFrame?)
	return CombatMoveUtil.ResolveFloorImpactCFrames({
		rawImpactCFrame = bossRootPart.CFrame,
		sourceModel = bossModel,
		targetCharacter = context.targetCharacter,
		aliveTargets = context.aliveTargets,
		warnPrefix = "[FireBurst]",
		distance = 2048,
	})
end

local function resolveHitboxCFrame(impactCFrame: CFrame): CFrame
	return CFrame.new(impactCFrame.Position + Vector3.new(0, HITBOX_VERTICAL_OFFSET, 0))
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

	local flameGuardGeneral = animations:FindFirstChild(ANIMATION_FOLDER_NAME)
	if not (flameGuardGeneral and flameGuardGeneral:IsA("Folder")) then
		return nil
	end

	local animationInstance = flameGuardGeneral:FindFirstChild(ANIMATION_NAME)
	if animationInstance and animationInstance:IsA("Animation") then
		return animationInstance
	end

	return nil
end

local function buildKnockbackDirection(bossRootPart: BasePart, impactPosition: Vector3, targetRootPart: BasePart?): Vector3
	return CombatMoveUtil.BuildRadialKnockbackDirection({
		impactPosition = impactPosition,
		targetRootPart = targetRootPart,
		fallbackPosition = bossRootPart.Position,
		speed = KNOCKBACK_SPEED,
		upwardSpeed = KNOCKBACK_UPWARD_SPEED,
	})
end

local function spawnFireBurstHitbox(
	context,
	impactCFrame: CFrame,
	hitTargets: { [Model]: boolean },
	onDestroy: (() -> ())?
)
	local bossModel = context.bossModel
	local bossRootPart = context.bossRootPart
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
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
				Direction = buildKnockbackDirection(bossRootPart, impactPosition, targetInfo.rootPart),
				Duration = 0.2,
				RagdollDuration = 0.5,
				Stun = 0.35,
				IFrames = 0.2,
				AntiStun = 0.4,
				GroundMode = "DeterministicMap",
			})
		end,
		HitboxDestroy = function()
			if onDestroy then
				onDestroy()
			end
			if hitbox then
				hitbox = nil
			end
		end,
	})

	return hitbox
end

function FireBurst.GetSelectionWeight(context)
	local distance = tonumber(context.distanceToTarget)
	if distance == nil then
		return 1
	end

	return getWeightedValue(distance, {
		{ distance = 0, weight = 0.2 },
		{ distance = 12, weight = 0.55 },
		{ distance = 24, weight = 1.35 },
		{ distance = 38, weight = 1.1 },
		{ distance = 56, weight = 0.5 },
		{ distance = 84, weight = 0.15 },
	})
end

function FireBurst.StartCast(context)
	local bossModel = context.bossModel
	local bossRootPart = context.bossRootPart
	local emitPresentation = context.EmitPresentation
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return nil
	end

	local animationInstance = resolveAnimationInstance()
	if animationInstance == nil then
		warn(
			"[FireBurst] Missing animation at ReplicatedStorage.GameAssets.Animations.FlameGuardGeneral.FlameBurst."
		)
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[FireBurst] Failed to create animation profile:", profileOrError)
		return nil
	end

	local profile = profileOrError
	local activeHitbox = nil
	local impactTriggered = false
	local warnedMissingImpact = false
	local completed = false
	local cancelled = false
	local cleanedUp = false
	local hitTargets = {}
	local stoppedConnection = nil
	local stoppedPresentation = false

	local function disconnectStoppedConnection()
		if stoppedConnection and stoppedConnection.Connected then
			stoppedConnection:Disconnect()
		end
		stoppedConnection = nil
	end

	local function warnMissingImpact()
		if warnedMissingImpact or cancelled then
			return
		end

		warnedMissingImpact = true
		warn("[FireBurst] Animation completed without firing the 'Impact' marker.")
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
		emitPresentation("stop")
	end

	local function markComplete()
		if completed then
			return
		end

		completed = true
		stopPresentation()
		destroyHitbox()
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

	local function handleImpact()
		if cancelled or impactTriggered or bossModel.Parent == nil or bossRootPart.Parent == nil then
			return
		end

		impactTriggered = true
		emitPresentation("impact")
		destroyHitbox()

		local impactCFrame = resolveImpactCFrames(context, bossModel, bossRootPart)
		activeHitbox = spawnFireBurstHitbox(context, impactCFrame, hitTargets, function()
			activeHitbox = nil
		end)
	end

	local track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, {
		[IMPACT_MARKER_NAME] = handleImpact,
		End = markComplete,
	}, ANIMATION_FADE_SECONDS)
	if track == nil then
		warn("[FireBurst] Failed to play FlameBurst animation.")
		return nil
	end

	emitPresentation("start", {
		scaleMultiplier = context.bossDefinition.scaleMultiplier,
	})
	track.Looped = false
	stoppedConnection = track.Stopped:Connect(function()
		disconnectStoppedConnection()
		destroyHitbox()
		if not impactTriggered then
			warnMissingImpact()
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

return table.freeze(FireBurst)
