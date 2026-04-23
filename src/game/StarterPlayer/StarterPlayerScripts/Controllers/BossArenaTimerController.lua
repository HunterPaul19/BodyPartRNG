local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local LOCAL_PLAYER = Players.LocalPlayer
local REMOTES_FOLDER_NAME = "Remotes"
local BOSS_ARENA_FOLDER_NAME = "BossArena"
local GET_TIMER_STATE_REMOTE_NAME = "GetEncounterTimerState"
local TIMER_STATE_CHANGED_REMOTE_NAME = "EncounterTimerStateChanged"
local ACTIVE_PROFILE_ID = "boss_arena"

type BossTimerState = {
	startsAtServerTime: number,
	endsAtServerTime: number,
	durationSeconds: number,
}

type BossTimerRemotes = {
	getState: RemoteFunction,
	stateChanged: RemoteEvent,
}

type BossTimerUi = {
	root: Frame,
	label: TextLabel,
}

local BossArenaTimerController = {
	_started = false,
	_remotes = nil :: BossTimerRemotes?,
	_ui = nil :: BossTimerUi?,
	_currentState = nil :: BossTimerState?,
	_lastDisplayedRemaining = nil :: number?,
	_stateChangedConnection = nil :: RBXScriptConnection?,
	_renderConnection = nil :: RBXScriptConnection?,
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
end

local function warnWithPrefix(message: string)
	warn(string.format("[BossArenaTimerController] %s", message))
end

local function normalizeTimerState(state: any): BossTimerState?
	if typeof(state) ~= "table" then
		return nil
	end

	local startsAtServerTime = tonumber(state.startsAtServerTime)
	local endsAtServerTime = tonumber(state.endsAtServerTime)
	local durationSeconds = math.max(0, math.floor(tonumber(state.durationSeconds) or 0))

	if startsAtServerTime == nil or endsAtServerTime == nil or durationSeconds <= 0 then
		return nil
	end
	if endsAtServerTime <= startsAtServerTime then
		return nil
	end

	return {
		startsAtServerTime = startsAtServerTime,
		endsAtServerTime = endsAtServerTime,
		durationSeconds = durationSeconds,
	}
end

local function invokeRemote(remote: RemoteFunction): BossTimerState?
	local ok, result = pcall(function()
		return remote:InvokeServer()
	end)

	if ok then
		return normalizeTimerState(result)
	end

	warnWithPrefix(string.format("Remote %s failed: %s", remote.Name, tostring(result)))
	return nil
end

function BossArenaTimerController:_getPlayerGui(): PlayerGui
	return LOCAL_PLAYER:WaitForChild("PlayerGui")
end

function BossArenaTimerController:_ensureRemotes(): BossTimerRemotes?
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

	local getState = bossArenaFolder:WaitForChild(GET_TIMER_STATE_REMOTE_NAME, 30)
	local stateChanged = bossArenaFolder:WaitForChild(TIMER_STATE_CHANGED_REMOTE_NAME, 30)

	if not (getState and getState:IsA("RemoteFunction")) then
		warnWithPrefix("BossArena.GetEncounterTimerState is missing.")
		return nil
	end
	if not (stateChanged and stateChanged:IsA("RemoteEvent")) then
		warnWithPrefix("BossArena.EncounterTimerStateChanged is missing.")
		return nil
	end

	self._remotes = {
		getState = getState,
		stateChanged = stateChanged,
	}

	return self._remotes
end

function BossArenaTimerController:_ensureUi(): BossTimerUi
	if self._ui and self._ui.root.Parent ~= nil then
		return self._ui
	end

	local playerGui = self:_getPlayerGui()
	local mainInterface = playerGui:WaitForChild("MainInterface", 30)
	if not (mainInterface and mainInterface:IsA("ScreenGui")) then
		error("[BossArenaTimerController] PlayerGui.MainInterface is missing.", 0)
	end

	local root = mainInterface:WaitForChild("BossFightTimer", 30)
	if not (root and root:IsA("Frame")) then
		error("[BossArenaTimerController] PlayerGui.MainInterface.BossFightTimer is missing.", 0)
	end

	local label = root:WaitForChild("Time", 30)
	if not (label and label:IsA("TextLabel")) then
		error("[BossArenaTimerController] BossFightTimer.Time is missing.", 0)
	end

	root.Visible = false
	label.Text = "180"

	self._ui = {
		root = root,
		label = label,
	}

	return self._ui
end

function BossArenaTimerController:_hideTimer()
	local ui = self:_ensureUi()
	self._currentState = nil
	self._lastDisplayedRemaining = nil
	ui.root.Visible = false
end

function BossArenaTimerController:_renderRemaining()
	local state = self._currentState
	if state == nil then
		self:_hideTimer()
		return
	end

	local ui = self:_ensureUi()
	local remainingSeconds = math.max(0, math.ceil(state.endsAtServerTime - Workspace:GetServerTimeNow()))
	if remainingSeconds ~= self._lastDisplayedRemaining then
		self._lastDisplayedRemaining = remainingSeconds
		ui.label.Text = tostring(remainingSeconds)
	end
	ui.root.Visible = true
end

function BossArenaTimerController:_renderState(state: BossTimerState?)
	local normalizedState = normalizeTimerState(state)
	if normalizedState == nil then
		self:_hideTimer()
		return
	end

	self._currentState = normalizedState
	self._lastDisplayedRemaining = nil
	self:_renderRemaining()
end

function BossArenaTimerController:_refreshState()
	local remotes = self:_ensureRemotes()
	if not remotes then
		self:_hideTimer()
		return
	end

	self:_renderState(invokeRemote(remotes.getState))
end

function BossArenaTimerController:_bindRemotes()
	local remotes = self:_ensureRemotes()
	if not remotes then
		return
	end

	if self._stateChangedConnection then
		self._stateChangedConnection:Disconnect()
	end

	self._stateChangedConnection = remotes.stateChanged.OnClientEvent:Connect(function(state: BossTimerState?)
		self:_renderState(state)
	end)
end

function BossArenaTimerController:_bindRenderLoop()
	if self._renderConnection then
		self._renderConnection:Disconnect()
	end

	self._renderConnection = RunService.RenderStepped:Connect(function()
		if self._currentState ~= nil then
			self:_renderRemaining()
		end
	end)
end

function BossArenaTimerController:OnStart()
	if self._started then
		return
	end
	self._started = true

	if RunService:IsClient() ~= true or not isEnabledForPlace() then
		return
	end

	self:_ensureUi()
	self:_bindRemotes()
	self:_bindRenderLoop()
	self:_refreshState()
end

return BossArenaTimerController
