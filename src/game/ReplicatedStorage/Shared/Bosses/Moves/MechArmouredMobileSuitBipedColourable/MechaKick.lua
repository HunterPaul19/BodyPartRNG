local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

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
local FLOOR_RAYCAST_START_HEIGHT = 40
local FLOOR_RAYCAST_DISTANCE = 500
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
	local rayOrigin = position + Vector3.new(0, FLOOR_RAYCAST_START_HEIGHT, 0)
	local rayDirection = Vector3.new(0, -(FLOOR_RAYCAST_START_HEIGHT + FLOOR_RAYCAST_DISTANCE), 0)
	local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, buildFloorRaycastParams(bossModel))
	if raycastResult == nil then
		return nil
	end

	return raycastResult.Position
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

local function resolveStandingHeight(bossHumanoid: Humanoid?, bossRootPart: BasePart): number
	if bossHumanoid == nil then
		return bossRootPart.Size.Y
	end

	return math.max((bossRootPart.Size.Y * 0.5) + bossHumanoid.HipHeight, bossRootPart.Size.Y)
end

local function resolveGroundedImpactCFrame(bossModel: Model, impactCFrame: CFrame, leftFoot: BasePart?): CFrame
	local footHeight = if leftFoot then leftFoot.Size.Y else 0
	local footBottomY = impactCFrame.Position.Y - (footHeight * 0.5)
	local groundPosition = raycastGroundNear(impactCFrame.Position, bossModel)
	local groundY = if groundPosition then groundPosition.Y else footBottomY

	return CFrame.new(impactCFrame.Position.X, groundY, impactCFrame.Position.Z)
end

local function resolveHitboxGeometry(
	bossModel: Model,
	bossHumanoid: Humanoid?,
	bossRootPart: BasePart,
	impactCFrame: CFrame,
	leftFoot: BasePart?
): (CFrame, Vector3)
	local baseHitboxSize = resolveHitboxSize(leftFoot)
	local footHeight = if leftFoot then leftFoot.Size.Y else 0
	local footBottomY = impactCFrame.Position.Y - (footHeight * 0.5)
	local groundPosition = raycastGroundNear(impactCFrame.Position, bossModel)
	local groundY = if groundPosition then groundPosition.Y else footBottomY
	local footTopY = if leftFoot then leftFoot.Position.Y + (leftFoot.Size.Y * 0.5) else impactCFrame.Position.Y
	local standingTopY = bossRootPart.Position.Y + resolveStandingHeight(bossHumanoid, bossRootPart)
	local rootTopY = bossRootPart.Position.Y + (bossRootPart.Size.Y * 0.5)
	local topY = math.max(footTopY, standingTopY, rootTopY)
	local height = math.max(baseHitboxSize.Y, MIN_HITBOX_HEIGHT, topY - groundY)
	local hitboxSize = Vector3.new(baseHitboxSize.X, height, baseHitboxSize.Z)
	local centerPosition = Vector3.new(
		impactCFrame.Position.X,
		groundY + (hitboxSize.Y * 0.5),
		impactCFrame.Position.Z
	)

	return CFrame.new(centerPosition), hitboxSize
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
	local hitboxCFrame, hitboxSize = resolveHitboxGeometry(
		bossModel,
		context.bossHumanoid,
		bossRootPart,
		impactCFrame,
		leftFoot
	)
	local impactPosition = impactCFrame.Position
	local hitbox
	hitbox = Hitbox.new({
		DebugVisibilityAttribute = "BossHitboxesVisible",
		Character = bossModel,
		HitboxCFrame = hitboxCFrame,
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

	return hitbox
end

local function resolveSelectionRangeScale(context): number
	local scaleMultiplier = tonumber(context.bossDefinition and context.bossDefinition.scaleMultiplier) or 1
	return math.clamp(math.sqrt(math.max(1, scaleMultiplier)), 1, 4)
end

function MechaKick.GetSelectionWeight(context)
	local distance = tonumber(context.distanceToTarget)
	if distance == nil then
		return 1
	end

	local rangeScale = resolveSelectionRangeScale(context)
	if distance <= 16 * rangeScale then
		return 1.8
	elseif distance <= 30 * rangeScale then
		return 0.85
	elseif distance <= 50 * rangeScale then
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
		local leftFoot = resolveLeftFootPart(bossModel)
		local groundedImpactCFrame = resolveGroundedImpactCFrame(bossModel, impactCFrame, leftFoot)
		context.EmitPresentation("impact", {
			impactCFrame = groundedImpactCFrame,
			sourceImpactCFrame = impactCFrame,
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
