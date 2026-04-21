local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossArenaRuntimeService = require(script.Parent.BossArenaRuntimeService)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local REMOTES_FOLDER_NAME = "Remotes"
local BOSS_ARENA_FOLDER_NAME = "BossArena"
local MOVE_PRESENTATION_REMOTE_NAME = "BossMovePresentation"
local ACTIVE_PROFILE_ID = "boss_arena"

local remotesFolder: Folder? = nil
local bossArenaFolder: Folder? = nil
local movePresentationRemote: RemoteEvent? = nil

local BossArenaMovePresentationService = {
	_started = false,
	_disconnectPresentationListener = nil :: (() -> ())?,
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

local function ensureMovePresentationRemote(): RemoteEvent
	local folder = ensureBossArenaFolder()
	if movePresentationRemote and movePresentationRemote.Parent == folder then
		return movePresentationRemote
	end

	local existing = folder:FindFirstChild(MOVE_PRESENTATION_REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		movePresentationRemote = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = MOVE_PRESENTATION_REMOTE_NAME
	remote.Parent = folder
	movePresentationRemote = remote
	return remote
end

function BossArenaMovePresentationService:OnStart()
	if self._started then
		return
	end
	self._started = true

	if not isEnabledForPlace() then
		return
	end

	local remote = ensureMovePresentationRemote()
	self._disconnectPresentationListener = BossArenaRuntimeService:ConnectMovePresentation(function(payload: any)
		remote:FireAllClients(payload)
	end)

	print("[BossArenaMovePresentationService] Ready for boss move presentation replication.")
end

return BossArenaMovePresentationService
