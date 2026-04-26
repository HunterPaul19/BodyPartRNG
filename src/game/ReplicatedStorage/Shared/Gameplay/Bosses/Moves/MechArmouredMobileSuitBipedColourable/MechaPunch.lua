local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssetPaths = require(ReplicatedStorage.Shared.Assets.GameAssetPaths)
local GameAssetResolver = require(ReplicatedStorage.Shared.Assets.GameAssetResolver)

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local CombatMoveUtil = require(ReplicatedStorage.Shared.Combat.CombatMoveUtil)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local Knockback = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Knockback)

local DAMAGE_PER_TICK = 60
local FINAL_DAMAGE = 300
local TICK_INTERVAL_SECONDS = 1
local HAZARD_DURATION_SECONDS = 3
local FINAL_HITBOX_DURATION_SECONDS = 0.12
local MIN_HITBOX_WIDTH = 48
local MIN_HITBOX_DEPTH = 52
local ROOT_WIDTH_SCALE = 3.2
local ROOT_DEPTH_SCALE = 4.2
local BOUNDS_WIDTH_SCALE = 1.35
local BOUNDS_DEPTH_SCALE = 1.1
local MIN_HITBOX_HEIGHT = 12
local MAX_HITBOX_PARTS = 192
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "Destroyer3000"
local ANIMATION_NAME = "Punch"
local IMPACT_MARKER_NAME = "Impact"
local FLOOR_RAYCAST_START_HEIGHT = 40
local FLOOR_RAYCAST_DISTANCE = 500
local LAUNCH_SPEED = 72
local LAUNCH_UPWARD_SPEED = 30

local stub = CreateExplicitBossMoveStub({
	bossId = "Destroyer 3000",
	moveLabel = "Mecha Punch",
	targetMode = "wide_area",
	summaryTemplate = "{moveLabel} detonates across {target}'s space",
	description = "Destroyer 3000 punches forward, creating a lingering frontal blast zone.",
})

local MechaPunch = {
	CanUse = stub.CanUse,
	GetTargeting = stub.GetTargeting,
	ExecuteStub = stub.ExecuteStub,
}

local function resolveAnimationInstance(): Animation?
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	if not (gameAssets and gameAssets:IsA("Folder")) then
		return nil
	end

	local animations = GameAssetResolver.FindFirst({ GameAssetPaths.Animations.Bosses, GameAssetPaths.Legacy.Animations })
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

local function raycastGroundNear(position: Vector3, bossModel: Model): Vector3?
	return CombatMoveUtil.RaycastGroundNear(position, {
		sourceModel = bossModel,
		startHeight = FLOOR_RAYCAST_START_HEIGHT,
		distance = FLOOR_RAYCAST_DISTANCE,
	})
end

local function resolvePlanarForward(bossRootPart: BasePart): Vector3
	local forward = Vector3.new(bossRootPart.CFrame.LookVector.X, 0, bossRootPart.CFrame.LookVector.Z)
	if forward.Magnitude <= 0.001 then
		return Vector3.new(0, 0, -1)
	end

	return forward.Unit
end

local function resolveStandingHeight(bossHumanoid: Humanoid?, bossRootPart: BasePart): number
	if bossHumanoid == nil then
		return bossRootPart.Size.Y
	end

	return math.max((bossRootPart.Size.Y * 0.5) + bossHumanoid.HipHeight, bossRootPart.Size.Y)
end

local function resolveHazardFootprint(bossModel: Model, bossRootPart: BasePart): (number, number)
	local _, boundingSize = bossModel:GetBoundingBox()
	local bossBoundsWidth = math.min(boundingSize.X, boundingSize.Z)
	local bossBoundsDepth = math.max(boundingSize.X, boundingSize.Z)
	local width = math.max(
		MIN_HITBOX_WIDTH,
		bossRootPart.Size.X * ROOT_WIDTH_SCALE,
		bossBoundsWidth * BOUNDS_WIDTH_SCALE
	)
	local depth = math.max(
		MIN_HITBOX_DEPTH,
		bossRootPart.Size.Z * ROOT_DEPTH_SCALE,
		bossBoundsDepth * BOUNDS_DEPTH_SCALE
	)

	return width, depth
end

local function resolveHazardGeometry(context): (CFrame, Vector3)
	local bossModel = context.bossModel
	local bossHumanoid = context.bossHumanoid
	local bossRootPart = context.bossRootPart
	local forward = resolvePlanarForward(bossRootPart)
	local right = forward:Cross(Vector3.yAxis)
	if right.Magnitude <= 0.001 then
		right = Vector3.xAxis
	else
		right = right.Unit
	end

	local hitboxWidth, hitboxDepth = resolveHazardFootprint(bossModel, bossRootPart)
	local centerPosition = bossRootPart.Position + (forward * ((bossRootPart.Size.Z * 0.5) + (hitboxDepth * 0.5)))
	local groundPosition = raycastGroundNear(centerPosition, bossModel) or centerPosition
	local standingHeight = resolveStandingHeight(bossHumanoid, bossRootPart)
	local topY = math.max(bossRootPart.Position.Y + (bossRootPart.Size.Y * 0.5), bossRootPart.Position.Y + standingHeight)
	local height = math.max(MIN_HITBOX_HEIGHT, topY - groundPosition.Y)
	local cframe = CFrame.fromMatrix(
		Vector3.new(centerPosition.X, groundPosition.Y + (height * 0.5), centerPosition.Z),
		right,
		Vector3.yAxis,
		-forward
	)

	return cframe, Vector3.new(hitboxWidth, height, hitboxDepth)
end

local function resolveLaunchDirection(hazardCFrame: CFrame): Vector3
	local forward = Vector3.new(hazardCFrame.LookVector.X, 0, hazardCFrame.LookVector.Z)
	if forward.Magnitude <= 0.001 then
		forward = Vector3.new(0, 0, -1)
	end

	return (forward.Unit * LAUNCH_SPEED) + Vector3.new(0, LAUNCH_UPWARD_SPEED, 0)
end

local function resolveImpactCFrame(hazardCFrame: CFrame, hazardSize: Vector3): CFrame
	return CFrame.fromMatrix(
		hazardCFrame.Position - (hazardCFrame.UpVector * (hazardSize.Y * 0.5)),
		hazardCFrame.RightVector,
		hazardCFrame.UpVector,
		hazardCFrame.ZVector
	)
end

local function applyTickDamage(context, targetModel: Model)
	local player = Players:GetPlayerFromCharacter(targetModel)
	if player == nil then
		return
	end

	local humanoid = resolveHumanoid(targetModel)
	if humanoid == nil or humanoid.Health <= 0 then
		return
	end

	humanoid:TakeDamage(CombatMoveUtil.ResolveScaledBossDamage(context, DAMAGE_PER_TICK))
end

local function applyFinalHit(context, targetModel: Model, hazardCFrame: CFrame)
	local player = Players:GetPlayerFromCharacter(targetModel)
	if player == nil then
		return
	end

	local humanoid = resolveHumanoid(targetModel)
	if humanoid == nil or humanoid.Health <= 0 then
		return
	end

	humanoid:TakeDamage(CombatMoveUtil.ResolveScaledBossDamage(context, FINAL_DAMAGE))
	Knockback(targetModel, "Default", {
		Direction = resolveLaunchDirection(hazardCFrame),
		Duration = 0.28,
		Stun = 0.35,
		IFrames = 0.2,
		AntiStun = 0.45,
		GroundMode = "DeterministicMap",
	})
end

local function spawnFinalHitbox(context, hazardCFrame: CFrame, hazardSize: Vector3)
	local bossModel = context.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		return
	end

	local hitTargets = {}
	local finalHitbox
	finalHitbox = Hitbox.new({
		DebugVisibilityAttribute = "BossHitboxesVisible",
		Character = bossModel,
		HitboxCFrame = hazardCFrame,
		HitboxSize = hazardSize,
		HitboxType = "SpacialQuery",
		Time = FINAL_HITBOX_DURATION_SECONDS,
		MaxParts = MAX_HITBOX_PARTS,
	}, {
		HitTarget = function(targetModel: Model)
			if hitTargets[targetModel] == true then
				return
			end

			hitTargets[targetModel] = true
			applyFinalHit(context, targetModel, hazardCFrame)
		end,
		HitboxDestroy = function()
			finalHitbox = nil
		end,
	})
end

local function spawnHazardHitbox(context, hazardCFrame: CFrame, hazardSize: Vector3)
	local bossModel = context.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		return nil
	end

	local hitbox
	hitbox = Hitbox.new({
		DebugVisibilityAttribute = "BossHitboxesVisible",
		Character = bossModel,
		HitboxCFrame = hazardCFrame,
		HitboxSize = hazardSize,
		HitboxType = "SpacialQuery",
		Time = HAZARD_DURATION_SECONDS,
		TickTime = TICK_INTERVAL_SECONDS,
		MaxParts = MAX_HITBOX_PARTS,
	}, {
		HitTarget = function(targetModel: Model)
			applyTickDamage(context, targetModel)
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

function MechaPunch.GetSelectionWeight(context)
	local distance = tonumber(context.distanceToTarget)
	if distance == nil then
		return 1
	end

	local rangeScale = resolveSelectionRangeScale(context)
	if distance <= 18 * rangeScale then
		return 1.4
	elseif distance <= 45 * rangeScale then
		return 1.0
	elseif distance <= 70 * rangeScale then
		return 0.45
	end

	return 0.12
end

function MechaPunch.StartCast(context)
	local bossModel = context.bossModel
	local bossRootPart = context.bossRootPart
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return nil
	end

	local animationInstance = resolveAnimationInstance()
	if animationInstance == nil then
		Logger.Warn("[MechaPunch] Missing animation at ReplicatedStorage.GameAssets.Animations.Bosses.Destroyer3000.Punch.")
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		Logger.Warn("[MechaPunch] Failed to create animation profile:", profileOrError)
		return nil
	end

	local profile = profileOrError
	local activeHitbox = nil
	local track = nil :: AnimationTrack?
	local stoppedConnection = nil :: RBXScriptConnection?
	local completed = false
	local cancelled = false
	local cleanedUp = false
	local impactTriggered = false
	local stoppedPresentation = false
	local recoveryEndsAt = nil :: number?
	local hazardToken = nil :: any

	local function disconnectStoppedConnection()
		if stoppedConnection and stoppedConnection.Connected then
			stoppedConnection:Disconnect()
		end
		stoppedConnection = nil
	end

	local function destroyActiveHitbox()
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
		recoveryEndsAt = os.clock() + (tonumber(context.move and context.move.recoverySeconds) or 0)
		stopPresentation()
		destroyActiveHitbox()
	end

	local function cleanup(stopAnimation: boolean)
		if cleanedUp then
			return
		end

		cleanedUp = true
		hazardToken = nil
		stopPresentation()
		destroyActiveHitbox()
		disconnectStoppedConnection()

		if stopAnimation and track then
			profile:StopAnimation(animationInstance, ANIMATION_FADE_SECONDS)
		end
	end

	local function finishHazard(token: any, hazardCFrame: CFrame, hazardSize: Vector3)
		if hazardToken ~= token or cancelled or completed then
			return
		end

		hazardToken = nil
		destroyActiveHitbox()
		spawnFinalHitbox(context, hazardCFrame, hazardSize)
		task.delay(FINAL_HITBOX_DURATION_SECONDS, function()
			if cancelled then
				return
			end

			markComplete()
		end)
	end

	local function handleImpact()
		if cancelled or impactTriggered or bossModel.Parent == nil or bossRootPart.Parent == nil then
			return
		end

		impactTriggered = true
		destroyActiveHitbox()

		local hazardCFrame, hazardSize = resolveHazardGeometry(context)
		context.EmitPresentation("impact", {
			impactCFrame = resolveImpactCFrame(hazardCFrame, hazardSize),
			scaleMultiplier = context.bossDefinition.scaleMultiplier,
		})
		activeHitbox = spawnHazardHitbox(context, hazardCFrame, hazardSize)

		local token = {}
		hazardToken = token
		task.delay(HAZARD_DURATION_SECONDS, function()
			finishHazard(token, hazardCFrame, hazardSize)
		end)
	end

	track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, {
		[IMPACT_MARKER_NAME] = handleImpact,
	}, ANIMATION_FADE_SECONDS)
	if track == nil then
		Logger.Warn("[MechaPunch] Failed to play Punch animation.")
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
		if not impactTriggered then
			Logger.Warn(string.format(
				"[MechaPunch] Animation '%s' completed without firing the '%s' marker.",
				animationInstance.Name,
				IMPACT_MARKER_NAME
			))
			markComplete()
		end
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

return table.freeze(MechaPunch)
