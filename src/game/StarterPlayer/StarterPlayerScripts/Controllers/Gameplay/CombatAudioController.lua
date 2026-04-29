local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local CombatSoundUtil = require(ReplicatedStorage.Shared.Audio.CombatSoundUtil)
local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)

local LOCAL_PLAYER = Players.LocalPlayer
local REMOTES_FOLDER_NAME = "Remotes"
local DASH_FOLDER_NAME = "Dash"
local PVP_FOLDER_NAME = "PvP"
local BOSS_ARENA_FOLDER_NAME = "BossArena"
local DASH_STARTED_REMOTE_NAME = "DashStarted"
local PLAYER_M1_STARTED_REMOTE_NAME = "PlayerM1Started"
local PLAYER_HIT_CONFIRMED_REMOTE_NAME = "PlayerHitConfirmed"
local BOSS_HIT_CONFIRMED_REMOTE_NAME = "BossHitConfirmed"
local ACTIVE_BOSS_MODEL_NAME = "ActiveBoss"
local BOSS_DEATH_SOUND_NAME = "bossdeath"

local CombatAudioController = {
	_started = false,
	_connections = {} :: { RBXScriptConnection },
}

local function getPayloadNumber(payload: any, fieldName: string): number?
	if typeof(payload) ~= "table" then
		return nil
	end

	return tonumber(payload[fieldName])
end

local function getPayloadString(payload: any, fieldName: string): string?
	if typeof(payload) ~= "table" then
		return nil
	end

	local value = payload[fieldName]
	if typeof(value) == "string" and value ~= "" then
		return value
	end

	return nil
end

local function getPayloadPosition(payload: any, fieldName: string): Vector3?
	if typeof(payload) ~= "table" then
		return nil
	end

	local value = payload[fieldName]
	if typeof(value) == "Vector3" then
		return value
	end

	return nil
end

local function getPayloadBoolean(payload: any, fieldName: string): boolean
	if typeof(payload) ~= "table" then
		return false
	end

	return payload[fieldName] == true
end

local function getPayloadModel(payload: any, fieldName: string): Model?
	if typeof(payload) ~= "table" then
		return nil
	end

	local value = payload[fieldName]
	if typeof(value) == "Instance" and value:IsA("Model") then
		return value
	end

	return nil
end

local function getPayloadPlayer(payload: any, playerFieldName: string, userIdFieldName: string): Player?
	if typeof(payload) ~= "table" then
		return nil
	end

	local payloadPlayer = payload[playerFieldName]
	if typeof(payloadPlayer) == "Instance" and payloadPlayer:IsA("Player") then
		return payloadPlayer
	end

	local userId = tonumber(payload[userIdFieldName])
	if userId == nil then
		return nil
	end

	return Players:GetPlayerByUserId(userId)
end

local function isLocalUserId(userId: number?): boolean
	return userId ~= nil and userId == LOCAL_PLAYER.UserId
end

local function resolveActiveBoss(): Model?
	local activeBoss = Workspace:FindFirstChild(ACTIVE_BOSS_MODEL_NAME)
	if activeBoss and activeBoss:IsA("Model") then
		return activeBoss
	end

	return nil
end

local function resolveRemote(folderName: string, remoteName: string): RemoteEvent?
	local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if not (remotesFolder and remotesFolder:IsA("Folder")) then
		return nil
	end

	local folder = remotesFolder:FindFirstChild(folderName)
	if not (folder and folder:IsA("Folder")) then
		return nil
	end

	local remote = folder:FindFirstChild(remoteName)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end

	return nil
end

local function resolveReplicatedSound(soundName: string): Sound?
	local directSound = ReplicatedStorage:FindFirstChild(soundName)
	if directSound and directSound:IsA("Sound") then
		return directSound
	end

	local targetName = string.lower(soundName)
	for _, child in ipairs(ReplicatedStorage:GetChildren()) do
		if child:IsA("Sound") and string.lower(child.Name) == targetName then
			return child
		end
	end

	for _, descendant in ipairs(ReplicatedStorage:GetDescendants()) do
		if descendant:IsA("Sound") and string.lower(descendant.Name) == targetName then
			return descendant
		end
	end

	return nil
end

local function playBossDeathSound(): boolean
	local sound = resolveReplicatedSound(BOSS_DEATH_SOUND_NAME)
	if sound == nil then
		return false
	end

	SoundUtil.Play(sound, SoundService)
	return true
end

function CombatAudioController:_connectWhenAvailable(folderName: string, remoteName: string, callback: (any) -> ())
	task.spawn(function()
		while self._started == true do
			local remote = resolveRemote(folderName, remoteName)
			if remote ~= nil then
				table.insert(self._connections, remote.OnClientEvent:Connect(callback))
				return
			end

			task.wait(0.25)
		end
	end)
end

function CombatAudioController:_handleDashStarted(payload: any)
	local userId = getPayloadNumber(payload, "userId")
	if isLocalUserId(userId) then
		return
	end

	local player = getPayloadPlayer(payload, "player", "userId")
	local direction = getPayloadString(payload, "direction")
	CombatSoundUtil.PlaySpatialDash(
		if player then player.Character else nil,
		direction,
		getPayloadPosition(payload, "position")
	)
end

function CombatAudioController:_handlePlayerM1Started(payload: any)
	local userId = getPayloadNumber(payload, "userId")
	if isLocalUserId(userId) then
		return
	end

	local player = getPayloadPlayer(payload, "player", "userId")
	CombatSoundUtil.PlaySpatialSwing(if player then player.Character else nil, getPayloadPosition(payload, "position"))
end

function CombatAudioController:_handlePvpHitConfirmed(payload: any)
	local attackerUserId = getPayloadNumber(payload, "attackerUserId")
	local damage = getPayloadNumber(payload, "damage")
	if damage == nil or damage <= 0 then
		return
	end

	if isLocalUserId(attackerUserId) then
		CombatSoundUtil.PlayLocalHit()
		return
	end

	local targetPlayer = getPayloadPlayer(payload, "target", "targetUserId")
	CombatSoundUtil.PlaySpatialHit(
		if targetPlayer then targetPlayer.Character else nil,
		getPayloadPosition(payload, "targetPosition") or getPayloadPosition(payload, "position")
	)
end

function CombatAudioController:_handleBossHitConfirmed(payload: any)
	local attackerUserId = getPayloadNumber(payload, "attackerUserId")
	local damage = getPayloadNumber(payload, "damage")
	if damage == nil or damage <= 0 then
		return
	end

	local targetType = getPayloadString(payload, "targetType") or "boss"
	if isLocalUserId(attackerUserId) then
		if targetType == "boss" and getPayloadBoolean(payload, "isKillingBlow") and playBossDeathSound() then
			return
		end

		CombatSoundUtil.PlayLocalHit()
		return
	end

	local targetModel = if targetType == "minion" then getPayloadModel(payload, "targetModel") else resolveActiveBoss()
	CombatSoundUtil.PlaySpatialHit(targetModel, getPayloadPosition(payload, "targetPosition"))
end

function CombatAudioController:OnStart()
	if self._started then
		return
	end
	self._started = true

	self:_connectWhenAvailable(DASH_FOLDER_NAME, DASH_STARTED_REMOTE_NAME, function(payload: any)
		self:_handleDashStarted(payload)
	end)
	self:_connectWhenAvailable(PVP_FOLDER_NAME, PLAYER_M1_STARTED_REMOTE_NAME, function(payload: any)
		self:_handlePlayerM1Started(payload)
	end)
	self:_connectWhenAvailable(PVP_FOLDER_NAME, PLAYER_HIT_CONFIRMED_REMOTE_NAME, function(payload: any)
		self:_handlePvpHitConfirmed(payload)
	end)
	self:_connectWhenAvailable(BOSS_ARENA_FOLDER_NAME, PLAYER_M1_STARTED_REMOTE_NAME, function(payload: any)
		self:_handlePlayerM1Started(payload)
	end)
	self:_connectWhenAvailable(BOSS_ARENA_FOLDER_NAME, BOSS_HIT_CONFIRMED_REMOTE_NAME, function(payload: any)
		self:_handleBossHitConfirmed(payload)
	end)
end

return CombatAudioController
