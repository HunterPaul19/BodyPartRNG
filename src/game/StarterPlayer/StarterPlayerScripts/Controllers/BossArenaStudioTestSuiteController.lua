local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)
local Notify = require(ReplicatedStorage.Shared.UI.Notify)
local UIController = require(script.Parent.UIController)

local LOCAL_PLAYER = Players.LocalPlayer
local ACTIVE_PROFILE_ID = "boss_arena"
local REMOTES_FOLDER_NAME = "Remotes"
local BOSS_ARENA_FOLDER_NAME = "BossArena"
local GET_STATE_REMOTE_NAME = "GetStudioTestSuiteState"
local RUN_MOVE_REMOTE_NAME = "RunStudioTestSuiteMove"
local RESET_REMOTE_NAME = "ResetStudioTestSuite"
local TELEPORT_REMOTE_NAME = "TeleportStudioTestSuitePlayer"
local STATE_CHANGED_REMOTE_NAME = "StudioTestSuiteStateChanged"
local SCREEN_GUI_NAME = "BossArenaStudioTestSuite"

type MoveEntry = {
	id: string,
	displayName: string,
	moduleId: string,
	tags: { string },
}

type BossEntry = {
	id: string,
	displayName: string,
	castingMoveId: string?,
	moves: { MoveEntry },
}

type TestSuiteState = {
	enabled: boolean,
	active: boolean,
	message: string?,
	bosses: { BossEntry },
}

type TestSuiteRemotes = {
	getState: RemoteFunction,
	runMove: RemoteFunction,
	reset: RemoteFunction,
	teleport: RemoteFunction,
	stateChanged: RemoteEvent,
}

type TestSuiteUi = {
	screenGui: ScreenGui,
	panel: Frame,
	statusLabel: TextLabel,
	scrollFrame: ScrollingFrame,
	listLayout: UIListLayout,
	buttonsByKey: { [string]: TextButton },
}

local BossArenaStudioTestSuiteController = {
	_started = false,
	_remotes = nil :: TestSuiteRemotes?,
	_ui = nil :: TestSuiteUi?,
	_currentState = nil :: TestSuiteState?,
	_requestInFlight = false,
	_stateChangedConnection = nil :: RBXScriptConnection?,
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

	warn(string.format("[BossArenaStudioTestSuiteController] Remote %s failed: %s", remote.Name, tostring(result)))
	return nil
end

local function formatMoveButtonText(move: MoveEntry): string
	return move.displayName
end

local function makeButtonKey(bossId: string, moveId: string): string
	return string.format("%s::%s", bossId, moveId)
end

function BossArenaStudioTestSuiteController:_getPlayerGui(): PlayerGui
	return LOCAL_PLAYER:WaitForChild("PlayerGui")
end

function BossArenaStudioTestSuiteController:_ensureRemotes(): TestSuiteRemotes?
	if self._remotes then
		return self._remotes
	end

	local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, 30)
	if not (remotesFolder and remotesFolder:IsA("Folder")) then
		warn("[BossArenaStudioTestSuiteController] ReplicatedStorage.Remotes is missing.")
		return nil
	end

	local bossArenaFolder = remotesFolder:WaitForChild(BOSS_ARENA_FOLDER_NAME, 30)
	if not (bossArenaFolder and bossArenaFolder:IsA("Folder")) then
		warn("[BossArenaStudioTestSuiteController] ReplicatedStorage.Remotes.BossArena is missing.")
		return nil
	end

	local getState = bossArenaFolder:WaitForChild(GET_STATE_REMOTE_NAME, 30)
	local runMove = bossArenaFolder:WaitForChild(RUN_MOVE_REMOTE_NAME, 30)
	local reset = bossArenaFolder:WaitForChild(RESET_REMOTE_NAME, 30)
	local teleport = bossArenaFolder:WaitForChild(TELEPORT_REMOTE_NAME, 30)
	local stateChanged = bossArenaFolder:WaitForChild(STATE_CHANGED_REMOTE_NAME, 30)

	if not (getState and getState:IsA("RemoteFunction")) then
		warn("[BossArenaStudioTestSuiteController] BossArena.GetStudioTestSuiteState is missing.")
		return nil
	end
	if not (runMove and runMove:IsA("RemoteFunction")) then
		warn("[BossArenaStudioTestSuiteController] BossArena.RunStudioTestSuiteMove is missing.")
		return nil
	end
	if not (reset and reset:IsA("RemoteFunction")) then
		warn("[BossArenaStudioTestSuiteController] BossArena.ResetStudioTestSuite is missing.")
		return nil
	end
	if not (teleport and teleport:IsA("RemoteFunction")) then
		warn("[BossArenaStudioTestSuiteController] BossArena.TeleportStudioTestSuitePlayer is missing.")
		return nil
	end
	if not (stateChanged and stateChanged:IsA("RemoteEvent")) then
		warn("[BossArenaStudioTestSuiteController] BossArena.StudioTestSuiteStateChanged is missing.")
		return nil
	end

	self._remotes = {
		getState = getState,
		runMove = runMove,
		reset = reset,
		teleport = teleport,
		stateChanged = stateChanged,
	}

	return self._remotes
end

function BossArenaStudioTestSuiteController:_updateCanvasSize()
	local ui = self._ui
	if not ui then
		return
	end

	ui.scrollFrame.CanvasSize = UDim2.new(0, 0, 0, ui.listLayout.AbsoluteContentSize.Y + 18)
end

function BossArenaStudioTestSuiteController:_ensureUi(): TestSuiteUi
	if self._ui and self._ui.screenGui.Parent ~= nil then
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
	screenGui.IgnoreGuiInset = false
	screenGui.DisplayOrder = 190
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.new(0, 18, 0.5, 0)
	panel.Size = UDim2.new(0, 430, 1, -48)
	panel.BackgroundColor3 = Color3.fromRGB(17, 22, 30)
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Parent = screenGui
	createCorner(panel, 8)
	createStroke(panel, Color3.fromRGB(117, 138, 172), 0.35)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.fromOffset(18, 14)
	titleLabel.Size = UDim2.new(1, -36, 0, 30)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Text = "Boss Test Suite"
	titleLabel.TextColor3 = Color3.fromRGB(246, 248, 252)
	titleLabel.TextSize = 22
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = panel

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.BackgroundTransparency = 1
	statusLabel.Position = UDim2.fromOffset(18, 48)
	statusLabel.Size = UDim2.new(1, -36, 0, 38)
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.Text = ""
	statusLabel.TextColor3 = Color3.fromRGB(184, 195, 211)
	statusLabel.TextSize = 14
	statusLabel.TextWrapped = true
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextYAlignment = Enum.TextYAlignment.Top
	statusLabel.Parent = panel

	local resetButton = Instance.new("TextButton")
	resetButton.Name = "Reset"
	resetButton.Position = UDim2.fromOffset(18, 94)
	resetButton.Size = UDim2.new(1, -36, 0, 36)
	resetButton.BackgroundColor3 = Color3.fromRGB(82, 54, 44)
	resetButton.BorderSizePixel = 0
	resetButton.Font = Enum.Font.GothamBold
	resetButton.Text = "Reset Suite"
	resetButton.TextColor3 = Color3.fromRGB(255, 244, 235)
	resetButton.TextSize = 15
	resetButton.Parent = panel
	createCorner(resetButton, 7)
	createStroke(resetButton, Color3.fromRGB(202, 132, 102), 0.45)
	UIController:CreateButton(resetButton, function()
		BossArenaStudioTestSuiteController:_handleReset()
	end)

	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "BossList"
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.Position = UDim2.fromOffset(12, 140)
	scrollFrame.Size = UDim2.new(1, -24, 1, -152)
	scrollFrame.CanvasSize = UDim2.new()
	scrollFrame.ScrollBarThickness = 5
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.None
	scrollFrame.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 14)
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.Parent = scrollFrame

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 10)
	listLayout.Parent = scrollFrame

	self._ui = {
		screenGui = screenGui,
		panel = panel,
		statusLabel = statusLabel,
		scrollFrame = scrollFrame,
		listLayout = listLayout,
		buttonsByKey = {},
	}

	if self._canvasConnection then
		self._canvasConnection:Disconnect()
	end
	self._canvasConnection = listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		self:_updateCanvasSize()
	end)

	return self._ui
end

function BossArenaStudioTestSuiteController:_setVisible(isVisible: boolean)
	local ui = self:_ensureUi()
	ui.screenGui.Enabled = isVisible
end

function BossArenaStudioTestSuiteController:_clearBossRows()
	local ui = self:_ensureUi()
	for _, child in ipairs(ui.scrollFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	table.clear(ui.buttonsByKey)
end

function BossArenaStudioTestSuiteController:_applyButtonState(button: TextButton, enabled: boolean)
	button.Active = enabled
	button.AutoButtonColor = false
	button.TextColor3 = if enabled then Color3.fromRGB(244, 247, 255) else Color3.fromRGB(142, 151, 164)
	button.BackgroundColor3 = if enabled then Color3.fromRGB(36, 49, 67) else Color3.fromRGB(27, 34, 45)
end

function BossArenaStudioTestSuiteController:_createSmallButton(parent: Instance, text: string, layoutOrder: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = text
	button.Size = UDim2.new(1, 0, 0, 34)
	button.BackgroundColor3 = Color3.fromRGB(36, 49, 67)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = Color3.fromRGB(244, 247, 255)
	button.TextSize = 14
	button.TextWrapped = true
	button.LayoutOrder = layoutOrder
	button.Parent = parent
	createCorner(button, 6)
	createStroke(button, Color3.fromRGB(111, 130, 156), 0.5)
	return button
end

function BossArenaStudioTestSuiteController:_createBossRow(boss: BossEntry, layoutOrder: number)
	local ui = self:_ensureUi()
	local moveCount = if typeof(boss.moves) == "table" then #boss.moves else 0
	local rowHeight = 92 + (moveCount * 40)

	local row = Instance.new("Frame")
	row.Name = boss.id
	row.Size = UDim2.new(1, 0, 0, rowHeight)
	row.BackgroundColor3 = Color3.fromRGB(22, 29, 39)
	row.BorderSizePixel = 0
	row.LayoutOrder = layoutOrder
	row.Parent = ui.scrollFrame
	createCorner(row, 8)
	createStroke(row, Color3.fromRGB(82, 101, 128), 0.6)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(12, 8)
	title.Size = UDim2.new(1, -24, 0, 24)
	title.Font = Enum.Font.GothamBold
	title.Text = boss.displayName
	title.TextColor3 = Color3.fromRGB(244, 247, 255)
	title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = row

	local teleportButton = Instance.new("TextButton")
	teleportButton.Name = "Teleport"
	teleportButton.Position = UDim2.fromOffset(12, 38)
	teleportButton.Size = UDim2.new(1, -24, 0, 30)
	teleportButton.BackgroundColor3 = Color3.fromRGB(48, 61, 79)
	teleportButton.BorderSizePixel = 0
	teleportButton.Font = Enum.Font.GothamBold
	teleportButton.Text = "Teleport To Boss"
	teleportButton.TextColor3 = Color3.fromRGB(238, 244, 255)
	teleportButton.TextSize = 13
	teleportButton.Parent = row
	createCorner(teleportButton, 6)
	createStroke(teleportButton, Color3.fromRGB(118, 141, 170), 0.5)
	UIController:CreateButton(teleportButton, function()
		BossArenaStudioTestSuiteController:_handleTeleport(boss.id)
	end)

	local movesFrame = Instance.new("Frame")
	movesFrame.Name = "Moves"
	movesFrame.BackgroundTransparency = 1
	movesFrame.Position = UDim2.fromOffset(12, 76)
	movesFrame.Size = UDim2.new(1, -24, 1, -84)
	movesFrame.Parent = row

	local movesLayout = Instance.new("UIListLayout")
	movesLayout.FillDirection = Enum.FillDirection.Vertical
	movesLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	movesLayout.SortOrder = Enum.SortOrder.LayoutOrder
	movesLayout.Padding = UDim.new(0, 6)
	movesLayout.Parent = movesFrame

	for index, move in ipairs(boss.moves or {}) do
		local key = makeButtonKey(boss.id, move.id)
		local button = self:_createSmallButton(movesFrame, formatMoveButtonText(move), index)
		UIController:CreateButton(button, function()
			BossArenaStudioTestSuiteController:_handleMoveSelected(boss.id, move.id)
		end)
		ui.buttonsByKey[key] = button
	end
end

function BossArenaStudioTestSuiteController:_renderState(state: TestSuiteState?)
	if typeof(state) ~= "table" then
		return
	end

	self._currentState = state
	local ui = self:_ensureUi()
	ui.statusLabel.Text = if typeof(state.message) == "string" and state.message ~= ""
		then state.message
		else "Select a boss move below to run the real ability in the test arena."

	if state.active ~= true then
		self:_setVisible(false)
		return
	end

	self:_setVisible(true)
	self:_clearBossRows()

	for index, boss in ipairs(state.bosses or {}) do
		self:_createBossRow(boss, index)
	end

	for _, boss in ipairs(state.bosses or {}) do
		local bossIsCasting = boss.castingMoveId ~= nil
		for _, move in ipairs(boss.moves or {}) do
			local key = makeButtonKey(boss.id, move.id)
			local button = ui.buttonsByKey[key]
			if button then
				local enabled = self._requestInFlight ~= true and bossIsCasting ~= true
				if boss.castingMoveId == move.id then
					button.Text = string.format("Casting %s...", move.displayName)
				else
					button.Text = formatMoveButtonText(move)
				end
				self:_applyButtonState(button, enabled)
			end
		end
	end

	self:_updateCanvasSize()
end

function BossArenaStudioTestSuiteController:_keepActivePanelVisible(message: string?)
	local state = self._currentState
	if typeof(state) ~= "table" or state.active ~= true then
		return false
	end

	self:_setVisible(true)
	local ui = self:_ensureUi()
	if typeof(message) == "string" and message ~= "" then
		ui.statusLabel.Text = message
	end
	return true
end

function BossArenaStudioTestSuiteController:_refreshState()
	local remotes = self:_ensureRemotes()
	if not remotes then
		return
	end

	local state = invokeRemote(remotes.getState)
	if typeof(state) == "table" then
		self:_renderState(state)
	end
end

function BossArenaStudioTestSuiteController:_handleResponse(result: any?, successFallback: string)
	if typeof(result) ~= "table" then
		warn("[BossArenaStudioTestSuiteController] Server did not return a valid response.")
		self:_keepActivePanelVisible("Request failed. The test suite panel is staying open.")
		return
	end

	local hadActiveState = typeof(self._currentState) == "table" and self._currentState.active == true
	local message = tostring(result.message or successFallback)
	if typeof(result.state) == "table" then
		if result.ok ~= true and hadActiveState and result.state.active ~= true and result.code ~= "START_FAILED" then
			self:_keepActivePanelVisible(message)
		else
			self:_renderState(result.state)
		end
	elseif hadActiveState then
		self:_keepActivePanelVisible(message)
	end

	if result.ok == true then
		Notify.Show(message, {
			channel = "system",
			duration = 3,
		})
		return
	end

	warn(string.format("[BossArenaStudioTestSuiteController] %s", message))
	Notify.Show(message, {
		channel = "system",
		duration = 4,
	})
end

function BossArenaStudioTestSuiteController:_handleMoveSelected(bossId: string, moveId: string)
	local remotes = self:_ensureRemotes()
	if not remotes or self._requestInFlight then
		return
	end

	self._requestInFlight = true
	self:_renderState(self._currentState)

	local result = invokeRemote(remotes.runMove, {
		bossId = bossId,
		moveId = moveId,
	})

	self._requestInFlight = false
	self:_handleResponse(result, "Move started.")
end

function BossArenaStudioTestSuiteController:_handleTeleport(bossId: string)
	local remotes = self:_ensureRemotes()
	if not remotes or self._requestInFlight then
		return
	end

	self._requestInFlight = true
	local result = invokeRemote(remotes.teleport, {
		bossId = bossId,
	})
	self._requestInFlight = false
	self:_handleResponse(result, "Teleported.")
end

function BossArenaStudioTestSuiteController:_handleReset()
	local remotes = self:_ensureRemotes()
	if not remotes or self._requestInFlight then
		return
	end

	self._requestInFlight = true
	self:_renderState(self._currentState)
	local result = invokeRemote(remotes.reset)
	self._requestInFlight = false
	self:_handleResponse(result, "Test suite reset.")
end

function BossArenaStudioTestSuiteController:_bindRemotes()
	local remotes = self:_ensureRemotes()
	if not remotes then
		return
	end

	if self._stateChangedConnection then
		self._stateChangedConnection:Disconnect()
	end

	self._stateChangedConnection = remotes.stateChanged.OnClientEvent:Connect(function(state: TestSuiteState)
		self:_renderState(state)
	end)
end

function BossArenaStudioTestSuiteController:OnStart()
	if self._started then
		return
	end
	self._started = true

	if not isEnabledForPlace() then
		return
	end

	self:_ensureUi()
	self:_bindRemotes()
	self:_refreshState()
end

return BossArenaStudioTestSuiteController
