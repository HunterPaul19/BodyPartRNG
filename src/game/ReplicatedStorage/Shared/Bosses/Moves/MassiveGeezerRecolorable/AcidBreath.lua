local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)

local DAMAGE = 20
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "MassiveGeezer"
local ANIMATION_NAME = "AcidBreath"
local SHOOT_MARKER_NAME = "Shoot"
local CONE_DISTANCE_STUDS = 125
local CONE_WIDTH_STUDS = 85
local CONE_LAYERS = 16
local CONE_DURATION_SECONDS = 0.5
local POISON_SCREEN_DURATION_SECONDS = 2.5

local stub = CreateExplicitBossMoveStub({
	bossId = "Massive Geezer RECOLORABLE",
	moveLabel = "Acid Breath",
	targetMode = "single",
	summaryTemplate = "{moveLabel} drenches {target}'s lane in acid",
	description = "Massive Geezer RECOLORABLE spews acid at a targeted player and leaves a puddle of acid on the ground.",
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

	local animations = gameAssets:FindFirstChild("Animations")
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

function AcidBreath.StartCast(context)
	local bossModel = context.bossModel
	local bossRootPart = context.bossRootPart
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return nil
	end

	local bossHead = resolveHeadPart(bossModel)
	if bossHead == nil or bossHead.Parent == nil then
		warn("[AcidBreath] Could not resolve boss Head for Acid Breath.")
		return nil
	end

	local animationInstance = resolveAnimationInstance()
	if animationInstance == nil then
		warn("[AcidBreath] Missing animation at ReplicatedStorage.GameAssets.Animations.MassiveGeezer.AcidBreath.")
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[AcidBreath] Failed to create animation profile:", profileOrError)
		return nil
	end

	faceBossTowardTarget(bossModel, bossRootPart, context.targetRootPart)

	local profile = profileOrError
	local activeHitbox = nil
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
		warn(string.format(
			"[AcidBreath] Animation '%s' completed without firing the '%s' marker.",
			animationInstance.Name,
			SHOOT_MARKER_NAME
		))
	end

	local function getConeCFrame(): CFrame?
		if cancelled or bossHead.Parent == nil or bossRootPart.Parent == nil then
			return nil
		end

		local direction = resolvePlanarDirection(bossHead.Position, context.targetRootPart, bossRootPart)
		return CFrame.lookAt(bossHead.Position, bossHead.Position + direction)
	end

	local function handleShoot()
		if cancelled or shootTriggered or bossModel.Parent == nil or bossHead.Parent == nil then
			return
		end

		shootTriggered = true
		context.EmitPresentation("shoot", {
			scaleMultiplier = context.bossDefinition.scaleMultiplier,
		})
		destroyHitbox()

		local hitbox
		hitbox = Hitbox.new({
			Character = bossModel,
			HitboxCFrame = getConeCFrame,
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
				humanoid:TakeDamage(DAMAGE)
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
		hitbox:Visible(true)
	end

	local track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, {
		[SHOOT_MARKER_NAME] = handleShoot,
	}, ANIMATION_FADE_SECONDS)
	if track == nil then
		warn("[AcidBreath] Failed to play AcidBreath animation.")
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
