local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Spring = require(ReplicatedStorage.Common.Spring)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local LOCAL_PLAYER = Players.LocalPlayer
local ACTIVE_PROFILE_ID = "boss_arena"
local REMOTES_FOLDER_NAME = "Remotes"
local BOSS_ARENA_FOLDER_NAME = "BossArena"
local GET_PLAYER_HEALTH_STATE_REMOTE_NAME = "GetPlayerHealthState"
local PLAYER_HEALTH_STATE_CHANGED_REMOTE_NAME = "PlayerHealthStateChanged"
local SPRING_DAMPING_RATIO = 0.85
local SPRING_FREQUENCY = 6

type PlayerHealthEntry = {
	userId: number,
	username: string,
	currentHealth: number,
	maxHealth: number,
	alive: boolean,
}

type PlayerHealthState = {
	active: boolean,
	roster: { PlayerHealthEntry },
	serverTime: number,
}

type HealthbarUi = {
	root: Frame,
	fill: Frame,
	amount: TextLabel,
	username: TextLabel?,
}

type CombatHudUi = {
	root: Frame,
	statsRoot: Frame,
	statsHealthbar: HealthbarUi,
	alliesRoot: Frame,
	allyTemplate: Frame,
	controls: { [string]: Frame },
}

type CombatHudRemotes = {
	getState: RemoteFunction,
	stateChanged: RemoteEvent,
}

local CombatHUDController = {
	_started = false,
	_ui = nil :: CombatHudUi?,
	_remotes = nil :: CombatHudRemotes?,
	_allyRows = {} :: { [number]: HealthbarUi },
	_healthStateConnection = nil :: RBXScriptConnection?,
	_preferredInputConnection = nil :: RBXScriptConnection?,
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
end

local function warnWithPrefix(message: string)
	warn(string.format("[CombatHUDController] %s", message))
end

local function waitForChildOfClass(parent: Instance, childName: string, className: string, timeout: number?): Instance
	local child = parent:WaitForChild(childName, timeout or 30)
	if not (child and child:IsA(className)) then
		error(string.format("[CombatHUDController] %s.%s must be a %s.", parent:GetFullName(), childName, className), 0)
	end

	return child
end

local function getPlayerGui(): PlayerGui
	return LOCAL_PLAYER:WaitForChild("PlayerGui")
end

local function getHealthPercent(entry: PlayerHealthEntry): number
	local maxHealth = tonumber(entry.maxHealth) or 0
	if maxHealth <= 0 then
		return 0
	end

	return math.clamp((tonumber(entry.currentHealth) or 0) / maxHealth, 0, 1)
end

local function setAmountText(label: TextLabel, currentHealth: number)
	label.Text = tostring(math.max(0, math.round(tonumber(currentHealth) or 0)))
end

local function resolveHealthbarUi(root: Frame, requireUsername: boolean): HealthbarUi
	local healthbar = waitForChildOfClass(root, "Healthbar", "Frame") :: Frame
	local fill = waitForChildOfClass(healthbar, "Fill", "Frame") :: Frame
	local amount = waitForChildOfClass(healthbar, "Amount", "TextLabel") :: TextLabel
	local username = healthbar:FindFirstChild("Username")

	if requireUsername and not (username and username:IsA("TextLabel")) then
		error(string.format("[CombatHUDController] %s.Username must be a TextLabel.", healthbar:GetFullName()), 0)
	end

	return {
		root = root,
		fill = fill,
		amount = amount,
		username = if username and username:IsA("TextLabel") then username else nil,
	}
end

local function isGamepadInput(inputType: Enum.UserInputType): boolean
	return string.find(inputType.Name, "Gamepad") ~= nil
end

local function getPreferredInputName(): string?
	local ok, preferredInput = pcall(function()
		return UserInputService.PreferredInput
	end)

	if ok and typeof(preferredInput) == "EnumItem" then
		return preferredInput.Name
	end

	return nil
end

local function getFallbackInputName(): string
	local lastInputType = UserInputService:GetLastInputType()
	if lastInputType == Enum.UserInputType.Touch then
		return "Touch"
	end
	if lastInputType == Enum.UserInputType.Keyboard
		or lastInputType == Enum.UserInputType.MouseButton1
		or lastInputType == Enum.UserInputType.MouseButton2
		or lastInputType == Enum.UserInputType.MouseButton3
		or lastInputType == Enum.UserInputType.MouseMovement
		or lastInputType == Enum.UserInputType.MouseWheel then
		return "KeyboardAndMouse"
	end
	if isGamepadInput(lastInputType) then
		return "Gamepad"
	end

	return "KeyboardAndMouse"
end

local function isPlayStationGamepad(): boolean
	local stringOk, buttonName = pcall(function()
		return UserInputService:GetStringForKeyCode(Enum.KeyCode.ButtonA)
	end)
	if stringOk and typeof(buttonName) == "string" and string.find(buttonName, "Cross") ~= nil then
		return true
	end

	local imageOk, image = pcall(function()
		return UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonA)
	end)
	if imageOk and typeof(image) == "string" and string.find(string.lower(image), "playstation") ~= nil then
		return true
	end

	return false
end

local function showOnlyControlFrame(controls: { [string]: Frame }, activeName: string)
	for name, frame in pairs(controls) do
		frame.Visible = name == activeName
	end
end

local function normalizeHealthState(state: any): PlayerHealthState?
	if typeof(state) ~= "table" then
		return nil
	end

	local roster = {}
	if typeof(state.roster) == "table" then
		for _, entry in ipairs(state.roster) do
			if typeof(entry) ~= "table" then
				continue
			end

			local userId = math.floor(tonumber(entry.userId) or 0)
			local maxHealth = tonumber(entry.maxHealth) or 0
			if userId <= 0 or maxHealth <= 0 then
				continue
			end

			table.insert(roster, {
				userId = userId,
				username = if typeof(entry.username) == "string" and entry.username ~= "" then entry.username else tostring(userId),
				currentHealth = math.max(0, tonumber(entry.currentHealth) or 0),
				maxHealth = math.max(1, maxHealth),
				alive = entry.alive == true,
			})
		end
	end

	return {
		active = state.active == true,
		roster = roster,
		serverTime = tonumber(state.serverTime) or 0,
	}
end

function CombatHUDController:_ensureUi(): CombatHudUi
	if self._ui and self._ui.root.Parent ~= nil then
		return self._ui
	end

	local playerGui = getPlayerGui()
	local mainInterface = waitForChildOfClass(playerGui, "MainInterface", "ScreenGui") :: ScreenGui
	local root = waitForChildOfClass(mainInterface, "CombatHUD", "Frame") :: Frame
	local statsRoot = waitForChildOfClass(root, "Stats", "Frame") :: Frame
	local alliesRoot = waitForChildOfClass(root, "Allies", "Frame") :: Frame
	local allyTemplate = waitForChildOfClass(alliesRoot, "Template", "Frame") :: Frame

	local controls = {
		PCControls = waitForChildOfClass(root, "PCControls", "Frame") :: Frame,
		MobileControls = waitForChildOfClass(root, "MobileControls", "Frame") :: Frame,
		XBOXControls = waitForChildOfClass(root, "XBOXControls", "Frame") :: Frame,
		PlayStationControls = waitForChildOfClass(root, "PlayStationControls", "Frame") :: Frame,
	}

	allyTemplate.Visible = false
	root.Visible = false

	self._ui = {
		root = root,
		statsRoot = statsRoot,
		statsHealthbar = resolveHealthbarUi(statsRoot, false),
		alliesRoot = alliesRoot,
		allyTemplate = allyTemplate,
		controls = controls,
	}

	self:_updateControlsVisibility()
	return self._ui
end

function CombatHUDController:_ensureRemotes(): CombatHudRemotes?
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

	local getState = bossArenaFolder:WaitForChild(GET_PLAYER_HEALTH_STATE_REMOTE_NAME, 30)
	local stateChanged = bossArenaFolder:WaitForChild(PLAYER_HEALTH_STATE_CHANGED_REMOTE_NAME, 30)

	if not (getState and getState:IsA("RemoteFunction")) then
		warnWithPrefix("BossArena.GetPlayerHealthState is missing.")
		return nil
	end
	if not (stateChanged and stateChanged:IsA("RemoteEvent")) then
		warnWithPrefix("BossArena.PlayerHealthStateChanged is missing.")
		return nil
	end

	self._remotes = {
		getState = getState,
		stateChanged = stateChanged,
	}

	return self._remotes
end

function CombatHUDController:_updateControlsVisibility()
	local ui = self:_ensureUi()
	local preferredInputName = getPreferredInputName() or getFallbackInputName()

	if preferredInputName == "Touch" then
		showOnlyControlFrame(ui.controls, "MobileControls")
	elseif preferredInputName == "Gamepad" then
		showOnlyControlFrame(ui.controls, if isPlayStationGamepad() then "PlayStationControls" else "XBOXControls")
	else
		showOnlyControlFrame(ui.controls, "PCControls")
	end
end

function CombatHUDController:_bindInputModeChanges()
	if self._preferredInputConnection then
		self._preferredInputConnection:Disconnect()
		self._preferredInputConnection = nil
	end

	local ok, connection = pcall(function()
		return UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
			self:_updateControlsVisibility()
		end)
	end)

	if ok and connection then
		self._preferredInputConnection = connection
		return
	end

	self._preferredInputConnection = UserInputService.LastInputTypeChanged:Connect(function()
		self:_updateControlsVisibility()
	end)
end

function CombatHUDController:_renderHealthbar(healthbar: HealthbarUi, entry: PlayerHealthEntry)
	setAmountText(healthbar.amount, entry.currentHealth)
	if healthbar.username then
		healthbar.username.Text = entry.username
	end

	Spring.target(healthbar.fill, SPRING_DAMPING_RATIO, SPRING_FREQUENCY, {
		Size = UDim2.new(getHealthPercent(entry), 0, 1, 0),
	})
end

function CombatHUDController:_getOrCreateAllyRow(entry: PlayerHealthEntry): HealthbarUi
	local existing = self._allyRows[entry.userId]
	if existing and existing.root.Parent ~= nil then
		return existing
	end

	local ui = self:_ensureUi()
	local row = ui.allyTemplate:Clone()
	row.Name = string.format("Ally_%d", entry.userId)
	row.LayoutOrder = #self._allyRows + 1
	row.Visible = true
	row.Parent = ui.alliesRoot

	local healthbar = resolveHealthbarUi(row, true)
	self._allyRows[entry.userId] = healthbar
	return healthbar
end

function CombatHUDController:_removeStaleAllyRows(activeAllyUserIds: { [number]: boolean })
	for userId, healthbar in pairs(self._allyRows) do
		if activeAllyUserIds[userId] == true then
			continue
		end

		Spring.stop(healthbar.fill, "Size")
		healthbar.root:Destroy()
		self._allyRows[userId] = nil
	end
end

function CombatHUDController:_hideHud()
	local ui = self:_ensureUi()
	Spring.stop(ui.statsHealthbar.fill, "Size")
	for _, healthbar in pairs(self._allyRows) do
		Spring.stop(healthbar.fill, "Size")
		healthbar.root:Destroy()
	end

	table.clear(self._allyRows)
	ui.allyTemplate.Visible = false
	ui.root.Visible = false
end

function CombatHUDController:_renderState(state: PlayerHealthState?)
	local ui = self:_ensureUi()
	if state == nil or state.active ~= true then
		self:_hideHud()
		return
	end

	local localEntry = nil :: PlayerHealthEntry?
	local activeAllyUserIds = {}

	for index, entry in ipairs(state.roster) do
		if entry.userId == LOCAL_PLAYER.UserId then
			localEntry = entry
			continue
		end

		activeAllyUserIds[entry.userId] = true
		local allyRow = self:_getOrCreateAllyRow(entry)
		allyRow.root.LayoutOrder = index
		self:_renderHealthbar(allyRow, entry)
	end

	self:_removeStaleAllyRows(activeAllyUserIds)

	ui.statsRoot.Visible = localEntry ~= nil
	if localEntry then
		self:_renderHealthbar(ui.statsHealthbar, localEntry)
	end

	ui.allyTemplate.Visible = false
	ui.root.Visible = true
end

function CombatHUDController:_refreshState()
	local remotes = self:_ensureRemotes()
	if not remotes then
		self:_hideHud()
		return
	end

	local ok, result = pcall(function()
		return remotes.getState:InvokeServer()
	end)

	if not ok then
		warnWithPrefix(string.format("GetPlayerHealthState failed: %s", tostring(result)))
		self:_hideHud()
		return
	end

	self:_renderState(normalizeHealthState(result))
end

function CombatHUDController:_bindRemotes()
	local remotes = self:_ensureRemotes()
	if not remotes then
		return
	end

	if self._healthStateConnection then
		self._healthStateConnection:Disconnect()
	end

	self._healthStateConnection = remotes.stateChanged.OnClientEvent:Connect(function(state: PlayerHealthState?)
		self:_renderState(normalizeHealthState(state))
	end)
end

function CombatHUDController:OnStart()
	if self._started then
		return
	end
	self._started = true

	if RunService:IsClient() ~= true or not isEnabledForPlace() then
		return
	end

	self:_ensureUi()
	self:_bindInputModeChanges()
	self:_bindRemotes()
	self:_refreshState()
end

return CombatHUDController
