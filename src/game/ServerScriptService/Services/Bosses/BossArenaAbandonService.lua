local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossArenaRuntimeService = require(script.Parent.BossArenaRuntimeService)
local RequestLimiter = require(script.Parent.Common.RequestLimiter)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local REMOTES_FOLDER_NAME = "Remotes"
local BOSS_ARENA_FOLDER_NAME = "BossArena"
local REQUEST_ABANDON_REMOTE_NAME = "RequestAbandonEncounter"
local ACTIVE_PROFILE_ID = "boss_arena"
local REQUEST_RATE_LIMIT_KEY = "remote.boss_arena.abandon"

type AbandonResponse = {
	ok: boolean,
	message: string?,
}

local remotesFolder: Folder? = nil
local bossArenaFolder: Folder? = nil
local requestAbandonRemote: RemoteFunction? = nil

local BossArenaAbandonService = {
	_started = false,
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
end

local function warnWithPrefix(message: string)
	Logger.Warn(string.format("[BossArenaAbandonService] %s", message))
end

local function buildResponse(ok: boolean, message: string?): AbandonResponse
	return {
		ok = ok,
		message = message,
	}
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

local function ensureRequestAbandonRemote(): RemoteFunction
	local folder = ensureBossArenaFolder()
	if requestAbandonRemote and requestAbandonRemote.Parent == folder then
		return requestAbandonRemote
	end

	local existing = folder:FindFirstChild(REQUEST_ABANDON_REMOTE_NAME)
	if existing and existing:IsA("RemoteFunction") then
		requestAbandonRemote = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = REQUEST_ABANDON_REMOTE_NAME
	remote.Parent = folder
	requestAbandonRemote = remote
	return remote
end

function BossArenaAbandonService:_handleRequest(player: Player): AbandonResponse
	local allowed, retryAfterSeconds = RequestLimiter:Allow(player, REQUEST_RATE_LIMIT_KEY)
	if not allowed then
		local retryText = if typeof(retryAfterSeconds) == "number"
			then string.format(" Try again in %.1f seconds.", retryAfterSeconds)
			else ""
		return buildResponse(false, "Abandon request rate limited." .. retryText)
	end

	if not isEnabledForPlace() then
		return buildResponse(false, "Abandon is unavailable in this place.")
	end

	local ok, message = BossArenaRuntimeService:RequestPlayerAbandon(player)
	return buildResponse(ok, message)
end

function BossArenaAbandonService:OnStart()
	if self._started then
		return
	end
	self._started = true

	if not isEnabledForPlace() then
		return
	end

	local requestRemote = ensureRequestAbandonRemote()
	requestRemote.OnServerInvoke = function(player: Player)
		local ok, response = xpcall(function()
			return self:_handleRequest(player)
		end, debug.traceback)
		if ok then
			return response
		end

		warnWithPrefix(string.format("RequestAbandonEncounter failed for %s: %s", player.Name, tostring(response)))
		return buildResponse(false, "Failed to abandon the boss encounter.")
	end

	Logger.Print("[BossArenaAbandonService] Ready for boss abandon requests.")
end

return BossArenaAbandonService
