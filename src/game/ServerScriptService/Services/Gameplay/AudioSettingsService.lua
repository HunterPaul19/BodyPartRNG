local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.DataService)
local RequestLimiter = require(script.Parent.Common.RequestLimiter)
local StatsService = require(script.Parent.StatsService)

local REMOTES_FOLDER_NAME = "Remotes"
local AUDIO_FOLDER_NAME = "Audio"
local GET_MUSIC_SETTINGS_REMOTE_NAME = "GetMusicSettings"
local SET_MUSIC_ENABLED_REMOTE_NAME = "SetMusicEnabled"
local SET_MUSIC_ENABLED_RATE_LIMIT_KEY = "remote.audio.set_music_enabled"

local remotesFolder: Folder? = nil
local audioRemotesFolder: Folder? = nil
local getMusicSettingsRemote: RemoteFunction? = nil
local setMusicEnabledRemote: RemoteFunction? = nil

local AudioSettingsService = {
	_started = false,
}

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

local function ensureAudioRemotesFolder(): Folder
	local rootFolder = ensureRemotesFolder()
	if audioRemotesFolder and audioRemotesFolder.Parent == rootFolder then
		return audioRemotesFolder
	end

	local existing = rootFolder:FindFirstChild(AUDIO_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		audioRemotesFolder = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = AUDIO_FOLDER_NAME
	folder.Parent = rootFolder
	audioRemotesFolder = folder
	return folder
end

local function ensureRemoteFunction(cachedRemote: RemoteFunction?, remoteName: string): RemoteFunction
	local folder = ensureAudioRemotesFolder()
	if cachedRemote and cachedRemote.Parent == folder then
		return cachedRemote
	end

	local existing = folder:FindFirstChild(remoteName)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = remoteName
	remote.Parent = folder
	return remote
end

local function waitForPlayerData(player: Player, timeoutSeconds: number?): boolean
	local timeoutAt = os.clock() + (timeoutSeconds or 15)
	while os.clock() < timeoutAt do
		if player.Parent ~= Players then
			return false
		end
		if DataService:IsPlayerDataLoaded(player) then
			return true
		end
		task.wait(0.25)
	end

	return false
end

local function response(ok: boolean, message: string, musicEnabled: boolean?)
	return {
		ok = ok,
		message = message,
		musicEnabled = if musicEnabled == nil then true else musicEnabled == true,
	}
end

local function getCurrentMusicEnabled(player: Player): boolean
	if not DataService:IsPlayerDataLoaded(player) then
		return true
	end

	return DataService:GetMusicEnabled(player)
end

function AudioSettingsService:GetMusicSettings(player: Player)
	if not waitForPlayerData(player, 15) then
		return response(false, "Player data is not loaded.", true)
	end

	return response(true, "Music settings loaded.", DataService:GetMusicEnabled(player))
end

function AudioSettingsService:SetMusicEnabled(player: Player, enabled: any)
	local allowed, retryAfterSeconds = RequestLimiter:Allow(player, SET_MUSIC_ENABLED_RATE_LIMIT_KEY)
	if not allowed then
		local retryText = if typeof(retryAfterSeconds) == "number"
			then string.format(" Try again in %.1f seconds.", retryAfterSeconds)
			else ""
		return response(false, "Music toggle rate limited." .. retryText, getCurrentMusicEnabled(player))
	end

	if typeof(enabled) ~= "boolean" then
		return response(false, "enabled must be a boolean.", getCurrentMusicEnabled(player))
	end
	if not waitForPlayerData(player, 15) then
		return response(false, "Player data is not loaded.", true)
	end

	local previousEnabled = DataService:GetMusicEnabled(player)
	local ok, message = DataService:SetMusicEnabled(player, enabled)
	local currentEnabled = DataService:GetMusicEnabled(player)
	if ok and currentEnabled ~= previousEnabled then
		StatsService:RecordSettingChange(player, "music")
	end

	return response(ok, message or "Music preference updated.", currentEnabled)
end

function AudioSettingsService:OnStart()
	if self._started then
		return
	end
	self._started = true

	getMusicSettingsRemote = ensureRemoteFunction(getMusicSettingsRemote, GET_MUSIC_SETTINGS_REMOTE_NAME)
	setMusicEnabledRemote = ensureRemoteFunction(setMusicEnabledRemote, SET_MUSIC_ENABLED_REMOTE_NAME)

	getMusicSettingsRemote.OnServerInvoke = function(player: Player)
		local ok, result = xpcall(function()
			return self:GetMusicSettings(player)
		end, debug.traceback)
		if ok then
			return result
		end

		Logger.Warn(string.format("[AudioSettingsService] GetMusicSettings failed for %s: %s", player.Name, tostring(result)))
		return response(false, "Failed to load music settings.", true)
	end

	setMusicEnabledRemote.OnServerInvoke = function(player: Player, payload: any)
		local ok, result = xpcall(function()
			local requestedEnabled = if typeof(payload) == "table" then payload.enabled else payload
			return self:SetMusicEnabled(player, requestedEnabled)
		end, debug.traceback)
		if ok then
			return result
		end

		Logger.Warn(string.format("[AudioSettingsService] SetMusicEnabled failed for %s: %s", player.Name, tostring(result)))
		return response(false, "Failed to update music settings.", getCurrentMusicEnabled(player))
	end
end

return AudioSettingsService
