local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local CharacterPhysicsContext = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Utilities.CharacterPhysicsContext)

local GRAB_RANGE_STUDS = 100
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "Agrynoth"
local GRAB_ANIMATION_NAME = "Grab"
local SLAM_ANIMATION_NAME = "GrabSlam"
local GRAB_MARKER_NAME = "Grab"
local HIT_MARKER_NAME = "Hit"
local HAND_PART_NAME = "LeftHand"
local GROUND_RAYCAST_LIFT = 10
local GROUND_RAYCAST_DEPTH = 260

local HIT_SEQUENCE = table.freeze({
	table.freeze({ radius = 14, damage = 15 }),
	table.freeze({ radius = 22, damage = 20 }),
	table.freeze({ radius = 32, damage = 25 }),
})

local stub = CreateExplicitBossMoveStub({
	bossId = "Agrynoth",
	moveLabel = "Bone Breaker",
	targetMode = "single",
	summaryTemplate = "{moveLabel} smashes {target} into the ground three times",
	description = "Agrynoth grabs a player and smashes them into the ground three times, creating a shockwave each time.",
})

local BoneBreaker = {
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

	local agrynothFolder = animations:FindFirstChild(ANIMATION_FOLDER_NAME)
	if not (agrynothFolder and agrynothFolder:IsA("Folder")) then
		return nil
	end

	local animationInstance = agrynothFolder:FindFirstChild(animationName)
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

local function setAssemblyVelocities(model: Model, linearVelocity: Vector3, angularVelocity: Vector3)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = linearVelocity
			descendant.AssemblyAngularVelocity = angularVelocity
		end
	end
end

local function applyHeldPartPhysics(character: Model): { [BasePart]: {
	canCollide: boolean,
	canTouch: boolean,
	canQuery: boolean,
	massless: boolean,
	rootPriority: number,
} }
	local partPhysicsStates = {}

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			partPhysicsStates[descendant] = {
				canCollide = descendant.CanCollide,
				canTouch = descendant.CanTouch,
				canQuery = descendant.CanQuery,
				massless = descendant.Massless,
				rootPriority = descendant.RootPriority,
			}

			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			descendant.RootPriority = -127
		end
	end

	return partPhysicsStates
end

local function restoreHeldPartPhysics(character: Model?, partPhysicsStates)
	if character == nil or character.Parent == nil then
		return
	end

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
		end
	end

	if typeof(partPhysicsStates) ~= "table" then
		return
	end

	for part, state in pairs(partPhysicsStates) do
		if part.Parent ~= nil and typeof(state) == "table" then
			part.CanCollide = state.canCollide == true
			part.CanTouch = state.canTouch == true
			part.CanQuery = state.canQuery == true
			part.Massless = state.massless == true
			part.RootPriority = tonumber(state.rootPriority) or part.RootPriority
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

local function faceTargetFlat(bossModel: Model, bossRootPart: BasePart, targetRootPart: BasePart)
	local offset = targetRootPart.Position - bossRootPart.Position
	local planarOffset = Vector3.new(offset.X, 0, offset.Z)
	if planarOffset.Magnitude <= 0.001 then
		return
	end

	local currentPivot = bossModel:GetPivot()
	local targetCFrame = CFrame.lookAt(currentPivot.Position, currentPivot.Position + planarOffset.Unit)
	bossModel:PivotTo(targetCFrame)
end

local function buildGroundRaycastParams(ignoreInstances: { Instance }): RaycastParams
	local include = {}

	local activeBossArena = Workspace:FindFirstChild("ActiveBossArena")
	if activeBossArena then
		table.insert(include, activeBossArena)
	end

	local map = Workspace:FindFirstChild("Map")
	if map then
		table.insert(include, map)
	end

	local world = Workspace:FindFirstChild("World")
	local worldMap = world and world:FindFirstChild("Map")
	if worldMap then
		for _, child in ipairs(worldMap:GetChildren()) do
			table.insert(include, child)
		end
	end

	if Workspace.Terrain then
		table.insert(include, Workspace.Terrain)
	end

	local params = RaycastParams.new()
	params.IgnoreWater = false
	if #include > 0 then
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = include
	else
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = ignoreInstances
	end

	return params
end

local function resolveGroundCFrame(character: Model?, rootPart: BasePart?): CFrame?
	if rootPart == nil or rootPart.Parent == nil then
		return nil
	end

	local rayOrigin = rootPart.Position + Vector3.new(0, GROUND_RAYCAST_LIFT, 0)
	local rayDirection = Vector3.new(0, -(GROUND_RAYCAST_DEPTH + GROUND_RAYCAST_LIFT), 0)
	local result = Workspace:Raycast(rayOrigin, rayDirection, buildGroundRaycastParams({ character or rootPart }))
	local floorPosition = if result then result.Position else rootPart.Position

	return CFrame.new(floorPosition)
end

local function attachTargetToHand(bossRootPart: BasePart, handPart: BasePart, targetData): { [string]: any }?
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

	local originalBossRootAnchored = bossRootPart.Anchored
	local originalBossRootPriority = bossRootPart.RootPriority
	local originalHandRootPriority = handPart.RootPriority
	bossRootPart.AssemblyLinearVelocity = Vector3.zero
	bossRootPart.AssemblyAngularVelocity = Vector3.zero
	bossRootPart.RootPriority = 127
	handPart.RootPriority = 127
	bossRootPart.Anchored = true

	local partPhysicsStates = applyHeldPartPhysics(character)
	setAssemblyVelocities(character, Vector3.zero, Vector3.zero)

	local holdOffset = CFrame.new(
		0,
		-(rootPart.Size.Y * 0.55),
		-((handPart.Size.Z * 0.9) + (rootPart.Size.Z * 0.65))
	) * CFrame.Angles(0, math.rad(180), 0)

	character:PivotTo(handPart.CFrame * holdOffset)
	setAssemblyVelocities(character, Vector3.zero, Vector3.zero)

	local weld = Instance.new("WeldConstraint")
	weld.Name = "AgrynothBoneBreakerWeld"
	weld.Part0 = handPart
	weld.Part1 = rootPart
	weld.Parent = handPart

	local originalUseJumpPower = humanoid.UseJumpPower
	local originalWalkSpeed = humanoid.WalkSpeed
	local originalJumpPower = humanoid.JumpPower
	local originalJumpHeight = humanoid.JumpHeight
	local originalAutoRotate = humanoid.AutoRotate
	local originalPlatformStand = humanoid.PlatformStand

	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid.WalkSpeed = 0
	if originalUseJumpPower then
		humanoid.JumpPower = 0
	else
		humanoid.JumpHeight = 0
	end
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	return {
		player = targetData.player,
		character = character,
		humanoid = humanoid,
		rootPart = rootPart,
		bossRootPart = bossRootPart,
		physicsContext = physicsContext,
		weld = weld,
		partPhysicsStates = partPhysicsStates,
		originalBossRootAnchored = originalBossRootAnchored,
		originalBossRootPriority = originalBossRootPriority,
		originalHandRootPriority = originalHandRootPriority,
		handPart = handPart,
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
			if humanoid.Health > 0 and originalPlatformStand ~= true then
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
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

	if captiveState.bossRootPart and captiveState.bossRootPart.Parent ~= nil then
		captiveState.bossRootPart.AssemblyLinearVelocity = Vector3.zero
		captiveState.bossRootPart.AssemblyAngularVelocity = Vector3.zero
		captiveState.bossRootPart.Anchored = captiveState.originalBossRootAnchored == true
		captiveState.bossRootPart.RootPriority = tonumber(captiveState.originalBossRootPriority)
			or captiveState.bossRootPart.RootPriority
	end

	if captiveState.handPart and captiveState.handPart.Parent ~= nil then
		captiveState.handPart.RootPriority = tonumber(captiveState.originalHandRootPriority) or captiveState.handPart.RootPriority
	end

	restoreHeldPartPhysics(character, captiveState.partPhysicsStates)

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
	}
end

local function isAlivePlayerCharacter(character: Model?): boolean
	local humanoid = resolveHumanoid(character)
	return character ~= nil and character.Parent ~= nil and humanoid ~= nil and humanoid.Health > 0
end

local function applyAoeDamage(origin: Vector3, radius: number, damage: number)
	local damagedCharacters = {}

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = resolveHumanoid(character)
		local rootPart = resolveRootPart(character)
		if character == nil or humanoid == nil or humanoid.Health <= 0 or rootPart == nil then
			continue
		end
		if damagedCharacters[character] == true then
			continue
		end

		local offset = rootPart.Position - origin
		local planarDistance = Vector3.new(offset.X, 0, offset.Z).Magnitude
		if planarDistance <= radius then
			damagedCharacters[character] = true
			humanoid:TakeDamage(damage)
		end
	end
end

function BoneBreaker.CanUse(context)
	if stub.CanUse(context) ~= true then
		return false, "No focus target"
	end

	return true
end

function BoneBreaker.GetSelectionWeight(context)
	local distance = tonumber(context.distanceToTarget)
	if distance == nil then
		return 1
	end

	return getWeightedValue(distance, {
		{ distance = 0, weight = 1.4 },
		{ distance = 12, weight = 1.65 },
		{ distance = 24, weight = 1.25 },
		{ distance = 42, weight = 0.55 },
		{ distance = 70, weight = 0.18 },
		{ distance = 100, weight = 0.08 },
	})
end

function BoneBreaker.StartCast(context)
	local bossModel = context.bossModel
	local bossRootPart = context.bossRootPart
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return nil
	end

	local handPart = resolveHandPart(bossModel)
	if handPart == nil then
		warn("[BoneBreaker] Missing LeftHand on Agrynoth boss model.")
		return nil
	end

	local grabAnimation = resolveAnimationInstance(GRAB_ANIMATION_NAME)
	local slamAnimation = resolveAnimationInstance(SLAM_ANIMATION_NAME)
	if grabAnimation == nil or slamAnimation == nil then
		warn("[BoneBreaker] Missing Grab/GrabSlam animations in ReplicatedStorage.GameAssets.Animations.Agrynoth.")
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[BoneBreaker] Failed to create animation profile:", profileOrError)
		return nil
	end

	local profile = profileOrError
	local completed = false
	local cancelled = false
	local cleanedUp = false
	local activePhase = "Grab"
	local stoppedConnection = nil :: RBXScriptConnection?
	local captiveState = nil
	local grabbed = false
	local hitIndex = 0
	local recoveryEndsAt = nil :: number?

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
		context.EmitPresentation("stop")
		releaseCaptiveAndClear(true)
		recoveryEndsAt = os.clock() + (tonumber(context.move and context.move.recoverySeconds) or 0)
	end

	local function cleanup(stopAnimation: boolean, restoreNetworkOwner: boolean)
		if cleanedUp then
			return
		end

		cleanedUp = true
		context.EmitPresentation("stop")
		disconnectStoppedConnection()
		releaseCaptiveAndClear(restoreNetworkOwner)

		if stopAnimation then
			profile:StopAnimation(grabAnimation, ANIMATION_FADE_SECONDS)
			profile:StopAnimation(slamAnimation, ANIMATION_FADE_SECONDS)
		end
	end

	local function handleHit()
		if cancelled or completed or captiveState == nil then
			return
		end
		if isAlivePlayerCharacter(captiveState.character) ~= true then
			markComplete()
			return
		end

		hitIndex += 1
		local hitSpec = HIT_SEQUENCE[math.min(hitIndex, #HIT_SEQUENCE)]
		local floorCFrame = resolveGroundCFrame(captiveState.character, captiveState.rootPart)
		if floorCFrame == nil then
			return
		end

		applyAoeDamage(floorCFrame.Position, hitSpec.radius, hitSpec.damage)
		context.EmitPresentation("impact", {
			hitIndex = math.min(hitIndex, #HIT_SEQUENCE),
			floorCFrame = floorCFrame,
			radius = hitSpec.radius,
		})
	end

	local function playSlamAnimation()
		if cancelled or bossModel.Parent == nil then
			return
		end

		activePhase = "GrabSlam"
		local track = profile:PlayAnimation(slamAnimation, Enum.AnimationPriority.Action, 1, {
			[HIT_MARKER_NAME] = handleHit,
		}, ANIMATION_FADE_SECONDS)
		if track == nil then
			warn("[BoneBreaker] Failed to play GrabSlam animation.")
			markComplete()
			return
		end

		track.Looped = false
		disconnectStoppedConnection()
		stoppedConnection = track.Stopped:Connect(function()
			disconnectStoppedConnection()
			if cancelled then
				return
			end
			if hitIndex < #HIT_SEQUENCE then
				warn(string.format(
					"[BoneBreaker] GrabSlam animation completed after %d '%s' markers; expected %d.",
					hitIndex,
					HIT_MARKER_NAME,
					#HIT_SEQUENCE
				))
			end

			markComplete()
		end)
	end

	local function handleGrab()
		if cancelled or grabbed or bossModel.Parent == nil or bossRootPart.Parent == nil or handPart.Parent == nil then
			return
		end

		grabbed = true
		local nearestTarget = resolveNearestTarget(bossRootPart, GRAB_RANGE_STUDS)
		if nearestTarget == nil then
			return
		end

		faceTargetFlat(bossModel, bossRootPart, nearestTarget.rootPart)
		captiveState = attachTargetToHand(bossRootPart, handPart, nearestTarget)
	end

	local grabTrack = profile:PlayAnimation(grabAnimation, Enum.AnimationPriority.Action, 1, {
		[GRAB_MARKER_NAME] = handleGrab,
	}, ANIMATION_FADE_SECONDS)
	if grabTrack == nil then
		warn("[BoneBreaker] Failed to play Grab animation.")
		return nil
	end

	context.EmitPresentation("start")
	grabTrack.Looped = false
	stoppedConnection = grabTrack.Stopped:Connect(function()
		disconnectStoppedConnection()
		if cancelled then
			return
		end
		if activePhase == "Grab" then
			if captiveState == nil then
				if not grabbed then
					warn("[BoneBreaker] Grab animation completed without firing the 'Grab' marker.")
				end
				markComplete()
				return
			end

			playSlamAnimation()
			return
		end

		if activePhase == "GrabSlam" then
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

return table.freeze(BoneBreaker)
