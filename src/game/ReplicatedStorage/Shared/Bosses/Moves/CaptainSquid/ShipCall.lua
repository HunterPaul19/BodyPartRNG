local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local CombatMoveUtil = require(ReplicatedStorage.Shared.Combat.CombatMoveUtil)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local Knockback = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Knockback)

local DAMAGE = 60
local AUTHORED_FPS = 60
local SHIP_RELEASE_FRAME = 91
local SHIP_END_FRAME = 162
local SHIP_RELEASE_SECONDS = SHIP_RELEASE_FRAME / AUTHORED_FPS
local SHIP_END_SECONDS = SHIP_END_FRAME / AUTHORED_FPS
local SHIP_ACTIVE_SECONDS = SHIP_END_SECONDS - SHIP_RELEASE_SECONDS
local SHIP_SPEED_STUDS_PER_SECOND = 150
local SHIP_FADE_SECONDS = 1.0
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "CaptainSquid"
local ANIMATION_NAME = "ShipCall"
local VFX_FOLDER_NAME = "VFX"
local CAPTAIN_SQUID_VFX_FOLDER_NAME = "CaptainSquid"
local SHIP_CALL_VFX_FOLDER_NAME = "ShipCall"
local SHIP_MODEL_NAME = "Ship"
local KNOCKBACK_FORWARD_SPEED = 44
local KNOCKBACK_UPWARD_SPEED = 10
local FLOOR_RAYCAST_START_HEIGHT = 5
local FLOOR_RAYCAST_DISTANCE = 200

local stub = CreateExplicitBossMoveStub({
	bossId = "Captain Squid",
	moveLabel = "Ship Call",
	targetMode = "wide_area",
	summaryTemplate = "{moveLabel} sails through {target}'s lane",
	description = "Captain Squid summons a pirate ship that sails forward and damages anyone in its path.",
})

local ShipCall = {
	CanUse = stub.CanUse,
	GetTargeting = stub.GetTargeting,
	ExecuteStub = stub.ExecuteStub,
}

local function getWeightedValue(distance: number, points: { { distance: number, weight: number } }): number
	if distance <= points[1].distance then
		return points[1].weight
	end

	for index = 2, #points do
		local previousPoint = points[index - 1]
		local currentPoint = points[index]
		if distance <= currentPoint.distance then
			local alpha = (distance - previousPoint.distance) / math.max(0.001, currentPoint.distance - previousPoint.distance)
			return previousPoint.weight + ((currentPoint.weight - previousPoint.weight) * alpha)
		end
	end

	return points[#points].weight
end

local function resolveHumanoid(model: Model?): Humanoid?
	if model == nil then
		return nil
	end

	return model:FindFirstChildOfClass("Humanoid")
end

local function resolveAnimationInstance(): Animation?
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	if not (gameAssets and gameAssets:IsA("Folder")) then
		return nil
	end

	local animations = gameAssets:FindFirstChild("Animations")
	if not (animations and animations:IsA("Folder")) then
		return nil
	end

	local captainSquidFolder = animations:FindFirstChild(ANIMATION_FOLDER_NAME)
	if not (captainSquidFolder and captainSquidFolder:IsA("Folder")) then
		return nil
	end

	local animationInstance = captainSquidFolder:FindFirstChild(ANIMATION_NAME)
	if animationInstance and animationInstance:IsA("Animation") then
		return animationInstance
	end

	return nil
end

local function resolveShipSourceModel(): Model?
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	if not (gameAssets and gameAssets:IsA("Folder")) then
		return nil
	end

	local vfxFolder = gameAssets:FindFirstChild(VFX_FOLDER_NAME)
	if not (vfxFolder and vfxFolder:IsA("Folder")) then
		return nil
	end

	local captainSquidFolder = vfxFolder:FindFirstChild(CAPTAIN_SQUID_VFX_FOLDER_NAME)
	if not (captainSquidFolder and captainSquidFolder:IsA("Folder")) then
		return nil
	end

	local shipCallFolder = captainSquidFolder:FindFirstChild(SHIP_CALL_VFX_FOLDER_NAME)
	if not (shipCallFolder and shipCallFolder:IsA("Folder")) then
		return nil
	end

	local shipModel = shipCallFolder:FindFirstChild(SHIP_MODEL_NAME)
	if shipModel and shipModel:IsA("Model") then
		return shipModel
	end

	return nil
end

local function resolveShipPrimaryPartBottomOffset(shipSourceModel: Model): number?
	local primaryPart = shipSourceModel.PrimaryPart or shipSourceModel:FindFirstChildWhichIsA("BasePart", true)
	if primaryPart == nil then
		warn("[ShipCall] Ship VFX model is missing a PrimaryPart/BasePart for floor alignment.")
		return nil
	end

	local relativePrimaryCFrame = shipSourceModel:GetPivot():ToObjectSpace(primaryPart.CFrame)
	local projectedHalfHeight = (math.abs(relativePrimaryCFrame.RightVector.Y) * primaryPart.Size.X * 0.5)
		+ (math.abs(relativePrimaryCFrame.UpVector.Y) * primaryPart.Size.Y * 0.5)
		+ (math.abs(relativePrimaryCFrame.LookVector.Y) * primaryPart.Size.Z * 0.5)

	return relativePrimaryCFrame.Position.Y - projectedHalfHeight
end

local function resolveShipHitboxSize(): Vector3?
	local shipSourceModel = resolveShipSourceModel()
	if shipSourceModel == nil then
		warn("[ShipCall] Missing ship VFX model at ReplicatedStorage.GameAssets.VFX.CaptainSquid.ShipCall.Ship.")
		return nil
	end

	local _, shipSize = shipSourceModel:GetBoundingBox()
	return shipSize
end

local function resolveShipFloorY(bossModel: Model, bossRootPart: BasePart): number?
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { bossModel }

	local rayOrigin = bossRootPart.Position + Vector3.new(0, FLOOR_RAYCAST_START_HEIGHT, 0)
	local rayDirection = Vector3.new(0, -(FLOOR_RAYCAST_START_HEIGHT + FLOOR_RAYCAST_DISTANCE), 0)
	local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	if raycastResult == nil then
		return nil
	end

	return raycastResult.Position.Y
end

local function resolvePlanarForwardDirection(bossRootPart: BasePart): Vector3
	local forwardDirection = Vector3.new(bossRootPart.CFrame.LookVector.X, 0, bossRootPart.CFrame.LookVector.Z)
	if forwardDirection.Magnitude <= 0.001 then
		return Vector3.new(0, 0, -1)
	end

	return forwardDirection.Unit
end

local function buildKnockbackDirection(travelDirection: Vector3): Vector3
	return (travelDirection * KNOCKBACK_FORWARD_SPEED) + Vector3.new(0, KNOCKBACK_UPWARD_SPEED, 0)
end

function ShipCall.GetSelectionWeight(context)
	local distance = tonumber(context.distanceToTarget)
	if distance == nil then
		return 1
	end

	return getWeightedValue(distance, {
		{ distance = 0, weight = 0.2 },
		{ distance = 12, weight = 0.28 },
		{ distance = 28, weight = 0.55 },
		{ distance = 48, weight = 0.8 },
		{ distance = 72, weight = 1.0 },
		{ distance = 104, weight = 1.1 },
		{ distance = 140, weight = 1.2 },
		{ distance = 176, weight = 1.2 },
	})
end

function ShipCall.StartCast(context)
	local bossModel = context.bossModel
	local bossRootPart = context.bossRootPart
	local animationInstance = resolveAnimationInstance()
	local shipSourceModel = resolveShipSourceModel()
	local shipHitboxSize = resolveShipHitboxSize()
	local shipPrimaryPartBottomOffset = if shipSourceModel ~= nil then resolveShipPrimaryPartBottomOffset(shipSourceModel) else nil
	local scaleMultiplier = math.max(0.1, tonumber(context.bossDefinition and context.bossDefinition.scaleMultiplier) or 1)
	if bossModel == nil
		or bossModel.Parent == nil
		or bossRootPart == nil
		or bossRootPart.Parent == nil
		or animationInstance == nil
		or shipHitboxSize == nil
		or shipPrimaryPartBottomOffset == nil then
		if animationInstance == nil then
			warn("[ShipCall] Missing animation at ReplicatedStorage.GameAssets.Animations.CaptainSquid.ShipCall.")
		end
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[ShipCall] Failed to create animation profile:", profileOrError)
		return nil
	end

	local scaledShipHitboxSize = shipHitboxSize * scaleMultiplier
	local scaledShipPrimaryPartBottomOffset = shipPrimaryPartBottomOffset * scaleMultiplier

	local profile = profileOrError
	local track = nil :: AnimationTrack?
	local stoppedConnection = nil :: RBXScriptConnection?
	local activeShipHitbox = nil
	local completed = false
	local cancelled = false
	local cleanedUp = false
	local shipSpawned = false
	local recoveryEndsAt = nil :: number?
	local presentationStopped = false
	local shipStartCFrame = nil :: CFrame?
	local travelDirection = nil :: Vector3?
	local shipStartTime = 0
	local hitTargets = {}

	local function stopPresentation(payload: { [string]: any }?)
		if presentationStopped then
			return
		end

		presentationStopped = true
		context.EmitPresentation("stop", payload)
	end

	local function disconnectStoppedConnection()
		if stoppedConnection and stoppedConnection.Connected then
			stoppedConnection:Disconnect()
		end
		stoppedConnection = nil
	end

	local function destroyShipHitbox()
		if activeShipHitbox == nil then
			return
		end

		activeShipHitbox:Destroy()
		activeShipHitbox = nil
	end

	local function finishAttack()
		if completed then
			return
		end

		completed = true
		recoveryEndsAt = os.clock() + (tonumber(context.move and context.move.recoverySeconds) or 0)
		stopPresentation({
			fadeSeconds = SHIP_FADE_SECONDS,
		})
		disconnectStoppedConnection()
		destroyShipHitbox()

		if track then
			profile:StopAnimation(animationInstance, ANIMATION_FADE_SECONDS)
		end
	end

	local function cleanup(stopAnimation: boolean)
		if cleanedUp then
			return
		end

		cleanedUp = true
		stopPresentation()
		disconnectStoppedConnection()
		destroyShipHitbox()

		if stopAnimation and track then
			profile:StopAnimation(animationInstance, ANIMATION_FADE_SECONDS)
		end
	end

	local function getCurrentShipCFrame(): CFrame?
		if shipStartCFrame == nil or travelDirection == nil then
			return nil
		end

		local elapsed = math.max(0, os.clock() - shipStartTime)
		local currentPosition = shipStartCFrame.Position + (travelDirection * (SHIP_SPEED_STUDS_PER_SECOND * elapsed))
		return CFrame.new(currentPosition) * (shipStartCFrame - shipStartCFrame.Position)
	end

	local function spawnShip()
		if cancelled or shipSpawned or bossModel.Parent == nil or bossRootPart.Parent == nil then
			return
		end

		shipSpawned = true
		travelDirection = resolvePlanarForwardDirection(bossRootPart)
		local shipFloorY = resolveShipFloorY(bossModel, bossRootPart)
		local shipSpawnPosition = Vector3.new(
			bossRootPart.Position.X,
			if shipFloorY ~= nil
				then shipFloorY - scaledShipPrimaryPartBottomOffset
				else bossRootPart.Position.Y - scaledShipPrimaryPartBottomOffset,
			bossRootPart.Position.Z
		)
		shipStartCFrame = CFrame.lookAt(shipSpawnPosition, shipSpawnPosition + travelDirection)
		shipStartTime = os.clock()

		context.EmitPresentation("ship", {
			startCFrame = shipStartCFrame,
			startPosition = shipStartCFrame.Position,
			direction = travelDirection,
			speed = SHIP_SPEED_STUDS_PER_SECOND,
			shipSize = shipHitboxSize,
			scaleMultiplier = scaleMultiplier,
			activeSeconds = SHIP_ACTIVE_SECONDS,
		})

		local shipHitbox
		shipHitbox = Hitbox.new({
			DebugVisibilityAttribute = "BossHitboxesVisible",
			Character = bossModel,
			HitboxCFrame = function()
				if cancelled then
					return nil
				end

				return getCurrentShipCFrame()
			end,
			HitboxSize = scaledShipHitboxSize,
			HitboxType = "SpacialQuery",
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
				if humanoid == nil or humanoid.Health <= 0 then
					return
				end

				if travelDirection == nil then
					return
				end

				hitTargets[targetModel] = true
				humanoid:TakeDamage(CombatMoveUtil.ResolveScaledBossDamage(context, DAMAGE))

				Knockback(targetModel, "Default", {
					Direction = buildKnockbackDirection(travelDirection),
					Duration = 0.18,
					RagdollDuration = 0.5,
					Stun = 0.35,
					IFrames = 0.2,
					AntiStun = 0.45,
					GroundMode = "DeterministicMap",
				})
			end,
			HitboxDestroy = function()
				if activeShipHitbox == shipHitbox then
					activeShipHitbox = nil
				end
			end,
		})

		activeShipHitbox = shipHitbox
	end

	track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, nil, ANIMATION_FADE_SECONDS)
	if track == nil then
		warn("[ShipCall] Failed to play ShipCall animation.")
		return nil
	end

	context.EmitPresentation("start", {
		scaleMultiplier = context.bossDefinition.scaleMultiplier,
	})
	task.delay(SHIP_RELEASE_SECONDS, spawnShip)
	task.delay(SHIP_END_SECONDS, function()
		if cancelled or completed then
			return
		end

		finishAttack()
	end)
	track.Looped = false
	stoppedConnection = track.Stopped:Connect(function()
		disconnectStoppedConnection()
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

return table.freeze(ShipCall)
