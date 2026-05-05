local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossArenaRuntimeService = require(script.Parent.BossArenaRuntimeService)
local RequestLimiter = require(script.Parent.Common.RequestLimiter)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local REMOTES_FOLDER_NAME = "Remotes"
local BOSS_ARENA_FOLDER_NAME = "BossArena"
local GET_RESULTS_STATE_REMOTE_NAME = "GetResultsState"
local RESULTS_STATE_CHANGED_REMOTE_NAME = "ResultsStateChanged"
local SET_REPLAY_READY_REMOTE_NAME = "SetReplayReady"
local RETURN_TO_LOBBY_REMOTE_NAME = "ReturnToBossLobby"
local ACTIVE_PROFILE_ID = "boss_arena"
local READY_RATE_LIMIT_KEY = "remote.boss_arena.results_ready"
local RETURN_RATE_LIMIT_KEY = "remote.boss_arena.results_return"

type ResultsResponse = {
	ok: boolean,
	message: string?,
	state: any?,
}

local remotesFolder: Folder? = nil
local bossArenaFolder: Folder? = nil
local getResultsStateRemote: RemoteFunction? = nil
local resultsStateChangedRemote: RemoteEvent? = nil
local setReplayReadyRemote: RemoteFunction? = nil
local returnToLobbyRemote: RemoteFunction? = nil

local BossArenaResultsService = {
	_started = false,
	_disconnectResultsListener = nil :: (() -> ())?,
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
end

local function warnWithPrefix(message: string)
	Logger.Warn(string.format("[BossArenaResultsService] %s", message))
end

local function buildResponse(ok: boolean, message: string?, state: any?): ResultsResponse
	return {
		ok = ok,
		message = message,
		state = state,
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

local function ensureRemoteFunction(name: string, current: RemoteFunction?): RemoteFunction
	local folder = ensureBossArenaFolder()
	if current and current.Parent == folder then
		return current
	end

	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local function ensureResultsStateChangedRemote(): RemoteEvent
	local folder = ensureBossArenaFolder()
	if resultsStateChangedRemote and resultsStateChangedRemote.Parent == folder then
		return resultsStateChangedRemote
	end

	local existing = folder:FindFirstChild(RESULTS_STATE_CHANGED_REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		resultsStateChangedRemote = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = RESULTS_STATE_CHANGED_REMOTE_NAME
	remote.Parent = folder
	resultsStateChangedRemote = remote
	return remote
end

local function ensureGetResultsStateRemote(): RemoteFunction
	getResultsStateRemote = ensureRemoteFunction(GET_RESULTS_STATE_REMOTE_NAME, getResultsStateRemote)
	return getResultsStateRemote
end

local function ensureSetReplayReadyRemote(): RemoteFunction
	setReplayReadyRemote = ensureRemoteFunction(SET_REPLAY_READY_REMOTE_NAME, setReplayReadyRemote)
	return setReplayReadyRemote
end

local function ensureReturnToLobbyRemote(): RemoteFunction
	returnToLobbyRemote = ensureRemoteFunction(RETURN_TO_LOBBY_REMOTE_NAME, returnToLobbyRemote)
	return returnToLobbyRemote
end

local function broadcastResultsStateChanged()
	local remote = ensureResultsStateChangedRemote()
	for _, player in ipairs(Players:GetPlayers()) do
		remote:FireClient(player, BossArenaRuntimeService:GetBossResultsState(player))
	end
end

function BossArenaResultsService:_handleSetReplayReady(player: Player, isReady: any): ResultsResponse
	local allowed, retryAfterSeconds = RequestLimiter:Allow(player, READY_RATE_LIMIT_KEY)
	if not allowed then
		local retryText = if typeof(retryAfterSeconds) == "number"
			then string.format(" Try again in %.1f seconds.", retryAfterSeconds)
			else ""
		return buildResponse(false, "Play again request rate limited." .. retryText, BossArenaRuntimeService:GetBossResultsState(player))
	end

	local ok, message = BossArenaRuntimeService:SetPlayerReplayReady(player, isReady == true)
	return buildResponse(ok, message, BossArenaRuntimeService:GetBossResultsState(player))
end

function BossArenaResultsService:_handleReturnToLobby(player: Player): ResultsResponse
	local allowed, retryAfterSeconds = RequestLimiter:Allow(player, RETURN_RATE_LIMIT_KEY)
	if not allowed then
		local retryText = if typeof(retryAfterSeconds) == "number"
			then string.format(" Try again in %.1f seconds.", retryAfterSeconds)
			else ""
		return buildResponse(false, "Return request rate limited." .. retryText, BossArenaRuntimeService:GetBossResultsState(player))
	end

	local ok, message = BossArenaRuntimeService:ReturnPlayerToBossLobbyFromResults(player)
	return buildResponse(ok, message, BossArenaRuntimeService:GetBossResultsState(player))
end

function BossArenaResultsService:OnStart()
	if self._started then
		return
	end
	self._started = true

	if not isEnabledForPlace() then
		return
	end

	local getResultsState = ensureGetResultsStateRemote()
	local setReplayReady = ensureSetReplayReadyRemote()
	local returnToLobby = ensureReturnToLobbyRemote()
	ensureResultsStateChangedRemote()

	getResultsState.OnServerInvoke = function(player: Player)
		return BossArenaRuntimeService:GetBossResultsState(player)
	end

	setReplayReady.OnServerInvoke = function(player: Player, isReady: any)
		local ok, response = xpcall(function()
			return self:_handleSetReplayReady(player, isReady)
		end, debug.traceback)
		if ok then
			return response
		end

		warnWithPrefix(string.format("SetReplayReady failed for %s: %s", player.Name, tostring(response)))
		return buildResponse(false, "Failed to update replay readiness.", BossArenaRuntimeService:GetBossResultsState(player))
	end

	returnToLobby.OnServerInvoke = function(player: Player)
		local ok, response = xpcall(function()
			return self:_handleReturnToLobby(player)
		end, debug.traceback)
		if ok then
			return response
		end

		warnWithPrefix(string.format("ReturnToBossLobby failed for %s: %s", player.Name, tostring(response)))
		return buildResponse(false, "Failed to return from boss results.", BossArenaRuntimeService:GetBossResultsState(player))
	end

	self._disconnectResultsListener = BossArenaRuntimeService:ConnectBossResultsStateChanged(function()
		broadcastResultsStateChanged()
	end)

	broadcastResultsStateChanged()
	Logger.Print("[BossArenaResultsService] Ready for boss results replication.")
end

function BossArenaResultsService:OnPlayerAdded(player: Player)
	if not isEnabledForPlace() then
		return
	end

	task.defer(function()
		if player.Parent == Players then
			ensureResultsStateChangedRemote():FireClient(player, BossArenaRuntimeService:GetBossResultsState(player))
		end
	end)
end

return BossArenaResultsService
