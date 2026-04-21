local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local Knockback = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Knockback)

local DAMAGE = 20
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "OinanThickhoof"
local ANIMATION_NAME = "Stomp"
local STOMP_MARKER_NAME = "Stomp"
local HITBOX_SIZE = Vector3.new(50, 24, 50)
local HITBOX_VERTICAL_OFFSET = HITBOX_SIZE.Y * 0.5
local HITBOX_DURATION_SECONDS = 0.12
local MAX_HITBOX_PARTS = 128
local KNOCKBACK_SPEED = 46
local KNOCKBACK_UPWARD_SPEED = 14

local LEFT_FOOT_CANDIDATE_NAMES = {
	"LeftFoot",
	"Left Foot",
	"LeftHoof",
	"Left Hoof",
	"LeftLowerLeg",
}

local stub = CreateExplicitBossMoveStub({
	bossId = "Oinan Thickhoof",
	moveLabel = "Stomp",
	targetMode = "wide_area",
	summaryTemplate = "{moveLabel} thunders around {target}",
	description = "Oinan Thickhoof stomps on the ground when players get close.",
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

	warn("[OinanStomp] Could not resolve left foot part. Falling back to boss root.")
	return bossRootPart.CFrame
end

local function resolveHitboxCFrame(impactCFrame: CFrame): CFrame
	return CFrame.new(impactCFrame.Position + Vector3.new(0, HITBOX_VERTICAL_OFFSET, 0))
end

local function buildKnockbackDirection(bossRootPart: BasePart, impactPosition: Vector3, targetRootPart: BasePart?): Vector3
	local direction = Vector3.new(0, 0, -1)
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

	return (direction * KNOCKBACK_SPEED) + Vector3.new(0, KNOCKBACK_UPWARD_SPEED, 0)
end

local function spawnStompHitbox(context, impactCFrame: CFrame, hitTargets: { [Model]: boolean })
	local bossModel = context.bossModel
	local bossRootPart = context.bossRootPart
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return nil
	end

	local impactPosition = impactCFrame.Position
	local hitbox
	hitbox = Hitbox.new({
		Character = bossModel,
		HitboxCFrame = resolveHitboxCFrame(impactCFrame),
		HitboxSize = HITBOX_SIZE,
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
				Direction = buildKnockbackDirection(bossRootPart, impactPosition, targetRootPart),
				Duration = 0.2,
				RagdollDuration = 0.5,
				Stun = 0.35,
				IFrames = 0.2,
				AntiStun = 0.4,
				GroundMode = "DeterministicMap",
			})
		end,
		HitboxDestroy = function()
			if hitbox then
				hitbox = nil
			end
		end,
	})

	hitbox:Visible(true)
	return hitbox
end

function Stomp.GetSelectionWeight(context)
	local distance = tonumber(context.distanceToTarget)
	if distance == nil then
		return 1
	end

	if distance <= 12 then
		return 1.6
	elseif distance <= 25 then
		return 0.8
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
		warn("[OinanStomp] Missing animation at ReplicatedStorage.GameAssets.Animations.OinanThickhoof.Stomp.")
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[OinanStomp] Failed to create animation profile:", profileOrError)
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
			"[OinanStomp] Animation '%s' completed without firing the '%s' marker.",
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

		local impactCFrame = resolveImpactCFrame(bossModel, bossRootPart)
		context.EmitPresentation("stomp", {
			impactCFrame = impactCFrame,
			scaleMultiplier = context.bossDefinition.scaleMultiplier,
		})
		activeHitbox = spawnStompHitbox(context, impactCFrame, hitTargets)
	end

	local track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, {
		[STOMP_MARKER_NAME] = handleStomp,
		End = markComplete,
	}, ANIMATION_FADE_SECONDS)
	if track == nil then
		warn("[OinanStomp] Failed to play Stomp animation.")
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
