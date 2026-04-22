local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REMOTES_FOLDER_NAME = "Remotes"
local BOSS_ARENA_FOLDER_NAME = "BossArena"
local MOVE_PRESENTATION_REMOTE_NAME = "BossMovePresentation"

local remotesFolder: Folder? = nil
local bossArenaFolder: Folder? = nil
local movePresentationRemote: RemoteEvent? = nil

local BossArenaMovePresentationRelay = {}

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

function BossArenaMovePresentationRelay.EnsureRemote(): RemoteEvent
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

function BossArenaMovePresentationRelay.FireAllClients(payload: any)
	BossArenaMovePresentationRelay.EnsureRemote():FireAllClients(payload)
end

return BossArenaMovePresentationRelay
