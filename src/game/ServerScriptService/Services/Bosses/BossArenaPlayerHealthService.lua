local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BossArenaRuntimeService = require(script.Parent.BossArenaRuntimeService)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local ACTIVE_PROFILE_ID = "boss_arena"
local DEFAULT_HEALTH_SCRIPT_NAME = "Health"
local REMOTES_FOLDER_NAME = "Remotes"
local BOSS_ARENA_FOLDER_NAME = "BossArena"
local GET_PLAYER_HEALTH_STATE_REMOTE_NAME = "GetPlayerHealthState"
local PLAYER_HEALTH_STATE_CHANGED_REMOTE_NAME = "PlayerHealthStateChanged"
local FALLBACK_MAX_HEALTH = 100

type PlayerHealthEntry = {
	userId: number,
	username: string,
	currentHealth: number,
	maxHealth: number,
	alive: boolean,
}

type PlayerHealthState = {
	active: boolean,
	roster: { PlayerHealthEntry },
	serverTime: number,
}

type PlayerState = {
	characterConnection: RBXScriptConnection?,
	characterRemovingConnection: RBXScriptConnection?,
	characterChildConnection: RBXScriptConnection?,
	humanoidHealthConnection: RBXScriptConnection?,
	humanoidMaxHealthConnection: RBXScriptConnection?,
}

local remotesFolder: Folder? = nil
local bossArenaFolder: Folder? = nil
local getPlayerHealthStateRemote: RemoteFunction? = nil
local playerHealthStateChangedRemote: RemoteEvent? = nil

local BossArenaPlayerHealthService = {
	_started = false,
	_playerStates = {} :: { [Player]: PlayerState },
	_disconnectRosterListener = nil :: (() -> ())?,
	_disconnectBossHealthListener = nil :: (() -> ())?,
	_broadcastScheduled = false,
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
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

	local created = Instance.new("Folder")
	created.Name = BOSS_ARENA_FOLDER_NAME
	created.Parent = folder
	bossArenaFolder = created
	return created
end

local function ensureGetPlayerHealthStateRemote(): RemoteFunction
	local folder = ensureBossArenaFolder()
	if getPlayerHealthStateRemote and getPlayerHealthStateRemote.Parent == folder then
		return getPlayerHealthStateRemote
	end

	local existing = folder:FindFirstChild(GET_PLAYER_HEALTH_STATE_REMOTE_NAME)
	if existing and existing:IsA("RemoteFunction") then
		getPlayerHealthStateRemote = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = GET_PLAYER_HEALTH_STATE_REMOTE_NAME
	remote.Parent = folder
	getPlayerHealthStateRemote = remote
	return remote
end

local function ensurePlayerHealthStateChangedRemote(): RemoteEvent
	local folder = ensureBossArenaFolder()
	if playerHealthStateChangedRemote and playerHealthStateChangedRemote.Parent == folder then
		return playerHealthStateChangedRemote
	end

	local existing = folder:FindFirstChild(PLAYER_HEALTH_STATE_CHANGED_REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		playerHealthStateChangedRemote = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = PLAYER_HEALTH_STATE_CHANGED_REMOTE_NAME
	remote.Parent = folder
	playerHealthStateChangedRemote = remote
	return remote
end

local function getPlayerByUserId(userId: number): Player?
	for _, player in ipairs(Players:GetPlayers()) do
		if player.UserId == userId then
			return player
		end
	end

	return nil
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	if character == nil then
		return nil
	end

	return character:FindFirstChildOfClass("Humanoid")
end

local function disableDefaultHealthScript(instance: Instance)
	if instance.Name ~= DEFAULT_HEALTH_SCRIPT_NAME or not instance:IsA("Script") then
		return
	end

	instance.Disabled = true
	instance:Destroy()
end

local function disconnectConnection(connection: RBXScriptConnection?)
	if connection then
		connection:Disconnect()
	end
end

local function isCombatHudActive(): boolean
	return BossArenaRuntimeService:GetBossHealthState() ~= nil
end

function BossArenaPlayerHealthService:_buildHealthEntry(userId: number): PlayerHealthEntry?
	local player = getPlayerByUserId(userId)
	if player == nil then
		return nil
	end

	local humanoid = getHumanoid(player)
	local maxHealth = FALLBACK_MAX_HEALTH
	local currentHealth = 0
	local alive = false

	if humanoid then
		maxHealth = math.max(1, tonumber(humanoid.MaxHealth) or FALLBACK_MAX_HEALTH)
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

function BossArenaPlayerHealthService:_buildHealthState(): PlayerHealthState
	local roster = {}
	local rosterUserIds = BossArenaRuntimeService:GetActiveRosterUserIds()

	for _, userId in ipairs(rosterUserIds) do
		local entry = self:_buildHealthEntry(userId)
		if entry then
			table.insert(roster, entry)
		end
	end

	return {
		active = isCombatHudActive(),
		roster = roster,
		serverTime = Workspace:GetServerTimeNow(),
	}
end

function BossArenaPlayerHealthService:_broadcastHealthState()
	local remote = ensurePlayerHealthStateChangedRemote()
	local state = self:_buildHealthState()

	for _, player in ipairs(Players:GetPlayers()) do
		remote:FireClient(player, state)
	end
end

function BossArenaPlayerHealthService:_scheduleHealthBroadcast()
	if self._broadcastScheduled then
		return
	end

	self._broadcastScheduled = true
	task.defer(function()
		self._broadcastScheduled = false
		if self._started ~= true or not isEnabledForPlace() then
			return
		end

		self:_broadcastHealthState()
	end)
end

function BossArenaPlayerHealthService:_getPlayerState(player: Player): PlayerState
	local state = self._playerStates[player]
	if state then
		return state
	end

	state = {
		characterConnection = nil,
		characterRemovingConnection = nil,
		characterChildConnection = nil,
		humanoidHealthConnection = nil,
		humanoidMaxHealthConnection = nil,
	}
	self._playerStates[player] = state
	return state
end

function BossArenaPlayerHealthService:_disconnectCharacterState(state: PlayerState)
	disconnectConnection(state.characterChildConnection)
	disconnectConnection(state.humanoidHealthConnection)
	disconnectConnection(state.humanoidMaxHealthConnection)

	state.characterChildConnection = nil
	state.humanoidHealthConnection = nil
	state.humanoidMaxHealthConnection = nil
end

function BossArenaPlayerHealthService:_bindHumanoid(state: PlayerState, humanoid: Humanoid)
	disconnectConnection(state.humanoidHealthConnection)
	disconnectConnection(state.humanoidMaxHealthConnection)

	state.humanoidHealthConnection = humanoid.HealthChanged:Connect(function()
		self:_scheduleHealthBroadcast()
	end)
	state.humanoidMaxHealthConnection = humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		self:_scheduleHealthBroadcast()
	end)

	self:_scheduleHealthBroadcast()
end

function BossArenaPlayerHealthService:_bindCharacter(player: Player, character: Model)
	local state = self:_getPlayerState(player)
	self:_disconnectCharacterState(state)

	for _, child in ipairs(character:GetChildren()) do
		disableDefaultHealthScript(child)
	end

	local existingHumanoid = character:FindFirstChildOfClass("Humanoid")
	if existingHumanoid then
		self:_bindHumanoid(state, existingHumanoid)
	end

	state.characterChildConnection = character.ChildAdded:Connect(function(child)
		disableDefaultHealthScript(child)
		if child:IsA("Humanoid") then
			self:_bindHumanoid(state, child)
		end
	end)

	self:_scheduleHealthBroadcast()
end

function BossArenaPlayerHealthService:OnStart()
	if self._started then
		return
	end
	self._started = true

	if not isEnabledForPlace() then
		return
	end

	local getPlayerHealthState = ensureGetPlayerHealthStateRemote()
	ensurePlayerHealthStateChangedRemote()

	getPlayerHealthState.OnServerInvoke = function(_player: Player): PlayerHealthState
		return self:_buildHealthState()
	end

	self._disconnectRosterListener = BossArenaRuntimeService:ConnectRosterStateChanged(function()
		self:_scheduleHealthBroadcast()
	end)
	self._disconnectBossHealthListener = BossArenaRuntimeService:ConnectBossHealthStateChanged(function()
		self:_scheduleHealthBroadcast()
	end)

	self:_scheduleHealthBroadcast()
	Logger.Print("[BossArenaPlayerHealthService] Ready for player health replication.")
end

function BossArenaPlayerHealthService:OnPlayerAdded(player: Player)
	if not isEnabledForPlace() then
		return
	end

	local state = self:_getPlayerState(player)
	disconnectConnection(state.characterConnection)
	disconnectConnection(state.characterRemovingConnection)

	state.characterConnection = player.CharacterAdded:Connect(function(character)
		self:_bindCharacter(player, character)
	end)
	state.characterRemovingConnection = player.CharacterRemoving:Connect(function()
		self:_disconnectCharacterState(state)
		self:_scheduleHealthBroadcast()
	end)

	if player.Character then
		self:_bindCharacter(player, player.Character)
	else
		self:_scheduleHealthBroadcast()
	end
end

function BossArenaPlayerHealthService:OnPlayerRemoving(player: Player)
	local state = self._playerStates[player]
	if not state then
		self:_scheduleHealthBroadcast()
		return
	end

	disconnectConnection(state.characterConnection)
	disconnectConnection(state.characterRemovingConnection)
	self:_disconnectCharacterState(state)
	self._playerStates[player] = nil
	self:_scheduleHealthBroadcast()
end

return BossArenaPlayerHealthService
