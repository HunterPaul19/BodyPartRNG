local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssetPaths = require(ReplicatedStorage.Shared.Assets.GameAssetPaths)
local GameAssetResolver = require(ReplicatedStorage.Shared.Assets.GameAssetResolver)
local Workspace = game:GetService("Workspace")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local CombatMoveUtil = require(ReplicatedStorage.Shared.Combat.CombatMoveUtil)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)

local DAMAGE = 250
local FLOOR_CUE_DELAY_SECONDS = 107 / 60
local TREE_RISE_START_DELAY_SECONDS = 163 / 60
local RISE_DURATION_SECONDS = (183 - 163) / 60
local CAST_END_DELAY_SECONDS = 467 / 60
local CUE_SCALE_MULTIPLIER = 4.5
local TREE_GAMEPLAY_SCALE_MULTIPLIER = CUE_SCALE_MULTIPLIER * 2
local HITBOX_DURATION_SECONDS = RISE_DURATION_SECONDS
local MAX_HITBOX_PARTS = 256
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "BroccoliBro"
local ANIMATION_NAME = "BroccoliSprout"
local VFX_FOLDER_NAME = "BroccoliBro"
local SPROUT_VFX_FOLDER_NAME = "BroccoliSprout"
local FLOOR_VFX_MODEL_NAME = "Floor"
local TREE_VFX_MODEL_NAME = "Broccoli"
local FALLBACK_FOOTPRINT_SIZE = Vector3.new(10, 0.05, 10)
local FLOOR_RAYCAST_START_HEIGHT = 20
local FLOOR_RAYCAST_DISTANCE = 350

local stub = CreateExplicitBossMoveStub({
	bossId = "Broccoli Bro",
	moveLabel = "Broccoli Sprout",
	targetMode = "all_players",
	summaryTemplate = "{moveLabel} erupts beneath {targets}",
	description = "Broccoli Bro makes giant broccoli trees sprout below all players, dealing damage.",
})

local BroccoliSprout = {
	CanUse = stub.CanUse,
	GetTargeting = stub.GetTargeting,
	ExecuteStub = stub.ExecuteStub,
}

type SproutGeometry = {
	treeSize: Vector3,
	footprintSize: Vector3,
	pivotToBoundingCenter: CFrame,
	treeRotationCorrection: CFrame,
	treeUprightAxis: string,
	scaledPivotToBoundingCenter: CFrame,
}

type SproutPoint = {
	index: number,
	floorCFrame: CFrame,
	footprintSize: Vector3,
	treeSize: Vector3,
	hitboxSize: Vector3,
	hitboxStartCFrame: CFrame,
	hitboxEndCFrame: CFrame,
	treeStartCFrame: CFrame,
	treeEndCFrame: CFrame,
	treeRotationCorrection: CFrame,
	treeUprightAxis: string,
}

local function scaleVector3(value: Vector3, scaleMultiplier: number): Vector3
	return Vector3.new(value.X * scaleMultiplier, value.Y * scaleMultiplier, value.Z * scaleMultiplier)
end

local function resolveTreeRotationCorrection(treeSize: Vector3): (CFrame, string)
	if treeSize.X >= treeSize.Y and treeSize.X >= treeSize.Z then
		return CFrame.Angles(0, 0, math.rad(90)), "X"
	end
	if treeSize.Z >= treeSize.X and treeSize.Z >= treeSize.Y then
		return CFrame.Angles(math.rad(-90), 0, 0), "Z"
	end

	return CFrame.new(), "Y"
end

local function resolveCorrectedTreeSize(treeSize: Vector3): Vector3
	if treeSize.X >= treeSize.Y and treeSize.X >= treeSize.Z then
		return Vector3.new(treeSize.Y, treeSize.X, treeSize.Z)
	end
	if treeSize.Z >= treeSize.X and treeSize.Z >= treeSize.Y then
		return Vector3.new(treeSize.X, treeSize.Z, treeSize.Y)
	end

	return treeSize
end

local function scalePivotToBoundingCenter(pivotToBoundingCenter: CFrame, scaleMultiplier: number): CFrame
	return CFrame.new(scaleVector3(pivotToBoundingCenter.Position, scaleMultiplier))
		* (pivotToBoundingCenter - pivotToBoundingCenter.Position)
end

local function resolveAnimationInstance(): Animation?
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	if not (gameAssets and gameAssets:IsA("Folder")) then
		return nil
	end

	local animations = GameAssetResolver.FindFirst({ GameAssetPaths.Animations.Bosses, GameAssetPaths.Legacy.Animations })
	if not (animations and animations:IsA("Folder")) then
		return nil
	end

	local broccoliBroFolder = animations:FindFirstChild(ANIMATION_FOLDER_NAME)
	if not (broccoliBroFolder and broccoliBroFolder:IsA("Folder")) then
		return nil
	end

	local animationInstance = broccoliBroFolder:FindFirstChild(ANIMATION_NAME)
	if animationInstance and animationInstance:IsA("Animation") then
		return animationInstance
	end

	return nil
end

local function resolveVfxFolder(): Folder?
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	local vfx = gameAssets and GameAssetResolver.FindFirst({ GameAssetPaths.Effects.Bosses, GameAssetPaths.Legacy.VFX })
	local broccoliBro = vfx and vfx:FindFirstChild(VFX_FOLDER_NAME)
	local sproutFolder = broccoliBro and broccoliBro:FindFirstChild(SPROUT_VFX_FOLDER_NAME)
	if sproutFolder and sproutFolder:IsA("Folder") then
		return sproutFolder
	end

	return nil
end

local function resolveSproutGeometry(): SproutGeometry?
	local sproutFolder = resolveVfxFolder()
	if sproutFolder == nil then
		Logger.Warn("[BroccoliSprout] Missing VFX folder at ReplicatedStorage.GameAssets.Effects.Bosses.BroccoliBro.BroccoliSprout.")
		return nil
	end

	local floorModel = sproutFolder:FindFirstChild(FLOOR_VFX_MODEL_NAME)
	if floorModel == nil then
		Logger.Warn("[BroccoliSprout] Missing floor VFX at ReplicatedStorage.GameAssets.Effects.Bosses.BroccoliBro.BroccoliSprout.Floor.")
		return nil
	end

	local treeModel = sproutFolder:FindFirstChild(TREE_VFX_MODEL_NAME)
	if not (treeModel and treeModel:IsA("Model")) then
		Logger.Warn("[BroccoliSprout] Missing tree model at ReplicatedStorage.GameAssets.Effects.Bosses.BroccoliBro.BroccoliSprout.Broccoli.")
		return nil
	end

	local treeBoundingCFrame, sourceTreeSize = treeModel:GetBoundingBox()
	if sourceTreeSize.X <= 0.1 or sourceTreeSize.Y <= 0.1 or sourceTreeSize.Z <= 0.1 then
		Logger.Warn("[BroccoliSprout] Broccoli tree VFX has invalid bounds.")
		return nil
	end
	local treeRotationCorrection, treeUprightAxis = resolveTreeRotationCorrection(sourceTreeSize)
	local treeSize = scaleVector3(resolveCorrectedTreeSize(sourceTreeSize), TREE_GAMEPLAY_SCALE_MULTIPLIER)

	local footprintSize = FALLBACK_FOOTPRINT_SIZE
	if floorModel:IsA("Model") then
		local _, floorSize = floorModel:GetBoundingBox()
		if floorSize.X > 0.1 and floorSize.Z > 0.1 then
			footprintSize = scaleVector3(
				Vector3.new(floorSize.X, math.max(0.01, floorSize.Y), floorSize.Z),
				TREE_GAMEPLAY_SCALE_MULTIPLIER
			)
		end
	elseif floorModel:IsA("BasePart") then
		footprintSize = scaleVector3(floorModel.Size, TREE_GAMEPLAY_SCALE_MULTIPLIER)
	end

	footprintSize = Vector3.new(
		math.max(footprintSize.X, treeSize.X),
		math.max(0.01, footprintSize.Y),
		math.max(footprintSize.Z, treeSize.Z)
	)

	return {
		treeSize = treeSize,
		footprintSize = footprintSize,
		pivotToBoundingCenter = treeModel:GetPivot():ToObjectSpace(treeBoundingCFrame),
		treeRotationCorrection = treeRotationCorrection,
		treeUprightAxis = treeUprightAxis,
		scaledPivotToBoundingCenter = scalePivotToBoundingCenter(
			treeModel:GetPivot():ToObjectSpace(treeBoundingCFrame),
			TREE_GAMEPLAY_SCALE_MULTIPLIER
		),
	}
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

local function addUniqueInstance(instances: { Instance }, seen: { [Instance]: boolean }, instance: Instance?)
	if instance == nil or instance.Parent == nil or seen[instance] == true then
		return
	end

	seen[instance] = true
	table.insert(instances, instance)
end

local function buildFloorRaycastParams(targetCharacter: Model?, bossModel: Model): RaycastParams
	local excludedInstances = {}
	local seen = {}

	addUniqueInstance(excludedInstances, seen, targetCharacter)
	addUniqueInstance(excludedInstances, seen, bossModel)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = excludedInstances
	raycastParams.IgnoreWater = false
	return raycastParams
end

local function raycastGroundNear(position: Vector3, targetCharacter: Model?, bossModel: Model): Vector3?
	local raycastParams = buildFloorRaycastParams(targetCharacter, bossModel)
	local rayOrigin = position + Vector3.new(0, FLOOR_RAYCAST_START_HEIGHT, 0)
	local rayDirection = Vector3.new(0, -(FLOOR_RAYCAST_START_HEIGHT + FLOOR_RAYCAST_DISTANCE), 0)
	local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	if raycastResult == nil then
		return nil
	end

	return raycastResult.Position
end

local function buildSproutPoint(index: number, groundPosition: Vector3, geometry: SproutGeometry): SproutPoint
	local floorCFrame = CFrame.new(groundPosition)
	local treeSize = geometry.treeSize
	local hitboxSize = treeSize
	local hitboxEndCFrame = CFrame.new(groundPosition + Vector3.new(0, treeSize.Y * 0.5, 0))
	local hitboxStartCFrame = hitboxEndCFrame - Vector3.new(0, treeSize.Y, 0)
	local pivotOffsetInverse = geometry.scaledPivotToBoundingCenter:Inverse()
	local treeEndBoundingCFrame = hitboxEndCFrame * geometry.treeRotationCorrection
	local treeStartBoundingCFrame = hitboxStartCFrame * geometry.treeRotationCorrection

	return {
		index = index,
		floorCFrame = floorCFrame,
		footprintSize = geometry.footprintSize,
		treeSize = treeSize,
		hitboxSize = hitboxSize,
		hitboxStartCFrame = hitboxStartCFrame,
		hitboxEndCFrame = hitboxEndCFrame,
		treeStartCFrame = treeStartBoundingCFrame * pivotOffsetInverse,
		treeEndCFrame = treeEndBoundingCFrame * pivotOffsetInverse,
		treeRotationCorrection = geometry.treeRotationCorrection,
		treeUprightAxis = geometry.treeUprightAxis,
	}
end

local function collectSproutPoints(targets: { any }, geometry: SproutGeometry, bossModel: Model): { SproutPoint }
	local points = {}
	local seenPlayers = {}

	for _, targetContext in ipairs(targets) do
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
		local groundPosition = raycastGroundNear(rootPart.Position, character, bossModel) or rootPart.Position
		table.insert(points, buildSproutPoint(#points + 1, groundPosition, geometry))
	end

	return points
end

local function collectWarningSproutPoints(context, geometry: SproutGeometry): { SproutPoint }
	local bossModel = context.bossModel
	if bossModel == nil then
		return {}
	end

	return collectSproutPoints(context.aliveTargets or {}, geometry, bossModel)
end

local function resolveRisingCFrame(point: SproutPoint, startedAt: number): CFrame
	local alpha = math.clamp((os.clock() - startedAt) / math.max(0.001, RISE_DURATION_SECONDS), 0, 1)
	return point.hitboxStartCFrame:Lerp(point.hitboxEndCFrame, alpha)
end

local function spawnSproutHitboxes(
	context,
	bossModel: Model,
	points: { SproutPoint },
	hitTargets: { [Model]: boolean },
	activeHitboxes: { any }
)
	local startedAt = os.clock()

	for _, point in ipairs(points) do
		local hitbox
		hitbox = Hitbox.new({
			DebugVisibilityAttribute = "BossHitboxesVisible",
			Character = bossModel,
			HitboxCFrame = function()
				if bossModel.Parent == nil then
					return nil
				end
				return resolveRisingCFrame(point, startedAt)
			end,
			HitboxSize = point.hitboxSize,
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
				humanoid:TakeDamage(CombatMoveUtil.ResolveScaledBossDamage(context, DAMAGE))
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

function BroccoliSprout.StartCast(context)
	local bossModel = context.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		return nil
	end

	local animationInstance = resolveAnimationInstance()
	if animationInstance == nil then
		Logger.Warn("[BroccoliSprout] Missing animation at ReplicatedStorage.GameAssets.Animations.Bosses.BroccoliBro.BroccoliSprout.")
		return nil
	end

	local geometry = resolveSproutGeometry()
	if geometry == nil then
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		Logger.Warn("[BroccoliSprout] Failed to create animation profile:", profileOrError)
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
	local sproutTriggered = false
	local presentationStopped = false
	local recoveryEndsAt = nil :: number?
	local warningPoints = collectWarningSproutPoints(context, geometry)

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

	local function emitFloor()
		if cancelled or completed or bossModel.Parent == nil then
			return
		end

		if #warningPoints <= 0 then
			return
		end

		context.EmitPresentation("floor", {
			points = warningPoints,
			scaleMultiplier = CUE_SCALE_MULTIPLIER,
		})
	end

	local function sprout()
		if cancelled or completed or bossModel.Parent == nil then
			return
		end

		sproutTriggered = true
		if #warningPoints <= 0 then
			Logger.Warn("[BroccoliSprout] Rise timing reached with no warning points.")
			stopPresentation()
			markComplete()
			return
		end

		context.EmitPresentation("sprout", {
			points = warningPoints,
			riseDurationSeconds = RISE_DURATION_SECONDS,
			scaleMultiplier = CUE_SCALE_MULTIPLIER,
			treeScaleMultiplier = TREE_GAMEPLAY_SCALE_MULTIPLIER,
			treeRotationCorrection = geometry.treeRotationCorrection,
			treeUprightAxis = geometry.treeUprightAxis,
		})
		spawnSproutHitboxes(context, bossModel, warningPoints, hitTargets, activeHitboxes)
	end

	local function completeCast()
		if cancelled then
			return
		end

		stopPresentation()
		markComplete()
	end

	track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, {}, ANIMATION_FADE_SECONDS)
	if track == nil then
		Logger.Warn("[BroccoliSprout] Failed to play BroccoliSprout animation.")
		return nil
	end

	context.EmitPresentation("start", {
		scaleMultiplier = CUE_SCALE_MULTIPLIER,
		treeRotationCorrection = geometry.treeRotationCorrection,
		treeUprightAxis = geometry.treeUprightAxis,
	})

	if #warningPoints > 0 then
		task.delay(FLOOR_CUE_DELAY_SECONDS, emitFloor)
		task.delay(TREE_RISE_START_DELAY_SECONDS, sprout)
		task.delay(CAST_END_DELAY_SECONDS, completeCast)
	else
		Logger.Warn("[BroccoliSprout] Cast started with no alive targets.")
		stopPresentation()
		markComplete()
	end

	track.Looped = false
	stoppedConnection = track.Stopped:Connect(function()
		disconnectStoppedConnection()
		if cancelled or completed or sproutTriggered then
			return
		end
		Logger.Warn(string.format("[BroccoliSprout] Animation '%s' stopped before the Moon rise timing.", animationInstance.Name))
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

return table.freeze(BroccoliSprout)
