local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)

local DAMAGE = 22
local WARNING_SECONDS = 0.5
local HITBOX_HEIGHT = 24
local HITBOX_DURATION_SECONDS = 0.16
local MAX_HITBOX_PARTS = 256
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "MagmaFiend"
local ANIMATION_NAME = "Eruption"
local SPAWN_MARKER_NAME = "Spawn"
local VFX_FOLDER_NAME = "MagmaFiend"
local ERUPTION_VFX_FOLDER_NAME = "EruptionThrow"
local FLOOR_VFX_MODEL_NAME = "Floor"
local FALLBACK_FOOTPRINT_SIZE = Vector3.new(9, 0.05, 9)
local FLOOR_RAYCAST_START_HEIGHT = 20
local FLOOR_RAYCAST_DISTANCE = 350

local stub = CreateExplicitBossMoveStub({
	bossId = "Magma Fiend",
	moveLabel = "Eruption",
	targetMode = "all_players",
	summaryTemplate = "{moveLabel} bursts lava beneath {targets}",
	description = "Magma Fiend creates a burst of lava underneath every player.",
})

local Eruption = {
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

	local magmaFiendFolder = animations:FindFirstChild(ANIMATION_FOLDER_NAME)
	if not (magmaFiendFolder and magmaFiendFolder:IsA("Folder")) then
		return nil
	end

	local animationInstance = magmaFiendFolder:FindFirstChild(ANIMATION_NAME)
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

local function resolveFloorFootprintSize(): Vector3
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	local vfx = gameAssets and gameAssets:FindFirstChild("VFX")
	local magmaFiend = vfx and vfx:FindFirstChild(VFX_FOLDER_NAME)
	local eruptionThrow = magmaFiend and magmaFiend:FindFirstChild(ERUPTION_VFX_FOLDER_NAME)
	local floorModel = eruptionThrow and eruptionThrow:FindFirstChild(FLOOR_VFX_MODEL_NAME)
	if floorModel and floorModel:IsA("Model") then
		local _, size = floorModel:GetBoundingBox()
		return Vector3.new(math.max(0.1, size.X), math.max(0.01, size.Y), math.max(0.1, size.Z))
	end
	if floorModel and floorModel:IsA("BasePart") then
		return floorModel.Size
	end

	warn("[Eruption] Missing floor VFX at ReplicatedStorage.GameAssets.VFX.MagmaFiend.EruptionThrow.Floor; using fallback footprint.")
	return FALLBACK_FOOTPRINT_SIZE
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

local function collectEruptionPoints(context, footprintSize: Vector3): { { index: number, floorCFrame: CFrame, footprintSize: Vector3 } }
	local points = {}
	local seenPlayers = {}
	local bossModel = context.bossModel
	if bossModel == nil then
		return points
	end

	for _, targetContext in ipairs(context.aliveTargets or {}) do
		local player = targetContext.player
		if player == nil or seenPlayers[player] == true then
			continue
		end

		local character = player.Character or targetContext.character
		local humanoid = resolveHumanoid(character)
		local rootPart = resolveRootPart(character)
		if character == nil or humanoid == nil or humanoid.Health <= 0 or rootPart == nil then
			continue
		end

		seenPlayers[player] = true
		local groundPosition = raycastGroundNear(rootPart.Position, bossModel) or rootPart.Position
		table.insert(points, {
			index = #points + 1,
			floorCFrame = CFrame.new(groundPosition),
			footprintSize = footprintSize,
		})
	end

	return points
end

local function spawnEruptionHitboxes(
	bossModel: Model,
	points: { { index: number, floorCFrame: CFrame, footprintSize: Vector3 } },
	hitTargets: { [Model]: boolean },
	activeHitboxes: { any }
)
	for _, point in ipairs(points) do
		local hitboxSize = Vector3.new(point.footprintSize.X, HITBOX_HEIGHT, point.footprintSize.Z)
		local hitbox
		hitbox = Hitbox.new({
			Character = bossModel,
			HitboxCFrame = point.floorCFrame + Vector3.new(0, HITBOX_HEIGHT * 0.5, 0),
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
				if humanoid == nil or humanoid.Health <= 0 then
					return
				end

				hitTargets[targetModel] = true
				humanoid:TakeDamage(DAMAGE)
			end,
			HitboxDestroy = function()
				for index, activeHitbox in ipairs(activeHitboxes) do
					if activeHitbox == hitbox then
						table.remove(activeHitboxes, index)
						break
					end
				end
			end,
		})

		table.insert(activeHitboxes, hitbox)
	end
end

function Eruption.StartCast(context)
	local bossModel = context.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		return nil
	end

	local animationInstance = resolveAnimationInstance()
	if animationInstance == nil then
		warn("[Eruption] Missing animation at ReplicatedStorage.GameAssets.Animations.MagmaFiend.Eruption.")
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[Eruption] Failed to create animation profile:", profileOrError)
		return nil
	end

	local profile = profileOrError
	local track = nil :: AnimationTrack?
	local stoppedConnection = nil :: RBXScriptConnection?
	local activeHitboxes = {}
	local hitTargets = {}
	local completed = false
	local cancelled = false
	local cleanedUp = false
	local spawnTriggered = false
	local presentationStopped = false
	local recoveryEndsAt = nil :: number?
	local warningPoints = nil :: { { index: number, floorCFrame: CFrame, footprintSize: Vector3 } }?

	local function disconnectStoppedConnection()
		if stoppedConnection and stoppedConnection.Connected then
			stoppedConnection:Disconnect()
		end
		stoppedConnection = nil
	end

	local function destroyActiveHitboxes()
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
	end

	local function cleanup(stopAnimation: boolean)
		if cleanedUp then
			return
		end

		cleanedUp = true
		stopPresentation()
		disconnectStoppedConnection()
		destroyActiveHitboxes()

		if stopAnimation and track then
			profile:StopAnimation(animationInstance, ANIMATION_FADE_SECONDS)
		end
	end

	local function erupt()
		if cancelled or completed or bossModel.Parent == nil then
			return
		end

		local points = warningPoints or {}
		if #points <= 0 then
			stopPresentation()
			markComplete()
			return
		end

		context.EmitPresentation("erupt", {
			points = points,
		})
		spawnEruptionHitboxes(bossModel, points, hitTargets, activeHitboxes)
		stopPresentation()
		markComplete()
	end

	local function handleSpawn()
		if cancelled or spawnTriggered or bossModel.Parent == nil then
			return
		end

		spawnTriggered = true
		local footprintSize = resolveFloorFootprintSize()
		warningPoints = collectEruptionPoints(context, footprintSize)
		if #warningPoints <= 0 then
			warn("[Eruption] Spawn marker fired with no alive targets.")
			stopPresentation()
			markComplete()
			return
		end

		context.EmitPresentation("warn", {
			warningSeconds = WARNING_SECONDS,
			points = warningPoints,
		})

		task.delay(WARNING_SECONDS, erupt)
	end

	track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, {
		[SPAWN_MARKER_NAME] = handleSpawn,
	}, ANIMATION_FADE_SECONDS)
	if track == nil then
		warn("[Eruption] Failed to play Eruption animation.")
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
		if not spawnTriggered then
			warn(string.format("[Eruption] Animation '%s' completed without firing the '%s' marker.", animationInstance.Name, SPAWN_MARKER_NAME))
			stopPresentation()
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

return table.freeze(Eruption)
