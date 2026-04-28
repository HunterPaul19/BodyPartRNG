local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssetPaths = require(ReplicatedStorage.Shared.Assets.GameAssetPaths)
local GameAssetResolver = require(ReplicatedStorage.Shared.Assets.GameAssetResolver)
local Workspace = game:GetService("Workspace")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local CombatMoveUtil = require(ReplicatedStorage.Shared.Combat.CombatMoveUtil)
local CombatProjectileUtil = require(ReplicatedStorage.Shared.Combat.CombatProjectileUtil)
local Knockback = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Knockback)
local RaycastUtil = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Utilities.RaycastUtil)
local CharacterPhysicsContext = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Utilities.CharacterPhysicsContext)
local StateUtil = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Utilities.StateUtil)

local GRAB_RANGE_STUDS = 100
local LANDING_DAMAGE = 280
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "BroccoliBro"
local GRAB_ANIMATION_NAME = "Grab"
local THROW_ANIMATION_NAME = "Throw"
local THROW_MARKER_NAME = "Throw"
local HAND_PART_NAME = "LeftHand"
local THROW_DOWNWARD_ANGLE_DEGREES = 45
local THROW_PROXY_SPEED_STUDS_PER_SECOND = 250
local THROW_PROXY_TRACE_DISTANCE_STUDS = 512
local THROW_POST_IMPACT_RAGDOLL_SECONDS = 2
local THROW_FALLBACK_DOWN_TRACE_LIFT = 8
local THROW_FALLBACK_DOWN_TRACE_DEPTH = 320
local IMPACT_FLOOR_TRACE_LIFT = 8
local IMPACT_FLOOR_TRACE_DEPTH = 64
local CANNOT_DASH_STATE_NAME = "CannotDash"

local stub = CreateExplicitBossMoveStub({
	bossId = "Broccoli Bro",
	moveLabel = "Grab",
	targetMode = "single",
	summaryTemplate = "{moveLabel} seizes {target} and spikes them down",
	description = "Broccoli Bro grabs a player and throws them at the ground.",
})

local Grab = {
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

	local animations = GameAssetResolver.FindFirst({ GameAssetPaths.Animations.Bosses, GameAssetPaths.Legacy.Animations })
	if not (animations and animations:IsA("Folder")) then
		return nil
	end

	local broccoliFolder = animations:FindFirstChild(ANIMATION_FOLDER_NAME)
	if not (broccoliFolder and broccoliFolder:IsA("Folder")) then
		return nil
	end

	local animationInstance = broccoliFolder:FindFirstChild(animationName)
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

local function buildThrowDirection(bossRootPart: BasePart): Vector3
	local planarDirection = buildFlatLookDirection(bossRootPart)
	local downwardWeight = math.tan(math.rad(THROW_DOWNWARD_ANGLE_DEGREES))
	return (planarDirection + Vector3.new(0, -downwardWeight, 0)).Unit
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

local function resolveThrowImpactPosition(startPosition: Vector3, throwDirection: Vector3, character: Model, bossModel: Model): Vector3?
	local supportSurface = RaycastUtil.raycastSupportSurface(startPosition, throwDirection * THROW_PROXY_TRACE_DISTANCE_STUDS, {
		character = character,
		extraExclude = { bossModel },
		ignoreWater = true,
		fallbackToMap = false,
	})
	if supportSurface then
		return supportSurface.Position
	end

	local fallbackStart = startPosition + (throwDirection * THROW_PROXY_TRACE_DISTANCE_STUDS)
	local fallbackSurface = RaycastUtil.raycastSupportSurface(
		fallbackStart + Vector3.new(0, THROW_FALLBACK_DOWN_TRACE_LIFT, 0),
		Vector3.new(0, -(THROW_FALLBACK_DOWN_TRACE_DEPTH + THROW_FALLBACK_DOWN_TRACE_LIFT), 0),
		{
			character = character,
			extraExclude = { bossModel },
			ignoreWater = true,
			fallbackToMap = false,
		}
	)
	if fallbackSurface then
		return fallbackSurface.Position
	end

	return nil
end

local function resolveImpactFloorCFrame(impactPosition: Vector3, targetCharacter: Model?): CFrame
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.IgnoreWater = true

	if targetCharacter ~= nil then
		raycastParams.FilterDescendantsInstances = { targetCharacter }
	end

	local floorResult = Workspace:Raycast(
		impactPosition + Vector3.new(0, IMPACT_FLOOR_TRACE_LIFT, 0),
		Vector3.new(0, -(IMPACT_FLOOR_TRACE_LIFT + IMPACT_FLOOR_TRACE_DEPTH), 0),
		raycastParams
	)
	if floorResult then
		return CFrame.new(floorResult.Position)
	end

	return CFrame.new(impactPosition)
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
	weld.Name = "BroccoliBroGrabWeld"
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
	StateUtil.createState(character, CANNOT_DASH_STATE_NAME)

	return {
		player = targetData.player,
		character = character,
		humanoid = humanoid,
		rootPart = rootPart,
		physicsContext = physicsContext,
		weld = weld,
		dashBlockStateCreated = true,
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
	local humanoid = captiveState.humanoid
	local rootPart = captiveState.rootPart
	local physicsContext = captiveState.physicsContext

	if captiveState.weld and captiveState.weld.Parent ~= nil then
		captiveState.weld:Destroy()
	end
	if captiveState.dashBlockStateCreated == true and character and character.Parent ~= nil then
		StateUtil.removeState(character, CANNOT_DASH_STATE_NAME)
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
		humanoid = humanoid,
		rootPart = rootPart,
		physicsContext = physicsContext,
	}
end

function Grab.CanUse(context)
	if stub.CanUse(context) ~= true then
		return false, "No focus target"
	end

	return true
end

function Grab.GetSelectionWeight(context)
	local distance = tonumber(context.distanceToTarget)
	if distance == nil then
		return 1
	end

	return getWeightedValue(distance, {
		{ distance = 0, weight = 1.35 },
		{ distance = 12, weight = 1.6 },
		{ distance = 26, weight = 1.35 },
		{ distance = 44, weight = 0.75 },
		{ distance = 70, weight = 0.25 },
		{ distance = 100, weight = 0.1 },
	})
end

function Grab.StartCast(context)
	local bossModel = context.bossModel
	local bossRootPart = context.bossRootPart
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return nil
	end

	local handPart = resolveHandPart(bossModel)
	if handPart == nil then
		Logger.Warn("[BroccoliGrab] Missing LeftHand on Broccoli Bro boss model.")
		return nil
	end

	local grabAnimation = resolveAnimationInstance(GRAB_ANIMATION_NAME)
	local throwAnimation = resolveAnimationInstance(THROW_ANIMATION_NAME)
	if grabAnimation == nil or throwAnimation == nil then
		Logger.Warn("[BroccoliGrab] Missing Grab/Throw animations in ReplicatedStorage.GameAssets.Animations.Bosses.BroccoliBro.")
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		Logger.Warn("[BroccoliGrab] Failed to create animation profile:", profileOrError)
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
	local landed = false
	local throwState = nil

	local function disconnectStoppedConnection()
		if stoppedConnection and stoppedConnection.Connected then
			stoppedConnection:Disconnect()
		end
		stoppedConnection = nil
	end

	local function cleanupThrowState(options)
		if throwState == nil then
			return nil
		end

		options = type(options) == "table" and options or {}
		local activeThrowState = throwState
		throwState = nil

		if activeThrowState.impactDelayThread then
			task.cancel(activeThrowState.impactDelayThread)
		end

		if options.invalidateKnockback == true
			and activeThrowState.character
			and activeThrowState.character.Parent ~= nil
			and type(activeThrowState.knockbackID) == "string"
			and activeThrowState.character:GetAttribute("KnockbackID") == activeThrowState.knockbackID then
			activeThrowState.character:SetAttribute("KnockbackID", "")
		end

		return activeThrowState
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

	local function cleanup(stopAnimation: boolean)
		if cleanedUp then
			return
		end

		cleanedUp = true
		disconnectStoppedConnection()
		releaseCaptiveAndClear(true)
		cleanupThrowState({
			invalidateKnockback = true,
		})

		if stopAnimation then
			profile:StopAnimation(grabAnimation, ANIMATION_FADE_SECONDS)
			profile:StopAnimation(throwAnimation, ANIMATION_FADE_SECONDS)
		end
	end

	local function handleImpact(activeThrowState)
		if landed then
			return
		end

		landed = true
		local character = activeThrowState.character
		local humanoid = resolveHumanoid(character) or activeThrowState.humanoid
		if character == nil or character.Parent == nil or humanoid == nil or humanoid.Health <= 0 then
			return
		end

		context.EmitPresentation("impact", {
			floorCFrame = resolveImpactFloorCFrame(activeThrowState.impactPosition, activeThrowState.character),
			scaleMultiplier = context.bossDefinition.scaleMultiplier,
			targetCharacter = activeThrowState.character,
			targetUserId = if activeThrowState.player then activeThrowState.player.UserId else nil,
		})

		humanoid:TakeDamage(CombatMoveUtil.ResolveScaledBossDamage(context, LANDING_DAMAGE))
	end

	local function handleThrow()
		if cancelled or throwTriggered or bossModel.Parent == nil or bossRootPart.Parent == nil then
			return
		end

		throwTriggered = true
		local releasedTarget = releaseCaptiveAndClear(true)
		if releasedTarget == nil then
			return
		end
		if releasedTarget.character == nil or releasedTarget.character.Parent == nil then
			return
		end

		local rootPart = resolveRootPart(releasedTarget.character) or releasedTarget.rootPart
		if rootPart == nil then
			markComplete()
			return
		end

		local startPosition = rootPart.Position
		local throwDirection = buildThrowDirection(bossRootPart)
		local impactPosition = resolveThrowImpactPosition(startPosition, throwDirection, releasedTarget.character, bossModel)
		if impactPosition == nil then
			Logger.Warn("[BroccoliGrab] Throw could not resolve a valid support surface.")
			markComplete()
			return
		end

		local projectileMotion = CombatProjectileUtil.CreateLinearMotion(
			startPosition,
			impactPosition,
			THROW_PROXY_SPEED_STUDS_PER_SECOND
		)
		local travelDuration = projectileMotion.travelDuration

		if travelDuration <= 0 then
			handleImpact({
				player = releasedTarget.player,
				character = releasedTarget.character,
				humanoid = releasedTarget.humanoid,
				impactPosition = impactPosition,
			})
			markComplete()
			return
		end

		Knockback(releasedTarget.character, "LinearProxy", {
			StartPosition = startPosition,
			ImpactPosition = impactPosition,
			Duration = travelDuration,
			RagdollDuration = travelDuration + THROW_POST_IMPACT_RAGDOLL_SECONDS,
			AuthorityMode = "VictimClient",
			FaceDirection = throwDirection,
		})

		local currentThrowState = {
			player = releasedTarget.player,
			character = releasedTarget.character,
			humanoid = releasedTarget.humanoid,
			impactPosition = impactPosition,
			knockbackID = releasedTarget.character:GetAttribute("KnockbackID"),
			impactDelayThread = nil,
		}
		throwState = currentThrowState

		currentThrowState.impactDelayThread = task.delay(travelDuration, function()
			if throwState ~= currentThrowState or cancelled or bossModel.Parent == nil then
				return
			end

			throwState = nil
			handleImpact(currentThrowState)
			markComplete()
		end)
	end

	local function playThrowAnimation()
		if cancelled or bossModel.Parent == nil then
			return
		end

		activePhase = "Throw"
		local track = profile:PlayAnimation(throwAnimation, Enum.AnimationPriority.Action, 1, {
			[THROW_MARKER_NAME] = handleThrow,
		}, ANIMATION_FADE_SECONDS)
		if track == nil then
			Logger.Warn("[BroccoliGrab] Failed to play Throw animation.")
			markComplete()
			cleanup(false)
			return
		end

		track.Looped = false
		disconnectStoppedConnection()
		stoppedConnection = track.Stopped:Connect(function()
			disconnectStoppedConnection()
			if not throwTriggered and not warnedMissingThrowMarker then
				warnedMissingThrowMarker = true
				Logger.Warn("[BroccoliGrab] Throw animation completed without firing the 'Throw' marker.")
			end

			if captiveState ~= nil then
				releaseCaptiveAndClear(true)
			end

			if throwState == nil then
				markComplete()
			end
		end)
	end

	local function handleGrabFinished()
		if cancelled or bossModel.Parent == nil or handPart.Parent == nil then
			return
		end

		local nearestTarget = resolveNearestTarget(bossRootPart, GRAB_RANGE_STUDS)
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
		Logger.Warn("[BroccoliGrab] Failed to play Grab animation.")
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
		if activePhase == "Grab" then
			handleGrabFinished()
			return
		end
		if activePhase == "Throw" and throwState == nil then
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

return table.freeze(Grab)
