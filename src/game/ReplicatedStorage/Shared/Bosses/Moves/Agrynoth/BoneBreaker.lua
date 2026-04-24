local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local CombatMoveUtil = require(ReplicatedStorage.Shared.Combat.CombatMoveUtil)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local CharacterPhysicsContext = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Utilities.CharacterPhysicsContext)

local DEFAULT_GRAB_SELECTION_RANGE = 56
local GRAB_HITBOX_DURATION_SECONDS = 0.12
local MAX_GRAB_HITBOX_PARTS = 48
local MIN_GRAB_HITBOX_WIDTH = 18
local MIN_GRAB_HITBOX_HEIGHT = 20
local MIN_GRAB_HITBOX_DEPTH = 28
local GRAB_HITBOX_WIDTH_ROOT_SCALE = 2.4
local GRAB_HITBOX_WIDTH_BOUNDS_SCALE = 1.0
local GRAB_HITBOX_HEIGHT_STANDING_SCALE = 1.15
local GRAB_HITBOX_DEPTH_ROOT_SCALE = 2.5
local GRAB_HITBOX_DEPTH_BOUNDS_SCALE = 1.1
local MIN_GRAB_HAND_FORWARD_OFFSET = 2
local GRAB_HAND_FORWARD_OFFSET_DEPTH_SCALE = 0.18
local GRAB_HAND_FORWARD_OFFSET_HAND_SCALE = 0.35
local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "Agrynoth"
local GRAB_ANIMATION_NAME = "Grab"
local SLAM_ANIMATION_NAME = "GrabSlam"
local GRAB_MARKER_NAME = "Grab"
local HAND_PART_NAME = "LeftHand"
local HAND_GRIP_ATTACHMENT_NAME = "HandGripAttachment"
local GROUND_RAYCAST_LIFT = 10
local GROUND_RAYCAST_DEPTH = 260
local EXPLOSION_HITBOX_HEIGHT = 24
local EXPLOSION_HITBOX_DURATION_SECONDS = 0.12
local MAX_EXPLOSION_HITBOX_PARTS = 128

local HIT_SEQUENCE = table.freeze({
	table.freeze({ radius = 14, damage = 260 }),
	table.freeze({ radius = 22, damage = 260 }),
	table.freeze({ radius = 32, damage = 260 }),
})

local SLAM_HIT_TIMINGS_SECONDS = table.freeze({
	115 / 60,
	144 / 60,
	180 / 60,
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

local function resolveHandGripAttachment(handPart: BasePart?): Attachment?
	if handPart == nil then
		return nil
	end

	local attachment = handPart:FindFirstChild(HAND_GRIP_ATTACHMENT_NAME, true)
	if attachment and attachment:IsA("Attachment") then
		return attachment
	end

	return nil
end

local function resolvePlanarForwardDirection(rootPart: BasePart): Vector3
	local forward = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
	if forward.Magnitude <= 0.001 then
		return Vector3.new(0, 0, -1)
	end

	return forward.Unit
end

local function resolveStandingHeight(bossHumanoid: Humanoid?, bossRootPart: BasePart): number
	if bossHumanoid == nil then
		return bossRootPart.Size.Y
	end

	return math.max((bossRootPart.Size.Y * 0.5) + bossHumanoid.HipHeight, bossRootPart.Size.Y)
end

local function resolveGrabHitboxFootprint(bossModel: Model, bossRootPart: BasePart): (number, number)
	local _, boundingSize = bossModel:GetBoundingBox()
	local rootSize = bossRootPart.Size
	local bossBoundsWidth = math.min(boundingSize.X, boundingSize.Z)
	local bossBoundsDepth = math.max(boundingSize.X, boundingSize.Z)
	local hitboxWidth = math.max(
		MIN_GRAB_HITBOX_WIDTH,
		rootSize.X * GRAB_HITBOX_WIDTH_ROOT_SCALE,
		bossBoundsWidth * GRAB_HITBOX_WIDTH_BOUNDS_SCALE
	)
	local hitboxDepth = math.max(
		MIN_GRAB_HITBOX_DEPTH,
		rootSize.Z * GRAB_HITBOX_DEPTH_ROOT_SCALE,
		bossBoundsDepth * GRAB_HITBOX_DEPTH_BOUNDS_SCALE
	)

	return hitboxWidth, hitboxDepth
end

local function resolveGrabHandForwardOffset(handPart: BasePart, hitboxDepth: number): number
	return math.max(
		MIN_GRAB_HAND_FORWARD_OFFSET,
		hitboxDepth * GRAB_HAND_FORWARD_OFFSET_DEPTH_SCALE,
		handPart.Size.Z * GRAB_HAND_FORWARD_OFFSET_HAND_SCALE
	)
end

local function resolveGrabForwardDirection(handPart: BasePart, bossRootPart: BasePart): Vector3
	local handForward = Vector3.new(handPart.CFrame.LookVector.X, 0, handPart.CFrame.LookVector.Z)
	if handForward.Magnitude > 0.001 then
		return handForward.Unit
	end

	return resolvePlanarForwardDirection(bossRootPart)
end

local function resolveGrabSelectionRange(context): number
	local bossModel = context and context.bossModel
	local bossRootPart = context and context.bossRootPart
	local handPart = if bossModel then resolveHandPart(bossModel) else nil
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return DEFAULT_GRAB_SELECTION_RANGE
	end
	if handPart == nil or handPart.Parent == nil then
		return DEFAULT_GRAB_SELECTION_RANGE
	end

	local _, hitboxDepth = resolveGrabHitboxFootprint(bossModel, bossRootPart)
	local handForwardOffset = resolveGrabHandForwardOffset(handPart, hitboxDepth)
	local planarHandOffset = Vector3.new(
		handPart.Position.X - bossRootPart.Position.X,
		0,
		handPart.Position.Z - bossRootPart.Position.Z
	).Magnitude
	return planarHandOffset + handForwardOffset + (hitboxDepth * 0.5)
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

local function buildGroundRaycastParams(bossModel: Model?): RaycastParams
	local exclude = {}
	local seen = {}
	if bossModel ~= nil then
		seen[bossModel] = true
		table.insert(exclude, bossModel)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character ~= nil and seen[character] ~= true then
			seen[character] = true
			table.insert(exclude, character)
		end
	end

	local params = RaycastParams.new()
	params.IgnoreWater = false
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	return params
end

local function raycastGroundPosition(position: Vector3, bossModel: Model?): Vector3
	local rayOrigin = position + Vector3.new(0, GROUND_RAYCAST_LIFT, 0)
	local rayDirection = Vector3.new(0, -(GROUND_RAYCAST_DEPTH + GROUND_RAYCAST_LIFT), 0)
	local result = Workspace:Raycast(rayOrigin, rayDirection, buildGroundRaycastParams(bossModel))
	if result then
		return result.Position
	end

	return position
end

local function resolveGroundCFrame(rootPart: BasePart?, bossModel: Model?): CFrame?
	if rootPart == nil or rootPart.Parent == nil then
		return nil
	end

	local rayOrigin = rootPart.Position + Vector3.new(0, GROUND_RAYCAST_LIFT, 0)
	local rayDirection = Vector3.new(0, -(GROUND_RAYCAST_DEPTH + GROUND_RAYCAST_LIFT), 0)
	local result = Workspace:Raycast(rayOrigin, rayDirection, buildGroundRaycastParams(bossModel))
	local floorPosition = if result then result.Position else rootPart.Position

	return CFrame.new(floorPosition)
end

local function resolveGrabHitboxGeometry(
	bossModel: Model,
	bossHumanoid: Humanoid?,
	bossRootPart: BasePart,
	handPart: BasePart
): (CFrame, Vector3)
	local forward = resolveGrabForwardDirection(handPart, bossRootPart)
	local right = forward:Cross(Vector3.yAxis)
	if right.Magnitude <= 0.001 then
		right = Vector3.xAxis
	else
		right = right.Unit
	end

	local hitboxWidth, hitboxDepth = resolveGrabHitboxFootprint(bossModel, bossRootPart)
	local forwardOffset = resolveGrabHandForwardOffset(handPart, hitboxDepth)
	local centerPosition = handPart.Position + (forward * forwardOffset)
	local groundPosition = raycastGroundPosition(centerPosition, bossModel)
	local standingHeight = resolveStandingHeight(bossHumanoid, bossRootPart)
	local topY = math.max(
		handPart.Position.Y + (handPart.Size.Y * 0.5),
		bossRootPart.Position.Y + (standingHeight * GRAB_HITBOX_HEIGHT_STANDING_SCALE)
	)
	local hitboxHeight = math.max(MIN_GRAB_HITBOX_HEIGHT, topY - groundPosition.Y)
	local hitboxCFrame = CFrame.fromMatrix(
		Vector3.new(centerPosition.X, groundPosition.Y + (hitboxHeight * 0.5), centerPosition.Z),
		right,
		Vector3.yAxis,
		-forward
	)

	return hitboxCFrame, Vector3.new(hitboxWidth, hitboxHeight, hitboxDepth)
end

local function buildTargetDataForCharacter(bossRootPart: BasePart, character: Model)
	local player = Players:GetPlayerFromCharacter(character)
	if player == nil then
		return nil
	end

	local humanoid = resolveHumanoid(character)
	local rootPart = resolveRootPart(character)
	if humanoid == nil or humanoid.Health <= 0 or rootPart == nil then
		return nil
	end

	return {
		player = player,
		character = character,
		humanoid = humanoid,
		rootPart = rootPart,
		distance = (rootPart.Position - bossRootPart.Position).Magnitude,
	}
end

local function resolveFallbackHoldCFrame(handPart: BasePart, rootPart: BasePart): CFrame
	return handPart.CFrame
		* CFrame.new(
			0,
			-(rootPart.Size.Y * 0.55),
			-((handPart.Size.Z * 0.9) + (rootPart.Size.Z * 0.65))
		)
		* CFrame.Angles(0, math.rad(180), 0)
end

local function pivotCharacterRootToWorldCFrame(character: Model, rootPart: BasePart, targetRootCFrame: CFrame)
	local rootToPivot = rootPart.CFrame:ToObjectSpace(character:GetPivot())
	character:PivotTo(targetRootCFrame * rootToPivot)
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

	local handGripAttachment = resolveHandGripAttachment(handPart)
	local targetRootCFrame = if handGripAttachment
		then handGripAttachment.WorldCFrame
		else resolveFallbackHoldCFrame(handPart, rootPart)
	if handGripAttachment == nil then
		warn("[Agrynoth.BoneBreaker] Missing HandGripAttachment on LeftHand; falling back to legacy hold offset.")
	end

	pivotCharacterRootToWorldCFrame(character, rootPart, targetRootCFrame)
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

local function resolveExplosionHitboxCFrame(floorCFrame: CFrame): CFrame
	return CFrame.new(floorCFrame.Position + Vector3.new(0, EXPLOSION_HITBOX_HEIGHT * 0.5, 0))
end

local function resolveExplosionHitboxSize(radius: number): Vector3
	local diameter = math.max(0, radius * 2)
	return Vector3.new(diameter, EXPLOSION_HITBOX_HEIGHT, diameter)
end

local function spawnExplosionHitbox(
	context,
	floorCFrame: CFrame,
	radius: number,
	damage: number,
	guaranteedCharacter: Model?,
	onDestroy: ((any) -> ())?
)
	local bossModel = context.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		return nil
	end

	local hitTargets = {}
	local resolvedDamage = CombatMoveUtil.ResolveScaledBossDamage(context, damage)
	if guaranteedCharacter ~= nil and guaranteedCharacter.Parent ~= nil then
		CombatMoveUtil.DamageOnce(hitTargets, guaranteedCharacter, resolvedDamage)
	end

	local hitbox
	hitbox = Hitbox.new({
		DebugVisibilityAttribute = "BossHitboxesVisible",
		Character = bossModel,
		HitboxCFrame = resolveExplosionHitboxCFrame(floorCFrame),
		HitboxSize = resolveExplosionHitboxSize(radius),
		HitboxType = "SpacialQuery",
		Time = EXPLOSION_HITBOX_DURATION_SECONDS,
		MaxParts = MAX_EXPLOSION_HITBOX_PARTS,
	}, {
		HitTarget = function(targetModel: Model)
			CombatMoveUtil.DamageOnce(hitTargets, targetModel, resolvedDamage)
		end,
		HitboxDestroy = function()
			if onDestroy then
				onDestroy(hitbox)
			end
			hitbox = nil
			hitTargets = {}
		end,
	})

	return hitbox
end

function BoneBreaker.CanUse(context)
	if stub.CanUse(context) ~= true then
		return false, "No focus target"
	end

	local distance = tonumber(context.distanceToTarget)
	if distance ~= nil and distance > resolveGrabSelectionRange(context) then
		return false, "Target outside grab range"
	end

	return true
end

function BoneBreaker.GetSelectionWeight(context)
	local distance = tonumber(context.distanceToTarget)
	if distance == nil then
		return 1
	end

	local selectionRange = resolveGrabSelectionRange(context)
	return getWeightedValue(distance, {
		{ distance = 0, weight = 1.4 },
		{ distance = 12, weight = 1.65 },
		{ distance = 24, weight = 1.25 },
		{ distance = 42, weight = 0.55 },
		{ distance = selectionRange, weight = 0 },
	})
end

function BoneBreaker.StartCast(context)
	local bossModel = context.bossModel
	local bossRootPart = context.bossRootPart
	local bossHumanoid = context.bossHumanoid
	if bossModel == nil
		or bossModel.Parent == nil
		or bossRootPart == nil
		or bossRootPart.Parent == nil
		or bossHumanoid == nil
		or bossHumanoid.Parent == nil then
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
	local activeGrabHitbox = nil
	local activeExplosionHitboxes = {}
	local grabbed = false
	local hitIndex = 0
	local slamSequence = 0
	local recoveryEndsAt = nil :: number?
	local presentationScaleMultiplier = math.max(0.1, tonumber(context.bossDefinition and context.bossDefinition.scaleMultiplier) or 1)

	local function disconnectStoppedConnection()
		if stoppedConnection and stoppedConnection.Connected then
			stoppedConnection:Disconnect()
		end
		stoppedConnection = nil
	end

	local function destroyGrabHitbox()
		if activeGrabHitbox == nil then
			return
		end

		activeGrabHitbox:Destroy()
		activeGrabHitbox = nil
	end

	local function removeExplosionHitbox(hitbox)
		local index = table.find(activeExplosionHitboxes, hitbox)
		if index then
			table.remove(activeExplosionHitboxes, index)
		end
	end

	local function destroyExplosionHitboxes()
		while #activeExplosionHitboxes > 0 do
			local hitbox = table.remove(activeExplosionHitboxes)
			if hitbox ~= nil then
				hitbox:Destroy()
			end
		end
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
		destroyGrabHitbox()
		destroyExplosionHitboxes()
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
		destroyGrabHitbox()
		destroyExplosionHitboxes()
		releaseCaptiveAndClear(restoreNetworkOwner)

		if stopAnimation then
			profile:StopAnimation(grabAnimation, ANIMATION_FADE_SECONDS)
			profile:StopAnimation(slamAnimation, ANIMATION_FADE_SECONDS)
		end
	end

	local function handleHit(nextHitIndex: number)
		if cancelled or completed or captiveState == nil then
			return
		end
		if isAlivePlayerCharacter(captiveState.character) ~= true then
			markComplete()
			return
		end

		hitIndex = math.max(hitIndex, math.clamp(nextHitIndex, 1, #HIT_SEQUENCE))
		local hitSpec = HIT_SEQUENCE[math.min(nextHitIndex, #HIT_SEQUENCE)]
		local floorCFrame = resolveGroundCFrame(captiveState.rootPart, bossModel)
		if floorCFrame == nil then
			return
		end

		local hitbox = spawnExplosionHitbox(
			context,
			floorCFrame,
			hitSpec.radius,
			hitSpec.damage,
			captiveState.character,
			removeExplosionHitbox
		)
		if hitbox ~= nil then
			table.insert(activeExplosionHitboxes, hitbox)
		end

		context.EmitPresentation("impact", {
			hitIndex = math.min(nextHitIndex, #HIT_SEQUENCE),
			floorCFrame = floorCFrame,
			radius = hitSpec.radius,
			scaleMultiplier = presentationScaleMultiplier,
		})
	end

	local function scheduleAuthoredSlamHits(activeSlamSequence: number)
		for scheduledHitIndex, delaySeconds in ipairs(SLAM_HIT_TIMINGS_SECONDS) do
			task.delay(delaySeconds, function()
				if activeSlamSequence ~= slamSequence then
					return
				end

				handleHit(scheduledHitIndex)
			end)
		end
	end

	local function playSlamAnimation()
		if cancelled or bossModel.Parent == nil then
			return
		end

		activePhase = "GrabSlam"
		local track = profile:PlayAnimation(slamAnimation, Enum.AnimationPriority.Action, 1, nil, ANIMATION_FADE_SECONDS)
		if track == nil then
			warn("[BoneBreaker] Failed to play GrabSlam animation.")
			markComplete()
			return
		end

		slamSequence += 1
		local activeSlamSequence = slamSequence
		context.EmitPresentation("slamStart", {
			scaleMultiplier = presentationScaleMultiplier,
		})
		scheduleAuthoredSlamHits(activeSlamSequence)

		track.Looped = false
		disconnectStoppedConnection()
		stoppedConnection = track.Stopped:Connect(function()
			disconnectStoppedConnection()
			if cancelled then
				return
			end
			if hitIndex < #HIT_SEQUENCE then
				warn(string.format(
					"[BoneBreaker] GrabSlam animation completed after %d %s; expected %d.",
					hitIndex,
					"authored timed hit",
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
		if context.targetRootPart and context.targetRootPart.Parent ~= nil then
			faceTargetFlat(bossModel, bossRootPart, context.targetRootPart)
		end

		destroyGrabHitbox()
		local function getGrabHitboxCFrame(): CFrame?
			if cancelled or bossModel.Parent == nil or bossRootPart.Parent == nil or handPart.Parent == nil then
				return nil
			end

			local grabHitboxCFrame = resolveGrabHitboxGeometry(bossModel, bossHumanoid, bossRootPart, handPart)
			return grabHitboxCFrame
		end

		local _, grabHitboxSize = resolveGrabHitboxGeometry(bossModel, bossHumanoid, bossRootPart, handPart)
		local hitbox
		hitbox = Hitbox.new({
			DebugVisibilityAttribute = "BossHitboxesVisible",
			Character = bossModel,
			HitboxCFrame = getGrabHitboxCFrame,
			HitboxSize = grabHitboxSize,
			HitboxType = "SpacialQuery",
			Time = GRAB_HITBOX_DURATION_SECONDS,
			MaxParts = MAX_GRAB_HITBOX_PARTS,
		}, {
			HitTarget = function(targetModel: Model)
				if cancelled or cleanedUp or captiveState ~= nil then
					return
				end

				local targetData = buildTargetDataForCharacter(bossRootPart, targetModel)
				if targetData == nil then
					return
				end

				faceTargetFlat(bossModel, bossRootPart, targetData.rootPart)
				captiveState = attachTargetToHand(bossRootPart, handPart, targetData)
				if captiveState ~= nil then
					destroyGrabHitbox()
				end
			end,
			HitboxDestroy = function()
				if activeGrabHitbox == hitbox then
					activeGrabHitbox = nil
				end
			end,
		})
		activeGrabHitbox = hitbox
	end

	local grabTrack = profile:PlayAnimation(grabAnimation, Enum.AnimationPriority.Action, 1, {
		[GRAB_MARKER_NAME] = handleGrab,
	}, ANIMATION_FADE_SECONDS)
	if grabTrack == nil then
		warn("[BoneBreaker] Failed to play Grab animation.")
		return nil
	end

	context.EmitPresentation("start", {
		scaleMultiplier = presentationScaleMultiplier,
	})
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
