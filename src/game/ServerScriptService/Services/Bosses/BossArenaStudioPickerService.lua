local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BossArenaArrivalService = require(script.Parent.BossArenaArrivalService)
local BossArenaRuntimeService = require(script.Parent.BossArenaRuntimeService)
local BossArenaStudioTestSuiteService = require(script.Parent.BossArenaStudioTestSuiteService)
local RequestLimiter = require(script.Parent.Common.RequestLimiter)
local Bosses = require(ReplicatedStorage.Shared.Bosses)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local REMOTES_FOLDER_NAME = "Remotes"
local BOSS_ARENA_FOLDER_NAME = "BossArena"
local GET_STATE_REMOTE_NAME = "GetStudioPickerState"
local SELECT_REMOTE_NAME = "SelectStudioBoss"
local STATE_CHANGED_REMOTE_NAME = "StudioPickerStateChanged"
local ACTIVE_PROFILE_ID = "boss_arena"
local TEST_SUITE_BOSS_ID = "__studio_test_suite"
local TEST_SUITE_DISPLAY_NAME = "Test Suite"
local GET_STATE_RATE_LIMIT_KEY = "remote.boss_arena.get_picker"
local SELECT_RATE_LIMIT_KEY = "remote.boss_arena.select_picker"

type PickerBossEntry = {
	id: string,
	displayName: string,
	isTestSuite: boolean?,
}

type PickerState = {
	enabled: boolean,
	canSelect: boolean,
	shouldPrompt: boolean,
	activeBossId: string?,
	bosses: { PickerBossEntry },
	reason: string?,
	message: string?,
}

local remotesFolder: Folder? = nil
local bossArenaFolder: Folder? = nil
local getStateRemote: RemoteFunction? = nil
local selectRemote: RemoteFunction? = nil
local stateChangedRemote: RemoteEvent? = nil

local BossArenaStudioPickerService = {
	_started = false,
	_disconnectEncounterListener = nil :: (() -> ())?,
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID and RunService:IsStudio()
end

local function response(ok: boolean, code: string, message: string, state: PickerState?): { [string]: any }
	return {
		ok = ok,
		code = code,
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

local function ensureGetStateRemote(): RemoteFunction
	local folder = ensureBossArenaFolder()
	if getStateRemote and getStateRemote.Parent == folder then
		return getStateRemote
	end

	local existing = folder:FindFirstChild(GET_STATE_REMOTE_NAME)
	if existing and existing:IsA("RemoteFunction") then
		getStateRemote = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = GET_STATE_REMOTE_NAME
	remote.Parent = folder
	getStateRemote = remote
	return remote
end

local function ensureSelectRemote(): RemoteFunction
	local folder = ensureBossArenaFolder()
	if selectRemote and selectRemote.Parent == folder then
		return selectRemote
	end

	local existing = folder:FindFirstChild(SELECT_REMOTE_NAME)
	if existing and existing:IsA("RemoteFunction") then
		selectRemote = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = SELECT_REMOTE_NAME
	remote.Parent = folder
	selectRemote = remote
	return remote
end

local function ensureStateChangedRemote(): RemoteEvent
	local folder = ensureBossArenaFolder()
	if stateChangedRemote and stateChangedRemote.Parent == folder then
		return stateChangedRemote
	end

	local existing = folder:FindFirstChild(STATE_CHANGED_REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		stateChangedRemote = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = STATE_CHANGED_REMOTE_NAME
	remote.Parent = folder
	stateChangedRemote = remote
	return remote
end

local function buildBossList(): { PickerBossEntry }
	local bossEntries = {
		{
			id = TEST_SUITE_BOSS_ID,
			displayName = TEST_SUITE_DISPLAY_NAME,
			isTestSuite = true,
		},
	}

	for _, definition in ipairs(Bosses.GetAll()) do
		table.insert(bossEntries, {
			id = definition.bossId,
			displayName = definition.displayName,
		})
	end

	table.sort(bossEntries, function(left, right)
		if left.isTestSuite == true then
			return true
		end
		if right.isTestSuite == true then
			return false
		end
		if left.displayName == right.displayName then
			return left.id < right.id
		end

		return left.displayName < right.displayName
	end)

	return bossEntries
end

local function hasAnyArrivalPayload(): boolean
	for _, player in ipairs(Players:GetPlayers()) do
		if BossArenaArrivalService:GetArrivalPayload(player) ~= nil then
			return true
		end
	end

	return false
end

local function buildPickerState(player: Player): PickerState
	local enabled = isEnabledForPlace()
	local activeBossId = BossArenaRuntimeService:GetActiveBossId()
	local isTestSuiteActive = BossArenaStudioTestSuiteService:IsActive()
	local playerHasArrivalPayload = BossArenaArrivalService:GetArrivalPayload(player) ~= nil
	local anyArrivalPayload = hasAnyArrivalPayload()
	local canSelect = false
	local reason = nil
	local message = nil

	if enabled ~= true then
		reason = "disabled"
		message = "Studio boss picker is unavailable in this place."
	elseif activeBossId ~= nil then
		reason = "active_encounter"
		message = string.format("Boss '%s' is already active.", activeBossId)
	elseif isTestSuiteActive then
		reason = "active_test_suite"
		message = "Studio boss test suite is already active."
	elseif anyArrivalPayload then
		reason = if playerHasArrivalPayload then "arrival_payload" else "pending_arrival_payload"
		message = "A teleport arrival payload is already driving boss arena initialization."
	else
		canSelect = true
	end

	return {
		enabled = enabled,
		canSelect = canSelect,
		shouldPrompt = canSelect,
		activeBossId = activeBossId,
		bosses = buildBossList(),
		reason = reason,
		message = message,
	}
end

local function broadcastStateChanged()
	local remote = ensureStateChangedRemote()
	for _, player in ipairs(Players:GetPlayers()) do
		remote:FireClient(player, buildPickerState(player))
	end
end

function BossArenaStudioPickerService:OnStart()
	if self._started then
		return
	end
	self._started = true

	if not isEnabledForPlace() then
		return
	end

	local getState = ensureGetStateRemote()
	local selectBoss = ensureSelectRemote()
	ensureStateChangedRemote()

	getState.OnServerInvoke = function(player: Player)
		local allowed = RequestLimiter:Allow(player, GET_STATE_RATE_LIMIT_KEY)
		if not allowed then
			local state = buildPickerState(player)
			state.message = "Studio boss picker state is being requested too quickly."
			return state
		end

		return buildPickerState(player)
	end

	selectBoss.OnServerInvoke = function(player: Player, request: any)
		local allowed = RequestLimiter:Allow(player, SELECT_RATE_LIMIT_KEY)
		if not allowed then
			return response(false, "RATE_LIMITED", "Boss selection is being requested too quickly.", buildPickerState(player))
		end

		local state = buildPickerState(player)
		if state.enabled ~= true then
			return response(false, "UNAVAILABLE", state.message or "Studio boss picker is unavailable here.", state)
		end
		if state.canSelect ~= true then
			return response(false, "LOCKED", state.message or "Boss selection is currently locked.", state)
		end
		if typeof(request) ~= "table" then
			return response(false, "BAD_REQUEST", "Boss selection requests must be tables.", state)
		end

		local bossId = request.bossId
		if typeof(bossId) ~= "string" or bossId == "" then
			return response(false, "BAD_REQUEST", "A valid bossId is required.", state)
		end

		if bossId == TEST_SUITE_BOSS_ID then
			local ok, err = BossArenaStudioTestSuiteService:StartStudioTestSuiteFromPlayer(player)
			if not ok then
				return response(false, "SPAWN_FAILED", tostring(err), buildPickerState(player))
			end

			broadcastStateChanged()
			return response(true, "OK", "Started Studio boss test suite.", buildPickerState(player))
		end

		local ok, err = BossArenaRuntimeService:StartStudioEncounterFromBossId(player, bossId)
		if not ok then
			return response(false, "SPAWN_FAILED", tostring(err), buildPickerState(player))
		end

		local definition = Bosses.GetDefinition(bossId)
		local displayName = if definition then definition.displayName else bossId
		return response(true, "OK", string.format("Spawned boss '%s'.", displayName), buildPickerState(player))
	end

	self._disconnectEncounterListener = BossArenaRuntimeService:ConnectEncounterStateChanged(function()
		broadcastStateChanged()
	end)

	Logger.Print("[BossArenaStudioPickerService] Ready for Studio boss selection.")
end

function BossArenaStudioPickerService:OnPlayerAdded(player: Player)
	if not isEnabledForPlace() then
		return
	end

	task.defer(function()
		if player.Parent == Players then
			ensureStateChangedRemote():FireClient(player, buildPickerState(player))
			broadcastStateChanged()
		end
	end)
end

function BossArenaStudioPickerService:OnPlayerRemoving(_player: Player)
	if not isEnabledForPlace() then
		return
	end

	task.defer(function()
		if #Players:GetPlayers() > 0 then
			broadcastStateChanged()
		end
	end)
end

return BossArenaStudioPickerService
