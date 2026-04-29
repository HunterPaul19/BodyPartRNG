local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local MUSIC_GROUP_NAME = "Music"
local PASSIVE_FOLDER_NAME = "Passive"
local COMBAT_FOLDER_NAME = "Combat"
local CONTROLLER_CLONE_ATTRIBUTE = "BackgroundMusicControllerClone"
local MUSIC_ASSET_WAIT_SECONDS = 3
local MUSIC_START_RETRY_SECONDS = 1
local MUSIC_START_MAX_RETRIES = 10

local rng = Random.new()

local BackgroundMusicController = {
	_started = false,
	_musicEnabled = true,
	_musicStartToken = 0,
	_currentSound = nil :: Sound?,
	_currentEndedConnection = nil :: RBXScriptConnection?,
	_passiveSources = {} :: { Sound },
	_passiveQueue = {} :: { Sound },
	_lastPassiveSource = nil :: Sound?,
	_warnedKeys = {} :: { [string]: boolean },
}

local function isPlayableSound(instance: Instance): boolean
	return instance:IsA("Sound") and instance.SoundId ~= ""
end

local function collectPlayableSounds(root: Instance?): { Sound }
	local sounds = {}
	if root == nil then
		return sounds
	end

	if isPlayableSound(root) then
		table.insert(sounds, root :: Sound)
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if isPlayableSound(descendant) then
			table.insert(sounds, descendant :: Sound)
		end
	end

	return sounds
end

local function shuffleSounds(sounds: { Sound }): { Sound }
	local shuffled = table.clone(sounds)
	for index = #shuffled, 2, -1 do
		local swapIndex = rng:NextInteger(1, index)
		shuffled[index], shuffled[swapIndex] = shuffled[swapIndex], shuffled[index]
	end

	return shuffled
end

function BackgroundMusicController:_warnOnce(key: string, message: string)
	if self._warnedKeys[key] == true then
		return
	end

	self._warnedKeys[key] = true
	Logger.Warn(string.format("[BackgroundMusicController] %s", message))
end

function BackgroundMusicController:_resolveMusicGroup(waitSeconds: number?): Instance?
	local musicGroup = SoundService:FindFirstChild(MUSIC_GROUP_NAME)
	if musicGroup == nil and typeof(waitSeconds) == "number" and waitSeconds > 0 then
		musicGroup = SoundService:WaitForChild(MUSIC_GROUP_NAME, waitSeconds)
	end
	if musicGroup == nil then
		self:_warnOnce("missing_music_group", string.format("SoundService.%s is missing.", MUSIC_GROUP_NAME))
		return nil
	end

	return musicGroup
end

function BackgroundMusicController:_resolveTrackFolder(folderName: string, waitSeconds: number?): Instance?
	local musicGroup = self:_resolveMusicGroup(waitSeconds)
	if musicGroup == nil then
		return nil
	end

	local folder = musicGroup:FindFirstChild(folderName)
	if folder == nil and typeof(waitSeconds) == "number" and waitSeconds > 0 then
		folder = musicGroup:WaitForChild(folderName, waitSeconds)
	end
	if folder == nil then
		self:_warnOnce(
			"missing_" .. folderName,
			string.format("SoundService.%s.%s is missing.", MUSIC_GROUP_NAME, folderName)
		)
		return nil
	end

	return folder
end

function BackgroundMusicController:_stopExistingMusic(musicGroup: Instance)
	for _, descendant in ipairs(musicGroup:GetDescendants()) do
		if not descendant:IsA("Sound") then
			continue
		end

		if descendant:GetAttribute(CONTROLLER_CLONE_ATTRIBUTE) == true then
			descendant:Stop()
			descendant:Destroy()
		elseif descendant.IsPlaying then
			descendant:Stop()
		end
	end
end

function BackgroundMusicController:_disconnectCurrentEnded()
	if self._currentEndedConnection and self._currentEndedConnection.Connected then
		self._currentEndedConnection:Disconnect()
	end

	self._currentEndedConnection = nil
end

function BackgroundMusicController:_clearCurrentSound()
	self:_disconnectCurrentEnded()

	if self._currentSound and self._currentSound.Parent ~= nil then
		self._currentSound:Stop()
		self._currentSound:Destroy()
	end

	self._currentSound = nil
end

function BackgroundMusicController:_playSource(source: Sound, looped: boolean): Sound?
	if self._musicEnabled ~= true then
		return nil
	end

	local musicGroup = self:_resolveMusicGroup(MUSIC_ASSET_WAIT_SECONDS)
	if musicGroup == nil then
		return nil
	end

	self:_stopExistingMusic(musicGroup)
	self:_clearCurrentSound()

	local clone = source:Clone()
	clone.Name = "BackgroundMusic"
	clone.Looped = looped == true
	clone.TimePosition = 0
	clone:SetAttribute(CONTROLLER_CLONE_ATTRIBUTE, true)
	clone.Parent = musicGroup
	clone:Play()

	self._currentSound = clone
	return clone
end

function BackgroundMusicController:_nextPassiveSource(): Sound?
	if #self._passiveSources <= 0 then
		return nil
	end

	if #self._passiveQueue <= 0 then
		self._passiveQueue = shuffleSounds(self._passiveSources)
		if #self._passiveQueue > 1 and self._passiveQueue[1] == self._lastPassiveSource then
			self._passiveQueue[1], self._passiveQueue[#self._passiveQueue] = self._passiveQueue[#self._passiveQueue], self._passiveQueue[1]
		end
	end

	local source = table.remove(self._passiveQueue, 1)
	self._lastPassiveSource = source
	return source
end

function BackgroundMusicController:_playNextPassive()
	if self._musicEnabled ~= true then
		return
	end

	local source = self:_nextPassiveSource()
	if source == nil then
		return
	end

	local sound = self:_playSource(source, false)
	if sound == nil then
		return
	end

	self._currentEndedConnection = sound.Ended:Connect(function()
		if self._currentSound ~= sound then
			return
		end
		if self._musicEnabled ~= true then
			self:_clearCurrentSound()
			return
		end

		self:_clearCurrentSound()
		self:_playNextPassive()
	end)
end

function BackgroundMusicController:_startPassiveCycle(): boolean
	local passiveFolder = self:_resolveTrackFolder(PASSIVE_FOLDER_NAME, MUSIC_ASSET_WAIT_SECONDS)
	local sources = collectPlayableSounds(passiveFolder)
	if #sources <= 0 then
		self:_warnOnce(
			"empty_passive",
			string.format("No playable sounds were found under SoundService.%s.%s.", MUSIC_GROUP_NAME, PASSIVE_FOLDER_NAME)
		)
		return false
	end

	self._passiveSources = sources
	self._passiveQueue = {}
	self:_playNextPassive()
	return self._currentSound ~= nil
end

function BackgroundMusicController:_startCombatLoop(): boolean
	local combatFolder = self:_resolveTrackFolder(COMBAT_FOLDER_NAME, MUSIC_ASSET_WAIT_SECONDS)
	local sources = collectPlayableSounds(combatFolder)
	if #sources <= 0 then
		self:_warnOnce(
			"empty_combat",
			string.format("No playable sounds were found under SoundService.%s.%s.", MUSIC_GROUP_NAME, COMBAT_FOLDER_NAME)
		)
		return false
	end

	local source = sources[rng:NextInteger(1, #sources)]
	self:_playSource(source, true)
	return self._currentSound ~= nil
end

function BackgroundMusicController:_scheduleMusicStartRetry(token: number, attempt: number)
	if token ~= self._musicStartToken or self._musicEnabled ~= true then
		return
	end
	if attempt >= MUSIC_START_MAX_RETRIES then
		self:_warnOnce(
			"music_start_retry_exhausted",
			string.format("Background music did not start after %d retries.", MUSIC_START_MAX_RETRIES)
		)
		return
	end

	task.delay(MUSIC_START_RETRY_SECONDS, function()
		if token ~= self._musicStartToken or self._musicEnabled ~= true then
			return
		end

		self:_startMusicForActiveProfile(token, attempt + 1)
	end)
end

function BackgroundMusicController:_startMusicForActiveProfile(token: number?, attempt: number?)
	if self._musicEnabled ~= true then
		self:_clearCurrentSound()
		return
	end
	if token ~= nil and token ~= self._musicStartToken then
		return
	end
	if self._currentSound and self._currentSound.Parent ~= nil and self._currentSound.IsPlaying then
		return
	end

	local activeProfile = PlaceProfile.GetActiveProfile()
	local didStart = false
	if activeProfile.id == "main" or activeProfile.id == "boss_lobby" then
		didStart = self:_startPassiveCycle()
	elseif activeProfile.id == "boss_arena" then
		didStart = self:_startCombatLoop()
	else
		self:_warnOnce("unsupported_profile", string.format("No background music rule exists for profile '%s'.", activeProfile.id))
		return
	end

	if not didStart then
		self:_scheduleMusicStartRetry(token or self._musicStartToken, attempt or 0)
	end
end

function BackgroundMusicController:IsMusicEnabled(): boolean
	return self._musicEnabled == true
end

function BackgroundMusicController:SetMusicEnabled(enabled: boolean)
	local nextEnabled = enabled == true
	if self._musicEnabled == nextEnabled then
		if nextEnabled and self._started then
			self:_startMusicForActiveProfile()
		end
		return
	end

	self._musicEnabled = nextEnabled
	if not self._started then
		return
	end

	if nextEnabled then
		self._musicStartToken += 1
		self:_startMusicForActiveProfile()
	else
		self._musicStartToken += 1
		self:_clearCurrentSound()
	end
end

function BackgroundMusicController:OnStart()
	if self._started then
		return
	end
	self._started = true

	local musicGroup = self:_resolveMusicGroup(0)
	if musicGroup ~= nil then
		self:_stopExistingMusic(musicGroup)
	end

	self._musicEnabled = true
	self._musicStartToken += 1
	self:_startMusicForActiveProfile()
end

return BackgroundMusicController
