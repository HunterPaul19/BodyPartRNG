local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossArenaRuntimeService = require(script.Parent.BossArenaRuntimeService)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local REMOTES_FOLDER_NAME = "Remotes"
local BOSS_ARENA_FOLDER_NAME = "BossArena"
local GET_TIMER_STATE_REMOTE_NAME = "GetEncounterTimerState"
local TIMER_STATE_CHANGED_REMOTE_NAME = "EncounterTimerStateChanged"
local ACTIVE_PROFILE_ID = "boss_arena"

type BossTimerState = {
	startsAtServerTime: number,
	endsAtServerTime: number,
	durationSeconds: number,
}

local remotesFolder: Folder? = nil
local bossArenaFolder: Folder? = nil
local getTimerStateRemote: RemoteFunction? = nil
local timerStateChangedRemote: RemoteEvent? = nil

local BossArenaEncounterTimerService = {
	_started = false,
	_disconnectTimerListener = nil :: (() -> ())?,
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

local function ensureGetTimerStateRemote(): RemoteFunction
	local folder = ensureBossArenaFolder()
	if getTimerStateRemote and getTimerStateRemote.Parent == folder then
		return getTimerStateRemote
	end

	local existing = folder:FindFirstChild(GET_TIMER_STATE_REMOTE_NAME)
	if existing and existing:IsA("RemoteFunction") then
		getTimerStateRemote = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = GET_TIMER_STATE_REMOTE_NAME
	remote.Parent = folder
	getTimerStateRemote = remote
	return remote
end

local function ensureTimerStateChangedRemote(): RemoteEvent
	local folder = ensureBossArenaFolder()
	if timerStateChangedRemote and timerStateChangedRemote.Parent == folder then
		return timerStateChangedRemote
	end

	local existing = folder:FindFirstChild(TIMER_STATE_CHANGED_REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		timerStateChangedRemote = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = TIMER_STATE_CHANGED_REMOTE_NAME
	remote.Parent = folder
	timerStateChangedRemote = remote
	return remote
end

local function broadcastTimerStateChanged()
	local timerState = BossArenaRuntimeService:GetBossTimerState()
	local remote = ensureTimerStateChangedRemote()

	for _, player in ipairs(Players:GetPlayers()) do
		remote:FireClient(player, timerState)
	end
end

function BossArenaEncounterTimerService:OnStart()
	if self._started then
		return
	end
	self._started = true

	if not isEnabledForPlace() then
		return
	end

	local getTimerState = ensureGetTimerStateRemote()
	ensureTimerStateChangedRemote()

	getTimerState.OnServerInvoke = function(_player: Player): BossTimerState?
		return BossArenaRuntimeService:GetBossTimerState()
	end

	self._disconnectTimerListener = BossArenaRuntimeService:ConnectBossTimerStateChanged(function()
		broadcastTimerStateChanged()
	end)

	broadcastTimerStateChanged()
	print("[BossArenaEncounterTimerService] Ready for boss timer replication.")
end

function BossArenaEncounterTimerService:OnPlayerAdded(player: Player)
	if not isEnabledForPlace() then
		return
	end

	task.defer(function()
		if player.Parent == Players then
			ensureTimerStateChangedRemote():FireClient(player, BossArenaRuntimeService:GetBossTimerState())
		end
	end)
end

return BossArenaEncounterTimerService
