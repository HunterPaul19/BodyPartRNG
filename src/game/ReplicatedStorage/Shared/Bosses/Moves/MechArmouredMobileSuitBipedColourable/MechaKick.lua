local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local Knockback = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Knockback)

local DAMAGE = 20
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "Destroyer3000"
local ANIMATION_NAME = "Kick"
local IMPACT_MARKER_NAME = "Impact"
local LOWERCASE_IMPACT_MARKER_NAME = "impact"
local HITBOX_DURATION_SECONDS = 0.12
local MAX_HITBOX_PARTS = 128
local HITBOX_DIAMETER_FOOT_SCALE = 2.4
local MIN_HITBOX_DIAMETER = 36
local MAX_HITBOX_DIAMETER = 70
local MIN_HITBOX_HEIGHT = 24
local KNOCKBACK_SPEED = 52
local KNOCKBACK_UPWARD_SPEED = 16

local LEFT_FOOT_CANDIDATE_NAMES = {
	"LeftFoot",
	"Left Foot",
	"LeftLowerLeg",
	"HumanoidRootPart",
}

local stub = CreateExplicitBossMoveStub({
	bossId = "Destroyer 3000",
	moveLabel = "Mecha Kick",
	targetMode = "single",
	summaryTemplate = "{moveLabel} lashes into {target}",
	description = "The mech does a fast kick that hits any players close to it.",
})

local MechaKick = {
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

local function resolveLeftFootPart(bossModel: Model): BasePart?
	for _, partName in ipairs(LEFT_FOOT_CANDIDATE_NAMES) do
		local part = bossModel:FindFirstChild(partName, true)
		if part and part:IsA("BasePart") then
			return part
		end
	end

	return nil
end

local function resolveImpactCFrame(bossModel: Model, bossRootPart: BasePart): CFrame
	local leftFoot = resolveLeftFootPart(bossModel)
	if leftFoot then
		return leftFoot.CFrame
	end

	warn("[MechaKick] Could not resolve left foot part. Falling back to boss root.")
	return bossRootPart.CFrame
end

local function resolveHitboxSize(leftFoot: BasePart?): Vector3
	local footSize = if leftFoot then leftFoot.Size else Vector3.new(MIN_HITBOX_DIAMETER / HITBOX_DIAMETER_FOOT_SCALE, 12, 12)
	local diameter = math.clamp(
		math.max(footSize.X, footSize.Z) * HITBOX_DIAMETER_FOOT_SCALE,
		MIN_HITBOX_DIAMETER,
		MAX_HITBOX_DIAMETER
	)
	local height = math.max(footSize.Y * 2, MIN_HITBOX_HEIGHT)

	return Vector3.new(diameter, height, diameter)
end

local function resolveHitboxCFrame(impactCFrame: CFrame, leftFoot: BasePart?): CFrame
	local hitboxSize = resolveHitboxSize(leftFoot)
	local footHeight = if leftFoot then leftFoot.Size.Y else 0
	local footBottomY = impactCFrame.Position.Y - (footHeight * 0.5)
	local centerPosition = Vector3.new(
		impactCFrame.Position.X,
		footBottomY + (hitboxSize.Y * 0.5),
		impactCFrame.Position.Z
	)

	return CFrame.new(centerPosition)
end

local function buildKnockbackDirection(impactPosition: Vector3, bossRootPart: BasePart, targetRootPart: BasePart?): Vector3
	local direction = Vector3.new(bossRootPart.CFrame.LookVector.X, 0, bossRootPart.CFrame.LookVector.Z)
	if targetRootPart and targetRootPart.Parent ~= nil then
		local offset = targetRootPart.Position - impactPosition
		local planarOffset = Vector3.new(offset.X, 0, offset.Z)
		if planarOffset.Magnitude <= 0.001 then
			offset = targetRootPart.Position - bossRootPart.Position
			planarOffset = Vector3.new(offset.X, 0, offset.Z)
		end
		if planarOffset.Magnitude > 0.001 then
			direction = planarOffset.Unit
		end
	end

	if direction.Magnitude <= 0.001 then
		direction = Vector3.new(0, 0, -1)
	end

	return (direction.Unit * KNOCKBACK_SPEED) + Vector3.new(0, KNOCKBACK_UPWARD_SPEED, 0)
end

local function spawnKickHitbox(context, impactCFrame: CFrame, hitTargets: { [Model]: boolean })
	local bossModel = context.bossModel
	local bossRootPart = context.bossRootPart
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return nil
	end

	local leftFoot = resolveLeftFootPart(bossModel)
	local hitboxSize = resolveHitboxSize(leftFoot)
	local impactPosition = impactCFrame.Position
	local hitbox
	hitbox = Hitbox.new({
		Character = bossModel,
		HitboxCFrame = resolveHitboxCFrame(impactCFrame, leftFoot),
		HitboxSize = hitboxSize,
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
			local targetRootPart = resolveRootPart(targetModel)
			if humanoid == nil or humanoid.Health <= 0 then
				return
			end

			hitTargets[targetModel] = true
			humanoid:TakeDamage(DAMAGE)

			Knockback(targetModel, "Default", {
				Direction = buildKnockbackDirection(impactPosition, bossRootPart, targetRootPart),
				Duration = 0.22,
				RagdollDuration = 0.55,
				Stun = 0.35,
				IFrames = 0.2,
				AntiStun = 0.45,
				GroundMode = "DeterministicMap",
			})
		end,
		HitboxDestroy = function()
			hitbox = nil
		end,
	})

	hitbox:Visible(true)
	return hitbox
end

function MechaKick.GetSelectionWeight(context)
	local distance = tonumber(context.distanceToTarget)
	if distance == nil then
		return 1
	end

	if distance <= 16 then
		return 1.8
	elseif distance <= 30 then
		return 0.85
	elseif distance <= 50 then
		return 0.2
	end

	return 0.03
end

function MechaKick.StartCast(context)
	local bossModel = context.bossModel
	local bossRootPart = context.bossRootPart
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return nil
	end

	local animationInstance = resolveAnimationInstance()
	if animationInstance == nil then
		warn("[MechaKick] Missing animation at ReplicatedStorage.GameAssets.Animations.Destroyer3000.Kick.")
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[MechaKick] Failed to create animation profile:", profileOrError)
		return nil
	end

	local profile = profileOrError
	local activeHitbox = nil
	local impactTriggered = false
	local warnedMissingImpact = false
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

	local function warnMissingImpact()
		if warnedMissingImpact or cancelled then
			return
		end

		warnedMissingImpact = true
		warn(string.format(
			"[MechaKick] Animation '%s' completed without firing the '%s' marker.",
			animationInstance.Name,
			IMPACT_MARKER_NAME
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

	local function handleImpact()
		if cancelled or impactTriggered or bossModel.Parent == nil or bossRootPart.Parent == nil then
			return
		end

		impactTriggered = true
		destroyHitbox()

		local impactCFrame = resolveImpactCFrame(bossModel, bossRootPart)
		context.EmitPresentation("impact", {
			impactCFrame = impactCFrame,
			scaleMultiplier = context.bossDefinition.scaleMultiplier,
		})
		activeHitbox = spawnKickHitbox(context, impactCFrame, hitTargets)
	end

	local track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, {
		[IMPACT_MARKER_NAME] = handleImpact,
		[LOWERCASE_IMPACT_MARKER_NAME] = handleImpact,
		End = markComplete,
	}, ANIMATION_FADE_SECONDS)
	if track == nil then
		warn("[MechaKick] Failed to play Kick animation.")
		return nil
	end

	context.EmitPresentation("start", {
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

return table.freeze(MechaKick)
