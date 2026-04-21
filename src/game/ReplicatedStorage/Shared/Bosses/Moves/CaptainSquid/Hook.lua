local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local Knockback = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Knockback)
local CharacterPhysicsContext = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Utilities.CharacterPhysicsContext)

local HOOK_RANGE_STUDS = 100
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "CaptainSquid"
local GRAB_ANIMATION_NAME = "Grab"
local THROW_ANIMATION_NAME = "GrabThrow"
local THROW_MARKER_NAME = "Throw"
local HAND_PART_NAME = "LeftHand"
local THROW_DISTANCE_STUDS = 150
local THROW_DURATION_SECONDS = 1.05
local THROW_RAGDOLL_SECONDS = 6.0
local THROW_UPWARD_FORCE = 60
local THROW_LANDED_RAGDOLL_DELAY = 6.0

local stub = CreateExplicitBossMoveStub({
	bossId = "Captain Squid",
	moveLabel = "Hook",
	targetMode = "single",
	summaryTemplate = "{moveLabel} snags {target} and hurls them away",
	description = "Captain Squid grabs a player with his hook and throws them away.",
})

local Hook = {
	ExecuteStub = stub.ExecuteStub,
	GetTargeting = stub.GetTargeting,
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

local function resolveAnimationInstance(animationName: string): Animation?
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

	local animationInstance = captainSquidFolder:FindFirstChild(animationName)
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

local function resolveHandPart(bossModel: Model?): BasePart?
	if bossModel == nil then
		return nil
	end

	local handPart = bossModel:FindFirstChild(HAND_PART_NAME, true)
	if handPart and handPart:IsA("BasePart") then
		return handPart
	end

	return nil
end

local function buildFlatLookDirection(rootPart: BasePart): Vector3
	local flatDirection = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
	if flatDirection.Magnitude <= 0.001 then
		return Vector3.new(0, 0, -1)
	end

	return flatDirection.Unit
end

local function buildThrowVelocity(bossRootPart: BasePart): Vector3
	local planarDirection = buildFlatLookDirection(bossRootPart)
	local planarVelocity = THROW_DISTANCE_STUDS / THROW_DURATION_SECONDS
	return (planarDirection * planarVelocity) + Vector3.new(0, THROW_UPWARD_FORCE, 0)
end

local function setAssemblyVelocities(model: Model, linearVelocity: Vector3, angularVelocity: Vector3)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = linearVelocity
			descendant.AssemblyAngularVelocity = angularVelocity
		end
	end
end

local function resolveNearestTarget(bossRootPart: BasePart, maxDistance: number)
	local nearestTarget = nil

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = resolveHumanoid(character)
		if character == nil or humanoid == nil or humanoid.Health <= 0 then
			continue
		end

		local rootPart = resolveRootPart(character)
		if rootPart == nil then
			continue
		end

		local distance = (rootPart.Position - bossRootPart.Position).Magnitude
		if distance > maxDistance then
			continue
		end

		if nearestTarget == nil or distance < nearestTarget.distance then
			nearestTarget = {
				player = player,
				character = character,
				humanoid = humanoid,
				rootPart = rootPart,
				distance = distance,
			}
		end
	end

	return nearestTarget
end

local function attachTargetToHand(handPart: BasePart, targetData): { [string]: any }?
	local character = targetData.character
	local humanoid = targetData.humanoid
	local rootPart = targetData.rootPart
	if character == nil or humanoid == nil or rootPart == nil then
		return nil
	end
	if character.Parent == nil or humanoid.Health <= 0 or handPart.Parent == nil then
		return nil
	end

	local physicsContext = CharacterPhysicsContext.fromCharacter(character)
	if physicsContext then
		physicsContext:clearBodymovers()
		physicsContext:setNetworkOwner(nil)
	end

	setAssemblyVelocities(character, Vector3.zero, Vector3.zero)

	local holdOffset = CFrame.new(
		0,
		-(rootPart.Size.Y * 0.55),
		-((handPart.Size.Z * 0.9) + (rootPart.Size.Z * 0.65))
	) * CFrame.Angles(0, math.rad(180), 0)

	character:PivotTo(handPart.CFrame * holdOffset)
	setAssemblyVelocities(character, Vector3.zero, Vector3.zero)

	local weld = Instance.new("Weld")
	weld.Name = "CaptainSquidHookWeld"
	weld.Part0 = handPart
	weld.Part1 = rootPart
	weld.C0 = handPart.CFrame:ToObjectSpace(rootPart.CFrame)
	weld.C1 = CFrame.new()
	weld.Parent = handPart

	local originalUseJumpPower = humanoid.UseJumpPower
	local originalWalkSpeed = humanoid.WalkSpeed
	local originalJumpPower = humanoid.JumpPower
	local originalJumpHeight = humanoid.JumpHeight
	local originalAutoRotate = humanoid.AutoRotate
	local originalPlatformStand = humanoid.PlatformStand

	humanoid.AutoRotate = false
	humanoid.PlatformStand = false
	humanoid.WalkSpeed = 0
	if originalUseJumpPower then
		humanoid.JumpPower = 0
	else
		humanoid.JumpHeight = 0
	end

	return {
		player = targetData.player,
		character = character,
		humanoid = humanoid,
		rootPart = rootPart,
		physicsContext = physicsContext,
		weld = weld,
		restoreMovement = function()
			if humanoid.Parent == nil then
				return
			end

			humanoid.AutoRotate = originalAutoRotate
			humanoid.PlatformStand = originalPlatformStand
			humanoid.WalkSpeed = originalWalkSpeed
			if originalUseJumpPower then
				humanoid.JumpPower = originalJumpPower
			else
				humanoid.JumpHeight = originalJumpHeight
			end
		end,
	}
end

local function releaseTarget(captiveState, restoreNetworkOwner: boolean)
	if captiveState == nil then
		return nil
	end

	local player = captiveState.player
	local character = captiveState.character
	local rootPart = captiveState.rootPart
	local physicsContext = captiveState.physicsContext

	if captiveState.weld and captiveState.weld.Parent ~= nil then
		captiveState.weld:Destroy()
	end

	if typeof(captiveState.restoreMovement) == "function" then
		captiveState.restoreMovement()
	end

	if character and character.Parent ~= nil then
		setAssemblyVelocities(character, Vector3.zero, Vector3.zero)
	end

	if restoreNetworkOwner and physicsContext and rootPart and rootPart.Parent ~= nil then
		physicsContext:setNetworkOwner(player)
	end

	return {
		player = player,
		character = character,
		rootPart = rootPart,
	}
end

function Hook.CanUse(context)
	if stub.CanUse(context) ~= true then
		return false, "No focus target"
	end

	local distance = tonumber(context.distanceToTarget)
	if distance == nil or distance > HOOK_RANGE_STUDS then
		return false, "Target out of hook range"
	end

	return true
end

function Hook.GetSelectionWeight(context)
	local distance = tonumber(context.distanceToTarget)
	if distance == nil or distance > HOOK_RANGE_STUDS then
		return 0
	end

	return getWeightedValue(distance, {
		{ distance = 0, weight = 0.2 },
		{ distance = 12, weight = 0.28 },
		{ distance = 28, weight = 0.38 },
		{ distance = 45, weight = 0.55 },
		{ distance = 65, weight = 0.48 },
		{ distance = 85, weight = 0.36 },
		{ distance = 100, weight = 0.24 },
	})
end

function Hook.StartCast(context)
	local bossModel = context.bossModel
	local bossRootPart = context.bossRootPart
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return nil
	end

	local handPart = resolveHandPart(bossModel)
	if handPart == nil then
		warn("[Hook] Missing LeftHand on Captain Squid boss model.")
		return nil
	end

	local grabAnimation = resolveAnimationInstance(GRAB_ANIMATION_NAME)
	local throwAnimation = resolveAnimationInstance(THROW_ANIMATION_NAME)
	if grabAnimation == nil or throwAnimation == nil then
		warn("[Hook] Missing Captain Squid hook animations in ReplicatedStorage.GameAssets.Animations.CaptainSquid.")
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[Hook] Failed to create animation profile:", profileOrError)
		return nil
	end

	local profile = profileOrError
	local completed = false
	local cancelled = false
	local cleanedUp = false
	local warnedMissingThrowMarker = false
	local stoppedConnection = nil
	local activePhase = "Grab"
	local recoveryEndsAt = nil :: number?
	local captiveState = nil
	local throwTriggered = false

	local function disconnectStoppedConnection()
		if stoppedConnection and stoppedConnection.Connected then
			stoppedConnection:Disconnect()
		end
		stoppedConnection = nil
	end

	local function releaseCaptiveAndClear(restoreNetworkOwner: boolean)
		local releasedTarget = releaseTarget(captiveState, restoreNetworkOwner)
		captiveState = nil
		return releasedTarget
	end

	local function markComplete()
		if completed then
			return
		end

		completed = true
		recoveryEndsAt = os.clock() + (tonumber(context.move and context.move.recoverySeconds) or 0)
	end

	local function cleanup(stopAnimation: boolean, restoreNetworkOwner: boolean)
		if cleanedUp then
			return
		end

		cleanedUp = true
		disconnectStoppedConnection()
		releaseCaptiveAndClear(restoreNetworkOwner)

		if stopAnimation then
			profile:StopAnimation(grabAnimation, ANIMATION_FADE_SECONDS)
			profile:StopAnimation(throwAnimation, ANIMATION_FADE_SECONDS)
		end
	end

	local function handleThrow()
		if cancelled or throwTriggered or bossModel.Parent == nil or bossRootPart.Parent == nil then
			return
		end

		throwTriggered = true
		local releasedTarget = releaseCaptiveAndClear(false)
		if releasedTarget == nil then
			return
		end
		if releasedTarget.character == nil or releasedTarget.character.Parent == nil then
			return
		end

		Knockback(releasedTarget.character, "Default", {
			Direction = buildThrowVelocity(bossRootPart),
			Duration = THROW_DURATION_SECONDS,
			RagdollDuration = THROW_RAGDOLL_SECONDS,
			Landed = {
				DisableRagdollDelay = THROW_LANDED_RAGDOLL_DELAY,
			},
			GroundMode = "DeterministicMap",
		})
	end

	local function playThrowAnimation()
		if cancelled or bossModel.Parent == nil then
			return
		end

		activePhase = "GrabThrow"
		local track = profile:PlayAnimation(throwAnimation, Enum.AnimationPriority.Action, 1, {
			[THROW_MARKER_NAME] = handleThrow,
		}, ANIMATION_FADE_SECONDS)
		if track == nil then
			warn("[Hook] Failed to play Captain Squid GrabThrow animation.")
			markComplete()
			cleanup(false, true)
			return
		end

		track.Looped = false
		disconnectStoppedConnection()
		stoppedConnection = track.Stopped:Connect(function()
			disconnectStoppedConnection()
			if not throwTriggered and not warnedMissingThrowMarker then
				warnedMissingThrowMarker = true
				warn("[Hook] GrabThrow animation completed without firing the 'Throw' marker.")
			end

			if captiveState ~= nil then
				releaseCaptiveAndClear(true)
			end

			markComplete()
		end)
	end

	local function handleGrabFinished()
		if cancelled or bossModel.Parent == nil or handPart.Parent == nil then
			return
		end

		local nearestTarget = resolveNearestTarget(bossRootPart, HOOK_RANGE_STUDS)
		if nearestTarget == nil then
			markComplete()
			return
		end

		captiveState = attachTargetToHand(handPart, nearestTarget)
		if captiveState == nil then
			markComplete()
			return
		end

		playThrowAnimation()
	end

	local track = profile:PlayAnimation(grabAnimation, Enum.AnimationPriority.Action, 1, nil, ANIMATION_FADE_SECONDS)
	if track == nil then
		warn("[Hook] Failed to play Captain Squid Grab animation.")
		return nil
	end

	track.Looped = false
	stoppedConnection = track.Stopped:Connect(function()
		disconnectStoppedConnection()
		if cancelled then
			return
		end
		if activePhase == "Grab" then
			handleGrabFinished()
			return
		end
		if activePhase == "GrabThrow" then
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
			cleanup(true, true)
		end,
		IsComplete = function()
			return completed
		end,
		GetRecoveryEndsAt = function()
			return recoveryEndsAt
		end,
	}
end

return table.freeze(Hook)
