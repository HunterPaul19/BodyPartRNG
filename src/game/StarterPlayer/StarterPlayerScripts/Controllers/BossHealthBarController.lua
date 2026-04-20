local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Spring = require(ReplicatedStorage.Common.Spring)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local LOCAL_PLAYER = Players.LocalPlayer
local REMOTES_FOLDER_NAME = "Remotes"
local BOSS_ARENA_FOLDER_NAME = "BossArena"
local GET_HEALTH_STATE_REMOTE_NAME = "GetBossHealthState"
local HEALTH_STATE_CHANGED_REMOTE_NAME = "BossHealthStateChanged"
local ACTIVE_PROFILE_ID = "boss_arena"
local SPRING_DAMPING_RATIO = 0.85
local SPRING_FREQUENCY = 6

type BossHealthState = {
	bossId: string,
	currentHealth: number,
	maxHealth: number,
}

type BossHealthRemotes = {
	getState: RemoteFunction,
	stateChanged: RemoteEvent,
}

type BossHealthUi = {
	root: Frame,
	fill: Frame,
	label: TextLabel,
}

local BossHealthBarController = {
	_started = false,
	_remotes = nil :: BossHealthRemotes?,
	_ui = nil :: BossHealthUi?,
	_stateChangedConnection = nil :: RBXScriptConnection?,
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
end

local function warnWithPrefix(message: string)
	warn(string.format("[BossHealthBarController] %s", message))
end

local function clampPercent(currentHealth: number, maxHealth: number): number
	if maxHealth <= 0 then
		return 0
	end

	return math.clamp(currentHealth / maxHealth, 0, 1)
end

local function formatHealthText(currentHealth: number, maxHealth: number): string
	return string.format("%d/%d HP", math.round(currentHealth), math.round(maxHealth))
end

local function invokeRemote(remote: RemoteFunction): BossHealthState?
	local ok, result = pcall(function()
		return remote:InvokeServer()
	end)

	if ok then
		return result
	end

	warnWithPrefix(string.format("Remote %s failed: %s", remote.Name, tostring(result)))
	return nil
end

function BossHealthBarController:_getPlayerGui(): PlayerGui
	return LOCAL_PLAYER:WaitForChild("PlayerGui")
end

function BossHealthBarController:_ensureRemotes(): BossHealthRemotes?
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

	local getState = bossArenaFolder:WaitForChild(GET_HEALTH_STATE_REMOTE_NAME, 30)
	local stateChanged = bossArenaFolder:WaitForChild(HEALTH_STATE_CHANGED_REMOTE_NAME, 30)

	if not (getState and getState:IsA("RemoteFunction")) then
		warnWithPrefix("BossArena.GetBossHealthState is missing.")
		return nil
	end
	if not (stateChanged and stateChanged:IsA("RemoteEvent")) then
		warnWithPrefix("BossArena.BossHealthStateChanged is missing.")
		return nil
	end

	self._remotes = {
		getState = getState,
		stateChanged = stateChanged,
	}

	return self._remotes
end

function BossHealthBarController:_ensureUi(): BossHealthUi
	if self._ui and self._ui.root.Parent ~= nil then
		return self._ui
	end

	local playerGui = self:_getPlayerGui()
	local mainInterface = playerGui:WaitForChild("MainInterface", 30)
	if not (mainInterface and mainInterface:IsA("ScreenGui")) then
		error("[BossHealthBarController] PlayerGui.MainInterface is missing.", 0)
	end

	local root = mainInterface:WaitForChild("BossHealthBar", 30)
	if not (root and root:IsA("Frame")) then
		error("[BossHealthBarController] PlayerGui.MainInterface.BossHealthBar is missing.", 0)
	end

	local frame = root:WaitForChild("Frame", 30)
	if not (frame and frame:IsA("Frame")) then
		error("[BossHealthBarController] BossHealthBar.Frame is missing.", 0)
	end

	local fill = frame:WaitForChild("Fill", 30)
	if not (fill and fill:IsA("Frame")) then
		error("[BossHealthBarController] BossHealthBar.Frame.Fill is missing.", 0)
	end

	local label = root:WaitForChild("HP", 30)
	if not (label and label:IsA("TextLabel")) then
		error("[BossHealthBarController] BossHealthBar.HP is missing.", 0)
	end

	Spring.stop(fill, "Size")
	fill.Size = UDim2.new(0, 0, 1, 0)
	root.Visible = false

	self._ui = {
		root = root,
		fill = fill,
		label = label,
	}

	return self._ui
end

function BossHealthBarController:_hideBar()
	local ui = self:_ensureUi()
	Spring.stop(ui.fill, "Size")
	ui.fill.Size = UDim2.new(0, 0, 1, 0)
	ui.root.Visible = false
end

function BossHealthBarController:_renderState(state: BossHealthState?)
	local ui = self:_ensureUi()

	if typeof(state) ~= "table" or typeof(state.currentHealth) ~= "number" or typeof(state.maxHealth) ~= "number" then
		self:_hideBar()
		return
	end

	if state.currentHealth <= 0 or state.maxHealth <= 0 then
		self:_hideBar()
		return
	end

	ui.root.Visible = true
	ui.label.Text = formatHealthText(state.currentHealth, state.maxHealth)
	Spring.target(ui.fill, SPRING_DAMPING_RATIO, SPRING_FREQUENCY, {
		Size = UDim2.new(clampPercent(state.currentHealth, state.maxHealth), 0, 1, 0),
	})
end

function BossHealthBarController:_refreshState()
	local remotes = self:_ensureRemotes()
	if not remotes then
		self:_hideBar()
		return
	end

	self:_renderState(invokeRemote(remotes.getState))
end

function BossHealthBarController:_bindRemotes()
	local remotes = self:_ensureRemotes()
	if not remotes then
		return
	end

	if self._stateChangedConnection then
		self._stateChangedConnection:Disconnect()
	end

	self._stateChangedConnection = remotes.stateChanged.OnClientEvent:Connect(function(state: BossHealthState?)
		self:_renderState(state)
	end)
end

function BossHealthBarController:OnStart()
	if self._started then
		return
	end
	self._started = true

	if RunService:IsClient() ~= true or not isEnabledForPlace() then
		return
	end

	self:_ensureUi()
	self:_bindRemotes()
	self:_refreshState()
end

return BossHealthBarController
