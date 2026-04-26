local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssetPaths = require(ReplicatedStorage.Shared.Assets.GameAssetPaths)
local GameAssetResolver = require(ReplicatedStorage.Shared.Assets.GameAssetResolver)

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local CombatMoveUtil = require(ReplicatedStorage.Shared.Combat.CombatMoveUtil)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)

local INITIAL_DAMAGE = 780
local LINGER_DAMAGE_PER_TICK = 150
local LINGER_DURATION_SECONDS = 3
local LINGER_TICK_INTERVAL_SECONDS = 1
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "MassiveGeezer"
local ANIMATION_NAME = "AcidBreath"
local SHOOT_MARKER_NAME = "Shoot"
local SHOOT_HITBOX_DELAY_SECONDS = 0.5
local CONE_DISTANCE_STUDS = 125
local CONE_WIDTH_STUDS = 85
local CONE_LAYERS = 16
local CONE_DURATION_SECONDS = 0.5
local POISON_SCREEN_DURATION_SECONDS = 2.5
local FLOOR_CLEARANCE_STUDS = 1.5
local FLOOR_RAYCAST_BUFFER_STUDS = 64
local FLOOR_RAYCAST_MIN_DISTANCE = 350
local FLOOR_RAYCAST_START_HEIGHT = 12

local stub = CreateExplicitBossMoveStub({
	bossId = "Massive Geezer",
	moveLabel = "Acid Breath",
	targetMode = "single",
	summaryTemplate = "{moveLabel} drenches {target}'s lane in acid",
	description = "Massive Geezer spews acid at a targeted player and leaves a puddle of acid on the ground.",
})

local AcidBreath = {
	CanUse = stub.CanUse,
	GetTargeting = stub.GetTargeting,
	ExecuteStub = stub.ExecuteStub,
}

local function resolveHumanoid(model: Model?): Humanoid?
	if model == nil then
		return nil
	end

	return model:FindFirstChildOfClass("Humanoid")
end

local function resolveStandingHeight(humanoid: Humanoid?, rootPart: BasePart): number
	return CombatMoveUtil.ResolveStandingHeight(humanoid, rootPart)
end

local function resolveHeadPart(model: Model?): BasePart?
	if model == nil then
		return nil
	end

	local head = model:FindFirstChild("Head", true)
	if head and head:IsA("BasePart") then
		return head
	end

	return nil
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

	local massiveGeezer = animations:FindFirstChild(ANIMATION_FOLDER_NAME)
	if not (massiveGeezer and massiveGeezer:IsA("Folder")) then
		return nil
	end

	local animationInstance = massiveGeezer:FindFirstChild(ANIMATION_NAME)
	if animationInstance and animationInstance:IsA("Animation") then
		return animationInstance
	end

	return nil
end

local function resolvePlanarDirection(fromPosition: Vector3, targetRootPart: BasePart?, fallbackPart: BasePart): Vector3
	if targetRootPart and targetRootPart.Parent ~= nil then
		local offset = targetRootPart.Position - fromPosition
		local planarOffset = Vector3.new(offset.X, 0, offset.Z)
		if planarOffset.Magnitude > 0.001 then
			return planarOffset.Unit
		end
	end

	local fallbackDirection = Vector3.new(fallbackPart.CFrame.LookVector.X, 0, fallbackPart.CFrame.LookVector.Z)
	if fallbackDirection.Magnitude > 0.001 then
		return fallbackDirection.Unit
	end

	return Vector3.new(0, 0, -1)
end

local function faceBossTowardTarget(bossModel: Model, bossRootPart: BasePart, targetRootPart: BasePart?)
	local direction = resolvePlanarDirection(bossRootPart.Position, targetRootPart, bossRootPart)
	local pivot = bossModel:GetPivot()
	bossModel:PivotTo(CFrame.lookAt(pivot.Position, pivot.Position + direction))
end

local function resolveGroundedConeOrigin(context, bossModel: Model, bossHead: BasePart, bossRootPart: BasePart): Vector3?
	local standingHeight = resolveStandingHeight(context.bossHumanoid, bossRootPart)
	local raycastDistance = math.max(
		FLOOR_RAYCAST_MIN_DISTANCE,
		(bossHead.Position.Y - bossRootPart.Position.Y) + standingHeight + FLOOR_RAYCAST_BUFFER_STUDS
	)
	local floorPosition = CombatMoveUtil.RaycastGroundNear(bossHead.Position, {
		sourceModel = bossModel,
		startHeight = FLOOR_RAYCAST_START_HEIGHT,
		distance = raycastDistance,
	})
	if floorPosition == nil then
		return nil
	end

	return Vector3.new(bossHead.Position.X, floorPosition.Y + FLOOR_CLEARANCE_STUDS, bossHead.Position.Z)
end

function AcidBreath.StartCast(context)
	local bossModel = context.bossModel
	local bossRootPart = context.bossRootPart
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return nil
	end

	local bossHead = resolveHeadPart(bossModel)
	if bossHead == nil or bossHead.Parent == nil then
		Logger.Warn("[AcidBreath] Could not resolve boss Head for Acid Breath.")
		return nil
	end

	local animationInstance = resolveAnimationInstance()
	if animationInstance == nil then
		Logger.Warn("[AcidBreath] Missing animation at ReplicatedStorage.GameAssets.Animations.Bosses.MassiveGeezer.AcidBreath.")
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		Logger.Warn("[AcidBreath] Failed to create animation profile:", profileOrError)
		return nil
	end

	faceBossTowardTarget(bossModel, bossRootPart, context.targetRootPart)
	local lockedAimDirection = resolvePlanarDirection(bossHead.Position, context.targetRootPart, bossRootPart)

	local profile = profileOrError
	local activeHitbox = nil
	local activeLingeringHitbox = nil
	local shootTriggered = false
	local warnedMissingShoot = false
	local completed = false
	local cancelled = false
	local cleanedUp = false
	local stoppedPresentation = false
	local hitTargets = {}
	local stoppedConnection = nil :: RBXScriptConnection?

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

	local function destroyLingeringHitbox()
		if activeLingeringHitbox == nil then
			return
		end

		activeLingeringHitbox:Destroy()
		activeLingeringHitbox = nil
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

	local function cleanup(stopAnimation: boolean)
		if cleanedUp then
			return
		end

		cleanedUp = true
		stopPresentation()
		destroyHitbox()
		destroyLingeringHitbox()
		disconnectStoppedConnection()

		if stopAnimation then
			profile:StopAnimation(animationInstance, ANIMATION_FADE_SECONDS)
		end
	end

	local function warnMissingShoot()
		if warnedMissingShoot or cancelled then
			return
		end

		warnedMissingShoot = true
		Logger.Warn(string.format(
			"[AcidBreath] Animation '%s' completed without firing the '%s' marker.",
			animationInstance.Name,
			SHOOT_MARKER_NAME
		))
	end

	local function getConeCFrame(): CFrame?
		if cancelled or bossHead.Parent == nil or bossRootPart.Parent == nil then
			return nil
		end

		local groundedOrigin = resolveGroundedConeOrigin(context, bossModel, bossHead, bossRootPart)
		if groundedOrigin ~= nil then
			return CFrame.lookAt(groundedOrigin, groundedOrigin + lockedAimDirection)
		end

		return CFrame.lookAt(bossHead.Position, bossHead.Position + lockedAimDirection)
	end

	local function startShootHitboxFlow()
		if completed or cancelled or cleanedUp or bossModel.Parent == nil or bossHead.Parent == nil then
			return
		end
		if bossRootPart.Parent == nil then
			return
		end

		context.EmitPresentation("shoot", {
			scaleMultiplier = context.bossDefinition.scaleMultiplier,
		})
		destroyHitbox()
		destroyLingeringHitbox()

		local coneCFrame = getConeCFrame()
		if coneCFrame == nil then
			markComplete()
			return
		end

		local hitbox
		hitbox = Hitbox.new({
			DebugVisibilityAttribute = "BossHitboxesVisible",
			Character = bossModel,
			HitboxCFrame = coneCFrame,
			HitboxType = "SpacialQuery",
			HitboxShape = "Pyramid",
			PyramidDistance = CONE_DISTANCE_STUDS,
			PyramidWidth = CONE_WIDTH_STUDS,
			PyramidLayers = CONE_LAYERS,
			Time = CONE_DURATION_SECONDS,
			MaxParts = 128,
		}, {
			HitTarget = function(targetModel: Model)
				if cleanedUp or hitTargets[targetModel] == true then
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
				humanoid:TakeDamage(CombatMoveUtil.ResolveScaledBossDamage(context, INITIAL_DAMAGE))
				context.EmitPresentation("poison", {
					targetUserId = player.UserId,
					durationSeconds = POISON_SCREEN_DURATION_SECONDS,
				})
			end,
			HitboxDestroy = function()
				if activeHitbox == hitbox then
					activeHitbox = nil
				end
			end,
		})

		activeHitbox = hitbox

		local lastDamagedAtByTarget = {}
		local lingeringHitbox
		lingeringHitbox = Hitbox.new({
			DebugVisibilityAttribute = "BossHitboxesVisible",
			Character = bossModel,
			HitboxCFrame = coneCFrame,
			HitboxType = "SpacialQuery",
			HitboxShape = "Pyramid",
			PyramidDistance = CONE_DISTANCE_STUDS,
			PyramidWidth = CONE_WIDTH_STUDS,
			PyramidLayers = CONE_LAYERS,
			Time = LINGER_DURATION_SECONDS,
			TickTime = LINGER_TICK_INTERVAL_SECONDS,
			MaxParts = 128,
		}, {
			HitTarget = function(targetModel: Model)
				local targetInfo = CombatMoveUtil.ResolveDamageTarget(targetModel)
				if targetInfo == nil then
					return
				end

				local now = os.clock()
				local lastDamagedAt = lastDamagedAtByTarget[targetModel]
				if lastDamagedAt ~= nil and (now - lastDamagedAt) < (LINGER_TICK_INTERVAL_SECONDS * 0.85) then
					return
				end

				lastDamagedAtByTarget[targetModel] = now
				targetInfo.humanoid:TakeDamage(CombatMoveUtil.ResolveScaledBossDamage(context, LINGER_DAMAGE_PER_TICK))
			end,
			HitboxDestroy = function()
				if activeLingeringHitbox == lingeringHitbox then
					activeLingeringHitbox = nil
				end
				lastDamagedAtByTarget = {}
			end,
		})

		activeLingeringHitbox = lingeringHitbox
	end

	local function handleShoot()
		if cancelled or shootTriggered or bossModel.Parent == nil or bossHead.Parent == nil then
			return
		end

		shootTriggered = true
		task.delay(SHOOT_HITBOX_DELAY_SECONDS, startShootHitboxFlow)
	end

	local track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, {
		[SHOOT_MARKER_NAME] = handleShoot,
	}, ANIMATION_FADE_SECONDS)
	if track == nil then
		Logger.Warn("[AcidBreath] Failed to play AcidBreath animation.")
		return nil
	end

	context.EmitPresentation("start", {
		scaleMultiplier = context.bossDefinition.scaleMultiplier,
	})
	track.Looped = false
	stoppedConnection = track.Stopped:Connect(function()
		disconnectStoppedConnection()
		destroyHitbox()
		if not shootTriggered then
			warnMissingShoot()
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

return table.freeze(AcidBreath)
