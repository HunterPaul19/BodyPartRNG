local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)

local DAMAGE = 16
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "FlameGuardGeneral"
local ANIMATION_NAME = "FlameBurst"
local ANIMATION_IMPACT_TIME_SECONDS = 1.2
local ANIMATION_END_TIME_SECONDS = 3.9833333492279054
local SHOCKWAVE_DURATION_SECONDS = ANIMATION_END_TIME_SECONDS - ANIMATION_IMPACT_TIME_SECONDS
local SHOCKWAVE_LIFETIME_EPSILON_SECONDS = 0.05
local GROUND_OFFSET = 0.15
local POP_HORIZONTAL_SPEED = 18
local POP_VERTICAL_SPEED = 9
local VISUAL_TEMPLATE_PATH = "ReplicatedStorage.GameAssets.VFX.FlameGuardGeneral.FlameBurst.MapRing"

local stub = CreateExplicitBossMoveStub({
	bossId = "Flame Guard General",
	moveLabel = "Fire Burst",
	targetMode = "wide_area",
	summaryTemplate = "{moveLabel} blasts a jumping shockwave around {target}",
	description = "Flame Guard General stabs his sword into the ground and releases a shockwave of fire that players have to jump over.",
})

local FireBurst = {
	CanUse = stub.CanUse,
	GetTargeting = stub.GetTargeting,
	ExecuteStub = stub.ExecuteStub,
}

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

local function resolveStandingHeight(bossHumanoid: Humanoid?, bossRootPart: BasePart): number
	if bossHumanoid == nil then
		return bossRootPart.Size.Y
	end

	return math.max((bossRootPart.Size.Y * 0.5) + bossHumanoid.HipHeight, bossRootPart.Size.Y)
end

local function resolveArenaEndRadius(): number?
	local activeBossArena = Workspace:FindFirstChild("ActiveBossArena")
	if not (activeBossArena and activeBossArena:IsA("Model")) then
		return nil
	end

	local _, arenaSize = activeBossArena:GetBoundingBox()
	return math.max(arenaSize.X, arenaSize.Z) * 0.5
end

local function resolveShockwaveData(bossHumanoid: Humanoid?, bossRootPart: BasePart)
	local standingHeight = resolveStandingHeight(bossHumanoid, bossRootPart)
	local rootWidth = bossRootPart.Size.X
	local hitboxHeight = math.clamp(standingHeight * 0.18, 2.5, 4.5)
	local arenaEndRadius = resolveArenaEndRadius()
	if arenaEndRadius == nil then
		warn("[FireBurst] Missing Workspace.ActiveBossArena, falling back to boss-scaled shockwave radius.")
	end

	return {
		startRadius = math.clamp(rootWidth * 0.9, 4, 8),
		endRadius = arenaEndRadius or math.clamp(rootWidth * 5.5, 20, 34),
		ringThickness = math.clamp(rootWidth * 0.8, 3.5, 6),
		hitboxHeight = hitboxHeight,
		visualTemplatePath = VISUAL_TEMPLATE_PATH,
		standingHeight = standingHeight,
	}
end

local function applyLightPop(targetRootPart: BasePart?, bossRootPart: BasePart)
	if targetRootPart == nil or targetRootPart.Parent == nil then
		return
	end

	local offset = targetRootPart.Position - bossRootPart.Position
	local planarOffset = Vector3.new(offset.X, 0, offset.Z)
	local awayDirection = planarOffset.Magnitude > 0.001 and planarOffset.Unit
		or Vector3.new(bossRootPart.CFrame.LookVector.X, 0, bossRootPart.CFrame.LookVector.Z).Unit
	local popVelocity = (awayDirection * POP_HORIZONTAL_SPEED) + Vector3.new(0, POP_VERTICAL_SPEED, 0)

	targetRootPart.AssemblyLinearVelocity = targetRootPart.AssemblyLinearVelocity + popVelocity
end

local function buildImpactPresentationPayload(context, bossRootPart: BasePart, shockwaveData): { [string]: any }
	return {
		impactPosition = bossRootPart.Position - Vector3.new(0, shockwaveData.standingHeight, 0),
		startRadius = shockwaveData.startRadius,
		endRadius = shockwaveData.endRadius,
		ringThickness = shockwaveData.ringThickness,
		durationSeconds = SHOCKWAVE_DURATION_SECONDS,
		scaleMultiplier = context.bossDefinition.scaleMultiplier,
	}
end

function FireBurst.GetSelectionWeight(context)
	local distance = tonumber(context.distanceToTarget)
	if distance == nil then
		return 1
	end

	return getWeightedValue(distance, {
		{ distance = 0, weight = 0.2 },
		{ distance = 12, weight = 0.55 },
		{ distance = 24, weight = 1.35 },
		{ distance = 38, weight = 1.1 },
		{ distance = 56, weight = 0.5 },
		{ distance = 84, weight = 0.15 },
	})
end

function FireBurst.StartCast(context)
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
			"[FireBurst] Missing animation at ReplicatedStorage.GameAssets.Animations.FlameGuardGeneral.FlameBurst."
		)
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[FireBurst] Failed to create animation profile:", profileOrError)
		return nil
	end

	local profile = profileOrError
	local activeHitbox = nil
	local impactTriggered = false
	local warnedMissingImpact = false
	local completed = false
	local cancelled = false
	local cleanedUp = false
	local hitTargets = {}
	local stoppedConnection = nil
	local shockwaveData = resolveShockwaveData(bossHumanoid, bossRootPart)
	local stoppedPresentation = false

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
		warn("[FireBurst] Animation completed without firing the 'Impact' marker.")
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
		emitPresentation("impact", buildImpactPresentationPayload(context, bossRootPart, shockwaveData))
		destroyHitbox()

		local hitbox
		hitbox = Hitbox.new({
			Character = bossModel,
			HitboxCFrame = function()
				if bossRootPart.Parent == nil then
					return nil
				end
				return bossRootPart.CFrame
			end,
			HitboxType = "GroundShockwave",
			StartRadius = shockwaveData.startRadius,
			EndRadius = shockwaveData.endRadius,
			RingThickness = shockwaveData.ringThickness,
			HitboxHeight = shockwaveData.hitboxHeight,
			VisualTemplatePath = shockwaveData.visualTemplatePath,
			GroundOffset = GROUND_OFFSET,
			Time = SHOCKWAVE_DURATION_SECONDS + SHOCKWAVE_LIFETIME_EPSILON_SECONDS,
			MaxParts = 256,
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
				humanoid:TakeDamage(DAMAGE)

				local targetRootPart = resolveRootPart(targetModel)
				applyLightPop(targetRootPart, bossRootPart)
			end,
			HitboxDestroy = function()
				if activeHitbox == hitbox then
					activeHitbox = nil
				end
			end,
		})

		activeHitbox = hitbox
		hitbox:Visible(true)
	end

	local track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, {
		Impact = handleImpact,
		End = markComplete,
	}, ANIMATION_FADE_SECONDS)
	if track == nil then
		warn("[FireBurst] Failed to play FlameBurst animation.")
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
			cleanup(true)
		end,
		IsComplete = function()
			return completed
		end,
	}
end

return table.freeze(FireBurst)
