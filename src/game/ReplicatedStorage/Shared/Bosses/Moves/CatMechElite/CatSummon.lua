local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)

local ANIMATION_FADE_SECONDS = 0.08
local ANIMATION_FOLDER_NAME = "CatMechElite"
local ANIMATION_NAME = "CatSummon"
local RIGHT_HAND_MARKER_NAME = "RightHand"
local ROOT_PART_MARKER_NAME = "RootPart"
local ROOT_PART_DELAY_SECONDS = 104 / 60
local IMPACT_DELAY_SECONDS = 212 / 60
local PRESENTATION_STOP_DELAY_AFTER_IMPACT_SECONDS = 0.75
local ACTIVE_MINIONS_FOLDER_NAME = "ActiveBossMinions"
local VFX_FOLDER_NAME = "VFX"
local CAT_MECH_ELITE_VFX_FOLDER_NAME = "CatMechElite"
local CAT_SUMMON_VFX_FOLDER_NAME = "CatSummon"
local MINION_MODEL_NAME = "Cat Mech"

local MINION_SCALE = 3
local MINION_MAX_HEALTH = 70
local MINION_WALK_SPEED = 14
local MINION_M1_DAMAGE = 8
local MINION_M1_COOLDOWN_SECONDS = 1.15
local MINION_MOVE_REFRESH_SECONDS = 0.25
local MINION_ATTACK_RANGE = 9
local MINION_HITBOX_DURATION_SECONDS = 0.12
local MINION_HITBOX_WIDTH_SCALE = 2.0
local MINION_HITBOX_HEIGHT_SCALE = 1.6
local MINION_HITBOX_DEPTH_SCALE = 3.0
local MINION_HITBOX_FORWARD_OFFSET_SCALE = 1.4
local MAX_HITBOX_PARTS = 48
local MINION_LOCOMOTION_FADE_SECONDS = 0.12
local MINION_LOCOMOTION_RUN_SPEED_THRESHOLD = MINION_WALK_SPEED * 0.75
local MINION_LOCOMOTION_MOVE_SPEED_THRESHOLD = 0.75
local GROUND_RAYCAST_LIFT = 80
local GROUND_RAYCAST_DEPTH = 420

local stub = CreateExplicitBossMoveStub({
	bossId = "Cat Mech Elite",
	moveLabel = "Cat Summon",
	targetMode = "all_players",
	summaryTemplate = "{moveLabel} calls in a regular cat mech support drop",
	description = "Cat Mech Elite shoots a flare into the air, then a regular cat mech falls from the sky and attacks players with normal M1s.",
})

local CatSummon = {
	CanUse = stub.CanUse,
	ExecuteStub = stub.ExecuteStub,
	GetTargeting = stub.GetTargeting,
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

	local rootPart = model:FindFirstChild("HumanoidRootPart", true)
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
	local animations = gameAssets and gameAssets:FindFirstChild("Animations")
	local catMechFolder = animations and animations:FindFirstChild(ANIMATION_FOLDER_NAME)
	local animationInstance = catMechFolder and catMechFolder:FindFirstChild(ANIMATION_NAME)
	if animationInstance and animationInstance:IsA("Animation") then
		return animationInstance
	end

	return nil
end

local function resolveCatSummonVfxFolder(): Folder?
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	local vfx = gameAssets and gameAssets:FindFirstChild(VFX_FOLDER_NAME)
	local catMechFolder = vfx and vfx:FindFirstChild(CAT_MECH_ELITE_VFX_FOLDER_NAME)
	local catSummonFolder = catMechFolder and catMechFolder:FindFirstChild(CAT_SUMMON_VFX_FOLDER_NAME)
	if catSummonFolder and catSummonFolder:IsA("Folder") then
		return catSummonFolder
	end

	return nil
end

local function resolveMinionSourceModel(): Model?
	local catSummonFolder = resolveCatSummonVfxFolder()
	local minionModel = catSummonFolder and catSummonFolder:FindFirstChild(MINION_MODEL_NAME)
	if minionModel and minionModel:IsA("Model") then
		return minionModel
	end

	return nil
end

local function resolveRuntimeImpactVfxPartCFrame(bossRootPart: BasePart, scaleMultiplier: number): CFrame
	local catSummonFolder = resolveCatSummonVfxFolder()
	local impactSource = catSummonFolder and catSummonFolder:FindFirstChild("Impact")
	if not (impactSource and impactSource:IsA("Model")) then
		return bossRootPart.CFrame
	end

	local impactModel = impactSource:Clone()
	impactModel:ScaleTo(math.max(0.1, scaleMultiplier))
	impactModel:PivotTo(bossRootPart.CFrame)

	local impactPart = impactModel:FindFirstChild("Impact", true)
	if not (impactPart and impactPart:IsA("BasePart")) then
		impactModel:Destroy()
		return bossRootPart.CFrame
	end

	local impactCFrame = impactPart.CFrame
	impactModel:Destroy()
	return impactCFrame
end

local function ensureActiveMinionsFolder(): Folder
	local existing = Workspace:FindFirstChild(ACTIVE_MINIONS_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = ACTIVE_MINIONS_FOLDER_NAME
	folder.Parent = Workspace
	return folder
end

local function buildGroundRaycastParams(ignoreInstances: { Instance }): RaycastParams
	local includeInstances = {}

	local activeBossArena = Workspace:FindFirstChild("ActiveBossArena")
	if activeBossArena then
		table.insert(includeInstances, activeBossArena)
	end

	local map = Workspace:FindFirstChild("Map")
	if map then
		table.insert(includeInstances, map)
	end

	local world = Workspace:FindFirstChild("World")
	local worldMap = world and world:FindFirstChild("Map")
	if worldMap then
		table.insert(includeInstances, worldMap)
	end

	if Workspace.Terrain then
		table.insert(includeInstances, Workspace.Terrain)
	end

	local params = RaycastParams.new()
	params.IgnoreWater = false
	if #includeInstances > 0 then
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = includeInstances
	else
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = ignoreInstances
	end

	return params
end

local function resolveGroundPosition(position: Vector3, ignoreInstances: { Instance }): Vector3
	local origin = position + Vector3.new(0, GROUND_RAYCAST_LIFT, 0)
	local direction = Vector3.new(0, -(GROUND_RAYCAST_LIFT + GROUND_RAYCAST_DEPTH), 0)
	local result = Workspace:Raycast(origin, direction, buildGroundRaycastParams(ignoreInstances))
	return if result then result.Position else position
end

local function getStandingHeight(humanoid: Humanoid, rootPart: BasePart): number
	return math.max((rootPart.Size.Y * 0.5) + humanoid.HipHeight, rootPart.Size.Y)
end

local function setServerNetworkOwnership(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Anchored == false then
			pcall(function()
				descendant:SetNetworkOwner(nil)
			end)
		end
	end
end

local function getOrCreateAnimator(humanoid: Humanoid): Animator
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end

	local createdAnimator = Instance.new("Animator")
	createdAnimator.Parent = humanoid
	return createdAnimator
end

local function resolveAnimateAnimation(animateScript: Instance?, folderName: string, animationNames: { string }): Animation?
	if animateScript == nil then
		return nil
	end

	local folder = animateScript:FindFirstChild(folderName)
	if folder == nil then
		return nil
	end

	for _, animationName in ipairs(animationNames) do
		local animation = folder:FindFirstChild(animationName)
		if animation and animation:IsA("Animation") then
			return animation
		end
	end

	return folder:FindFirstChildWhichIsA("Animation")
end

local function loadMinionLocomotionTrack(animator: Animator, animation: Animation?): AnimationTrack?
	if animation == nil then
		return nil
	end

	local ok, trackOrError = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or trackOrError == nil then
		warn("[CatSummon] Failed to load minion locomotion animation:", trackOrError)
		return nil
	end

	local track = trackOrError
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Movement
	return track
end

local function createMinionLocomotionController(minionModel: Model, humanoid: Humanoid, rootPart: BasePart)
	local animateScript = minionModel:FindFirstChild("Animate")
	local animator = getOrCreateAnimator(humanoid)
	local idleAnimation = resolveAnimateAnimation(animateScript, "idle", { "Animation1", "Animation2" })
	local walkAnimation = resolveAnimateAnimation(animateScript, "walk", { "WalkAnim" })
	local runAnimation = resolveAnimateAnimation(animateScript, "run", { "RunAnim" })
	local tracks = {
		idle = loadMinionLocomotionTrack(animator, idleAnimation),
		walk = loadMinionLocomotionTrack(animator, walkAnimation),
		run = loadMinionLocomotionTrack(animator, runAnimation),
	}
	local activeState = nil :: string?
	local destroyed = false

	local function stopTrack(trackToStop: AnimationTrack?)
		if trackToStop ~= nil and trackToStop.IsPlaying then
			trackToStop:Stop(MINION_LOCOMOTION_FADE_SECONDS)
		end
	end

	local function playState(nextState: string)
		if destroyed or activeState == nextState then
			return
		end

		local nextTrack = tracks[nextState]
		if nextTrack == nil then
			for _, existingTrack in pairs(tracks) do
				stopTrack(existingTrack)
			end
			activeState = nil
			return
		end

		for state, existingTrack in pairs(tracks) do
			if state ~= nextState then
				stopTrack(existingTrack)
			end
		end

		if not nextTrack.IsPlaying then
			nextTrack:Play(MINION_LOCOMOTION_FADE_SECONDS)
		end
		activeState = nextState
	end

	playState("idle")

	return {
		Update = function(hasTarget: boolean)
			if destroyed then
				return
			end

			if hasTarget ~= true or humanoid.Health <= 0 or rootPart.Parent == nil then
				playState("idle")
				return
			end

			local velocity = rootPart.AssemblyLinearVelocity
			local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
			if horizontalSpeed < MINION_LOCOMOTION_MOVE_SPEED_THRESHOLD then
				playState("idle")
			elseif horizontalSpeed >= MINION_LOCOMOTION_RUN_SPEED_THRESHOLD and tracks.run ~= nil then
				playState("run")
			else
				playState("walk")
			end
		end,
		Destroy = function()
			if destroyed then
				return
			end

			destroyed = true
			for _, locomotionTrack in pairs(tracks) do
				stopTrack(locomotionTrack)
				pcall(function()
					locomotionTrack:Destroy()
				end)
			end
			table.clear(tracks)
		end,
	}
end

local function getAlivePlayerTargets(origin: Vector3)
	local targets = {}

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = resolveHumanoid(character)
		local rootPart = resolveRootPart(character)
		if character == nil or humanoid == nil or humanoid.Health <= 0 or rootPart == nil then
			continue
		end

		table.insert(targets, {
			player = player,
			character = character,
			humanoid = humanoid,
			rootPart = rootPart,
			distance = (rootPart.Position - origin).Magnitude,
		})
	end

	table.sort(targets, function(left, right)
		if left.distance == right.distance then
			return left.player.UserId < right.player.UserId
		end

		return left.distance < right.distance
	end)

	return targets
end

local function resolveMinionHitboxSizeAndOffset(rootPart: BasePart): (Vector3, number)
	local rootSize = rootPart.Size
	return Vector3.new(
		rootSize.X * MINION_HITBOX_WIDTH_SCALE,
		rootSize.Y * MINION_HITBOX_HEIGHT_SCALE,
		rootSize.Z * MINION_HITBOX_DEPTH_SCALE
	), rootSize.Z * MINION_HITBOX_FORWARD_OFFSET_SCALE
end

local function spawnMinionAttackHitbox(
	minionModel: Model,
	minionRootPart: BasePart,
	damagedTargets: { [Model]: boolean },
	activeHitboxes: { [any]: boolean }
)
	local hitboxSize, forwardOffset = resolveMinionHitboxSizeAndOffset(minionRootPart)
	local hitbox
	hitbox = Hitbox.new({
		Character = minionModel,
		HitboxCFrame = function()
			if minionRootPart.Parent == nil then
				return nil
			end

			return minionRootPart.CFrame
		end,
		HitboxOffset = CFrame.new(0, 0, -forwardOffset),
		HitboxSize = hitboxSize,
		HitboxType = "SpacialQuery",
		Time = MINION_HITBOX_DURATION_SECONDS,
		MaxParts = MAX_HITBOX_PARTS,
	}, {
		HitTarget = function(targetModel: Model)
			if damagedTargets[targetModel] == true then
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

			damagedTargets[targetModel] = true
			humanoid:TakeDamage(MINION_M1_DAMAGE)
		end,
		HitboxDestroy = function()
			activeHitboxes[hitbox] = nil
		end,
	})

	activeHitboxes[hitbox] = true
	hitbox:Visible(true)
end

function CatSummon.StartCast(context)
	local bossModel = context.bossModel
	local bossHumanoid = context.bossHumanoid
	local bossRootPart = context.bossRootPart
	if bossModel == nil
		or bossModel.Parent == nil
		or bossHumanoid == nil
		or bossHumanoid.Health <= 0
		or bossRootPart == nil
		or bossRootPart.Parent == nil then
		return nil
	end

	local animationInstance = resolveAnimationInstance()
	if animationInstance == nil then
		warn("[CatSummon] Missing animation at ReplicatedStorage.GameAssets.Animations.CatMechElite.CatSummon.")
		return nil
	end

	local minionSourceModel = resolveMinionSourceModel()
	if minionSourceModel == nil then
		warn("[CatSummon] Missing minion model at ReplicatedStorage.GameAssets.VFX.CatMechElite.CatSummon.Cat Mech.")
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[CatSummon] Failed to create animation profile:", profileOrError)
		return nil
	end

	local profile = profileOrError
	local track = nil :: AnimationTrack?
	local stoppedConnection = nil :: RBXScriptConnection?
	local rootPartFallbackThread = nil :: thread?
	local impactThread = nil :: thread?
	local completed = false
	local cancelled = false
	local cleanedUp = false
	local rightHandTriggered = false
	local rootPartTriggered = false
	local impactTriggered = false
	local presentationStopped = false
	local recoveryEndsAt = nil :: number?
	local minionModel = nil :: Model?
	local minionConnections = {}
	local activeMinionHitboxes = {}
	local minionLocomotionController = nil

	local function disconnectStoppedConnection()
		if stoppedConnection and stoppedConnection.Connected then
			stoppedConnection:Disconnect()
		end
		stoppedConnection = nil
	end

	local function disconnectMinionConnections()
		for _, connection in ipairs(minionConnections) do
			if connection.Connected then
				connection:Disconnect()
			end
		end
		table.clear(minionConnections)
	end

	local function destroyActiveMinionHitboxes()
		for hitbox in pairs(activeMinionHitboxes) do
			hitbox:Destroy()
		end
		table.clear(activeMinionHitboxes)
	end

	local function destroyMinionLocomotionController()
		if minionLocomotionController == nil then
			return
		end

		local ok, err = pcall(minionLocomotionController.Destroy)
		if not ok then
			warn("[CatSummon] Failed to destroy minion locomotion controller:", err)
		end
		minionLocomotionController = nil
	end

	local function stopPresentation()
		if presentationStopped then
			return
		end

		presentationStopped = true
		context.EmitPresentation("stop")
	end

	local function markComplete()
		if completed then
			return
		end

		completed = true
		recoveryEndsAt = os.clock() + (tonumber(context.move and context.move.recoverySeconds) or 0)
		task.delay(PRESENTATION_STOP_DELAY_AFTER_IMPACT_SECONDS, function()
			if not cancelled then
				stopPresentation()
			end
		end)
	end

	local function destroyMinion()
		if minionModel and minionModel.Parent ~= nil then
			minionModel:Destroy()
		end
		minionModel = nil
	end

	local function cleanup(stopAnimation: boolean)
		if cleanedUp then
			return
		end

		cleanedUp = true
		stopPresentation()
		disconnectStoppedConnection()
		disconnectMinionConnections()
		destroyActiveMinionHitboxes()
		destroyMinionLocomotionController()
		destroyMinion()

		if impactThread ~= nil then
			task.cancel(impactThread)
			impactThread = nil
		end
		if rootPartFallbackThread ~= nil then
			task.cancel(rootPartFallbackThread)
			rootPartFallbackThread = nil
		end

		if stopAnimation and track then
			profile:StopAnimation(animationInstance, ANIMATION_FADE_SECONDS)
		end

		local minionsFolder = Workspace:FindFirstChild(ACTIVE_MINIONS_FOLDER_NAME)
		if minionsFolder and minionsFolder:IsA("Folder") and #minionsFolder:GetChildren() <= 0 then
			minionsFolder:Destroy()
		end
	end

	local function removeMinion()
		destroyMinionLocomotionController()
		disconnectMinionConnections()
		minionModel = nil

		local minionsFolder = Workspace:FindFirstChild(ACTIVE_MINIONS_FOLDER_NAME)
		if minionsFolder and minionsFolder:IsA("Folder") and #minionsFolder:GetChildren() <= 0 then
			minionsFolder:Destroy()
		end
	end

	local function bindMinionAi(spawnedMinion: Model, humanoid: Humanoid, rootPart: BasePart)
		local nextAttackAt = 0
		local lastMoveAt = 0
		minionLocomotionController = createMinionLocomotionController(spawnedMinion, humanoid, rootPart)

		table.insert(minionConnections, humanoid.Died:Connect(function()
			task.defer(function()
				if spawnedMinion.Parent ~= nil then
					spawnedMinion:Destroy()
				end
				removeMinion()
			end)
		end))
		table.insert(minionConnections, spawnedMinion.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				removeMinion()
			end
		end))
		table.insert(minionConnections, bossModel.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				destroyMinion()
			end
		end))
		table.insert(minionConnections, bossHumanoid.Died:Connect(function()
			destroyMinion()
		end))

		table.insert(minionConnections, RunService.Heartbeat:Connect(function()
			if cancelled or spawnedMinion.Parent == nil or humanoid.Health <= 0 or rootPart.Parent == nil then
				return
			end

			local targets = getAlivePlayerTargets(rootPart.Position)
			local target = targets[1]
			if target == nil then
				minionLocomotionController.Update(false)
				return
			end

			local now = os.clock()
			if now - lastMoveAt >= MINION_MOVE_REFRESH_SECONDS then
				lastMoveAt = now
				humanoid:MoveTo(target.rootPart.Position)
			end
			minionLocomotionController.Update(true)

			if target.distance > MINION_ATTACK_RANGE or now < nextAttackAt then
				return
			end

			nextAttackAt = now + MINION_M1_COOLDOWN_SECONDS
			spawnMinionAttackHitbox(spawnedMinion, rootPart, {}, activeMinionHitboxes)
		end))
	end

	local function spawnMinionAtImpact(impactCFrame: CFrame)
		local minionsFolder = ensureActiveMinionsFolder()
		local floorPosition = resolveGroundPosition(impactCFrame.Position, { bossModel })
		local spawnedMinion = minionSourceModel:Clone()
		spawnedMinion.Name = "CatSummonMinion_" .. HttpService:GenerateGUID(false)
		spawnedMinion:SetAttribute("Team", "CatMechElite")
		spawnedMinion.Parent = minionsFolder
		spawnedMinion:ScaleTo(MINION_SCALE)

		local humanoid = resolveHumanoid(spawnedMinion)
		local rootPart = resolveRootPart(spawnedMinion)
		if humanoid == nil or rootPart == nil then
			warn("[CatSummon] Minion source must contain a Humanoid and HumanoidRootPart.")
			spawnedMinion:Destroy()
			return
		end

		local standingHeight = getStandingHeight(humanoid, rootPart)
		local spawnPosition = floorPosition + Vector3.new(0, standingHeight, 0)
		local lookTarget = Vector3.new(bossRootPart.Position.X, spawnPosition.Y, bossRootPart.Position.Z)
		if (lookTarget - spawnPosition).Magnitude <= 0.001 then
			lookTarget = spawnPosition + bossRootPart.CFrame.LookVector
		end

		humanoid.MaxHealth = MINION_MAX_HEALTH
		humanoid.Health = MINION_MAX_HEALTH
		humanoid.WalkSpeed = MINION_WALK_SPEED
		humanoid.AutoRotate = true
		spawnedMinion:PivotTo(CFrame.lookAt(spawnPosition, lookTarget))
		setServerNetworkOwnership(spawnedMinion)
		minionModel = spawnedMinion
		bindMinionAi(spawnedMinion, humanoid, rootPart)
	end

	local function handleRightHand()
		if cancelled or rightHandTriggered then
			return
		end

		rightHandTriggered = true
		context.EmitPresentation("start", {
			scaleMultiplier = tonumber(context.bossDefinition and context.bossDefinition.scaleMultiplier) or 1,
		})
	end

	local function handleRootPart()
		if cancelled or rootPartTriggered then
			return
		end

		rootPartTriggered = true
		rootPartFallbackThread = nil
		context.EmitPresentation("rootPart", {
			scaleMultiplier = tonumber(context.bossDefinition and context.bossDefinition.scaleMultiplier) or 1,
		})
	end

	local function handleImpact()
		if cancelled or completed or impactTriggered or bossModel.Parent == nil or bossRootPart.Parent == nil then
			return
		end

		impactTriggered = true
		impactThread = nil
		local scaleMultiplier = tonumber(context.bossDefinition and context.bossDefinition.scaleMultiplier) or 1
		local impactVfxPartCFrame = resolveRuntimeImpactVfxPartCFrame(bossRootPart, scaleMultiplier)
		context.EmitPresentation("impact", {
			scaleMultiplier = scaleMultiplier,
		})
		spawnMinionAtImpact(impactVfxPartCFrame)
		markComplete()
	end

	track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, {
		[RIGHT_HAND_MARKER_NAME] = handleRightHand,
		[ROOT_PART_MARKER_NAME] = handleRootPart,
	}, ANIMATION_FADE_SECONDS)
	if track == nil then
		warn("[CatSummon] Failed to play CatSummon animation.")
		return nil
	end

	handleRightHand()
	track.Looped = false
	rootPartFallbackThread = task.delay(ROOT_PART_DELAY_SECONDS, handleRootPart)
	impactThread = task.delay(IMPACT_DELAY_SECONDS, handleImpact)
	stoppedConnection = track.Stopped:Connect(function()
		disconnectStoppedConnection()
		if cancelled then
			return
		end

		if not rightHandTriggered then
			handleRightHand()
		end
		if not rootPartTriggered then
			warn(string.format(
				"[CatSummon] Animation '%s' completed without firing the '%s' marker.",
				animationInstance.Name,
				ROOT_PART_MARKER_NAME
			))
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

return table.freeze(CatSummon)
