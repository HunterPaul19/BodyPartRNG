local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local Knockback = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Knockback)

local DAMAGE = 20
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "Agrynoth"
local ANIMATION_NAME = "Stomp"
local IMPACT_MARKER_NAME = "Impact"
local HITBOX_SIZE = Vector3.new(50, 24, 50)
local HITBOX_VERTICAL_OFFSET = HITBOX_SIZE.Y * 0.5
local HITBOX_DURATION_SECONDS = 0.12
local MAX_HITBOX_PARTS = 128
local KNOCKBACK_SPEED = 46
local KNOCKBACK_UPWARD_SPEED = 14
local FLOOR_RAYCAST_START_HEIGHT = 20
local FLOOR_RAYCAST_DISTANCE = 350

local LEFT_FOOT_CANDIDATE_NAMES = {
	"LeftFoot",
	"Left Foot",
	"LeftLowerLeg",
	"HumanoidRootPart",
}

local stub = CreateExplicitBossMoveStub({
	bossId = "Agrynoth",
	moveLabel = "Stomp",
	targetMode = "wide_area",
	summaryTemplate = "{moveLabel} hammers the ground around {target}",
	description = "Agrynoth stomps on the ground when players get close.",
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

local function resolveImpactCFrame(bossModel: Model, bossRootPart: BasePart): CFrame
	local footPart = resolveLeftFootPart(bossModel)
	local rawImpactCFrame = if footPart then footPart.CFrame else bossRootPart.CFrame
	if footPart == nil then
		warn("[AgrynothStomp] Could not resolve left foot part. Falling back to boss root.")
	end

	local groundPosition = raycastGroundNear(rawImpactCFrame.Position, bossModel)
	if groundPosition == nil then
		warn("[AgrynothStomp] Could not raycast stomp floor. Falling back to foot/root position.")
		return CFrame.new(rawImpactCFrame.Position)
	end

	return CFrame.new(groundPosition)
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
		warn("[AgrynothStomp] Missing animation at ReplicatedStorage.GameAssets.Animations.Agrynoth.Stomp.")
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[AgrynothStomp] Failed to create animation profile:", profileOrError)
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
			"[AgrynothStomp] Animation '%s' completed without firing the '%s' marker.",
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
		context.EmitPresentation("stomp", {
			impactCFrame = impactCFrame,
			scaleMultiplier = context.bossDefinition.scaleMultiplier,
		})
		activeHitbox = spawnStompHitbox(context, impactCFrame, hitTargets)
	end

	local track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, {
		[IMPACT_MARKER_NAME] = handleImpact,
		End = markComplete,
	}, ANIMATION_FADE_SECONDS)
	if track == nil then
		warn("[AgrynothStomp] Failed to play Stomp animation.")
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

return table.freeze(Stomp)
