local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Animation = require(ReplicatedStorage.Shared.Animation)
local MinionDisplay = require(ReplicatedStorage.Shared.Bosses.MinionDisplay)
local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)

local ANIMATION_FOLDER_NAME = "Agrynoth"
local ANIMATION_NAME = "Warcall"
local SPAWN_MARKER_NAME = "Spawn"
local ANIMATION_FADE_SECONDS = 0.08
local BOSS_INVULNERABLE_ATTRIBUTE = "BossM1Invulnerable"
local WAR_CALL_USED_ATTRIBUTE = "WarCallUsed"
local ACTIVE_MINIONS_FOLDER_NAME = "ActiveBossMinions"

local VFX_FOLDER_NAME = "VFX"
local AGRYNOTH_VFX_FOLDER_NAME = "Agrynoth"
local WAR_CALL_VFX_FOLDER_NAME = "WarCall"
local MINION_MODEL_NAME = "Minion"
local MINION_DISPLAY_NAME = "Agrynoth Minion"

local HEALTH_THRESHOLD = 0.5
local ELIGIBLE_SELECTION_WEIGHT = 1000
local MINION_COUNT = 6
local MINION_SCALE = 3
local MINION_SPAWN_RADIUS = 42
local MINION_MAX_HEALTH = 80
local MINION_WALK_SPEED = 14
local MINION_M1_DAMAGE = 8
local MINION_M1_COOLDOWN_SECONDS = 1.15
local MINION_MOVE_REFRESH_SECONDS = 0.25
local MINION_ATTACK_RANGE = 10
local MINION_HITBOX_DURATION_SECONDS = 0.12
local MINION_HITBOX_WIDTH_SCALE = 2.2
local MINION_HITBOX_HEIGHT_SCALE = 1.7
local MINION_HITBOX_DEPTH_SCALE = 3.2
local MINION_HITBOX_FORWARD_OFFSET_SCALE = 1.45
local MAX_HITBOX_PARTS = 48
local GROUND_RAYCAST_LIFT = 80
local GROUND_RAYCAST_DEPTH = 420
local MINION_LOCOMOTION_FADE_SECONDS = 0.12
local MINION_LOCOMOTION_RUN_SPEED_THRESHOLD = MINION_WALK_SPEED * 0.75
local MINION_LOCOMOTION_MOVE_SPEED_THRESHOLD = 0.75

local stub = CreateExplicitBossMoveStub({
	bossId = "Agrynoth",
	moveLabel = "War Call",
	targetMode = "all_players",
	summaryTemplate = "{moveLabel} summons minions to hunt {targets}",
	description = "Agrynoth calls six minions into the arena and waits until they are defeated.",
})

local WarCall = {
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

	local animationInstance = agrynothFolder:FindFirstChild(ANIMATION_NAME)
	if animationInstance and animationInstance:IsA("Animation") then
		return animationInstance
	end

	return nil
end

local function resolveMinionSourceModel(): Model?
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	if not (gameAssets and gameAssets:IsA("Folder")) then
		return nil
	end

	local vfxFolder = gameAssets:FindFirstChild(VFX_FOLDER_NAME)
	if not (vfxFolder and vfxFolder:IsA("Folder")) then
		return nil
	end

	local agrynothFolder = vfxFolder:FindFirstChild(AGRYNOTH_VFX_FOLDER_NAME)
	if not (agrynothFolder and agrynothFolder:IsA("Folder")) then
		return nil
	end

	local warCallFolder = agrynothFolder:FindFirstChild(WAR_CALL_VFX_FOLDER_NAME)
	if not (warCallFolder and warCallFolder:IsA("Folder")) then
		return nil
	end

	local minionModel = warCallFolder:FindFirstChild(MINION_MODEL_NAME)
	if minionModel and minionModel:IsA("Model") then
		return minionModel
	end

	return nil
end

local function ensureActiveMinionsFolder(): Folder
	local existing = Workspace:FindFirstChild(ACTIVE_MINIONS_FOLDER_NAME)
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
		warn("[WarCall] Failed to load minion locomotion animation:", trackOrError)
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

	if idleAnimation == nil or walkAnimation == nil or runAnimation == nil then
		warn(string.format(
			"[WarCall] Minion '%s' is missing one or more Animate idle/walk/run animations.",
			minionModel.Name
		))
	end

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

	local function stopAll()
		for _, locomotionTrack in pairs(tracks) do
			stopTrack(locomotionTrack)
		end
		activeState = nil
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
			stopAll()
			for _, locomotionTrack in pairs(tracks) do
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

local function spawnMinionAttackHitbox(minionModel: Model, minionRootPart: BasePart, damagedTargets: { [Model]: boolean }, activeHitboxes: { [any]: boolean })
	local hitboxSize, forwardOffset = resolveMinionHitboxSizeAndOffset(minionRootPart)
	local hitbox
	hitbox = Hitbox.new({
		DebugVisibilityAttribute = "BossHitboxesVisible",
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
end

function WarCall.CanUse(context)
	if stub.CanUse(context) ~= true then
		return false, "No alive players"
	end
	if context.bossModel and context.bossModel:GetAttribute(WAR_CALL_USED_ATTRIBUTE) == true then
		return false, "War Call already used"
	end

	local bossHumanoid = context.bossHumanoid
	if bossHumanoid == nil or bossHumanoid.MaxHealth <= 0 then
		return false, "Missing boss health"
	end
	if bossHumanoid.Health > bossHumanoid.MaxHealth * HEALTH_THRESHOLD then
		return false, "Health threshold not reached"
	end

	return true
end

function WarCall.GetSelectionWeight(_context)
	return ELIGIBLE_SELECTION_WEIGHT
end

function WarCall.StartCast(context)
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
		warn("[WarCall] Missing animation at ReplicatedStorage.GameAssets.Animations.Agrynoth.Warcall.")
		return nil
	end

	local minionSourceModel = resolveMinionSourceModel()
	if minionSourceModel == nil then
		warn("[WarCall] Missing minion model at ReplicatedStorage.GameAssets.VFX.Agrynoth.WarCall.Minion.")
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[WarCall] Failed to create animation profile:", profileOrError)
		return nil
	end

	bossModel:SetAttribute(WAR_CALL_USED_ATTRIBUTE, true)

	local profile = profileOrError
	local track = nil :: AnimationTrack?
	local stoppedConnection = nil :: RBXScriptConnection?
	local completed = false
	local cancelled = false
	local cleanedUp = false
	local spawnTriggered = false
	local presentationStopped = false
	local recoveryEndsAt = nil :: number?
	local minionsFolder = nil :: Folder?
	local activeMinions = {}
	local minionConnections = {}
	local activeMinionHitboxes = {}
	local activeMinionLocomotionControllers = {}

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

	local function destroyMinionLocomotionController(minionModel: Model)
		local locomotionController = activeMinionLocomotionControllers[minionModel]
		if locomotionController == nil then
			return
		end

		activeMinionLocomotionControllers[minionModel] = nil
		local ok, err = pcall(locomotionController.Destroy)
		if not ok then
			warn("[WarCall] Failed to destroy minion locomotion controller:", err)
		end
	end

	local function destroyActiveMinionLocomotionControllers()
		for minionModel in pairs(activeMinionLocomotionControllers) do
			destroyMinionLocomotionController(minionModel)
		end
		table.clear(activeMinionLocomotionControllers)
	end

	local function stopPresentation()
		if presentationStopped then
			return
		end

		presentationStopped = true
		context.EmitPresentation("stop")
	end

	local function clearBossInvulnerability()
		if bossModel.Parent ~= nil then
			bossModel:SetAttribute(BOSS_INVULNERABLE_ATTRIBUTE, nil)
		end
	end

	local function countActiveMinions(): number
		local count = 0
		for _ in pairs(activeMinions) do
			count += 1
		end
		return count
	end

	local function markComplete()
		if completed then
			return
		end

		completed = true
		recoveryEndsAt = os.clock() + (tonumber(context.move and context.move.recoverySeconds) or 0)
		clearBossInvulnerability()
		stopPresentation()
		destroyActiveMinionHitboxes()
		destroyActiveMinionLocomotionControllers()
		disconnectMinionConnections()
		if minionsFolder and minionsFolder.Parent and #minionsFolder:GetChildren() <= 0 then
			minionsFolder:Destroy()
		end
	end

	local function destroyMinionsFolderIfEmpty()
		if minionsFolder and minionsFolder.Parent and #minionsFolder:GetChildren() <= 0 then
			minionsFolder:Destroy()
		end
	end

	local function removeMinion(minionModel: Model)
		if activeMinions[minionModel] ~= true then
			return
		end

		activeMinions[minionModel] = nil
		destroyMinionLocomotionController(minionModel)
		if countActiveMinions() <= 0 then
			markComplete()
		end
	end

	local function cleanup(stopAnimation: boolean)
		if cleanedUp then
			return
		end

		cleanedUp = true
		clearBossInvulnerability()
		stopPresentation()
		disconnectStoppedConnection()
		disconnectMinionConnections()
		destroyActiveMinionHitboxes()
		destroyActiveMinionLocomotionControllers()

		if stopAnimation and track then
			profile:StopAnimation(animationInstance, ANIMATION_FADE_SECONDS)
		end
		if minionsFolder and minionsFolder.Parent then
			minionsFolder:Destroy()
		end
	end

	local function bindMinionAi(minionModel: Model, humanoid: Humanoid, rootPart: BasePart)
		local nextAttackAt = 0
		local lastMoveAt = 0
		local locomotionController = createMinionLocomotionController(minionModel, humanoid, rootPart)
		activeMinionLocomotionControllers[minionModel] = locomotionController

		table.insert(minionConnections, humanoid.Died:Connect(function()
			removeMinion(minionModel)
			task.defer(function()
				if minionModel.Parent ~= nil then
					minionModel:Destroy()
				end
				destroyMinionsFolderIfEmpty()
			end)
		end))
		table.insert(minionConnections, minionModel.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				removeMinion(minionModel)
				destroyMinionsFolderIfEmpty()
			end
		end))

		table.insert(minionConnections, RunService.Heartbeat:Connect(function()
			if cancelled or completed or minionModel.Parent == nil or humanoid.Health <= 0 or rootPart.Parent == nil then
				if humanoid.Health <= 0 or minionModel.Parent == nil then
					removeMinion(minionModel)
				end
				return
			end

			local targets = getAlivePlayerTargets(rootPart.Position)
			local target = targets[1]
			if target == nil then
				locomotionController.Update(false)
				return
			end

			local now = os.clock()
			if now - lastMoveAt >= MINION_MOVE_REFRESH_SECONDS then
				lastMoveAt = now
				humanoid:MoveTo(target.rootPart.Position)
			end
			locomotionController.Update(true)

			if target.distance > MINION_ATTACK_RANGE or now < nextAttackAt then
				return
			end

			nextAttackAt = now + MINION_M1_COOLDOWN_SECONDS
			spawnMinionAttackHitbox(minionModel, rootPart, {}, activeMinionHitboxes)
		end))
	end

	local function spawnMinions()
		if cancelled or completed or spawnTriggered or bossModel.Parent == nil or bossRootPart.Parent == nil then
			return
		end

		spawnTriggered = true
		bossModel:SetAttribute(BOSS_INVULNERABLE_ATTRIBUTE, true)
		minionsFolder = ensureActiveMinionsFolder()

		local presentationMinions = {}
		for index = 1, MINION_COUNT do
			local angle = ((index - 1) / MINION_COUNT) * math.pi * 2
			local offset = Vector3.new(math.cos(angle) * MINION_SPAWN_RADIUS, 0, math.sin(angle) * MINION_SPAWN_RADIUS)
			local floorPosition = resolveGroundPosition(bossRootPart.Position + offset, { bossModel })
			local minionModel = minionSourceModel:Clone()
			minionModel.Name = string.format("WarCallMinion%d", index)
			minionModel:SetAttribute("Team", "Agrynoth")

			local scaleOk, scaleError = pcall(function()
				minionModel:ScaleTo(MINION_SCALE)
			end)
			if not scaleOk then
				warn("[WarCall] Failed to scale minion:", scaleError)
			end

			local humanoid = resolveHumanoid(minionModel)
			local rootPart = resolveRootPart(minionModel)
			if humanoid == nil or rootPart == nil then
				warn("[WarCall] Minion source must contain a Humanoid and HumanoidRootPart.")
				minionModel:Destroy()
				continue
			end

			local standingHeight = getStandingHeight(humanoid, rootPart)
			local spawnPosition = floorPosition + Vector3.new(0, standingHeight, 0)
			local lookTarget = Vector3.new(bossRootPart.Position.X, spawnPosition.Y, bossRootPart.Position.Z)
			if (lookTarget - spawnPosition).Magnitude <= 0.001 then
				lookTarget = spawnPosition + Vector3.zAxis
			end

			humanoid.MaxHealth = MINION_MAX_HEALTH
			humanoid.Health = MINION_MAX_HEALTH
			humanoid.WalkSpeed = MINION_WALK_SPEED
			humanoid.AutoRotate = true
			MinionDisplay.ConfigureHumanoid(humanoid, MINION_DISPLAY_NAME)
			minionModel:PivotTo(CFrame.lookAt(spawnPosition, lookTarget))
			minionModel.Parent = minionsFolder
			setServerNetworkOwnership(minionModel)

			activeMinions[minionModel] = true
			bindMinionAi(minionModel, humanoid, rootPart)
			table.insert(presentationMinions, {
				minionModel = minionModel,
				spawnCFrame = CFrame.new(floorPosition),
			})
		end

		if #presentationMinions <= 0 then
			markComplete()
			return
		end

		context.EmitPresentation("spawn", {
			bossScale = context.bossDefinition.scaleMultiplier,
			minionScale = MINION_SCALE,
			minions = presentationMinions,
		})
	end

	track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, {
		[SPAWN_MARKER_NAME] = spawnMinions,
	}, ANIMATION_FADE_SECONDS)
	if track == nil then
		warn("[WarCall] Failed to play Warcall animation.")
		return nil
	end

	context.EmitPresentation("start", {
		bossScale = context.bossDefinition.scaleMultiplier,
		minionScale = MINION_SCALE,
	})
	track.Looped = false
	stoppedConnection = track.Stopped:Connect(function()
		disconnectStoppedConnection()
		if cancelled then
			return
		end
		if not spawnTriggered then
			warn(string.format(
				"[WarCall] Animation '%s' completed without firing the '%s' marker.",
				animationInstance.Name,
				SPAWN_MARKER_NAME
			))
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

return table.freeze(WarCall)
