local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Icon = require(ReplicatedStorage.Packages.TopBarPlus)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)
local Notify = require(ReplicatedStorage.Shared.UI.Notify)

local LOCAL_PLAYER = Players.LocalPlayer
local REMOTES_FOLDER_NAME = "Remotes"
local BOSS_ARENA_FOLDER_NAME = "BossArena"
local REQUEST_ABANDON_REMOTE_NAME = "RequestAbandonEncounter"
local GET_TIMER_STATE_REMOTE_NAME = "GetEncounterTimerState"
local TIMER_STATE_CHANGED_REMOTE_NAME = "EncounterTimerStateChanged"
local ACTIVE_PROFILE_ID = "boss_arena"

type BossTimerState = {
	phase: string,
	startsAtServerTime: number,
	endsAtServerTime: number,
	durationSeconds: number,
}

type AbandonResponse = {
	ok: boolean,
	message: string?,
}

type AbandonRemotes = {
	requestAbandon: RemoteFunction,
	getTimerState: RemoteFunction,
	timerStateChanged: RemoteEvent,
}

local BossArenaAbandonController = {
	_started = false,
	_requestInFlight = false,
	_remotes = nil :: AbandonRemotes?,
	_abandonIcon = nil :: any,
	_confirmIcon = nil :: any,
	_timerStateChangedConnection = nil :: RBXScriptConnection?,
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
end

local function warnWithPrefix(message: string)
	Logger.Warn(string.format("[BossArenaAbandonController] %s", message))
end

local function isAbandonableTimerState(state: any): boolean
	if typeof(state) ~= "table" or typeof(state.phase) ~= "string" then
		return false
	end

	return state.phase == "intro" or state.phase == "fight"
end

local function invokeTimerState(remote: RemoteFunction): BossTimerState?
	local ok, result = pcall(function()
		return remote:InvokeServer()
	end)

	if ok then
		return result
	end

	warnWithPrefix(string.format("Remote %s failed: %s", remote.Name, tostring(result)))
	return nil
end

function BossArenaAbandonController:_ensureRemotes(): AbandonRemotes?
	if self._remotes then
		return self._remotes
	end

	local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, 30)
	if not (remotesFolder and remotesFolder:IsA("Folder")) then
		warnWithPrefix("ReplicatedStorage.Remotes is missing.")
		return nil
	end

	local bossArenaFolder = remotesFolder:WaitForChild(BOSS_ARENA_FOLDER_NAME, 30)
	if not (bossArenaFolder and bossArenaFolder:IsA("Folder")) then
		warnWithPrefix("ReplicatedStorage.Remotes.BossArena is missing.")
		return nil
	end

	local requestAbandon = bossArenaFolder:WaitForChild(REQUEST_ABANDON_REMOTE_NAME, 30)
	local getTimerState = bossArenaFolder:WaitForChild(GET_TIMER_STATE_REMOTE_NAME, 30)
	local timerStateChanged = bossArenaFolder:WaitForChild(TIMER_STATE_CHANGED_REMOTE_NAME, 30)

	if not (requestAbandon and requestAbandon:IsA("RemoteFunction")) then
		warnWithPrefix("BossArena.RequestAbandonEncounter is missing.")
		return nil
	end
	if not (getTimerState and getTimerState:IsA("RemoteFunction")) then
		warnWithPrefix("BossArena.GetEncounterTimerState is missing.")
		return nil
	end
	if not (timerStateChanged and timerStateChanged:IsA("RemoteEvent")) then
		warnWithPrefix("BossArena.EncounterTimerStateChanged is missing.")
		return nil
	end

	self._remotes = {
		requestAbandon = requestAbandon,
		getTimerState = getTimerState,
		timerStateChanged = timerStateChanged,
	}

	return self._remotes
end

function BossArenaAbandonController:_setIconsLocked(isLocked: boolean)
	local abandonIcon = self._abandonIcon
	local confirmIcon = self._confirmIcon

	if abandonIcon then
		if isLocked then
			abandonIcon:lock()
		else
			abandonIcon:unlock()
		end
	end
	if confirmIcon then
		if isLocked then
			confirmIcon:lock()
		else
			confirmIcon:unlock()
		end
	end
end

function BossArenaAbandonController:_setVisible(isVisible: boolean)
	local abandonIcon = self._abandonIcon
	if abandonIcon == nil then
		return
	end

	abandonIcon:setEnabled(isVisible == true)
	if not isVisible then
		abandonIcon:deselect("BossArenaAbandonHidden", abandonIcon)
	end
end

function BossArenaAbandonController:_renderTimerState(state: BossTimerState?)
	self:_setVisible(isAbandonableTimerState(state))
end

function BossArenaAbandonController:_requestAbandon()
	if self._requestInFlight then
		return
	end

	local remotes = self:_ensureRemotes()
	if not remotes then
		Notify.Show("The boss abandon control is not ready yet.", {
			title = "Boss",
			channel = "system",
		})
		return
	end

	self._requestInFlight = true
	self:_setIconsLocked(true)

	local ok, response = pcall(function()
		return remotes.requestAbandon:InvokeServer()
	end)

	self._requestInFlight = false
	self:_setIconsLocked(false)

	if not ok then
		warnWithPrefix(string.format("RequestAbandonEncounter failed: %s", tostring(response)))
		Notify.Show("Failed to abandon the boss encounter.", {
			title = "Boss",
			channel = "system",
		})
		return
	end

	if typeof(response) == "table" and response.ok == true then
		self:_setVisible(false)
		return
	end

	local message = if typeof(response) == "table" and typeof(response.message) == "string"
		then response.message
		else "Failed to abandon the boss encounter."
	Notify.Show(message, {
		title = "Boss",
		channel = "system",
	})
end

function BossArenaAbandonController:_ensureIcons()
	if self._abandonIcon ~= nil then
		return
	end

	local confirmIcon = Icon.new()
	confirmIcon:setName("BossArenaConfirmAbandon")
	confirmIcon:setLabel("Confirm abandon")
	confirmIcon:setCaption("Return to the boss lobby")
	confirmIcon:oneClick()
	confirmIcon:bindEvent("selected", function()
		self:_requestAbandon()
	end)

	local abandonIcon = Icon.new()
	abandonIcon:setName("BossArenaAbandon")
	abandonIcon:setLabel("Abandon")
	abandonIcon:setCaption("Leave the boss fight")
	abandonIcon:align("Left")
	abandonIcon:setDropdown({ confirmIcon })
	abandonIcon:setEnabled(false)

	self._confirmIcon = confirmIcon
	self._abandonIcon = abandonIcon
end

function BossArenaAbandonController:_bindRemotes()
	local remotes = self:_ensureRemotes()
	if not remotes then
		return
	end

	if self._timerStateChangedConnection then
		self._timerStateChangedConnection:Disconnect()
	end

	self._timerStateChangedConnection = remotes.timerStateChanged.OnClientEvent:Connect(function(state: BossTimerState?)
		self:_renderTimerState(state)
	end)
end

function BossArenaAbandonController:_refreshTimerState()
	local remotes = self:_ensureRemotes()
	if not remotes then
		self:_setVisible(false)
		return
	end

	self:_renderTimerState(invokeTimerState(remotes.getTimerState))
end

function BossArenaAbandonController:OnStart()
	if self._started then
		return
	end
	self._started = true

	if RunService:IsClient() ~= true or not isEnabledForPlace() then
		return
	end

	self:_ensureIcons()
	self:_bindRemotes()
	self:_refreshTimerState()
end

return BossArenaAbandonController
