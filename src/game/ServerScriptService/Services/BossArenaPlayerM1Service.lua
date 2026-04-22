local HttpService = game:GetService("HttpService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BossArenaRuntimeService = require(script.Parent.BossArenaRuntimeService)
local RequestLimiter = require(script.Parent.Common.RequestLimiter)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local PlayerM1Config = require(ReplicatedStorage.Shared.BossArena.PlayerM1Config)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local REMOTES_FOLDER_NAME = "Remotes"
local BOSS_ARENA_FOLDER_NAME = "BossArena"
local REQUEST_M1_REMOTE_NAME = "RequestPlayerM1"
local ACTIVE_PROFILE_ID = "boss_arena"
local REQUEST_RATE_LIMIT_KEY = "remote.boss_arena.player_m1"
local IMPACT_MARKER_NAME = "Impact"
local M1_FOLDER_NAME = "M1"
local ACTIVE_MINIONS_FOLDER_NAME = "ActiveBossMinions"
local BOSS_INVULNERABLE_ATTRIBUTE = "BossM1Invulnerable"

type SwingState = {
	swingId: string,
	character: Model,
	humanoid: Humanoid,
	startedAt: number,
}

type PlayerConnections = {
	characterAdded: RBXScriptConnection?,
	died: RBXScriptConnection?,
}

local remotesFolder: Folder? = nil
local bossArenaFolder: Folder? = nil
local requestM1Remote: RemoteFunction? = nil
local animationFolderCache: Folder? = nil
local animationListCache: { Animation }? = nil
local impactDelayCache: { [string]: number } = {}
local activeSwingByPlayer: { [Player]: SwingState } = {}
local cooldownEndsAtByPlayer: { [Player]: number } = {}
local playerConnections: { [Player]: PlayerConnections } = {}

local BossArenaPlayerM1Service = {
	_started = false,
	_disconnectEncounterStateListener = nil :: (() -> ())?,
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
end

local function warnWithPrefix(message: string)
	warn(string.format("[BossArenaPlayerM1Service] %s", message))
end

local function disconnectConnection(connection: RBXScriptConnection?)
	if connection and connection.Connected then
		connection:Disconnect()
	end
end

local function clearSwingState(player: Player)
	activeSwingByPlayer[player] = nil
	cooldownEndsAtByPlayer[player] = nil
end

local function resolveHumanoid(model: Model?): Humanoid?
	if model == nil then
		return nil
	end

	return model:FindFirstChildOfClass("Humanoid")
end

local function resolveRootPart(model: Model?, humanoid: Humanoid?): BasePart?
	if model == nil then
		return nil
	end

	if humanoid and humanoid.RootPart and humanoid.RootPart:IsA("BasePart") then
		return humanoid.RootPart
	end

	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function ensureRemotesFolder(): Folder
	if remotesFolder and remotesFolder.Parent == ReplicatedStorage then
		return remotesFolder
	end

	local existing = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		remotesFolder = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = REMOTES_FOLDER_NAME
	folder.Parent = ReplicatedStorage
	remotesFolder = folder
	return folder
end

local function ensureBossArenaFolder(): Folder
	local folder = ensureRemotesFolder()
	if bossArenaFolder and bossArenaFolder.Parent == folder then
		return bossArenaFolder
	end

	local existing = folder:FindFirstChild(BOSS_ARENA_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		bossArenaFolder = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local bossFolder = Instance.new("Folder")
	bossFolder.Name = BOSS_ARENA_FOLDER_NAME
	bossFolder.Parent = folder
	bossArenaFolder = bossFolder
	return bossFolder
end

local function ensureRequestM1Remote(): RemoteFunction
	local folder = ensureBossArenaFolder()
	if requestM1Remote and requestM1Remote.Parent == folder then
		return requestM1Remote
	end

	local existing = folder:FindFirstChild(REQUEST_M1_REMOTE_NAME)
	if existing and existing:IsA("RemoteFunction") then
		requestM1Remote = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = REQUEST_M1_REMOTE_NAME
	remote.Parent = folder
	requestM1Remote = remote
	return remote
end

local function resolveAnimationFolder(): Folder?
	if animationFolderCache and animationFolderCache.Parent ~= nil then
		return animationFolderCache
	end

	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	local animations = gameAssets and gameAssets:FindFirstChild("Animations")
	local m1Folder = animations and animations:FindFirstChild(M1_FOLDER_NAME)
	if m1Folder and m1Folder:IsA("Folder") then
		animationFolderCache = m1Folder
		return m1Folder
	end

	return nil
end

local function getM1Animations(): { Animation }
	if animationListCache then
		return animationListCache
	end

	local folder = resolveAnimationFolder()
	local animations = {}
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Animation") then
				table.insert(animations, child)
			end
		end
	end

	animationListCache = animations
	return animations
end

local function resolveImpactDelaySeconds(animationInstance: Animation): number?
	local cacheKey = animationInstance.AnimationId
	local cached = impactDelayCache[cacheKey]
	if cached ~= nil then
		return cached
	end

	local ok, keyframeSequence = pcall(function()
		return KeyframeSequenceProvider:GetKeyframeSequenceAsync(animationInstance.AnimationId)
	end)
	if not ok or keyframeSequence == nil then
		warnWithPrefix(string.format(
			"Failed to resolve keyframes for animation '%s': %s",
			animationInstance.Name,
			tostring(keyframeSequence)
		))
		return nil
	end

	for _, keyframe in ipairs(keyframeSequence:GetKeyframes()) do
		for _, marker in ipairs(keyframe:GetMarkers()) do
			if marker.Name == IMPACT_MARKER_NAME then
				impactDelayCache[cacheKey] = keyframe.Time
				return keyframe.Time
			end
		end
	end

	return nil
end

local function chooseAnimation(): Animation?
	local animations = getM1Animations()
	if #animations <= 0 then
		return nil
	end

	local index = math.random(1, #animations)
	return animations[index]
end

local function averageBasePartSizes(root: Instance, blacklist: { [string]: boolean }?): (Vector3?, number)
	local sum = Vector3.zero
	local count = 0

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") and (not blacklist or blacklist[descendant.Name] ~= true) then
			sum += descendant.Size
			count += 1
		end
	end

	if count <= 0 then
		return nil, 0
	end

	return sum / count, count
end

local function resolveAveragePartSize(character: Model, rootPart: BasePart): Vector3
	local bodyPartFolder = character:FindFirstChild("CharacterBodyParts")
	if bodyPartFolder then
		local averageFromBodyParts = averageBasePartSizes(bodyPartFolder)
		if averageFromBodyParts ~= nil then
			return averageFromBodyParts
		end
	end

	local averageFromCharacter = averageBasePartSizes(character, {
		HumanoidRootPart = true,
		HitboxVisualizer = true,
	})
	if averageFromCharacter ~= nil then
		return averageFromCharacter
	end

	return rootPart.Size
end

local function resolveHitboxSizeAndForwardOffset(character: Model, rootPart: BasePart): (Vector3, number)
	local averagePartSize = resolveAveragePartSize(character, rootPart)
	local hitboxSize = Vector3.new(
		math.max(1, averagePartSize.X * PlayerM1Config.WidthScale),
		math.max(1, averagePartSize.Y * PlayerM1Config.HeightScale),
		math.max(1, averagePartSize.Z * PlayerM1Config.DepthScale)
	)
	local forwardOffset = math.max(rootPart.Size.Z * 0.5, hitboxSize.Z * PlayerM1Config.ForwardOffsetScale)

	return hitboxSize, forwardOffset
end

local function buildSuccessResponse(swingId: string, animationInstance: Animation, impactDelaySeconds: number): { [string]: any }
	return {
		ok = true,
		swingId = swingId,
		animationName = animationInstance.Name,
		serverStartedAt = Workspace:GetServerTimeNow(),
		impactDelaySeconds = impactDelaySeconds,
		cooldownSeconds = PlayerM1Config.CooldownSeconds,
	}
end

local function buildFailureResponse(code: string, retryAfterSeconds: number?): { [string]: any }
	return {
		ok = false,
		code = code,
		retryAfterSeconds = retryAfterSeconds,
	}
end

local function isActiveBossMinion(model: Model): boolean
	local activeMinionsFolder = Workspace:FindFirstChild(ACTIVE_MINIONS_FOLDER_NAME)
	return activeMinionsFolder ~= nil and model.Parent == activeMinionsFolder
end

function BossArenaPlayerM1Service:_bindCharacter(player: Player, character: Model)
	local connections = playerConnections[player]
	if connections == nil then
		return
	end

	clearSwingState(player)
	disconnectConnection(connections.died)
	connections.died = nil

	local humanoid = resolveHumanoid(character)
	if humanoid then
		connections.died = humanoid.Died:Connect(function()
			clearSwingState(player)
		end)
	end
end

function BossArenaPlayerM1Service:_clearAllSwingState()
	for player in pairs(activeSwingByPlayer) do
		clearSwingState(player)
	end
end

function BossArenaPlayerM1Service:_spawnHitboxForSwing(player: Player, swingId: string)
	local swingState = activeSwingByPlayer[player]
	if swingState == nil or swingState.swingId ~= swingId then
		return
	end

	local character = player.Character
	local humanoid = resolveHumanoid(character)
	local rootPart = resolveRootPart(character, humanoid)
	local bossModel = BossArenaRuntimeService:GetActiveBossModel()
	local bossHumanoid = resolveHumanoid(bossModel)
	if character == nil or humanoid == nil or humanoid.Health <= 0 or rootPart == nil then
		clearSwingState(player)
		return
	end
	if bossModel == nil or bossHumanoid == nil or bossHumanoid.Health <= 0 then
		clearSwingState(player)
		return
	end

	local hitboxSize, forwardOffset = resolveHitboxSizeAndForwardOffset(character, rootPart)
	local damagedTarget = false
	local hitbox
	hitbox = Hitbox.new({
		Character = character,
		HitboxCFrame = function()
			if rootPart.Parent == nil then
				return nil
			end
			return rootPart.CFrame
		end,
		HitboxOffset = CFrame.new(0, 0, -forwardOffset),
		HitboxSize = hitboxSize,
		HitboxType = "SpacialQuery",
		Time = PlayerM1Config.HitboxDurationSeconds,
		MaxParts = PlayerM1Config.MaxParts,
	}, {
		HitTarget = function(targetModel: Model)
			if damagedTarget or bossHumanoid.Health <= 0 then
				return
			end

			local targetHumanoid = nil :: Humanoid?
			if targetModel == bossModel then
				if bossModel:GetAttribute(BOSS_INVULNERABLE_ATTRIBUTE) == true then
					return
				end
				targetHumanoid = bossHumanoid
			elseif isActiveBossMinion(targetModel) then
				targetHumanoid = resolveHumanoid(targetModel)
			else
				return
			end
			if targetHumanoid == nil or targetHumanoid.Health <= 0 then
				return
			end

			damagedTarget = true
			targetHumanoid:TakeDamage(PlayerM1Config.Damage)
		end,
		HitboxDestroy = function()
			if activeSwingByPlayer[player] == swingState then
				activeSwingByPlayer[player] = nil
			end
		end,
	})

	task.delay(PlayerM1Config.HitboxDurationSeconds + 0.05, function()
		if activeSwingByPlayer[player] == swingState then
			activeSwingByPlayer[player] = nil
		end
	end)
end

function BossArenaPlayerM1Service:_handleRequest(player: Player): { [string]: any }
	local allowed, retryAfterSeconds = RequestLimiter:Allow(player, REQUEST_RATE_LIMIT_KEY)
	if not allowed then
		return buildFailureResponse("RATE_LIMITED", retryAfterSeconds)
	end

	if not isEnabledForPlace() then
		return buildFailureResponse("DISABLED")
	end

	local now = Workspace:GetServerTimeNow()
	local cooldownEndsAt = cooldownEndsAtByPlayer[player]
	if cooldownEndsAt and now < cooldownEndsAt then
		return buildFailureResponse("COOLDOWN", cooldownEndsAt - now)
	end

	if activeSwingByPlayer[player] ~= nil then
		return buildFailureResponse("ACTIVE_SWING")
	end

	local bossModel = BossArenaRuntimeService:GetActiveBossModel()
	local bossHumanoid = resolveHumanoid(bossModel)
	if bossModel == nil or bossHumanoid == nil or bossHumanoid.Health <= 0 then
		return buildFailureResponse("NO_ACTIVE_BOSS")
	end

	local character = player.Character
	local humanoid = resolveHumanoid(character)
	local rootPart = resolveRootPart(character, humanoid)
	if character == nil or humanoid == nil or humanoid.Health <= 0 or rootPart == nil then
		return buildFailureResponse("INVALID_CHARACTER")
	end

	local animationInstance = chooseAnimation()
	if animationInstance == nil then
		warnWithPrefix("No animations exist under ReplicatedStorage.GameAssets.Animations.M1.")
		return buildFailureResponse("MISSING_ANIMATION")
	end

	local impactDelaySeconds = resolveImpactDelaySeconds(animationInstance)
	if impactDelaySeconds == nil then
		warnWithPrefix(string.format(
			"Animation '%s' is missing the '%s' marker.",
			animationInstance.Name,
			IMPACT_MARKER_NAME
		))
		return buildFailureResponse("MISSING_IMPACT_MARKER")
	end

	local swingId = HttpService:GenerateGUID(false)
	local swingState = {
		swingId = swingId,
		character = character,
		humanoid = humanoid,
		startedAt = now,
	}

	activeSwingByPlayer[player] = swingState
	cooldownEndsAtByPlayer[player] = now + PlayerM1Config.CooldownSeconds

	task.delay(impactDelaySeconds, function()
		self:_spawnHitboxForSwing(player, swingId)
	end)

	task.delay(math.max(PlayerM1Config.CooldownSeconds, impactDelaySeconds + PlayerM1Config.HitboxDurationSeconds) + 0.1, function()
		if activeSwingByPlayer[player] == swingState then
			activeSwingByPlayer[player] = nil
		end
	end)

	return buildSuccessResponse(swingId, animationInstance, impactDelaySeconds)
end

function BossArenaPlayerM1Service:OnStart()
	if self._started then
		return
	end
	self._started = true

	if not isEnabledForPlace() then
		return
	end

	local requestRemote = ensureRequestM1Remote()
	requestRemote.OnServerInvoke = function(player: Player)
		return self:_handleRequest(player)
	end

	self._disconnectEncounterStateListener = BossArenaRuntimeService:ConnectEncounterStateChanged(function(activeBossId: string?)
		if activeBossId == nil then
			self:_clearAllSwingState()
		end
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		self:OnPlayerAdded(player)
	end
end

function BossArenaPlayerM1Service:OnPlayerAdded(player: Player)
	if not isEnabledForPlace() then
		return
	end

	local connections = playerConnections[player]
	if connections == nil then
		connections = {}
		playerConnections[player] = connections
	end

	disconnectConnection(connections.characterAdded)
	disconnectConnection(connections.died)

	connections.characterAdded = player.CharacterAdded:Connect(function(character: Model)
		self:_bindCharacter(player, character)
	end)
	connections.died = nil

	if player.Character then
		self:_bindCharacter(player, player.Character)
	end
end

function BossArenaPlayerM1Service:OnPlayerRemoving(player: Player)
	local connections = playerConnections[player]
	if connections then
		disconnectConnection(connections.characterAdded)
		disconnectConnection(connections.died)
		playerConnections[player] = nil
	end

	clearSwingState(player)
end

return BossArenaPlayerM1Service
