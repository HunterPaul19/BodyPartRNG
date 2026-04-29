local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local MUSIC_GROUP_NAME = "Music"
local PASSIVE_FOLDER_NAME = "Passive"
local COMBAT_FOLDER_NAME = "Combat"
local CONTROLLER_CLONE_ATTRIBUTE = "BackgroundMusicControllerClone"

local rng = Random.new()

local BackgroundMusicController = {
	_started = false,
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

function BackgroundMusicController:_resolveMusicGroup(): Instance?
	local musicGroup = SoundService:FindFirstChild(MUSIC_GROUP_NAME)
	if musicGroup == nil then
		self:_warnOnce("missing_music_group", string.format("SoundService.%s is missing.", MUSIC_GROUP_NAME))
		return nil
	end

	return musicGroup
end

function BackgroundMusicController:_resolveTrackFolder(folderName: string): Instance?
	local musicGroup = self:_resolveMusicGroup()
	if musicGroup == nil then
		return nil
	end

	local folder = musicGroup:FindFirstChild(folderName)
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

		descendant:Stop()
		if descendant:GetAttribute(CONTROLLER_CLONE_ATTRIBUTE) == true then
			descendant:Destroy()
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
	local musicGroup = self:_resolveMusicGroup()
	if musicGroup == nil then
		return nil
	end

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

		self:_clearCurrentSound()
		self:_playNextPassive()
	end)
end

function BackgroundMusicController:_startPassiveCycle()
	local passiveFolder = self:_resolveTrackFolder(PASSIVE_FOLDER_NAME)
	local sources = collectPlayableSounds(passiveFolder)
	if #sources <= 0 then
		self:_warnOnce(
			"empty_passive",
			string.format("No playable sounds were found under SoundService.%s.%s.", MUSIC_GROUP_NAME, PASSIVE_FOLDER_NAME)
		)
		return
	end

	self._passiveSources = sources
	self._passiveQueue = {}
	self:_playNextPassive()
end

function BackgroundMusicController:_startCombatLoop()
	local combatFolder = self:_resolveTrackFolder(COMBAT_FOLDER_NAME)
	local sources = collectPlayableSounds(combatFolder)
	if #sources <= 0 then
		self:_warnOnce(
			"empty_combat",
			string.format("No playable sounds were found under SoundService.%s.%s.", MUSIC_GROUP_NAME, COMBAT_FOLDER_NAME)
		)
		return
	end

	local source = sources[rng:NextInteger(1, #sources)]
	self:_playSource(source, true)
end

function BackgroundMusicController:OnStart()
	if self._started then
		return
	end
	self._started = true

	local musicGroup = self:_resolveMusicGroup()
	if musicGroup == nil then
		return
	end

	self:_stopExistingMusic(musicGroup)

	local activeProfile = PlaceProfile.GetActiveProfile()
	if activeProfile.id == "main" or activeProfile.id == "boss_lobby" then
		self:_startPassiveCycle()
	elseif activeProfile.id == "boss_arena" then
		self:_startCombatLoop()
	else
		self:_warnOnce("unsupported_profile", string.format("No background music rule exists for profile '%s'.", activeProfile.id))
	end
end

return BackgroundMusicController
