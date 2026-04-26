local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossArenaRuntimeService = require(script.Parent.BossArenaRuntimeService)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local REMOTES_FOLDER_NAME = "Remotes"
local BOSS_ARENA_FOLDER_NAME = "BossArena"
local GET_HEALTH_STATE_REMOTE_NAME = "GetBossHealthState"
local HEALTH_STATE_CHANGED_REMOTE_NAME = "BossHealthStateChanged"
local BOSS_HIT_CONFIRMED_REMOTE_NAME = "BossHitConfirmed"
local ACTIVE_PROFILE_ID = "boss_arena"

type BossHealthState = {
	bossId: string,
	currentHealth: number,
	maxHealth: number,
}

type BossHitConfirmedPayload = {
	bossId: string,
	damage: number,
	attackerUserId: number,
	serverTime: number,
}

local remotesFolder: Folder? = nil
local bossArenaFolder: Folder? = nil
local getHealthStateRemote: RemoteFunction? = nil
local healthStateChangedRemote: RemoteEvent? = nil
local bossHitConfirmedRemote: RemoteEvent? = nil

local BossArenaBossHealthService = {
	_started = false,
	_disconnectHealthListener = nil :: (() -> ())?,
	_disconnectHitConfirmedListener = nil :: (() -> ())?,
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

	local bossFolder = Instance.new("Folder")
	bossFolder.Name = BOSS_ARENA_FOLDER_NAME
	bossFolder.Parent = folder
	bossArenaFolder = bossFolder
	return bossFolder
end

local function ensureGetHealthStateRemote(): RemoteFunction
	local folder = ensureBossArenaFolder()
	if getHealthStateRemote and getHealthStateRemote.Parent == folder then
		return getHealthStateRemote
	end

	local existing = folder:FindFirstChild(GET_HEALTH_STATE_REMOTE_NAME)
	if existing and existing:IsA("RemoteFunction") then
		getHealthStateRemote = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = GET_HEALTH_STATE_REMOTE_NAME
	remote.Parent = folder
	getHealthStateRemote = remote
	return remote
end

local function ensureHealthStateChangedRemote(): RemoteEvent
	local folder = ensureBossArenaFolder()
	if healthStateChangedRemote and healthStateChangedRemote.Parent == folder then
		return healthStateChangedRemote
	end

	local existing = folder:FindFirstChild(HEALTH_STATE_CHANGED_REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		healthStateChangedRemote = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = HEALTH_STATE_CHANGED_REMOTE_NAME
	remote.Parent = folder
	healthStateChangedRemote = remote
	return remote
end

local function ensureBossHitConfirmedRemote(): RemoteEvent
	local folder = ensureBossArenaFolder()
	if bossHitConfirmedRemote and bossHitConfirmedRemote.Parent == folder then
		return bossHitConfirmedRemote
	end

	local existing = folder:FindFirstChild(BOSS_HIT_CONFIRMED_REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		bossHitConfirmedRemote = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = BOSS_HIT_CONFIRMED_REMOTE_NAME
	remote.Parent = folder
	bossHitConfirmedRemote = remote
	return remote
end

local function broadcastHealthStateChanged()
	local healthState = BossArenaRuntimeService:GetBossHealthState()
	local remote = ensureHealthStateChangedRemote()

	for _, player in ipairs(Players:GetPlayers()) do
		remote:FireClient(player, healthState)
	end
end

local function broadcastBossHitConfirmed(hitPayload: BossHitConfirmedPayload)
	local remote = ensureBossHitConfirmedRemote()

	for _, player in ipairs(Players:GetPlayers()) do
		remote:FireClient(player, hitPayload)
	end
end

function BossArenaBossHealthService:OnStart()
	if self._started then
		return
	end
	self._started = true

	if not isEnabledForPlace() then
		return
	end

	local getHealthState = ensureGetHealthStateRemote()
	ensureHealthStateChangedRemote()
	ensureBossHitConfirmedRemote()

	getHealthState.OnServerInvoke = function(_player: Player): BossHealthState?
		return BossArenaRuntimeService:GetBossHealthState()
	end

	self._disconnectHealthListener = BossArenaRuntimeService:ConnectBossHealthStateChanged(function()
		broadcastHealthStateChanged()
	end)
	self._disconnectHitConfirmedListener = BossArenaRuntimeService:ConnectBossHitConfirmed(function(hitPayload)
		broadcastBossHitConfirmed(hitPayload)
	end)

	broadcastHealthStateChanged()
	Logger.Print("[BossArenaBossHealthService] Ready for boss health replication.")
end

function BossArenaBossHealthService:OnPlayerAdded(player: Player)
	if not isEnabledForPlace() then
		return
	end

	task.defer(function()
		if player.Parent == Players then
			ensureHealthStateChangedRemote():FireClient(player, BossArenaRuntimeService:GetBossHealthState())
		end
	end)
end

return BossArenaBossHealthService
