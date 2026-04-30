local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local HttpService = game:GetService("HttpService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local PlayerM1AnimationResolver = require(ReplicatedStorage.Shared.BossArena.PlayerM1AnimationResolver)
local PlayerM1Config = require(ReplicatedStorage.Shared.BossArena.PlayerM1Config)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)
local PlayerLoadoutStatsService = require(script.Parent.PlayerLoadoutStatsService)
local RequestLimiter = require(script.Parent.Common.RequestLimiter)

local ACTIVE_PROFILE_ID = "main"
local REMOTES_FOLDER_NAME = "Remotes"
local PVP_FOLDER_NAME = "PvP"
local GET_PVP_STATE_REMOTE_NAME = "GetPvpState"
local SET_PVP_ENABLED_REMOTE_NAME = "SetPvpEnabled"
local REQUEST_M1_REMOTE_NAME = "RequestPlayPerM1"
local PVP_STATE_CHANGED_REMOTE_NAME = "PvpStateChanged"
local PLAYER_M1_STARTED_REMOTE_NAME = "PlayerM1Started"
local PLAYER_HIT_CONFIRMED_REMOTE_NAME = "PlayerHitConfirmed"
local SET_ENABLED_RATE_LIMIT_KEY = "remote.pvp.set_enabled"
local REQUEST_M1_RATE_LIMIT_KEY = "remote.pvp.player_m1"
local IMPACT_MARKER_NAME = "Impact"

type PlayerHealthEntry = {
	userId: number,
	username: string,
	currentHealth: number,
	maxHealth: number,
	alive: boolean,
}

type PvpState = {
	enabled: boolean,
	active: boolean,
	roster: { PlayerHealthEntry },
	serverTime: number,
}

type SwingState = {
	swingId: string,
	character: Model,
	humanoid: Humanoid,
	startedAt: number,
}

type PlayerConnections = {
	characterAdded: RBXScriptConnection?,
	characterRemoving: RBXScriptConnection?,
	died: RBXScriptConnection?,
	healthChanged: RBXScriptConnection?,
	maxHealthChanged: RBXScriptConnection?,
}

local remotesFolder: Folder? = nil
local pvpFolder: Folder? = nil
local getPvpStateRemote: RemoteFunction? = nil
local setPvpEnabledRemote: RemoteFunction? = nil
local requestM1Remote: RemoteFunction? = nil
local pvpStateChangedRemote: RemoteEvent? = nil
local playerM1StartedRemote: RemoteEvent? = nil
local playerHitConfirmedRemote: RemoteEvent? = nil
local impactDelayCache: { [string]: number } = {}
local pvpEnabledByPlayer: { [Player]: boolean } = {}
local activeSwingByPlayer: { [Player]: SwingState } = {}
local cooldownEndsAtByPlayer: { [Player]: number } = {}
local playerConnections: { [Player]: PlayerConnections } = {}

local PvpService = {
	_started = false,
	_broadcastScheduled = false,
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
end

local function warnWithPrefix(message: string)
	Logger.Warn(string.format("[PvpService] %s", message))
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

local function ensurePvpFolder(): Folder
	local folder = ensureRemotesFolder()
	if pvpFolder and pvpFolder.Parent == folder then
		return pvpFolder
	end

	local existing = folder:FindFirstChild(PVP_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		pvpFolder = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local created = Instance.new("Folder")
	created.Name = PVP_FOLDER_NAME
	created.Parent = folder
	pvpFolder = created
	return created
end

local function ensureRemoteFunction(cached: RemoteFunction?, name: string): RemoteFunction
	local folder = ensurePvpFolder()
	if cached and cached.Parent == folder then
		return cached
	end

	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local function ensureRemoteEvent(cached: RemoteEvent?, name: string): RemoteEvent
	local folder = ensurePvpFolder()
	if cached and cached.Parent == folder then
		return cached
	end

	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local function ensureGetPvpStateRemote(): RemoteFunction
	getPvpStateRemote = ensureRemoteFunction(getPvpStateRemote, GET_PVP_STATE_REMOTE_NAME)
	return getPvpStateRemote
end

local function ensureSetPvpEnabledRemote(): RemoteFunction
	setPvpEnabledRemote = ensureRemoteFunction(setPvpEnabledRemote, SET_PVP_ENABLED_REMOTE_NAME)
	return setPvpEnabledRemote
end

local function ensureRequestM1Remote(): RemoteFunction
	requestM1Remote = ensureRemoteFunction(requestM1Remote, REQUEST_M1_REMOTE_NAME)
	return requestM1Remote
end

local function ensurePvpStateChangedRemote(): RemoteEvent
	pvpStateChangedRemote = ensureRemoteEvent(pvpStateChangedRemote, PVP_STATE_CHANGED_REMOTE_NAME)
	return pvpStateChangedRemote
end

local function ensurePlayerM1StartedRemote(): RemoteEvent
	playerM1StartedRemote = ensureRemoteEvent(playerM1StartedRemote, PLAYER_M1_STARTED_REMOTE_NAME)
	return playerM1StartedRemote
end

local function ensurePlayerHitConfirmedRemote(): RemoteEvent
	playerHitConfirmedRemote = ensureRemoteEvent(playerHitConfirmedRemote, PLAYER_HIT_CONFIRMED_REMOTE_NAME)
	return playerHitConfirmedRemote
end

local function getM1Animations(): { Animation }
	return PlayerM1AnimationResolver.GetAnimations()
end

local function resolvePredictedAnimation(predictedAnimationName: any): Animation?
	return PlayerM1AnimationResolver.FindAnimation(predictedAnimationName)
end

local function chooseAnimation(): Animation?
	local animations = getM1Animations()
	if #animations <= 0 then
		return nil
	end

	return animations[math.random(1, #animations)]
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

local function warmImpactDelayCache()
	task.defer(function()
		for _, animationInstance in ipairs(getM1Animations()) do
			resolveImpactDelaySeconds(animationInstance)
		end
	end)
end

local function averageBasePartSizes(root: Instance, blacklist: { [string]: boolean }?): Vector3?
	local sum = Vector3.zero
	local count = 0

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") and (not blacklist or blacklist[descendant.Name] ~= true) then
			sum += descendant.Size
			count += 1
		end
	end

	if count <= 0 then
		return nil
	end

	return sum / count
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
		PlayerM1Config.HitboxHeightStuds,
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

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	if character == nil then
		return nil
	end

	return character:FindFirstChildOfClass("Humanoid")
end

local function buildHealthEntry(player: Player): PlayerHealthEntry?
	local humanoid = getHumanoid(player)
	local maxHealth = 100
	local currentHealth = 0
	local alive = false

	if humanoid then
		maxHealth = math.max(1, tonumber(humanoid.MaxHealth) or 100)
		currentHealth = math.clamp(tonumber(humanoid.Health) or 0, 0, maxHealth)
		alive = currentHealth > 0
	end

	return {
		userId = player.UserId,
		username = player.Name,
		currentHealth = currentHealth,
		maxHealth = maxHealth,
		alive = alive,
	}
end

function PvpService:_buildStateForPlayer(player: Player): PvpState
	local enabled = pvpEnabledByPlayer[player] == true
	local roster = {}

	if enabled then
		for _, rosterPlayer in ipairs(Players:GetPlayers()) do
			if pvpEnabledByPlayer[rosterPlayer] == true then
				local entry = buildHealthEntry(rosterPlayer)
				if entry then
					table.insert(roster, entry)
				end
			end
		end
	end

	return {
		enabled = enabled,
		active = enabled,
		roster = roster,
		serverTime = Workspace:GetServerTimeNow(),
	}
end

function PvpService:_broadcastPvpState()
	local remote = ensurePvpStateChangedRemote()
	for _, player in ipairs(Players:GetPlayers()) do
		remote:FireClient(player, self:_buildStateForPlayer(player))
	end
end

function PvpService:_schedulePvpStateBroadcast()
	if self._broadcastScheduled then
		return
	end

	self._broadcastScheduled = true
	task.defer(function()
		self._broadcastScheduled = false
		if self._started ~= true or not isEnabledForPlace() then
			return
		end

		self:_broadcastPvpState()
	end)
end

function PvpService:_setPvpEnabled(player: Player, enabled: boolean)
	local nextEnabled = enabled == true
	if pvpEnabledByPlayer[player] == nextEnabled then
		return
	end

	pvpEnabledByPlayer[player] = if nextEnabled then true else nil
	clearSwingState(player)
	self:_schedulePvpStateBroadcast()
end

local function resolvePlayerM1Damage(player: Player): number
	local stats = PlayerLoadoutStatsService:GetFinalStats(player)
	local damage = tonumber(stats and stats.damage) or PlayerM1Config.Damage
	return math.max(0, damage)
end

function PvpService:_bindHumanoid(player: Player, humanoid: Humanoid)
	local connections = playerConnections[player]
	if connections == nil then
		return
	end

	disconnectConnection(connections.died)
	disconnectConnection(connections.healthChanged)
	disconnectConnection(connections.maxHealthChanged)

	connections.died = humanoid.Died:Connect(function()
		self:_setPvpEnabled(player, false)
	end)
	connections.healthChanged = humanoid.HealthChanged:Connect(function()
		self:_schedulePvpStateBroadcast()
	end)
	connections.maxHealthChanged = humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		self:_schedulePvpStateBroadcast()
	end)
end

function PvpService:_bindCharacter(player: Player, character: Model)
	clearSwingState(player)
	self:_setPvpEnabled(player, false)

	local humanoid = resolveHumanoid(character)
	if humanoid then
		self:_bindHumanoid(player, humanoid)
	end

	self:_schedulePvpStateBroadcast()
end

function PvpService:_spawnHitboxForSwing(player: Player, swingId: string)
	local swingState = activeSwingByPlayer[player]
	if swingState == nil or swingState.swingId ~= swingId then
		return
	end

	if pvpEnabledByPlayer[player] ~= true then
		clearSwingState(player)
		return
	end

	local character = player.Character
	local humanoid = resolveHumanoid(character)
	local rootPart = resolveRootPart(character, humanoid)
	if character == nil or humanoid == nil or humanoid.Health <= 0 or rootPart == nil then
		clearSwingState(player)
		return
	end

	local hitboxSize, forwardOffset = resolveHitboxSizeAndForwardOffset(character, rootPart)
	local damagedTarget = false
	Hitbox.new({
		Character = character,
		AllowFriendlyFire = true,
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
			if damagedTarget then
				return
			end

			local targetPlayer = Players:GetPlayerFromCharacter(targetModel)
			if targetPlayer == nil or targetPlayer == player or pvpEnabledByPlayer[targetPlayer] ~= true then
				return
			end

			local targetHumanoid = resolveHumanoid(targetModel)
			if targetHumanoid == nil or targetHumanoid.Health <= 0 then
				return
			end

			local damage = resolvePlayerM1Damage(player)
			if damage <= 0 then
				return
			end

			targetHumanoid:TakeDamage(damage)
			damagedTarget = true
			local targetRootPart = resolveRootPart(targetModel, targetHumanoid)
			ensurePlayerHitConfirmedRemote():FireAllClients({
				attacker = player,
				attackerUserId = player.UserId,
				target = targetPlayer,
				targetUserId = targetPlayer.UserId,
				damage = damage,
				serverTime = Workspace:GetServerTimeNow(),
				position = rootPart.Position,
				targetPosition = if targetRootPart then targetRootPart.Position else nil,
			})
			self:_schedulePvpStateBroadcast()
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

function PvpService:_handleSetPvpEnabled(player: Player, payload: any): { [string]: any }
	local allowed, retryAfterSeconds = RequestLimiter:Allow(player, SET_ENABLED_RATE_LIMIT_KEY)
	if not allowed then
		return {
			ok = false,
			code = "RATE_LIMITED",
			retryAfterSeconds = retryAfterSeconds,
			state = self:_buildStateForPlayer(player),
		}
	end

	if not isEnabledForPlace() then
		return {
			ok = false,
			code = "DISABLED",
			state = self:_buildStateForPlayer(player),
		}
	end

	local requestedEnabled = typeof(payload) == "table" and payload.enabled == true
	local character = player.Character
	local humanoid = resolveHumanoid(character)
	if requestedEnabled and (character == nil or humanoid == nil or humanoid.Health <= 0) then
		return {
			ok = false,
			code = "INVALID_CHARACTER",
			state = self:_buildStateForPlayer(player),
		}
	end

	self:_setPvpEnabled(player, requestedEnabled)
	return {
		ok = true,
		state = self:_buildStateForPlayer(player),
	}
end

function PvpService:_handleRequestM1(player: Player, predictedAnimationName: any): { [string]: any }
	local allowed, retryAfterSeconds = RequestLimiter:Allow(player, REQUEST_M1_RATE_LIMIT_KEY)
	if not allowed then
		return buildFailureResponse("RATE_LIMITED", retryAfterSeconds)
	end

	if not isEnabledForPlace() then
		return buildFailureResponse("DISABLED")
	end
	if pvpEnabledByPlayer[player] ~= true then
		return buildFailureResponse("PVP_DISABLED")
	end

	local now = Workspace:GetServerTimeNow()
	local cooldownEndsAt = cooldownEndsAtByPlayer[player]
	if cooldownEndsAt and now < cooldownEndsAt then
		return buildFailureResponse("COOLDOWN", cooldownEndsAt - now)
	end

	if activeSwingByPlayer[player] ~= nil then
		return buildFailureResponse("ACTIVE_SWING")
	end

	local character = player.Character
	local humanoid = resolveHumanoid(character)
	local rootPart = resolveRootPart(character, humanoid)
	if character == nil or humanoid == nil or humanoid.Health <= 0 or rootPart == nil then
		return buildFailureResponse("INVALID_CHARACTER")
	end

	local animationInstance = resolvePredictedAnimation(predictedAnimationName) or chooseAnimation()
	if animationInstance == nil then
		warnWithPrefix("No animations exist under ReplicatedStorage.GameAssets.Animations.Bosses.M1 or ReplicatedStorage.GameAssets.Animations.M1.")
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

	ensurePlayerM1StartedRemote():FireAllClients({
		player = player,
		userId = player.UserId,
		swingId = swingId,
		animationName = animationInstance.Name,
		serverStartedAt = now,
		impactDelaySeconds = impactDelaySeconds,
		position = rootPart.Position,
	})

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

function PvpService:OnStart()
	if self._started then
		return
	end
	self._started = true

	if not isEnabledForPlace() then
		return
	end

	ensurePvpStateChangedRemote()
	ensurePlayerM1StartedRemote()
	ensurePlayerHitConfirmedRemote()

	local getStateRemote = ensureGetPvpStateRemote()
	getStateRemote.OnServerInvoke = function(player: Player)
		return self:_buildStateForPlayer(player)
	end

	local setEnabledRemote = ensureSetPvpEnabledRemote()
	setEnabledRemote.OnServerInvoke = function(player: Player, payload: any)
		return self:_handleSetPvpEnabled(player, payload)
	end

	local requestRemote = ensureRequestM1Remote()
	requestRemote.OnServerInvoke = function(player: Player, predictedAnimationName: any)
		return self:_handleRequestM1(player, predictedAnimationName)
	end

	warmImpactDelayCache()
	self:_schedulePvpStateBroadcast()
end

function PvpService:OnPlayerAdded(player: Player)
	if not isEnabledForPlace() then
		return
	end

	local connections = playerConnections[player]
	if connections == nil then
		connections = {}
		playerConnections[player] = connections
	end

	pvpEnabledByPlayer[player] = nil
	clearSwingState(player)

	disconnectConnection(connections.characterAdded)
	disconnectConnection(connections.characterRemoving)
	disconnectConnection(connections.died)
	disconnectConnection(connections.healthChanged)
	disconnectConnection(connections.maxHealthChanged)

	connections.characterAdded = player.CharacterAdded:Connect(function(character: Model)
		self:_bindCharacter(player, character)
	end)
	connections.characterRemoving = player.CharacterRemoving:Connect(function()
		clearSwingState(player)
		self:_setPvpEnabled(player, false)
	end)
	connections.died = nil
	connections.healthChanged = nil
	connections.maxHealthChanged = nil

	if player.Character then
		self:_bindCharacter(player, player.Character)
	else
		self:_schedulePvpStateBroadcast()
	end
end

function PvpService:OnPlayerRemoving(player: Player)
	local connections = playerConnections[player]
	if connections then
		disconnectConnection(connections.characterAdded)
		disconnectConnection(connections.characterRemoving)
		disconnectConnection(connections.died)
		disconnectConnection(connections.healthChanged)
		disconnectConnection(connections.maxHealthChanged)
		playerConnections[player] = nil
	end

	pvpEnabledByPlayer[player] = nil
	clearSwingState(player)
	self:_schedulePvpStateBroadcast()
end

return PvpService
