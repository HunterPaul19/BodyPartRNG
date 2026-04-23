local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)

local DAMAGE_PER_TICK = 6
local TICK_INTERVAL_SECONDS = 0.25
local ACTIVE_WINDOW_SECONDS = 1.5
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "CatMechElite"
local ANIMATION_NAME = "CatSpin"
local VFX_MARKER_NAME = "RootPart"
local SPIN_START_MARKER_NAME = "SpinStart"
local SPIN_END_MARKER_NAME = "SpinEnd"
local END_MARKER_NAME = "End"
local MAX_HITBOX_PARTS = 192
local MIN_HITBOX_RADIUS = 14
local MAX_HITBOX_RADIUS = 48
local ROOT_RADIUS_MULTIPLIER = 1.75
local GROUNDED_HITBOX_HEIGHT = 12
local HITBOX_GROUND_INSET = 2
local FLOOR_RAYCAST_START_HEIGHT = 40
local FLOOR_RAYCAST_DISTANCE = 500

local stub = CreateExplicitBossMoveStub({
	bossId = "Cat Mech Elite",
	moveLabel = "Cat Spin",
	targetMode = "wide_area",
	summaryTemplate = "{moveLabel} shreds the space around {target}",
	description = "Cat Mech Elite spins like a blender and deals AOE damage to players close by.",
})

local CatSpin = {
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

local function resolveHitboxRadius(bossDefinition: any, bossRootPart: BasePart): number
	local scaleMultiplier = math.max(0.1, tonumber(bossDefinition and bossDefinition.scaleMultiplier) or 1)
	local scaleFloor = MIN_HITBOX_RADIUS * math.clamp(math.sqrt(scaleMultiplier) / math.sqrt(12.5), 0.75, 1.35)
	local rootRadius = math.max(bossRootPart.Size.X, bossRootPart.Size.Z) * ROOT_RADIUS_MULTIPLIER

	return math.clamp(math.max(scaleFloor, rootRadius), MIN_HITBOX_RADIUS, MAX_HITBOX_RADIUS)
end

local function resolveHitboxGeometry(context): (CFrame?, Vector3?)
	local bossModel = context.bossModel
	local bossRootPart = context.bossRootPart
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return nil, nil
	end

	local groundPosition = raycastGroundNear(bossRootPart.Position, bossModel)
	local groundY = if groundPosition then groundPosition.Y else bossRootPart.Position.Y - (bossRootPart.Size.Y * 0.5)
	local radius = resolveHitboxRadius(context.bossDefinition, bossRootPart)
	local centerPosition = Vector3.new(
		bossRootPart.Position.X,
		groundY + (GROUNDED_HITBOX_HEIGHT * 0.5) - HITBOX_GROUND_INSET,
		bossRootPart.Position.Z
	)

	return CFrame.new(centerPosition), Vector3.new(radius * 2, GROUNDED_HITBOX_HEIGHT, radius * 2)
end

local function applyDamage(targetModel: Model)
	local player = Players:GetPlayerFromCharacter(targetModel)
	if player == nil then
		return
	end

	local humanoid = resolveHumanoid(targetModel)
	if humanoid == nil or humanoid.Health <= 0 then
		return
	end

	humanoid:TakeDamage(DAMAGE_PER_TICK)
end

local function spawnSpinHitbox(context, onDestroy: (() -> ())?)
	local bossModel = context.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		return nil
	end

	local hitbox
	hitbox = Hitbox.new({
		Character = bossModel,
		HitboxCFrame = function()
			local hitboxCFrame = resolveHitboxGeometry(context)
			return hitboxCFrame
		end,
		HitboxSize = function()
			local _, hitboxSize = resolveHitboxGeometry(context)
			return hitboxSize
		end,
		HitboxType = "SpacialQuery",
		Time = ACTIVE_WINDOW_SECONDS,
		TickTime = TICK_INTERVAL_SECONDS,
		MaxParts = MAX_HITBOX_PARTS,
	}, {
		HitTarget = applyDamage,
		HitboxDestroy = function()
			hitbox = nil
			if onDestroy then
				onDestroy()
			end
		end,
	})
	hitbox:Visible(true)
	return hitbox
end

function CatSpin.GetSelectionWeight(context)
	local distance = tonumber(context.distanceToTarget)
	if distance == nil then
		return 1
	end

	local bossRootPart = context.bossRootPart
	local radius = if bossRootPart then resolveHitboxRadius(context.bossDefinition, bossRootPart) else MIN_HITBOX_RADIUS
	if distance <= radius * 0.85 then
		return 1.6
	elseif distance <= radius * 1.25 then
		return 0.85
	end

	return 0.2
end

function CatSpin.StartCast(context)
	local bossModel = context.bossModel
	local bossRootPart = context.bossRootPart
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return nil
	end

	local animationInstance = resolveAnimationInstance()
	if animationInstance == nil then
		warn("[CatSpin] Missing animation at ReplicatedStorage.GameAssets.Animations.CatMechElite.CatSpin.")
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[CatSpin] Failed to create animation profile:", profileOrError)
		return nil
	end

	local profile = profileOrError
	local track = nil :: AnimationTrack?
	local stoppedConnection = nil :: RBXScriptConnection?
	local activeHitbox = nil
	local completed = false
	local cancelled = false
	local cleanedUp = false
	local vfxTriggered = false
	local spinStarted = false
	local spinEnded = false
	local endTriggered = false
	local presentationStopped = false
	local recoveryEndsAt = nil :: number?

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
		destroyHitbox()
		stopPresentation()
	end

	local function cleanup(stopAnimation: boolean)
		if cleanedUp then
			return
		end

		cleanedUp = true
		destroyHitbox()
		stopPresentation()
		disconnectStoppedConnection()

		if stopAnimation and track then
			profile:StopAnimation(animationInstance, ANIMATION_FADE_SECONDS)
		end
	end

	local function handleRootPart()
		if cancelled or vfxTriggered then
			return
		end

		vfxTriggered = true
		context.EmitPresentation("start", {
			scaleMultiplier = context.bossDefinition.scaleMultiplier,
			activeWindowSeconds = ACTIVE_WINDOW_SECONDS,
		})
	end

	local function handleSpinStart()
		if cancelled or spinStarted or bossModel.Parent == nil or bossRootPart.Parent == nil then
			return
		end

		spinStarted = true
		handleRootPart()
		destroyHitbox()
		activeHitbox = spawnSpinHitbox(context, function()
			activeHitbox = nil
		end)
	end

	local function handleSpinEnd()
		if cancelled or spinEnded then
			return
		end

		spinEnded = true
		destroyHitbox()
		stopPresentation()
	end

	local function handleEnd()
		if cancelled or endTriggered then
			return
		end

		endTriggered = true
		if not spinEnded then
			handleSpinEnd()
		end
		markComplete()
	end

	track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, {
		[VFX_MARKER_NAME] = handleRootPart,
		[SPIN_START_MARKER_NAME] = handleSpinStart,
		[SPIN_END_MARKER_NAME] = handleSpinEnd,
		[END_MARKER_NAME] = handleEnd,
	}, ANIMATION_FADE_SECONDS)
	if track == nil then
		warn("[CatSpin] Failed to play CatSpin animation.")
		return nil
	end

	track.Looped = false
	stoppedConnection = track.Stopped:Connect(function()
		disconnectStoppedConnection()
		if cancelled then
			return
		end
		if not spinStarted then
			warn(string.format(
				"[CatSpin] Animation '%s' completed without firing the '%s' marker.",
				animationInstance.Name,
				SPIN_START_MARKER_NAME
			))
		elseif not spinEnded then
			warn(string.format(
				"[CatSpin] Animation '%s' completed without firing the '%s' marker.",
				animationInstance.Name,
				SPIN_END_MARKER_NAME
			))
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

return table.freeze(CatSpin)
