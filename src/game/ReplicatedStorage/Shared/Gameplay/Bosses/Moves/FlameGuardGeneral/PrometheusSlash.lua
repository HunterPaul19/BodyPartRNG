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

local DAMAGE = 18
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "FlameGuardGeneral"
local ANIMATION_NAME = "PrometheusSlash"
local IMPACT_MARKER_NAME = "Impact"
local WALL_Y_AXIS_ROTATION = math.rad(90)
local WALL_TRAVEL_DISTANCE_STUDS = 1000
local WALL_TRAVEL_SPEED_STUDS_PER_SECOND = 150
local WALL_TRAVEL_DURATION_SECONDS = WALL_TRAVEL_DISTANCE_STUDS / WALL_TRAVEL_SPEED_STUDS_PER_SECOND
local VFX_FOLDER_NAME = "VFX"
local PROMETHEUS_VFX_FOLDER_NAME = "FlameGuardGeneral"
local PROMETHEUS_VFX_NAME = "PrometheusSlash"
local PROMETHEUS_SLASH_MODEL_NAME = "Slash"
local PROMETHEUS_SLASH_SCALE = 12.5

local stub = CreateExplicitBossMoveStub({
	bossId = "Flame Guard General",
	moveLabel = "Prometheus Slash",
	targetMode = "wide_area",
	summaryTemplate = "{moveLabel} carves a wall of fire toward {target}",
	description = "Flame Guard General brings his sword up and slashes downward, creating a long ranged AOE wall of fire.",
})

local PrometheusSlash = {
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

	local animations = GameAssetResolver.FindFirst({ GameAssetPaths.Animations.Bosses, GameAssetPaths.Legacy.Animations })
	if not (animations and animations:IsA("Folder")) then
		return nil
	end

	local flameGuardGeneral = animations:FindFirstChild(ANIMATION_FOLDER_NAME)
	if not (flameGuardGeneral and flameGuardGeneral:IsA("Folder")) then
		return nil
	end

	local animationInstance = flameGuardGeneral:FindFirstChild(ANIMATION_NAME)
	if animationInstance and animationInstance:IsA("Animation") then
		return animationInstance
	end

	return nil
end

local function resolvePrometheusSlashSourceModel(): Model?
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	if not (gameAssets and gameAssets:IsA("Folder")) then
		return nil
	end

	local vfxFolder = GameAssetResolver.FindFirst({ GameAssetPaths.Effects.Bosses, GameAssetPaths.Legacy.VFX })
	if not (vfxFolder and vfxFolder:IsA("Folder")) then
		return nil
	end

	local flameGuardGeneral = vfxFolder:FindFirstChild(PROMETHEUS_VFX_FOLDER_NAME)
	if not (flameGuardGeneral and flameGuardGeneral:IsA("Folder")) then
		return nil
	end

	local prometheusSlashFolder = flameGuardGeneral:FindFirstChild(PROMETHEUS_VFX_NAME)
	if not (prometheusSlashFolder and prometheusSlashFolder:IsA("Folder")) then
		return nil
	end

	local slashModel = prometheusSlashFolder:FindFirstChild(PROMETHEUS_SLASH_MODEL_NAME)
	if slashModel and slashModel:IsA("Model") then
		return slashModel
	end

	return nil
end

local function resolveModelBasePart(model: Model?): BasePart?
	if model == nil then
		return nil
	end

	local primaryPart = model.PrimaryPart
	if primaryPart then
		return primaryPart
	end

	local basePart = model:FindFirstChildWhichIsA("BasePart", true)
	if basePart then
		pcall(function()
			model.PrimaryPart = basePart
		end)
	end

	return basePart
end

local function resolvePlanarDirection(bossRootPart: BasePart, targetRootPart: BasePart?): Vector3
	local direction = Vector3.new(bossRootPart.CFrame.LookVector.X, 0, bossRootPart.CFrame.LookVector.Z)

	if targetRootPart and targetRootPart.Parent ~= nil then
		local offset = targetRootPart.Position - bossRootPart.Position
		local planarOffset = Vector3.new(offset.X, 0, offset.Z)
		if planarOffset.Magnitude > 0.001 then
			direction = planarOffset
		end
	end

	if direction.Magnitude <= 0.001 then
		return Vector3.new(0, 0, -1)
	end

	return direction.Unit
end

local function resolveStandingHeight(bossHumanoid: Humanoid?, bossRootPart: BasePart): number
	if bossHumanoid == nil then
		return bossRootPart.Size.Y
	end

	return math.max((bossRootPart.Size.Y * 0.5) + bossHumanoid.HipHeight, bossRootPart.Size.Y)
end

local function resolveSlashHitboxSizeAndOffset(bossRootPart: BasePart): (Vector3?, number?)
	local slashSource = resolvePrometheusSlashSourceModel()
	if slashSource == nil then
		Logger.Warn(
			"[PrometheusSlash] Missing slash VFX model at ReplicatedStorage.GameAssets.Effects.Bosses.FlameGuardGeneral.PrometheusSlash.Slash."
		)
		return nil, nil
	end

	local slashModel = slashSource:Clone()
	local scaleOk, scaleError = pcall(function()
		slashModel:ScaleTo(PROMETHEUS_SLASH_SCALE)
	end)
	if not scaleOk then
		Logger.Warn("[PrometheusSlash] Failed to scale slash VFX model:", scaleError)
		return nil, nil
	end

	local slashBasePart = resolveModelBasePart(slashModel)
	if slashBasePart == nil then
		Logger.Warn("[PrometheusSlash] Slash VFX model is missing a BasePart for hitbox sizing.")
		return nil, nil
	end

	local hitboxSize = slashBasePart.Size
	local forwardHalfExtent = ((math.abs(math.cos(WALL_Y_AXIS_ROTATION)) * hitboxSize.Z)
		+ (math.abs(math.sin(WALL_Y_AXIS_ROTATION)) * hitboxSize.X)) * 0.5
	local spawnOffset = forwardHalfExtent + (bossRootPart.Size.Z * 0.5)

	return hitboxSize, spawnOffset
end

local function buildKnockbackDirection(planarDirection: Vector3): Vector3
	return (planarDirection * 34) + Vector3.new(0, 10, 0)
end

function PrometheusSlash.GetSelectionWeight(context)
	local distance = tonumber(context.distanceToTarget)
	if distance == nil then
		return 1
	end

	return getWeightedValue(distance, {
		{ distance = 0, weight = 0.15 },
		{ distance = 18, weight = 0.3 },
		{ distance = 36, weight = 0.55 },
		{ distance = 56, weight = 0.8 },
		{ distance = 78, weight = 1.0 },
		{ distance = 110, weight = 0.85 },
	})
end

function PrometheusSlash.StartCast(context)
	local bossModel = context.bossModel
	local bossHumanoid = context.bossHumanoid
	local bossRootPart = context.bossRootPart
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return nil
	end

	local animationInstance = resolveAnimationInstance()
	if animationInstance == nil then
		Logger.Warn(
			"[PrometheusSlash] Missing animation at ReplicatedStorage.GameAssets.Animations.Bosses.FlameGuardGeneral.PrometheusSlash."
		)
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		Logger.Warn("[PrometheusSlash] Failed to create animation profile:", profileOrError)
		return nil
	end

	local profile = profileOrError
	local activeHitbox = nil
	local hitTargets = {}
	local impactTriggered = false
	local warnedMissingImpact = false
	local completed = false
	local cancelled = false
	local cleanedUp = false
	local stoppedConnection = nil
	local recoveryEndsAt = nil :: number?
	local stoppedPresentation = false
	local wallSize, initialForwardOffset = resolveSlashHitboxSizeAndOffset(bossRootPart)
	local standingHeight = resolveStandingHeight(bossHumanoid, bossRootPart)
	local travelDistance = WALL_TRAVEL_DISTANCE_STUDS
	if wallSize == nil or initialForwardOffset == nil then
		return nil
	end

	local function disconnectStoppedConnection()
		if stoppedConnection and stoppedConnection.Connected then
			stoppedConnection:Disconnect()
		end
		stoppedConnection = nil
	end

	local function stopPresentation()
		if stoppedPresentation then
			return
		end

		stoppedPresentation = true
		context.EmitPresentation("stop")
	end

	local function destroyHitbox()
		if activeHitbox == nil then
			return
		end

		activeHitbox:Destroy()
		activeHitbox = nil
	end

	local function markComplete()
		if completed then
			return
		end

		completed = true
		stopPresentation()
		recoveryEndsAt = os.clock() + (tonumber(context.move and context.move.recoverySeconds) or 0)
		destroyHitbox()
	end

	local function warnMissingImpact()
		if warnedMissingImpact or cancelled then
			return
		end

		warnedMissingImpact = true
		Logger.Warn(string.format(
			"[PrometheusSlash] Animation '%s' completed without firing the '%s' marker.",
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

		local planarDirection = resolvePlanarDirection(bossRootPart, context.targetRootPart)
		local groundY = bossRootPart.Position.Y - standingHeight
		local baseCenter = Vector3.new(
			bossRootPart.Position.X,
			groundY + (wallSize.Y * 0.5),
			bossRootPart.Position.Z
		) + (planarDirection * initialForwardOffset)
		local startTime = os.clock()
		context.EmitPresentation("impact", {
			startPosition = baseCenter,
			direction = planarDirection,
			travelDistance = travelDistance,
			travelDuration = WALL_TRAVEL_DURATION_SECONDS,
			yRotation = WALL_Y_AXIS_ROTATION,
			slashScale = PROMETHEUS_SLASH_SCALE,
			scaleMultiplier = context.bossDefinition.scaleMultiplier,
		})

		local hitbox
		hitbox = Hitbox.new({
			DebugVisibilityAttribute = "BossHitboxesVisible",
			Character = bossModel,
			HitboxCFrame = function()
				if cancelled or bossModel.Parent == nil or bossRootPart.Parent == nil then
					return nil
				end

				local elapsed = os.clock() - startTime
				local alpha = math.clamp(elapsed / WALL_TRAVEL_DURATION_SECONDS, 0, 1)
				local center = baseCenter + (planarDirection * (travelDistance * alpha))
				return CFrame.lookAt(center, center + planarDirection) * CFrame.Angles(0, WALL_Y_AXIS_ROTATION, 0)
			end,
			HitboxSize = wallSize,
			HitboxType = "SpacialQuery",
			Time = WALL_TRAVEL_DURATION_SECONDS,
			MaxParts = 64,
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
				Logger.Print(string.format(
					"[PrometheusSlash] Hit player '%s' with Prometheus Slash (model=%s, healthBefore=%.1f).",
					player.Name,
					targetModel.Name,
					humanoid.Health
				))
				humanoid:TakeDamage(CombatMoveUtil.ResolveScaledBossDamage(context, DAMAGE))

				Knockback(targetModel, "Default", {
					Direction = buildKnockbackDirection(planarDirection),
					Duration = 0.18,
					RagdollDuration = 0.45,
					Stun = 0.35,
					IFrames = 0.2,
					AntiStun = 0.4,
					GroundMode = "DeterministicMap",
				})
			end,
			HitboxDestroy = function()
				if activeHitbox == hitbox then
					activeHitbox = nil
				end

				if not cancelled then
					markComplete()
				end
			end,
		})

		activeHitbox = hitbox
	end

	local track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, {
		Impact = handleImpact,
	}, ANIMATION_FADE_SECONDS)
	if track == nil then
		Logger.Warn("[PrometheusSlash] Failed to play PrometheusSlash animation.")
		return nil
	end

	context.EmitPresentation("start", {
		scaleMultiplier = context.bossDefinition.scaleMultiplier,
	})
	track.Looped = false
	stoppedConnection = track.Stopped:Connect(function()
		disconnectStoppedConnection()
		if not impactTriggered then
			warnMissingImpact()
			markComplete()
			return
		end

		if activeHitbox == nil then
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

return table.freeze(PrometheusSlash)
