local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BackgroundMusicController = require(script.Parent.BackgroundMusicController)
local TopBarPlus = require(ReplicatedStorage.Packages.TopBarPlus)

local REMOTES_FOLDER_NAME = "Remotes"
local AUDIO_FOLDER_NAME = "Audio"
local GET_MUSIC_SETTINGS_REMOTE_NAME = "GetMusicSettings"
local SET_MUSIC_ENABLED_REMOTE_NAME = "SetMusicEnabled"
local REMOTE_WAIT_TIMEOUT = 15

local MusicTopBarController = {
	_started = false,
	_icon = nil,
	_getMusicSettingsRemote = nil :: RemoteFunction?,
	_setMusicEnabledRemote = nil :: RemoteFunction?,
	_requestPending = false,
}

local function waitForRemoteFunction(parent: Instance, childName: string, timeoutSeconds: number): RemoteFunction?
	local child = parent:WaitForChild(childName, timeoutSeconds)
	if child and child:IsA("RemoteFunction") then
		return child
	end

	return nil
end

local function buildLabel(musicEnabled: boolean): string
	return if musicEnabled then "Music: On" else "Music: Off"
end

function MusicTopBarController:_warn(message: string)
	Logger.Warn(string.format("[MusicTopBarController] %s", message))
end

function MusicTopBarController:_resolveRemotes(): boolean
	local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, REMOTE_WAIT_TIMEOUT)
	if not (remotesFolder and remotesFolder:IsA("Folder")) then
		self:_warn("ReplicatedStorage.Remotes is missing.")
		return false
	end

	local audioFolder = remotesFolder:WaitForChild(AUDIO_FOLDER_NAME, REMOTE_WAIT_TIMEOUT)
	if not (audioFolder and audioFolder:IsA("Folder")) then
		self:_warn("ReplicatedStorage.Remotes.Audio is missing.")
		return false
	end

	self._getMusicSettingsRemote = waitForRemoteFunction(audioFolder, GET_MUSIC_SETTINGS_REMOTE_NAME, REMOTE_WAIT_TIMEOUT)
	self._setMusicEnabledRemote = waitForRemoteFunction(audioFolder, SET_MUSIC_ENABLED_REMOTE_NAME, REMOTE_WAIT_TIMEOUT)
	if self._getMusicSettingsRemote == nil or self._setMusicEnabledRemote == nil then
		self:_warn("Music settings remotes are missing.")
		return false
	end

	return true
end

function MusicTopBarController:_setIconMusicEnabled(musicEnabled: boolean)
	BackgroundMusicController:SetMusicEnabled(musicEnabled)

	if self._icon then
		self._icon:setLabel(buildLabel(musicEnabled))
		self._icon:setCaption(if musicEnabled then "Turn background music off" else "Turn background music on")
	end
end

function MusicTopBarController:_loadInitialState()
	if self._getMusicSettingsRemote == nil then
		self:_setIconMusicEnabled(BackgroundMusicController:IsMusicEnabled())
		return
	end

	local ok, result = pcall(function()
		return self._getMusicSettingsRemote:InvokeServer()
	end)
	if not ok or typeof(result) ~= "table" or result.ok ~= true then
		local message = if ok and typeof(result) == "table" then tostring(result.message) else tostring(result)
		self:_warn(string.format("Failed to load music settings: %s", message))
		self:_setIconMusicEnabled(BackgroundMusicController:IsMusicEnabled())
		return
	end

	self:_setIconMusicEnabled(result.musicEnabled ~= false)
end

function MusicTopBarController:_requestMusicEnabled(musicEnabled: boolean)
	if self._requestPending then
		return
	end
	if self._setMusicEnabledRemote == nil then
		self:_warn("Cannot update music settings because SetMusicEnabled is missing.")
		self:_setIconMusicEnabled(BackgroundMusicController:IsMusicEnabled())
		return
	end

	self._requestPending = true
	local ok, result = pcall(function()
		return self._setMusicEnabledRemote:InvokeServer({
			enabled = musicEnabled == true,
		})
	end)
	self._requestPending = false

	if not ok or typeof(result) ~= "table" or result.ok ~= true then
		local message = if ok and typeof(result) == "table" then tostring(result.message) else tostring(result)
		self:_warn(string.format("Failed to update music settings: %s", message))
		local serverState = if ok and typeof(result) == "table" then result.musicEnabled else nil
		self:_setIconMusicEnabled(if typeof(serverState) == "boolean" then serverState else BackgroundMusicController:IsMusicEnabled())
		return
	end

	self:_setIconMusicEnabled(result.musicEnabled ~= false)
end

function MusicTopBarController:_createIcon()
	local icon = TopBarPlus.new()
	icon:align("Left")
	icon:setOrder(10)
	icon:setLabel(buildLabel(BackgroundMusicController:IsMusicEnabled()))
	icon:setCaption("Toggle background music")
	icon:oneClick(true)
	icon:bindEvent("selected", function()
		self:_requestMusicEnabled(not BackgroundMusicController:IsMusicEnabled())
	end)

	self._icon = icon
end

function MusicTopBarController:OnStart()
	if self._started then
		return
	end
	self._started = true

	self:_createIcon()
	if self:_resolveRemotes() then
		self:_loadInitialState()
	else
		self:_setIconMusicEnabled(BackgroundMusicController:IsMusicEnabled())
	end
end

return MusicTopBarController
