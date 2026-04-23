local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local Knockback = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Knockback)

local DAMAGE = 20
local HITBOX_DURATION_SECONDS = 0.12
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "FlameGuardGeneral"
local ANIMATION_NAME = "FlameSlash"
local HITBOX_WIDTH_SCALE = 1.9
local HITBOX_DEPTH_SCALE = 5.5
local HITBOX_FORWARD_OFFSET_SCALE = 2.5
local HITBOX_GROUND_REACH_ROOT_HEIGHT_SCALE = 0.5

local stub = CreateExplicitBossMoveStub({
	bossId = "Flame Guard General",
	moveLabel = "Flame Slash",
	targetMode = "single",
	summaryTemplate = "{moveLabel} cleaves into {target}",
	description = "Flame Guard General winds up and slashes forward, striking players at the Impact marker.",
})

local FlameSlash = {
	CanUse = stub.CanUse,
	GetTargeting = stub.GetTargeting,
	ExecuteStub = stub.ExecuteStub,
}

local function getDistanceFromContext(context): number?
	return tonumber(context.distanceToTarget)
end

local function getWeightedValue(distance: number, points: { { distance: number, weight: number } }): number
	if #points <= 0 then
		return 0
	end
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

local function resolveRootPart(model: Model?): BasePart?
	if model == nil then
		return nil
	end

	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	local primaryPart = model.PrimaryPart
	if primaryPart then
		return primaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
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

local function buildKnockbackDirection(bossRootPart: BasePart, targetRootPart: BasePart?): Vector3
	local planarDirection = resolvePlanarDirection(bossRootPart, targetRootPart)
	return (planarDirection * 34) + Vector3.new(0, 10, 0)
end

local function resolveStandingHeight(bossHumanoid: Humanoid?, bossRootPart: BasePart): number
	if bossHumanoid == nil then
		return bossRootPart.Size.Y
	end

	return math.max((bossRootPart.Size.Y * 0.5) + bossHumanoid.HipHeight, bossRootPart.Size.Y)
end

local function resolveHitboxSizeAndOffset(bossHumanoid: Humanoid?, bossRootPart: BasePart): (Vector3, number)
	local rootSize = bossRootPart.Size
	local standingHeight = resolveStandingHeight(bossHumanoid, bossRootPart)
	return Vector3.new(
		rootSize.X * HITBOX_WIDTH_SCALE,
		(standingHeight * 2) + (rootSize.Y * HITBOX_GROUND_REACH_ROOT_HEIGHT_SCALE),
		rootSize.Z * HITBOX_DEPTH_SCALE
	), rootSize.Z * HITBOX_FORWARD_OFFSET_SCALE
end

local function buildImpactPresentationPayload(
	context,
	bossHumanoid: Humanoid?,
	bossRootPart: BasePart,
	targetRootPart: BasePart?,
	hitboxSize: Vector3,
	hitboxForwardOffset: number
): { [string]: any }
	local planarDirection = resolvePlanarDirection(bossRootPart, targetRootPart)
	local standingHeight = resolveStandingHeight(bossHumanoid, bossRootPart)
	local impactPosition = bossRootPart.Position - Vector3.new(0, standingHeight, 0) + (planarDirection * hitboxForwardOffset)
	local trailLength = math.max(bossRootPart.Size.Z * 2.75, hitboxSize.Z * 0.7)
	local trailWidth = math.max(bossRootPart.Size.X * 1.1, hitboxSize.X * 0.55)

	return {
		impactPosition = impactPosition,
		direction = planarDirection,
		trailLength = trailLength,
		trailWidth = trailWidth,
		burstScale = math.max(trailWidth, bossRootPart.Size.Y * 0.55),
		scaleMultiplier = context.bossDefinition.scaleMultiplier,
	}
end

function FlameSlash.GetSelectionWeight(context)
	local distance = getDistanceFromContext(context)
	if distance == nil then
		return 1
	end

	return getWeightedValue(distance, {
		{ distance = 0, weight = 2.2 },
		{ distance = 16, weight = 2.0 },
		{ distance = 32, weight = 1.7 },
		{ distance = 48, weight = 1.15 },
		{ distance = 72, weight = 0.55 },
		{ distance = 100, weight = 0.2 },
	})
end

function FlameSlash.StartCast(context)
	local bossModel = context.bossModel
	local bossHumanoid = context.bossHumanoid
	local bossRootPart = context.bossRootPart
	local emitPresentation = context.EmitPresentation
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return nil
	end

	local animationInstance = resolveAnimationInstance()
	if animationInstance == nil then
		warn(
			"[FlameSlash] Missing animation at ReplicatedStorage.GameAssets.Animations.FlameGuardGeneral.FlameSlash."
		)
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[FlameSlash] Failed to create animation profile:", profileOrError)
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
	local hitTargets = {}
	local stoppedConnection = nil
	local hitboxSize, hitboxForwardOffset = resolveHitboxSizeAndOffset(bossHumanoid, bossRootPart)

	local function disconnectStoppedConnection()
		if stoppedConnection and stoppedConnection.Connected then
			stoppedConnection:Disconnect()
		end
		stoppedConnection = nil
	end

	local function warnMissingImpact()
		if warnedMissingImpact or cancelled then
			return
		end

		warnedMissingImpact = true
		warn("[FlameSlash] Animation completed without firing the 'Impact' marker.")
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
		emitPresentation("stop")
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
		emitPresentation(
			"impact",
			buildImpactPresentationPayload(context, bossHumanoid, bossRootPart, context.targetRootPart, hitboxSize, hitboxForwardOffset)
		)
		destroyHitbox()

		local hitbox
		hitbox = Hitbox.new({
			DebugVisibilityAttribute = "BossHitboxesVisible",
			Character = bossModel,
			HitboxCFrame = function()
				if bossRootPart.Parent == nil then
					return nil
				end
				return bossRootPart.CFrame
			end,
			HitboxOffset = CFrame.new(0, 0, -hitboxForwardOffset),
			HitboxSize = hitboxSize,
			HitboxType = "SpacialQuery",
			Time = HITBOX_DURATION_SECONDS,
			MaxParts = 48,
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
				print(string.format(
					"[FlameSlash] Hit player '%s' with Flame Slash (model=%s, healthBefore=%.1f).",
					player.Name,
					targetModel.Name,
					humanoid.Health
				))
				humanoid:TakeDamage(DAMAGE)

				local targetRootPart = resolveRootPart(targetModel)
				Knockback(targetModel, "Default", {
					Direction = buildKnockbackDirection(bossRootPart, targetRootPart),
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
			end,
		})

		activeHitbox = hitbox
	end

	local track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, {
		Impact = handleImpact,
		End = markComplete,
	}, ANIMATION_FADE_SECONDS)
	if track == nil then
		warn("[FlameSlash] Failed to play FlameSlash animation.")
		return nil
	end

	emitPresentation("start", {
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
			stopPresentation()
			cleanup(true)
		end,
		IsComplete = function()
			return completed
		end,
	}
end

return table.freeze(FlameSlash)
