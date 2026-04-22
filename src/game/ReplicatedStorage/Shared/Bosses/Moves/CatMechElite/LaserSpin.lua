local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)

local DAMAGE_PER_TICK = 7
local TICK_INTERVAL_SECONDS = 0.25
local FALLBACK_ACTIVE_WINDOW_SECONDS = 4
local MAX_ACTIVE_WINDOW_SECONDS = 6
local MAX_HITBOX_PARTS = 192
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "CatMechElite"
local ANIMATION_NAME = "LaserSpin"
local BEAMS_MARKER_NAME = "Beams"
local BEAMS_END_MARKER_NAME = "BeamsEnd"
local VFX_FOLDER_NAME = "CatMechElite"
local LASER_SPIN_VFX_NAME = "LaserSpin"
local BEAMS_MODEL_NAME = "Beams"
local BEAM_PART_NAME = "Beam"
local BEAM_PRIMARY_NAME = "Middle"
local FLOOR_RAYCAST_START_HEIGHT = 40
local FLOOR_RAYCAST_DISTANCE = 500
local LASER_SPIN_SCALE = 20
local VISUAL_FLOOR_CLEARANCE_STUDS = 0.15
local HITBOX_CENTER_HEIGHT_STUDS = 2.75
local HITBOX_HEIGHT_STUDS = 5.5
local MIN_BEAM_LENGTH_STUDS = 16
local MAX_BEAM_LENGTH_STUDS = 700
local MIN_BEAM_THICKNESS_STUDS = 2.25
local MAX_BEAM_THICKNESS_STUDS = 5.5
local SPIN_RADIANS_PER_SECOND = (math.pi * 2) / (FALLBACK_ACTIVE_WINDOW_SECONDS * 2)

type BeamGeometry = {
	localCFrame: CFrame,
	size: Vector3,
}

local stub = CreateExplicitBossMoveStub({
	bossId = "Cat Mech Elite",
	moveLabel = "Laser Spin",
	targetMode = "wide_area",
	summaryTemplate = "{moveLabel} sweeps spinning lasers across {target}'s space",
	description = "Cat Mech Elite shoots out 12 lasers that spin for 4 seconds and players have to jump over them.",
})

local LaserSpin = {
	CanUse = stub.CanUse,
	GetTargeting = stub.GetTargeting,
	ExecuteStub = stub.ExecuteStub,
}

local function resolveAnimationInstance(): Animation?
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	local animations = gameAssets and gameAssets:FindFirstChild("Animations")
	local bossFolder = animations and animations:FindFirstChild(ANIMATION_FOLDER_NAME)
	local animationInstance = bossFolder and bossFolder:FindFirstChild(ANIMATION_NAME)
	if animationInstance and animationInstance:IsA("Animation") then
		return animationInstance
	end

	return nil
end

local function resolveBeamsModel(): Model?
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	local vfx = gameAssets and gameAssets:FindFirstChild("VFX")
	local bossFolder = vfx and vfx:FindFirstChild(VFX_FOLDER_NAME)
	local moveFolder = bossFolder and bossFolder:FindFirstChild(LASER_SPIN_VFX_NAME)
	local beamsModel = moveFolder and moveFolder:FindFirstChild(BEAMS_MODEL_NAME)
	if beamsModel and beamsModel:IsA("Model") then
		return beamsModel
	end

	return nil
end

local function resolveHumanoid(model: Model?): Humanoid?
	if model == nil then
		return nil
	end

	return model:FindFirstChildOfClass("Humanoid")
end

local function resolveModelPrimaryPart(model: Model): BasePart?
	local primaryPart = model.PrimaryPart
	if primaryPart then
		return primaryPart
	end

	local namedPrimary = model:FindFirstChild(BEAM_PRIMARY_NAME, true)
	if namedPrimary and namedPrimary:IsA("BasePart") then
		return namedPrimary
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
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

local function resolveVisualScale(bossDefinition: any): number
	return LASER_SPIN_SCALE
end

local function resolveRenderedBeamHalfHeight(visualScale: number): number
	local beamsModel = resolveBeamsModel()
	if beamsModel == nil then
		return HITBOX_CENTER_HEIGHT_STUDS
	end

	local maxHalfHeight = 0
	for _, child in ipairs(beamsModel:GetChildren()) do
		if not (child:IsA("BasePart") and child.Name == BEAM_PART_NAME) then
			continue
		end

		local mesh = child:FindFirstChildOfClass("SpecialMesh")
		local meshScaleY = if mesh then math.abs(mesh.Scale.Y) else 1
		local renderedHeight = math.abs(child.Size.Y * meshScaleY * visualScale)
		maxHalfHeight = math.max(maxHalfHeight, renderedHeight * 0.5)
	end

	if maxHalfHeight <= 0 then
		return HITBOX_CENTER_HEIGHT_STUDS
	end

	return maxHalfHeight
end

local function resolveBaseCFrames(context, visualScale: number): (CFrame?, CFrame?)
	local bossModel = context.bossModel
	local bossRootPart = context.bossRootPart
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return nil, nil
	end

	local groundPosition = raycastGroundNear(bossRootPart.Position, bossModel)
	local groundY = if groundPosition then groundPosition.Y else bossRootPart.Position.Y - (bossRootPart.Size.Y * 0.5)
	local lookVector = bossRootPart.CFrame.LookVector
	local planarLook = Vector3.new(lookVector.X, 0, lookVector.Z)
	if planarLook.Magnitude <= 0.001 then
		planarLook = Vector3.zAxis
	end

	local planarDirection = planarLook.Unit
	local beamCenterHeight = resolveRenderedBeamHalfHeight(visualScale) + VISUAL_FLOOR_CLEARANCE_STUDS
	local visualCenterPosition = Vector3.new(
		bossRootPart.Position.X,
		groundY + beamCenterHeight,
		bossRootPart.Position.Z
	)
	local hitboxCenterPosition = Vector3.new(
		bossRootPart.Position.X,
		groundY + beamCenterHeight,
		bossRootPart.Position.Z
	)

	return CFrame.lookAt(visualCenterPosition, visualCenterPosition + planarDirection),
		CFrame.lookAt(hitboxCenterPosition, hitboxCenterPosition + planarDirection)
end

local function resolveBeamGeometries(visualScale: number): { BeamGeometry }
	local beamsModel = resolveBeamsModel()
	if beamsModel == nil then
		return {}
	end

	local primaryPart = resolveModelPrimaryPart(beamsModel)
	if primaryPart == nil then
		return {}
	end

	local geometries = {}
	for _, child in ipairs(beamsModel:GetChildren()) do
		if not (child:IsA("BasePart") and child.Name == BEAM_PART_NAME) then
			continue
		end

		local mesh = child:FindFirstChildOfClass("SpecialMesh")
		local meshScale = if mesh then mesh.Scale else Vector3.one
		local visualLength = math.abs(child.Size.Z * meshScale.Z * visualScale)
		local beamLength = math.clamp(visualLength, MIN_BEAM_LENGTH_STUDS, MAX_BEAM_LENGTH_STUDS)
		local beamThickness = math.clamp(child.Size.X * visualScale, MIN_BEAM_THICKNESS_STUDS, MAX_BEAM_THICKNESS_STUDS)
		local localCFrame = primaryPart.CFrame:ToObjectSpace(child.CFrame)
		local localPosition = localCFrame.Position * visualScale
		local localRotation = localCFrame - localCFrame.Position

		table.insert(geometries, {
			localCFrame = CFrame.new(localPosition) * localRotation,
			size = Vector3.new(beamThickness, HITBOX_HEIGHT_STUDS, beamLength),
		})
	end

	return geometries
end

local function resolveSpinningBeamCFrame(baseCFrame: CFrame, beamGeometry: BeamGeometry, startedAt: number): CFrame
	local elapsed = math.max(0, os.clock() - startedAt)
	return baseCFrame * CFrame.Angles(0, elapsed * SPIN_RADIANS_PER_SECOND, 0) * beamGeometry.localCFrame
end

local function applyDamage(targetModel: Model, damagedAtByModel: { [Model]: number })
	local player = Players:GetPlayerFromCharacter(targetModel)
	if player == nil then
		return
	end

	local now = os.clock()
	local lastDamagedAt = damagedAtByModel[targetModel]
	if lastDamagedAt and now - lastDamagedAt < TICK_INTERVAL_SECONDS * 0.85 then
		return
	end

	local humanoid = resolveHumanoid(targetModel)
	if humanoid == nil or humanoid.Health <= 0 then
		return
	end

	damagedAtByModel[targetModel] = now
	humanoid:TakeDamage(DAMAGE_PER_TICK)
end

local function spawnBeamHitboxes(context, baseCFrame: CFrame, visualScale: number, startedAt: number)
	local bossModel = context.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		return {}
	end

	local geometries = resolveBeamGeometries(visualScale)
	if #geometries <= 0 then
		warn("[LaserSpin] Missing beam VFX geometry at ReplicatedStorage.GameAssets.VFX.CatMechElite.LaserSpin.Beams.")
		return {}
	end

	local damagedAtByModel = {}
	local hitboxes = table.create(#geometries)
	for _, beamGeometry in ipairs(geometries) do
		local hitbox = Hitbox.new({
			Character = bossModel,
			HitboxCFrame = function()
				return resolveSpinningBeamCFrame(baseCFrame, beamGeometry, startedAt)
			end,
			HitboxSize = function()
				return beamGeometry.size
			end,
			HitboxType = "SpacialQuery",
			Time = MAX_ACTIVE_WINDOW_SECONDS,
			TickTime = TICK_INTERVAL_SECONDS,
			MaxParts = MAX_HITBOX_PARTS,
		}, {
			HitTarget = function(targetModel: Model)
				applyDamage(targetModel, damagedAtByModel)
			end,
		})
		table.insert(hitboxes, hitbox)
	end

	return hitboxes
end

function LaserSpin.GetSelectionWeight(context)
	local distance = tonumber(context.distanceToTarget)
	if distance == nil then
		return 1
	end

	if distance <= 32 then
		return 1.35
	elseif distance <= 95 then
		return 1
	elseif distance <= 140 then
		return 0.55
	end

	return 0.2
end

function LaserSpin.StartCast(context)
	local bossModel = context.bossModel
	local bossRootPart = context.bossRootPart
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return nil
	end

	local animationInstance = resolveAnimationInstance()
	if animationInstance == nil then
		warn("[LaserSpin] Missing animation at ReplicatedStorage.GameAssets.Animations.CatMechElite.LaserSpin.")
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[LaserSpin] Failed to create animation profile:", profileOrError)
		return nil
	end

	local profile = profileOrError
	local track = nil :: AnimationTrack?
	local stoppedConnection = nil :: RBXScriptConnection?
	local activeHitboxes = {}
	local completed = false
	local cancelled = false
	local cleanedUp = false
	local beamsStarted = false
	local beamsEnded = false
	local presentationStopped = false
	local recoveryEndsAt = nil :: number?

	local function disconnectStoppedConnection()
		if stoppedConnection and stoppedConnection.Connected then
			stoppedConnection:Disconnect()
		end
		stoppedConnection = nil
	end

	local function destroyHitboxes()
		for _, hitbox in ipairs(activeHitboxes) do
			hitbox:Destroy()
		end
		table.clear(activeHitboxes)
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
		destroyHitboxes()
		stopPresentation()
	end

	local function cleanup(stopAnimation: boolean)
		if cleanedUp then
			return
		end

		cleanedUp = true
		destroyHitboxes()
		stopPresentation()
		disconnectStoppedConnection()

		if stopAnimation and track then
			profile:StopAnimation(animationInstance, ANIMATION_FADE_SECONDS)
		end
	end

	local function handleBeams()
		if cancelled or beamsStarted or bossModel.Parent == nil or bossRootPart.Parent == nil then
			return
		end

		local visualScale = resolveVisualScale(context.bossDefinition)
		local visualBaseCFrame, hitboxBaseCFrame = resolveBaseCFrames(context, visualScale)
		if visualBaseCFrame == nil or hitboxBaseCFrame == nil then
			markComplete()
			return
		end

		beamsStarted = true
		presentationStopped = false
		local startedAt = os.clock()
		activeHitboxes = spawnBeamHitboxes(context, hitboxBaseCFrame, visualScale, startedAt)
		context.EmitPresentation("start", {
			scaleMultiplier = context.bossDefinition.scaleMultiplier,
			visualScale = visualScale,
			baseCFrame = visualBaseCFrame,
			activeWindowSeconds = MAX_ACTIVE_WINDOW_SECONDS,
			spinRadiansPerSecond = SPIN_RADIANS_PER_SECOND,
		})
	end

	local function handleBeamsEnd()
		if cancelled or beamsEnded then
			return
		end

		beamsEnded = true
		markComplete()
	end

	track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, {
		[BEAMS_MARKER_NAME] = handleBeams,
		[BEAMS_END_MARKER_NAME] = handleBeamsEnd,
	}, ANIMATION_FADE_SECONDS)
	if track == nil then
		warn("[LaserSpin] Failed to play LaserSpin animation.")
		return nil
	end

	track.Looped = false
	stoppedConnection = track.Stopped:Connect(function()
		disconnectStoppedConnection()
		if cancelled then
			return
		end
		if not beamsStarted then
			warn(string.format(
				"[LaserSpin] Animation '%s' completed without firing the '%s' marker.",
				animationInstance.Name,
				BEAMS_MARKER_NAME
			))
		elseif not beamsEnded then
			warn(string.format(
				"[LaserSpin] Animation '%s' completed without firing the '%s' marker.",
				animationInstance.Name,
				BEAMS_END_MARKER_NAME
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

return table.freeze(LaserSpin)
