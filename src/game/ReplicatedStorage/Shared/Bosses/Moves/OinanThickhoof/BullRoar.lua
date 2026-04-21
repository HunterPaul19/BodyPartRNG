local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local StateUtil = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Utilities.StateUtil)

local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "OinanThickhoof"
local ANIMATION_NAME = "Roar"
local ROAR_MARKER_NAME = "Roar"
local HITBOX_RADIUS = 50
local HITBOX_HEIGHT = 100
local HITBOX_DURATION_SECONDS = 0.12
local STUN_DURATION_SECONDS = 3

local stub = CreateExplicitBossMoveStub({
	bossId = "Oinan Thickhoof",
	moveLabel = "Bull Roar",
	targetMode = "wide_area",
	summaryTemplate = "{moveLabel} locks down players around {target}",
	description = "Oinan Thickhoof roars and briefly stops nearby players from moving.",
})

local BullRoar = {
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

	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
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

local function isInsideRoarCylinder(bossRootPart: BasePart, targetRootPart: BasePart): boolean
	local offset = targetRootPart.Position - bossRootPart.Position
	local planarDistance = Vector3.new(offset.X, 0, offset.Z).Magnitude
	return planarDistance <= HITBOX_RADIUS and math.abs(offset.Y) <= HITBOX_HEIGHT * 0.5
end

local function stopCharacterMovement(character: Model, humanoid: Humanoid, rootPart: BasePart?)
	if humanoid.Parent == nil then
		return
	end

	StateUtil.createState(character, "Stunned", STUN_DURATION_SECONDS)
	StateUtil.createMovement(character, "WalkSpeed", 0, STUN_DURATION_SECONDS)
	StateUtil.createMovement(character, "JumpPower", 0, STUN_DURATION_SECONDS)
	StateUtil.createMovement(character, "JumpHeight", 0, STUN_DURATION_SECONDS)

	if rootPart and rootPart.Parent ~= nil then
		rootPart.AssemblyLinearVelocity = Vector3.new(0, rootPart.AssemblyLinearVelocity.Y, 0)
		rootPart.AssemblyAngularVelocity = Vector3.zero
	end
end

local function spawnRoarHitbox(context, hitTargets: { [Model]: boolean })
	local bossModel = context.bossModel
	local bossRootPart = context.bossRootPart
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return nil
	end

	local hitbox = Hitbox.new({
		Character = bossModel,
		HitboxCFrame = function()
			if bossRootPart.Parent == nil then
				return nil
			end
			return bossRootPart.CFrame
		end,
		HitboxSize = Vector3.new(HITBOX_RADIUS * 2, HITBOX_HEIGHT, HITBOX_RADIUS * 2),
		HitboxType = "SpacialQuery",
		Time = HITBOX_DURATION_SECONDS,
		MaxParts = 128,
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
			if humanoid == nil or humanoid.Health <= 0 or targetRootPart == nil then
				return
			end
			if not isInsideRoarCylinder(bossRootPart, targetRootPart) then
				return
			end

			hitTargets[targetModel] = true
			stopCharacterMovement(targetModel, humanoid, targetRootPart)
		end,
	})

	hitbox:Visible(true)
	return hitbox
end

function BullRoar.GetSelectionWeight(context)
	local distance = tonumber(context.distanceToTarget)
	if distance == nil then
		return 1
	end

	if distance <= 18 then
		return 1.45
	elseif distance <= HITBOX_RADIUS then
		return 1
	end

	return 0.2
end

function BullRoar.StartCast(context)
	local bossModel = context.bossModel
	local bossRootPart = context.bossRootPart
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return nil
	end

	local animationInstance = resolveAnimationInstance()
	if animationInstance == nil then
		warn("[BullRoar] Missing animation at ReplicatedStorage.GameAssets.Animations.OinanThickhoof.Roar.")
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[BullRoar] Failed to create animation profile:", profileOrError)
		return nil
	end

	local profile = profileOrError
	local activeHitbox = nil
	local roarTriggered = false
	local warnedMissingRoar = false
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

	local function warnMissingRoar()
		if warnedMissingRoar or cancelled then
			return
		end

		warnedMissingRoar = true
		warn(string.format(
			"[BullRoar] Animation '%s' completed without firing the '%s' marker.",
			animationInstance.Name,
			ROAR_MARKER_NAME
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

	local function handleRoar()
		if cancelled or roarTriggered or bossModel.Parent == nil or bossRootPart.Parent == nil then
			return
		end

		roarTriggered = true
		context.EmitPresentation("roar", {
			scaleMultiplier = context.bossDefinition.scaleMultiplier,
		})
		destroyHitbox()
		activeHitbox = spawnRoarHitbox(context, hitTargets)
	end

	local track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, {
		[ROAR_MARKER_NAME] = handleRoar,
		End = markComplete,
	}, ANIMATION_FADE_SECONDS)
	if track == nil then
		warn("[BullRoar] Failed to play Roar animation.")
		return nil
	end

	context.EmitPresentation("start", {
		scaleMultiplier = context.bossDefinition.scaleMultiplier,
	})
	track.Looped = false
	stoppedConnection = track.Stopped:Connect(function()
		disconnectStoppedConnection()
		destroyHitbox()
		if not roarTriggered then
			warnMissingRoar()
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

return table.freeze(BullRoar)
