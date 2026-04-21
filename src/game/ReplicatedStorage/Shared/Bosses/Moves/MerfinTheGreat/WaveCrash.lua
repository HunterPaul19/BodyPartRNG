local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local Knockback = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Knockback)

local DAMAGE = 20
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "MerfinTheGreat"
local ANIMATION_NAME = "WaveCrash"
local SEND_MARKER_NAME = "Send"
local VFX_FOLDER_NAME = "VFX"
local MERFIN_VFX_FOLDER_NAME = "MerfinTheGreat"
local WAVE_CRASH_VFX_FOLDER_NAME = "WaveCrash"
local WAVE_MODEL_NAME = "Wave"
local WAVE_TRAVEL_SPEED_STUDS_PER_SECOND = 100
local WAVE_LIFETIME_SECONDS = 7
local FLOOR_RAYCAST_START_HEIGHT = 5
local FLOOR_RAYCAST_DISTANCE = 240

local stub = CreateExplicitBossMoveStub({
	bossId = "Merfin the Great",
	moveLabel = "Wave Crash",
	targetMode = "wide_area",
	summaryTemplate = "{moveLabel} surges through {target}'s path",
	description = "Merfin the Great creates a giant wave of water that travels forward and deals damage to players hit.",
})

local WaveCrash = {
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

	local merfinFolder = animations:FindFirstChild(ANIMATION_FOLDER_NAME)
	if not (merfinFolder and merfinFolder:IsA("Folder")) then
		return nil
	end

	local animationInstance = merfinFolder:FindFirstChild(ANIMATION_NAME)
	if animationInstance and animationInstance:IsA("Animation") then
		return animationInstance
	end

	return nil
end

local function resolveWaveSourceModel(): Model?
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	if not (gameAssets and gameAssets:IsA("Folder")) then
		return nil
	end

	local vfxFolder = gameAssets:FindFirstChild(VFX_FOLDER_NAME)
	if not (vfxFolder and vfxFolder:IsA("Folder")) then
		return nil
	end

	local merfinFolder = vfxFolder:FindFirstChild(MERFIN_VFX_FOLDER_NAME)
	if not (merfinFolder and merfinFolder:IsA("Folder")) then
		return nil
	end

	local waveCrashFolder = merfinFolder:FindFirstChild(WAVE_CRASH_VFX_FOLDER_NAME)
	if not (waveCrashFolder and waveCrashFolder:IsA("Folder")) then
		return nil
	end

	local waveModel = waveCrashFolder:FindFirstChild(WAVE_MODEL_NAME)
	if waveModel and waveModel:IsA("Model") then
		return waveModel
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

local function resolvePlanarForwardDirection(bossRootPart: BasePart): Vector3
	local direction = Vector3.new(bossRootPart.CFrame.LookVector.X, 0, bossRootPart.CFrame.LookVector.Z)
	if direction.Magnitude <= 0.001 then
		return Vector3.new(0, 0, -1)
	end

	return direction.Unit
end

local function resolveWaveModelMetrics(scaleMultiplier: number): (Vector3?, CFrame?, number?)
	local waveSource = resolveWaveSourceModel()
	if waveSource == nil then
		warn(
			"[WaveCrash] Missing wave VFX model at ReplicatedStorage.GameAssets.VFX.MerfinTheGreat.WaveCrash.Wave."
		)
		return nil, nil
	end

	local waveModel = waveSource:Clone()
	local scaleOk, scaleError = pcall(function()
		waveModel:ScaleTo(scaleMultiplier)
	end)
	if not scaleOk then
		waveModel:Destroy()
		warn("[WaveCrash] Failed to scale wave VFX model:", scaleError)
		return nil, nil
	end

	if resolveModelBasePart(waveModel) == nil then
		waveModel:Destroy()
		warn("[WaveCrash] Wave VFX model is missing a BasePart for hitbox sizing.")
		return nil, nil, nil
	end

	local primaryPart = waveModel.PrimaryPart or waveModel:FindFirstChildWhichIsA("BasePart", true)
	local pivotCFrame = waveModel:GetPivot()
	local boundingCFrame, boundingSize = waveModel:GetBoundingBox()
	local boundingOffset = pivotCFrame:ToObjectSpace(boundingCFrame)
	local primaryPartOffset = pivotCFrame:ToObjectSpace(primaryPart.CFrame)
	local primaryBottomOffset = primaryPartOffset.Position.Y - (primaryPart.Size.Y * 0.5)
	waveModel:Destroy()

	return boundingSize, boundingOffset, primaryBottomOffset
end

local function resolveFloorY(bossModel: Model, bossRootPart: BasePart): number?
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

local function buildWaveFacingCFrame(position: Vector3, planarDirection: Vector3): CFrame
	local rightVector = planarDirection
	local upVector = Vector3.yAxis
	local backVector = -rightVector:Cross(upVector)
	if backVector.Magnitude <= 0.001 then
		backVector = Vector3.zAxis
	else
		backVector = backVector.Unit
	end

	return CFrame.fromMatrix(position, rightVector, upVector, backVector)
end

local function buildGroundedWaveStartCFrame(
	bossModel: Model,
	bossRootPart: BasePart,
	planarDirection: Vector3,
	primaryBottomOffset: number
): CFrame
	local floorY = resolveFloorY(bossModel, bossRootPart) or bossRootPart.Position.Y
	local startPosition = Vector3.new(
		bossRootPart.Position.X,
		floorY - primaryBottomOffset,
		bossRootPart.Position.Z
	)

	return buildWaveFacingCFrame(startPosition, planarDirection)
end

local function buildWaveCFrame(startCFrame: CFrame, planarDirection: Vector3, elapsedSeconds: number): CFrame
	local currentPosition = startCFrame.Position + (planarDirection * (WAVE_TRAVEL_SPEED_STUDS_PER_SECOND * elapsedSeconds))
	return CFrame.new(currentPosition) * (startCFrame - startCFrame.Position)
end

local function buildKnockbackDirection(planarDirection: Vector3, wavePosition: Vector3, targetRootPart: BasePart?): Vector3
	local sideDirection = planarDirection:Cross(Vector3.yAxis)
	if sideDirection.Magnitude <= 0.001 then
		sideDirection = Vector3.xAxis
	else
		sideDirection = sideDirection.Unit
	end

	if targetRootPart ~= nil and targetRootPart.Parent ~= nil then
		local offset = targetRootPart.Position - wavePosition
		if offset:Dot(sideDirection) < 0 then
			sideDirection = -sideDirection
		end
	end

	return (planarDirection * 42) + (sideDirection * 24) + Vector3.new(0, 12, 0)
end

function WaveCrash.GetSelectionWeight(_context)
	return 1
end

function WaveCrash.StartCast(context)
	local bossModel = context.bossModel
	local bossRootPart = context.bossRootPart
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return nil
	end

	local animationInstance = resolveAnimationInstance()
	if animationInstance == nil then
		warn("[WaveCrash] Missing animation at ReplicatedStorage.GameAssets.Animations.MerfinTheGreat.WaveCrash.")
		return nil
	end

	local waveSize, waveBoundingOffset, primaryBottomOffset = resolveWaveModelMetrics(context.bossDefinition.scaleMultiplier)
	if waveSize == nil or waveBoundingOffset == nil or primaryBottomOffset == nil then
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[WaveCrash] Failed to create animation profile:", profileOrError)
		return nil
	end

	local profile = profileOrError
	local track = nil :: AnimationTrack?
	local stoppedConnection = nil :: RBXScriptConnection?
	local activeHitbox = nil
	local hitTargets = {}
	local sendTriggered = false
	local warnedMissingSend = false
	local completed = false
	local cancelled = false
	local cleanedUp = false
	local stoppedPresentation = false
	local recoveryEndsAt = nil :: number?

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

	local function warnMissingSend()
		if warnedMissingSend or cancelled then
			return
		end

		warnedMissingSend = true
		warn(string.format(
			"[WaveCrash] Animation '%s' completed without firing the '%s' marker.",
			animationInstance.Name,
			SEND_MARKER_NAME
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

		if stopAnimation and track then
			profile:StopAnimation(animationInstance, ANIMATION_FADE_SECONDS)
		end
	end

	local function handleSend()
		if cancelled or sendTriggered or bossModel.Parent == nil or bossRootPart.Parent == nil then
			return
		end

		sendTriggered = true
		destroyHitbox()

		local planarDirection = resolvePlanarForwardDirection(bossRootPart)
		local startCFrame = buildGroundedWaveStartCFrame(bossModel, bossRootPart, planarDirection, primaryBottomOffset)
		local startedAt = os.clock()
		context.EmitPresentation("send", {
			startCFrame = startCFrame,
			direction = planarDirection,
			speed = WAVE_TRAVEL_SPEED_STUDS_PER_SECOND,
			durationSeconds = WAVE_LIFETIME_SECONDS,
			scaleMultiplier = context.bossDefinition.scaleMultiplier,
		})

		local hitbox
		hitbox = Hitbox.new({
			Character = bossModel,
			HitboxCFrame = function()
				if cancelled or bossModel.Parent == nil then
					return nil
				end

				local elapsed = math.clamp(os.clock() - startedAt, 0, WAVE_LIFETIME_SECONDS)
				return buildWaveCFrame(startCFrame, planarDirection, elapsed) * waveBoundingOffset
			end,
			HitboxSize = waveSize,
			HitboxType = "SpacialQuery",
			Time = WAVE_LIFETIME_SECONDS,
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

				local elapsed = math.clamp(os.clock() - startedAt, 0, WAVE_LIFETIME_SECONDS)
				local wavePosition = buildWaveCFrame(startCFrame, planarDirection, elapsed).Position
				Knockback(targetModel, "Default", {
					Direction = buildKnockbackDirection(planarDirection, wavePosition, resolveRootPart(targetModel)),
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

				if not cancelled then
					markComplete()
				end
			end,
		})

		activeHitbox = hitbox
	end

	track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, {
		[SEND_MARKER_NAME] = handleSend,
	}, ANIMATION_FADE_SECONDS)
	if track == nil then
		warn("[WaveCrash] Failed to play WaveCrash animation.")
		return nil
	end

	context.EmitPresentation("start", {
		scaleMultiplier = context.bossDefinition.scaleMultiplier,
	})
	track.Looped = false
	stoppedConnection = track.Stopped:Connect(function()
		disconnectStoppedConnection()
		if not sendTriggered then
			warnMissingSend()
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

return table.freeze(WaveCrash)
