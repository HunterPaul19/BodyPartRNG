local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local CombatMoveUtil = require(ReplicatedStorage.Shared.Combat.CombatMoveUtil)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local Knockback = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Knockback)

local DAMAGE = 130
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "OinanThickhoof"
local ANIMATION_NAME = "Charge"
local CHARGE_MARKER_NAME = "Charge"
local CHARGE_DISTANCE_STUDS = 100
local CHARGE_SPEED_STUDS_PER_SECOND = 100
local CHARGE_DURATION_SECONDS = CHARGE_DISTANCE_STUDS / CHARGE_SPEED_STUDS_PER_SECOND
local HITBOX_WIDTH_ROOT_SCALE = 2.0
local HITBOX_HEIGHT_STANDING_SCALE = 2.25
local HITBOX_DEPTH_ROOT_SCALE = 4.0
local MIN_HITBOX_DEPTH_STUDS = 18
local SIDE_KNOCKBACK_SPEED = 48
local UPWARD_KNOCKBACK_SPEED = 12

local stub = CreateExplicitBossMoveStub({
	bossId = "Oinan Thickhoof",
	moveLabel = "Bull Charge",
	targetMode = "single",
	summaryTemplate = "{moveLabel} tears through {target}'s line",
	description = "Oinan Thickhoof charges forward, dealing damage and knocking players sideways.",
})

local BullCharge = {
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

local function resolveAnimationInstance(): Animation?
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	if not (gameAssets and gameAssets:IsA("Folder")) then
		return nil
	end

	local animations = gameAssets:FindFirstChild("Animations")
	if not (animations and animations:IsA("Folder")) then
		return nil
	end

	local oinanFolder = animations:FindFirstChild(ANIMATION_FOLDER_NAME)
	if not (oinanFolder and oinanFolder:IsA("Folder")) then
		return nil
	end

	local animationInstance = oinanFolder:FindFirstChild(ANIMATION_NAME)
	if animationInstance and animationInstance:IsA("Animation") then
		return animationInstance
	end

	return nil
end

local function resolvePlanarForwardDirection(bossRootPart: BasePart): Vector3
	local direction = Vector3.new(bossRootPart.CFrame.LookVector.X, 0, bossRootPart.CFrame.LookVector.Z)
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

local function resolveHitboxSizeAndOffset(bossModel: Model, bossHumanoid: Humanoid?, bossRootPart: BasePart): (Vector3, number)
	local _, boundingSize = bossModel:GetBoundingBox()
	local rootSize = bossRootPart.Size
	local bossWidth = math.max(rootSize.X * HITBOX_WIDTH_ROOT_SCALE, math.min(boundingSize.X, boundingSize.Z))
	local standingHeight = resolveStandingHeight(bossHumanoid, bossRootPart)
	local hitboxHeight = math.max(standingHeight * HITBOX_HEIGHT_STANDING_SCALE, rootSize.Y * 3)
	local hitboxDepth = math.max(rootSize.Z * HITBOX_DEPTH_ROOT_SCALE, MIN_HITBOX_DEPTH_STUDS)

	return Vector3.new(bossWidth, hitboxHeight, hitboxDepth), (rootSize.Z * 0.5) + (hitboxDepth * 0.5)
end

local function setAssemblyVelocities(model: Model, linearVelocity: Vector3, angularVelocity: Vector3)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = linearVelocity
			descendant.AssemblyAngularVelocity = angularVelocity
		end
	end
end

local function buildChargeCFrame(startCFrame: CFrame, direction: Vector3, elapsedSeconds: number): CFrame
	local alpha = math.clamp(elapsedSeconds / CHARGE_DURATION_SECONDS, 0, 1)
	local position = startCFrame.Position + (direction * (CHARGE_DISTANCE_STUDS * alpha))
	return CFrame.new(position) * (startCFrame - startCFrame.Position)
end

local function buildSideKnockbackDirection(direction: Vector3, chargeStartPosition: Vector3, targetRootPart: BasePart?): Vector3
	local sideDirection = direction:Cross(Vector3.yAxis)
	if sideDirection.Magnitude <= 0.001 then
		sideDirection = Vector3.xAxis
	else
		sideDirection = sideDirection.Unit
	end

	if targetRootPart ~= nil and targetRootPart.Parent ~= nil then
		local offset = targetRootPart.Position - chargeStartPosition
		if offset:Dot(sideDirection) < 0 then
			sideDirection = -sideDirection
		end
	end

	return (sideDirection * SIDE_KNOCKBACK_SPEED) + Vector3.new(0, UPWARD_KNOCKBACK_SPEED, 0)
end

function BullCharge.GetSelectionWeight(_context)
	return 1
end

function BullCharge.StartCast(context)
	local bossModel = context.bossModel
	local bossHumanoid = context.bossHumanoid
	local bossRootPart = context.bossRootPart
	if bossModel == nil
		or bossModel.Parent == nil
		or bossHumanoid == nil
		or bossHumanoid.Parent == nil
		or bossRootPart == nil
		or bossRootPart.Parent == nil then
		return nil
	end

	local animationInstance = resolveAnimationInstance()
	if animationInstance == nil then
		warn("[BullCharge] Missing animation at ReplicatedStorage.GameAssets.Animations.OinanThickhoof.Charge.")
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[BullCharge] Failed to create animation profile:", profileOrError)
		return nil
	end

	local profile = profileOrError
	local track = nil :: AnimationTrack?
	local stoppedConnection = nil :: RBXScriptConnection?
	local chargeHeartbeat = nil :: RBXScriptConnection?
	local activeHitbox = nil
	local hitTargets = {}
	local chargeTriggered = false
	local warnedMissingCharge = false
	local completed = false
	local cancelled = false
	local cleanedUp = false
	local stoppedPresentation = false
	local recoveryEndsAt = nil :: number?
	local chargeStartedAt = 0
	local chargeStartCFrame = nil :: CFrame?
	local chargeDirection = nil :: Vector3?
	local hitboxSize, hitboxForwardOffset = resolveHitboxSizeAndOffset(bossModel, bossHumanoid, bossRootPart)

	local function disconnectStoppedConnection()
		if stoppedConnection and stoppedConnection.Connected then
			stoppedConnection:Disconnect()
		end
		stoppedConnection = nil
	end

	local function disconnectChargeHeartbeat()
		if chargeHeartbeat and chargeHeartbeat.Connected then
			chargeHeartbeat:Disconnect()
		end
		chargeHeartbeat = nil
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
		recoveryEndsAt = os.clock() + (tonumber(context.move and context.move.recoverySeconds) or 0)
		stopPresentation()
		disconnectChargeHeartbeat()
		destroyHitbox()
		setAssemblyVelocities(bossModel, Vector3.zero, Vector3.zero)
	end

	local function warnMissingCharge()
		if warnedMissingCharge or cancelled then
			return
		end

		warnedMissingCharge = true
		warn(string.format(
			"[BullCharge] Animation '%s' completed without firing the '%s' marker.",
			animationInstance.Name,
			CHARGE_MARKER_NAME
		))
	end

	local function cleanup(stopAnimation: boolean)
		if cleanedUp then
			return
		end

		cleanedUp = true
		stopPresentation()
		disconnectStoppedConnection()
		disconnectChargeHeartbeat()
		destroyHitbox()
		setAssemblyVelocities(bossModel, Vector3.zero, Vector3.zero)

		if stopAnimation and track then
			profile:StopAnimation(animationInstance, ANIMATION_FADE_SECONDS)
		end
	end

	local function finishCharge()
		if cancelled then
			return
		end

		if chargeStartCFrame ~= nil and chargeDirection ~= nil and bossModel.Parent ~= nil then
			bossModel:PivotTo(buildChargeCFrame(chargeStartCFrame, chargeDirection, CHARGE_DURATION_SECONDS))
		end

		markComplete()
	end

	local function getChargeHitboxCFrame(): CFrame?
		if cancelled or bossRootPart.Parent == nil or chargeDirection == nil then
			return nil
		end

		return CFrame.lookAt(bossRootPart.Position, bossRootPart.Position + chargeDirection)
	end

	local function startCharge()
		if cancelled or chargeTriggered or bossModel.Parent == nil or bossRootPart.Parent == nil then
			return
		end

		chargeTriggered = true
		chargeStartedAt = os.clock()
		chargeStartCFrame = bossModel:GetPivot()
		chargeDirection = resolvePlanarForwardDirection(bossRootPart)
		setAssemblyVelocities(bossModel, Vector3.zero, Vector3.zero)

		context.EmitPresentation("charge", {
			startCFrame = bossRootPart.CFrame,
			direction = chargeDirection,
			speed = CHARGE_SPEED_STUDS_PER_SECOND,
			durationSeconds = CHARGE_DURATION_SECONDS,
			distanceStuds = CHARGE_DISTANCE_STUDS,
			scaleMultiplier = context.bossDefinition.scaleMultiplier,
		})

		local hitbox
		hitbox = Hitbox.new({
			DebugVisibilityAttribute = "BossHitboxesVisible",
			Character = bossModel,
			HitboxCFrame = getChargeHitboxCFrame,
			HitboxOffset = CFrame.new(0, 0, -hitboxForwardOffset),
			HitboxSize = hitboxSize,
			HitboxType = "SpacialQuery",
			Time = CHARGE_DURATION_SECONDS,
			MaxParts = 128,
		}, {
			HitTarget = function(targetModel: Model)
				if cleanedUp or hitTargets[targetModel] == true or chargeDirection == nil then
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

				Knockback(targetModel, "Default", {
					Direction = buildSideKnockbackDirection(
						chargeDirection,
						if chargeStartCFrame then chargeStartCFrame.Position else bossRootPart.Position,
						resolveRootPart(targetModel)
					),
					Duration = 0.2,
					RagdollDuration = 0.5,
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

		chargeHeartbeat = RunService.Heartbeat:Connect(function()
			if cancelled or bossModel.Parent == nil or bossRootPart.Parent == nil or chargeStartCFrame == nil or chargeDirection == nil then
				finishCharge()
				return
			end

			local elapsed = math.max(0, os.clock() - chargeStartedAt)
			bossModel:PivotTo(buildChargeCFrame(chargeStartCFrame, chargeDirection, elapsed))
			setAssemblyVelocities(bossModel, Vector3.zero, Vector3.zero)

			if elapsed >= CHARGE_DURATION_SECONDS then
				finishCharge()
			end
		end)
	end

	track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, {
		[CHARGE_MARKER_NAME] = startCharge,
	}, ANIMATION_FADE_SECONDS)
	if track == nil then
		warn("[BullCharge] Failed to play Charge animation.")
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

		if not chargeTriggered then
			warnMissingCharge()
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

return table.freeze(BullCharge)
