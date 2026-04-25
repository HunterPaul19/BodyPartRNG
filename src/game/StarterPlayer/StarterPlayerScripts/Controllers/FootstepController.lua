local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FootstepController = {}

local LOCAL_PLAYER = Players.LocalPlayer
local ACTIVE_BOSS_MODEL_NAME = "ActiveBoss"
local GAME_ASSETS_FOLDER_NAME = "GameAssets"
local AUDIO_FOLDER_NAME = "Audio"
local FOOTSTEPS_FOLDER_NAME = "Footsteps"
local BASE_RIG_PATH = { "BodyParts", "BaseRigs", "DefaultR15" }
local FOOTSTEP_EMITTER_NAME = "FootstepAudioEmitter"

local WALK_SPEED_THRESHOLD = 1.25
local MAX_TRACK_DISTANCE_STUDS = 260
local MAX_BOSS_TRACK_DISTANCE_STUDS = 420
local BASE_STEP_DISTANCE_STUDS = 3.8
local MIN_STEP_INTERVAL_SECONDS = 0.16
local MAX_STEP_INTERVAL_SECONDS = 0.8
local TELEPORT_DELTA_RESET_STUDS = 35
local DEFAULT_CLEANUP_SECONDS = 3
local DEFAULT_CONCRETE_GROUP_NAME = "Concrete"

local LEG_PART_NAMES = {
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
}

local PRIVATE_SOUND_IDS = {
	["rbxassetid://10822813850"] = true,
	["rbxassetid://10822813728"] = true,
	["rbxassetid://10822813637"] = true,
	["rbxassetid://10822813572"] = true,
	["rbxassetid://10822813486"] = true,
	["rbxassetid://10822813412"] = true,
}

local MATERIAL_TO_GROUP = {
	[Enum.Material.Slate] = "Concrete",
	[Enum.Material.Concrete] = "Concrete",
	[Enum.Material.Brick] = "Concrete",
	[Enum.Material.Cobblestone] = "Concrete",
	[Enum.Material.Sandstone] = "Concrete",
	[Enum.Material.Rock] = "Concrete",
	[Enum.Material.Basalt] = "Concrete",
	[Enum.Material.CrackedLava] = "Concrete",
	[Enum.Material.Asphalt] = "Concrete",
	[Enum.Material.Limestone] = "Concrete",
	[Enum.Material.Pavement] = "Concrete",

	[Enum.Material.Plastic] = "Tile",
	[Enum.Material.Marble] = "Tile",
	[Enum.Material.Neon] = "Tile",
	[Enum.Material.Granite] = "Tile",

	[Enum.Material.Wood] = "Wood",
	[Enum.Material.WoodPlanks] = "Wood",

	[Enum.Material.Water] = "Slosh",

	[Enum.Material.CorrodedMetal] = "Metal_Solid",
	[Enum.Material.DiamondPlate] = "Metal_Solid",
	[Enum.Material.Metal] = "Metal_Solid",

	[Enum.Material.Foil] = "Metal_Grate",

	[Enum.Material.Ground] = "Dirt",

	[Enum.Material.Grass] = "Grass",
	[Enum.Material.LeafyGrass] = "Grass",

	[Enum.Material.Fabric] = "Carpet",

	[Enum.Material.Pebble] = "Gravel",

	[Enum.Material.Snow] = "Snow",

	[Enum.Material.Sand] = "Sand",
	[Enum.Material.Salt] = "Sand",

	[Enum.Material.Ice] = "Glass",
	[Enum.Material.Glacier] = "Glass",
	[Enum.Material.Glass] = "Glass",

	[Enum.Material.SmoothPlastic] = "Rubber",
	[Enum.Material.ForceField] = "Rubber",

	[Enum.Material.Mud] = "Mud",
}

local GROUP_FALLBACKS = {
	Slosh = { "Mud", "Sand", DEFAULT_CONCRETE_GROUP_NAME },
}

type CharacterState = {
	model: Model,
	humanoid: Humanoid,
	rootPart: BasePart,
	isBoss: boolean,
	nextLeftFoot: boolean,
	lastPosition: Vector3?,
	distanceAccumulator: number,
	nextStepAt: number,
	connections: { RBXScriptConnection },
}

local trackedStatesByModel: { [Model]: CharacterState } = {}
local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local heartbeatConnection: RBXScriptConnection? = nil
local workspaceConnections: { RBXScriptConnection } = {}
local baseLegHeight: number? = nil
local rng = Random.new()

local function getChildByPath(root: Instance?, path: { string }): Instance?
	local current = root
	for _, name in ipairs(path) do
		if current == nil then
			return nil
		end
		current = current:FindFirstChild(name)
	end
	return current
end

local function resolveFootstepsFolder(): Folder?
	local gameAssets = ReplicatedStorage:FindFirstChild(GAME_ASSETS_FOLDER_NAME)
	if not gameAssets then
		return nil
	end

	local audioFolder = gameAssets:FindFirstChild(AUDIO_FOLDER_NAME)
	if not audioFolder then
		return nil
	end

	local footstepsFolder = audioFolder:FindFirstChild(FOOTSTEPS_FOLDER_NAME)
	if footstepsFolder and footstepsFolder:IsA("Folder") then
		return footstepsFolder
	end

	return nil
end

local function resolveBaseLegHeight(): number?
	if baseLegHeight ~= nil then
		return baseLegHeight
	end

	local gameAssets = ReplicatedStorage:FindFirstChild(GAME_ASSETS_FOLDER_NAME)
	local baseRig = getChildByPath(gameAssets, BASE_RIG_PATH)
	if not (baseRig and baseRig:IsA("Model")) then
		return nil
	end

	local totalHeight = 0
	for _, partName in ipairs(LEG_PART_NAMES) do
		local part = baseRig:FindFirstChild(partName, true)
		if part and part:IsA("BasePart") then
			totalHeight += math.max(0, part.Size.Y)
		end
	end

	if totalHeight > 0 then
		baseLegHeight = totalHeight
	end

	return baseLegHeight
end

local function resolveRootPart(model: Model): BasePart?
	local rootPart = model:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	if model.PrimaryPart then
		return model.PrimaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function resolveHumanoid(model: Model): Humanoid?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end

	return nil
end

local function disconnectState(state: CharacterState)
	for _, connection in ipairs(state.connections) do
		if connection.Connected then
			connection:Disconnect()
		end
	end
end

local function removeTrackedModel(model: Model)
	local state = trackedStatesByModel[model]
	if state == nil then
		return
	end

	disconnectState(state)
	trackedStatesByModel[model] = nil
end

local function fallbackModelScale(model: Model): number
	local ok, scale = pcall(function()
		return model:GetScale()
	end)
	if ok and typeof(scale) == "number" and scale > 0 then
		return scale
	end

	return 1
end

local function resolveLegScale(model: Model): number
	local baseHeight = resolveBaseLegHeight()
	if baseHeight ~= nil and baseHeight > 0 then
		local legHeight = 0
		local legPartCount = 0
		for _, partName in ipairs(LEG_PART_NAMES) do
			local part = model:FindFirstChild(partName, true)
			if part and part:IsA("BasePart") then
				legHeight += math.max(0, part.Size.Y)
				legPartCount += 1
			end
		end

		if legPartCount >= 2 and legHeight > 0 then
			return math.clamp(legHeight / baseHeight, 0.35, 8)
		end
	end

	return math.clamp(fallbackModelScale(model), 0.35, 8)
end

local function resolveActorScale(state: CharacterState): number
	if state.isBoss then
		return math.clamp(fallbackModelScale(state.model), 0.35, 10)
	end

	return resolveLegScale(state.model)
end

local function resolveSoundGroupName(material: Enum.Material): string
	return MATERIAL_TO_GROUP[material] or DEFAULT_CONCRETE_GROUP_NAME
end

local function collectPlayableSounds(groupFolder: Instance?): { Sound }
	local sounds = {}
	if groupFolder == nil then
		return sounds
	end

	for _, descendant in ipairs(groupFolder:GetDescendants()) do
		if descendant:IsA("Sound") and descendant.SoundId ~= "" and not PRIVATE_SOUND_IDS[descendant.SoundId] then
			table.insert(sounds, descendant)
		end
	end

	return sounds
end

local function resolveSoundsForGroup(groupName: string): { Sound }
	local footstepsFolder = resolveFootstepsFolder()
	if footstepsFolder == nil then
		return {}
	end

	local groupFolder = footstepsFolder:FindFirstChild(groupName)
	local sounds = collectPlayableSounds(groupFolder)
	if #sounds > 0 then
		return sounds
	end

	for _, fallbackGroupName in ipairs(GROUP_FALLBACKS[groupName] or {}) do
		sounds = collectPlayableSounds(footstepsFolder:FindFirstChild(fallbackGroupName))
		if #sounds > 0 then
			return sounds
		end
	end

	if groupName ~= DEFAULT_CONCRETE_GROUP_NAME then
		return collectPlayableSounds(footstepsFolder:FindFirstChild(DEFAULT_CONCRETE_GROUP_NAME))
	end

	return {}
end

local function resolveFootPart(model: Model, preferLeft: boolean): BasePart?
	local primaryName = if preferLeft then "LeftFoot" else "RightFoot"
	local fallbackName = if preferLeft then "RightFoot" else "LeftFoot"
	local primaryFoot = model:FindFirstChild(primaryName, true)
	if primaryFoot and primaryFoot:IsA("BasePart") then
		return primaryFoot
	end

	local fallbackFoot = model:FindFirstChild(fallbackName, true)
	if fallbackFoot and fallbackFoot:IsA("BasePart") then
		return fallbackFoot
	end

	return nil
end

local function resolveListenerDistance(rootPart: BasePart): number
	local localCharacter = LOCAL_PLAYER.Character
	local localRootPart = if localCharacter then resolveRootPart(localCharacter) else nil
	if localRootPart == nil then
		return 0
	end

	return (rootPart.Position - localRootPart.Position).Magnitude
end

local function createEmitter(position: Vector3, scaleMultiplier: number): BasePart
	local emitter = Instance.new("Part")
	emitter.Name = FOOTSTEP_EMITTER_NAME
	emitter.Anchored = true
	emitter.CanCollide = false
	emitter.CanTouch = false
	emitter.CanQuery = false
	emitter.CastShadow = false
	emitter.Massless = true
	emitter.Transparency = 1
	emitter.Size = Vector3.new(0.2, 0.2, 0.2) * math.clamp(scaleMultiplier, 1, 3)
	emitter.CFrame = CFrame.new(position)
	emitter.Parent = Workspace
	return emitter
end

local function configureReverb(sound: Sound, scaleMultiplier: number)
	local reverb = Instance.new("ReverbSoundEffect")
	local scaleAlpha = math.clamp((scaleMultiplier - 1) / 4, 0, 1)
	reverb.DryLevel = 0
	reverb.WetLevel = -28 + (scaleAlpha * 10)
	reverb.DecayTime = 0.45 + (scaleAlpha * 1.1)
	reverb.Density = 0.35 + (scaleAlpha * 0.3)
	reverb.Diffusion = 0.45 + (scaleAlpha * 0.25)
	reverb.Parent = sound
end

local function configureSpatialSound(sound: Sound, scaleMultiplier: number)
	local resolvedScale = math.clamp(scaleMultiplier, 0.35, 10)
	local playbackScale = math.clamp(1 / (resolvedScale ^ 0.18), 0.65, 1.18)
	local emitterScale = math.clamp(resolvedScale ^ 0.55, 0.75, 3.5)
	local volumeScale = math.clamp(resolvedScale ^ 0.18, 0.85, 1.45)

	sound.PlaybackSpeed = math.clamp((tonumber(sound.PlaybackSpeed) or 1) * playbackScale * rng:NextNumber(0.96, 1.04), 0.55, 1.25)
	sound.Volume = math.clamp((tonumber(sound.Volume) or 0.5) * volumeScale, 0, 2)
	sound.EmitterSize = math.max(6 * emitterScale, tonumber(sound.EmitterSize) or 0)
	sound.RollOffMinDistance = math.max(5 * emitterScale, tonumber(sound.RollOffMinDistance) or 0)
	sound.RollOffMaxDistance = math.max(55 * emitterScale, tonumber(sound.RollOffMaxDistance) or 0)
	configureReverb(sound, resolvedScale)
end

local function cleanupEmitterAfterPlayback(emitter: BasePart, sound: Sound)
	local cleanedUp = false
	local function cleanup()
		if cleanedUp then
			return
		end

		cleanedUp = true
		if emitter.Parent ~= nil then
			emitter:Destroy()
		end
	end

	local endedConnection: RBXScriptConnection? = nil
	endedConnection = sound.Ended:Connect(function()
		if endedConnection then
			endedConnection:Disconnect()
			endedConnection = nil
		end
		cleanup()
	end)

	local cleanupSeconds = DEFAULT_CLEANUP_SECONDS
	if sound.TimeLength > 0 then
		cleanupSeconds = (sound.TimeLength / math.max(0.001, sound.PlaybackSpeed)) + 0.35
	end

	task.delay(cleanupSeconds, function()
		if endedConnection then
			endedConnection:Disconnect()
			endedConnection = nil
		end
		cleanup()
	end)
end

local function playFootstep(state: CharacterState, material: Enum.Material, scaleMultiplier: number)
	local sounds = resolveSoundsForGroup(resolveSoundGroupName(material))
	if #sounds <= 0 then
		return
	end

	local footPart = resolveFootPart(state.model, state.nextLeftFoot)
	state.nextLeftFoot = not state.nextLeftFoot

	local sourceSound = sounds[rng:NextInteger(1, #sounds)]
	local stepPosition = if footPart then footPart.Position else state.rootPart.Position
	local emitter = createEmitter(stepPosition, scaleMultiplier)
	local sound = sourceSound:Clone()
	sound.TimePosition = 0
	sound.Looped = false
	configureSpatialSound(sound, scaleMultiplier)
	sound.Parent = emitter
	sound:Play()
	cleanupEmitterAfterPlayback(emitter, sound)
end

local function updateState(state: CharacterState, now: number, dt: number)
	if state.model.Parent == nil or state.humanoid.Parent == nil or state.rootPart.Parent == nil then
		removeTrackedModel(state.model)
		return
	end

	if state.humanoid.Health <= 0 then
		return
	end

	local maxDistance = if state.isBoss then MAX_BOSS_TRACK_DISTANCE_STUDS else MAX_TRACK_DISTANCE_STUDS
	if resolveListenerDistance(state.rootPart) > maxDistance then
		state.lastPosition = state.rootPart.Position
		state.distanceAccumulator = 0
		return
	end

	local material = state.humanoid.FloorMaterial
	if material == Enum.Material.Air then
		state.lastPosition = state.rootPart.Position
		state.distanceAccumulator = 0
		return
	end

	local currentPosition = state.rootPart.Position
	local previousPosition = state.lastPosition
	state.lastPosition = currentPosition
	if previousPosition == nil then
		return
	end

	local planarDelta = Vector3.new(currentPosition.X - previousPosition.X, 0, currentPosition.Z - previousPosition.Z)
	local deltaMagnitude = planarDelta.Magnitude
	if deltaMagnitude > TELEPORT_DELTA_RESET_STUDS then
		state.distanceAccumulator = 0
		return
	end

	local velocity = state.rootPart.AssemblyLinearVelocity
	local planarSpeed = math.max(Vector3.new(velocity.X, 0, velocity.Z).Magnitude, deltaMagnitude / math.max(dt, 0.001))
	if planarSpeed < WALK_SPEED_THRESHOLD then
		return
	end

	local scaleMultiplier = resolveActorScale(state)
	local stepDistance = BASE_STEP_DISTANCE_STUDS * math.clamp(scaleMultiplier ^ 0.35, 0.75, 1.7)
	state.distanceAccumulator += deltaMagnitude
	if state.distanceAccumulator < stepDistance or now < state.nextStepAt then
		return
	end

	state.distanceAccumulator = math.fmod(state.distanceAccumulator, stepDistance)
	local nextInterval = math.clamp(stepDistance / math.max(planarSpeed, 0.001), MIN_STEP_INTERVAL_SECONDS, MAX_STEP_INTERVAL_SECONDS)
	state.nextStepAt = now + nextInterval
	playFootstep(state, material, scaleMultiplier)
end

local function trackModel(model: Model, isBoss: boolean)
	if trackedStatesByModel[model] ~= nil then
		return
	end

	local humanoid = resolveHumanoid(model)
	local rootPart = resolveRootPart(model)
	if humanoid == nil or rootPart == nil then
		return
	end

	local state: CharacterState = {
		model = model,
		humanoid = humanoid,
		rootPart = rootPart,
		isBoss = isBoss,
		nextLeftFoot = true,
		lastPosition = rootPart.Position,
		distanceAccumulator = 0,
		nextStepAt = 0,
		connections = {},
	}

	table.insert(state.connections, model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			removeTrackedModel(model)
		end
	end))
	table.insert(state.connections, humanoid.Died:Connect(function()
		removeTrackedModel(model)
	end))

	trackedStatesByModel[model] = state
end

local function trackCharacterWhenReady(character: Model, isBoss: boolean)
	task.spawn(function()
		local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
		local rootPart = resolveRootPart(character) or character:WaitForChild("HumanoidRootPart", 10)
		if not (humanoid and humanoid:IsA("Humanoid") and rootPart and rootPart:IsA("BasePart")) then
			return
		end

		trackModel(character, isBoss)
	end)
end

local function bindPlayer(player: Player)
	if playerConnections[player] ~= nil then
		return
	end

	local connections = {}
	playerConnections[player] = connections
	table.insert(connections, player.CharacterAdded:Connect(function(character)
		trackCharacterWhenReady(character, false)
	end))

	if player.Character then
		trackCharacterWhenReady(player.Character, false)
	end
end

local function unbindPlayer(player: Player)
	local connections = playerConnections[player]
	if connections then
		for _, connection in ipairs(connections) do
			if connection.Connected then
				connection:Disconnect()
			end
		end
	end
	playerConnections[player] = nil

	if player.Character then
		removeTrackedModel(player.Character)
	end
end

local function bindActiveBoss(model: Instance?)
	if model and model:IsA("Model") and model.Name == ACTIVE_BOSS_MODEL_NAME then
		trackCharacterWhenReady(model, true)
	end
end

function FootstepController:OnStart()
	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end

	table.insert(workspaceConnections, Players.PlayerAdded:Connect(bindPlayer))
	table.insert(workspaceConnections, Players.PlayerRemoving:Connect(unbindPlayer))
	table.insert(workspaceConnections, Workspace.ChildAdded:Connect(bindActiveBoss))
	table.insert(workspaceConnections, Workspace.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			removeTrackedModel(child)
		end
	end))

	bindActiveBoss(Workspace:FindFirstChild(ACTIVE_BOSS_MODEL_NAME))

	if heartbeatConnection then
		heartbeatConnection:Disconnect()
	end

	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for _, state in pairs(trackedStatesByModel) do
			updateState(state, now, dt)
		end
	end)
end

return FootstepController
