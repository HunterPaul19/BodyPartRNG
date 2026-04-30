local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Spring = require(ReplicatedStorage.Common.Spring)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local LOCAL_PLAYER = Players.LocalPlayer
local BOSS_ARENA_PROFILE_ID = "boss_arena"
local MAIN_PROFILE_ID = "main"
local REMOTES_FOLDER_NAME = "Remotes"
local BOSS_ARENA_FOLDER_NAME = "BossArena"
local PVP_FOLDER_NAME = "PvP"
local GET_PLAYER_HEALTH_STATE_REMOTE_NAME = "GetPlayerHealthState"
local PLAYER_HEALTH_STATE_CHANGED_REMOTE_NAME = "PlayerHealthStateChanged"
local GET_PVP_STATE_REMOTE_NAME = "GetPvpState"
local PVP_STATE_CHANGED_REMOTE_NAME = "PvpStateChanged"
local SPRING_DAMPING_RATIO = 0.85
local SPRING_FREQUENCY = 6
local GENERATED_ALLY_ROW_ATTRIBUTE = "CombatHudGeneratedAllyRow"

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

type CombatHudBackend = {
	folderName: string,
	getStateRemoteName: string,
	stateChangedRemoteName: string,
}

local CombatHUDController = {
	_started = false,
	_ui = nil :: CombatHudUi?,
	_remotes = nil :: CombatHudRemotes?,
	_allyRows = {} :: { [number]: HealthbarUi },
	_healthStateConnection = nil :: RBXScriptConnection?,
	_preferredInputConnection = nil :: RBXScriptConnection?,
	_remoteBindingStarted = false,
	_uiBindingStarted = false,
	_warnedMissingUi = false,
}

local function isEnabledForPlace(): boolean
	local activeProfileId = PlaceProfile.GetActiveProfile().id
	return activeProfileId == BOSS_ARENA_PROFILE_ID or activeProfileId == MAIN_PROFILE_ID
end

local function getBackend(): CombatHudBackend?
	local activeProfileId = PlaceProfile.GetActiveProfile().id
	if activeProfileId == BOSS_ARENA_PROFILE_ID then
		return {
			folderName = BOSS_ARENA_FOLDER_NAME,
			getStateRemoteName = GET_PLAYER_HEALTH_STATE_REMOTE_NAME,
			stateChangedRemoteName = PLAYER_HEALTH_STATE_CHANGED_REMOTE_NAME,
		}
	end
	if activeProfileId == MAIN_PROFILE_ID then
		return {
			folderName = PVP_FOLDER_NAME,
			getStateRemoteName = GET_PVP_STATE_REMOTE_NAME,
			stateChangedRemoteName = PVP_STATE_CHANGED_REMOTE_NAME,
		}
	end

	return nil
end

local function shouldShowHealthbars(): boolean
	return PlaceProfile.GetActiveProfile().id == BOSS_ARENA_PROFILE_ID
end

local function warnWithPrefix(message: string)
	Logger.Warn(string.format("[CombatHUDController] %s", message))
end

local function findChildOfClass(parent: Instance, childName: string, className: string): Instance?
	local child = parent:FindFirstChild(childName)
	if not (child and child:IsA(className)) then
		return nil
	end

	return child
end

local function getPlayerGui(): PlayerGui?
	local playerGui = LOCAL_PLAYER:FindFirstChild("PlayerGui")
	if playerGui and playerGui:IsA("PlayerGui") then
		return playerGui
	end

	return nil
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

local function isGeneratedAllyRow(row: Instance): boolean
	return row:GetAttribute(GENERATED_ALLY_ROW_ATTRIBUTE) == true
end

local function resolveHealthbarUi(root: Frame, requireUsername: boolean): HealthbarUi?
	local healthbar = findChildOfClass(root, "Healthbar", "Frame") :: Frame?
	if healthbar == nil then
		return nil
	end

	local fill = findChildOfClass(healthbar, "Fill", "Frame") :: Frame?
	local amount = findChildOfClass(healthbar, "Amount", "TextLabel") :: TextLabel?
	if fill == nil or amount == nil then
		return nil
	end

	local username = healthbar:FindFirstChild("Username")

	if requireUsername and not (username and username:IsA("TextLabel")) then
		return nil
	end

	return {
		root = root,
		fill = fill,
		amount = amount,
		username = if username and username:IsA("TextLabel") then username else nil,
	}
end

local function resolveAllyTemplate(alliesRoot: Frame): Frame?
	local explicitTemplate = findChildOfClass(alliesRoot, "Template", "Frame") :: Frame?
	if explicitTemplate and resolveHealthbarUi(explicitTemplate, true) ~= nil then
		return explicitTemplate
	end

	for _, child in ipairs(alliesRoot:GetChildren()) do
		if not child:IsA("Frame") or isGeneratedAllyRow(child) then
			continue
		end
		if child == explicitTemplate then
			continue
		end
		if resolveHealthbarUi(child, true) ~= nil then
			return child
		end
	end

	return nil
end

local function hideAuthoredAllyRows(alliesRoot: Frame)
	for _, child in ipairs(alliesRoot:GetChildren()) do
		if not child:IsA("Frame") or isGeneratedAllyRow(child) then
			continue
		end

		child.Visible = false
	end
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

local function isTouchOnlyInput(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.GamepadEnabled
end

local function getFallbackInputName(): string
	if isTouchOnlyInput() then
		return "Touch"
	end

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

function CombatHUDController:_warnMissingUi(missingPaths: { string })
	if self._warnedMissingUi == true then
		return
	end

	self._warnedMissingUi = true
	warnWithPrefix(string.format(
		"PlayerGui.MainInterface.CombatHUD is missing required UI children: %s.",
		table.concat(missingPaths, ", ")
	))
end

function CombatHUDController:_ensureUi(): CombatHudUi?
	if self._ui and self._ui.root.Parent ~= nil then
		return self._ui
	end

	local playerGui = getPlayerGui()
	if playerGui == nil then
		return nil
	end

	local mainInterface = findChildOfClass(playerGui, "MainInterface", "ScreenGui") :: ScreenGui?
	if mainInterface == nil then
		return nil
	end

	local root = findChildOfClass(mainInterface, "CombatHUD", "Frame") :: Frame?
	if root == nil then
		self:_warnMissingUi({ "MainInterface.CombatHUD" })
		return nil
	end

	local missingPaths = {}
	local statsRoot = findChildOfClass(root, "Stats", "Frame") :: Frame?
	local alliesRoot = findChildOfClass(root, "Allies", "Frame") :: Frame?

	if statsRoot == nil then
		table.insert(missingPaths, "CombatHUD.Stats")
	end
	if alliesRoot == nil then
		table.insert(missingPaths, "CombatHUD.Allies")
	end

	local allyTemplate = if alliesRoot then resolveAllyTemplate(alliesRoot) else nil
	if alliesRoot ~= nil and allyTemplate == nil then
		table.insert(missingPaths, "CombatHUD.Allies.Template or authored ally row")
	end

	if #missingPaths > 0 then
		self:_warnMissingUi(missingPaths)
		return nil
	end

	local statsHealthbar = resolveHealthbarUi(statsRoot, false)
	if statsHealthbar == nil then
		self:_warnMissingUi({ "CombatHUD.Stats.Healthbar.Fill", "CombatHUD.Stats.Healthbar.Amount" })
		return nil
	end

	local controls = {
		PCControls = findChildOfClass(root, "PCControls", "Frame") :: Frame?,
		MobileControls = findChildOfClass(root, "MobileControls", "Frame") :: Frame?,
		XBOXControls = findChildOfClass(root, "XBOXControls", "Frame") :: Frame?,
		PlayStationControls = findChildOfClass(root, "PlayStationControls", "Frame") :: Frame?,
	}
	if controls.PCControls == nil
		or controls.MobileControls == nil
		or controls.XBOXControls == nil
		or controls.PlayStationControls == nil then
		local missingControlPaths = {}
		if controls.PCControls == nil then
			table.insert(missingControlPaths, "CombatHUD.PCControls")
		end
		if controls.MobileControls == nil then
			table.insert(missingControlPaths, "CombatHUD.MobileControls")
		end
		if controls.XBOXControls == nil then
			table.insert(missingControlPaths, "CombatHUD.XBOXControls")
		end
		if controls.PlayStationControls == nil then
			table.insert(missingControlPaths, "CombatHUD.PlayStationControls")
		end

		self:_warnMissingUi(missingControlPaths)
		return nil
	end

	hideAuthoredAllyRows(alliesRoot)
	root.Visible = false

	self._ui = {
		root = root,
		statsRoot = statsRoot,
		statsHealthbar = statsHealthbar,
		alliesRoot = alliesRoot,
		allyTemplate = allyTemplate,
		controls = controls :: { [string]: Frame },
	}

	self:_updateControlsVisibility()
	return self._ui
end

function CombatHUDController:_ensureRemotes(): CombatHudRemotes?
	if self._remotes then
		return self._remotes
	end

	local backend = getBackend()
	if backend == nil then
		return nil
	end

	local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if not (remotesFolder and remotesFolder:IsA("Folder")) then
		return nil
	end

	local backendFolder = remotesFolder:FindFirstChild(backend.folderName)
	if not (backendFolder and backendFolder:IsA("Folder")) then
		return nil
	end

	local getState = backendFolder:FindFirstChild(backend.getStateRemoteName)
	local stateChanged = backendFolder:FindFirstChild(backend.stateChangedRemoteName)

	if not (getState and getState:IsA("RemoteFunction")) then
		warnWithPrefix(string.format("%s.%s is missing.", backend.folderName, backend.getStateRemoteName))
		return nil
	end
	if not (stateChanged and stateChanged:IsA("RemoteEvent")) then
		warnWithPrefix(string.format("%s.%s is missing.", backend.folderName, backend.stateChangedRemoteName))
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
	if ui == nil then
		return
	end

	local preferredInputName = if isTouchOnlyInput() then "Touch" else getPreferredInputName() or getFallbackInputName()

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
		Size = UDim2.new(1, 0, getHealthPercent(entry), 0),
	})
end

function CombatHUDController:_getOrCreateAllyRow(entry: PlayerHealthEntry): HealthbarUi?
	local existing = self._allyRows[entry.userId]
	if existing and existing.root.Parent ~= nil then
		return existing
	end

	local ui = self:_ensureUi()
	if ui == nil then
		return nil
	end

	local row = ui.allyTemplate:Clone()
	row.Name = string.format("Ally_%d", entry.userId)
	row.LayoutOrder = #self._allyRows + 1
	row:SetAttribute(GENERATED_ALLY_ROW_ATTRIBUTE, true)
	row.Visible = true
	row.Parent = ui.alliesRoot

	local healthbar = resolveHealthbarUi(row, true)
	if healthbar == nil then
		row:Destroy()
		return nil
	end

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
	if ui == nil then
		return
	end

	Spring.stop(ui.statsHealthbar.fill, "Size")
	for _, healthbar in pairs(self._allyRows) do
		Spring.stop(healthbar.fill, "Size")
		healthbar.root:Destroy()
	end

	table.clear(self._allyRows)
	hideAuthoredAllyRows(ui.alliesRoot)
	ui.root.Visible = false
end

function CombatHUDController:_renderState(state: PlayerHealthState?)
	local ui = self:_ensureUi()
	if ui == nil then
		return
	end

	if state == nil or state.active ~= true then
		self:_hideHud()
		return
	end

	if not shouldShowHealthbars() then
		Spring.stop(ui.statsHealthbar.fill, "Size")
		for _, healthbar in pairs(self._allyRows) do
			Spring.stop(healthbar.fill, "Size")
			healthbar.root:Destroy()
		end

		table.clear(self._allyRows)
		hideAuthoredAllyRows(ui.alliesRoot)
		ui.statsRoot.Visible = false
		ui.alliesRoot.Visible = false
		self:_updateControlsVisibility()
		ui.root.Visible = true
		return
	end

	hideAuthoredAllyRows(ui.alliesRoot)

	local localEntry = nil :: PlayerHealthEntry?
	local activeAllyUserIds = {}

	for index, entry in ipairs(state.roster) do
		if entry.userId == LOCAL_PLAYER.UserId then
			localEntry = entry
			continue
		end

		activeAllyUserIds[entry.userId] = true
		local allyRow = self:_getOrCreateAllyRow(entry)
		if allyRow then
			allyRow.root.LayoutOrder = index
			self:_renderHealthbar(allyRow, entry)
		end
	end

	self:_removeStaleAllyRows(activeAllyUserIds)

	ui.statsRoot.Visible = true
	ui.alliesRoot.Visible = true
	if localEntry then
		self:_renderHealthbar(ui.statsHealthbar, localEntry)
	end

	hideAuthoredAllyRows(ui.alliesRoot)
	self:_updateControlsVisibility()
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

function CombatHUDController:_startRemoteBinding()
	if self._remoteBindingStarted then
		return
	end

	self._remoteBindingStarted = true
	task.spawn(function()
		while self._started == true and self._remotes == nil do
			self:_bindRemotes()
			if self._remotes then
				self:_refreshState()
				return
			end

			task.wait(0.25)
		end
	end)
end

function CombatHUDController:_startUiBinding()
	if self._uiBindingStarted then
		return
	end

	self._uiBindingStarted = true
	task.spawn(function()
		while self._started == true do
			if self:_ensureUi() then
				self:_bindInputModeChanges()
				self:_startRemoteBinding()
				return
			end

			task.wait(0.25)
		end
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

	self:_startUiBinding()
end

return CombatHUDController
