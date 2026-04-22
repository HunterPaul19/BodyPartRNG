local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)
local Notify = require(ReplicatedStorage.Shared.UI.Notify)
local UIController = require(script.Parent.UIController)

local LOCAL_PLAYER = Players.LocalPlayer
local REMOTES_FOLDER_NAME = "Remotes"
local BOSS_ARENA_FOLDER_NAME = "BossArena"
local GET_STATE_REMOTE_NAME = "GetStudioPickerState"
local SELECT_REMOTE_NAME = "SelectStudioBoss"
local STATE_CHANGED_REMOTE_NAME = "StudioPickerStateChanged"
local SCREEN_GUI_NAME = "BossArenaStudioPicker"
local ACTIVE_PROFILE_ID = "boss_arena"

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

type PickerRemotes = {
	getState: RemoteFunction,
	selectBoss: RemoteFunction,
	stateChanged: RemoteEvent,
}

type PickerUi = {
	screenGui: ScreenGui,
	statusLabel: TextLabel,
	buttonList: ScrollingFrame,
	buttonLayout: UIListLayout,
	footerLabel: TextLabel,
	buttonsByBossId: { [string]: TextButton },
}

local BossArenaStudioPickerController = {
	_started = false,
	_remotes = nil :: PickerRemotes?,
	_ui = nil :: PickerUi?,
	_currentState = nil :: PickerState?,
	_selectionInFlight = false,
	_stateChangedConnection = nil :: RBXScriptConnection?,
	_characterAddedConnection = nil :: RBXScriptConnection?,
	_canvasConnection = nil :: RBXScriptConnection?,
}

local function isEnabledForPlace(): boolean
	return RunService:IsStudio() and PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
end

local function createCorner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function createStroke(parent: Instance, color: Color3, transparency: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Transparency = transparency
	stroke.Parent = parent
	return stroke
end

local function invokeRemote(remote: RemoteFunction, payload: any?): any?
	local ok, result = pcall(function()
		if payload ~= nil then
			return remote:InvokeServer(payload)
		end

		return remote:InvokeServer()
	end)

	if ok then
		return result
	end

	warn(string.format("[BossArenaStudioPickerController] Remote %s failed: %s", remote.Name, tostring(result)))
	return nil
end

function BossArenaStudioPickerController:_getPlayerGui(): PlayerGui
	return LOCAL_PLAYER:WaitForChild("PlayerGui")
end

function BossArenaStudioPickerController:_ensureRemotes(): PickerRemotes?
	if self._remotes then
		return self._remotes
	end

	local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, 30)
	if not (remotesFolder and remotesFolder:IsA("Folder")) then
		warn("[BossArenaStudioPickerController] ReplicatedStorage.Remotes is missing.")
		return nil
	end

	local bossArenaFolder = remotesFolder:WaitForChild(BOSS_ARENA_FOLDER_NAME, 30)
	if not (bossArenaFolder and bossArenaFolder:IsA("Folder")) then
		warn("[BossArenaStudioPickerController] ReplicatedStorage.Remotes.BossArena is missing.")
		return nil
	end

	local getState = bossArenaFolder:WaitForChild(GET_STATE_REMOTE_NAME, 30)
	local selectBoss = bossArenaFolder:WaitForChild(SELECT_REMOTE_NAME, 30)
	local stateChanged = bossArenaFolder:WaitForChild(STATE_CHANGED_REMOTE_NAME, 30)

	if not (getState and getState:IsA("RemoteFunction")) then
		warn("[BossArenaStudioPickerController] BossArena.GetStudioPickerState is missing.")
		return nil
	end
	if not (selectBoss and selectBoss:IsA("RemoteFunction")) then
		warn("[BossArenaStudioPickerController] BossArena.SelectStudioBoss is missing.")
		return nil
	end
	if not (stateChanged and stateChanged:IsA("RemoteEvent")) then
		warn("[BossArenaStudioPickerController] BossArena.StudioPickerStateChanged is missing.")
		return nil
	end

	self._remotes = {
		getState = getState,
		selectBoss = selectBoss,
		stateChanged = stateChanged,
	}

	return self._remotes
end

function BossArenaStudioPickerController:_updateCanvasSize()
	local ui = self._ui
	if not ui then
		return
	end

	ui.buttonList.CanvasSize = UDim2.new(0, 0, 0, ui.buttonLayout.AbsoluteContentSize.Y + 12)
end

function BossArenaStudioPickerController:_ensureUi(): PickerUi
	if self._ui and self._ui.screenGui.Parent then
		return self._ui
	end

	local playerGui = self:_getPlayerGui()
	local existing = playerGui:FindFirstChild(SCREEN_GUI_NAME)
	if existing then
		existing:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = SCREEN_GUI_NAME
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 200
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.BackgroundColor3 = Color3.fromRGB(7, 11, 18)
	backdrop.BackgroundTransparency = 0.22
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(520, 540)
	panel.BackgroundColor3 = Color3.fromRGB(18, 24, 38)
	panel.BorderSizePixel = 0
	panel.Parent = backdrop
	createCorner(panel, 20)
	createStroke(panel, Color3.fromRGB(117, 138, 172), 0.35)

	local panelGradient = Instance.new("UIGradient")
	panelGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(26, 35, 56)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(13, 18, 29)),
	})
	panelGradient.Rotation = 90
	panelGradient.Parent = panel

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.fromOffset(28, 22)
	titleLabel.Size = UDim2.new(1, -56, 0, 42)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Text = "Studio Boss Picker"
	titleLabel.TextColor3 = Color3.fromRGB(245, 248, 255)
	titleLabel.TextSize = 26
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = panel

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.BackgroundTransparency = 1
	statusLabel.Position = UDim2.fromOffset(28, 68)
	statusLabel.Size = UDim2.new(1, -56, 0, 54)
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.Text = "Choose a boss encounter or open the test suite."
	statusLabel.TextColor3 = Color3.fromRGB(186, 196, 214)
	statusLabel.TextSize = 16
	statusLabel.TextWrapped = true
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextYAlignment = Enum.TextYAlignment.Top
	statusLabel.Parent = panel

	local buttonList = Instance.new("ScrollingFrame")
	buttonList.Name = "BossList"
	buttonList.BackgroundColor3 = Color3.fromRGB(10, 14, 24)
	buttonList.BorderSizePixel = 0
	buttonList.Position = UDim2.fromOffset(24, 136)
	buttonList.Size = UDim2.new(1, -48, 1, -214)
	buttonList.CanvasSize = UDim2.new()
	buttonList.ScrollBarThickness = 5
	buttonList.AutomaticCanvasSize = Enum.AutomaticSize.None
	buttonList.Parent = panel
	createCorner(buttonList, 16)
	createStroke(buttonList, Color3.fromRGB(103, 122, 152), 0.55)

	local buttonPadding = Instance.new("UIPadding")
	buttonPadding.PaddingTop = UDim.new(0, 10)
	buttonPadding.PaddingBottom = UDim.new(0, 10)
	buttonPadding.PaddingLeft = UDim.new(0, 10)
	buttonPadding.PaddingRight = UDim.new(0, 10)
	buttonPadding.Parent = buttonList

	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.Padding = UDim.new(0, 10)
	buttonLayout.FillDirection = Enum.FillDirection.Vertical
	buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	buttonLayout.SortOrder = Enum.SortOrder.LayoutOrder
	buttonLayout.Parent = buttonList

	local footerLabel = Instance.new("TextLabel")
	footerLabel.Name = "Footer"
	footerLabel.BackgroundTransparency = 1
	footerLabel.Position = UDim2.fromOffset(28, 472)
	footerLabel.Size = UDim2.new(1, -56, 0, 38)
	footerLabel.Font = Enum.Font.Gotham
	footerLabel.Text = "Studio only. First valid selection locks the arena until the encounter resets."
	footerLabel.TextColor3 = Color3.fromRGB(140, 152, 176)
	footerLabel.TextSize = 14
	footerLabel.TextWrapped = true
	footerLabel.TextXAlignment = Enum.TextXAlignment.Left
	footerLabel.TextYAlignment = Enum.TextYAlignment.Top
	footerLabel.Parent = panel

	self._ui = {
		screenGui = screenGui,
		statusLabel = statusLabel,
		buttonList = buttonList,
		buttonLayout = buttonLayout,
		footerLabel = footerLabel,
		buttonsByBossId = {},
	}

	if self._canvasConnection then
		self._canvasConnection:Disconnect()
	end
	self._canvasConnection = buttonLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		self:_updateCanvasSize()
	end)

	return self._ui
end

function BossArenaStudioPickerController:_setVisible(isVisible: boolean)
	local ui = self:_ensureUi()
	if ui.screenGui.Enabled == isVisible then
		return
	end

	if isVisible then
		UIController:OpenContainer(ui.screenGui)
	else
		UIController:CloseContainer(ui.screenGui)
	end
end

function BossArenaStudioPickerController:_setStatus(text: string, color: Color3?)
	local ui = self:_ensureUi()
	ui.statusLabel.Text = text
	ui.statusLabel.TextColor3 = color or Color3.fromRGB(186, 196, 214)
end

function BossArenaStudioPickerController:_applyButtonState(button: TextButton, enabled: boolean, highlighted: boolean)
	button.Active = enabled
	button.AutoButtonColor = false
	button.TextColor3 = if enabled then Color3.fromRGB(244, 247, 255) else Color3.fromRGB(138, 149, 169)
	button.BackgroundColor3 = if highlighted
		then Color3.fromRGB(112, 76, 41)
		elseif enabled
		then Color3.fromRGB(34, 46, 69)
		else Color3.fromRGB(24, 31, 47)
end

function BossArenaStudioPickerController:_warnMenuError(message: string)
	warn(string.format("[BossArenaStudioPickerController] %s", message))
end

function BossArenaStudioPickerController:_handleBossSelected(bossId: string)
	local remotes = self:_ensureRemotes()
	if not remotes or self._selectionInFlight then
		return
	end

	self._selectionInFlight = true
	self:_renderState(self._currentState)

	local result = invokeRemote(remotes.selectBoss, {
		bossId = bossId,
	})
	self._selectionInFlight = false

	if typeof(result) ~= "table" then
		self:_warnMenuError("Boss selection failed. The server did not return a valid response.")
		self:_refreshState()
		return
	end

	if typeof(result.state) == "table" then
		self:_renderState(result.state)
	end

	if result.ok == true then
		self:_setVisible(false)
		Notify.Show(tostring(result.message or "Boss spawned."), {
			channel = "system",
			duration = 4,
		})
		return
	end

	self:_warnMenuError(tostring(result.message or "Boss selection failed."))

	if typeof(result.state) == "table" and result.state.shouldPrompt ~= true then
		self:_setVisible(false)
	end
end

function BossArenaStudioPickerController:_createBossButton(entry: PickerBossEntry, layoutOrder: number): TextButton
	local ui = self:_ensureUi()

	local button = Instance.new("TextButton")
	button.Name = entry.id
	button.Size = UDim2.new(1, 0, 0, 54)
	button.BackgroundColor3 = Color3.fromRGB(34, 46, 69)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.Text = entry.displayName
	button.TextSize = 17
	button.LayoutOrder = layoutOrder
	button.Parent = ui.buttonList
	createCorner(button, 12)
	createStroke(button, Color3.fromRGB(130, 148, 179), 0.45)

	UIController:CreateButton(button, function()
		BossArenaStudioPickerController:_handleBossSelected(entry.id)
	end)

	ui.buttonsByBossId[entry.id] = button
	return button
end

function BossArenaStudioPickerController:_syncBossButtons(bosses: { PickerBossEntry })
	local ui = self:_ensureUi()
	local activeBossIds = {}

	for index, entry in ipairs(bosses) do
		activeBossIds[entry.id] = true
		local button = ui.buttonsByBossId[entry.id]
		if not button then
			button = self:_createBossButton(entry, index)
		end

		button.LayoutOrder = index
		button.Text = entry.displayName
	end

	for bossId, button in pairs(ui.buttonsByBossId) do
		if activeBossIds[bossId] ~= true then
			ui.buttonsByBossId[bossId] = nil
			button:Destroy()
		end
	end

	self:_updateCanvasSize()
end

function BossArenaStudioPickerController:_renderState(state: PickerState?)
	if typeof(state) ~= "table" then
		return
	end

	self._currentState = state
	local ui = self:_ensureUi()
	local bosses = if typeof(state.bosses) == "table" then state.bosses else {}
	self:_syncBossButtons(bosses)

	local statusText = "Choose a boss encounter or open the test suite."
	local statusColor = Color3.fromRGB(186, 196, 214)
	if self._selectionInFlight then
		statusText = "Spawning boss..."
		statusColor = Color3.fromRGB(253, 224, 71)
	elseif typeof(state.message) == "string" and state.message ~= "" then
		statusText = state.message
		if state.canSelect then
			statusColor = Color3.fromRGB(186, 196, 214)
		else
			statusColor = Color3.fromRGB(248, 166, 166)
		end
	end

	self:_setStatus(statusText, statusColor)
	ui.footerLabel.Text = if state.activeBossId ~= nil
		then string.format("Active boss: %s", state.activeBossId)
		else "Studio only. First valid selection locks the arena until the encounter resets."

	for bossId, button in pairs(ui.buttonsByBossId) do
		local enabled = state.canSelect == true and self._selectionInFlight ~= true
		local highlighted = state.activeBossId == bossId
		self:_applyButtonState(button, enabled, highlighted)
	end

	if state.shouldPrompt == true then
		self:_setVisible(true)
	else
		self:_setVisible(false)
	end
end

function BossArenaStudioPickerController:_refreshState()
	local remotes = self:_ensureRemotes()
	if not remotes then
		return
	end

	local state = invokeRemote(remotes.getState)
	if typeof(state) == "table" then
		self:_renderState(state)
	end
end

function BossArenaStudioPickerController:_bindRemotes()
	local remotes = self:_ensureRemotes()
	if not remotes then
		return
	end

	if self._stateChangedConnection then
		self._stateChangedConnection:Disconnect()
	end

	self._stateChangedConnection = remotes.stateChanged.OnClientEvent:Connect(function(state: PickerState)
		self:_renderState(state)
	end)
end

function BossArenaStudioPickerController:_bindCharacterLifecycle()
	if self._characterAddedConnection then
		self._characterAddedConnection:Disconnect()
	end

	self._characterAddedConnection = LOCAL_PLAYER.CharacterAdded:Connect(function()
		task.defer(function()
			self:_refreshState()
		end)
	end)
end

function BossArenaStudioPickerController:OnStart()
	if self._started then
		return
	end
	self._started = true

	if not isEnabledForPlace() then
		return
	end

	self:_ensureUi()
	self:_bindRemotes()
	self:_bindCharacterLifecycle()
	self:_refreshState()

	if LOCAL_PLAYER.Character then
		task.defer(function()
			self:_refreshState()
		end)
	end
end

return BossArenaStudioPickerController
