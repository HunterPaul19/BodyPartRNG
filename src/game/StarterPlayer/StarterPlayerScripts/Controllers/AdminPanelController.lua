local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local NumberFormatter = require(ReplicatedStorage.Shared.Formatting.NumberFormatter)
local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local SizeConfig = require(ReplicatedStorage.Shared.Config.SizeConfig)
local BodyPartRegions = require(ReplicatedStorage.Shared.Character.BodyPartRegions)
local AdminPanelDefinitions = require(ReplicatedStorage.Shared.UI.AdminPanelDefinitions)
local PlayerStatsPresentation = require(ReplicatedStorage.Shared.UI.PlayerStatsPresentation)
local DialogueController = require(script.Parent.DialogueController)
local HUDWindowController = require(script.Parent.HUDWindowController)
local UIController = require(script.Parent.UIController)

local LOCAL_PLAYER = Players.LocalPlayer
local ACCESS_ATTRIBUTE = "CanUseAdminPanel"
local OVERVIEW_TAB_ID = "overview"
local PLAYERS_TAB_ID = "players"
local BODY_PARTS_TAB_ID = "bodyParts"
local WINDOW_NAME = "AdminPanel"
local TOGGLE_KEY = Enum.KeyCode.P
local SUCCESS_COLOR = Color3.fromRGB(120, 255, 178)
local ERROR_COLOR = Color3.fromRGB(255, 141, 141)
local DEFAULT_STATUS_COLOR = Color3.fromRGB(178, 187, 211)
local SANDBOX_CARD_COLOR = Color3.fromRGB(19, 25, 45)
local SANDBOX_STROKE_COLOR = Color3.fromRGB(62, 74, 111)
local SANDBOX_FIELD_COLOR = Color3.fromRGB(24, 31, 55)
local SANDBOX_BUTTON_COLOR = Color3.fromRGB(45, 59, 103)
local SANDBOX_BUTTON_TEXT_COLOR = Color3.fromRGB(235, 240, 255)

local AdminPanelController = {}

function AdminPanelController:_ensureState()
	if self._started then
		return
	end

	self._started = true
	self._selectedTabId = nil
	self._tabButtons = {}
	self._pages = {}
	self._statusLabel = nil
	self._screenGui = nil
	self._windowRoot = nil
	self._remote = nil
	self._authorized = LOCAL_PLAYER:GetAttribute(ACCESS_ATTRIBUTE) == true
	self._windowRegistered = false
	self._inputConnection = nil
	self._accessConnection = nil
	self._pageTitleLabel = nil
	self._pageSubtitleLabel = nil
	self._visualSandboxOptions = nil
	self._visualSandboxOptionsLoaded = false
	self._visualSandboxRegion = BodyPartRegions.Order[1]
	self._visualSandboxSelectedBundles = {}
	self._visualSandboxScaleText = "1.0"
	self._visualSandboxUi = {}
	self._runtimeState = nil
	self._runtimeScaleText = "1.0"
	self._runtimeSelectedOwnedId = nil
	self._runtimeSelectedRegion = BodyPartRegions.Order[1]
	self._runtimeUi = {}
	self._grantSelectedPieceId = nil :: string?
	self._grantSelectedAuraId = nil :: string?
	self._grantUi = {}
	self._playerStatsSelectedUserId = nil
	self._playerStatsSummary = nil
	self._playerStatsUi = {}
end

local function setTextStroke(label: TextLabel, transparency: number)
	local stroke = label:FindFirstChildWhichIsA("UIStroke")
	if stroke then
		stroke.Transparency = transparency
	end
end

local function setGenerated(instance: Instance)
	instance:SetAttribute("GeneratedAdminPanel", true)
end

function AdminPanelController:_setStatus(message: string, color: Color3?)
	if not self._statusLabel then
		return
	end

	self._statusLabel.Text = message
	self._statusLabel.TextColor3 = color or DEFAULT_STATUS_COLOR
end

local function formatSignedPercent(value: number): string
	local percent = (tonumber(value) or 0) * 100
	if math.abs(percent - math.round(percent)) < 0.005 then
		return string.format("%d%%", math.round(percent))
	end
	return string.format("%.2f%%", percent):gsub("0+$", ""):gsub("%.$", "")
end

local function formatNumberish(value: number): string
	local numericValue = tonumber(value) or 0
	if math.abs(numericValue - math.round(numericValue)) < 0.005 then
		return NumberFormatter.Format(math.round(numericValue))
	end
	return string.format("%.2f", numericValue):gsub("0+$", ""):gsub("%.$", "")
end

local function formatPlayerDisplay(player: Player?): string
	if not player then
		return "No player selected"
	end

	return string.format("%s (@%s)", player.DisplayName, player.Name)
end

local function setSandboxButtonEnabled(button: GuiButton?, enabled: boolean)
	if not (button and button:IsA("GuiButton")) then
		return
	end

	button.Active = enabled
	button.TextTransparency = if enabled then 0 else 0.35
	button.BackgroundTransparency = if enabled then 0 else 0.35
end

function AdminPanelController:_invokeAdminRequest(tabId: string, actionId: string, actionTitle: string, payload: any?): (boolean, any)
	local remote = self:_getRemote()
	if not remote then
		self:_setStatus("AdminAction remote is not available yet.", ERROR_COLOR)
		return false, nil
	end

	self:_setStatus(string.format("%s...", actionTitle))

	local ok, result = pcall(function()
		return remote:InvokeServer({
			tabId = tabId,
			actionId = actionId,
			payload = payload or {},
		})
	end)

	if not ok then
		self:_setStatus("Admin action failed to send. Check the output for details.", ERROR_COLOR)
		warn(string.format("[AdminPanelController] AdminAction invoke failed: %s", tostring(result)))
		return false, nil
	end

	if typeof(result) ~= "table" then
		self:_setStatus("Admin action returned an invalid response.", ERROR_COLOR)
		return false, nil
	end

	return true, result
end

function AdminPanelController:_isAuthorized(): boolean
	return self._authorized == true
end

function AdminPanelController:_isWindowOpen(): boolean
	return self._windowRoot ~= nil and self._windowRoot.Visible
end

function AdminPanelController:_getRemote(): RemoteFunction?
	if self._remote and self._remote.Parent then
		return self._remote
	end

	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotesFolder then
		return nil
	end

	local remote = remotesFolder:FindFirstChild("AdminAction")
	if remote and remote:IsA("RemoteFunction") then
		self._remote = remote
		return remote
	end

	return nil
end

function AdminPanelController:_styleTabButton(button: GuiButton, selected: boolean)
	local indicator = button:FindFirstChild("SelectedIndicator")
	local titleLabel = button:FindFirstChild("TitleLabel")
	local subtitleLabel = button:FindFirstChild("SubtitleLabel")
	local stroke = button:FindFirstChildWhichIsA("UIStroke")

	button.BackgroundColor3 = if selected then Color3.fromRGB(45, 59, 103) else Color3.fromRGB(25, 31, 54)
	button.BackgroundTransparency = if selected then 0 else 0.08

	if indicator and indicator:IsA("Frame") then
		indicator.Visible = selected
	end

	if stroke then
		stroke.Color = if selected then Color3.fromRGB(145, 179, 255) else Color3.fromRGB(62, 74, 111)
		stroke.Transparency = if selected then 0 else 0.2
	end

	if titleLabel and titleLabel:IsA("TextLabel") then
		titleLabel.TextColor3 = if selected then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(219, 226, 255)
		setTextStroke(titleLabel, if selected then 0.45 else 0.65)
	end

	if subtitleLabel and subtitleLabel:IsA("TextLabel") then
		subtitleLabel.TextColor3 = if selected then Color3.fromRGB(214, 226, 255) else Color3.fromRGB(151, 162, 198)
	end
end

function AdminPanelController:_setTab(tabId: string)
	self._selectedTabId = tabId

	local tabDefinition = AdminPanelDefinitions.TabsById[tabId]
	if tabDefinition then
		if self._pageTitleLabel then
			self._pageTitleLabel.Text = tabDefinition.title
		end
		if self._pageSubtitleLabel then
			self._pageSubtitleLabel.Text = tabDefinition.subtitle
		end
		self:_setStatus(string.format("%s tab ready.", tabDefinition.title))
	end

	for buttonTabId, button in pairs(self._tabButtons) do
		self:_styleTabButton(button, buttonTabId == tabId)
	end

	for pageTabId, page in pairs(self._pages) do
		page.Visible = pageTabId == tabId
	end

	if tabId == BODY_PARTS_TAB_ID then
		self:_loadRuntimeState(true)
		self:_loadVisualSandboxOptions(true)
	elseif tabId == PLAYERS_TAB_ID then
		self:_syncPlayerStatsUi()
		self:_loadSelectedPlayerStats(true)
	end
end

function AdminPanelController:_createSectionHeader(parent: Instance, title: string, description: string)
	local container = Instance.new("Frame")
	container.Name = title:gsub("%s+", "") .. "Section"
	container.BackgroundTransparency = 1
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.Size = UDim2.new(1, 0, 0, 0)
	container.Parent = parent
	setGenerated(container)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.new(1, 0, 0, 24)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Text = title
	titleLabel.TextSize = 18
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextColor3 = Color3.fromRGB(247, 249, 255)
	titleLabel.Parent = container
	setGenerated(titleLabel)

	local descriptionLabel = Instance.new("TextLabel")
	descriptionLabel.Name = "DescriptionLabel"
	descriptionLabel.BackgroundTransparency = 1
	descriptionLabel.Position = UDim2.fromOffset(0, 26)
	descriptionLabel.Size = UDim2.new(1, 0, 0, 32)
	descriptionLabel.AutomaticSize = Enum.AutomaticSize.Y
	descriptionLabel.Font = Enum.Font.Gotham
	descriptionLabel.Text = description
	descriptionLabel.TextWrapped = true
	descriptionLabel.TextSize = 14
	descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
	descriptionLabel.TextYAlignment = Enum.TextYAlignment.Top
	descriptionLabel.TextColor3 = Color3.fromRGB(159, 170, 201)
	descriptionLabel.Parent = container
	setGenerated(descriptionLabel)
end

function AdminPanelController:_createSpacer(parent: Instance, height: number)
	local spacer = Instance.new("Frame")
	spacer.Name = "Spacer"
	spacer.BackgroundTransparency = 1
	spacer.Size = UDim2.new(1, 0, 0, height)
	spacer.Parent = parent
	setGenerated(spacer)
end

function AdminPanelController:_invokeAction(tabId: string, actionId: string, actionTitle: string)
	local ok, result = self:_invokeAdminRequest(tabId, actionId, string.format("Sending %s", actionTitle), {})
	if not ok or not result then
		return
	end

	if result.ok and tabId == OVERVIEW_TAB_ID and actionId == "test_dialogue" then
		local data = if typeof(result.data) == "table" then result.data else {}
		local dialogueId = if typeof(data.dialogueId) == "string" and data.dialogueId ~= "" then data.dialogueId else "merchant_default"
		local context = if typeof(data.context) == "table" then data.context else {}

		HUDWindowController:CloseWindow(WINDOW_NAME, true)
		task.defer(function()
			DialogueController.StartDialogue(dialogueId, context)
		end)
	end

	local message = tostring(result.message or "No response message provided.")
	self:_setStatus(message, if result.ok then SUCCESS_COLOR else ERROR_COLOR)
end

function AdminPanelController:_styleSandboxButton(button: GuiButton, callback: () -> ())
	button.AutoButtonColor = false
	button.BackgroundColor3 = SANDBOX_BUTTON_COLOR
	button.TextColor3 = SANDBOX_BUTTON_TEXT_COLOR
	button.Font = Enum.Font.GothamSemibold
	button.TextSize = 14

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button
	setGenerated(corner)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(92, 110, 165)
	stroke.Transparency = 0.18
	stroke.Parent = button
	setGenerated(stroke)

	UIController:CreateButton(button, callback)
end

function AdminPanelController:_createSandboxButton(parent: Instance, name: string, text: string, size: UDim2, callback: () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.Text = text
	button.Parent = parent
	setGenerated(button)

	self:_styleSandboxButton(button, callback)
	return button
end

function AdminPanelController:_createSandboxField(parent: Instance, labelText: string): Frame
	local field = Instance.new("Frame")
	field.Name = labelText:gsub("%s+", "") .. "Field"
	field.BackgroundColor3 = SANDBOX_FIELD_COLOR
	field.AutomaticSize = Enum.AutomaticSize.Y
	field.Size = UDim2.new(1, 0, 0, 0)
	field.Parent = parent
	setGenerated(field)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = field
	setGenerated(corner)

	local stroke = Instance.new("UIStroke")
	stroke.Color = SANDBOX_STROKE_COLOR
	stroke.Transparency = 0.22
	stroke.Parent = field
	setGenerated(stroke)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = field
	setGenerated(padding)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Padding = UDim.new(0, 8)
	layout.Parent = field
	setGenerated(layout)

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 18)
	label.Font = Enum.Font.GothamBold
	label.Text = labelText
	label.TextColor3 = Color3.fromRGB(232, 238, 255)
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = field
	setGenerated(label)

	return field
end

function AdminPanelController:_createSandboxValueLabel(parent: Instance): TextLabel
	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = "ValueLabel"
	valueLabel.BackgroundTransparency = 1
	valueLabel.AutomaticSize = Enum.AutomaticSize.Y
	valueLabel.Size = UDim2.new(1, 0, 0, 0)
	valueLabel.Font = Enum.Font.GothamSemibold
	valueLabel.Text = ""
	valueLabel.TextColor3 = Color3.fromRGB(244, 247, 255)
	valueLabel.TextSize = 14
	valueLabel.TextWrapped = true
	valueLabel.TextXAlignment = Enum.TextXAlignment.Left
	valueLabel.TextYAlignment = Enum.TextYAlignment.Top
	valueLabel.Parent = parent
	setGenerated(valueLabel)

	return valueLabel
end

function AdminPanelController:_getPlayerStatsTargets(): { Player }
	local targets = Players:GetPlayers()
	table.sort(targets, function(a, b)
		local displayA = string.lower(a.DisplayName)
		local displayB = string.lower(b.DisplayName)
		if displayA ~= displayB then
			return displayA < displayB
		end

		local nameA = string.lower(a.Name)
		local nameB = string.lower(b.Name)
		if nameA ~= nameB then
			return nameA < nameB
		end

		return a.UserId < b.UserId
	end)

	return targets
end

function AdminPanelController:_getSelectedPlayerStatsTarget(): (Player?, { Player })
	local targets = self:_getPlayerStatsTargets()
	if #targets == 0 then
		self._playerStatsSelectedUserId = nil
		return nil, targets
	end

	for _, player in ipairs(targets) do
		if player.UserId == self._playerStatsSelectedUserId then
			return player, targets
		end
	end

	local fallbackPlayer = Players:GetPlayerByUserId(LOCAL_PLAYER.UserId) or targets[1]
	self._playerStatsSelectedUserId = fallbackPlayer.UserId
	return fallbackPlayer, targets
end

function AdminPanelController:_cyclePlayerStatsTarget(direction: number)
	local selectedPlayer, targets = self:_getSelectedPlayerStatsTarget()
	if #targets == 0 then
		self._playerStatsSummary = nil
		self:_syncPlayerStatsUi()
		self:_setStatus("No players are currently available to inspect.", ERROR_COLOR)
		return
	end

	local currentIndex = 1
	for index, player in ipairs(targets) do
		if selectedPlayer and player.UserId == selectedPlayer.UserId then
			currentIndex = index
			break
		end
	end

	local nextIndex = ((currentIndex - 1 + direction) % #targets) + 1
	self._playerStatsSelectedUserId = targets[nextIndex].UserId
	self._playerStatsSummary = nil
	self:_syncPlayerStatsUi()
	self:_loadSelectedPlayerStats(true)
end

function AdminPanelController:_syncPlayerStatsUi()
	local ui = self._playerStatsUi
	if not ui or next(ui) == nil then
		return
	end

	local selectedPlayer, targets = self:_getSelectedPlayerStatsTarget()
	local hasTargets = #targets > 0
	local hasMultipleTargets = #targets > 1
	local summary = self._playerStatsSummary
	if summary and ((not selectedPlayer) or summary.userId ~= selectedPlayer.UserId) then
		summary = nil
	end

	if ui.playerValue and ui.playerValue:IsA("TextLabel") then
		ui.playerValue.Text = if selectedPlayer then formatPlayerDisplay(selectedPlayer) else "No players available"
	end

	local sections = if summary then PlayerStatsPresentation.BuildAdminSections(summary) else {
		overview = if selectedPlayer
			then string.format("%s is selected.\nPress refresh to load their persisted lifetime stats.", formatPlayerDisplay(selectedPlayer))
			else "No players are currently available.",
		economy = "Load a player to view earned and spent currency totals by source.",
		rolls = "Load a player to view request volume, failures, rarity mix, and best-ever roll data.",
		collection = "Load a player to view acquisition, sells, auras, and set completion history.",
		monetization = "Load a player to view purchase prompts and successful purchase tracking.",
		settings = "Load a player to view client setting toggle and selection counters.",
	}

	if ui.overviewValue and ui.overviewValue:IsA("TextLabel") then
		ui.overviewValue.Text = sections.overview
	end
	if ui.economyValue and ui.economyValue:IsA("TextLabel") then
		ui.economyValue.Text = sections.economy
	end
	if ui.rollsValue and ui.rollsValue:IsA("TextLabel") then
		ui.rollsValue.Text = sections.rolls
	end
	if ui.collectionValue and ui.collectionValue:IsA("TextLabel") then
		ui.collectionValue.Text = sections.collection
	end
	if ui.monetizationValue and ui.monetizationValue:IsA("TextLabel") then
		ui.monetizationValue.Text = sections.monetization
	end
	if ui.settingsValue and ui.settingsValue:IsA("TextLabel") then
		ui.settingsValue.Text = sections.settings
	end

	setSandboxButtonEnabled(ui.playerPrevButton, hasMultipleTargets)
	setSandboxButtonEnabled(ui.playerNextButton, hasMultipleTargets)
	setSandboxButtonEnabled(ui.refreshButton, hasTargets)
end

function AdminPanelController:_loadSelectedPlayerStats(forceRefresh: boolean?): boolean
	local selectedPlayer = select(1, self:_getSelectedPlayerStatsTarget())
	if not selectedPlayer then
		self._playerStatsSummary = nil
		self:_syncPlayerStatsUi()
		self:_setStatus("No players are currently available to inspect.", ERROR_COLOR)
		return false
	end

	if not forceRefresh and self._playerStatsSummary and self._playerStatsSummary.userId == selectedPlayer.UserId then
		self:_syncPlayerStatsUi()
		return true
	end

	local ok, result = self:_invokeAdminRequest(PLAYERS_TAB_ID, "inspect_player_profile", "Loading player stats", {
		userId = selectedPlayer.UserId,
	})
	if not ok or not result then
		self._playerStatsSummary = nil
		self:_syncPlayerStatsUi()
		return false
	end

	if result.ok ~= true or typeof(result.data) ~= "table" then
		self._playerStatsSummary = nil
		self:_syncPlayerStatsUi()
		self:_setStatus(tostring(result.message or "Failed to load player stats."), ERROR_COLOR)
		return false
	end

	self._playerStatsSummary = result.data
	self:_syncPlayerStatsUi()
	self:_setStatus(tostring(result.message or "Loaded player stats."), SUCCESS_COLOR)
	return true
end

function AdminPanelController:_syncVisualSandboxUi()
	local ui = self._visualSandboxUi
	local region = self._visualSandboxRegion
	local options = self._visualSandboxOptions
	local bundleNames = options and options.regions and options.regions[region] or {}

	if self._visualSandboxSelectedBundles[region] == nil and #bundleNames > 0 then
		self._visualSandboxSelectedBundles[region] = bundleNames[1]
	end

	local selectedBundle = self._visualSandboxSelectedBundles[region]
	if selectedBundle and not table.find(bundleNames, selectedBundle) then
		selectedBundle = bundleNames[1]
		self._visualSandboxSelectedBundles[region] = selectedBundle
	end

	if ui.regionValue and ui.regionValue:IsA("TextLabel") then
		ui.regionValue.Text = region
	end

	if ui.bundleValue and ui.bundleValue:IsA("TextLabel") then
		if not self._visualSandboxOptionsLoaded then
			ui.bundleValue.Text = "Loading..."
		elseif #bundleNames == 0 then
			ui.bundleValue.Text = "No bundles"
		else
			ui.bundleValue.Text = selectedBundle or "No bundles"
		end
	end

	if ui.scaleInput and ui.scaleInput:IsA("TextBox") then
		if not ui.scaleInput:IsFocused() then
			ui.scaleInput.Text = self._visualSandboxScaleText
		end
	end

	local hasOptions = self._visualSandboxOptionsLoaded
	local hasBundles = #bundleNames > 0

	for _, button in ipairs({
		ui.regionPrevButton,
		ui.regionNextButton,
		ui.bundlePrevButton,
		ui.bundleNextButton,
		ui.applyButton,
		ui.resetRegionButton,
		ui.resetCharacterButton,
	}) do
		if button and button:IsA("GuiButton") then
			button.Active = hasOptions
			button.TextTransparency = if hasOptions then 0 else 0.35
			button.BackgroundTransparency = if hasOptions then 0 else 0.35
		end
	end

	for _, button in ipairs({ ui.bundlePrevButton, ui.bundleNextButton, ui.applyButton }) do
		if button and button:IsA("GuiButton") then
			local enabled = hasOptions and hasBundles
			button.Active = enabled
			button.TextTransparency = if enabled then 0 else 0.35
			button.BackgroundTransparency = if enabled then 0 else 0.35
		end
	end
end

function AdminPanelController:_getGrantBodyPartOptions()
	local pieces = {}

	for _, piece in ipairs(BodyPartsCatalog.GetAllPieces()) do
		table.insert(pieces, piece)
	end

	table.sort(pieces, function(a, b)
		local setA = BodyPartsCatalog.GetSetForPiece(a.id)
		local setB = BodyPartsCatalog.GetSetForPiece(b.id)
		local chanceA = math.max(1, math.floor(tonumber(setA and setA.rollDisplay.chance) or math.huge))
		local chanceB = math.max(1, math.floor(tonumber(setB and setB.rollDisplay.chance) or math.huge))
		if chanceA ~= chanceB then
			return chanceA < chanceB
		end

		local regionIndexA = table.find(BodyPartRegions.Order, a.region) or math.huge
		local regionIndexB = table.find(BodyPartRegions.Order, b.region) or math.huge
		if regionIndexA ~= regionIndexB then
			return regionIndexA < regionIndexB
		end

		if a.displayName ~= b.displayName then
			return a.displayName < b.displayName
		end

		return a.id < b.id
	end)

	return pieces
end

function AdminPanelController:_getSelectedGrantBodyPart()
	local selectedPieceId = self._grantSelectedPieceId
	for _, piece in ipairs(self:_getGrantBodyPartOptions()) do
		if piece.id == selectedPieceId then
			return piece
		end
	end

	return nil
end

function AdminPanelController:_getGrantAuraOptions()
	local auras = {}

	for _, auraConfig in ipairs(AuraConfig.GetOrdered()) do
		table.insert(auras, auraConfig)
	end

	return auras
end

function AdminPanelController:_getSelectedGrantAura()
	local selectedAuraId = self._grantSelectedAuraId
	for _, auraConfig in ipairs(self:_getGrantAuraOptions()) do
		if auraConfig.id == selectedAuraId then
			return auraConfig
		end
	end

	return nil
end

function AdminPanelController:_formatGrantBodyPart(piece: any): string
	if not piece then
		return "No body parts are available."
	end

	local setConfig = BodyPartsCatalog.GetSetForPiece(piece.id)
	local setName = if setConfig then setConfig.displayName else "Unknown Set"
	local rarity = if setConfig then setConfig.rollDisplay.rarity else "Unknown"
	local odds = if setConfig then math.max(1, math.floor(tonumber(setConfig.rollDisplay.chance) or 1)) else math.max(1, math.floor(tonumber(piece.rarity) or 1))

	return table.concat({
		piece.displayName,
		string.format("Piece ID: %s", piece.id),
		string.format("Set: %s", setName),
		string.format("Region: %s", piece.region),
		string.format("Rarity: %s", rarity),
		string.format("Odds: 1/%s", formatNumberish(odds)),
		string.format("Luck Bonus: %s", formatSignedPercent(tonumber(piece.luckBonus) or 0)),
		string.format("Roll Speed Bonus: %s", formatSignedPercent(tonumber(piece.rollSpeedBonus) or 0)),
		string.format("Income / s: %s", formatNumberish(tonumber(piece.passiveIncomePerSecond) or 0)),
	}, "\n")
end

function AdminPanelController:_formatGrantAura(auraConfig: AuraConfig.AuraConfigEntry?): string
	if not auraConfig then
		return "No auras are available."
	end

	return table.concat({
		auraConfig.label,
		string.format("Aura ID: %s", auraConfig.id),
		string.format("Set ID: %s", auraConfig.setId),
		string.format("Tier: %s", auraConfig.tierLabel),
		string.format("Luck Bonus: %s", formatSignedPercent(tonumber(auraConfig.bonuses.luckBonus) or 0)),
		string.format("Roll Speed Bonus: %s", formatSignedPercent(tonumber(auraConfig.bonuses.rollSpeedBonus) or 0)),
		string.format("Money Multiplier: x%s", formatNumberish(tonumber(auraConfig.bonuses.moneyMultiplier) or 1)),
		string.format("Passive Bonus / s: %s", formatNumberish(tonumber(auraConfig.bonuses.passiveIncomePerSecondBonus) or 0)),
	}, "\n")
end

function AdminPanelController:_syncGrantUi()
	local ui = self._grantUi
	if not ui or next(ui) == nil then
		return
	end

	local bodyPartOptions = self:_getGrantBodyPartOptions()
	local auraOptions = self:_getGrantAuraOptions()
	local selectedPiece = self:_getSelectedGrantBodyPart()
	local selectedAura = self:_getSelectedGrantAura()

	if selectedPiece == nil and bodyPartOptions[1] then
		self._grantSelectedPieceId = bodyPartOptions[1].id
		selectedPiece = bodyPartOptions[1]
	end

	if selectedAura == nil and auraOptions[1] then
		self._grantSelectedAuraId = auraOptions[1].id
		selectedAura = auraOptions[1]
	end

	if ui.bodyPartValue and ui.bodyPartValue:IsA("TextLabel") then
		ui.bodyPartValue.Text = self:_formatGrantBodyPart(selectedPiece)
	end

	if ui.auraValue and ui.auraValue:IsA("TextLabel") then
		ui.auraValue.Text = self:_formatGrantAura(selectedAura)
	end

	local hasBodyPartOptions = #bodyPartOptions > 0
	local hasAuraOptions = #auraOptions > 0

	for _, button in ipairs({ ui.bodyPartPrevButton, ui.bodyPartNextButton, ui.grantBodyPartButton }) do
		setSandboxButtonEnabled(button, hasBodyPartOptions)
	end

	for _, button in ipairs({ ui.auraPrevButton, ui.auraNextButton, ui.grantAuraButton }) do
		setSandboxButtonEnabled(button, hasAuraOptions)
	end
end

function AdminPanelController:_cycleGrantBodyPart(direction: number)
	local options = self:_getGrantBodyPartOptions()
	if #options == 0 then
		self._grantSelectedPieceId = nil
		self:_syncGrantUi()
		self:_setStatus("No body parts are configured to grant.", ERROR_COLOR)
		return
	end

	local currentIndex = 1
	for index, piece in ipairs(options) do
		if piece.id == self._grantSelectedPieceId then
			currentIndex = index
			break
		end
	end

	local nextIndex = ((currentIndex - 1 + direction) % #options) + 1
	self._grantSelectedPieceId = options[nextIndex].id
	self:_syncGrantUi()
end

function AdminPanelController:_cycleGrantAura(direction: number)
	local options = self:_getGrantAuraOptions()
	if #options == 0 then
		self._grantSelectedAuraId = nil
		self:_syncGrantUi()
		self:_setStatus("No auras are configured to grant.", ERROR_COLOR)
		return
	end

	local currentIndex = 1
	for index, auraConfig in ipairs(options) do
		if auraConfig.id == self._grantSelectedAuraId then
			currentIndex = index
			break
		end
	end

	local nextIndex = ((currentIndex - 1 + direction) % #options) + 1
	self._grantSelectedAuraId = options[nextIndex].id
	self:_syncGrantUi()
end

function AdminPanelController:_grantSelectedBodyPart()
	local selectedPiece = self:_getSelectedGrantBodyPart()
	if not selectedPiece then
		self:_setStatus("Select a body part to grant first.", ERROR_COLOR)
		return
	end

	local ok, result = self:_invokeAdminRequest(BODY_PARTS_TAB_ID, "grant_body_part", "Granting body part", {
		pieceId = selectedPiece.id,
	})
	if not ok or not result then
		return
	end

	if typeof(result.data) == "table" and typeof(result.data.grantedRecord) == "table" and typeof(result.data.grantedRecord.ownedId) == "string" then
		self._runtimeSelectedOwnedId = result.data.grantedRecord.ownedId
	end

	if typeof(result.data) == "table" and typeof(result.data.runtimeState) == "table" then
		self:_applyRuntimeState(result.data.runtimeState)
	end

	self:_setStatus(tostring(result.message or "No response message provided."), if result.ok then SUCCESS_COLOR else ERROR_COLOR)
end

function AdminPanelController:_grantSelectedAura()
	local selectedAura = self:_getSelectedGrantAura()
	if not selectedAura then
		self:_setStatus("Select an aura to grant first.", ERROR_COLOR)
		return
	end

	local ok, result = self:_invokeAdminRequest(BODY_PARTS_TAB_ID, "grant_aura", "Granting aura", {
		auraId = selectedAura.id,
	})
	if not ok or not result then
		return
	end

	self:_setStatus(tostring(result.message or "No response message provided."), if result.ok then SUCCESS_COLOR else ERROR_COLOR)
end

function AdminPanelController:_getOwnedRecords()
	local ownedById = self._runtimeState and self._runtimeState.ownedBodyParts
	local records = {}

	if typeof(ownedById) ~= "table" then
		return records
	end

	for ownedId, record in pairs(ownedById) do
		if typeof(record) == "table" then
			local copy = table.clone(record)
			copy.ownedId = copy.ownedId or ownedId
			table.insert(records, copy)
		end
	end

	table.sort(records, function(a, b)
		local serialA = tonumber(a.serialNumber) or math.huge
		local serialB = tonumber(b.serialNumber) or math.huge
		if serialA ~= serialB then
			return serialA < serialB
		end

		return tostring(a.ownedId) < tostring(b.ownedId)
	end)

	return records
end

function AdminPanelController:_getSelectedOwnedRecord()
	local selectedOwnedId = self._runtimeSelectedOwnedId
	for _, record in ipairs(self:_getOwnedRecords()) do
		if record.ownedId == selectedOwnedId then
			return record
		end
	end

	return nil
end

function AdminPanelController:_applyRuntimeState(state: any)
	self._runtimeState = if typeof(state) == "table" then state else nil

	local selectedRecord = self:_getSelectedOwnedRecord()
	if not selectedRecord then
		local records = self:_getOwnedRecords()
		self._runtimeSelectedOwnedId = records[1] and records[1].ownedId or nil
	end

	local selectedRegion = self._runtimeSelectedRegion
	if not BodyPartRegions.IsValid(selectedRegion) then
		self._runtimeSelectedRegion = BodyPartRegions.Order[1]
	end

	self:_syncRuntimeUi()
end

function AdminPanelController:_loadRuntimeState(_forceRefresh: boolean?): boolean
	local ok, result = self:_invokeAdminRequest(BODY_PARTS_TAB_ID, "get_runtime_state", "Loading runtime state", {})
	if not ok or not result then
		self:_syncRuntimeUi()
		return false
	end

	if result.ok ~= true or typeof(result.data) ~= "table" then
		self:_setStatus(tostring(result.message or "Failed to load body part runtime state."), ERROR_COLOR)
		self:_syncRuntimeUi()
		return false
	end

	self:_applyRuntimeState(result.data)
	self:_setStatus(tostring(result.message or "Loaded body part runtime state."), SUCCESS_COLOR)
	return true
end

function AdminPanelController:_cycleRuntimeOwned(direction: number)
	local records = self:_getOwnedRecords()
	if #records == 0 then
		self._runtimeSelectedOwnedId = nil
		self:_syncRuntimeUi()
		self:_setStatus("No owned body parts are available yet.", ERROR_COLOR)
		return
	end

	local currentIndex = 1
	for index, record in ipairs(records) do
		if record.ownedId == self._runtimeSelectedOwnedId then
			currentIndex = index
			break
		end
	end

	local nextIndex = ((currentIndex - 1 + direction) % #records) + 1
	self._runtimeSelectedOwnedId = records[nextIndex].ownedId
	self:_syncRuntimeUi()
end

function AdminPanelController:_cycleRuntimeRegion(direction: number)
	local currentIndex = table.find(BodyPartRegions.Order, self._runtimeSelectedRegion) or 1
	local nextIndex = ((currentIndex - 1 + direction) % #BodyPartRegions.Order) + 1
	self._runtimeSelectedRegion = BodyPartRegions.Order[nextIndex]
	self:_syncRuntimeUi()
end

function AdminPanelController:_getRuntimeScale(): number?
	local scaleText = self._runtimeScaleText
	local ui = self._runtimeUi
	if ui.scaleInput and ui.scaleInput:IsA("TextBox") then
		scaleText = ui.scaleInput.Text
		self._runtimeScaleText = scaleText
	end

	local numericScale = tonumber(scaleText)
	if not numericScale or numericScale <= 0 then
		return nil
	end

	return numericScale
end

function AdminPanelController:_formatOwnedRecord(record: any): string
	local piece = record and record.pieceId and BodyPartsCatalog.GetPiece(record.pieceId) or nil
	local displayName = if piece then piece.displayName else tostring(record and record.pieceId or "Unknown Piece")
	local mutation = tostring(record and record.mutation or "")
	if mutation == "" then
		mutation = "None"
	end

	local sizeScale = tonumber(record and record.sizeMultiplier) or 1
	local sizeEntry = SizeConfig.GetByScale(sizeScale)
		or SizeConfig.Get(record and record.sizeId)
		or SizeConfig.GetDefault()

	return table.concat({
		displayName,
		string.format("Owned ID: %s", tostring(record and record.ownedId or "N/A")),
		string.format("Region: %s", tostring(piece and piece.region or record and record.region or "Unknown")),
		string.format("Serial: #%s", tostring(record and record.serialNumber or "?")),
		string.format("Odds: 1/%s", formatNumberish(tonumber(record and (record.displayOddsDenominator or record.rarityDenominator)) or 0)),
		string.format("Display Rarity: %s", tostring(record and record.displayRarity or (record and record.rarity) or "Unknown")),
		string.format("Mutation: %s", mutation),
		string.format("Size: %s (%sx)", sizeEntry.displayName, formatNumberish(sizeScale)),
		string.format("Income / s: %s", formatNumberish(tonumber(record and record.finalPassiveIncomePerSecond) or tonumber(piece and piece.passiveIncomePerSecond) or 0)),
	}, "\n")
end

function AdminPanelController:_formatEquippedState(): string
	local equipped = self._runtimeState and self._runtimeState.equipped
	local lines = {}

	for _, region in ipairs(BodyPartRegions.Order) do
		local entry = equipped and equipped[region]
		if entry then
			local piece = BodyPartsCatalog.GetPiece(entry.pieceId)
			local displayName = if piece then piece.displayName else tostring(entry.pieceId)
			table.insert(lines, string.format("%s: %s (%s, %.2fx)", region, displayName, tostring(entry.ownedId), tonumber(entry.scale) or 1))
		else
			table.insert(lines, string.format("%s: Empty", region))
		end
	end

	return table.concat(lines, "\n")
end

function AdminPanelController:_formatBonuses(): string
	local bonuses = self._runtimeState and self._runtimeState.bonuses or {}
	local setId = bonuses.activeSetId
	local setDisplay = "None"
	if typeof(setId) == "string" and setId ~= "" then
		local setConfig = BodyPartsCatalog.GetSet(setId)
		setDisplay = if setConfig then setConfig.displayName else setId
	end

	return table.concat({
		string.format("Passive Income / s: %s", formatNumberish(tonumber(bonuses.passiveIncomePerSecond) or 0)),
		string.format("Luck Bonus: %s", formatSignedPercent(tonumber(bonuses.luckBonus) or 0)),
		string.format("Roll Speed Bonus: %s", formatSignedPercent(tonumber(bonuses.rollSpeedBonus) or 0)),
		string.format("Active Set: %s", setDisplay),
	}, "\n")
end

function AdminPanelController:_syncRuntimeUi()
	local ui = self._runtimeUi
	if not ui or next(ui) == nil then
		return
	end

	local records = self:_getOwnedRecords()
	local selectedRecord = self:_getSelectedOwnedRecord()
	local hasOwned = #records > 0
	local selectedRegion = self._runtimeSelectedRegion

	if ui.ownedValue and ui.ownedValue:IsA("TextLabel") then
		ui.ownedValue.Text = if selectedRecord then self:_formatOwnedRecord(selectedRecord) else "No owned body parts found."
	end

	if ui.regionValue and ui.regionValue:IsA("TextLabel") then
		ui.regionValue.Text = selectedRegion
	end

	if ui.equippedValue and ui.equippedValue:IsA("TextLabel") then
		ui.equippedValue.Text = self:_formatEquippedState()
	end

	if ui.bonusesValue and ui.bonusesValue:IsA("TextLabel") then
		ui.bonusesValue.Text = self:_formatBonuses()
	end

	if ui.scaleInput and ui.scaleInput:IsA("TextBox") and not ui.scaleInput:IsFocused() then
		ui.scaleInput.Text = self._runtimeScaleText
	end

	for _, button in ipairs({ ui.ownedPrevButton, ui.ownedNextButton, ui.refreshButton, ui.clearButton, ui.regionPrevButton, ui.regionNextButton, ui.unequipButton }) do
		if button and button:IsA("GuiButton") then
			button.Active = true
			button.TextTransparency = 0
			button.BackgroundTransparency = 0
		end
	end

	if ui.equipButton and ui.equipButton:IsA("GuiButton") then
		ui.equipButton.Active = hasOwned
		ui.equipButton.TextTransparency = if hasOwned then 0 else 0.35
		ui.equipButton.BackgroundTransparency = if hasOwned then 0 else 0.35
	end

	for _, button in ipairs({ ui.ownedPrevButton, ui.ownedNextButton }) do
		if button and button:IsA("GuiButton") then
			button.Active = hasOwned
			button.TextTransparency = if hasOwned then 0 else 0.35
			button.BackgroundTransparency = if hasOwned then 0 else 0.35
		end
	end
end

function AdminPanelController:_refreshRuntimeState()
	self:_loadRuntimeState(true)
end

function AdminPanelController:_equipSelectedOwnedBodyPart()
	local selectedRecord = self:_getSelectedOwnedRecord()
	if not selectedRecord then
		self:_setStatus("Select an owned body part first.", ERROR_COLOR)
		return
	end

	local scale = self:_getRuntimeScale()
	if not scale then
		self:_setStatus("Scale must be a positive number.", ERROR_COLOR)
		return
	end

	local ok, result = self:_invokeAdminRequest(BODY_PARTS_TAB_ID, "equip_owned_body_part", "Equipping owned body part", {
		ownedId = selectedRecord.ownedId,
		scale = scale,
	})
	if not ok or not result then
		return
	end

	if typeof(result.data) == "table" then
		self:_applyRuntimeState(result.data)
	end

	self:_setStatus(tostring(result.message or "No response message provided."), if result.ok then SUCCESS_COLOR else ERROR_COLOR)
end

function AdminPanelController:_unequipSelectedRuntimeRegion()
	local ok, result = self:_invokeAdminRequest(BODY_PARTS_TAB_ID, "unequip_runtime_region", "Unequipping runtime region", {
		region = self._runtimeSelectedRegion,
	})
	if not ok or not result then
		return
	end

	if typeof(result.data) == "table" then
		self:_applyRuntimeState(result.data)
	end

	self:_setStatus(tostring(result.message or "No response message provided."), if result.ok then SUCCESS_COLOR else ERROR_COLOR)
end

function AdminPanelController:_clearRuntimeLoadout()
	local ok, result = self:_invokeAdminRequest(BODY_PARTS_TAB_ID, "clear_runtime_loadout", "Clearing runtime loadout", {})
	if not ok or not result then
		return
	end

	if typeof(result.data) == "table" then
		self:_applyRuntimeState(result.data)
	end

	self:_setStatus(tostring(result.message or "No response message provided."), if result.ok then SUCCESS_COLOR else ERROR_COLOR)
end

function AdminPanelController:_loadVisualSandboxOptions(forceRefresh: boolean?)
	if self._visualSandboxOptionsLoaded and not forceRefresh then
		self:_syncVisualSandboxUi()
		return true
	end

	local ok, result = self:_invokeAdminRequest(BODY_PARTS_TAB_ID, "get_visual_sandbox_options", "Loading visual sandbox options", {})
	if not ok or not result then
		self._visualSandboxOptionsLoaded = false
		self:_syncVisualSandboxUi()
		return false
	end

	if result.ok ~= true or typeof(result.data) ~= "table" or typeof(result.data.regions) ~= "table" then
		self._visualSandboxOptionsLoaded = false
		self:_setStatus(tostring(result.message or "Failed to load visual sandbox options."), ERROR_COLOR)
		self:_syncVisualSandboxUi()
		return false
	end

	self._visualSandboxOptions = result.data
	self._visualSandboxOptionsLoaded = true

	for _, region in ipairs(BodyPartRegions.Order) do
		local bundleNames = result.data.regions[region]
		if typeof(bundleNames) == "table" and #bundleNames > 0 then
			local selectedBundle = self._visualSandboxSelectedBundles[region]
			if not selectedBundle or not table.find(bundleNames, selectedBundle) then
				self._visualSandboxSelectedBundles[region] = bundleNames[1]
			end
		else
			self._visualSandboxSelectedBundles[region] = nil
		end
	end

	self:_syncVisualSandboxUi()
	self:_setStatus(tostring(result.message or "Visual sandbox options loaded."), SUCCESS_COLOR)
	return true
end

function AdminPanelController:_cycleVisualSandboxRegion(direction: number)
	local currentIndex = table.find(BodyPartRegions.Order, self._visualSandboxRegion) or 1
	local nextIndex = ((currentIndex - 1 + direction) % #BodyPartRegions.Order) + 1
	self._visualSandboxRegion = BodyPartRegions.Order[nextIndex]
	self:_syncVisualSandboxUi()
end

function AdminPanelController:_cycleVisualSandboxBundle(direction: number)
	if not self:_loadVisualSandboxOptions(true) then
		return
	end

	local bundleNames = self._visualSandboxOptions and self._visualSandboxOptions.regions and self._visualSandboxOptions.regions[self._visualSandboxRegion] or {}
	if #bundleNames == 0 then
		self:_setStatus("No example bundles are available for the selected region.", ERROR_COLOR)
		return
	end

	local currentBundle = self._visualSandboxSelectedBundles[self._visualSandboxRegion] or bundleNames[1]
	local currentIndex = table.find(bundleNames, currentBundle) or 1
	local nextIndex = ((currentIndex - 1 + direction) % #bundleNames) + 1
	self._visualSandboxSelectedBundles[self._visualSandboxRegion] = bundleNames[nextIndex]
	self:_syncVisualSandboxUi()
	self:_setStatus(string.format("Selected %s bundle: %s", self._visualSandboxRegion, bundleNames[nextIndex]), SUCCESS_COLOR)
end

function AdminPanelController:_getVisualSandboxScale(): number?
	local scaleText = self._visualSandboxScaleText
	local ui = self._visualSandboxUi
	if ui and ui.scaleInput and ui.scaleInput:IsA("TextBox") then
		scaleText = ui.scaleInput.Text
		self._visualSandboxScaleText = scaleText
	end

	local numericScale = tonumber(scaleText)
	if not numericScale or numericScale <= 0 then
		return nil
	end

	return numericScale
end

function AdminPanelController:_applyVisualSandboxRegion()
	if not self:_loadVisualSandboxOptions(true) then
		return
	end

	local scale = self:_getVisualSandboxScale()
	if not scale then
		self:_setStatus("Scale must be a positive number.", ERROR_COLOR)
		return
	end

	local region = self._visualSandboxRegion
	local bundleName = self._visualSandboxSelectedBundles[region]
	if not bundleName then
		self:_setStatus("Select a valid example bundle before applying.", ERROR_COLOR)
		return
	end

	local ok, result = self:_invokeAdminRequest(BODY_PARTS_TAB_ID, "apply_visual_region", "Applying visual region", {
		region = region,
		bundleName = bundleName,
		scale = scale,
	})
	if not ok or not result then
		return
	end

	self:_setStatus(tostring(result.message or "No response message provided."), if result.ok then SUCCESS_COLOR else ERROR_COLOR)

	if result.ok and typeof(result.data) == "table" and typeof(result.data.scale) == "number" then
		self._visualSandboxScaleText = string.format("%.2f", result.data.scale):gsub("0+$", ""):gsub("%.$", "")
		self:_syncVisualSandboxUi()
	end
end

function AdminPanelController:_resetVisualSandboxRegion()
	if not self:_loadVisualSandboxOptions() then
		return
	end

	local ok, result = self:_invokeAdminRequest(BODY_PARTS_TAB_ID, "reset_visual_region", "Resetting visual region", {
		region = self._visualSandboxRegion,
	})
	if not ok or not result then
		return
	end

	self:_setStatus(tostring(result.message or "No response message provided."), if result.ok then SUCCESS_COLOR else ERROR_COLOR)
end

function AdminPanelController:_resetVisualSandboxCharacter()
	local ok, result = self:_invokeAdminRequest(BODY_PARTS_TAB_ID, "reset_visual_character", "Resetting full character", {})
	if not ok or not result then
		return
	end

	self:_setStatus(tostring(result.message or "No response message provided."), if result.ok then SUCCESS_COLOR else ERROR_COLOR)
end

function AdminPanelController:_createVisualSandboxSection(parent: ScrollingFrame)
	self:_createSectionHeader(parent, "Visual Sandbox", "Live controls for trying example body part bundles and scale values on your own character.")

	local card = Instance.new("Frame")
	card.Name = "VisualSandboxCard"
	card.BackgroundColor3 = SANDBOX_CARD_COLOR
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Size = UDim2.new(1, -4, 0, 0)
	card.Parent = parent
	setGenerated(card)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = card
	setGenerated(corner)

	local stroke = Instance.new("UIStroke")
	stroke.Color = SANDBOX_STROKE_COLOR
	stroke.Transparency = 0.14
	stroke.Parent = card
	setGenerated(stroke)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 14)
	padding.PaddingBottom = UDim.new(0, 14)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = card
	setGenerated(padding)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Padding = UDim.new(0, 10)
	layout.Parent = card
	setGenerated(layout)

	local description = Instance.new("TextLabel")
	description.Name = "DescriptionLabel"
	description.BackgroundTransparency = 1
	description.Size = UDim2.new(1, 0, 0, 34)
	description.AutomaticSize = Enum.AutomaticSize.Y
	description.Font = Enum.Font.Gotham
	description.Text = "Cycle through the example bundles in GameAssets, set a scale, and apply them to the selected region of your current R15 character."
	description.TextWrapped = true
	description.TextSize = 14
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.TextColor3 = Color3.fromRGB(184, 196, 227)
	description.Parent = card
	setGenerated(description)

	local regionField = self:_createSandboxField(card, "Region")
	local regionRow = Instance.new("Frame")
	regionRow.Name = "ValueRow"
	regionRow.BackgroundTransparency = 1
	regionRow.Size = UDim2.new(1, 0, 0, 36)
	regionRow.Parent = regionField
	setGenerated(regionRow)

	local regionPrevButton = self:_createSandboxButton(regionRow, "PrevButton", "<", UDim2.fromOffset(38, 36), function()
		self:_cycleVisualSandboxRegion(-1)
	end)

	local regionValue = Instance.new("TextLabel")
	regionValue.Name = "ValueLabel"
	regionValue.BackgroundTransparency = 1
	regionValue.Position = UDim2.fromOffset(48, 0)
	regionValue.Size = UDim2.new(1, -96, 1, 0)
	regionValue.Font = Enum.Font.GothamSemibold
	regionValue.TextColor3 = Color3.fromRGB(244, 247, 255)
	regionValue.TextSize = 16
	regionValue.TextXAlignment = Enum.TextXAlignment.Center
	regionValue.Parent = regionRow
	setGenerated(regionValue)

	local regionNextButton = self:_createSandboxButton(regionRow, "NextButton", ">", UDim2.fromOffset(38, 36), function()
		self:_cycleVisualSandboxRegion(1)
	end)
	regionNextButton.Position = UDim2.new(1, -38, 0, 0)

	local bundleField = self:_createSandboxField(card, "Bundle")
	local bundleRow = Instance.new("Frame")
	bundleRow.Name = "ValueRow"
	bundleRow.BackgroundTransparency = 1
	bundleRow.Size = UDim2.new(1, 0, 0, 36)
	bundleRow.Parent = bundleField
	setGenerated(bundleRow)

	local bundlePrevButton = self:_createSandboxButton(bundleRow, "PrevButton", "<", UDim2.fromOffset(38, 36), function()
		self:_cycleVisualSandboxBundle(-1)
	end)

	local bundleValue = Instance.new("TextLabel")
	bundleValue.Name = "ValueLabel"
	bundleValue.BackgroundTransparency = 1
	bundleValue.Position = UDim2.fromOffset(48, 0)
	bundleValue.Size = UDim2.new(1, -96, 1, 0)
	bundleValue.Font = Enum.Font.GothamSemibold
	bundleValue.TextColor3 = Color3.fromRGB(244, 247, 255)
	bundleValue.TextSize = 16
	bundleValue.TextXAlignment = Enum.TextXAlignment.Center
	bundleValue.Parent = bundleRow
	setGenerated(bundleValue)

	local bundleNextButton = self:_createSandboxButton(bundleRow, "NextButton", ">", UDim2.fromOffset(38, 36), function()
		self:_cycleVisualSandboxBundle(1)
	end)
	bundleNextButton.Position = UDim2.new(1, -38, 0, 0)

	local scaleField = self:_createSandboxField(card, "Scale")
	local scaleInput = Instance.new("TextBox")
	scaleInput.Name = "ScaleInput"
	scaleInput.BackgroundColor3 = Color3.fromRGB(15, 20, 39)
	scaleInput.ClearTextOnFocus = false
	scaleInput.PlaceholderText = "1.0"
	scaleInput.Size = UDim2.new(1, 0, 0, 38)
	scaleInput.Font = Enum.Font.GothamSemibold
	scaleInput.Text = self._visualSandboxScaleText
	scaleInput.TextColor3 = Color3.fromRGB(245, 248, 255)
	scaleInput.TextSize = 16
	scaleInput.TextXAlignment = Enum.TextXAlignment.Left
	scaleInput.Parent = scaleField
	setGenerated(scaleInput)

	local inputCorner = Instance.new("UICorner")
	inputCorner.CornerRadius = UDim.new(0, 10)
	inputCorner.Parent = scaleInput
	setGenerated(inputCorner)

	local inputStroke = Instance.new("UIStroke")
	inputStroke.Color = SANDBOX_STROKE_COLOR
	inputStroke.Transparency = 0.2
	inputStroke.Parent = scaleInput
	setGenerated(inputStroke)

	local inputPadding = Instance.new("UIPadding")
	inputPadding.PaddingLeft = UDim.new(0, 12)
	inputPadding.PaddingRight = UDim.new(0, 12)
	inputPadding.Parent = scaleInput
	setGenerated(inputPadding)

	scaleInput.FocusLost:Connect(function()
		self._visualSandboxScaleText = scaleInput.Text
	end)

	local actionRow = Instance.new("Frame")
	actionRow.Name = "ActionRow"
	actionRow.BackgroundTransparency = 1
	actionRow.Size = UDim2.new(1, 0, 0, 40)
	actionRow.Parent = card
	setGenerated(actionRow)

	local actionLayout = Instance.new("UIListLayout")
	actionLayout.FillDirection = Enum.FillDirection.Horizontal
	actionLayout.Padding = UDim.new(0, 10)
	actionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	actionLayout.Parent = actionRow
	setGenerated(actionLayout)

	local actionButtonSize = UDim2.new(1 / 3, -7, 1, 0)

	local applyButton = self:_createSandboxButton(actionRow, "ApplyButton", "Apply Selected Region", actionButtonSize, function()
		self:_applyVisualSandboxRegion()
	end)

	local resetRegionButton = self:_createSandboxButton(actionRow, "ResetRegionButton", "Reset Selected Region", actionButtonSize, function()
		self:_resetVisualSandboxRegion()
	end)

	local resetCharacterButton = self:_createSandboxButton(actionRow, "ResetCharacterButton", "Reset Full Character", actionButtonSize, function()
		self:_resetVisualSandboxCharacter()
	end)

	self._visualSandboxUi = {
		regionPrevButton = regionPrevButton,
		regionNextButton = regionNextButton,
		regionValue = regionValue,
		bundlePrevButton = bundlePrevButton,
		bundleNextButton = bundleNextButton,
		bundleValue = bundleValue,
		scaleInput = scaleInput,
		applyButton = applyButton,
		resetRegionButton = resetRegionButton,
		resetCharacterButton = resetCharacterButton,
	}

	self:_syncVisualSandboxUi()
end

function AdminPanelController:_createGrantInventorySection(parent: ScrollingFrame)
	self:_createSectionHeader(parent, "Grant Inventory", "Grant a selected body part or aura directly to your own account for testing without leaving the admin panel.")

	local card = Instance.new("Frame")
	card.Name = "GrantInventoryCard"
	card.BackgroundColor3 = SANDBOX_CARD_COLOR
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Size = UDim2.new(1, -4, 0, 0)
	card.Parent = parent
	setGenerated(card)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = card
	setGenerated(corner)

	local stroke = Instance.new("UIStroke")
	stroke.Color = SANDBOX_STROKE_COLOR
	stroke.Transparency = 0.14
	stroke.Parent = card
	setGenerated(stroke)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 14)
	padding.PaddingBottom = UDim.new(0, 14)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = card
	setGenerated(padding)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Padding = UDim.new(0, 10)
	layout.Parent = card
	setGenerated(layout)

	local description = Instance.new("TextLabel")
	description.Name = "DescriptionLabel"
	description.BackgroundTransparency = 1
	description.Size = UDim2.new(1, 0, 0, 34)
	description.AutomaticSize = Enum.AutomaticSize.Y
	description.Font = Enum.Font.Gotham
	description.Text = "These grants go straight to your live profile data. Body parts are stored with default None/Normal variants, and aura grants reuse the normal unlock path."
	description.TextWrapped = true
	description.TextSize = 14
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.TextColor3 = Color3.fromRGB(184, 196, 227)
	description.Parent = card
	setGenerated(description)

	local bodyPartField = self:_createSandboxField(card, "Grant Body Part")
	local bodyPartRow = Instance.new("Frame")
	bodyPartRow.Name = "ValueRow"
	bodyPartRow.BackgroundTransparency = 1
	bodyPartRow.Size = UDim2.new(1, 0, 0, 126)
	bodyPartRow.Parent = bodyPartField
	setGenerated(bodyPartRow)

	local bodyPartPrevButton = self:_createSandboxButton(bodyPartRow, "PrevButton", "<", UDim2.fromOffset(38, 36), function()
		self:_cycleGrantBodyPart(-1)
	end)

	local bodyPartValue = Instance.new("TextLabel")
	bodyPartValue.Name = "ValueLabel"
	bodyPartValue.BackgroundTransparency = 1
	bodyPartValue.Position = UDim2.fromOffset(48, 0)
	bodyPartValue.Size = UDim2.new(1, -96, 1, 0)
	bodyPartValue.Font = Enum.Font.GothamSemibold
	bodyPartValue.TextColor3 = Color3.fromRGB(244, 247, 255)
	bodyPartValue.TextSize = 14
	bodyPartValue.TextWrapped = true
	bodyPartValue.TextXAlignment = Enum.TextXAlignment.Left
	bodyPartValue.TextYAlignment = Enum.TextYAlignment.Top
	bodyPartValue.Parent = bodyPartRow
	setGenerated(bodyPartValue)

	local bodyPartNextButton = self:_createSandboxButton(bodyPartRow, "NextButton", ">", UDim2.fromOffset(38, 36), function()
		self:_cycleGrantBodyPart(1)
	end)
	bodyPartNextButton.Position = UDim2.new(1, -38, 0, 0)

	local grantBodyPartButton = self:_createSandboxButton(card, "GrantBodyPartButton", "Grant Selected Body Part", UDim2.new(1, 0, 0, 40), function()
		self:_grantSelectedBodyPart()
	end)

	local auraField = self:_createSandboxField(card, "Grant Aura")
	local auraRow = Instance.new("Frame")
	auraRow.Name = "ValueRow"
	auraRow.BackgroundTransparency = 1
	auraRow.Size = UDim2.new(1, 0, 0, 118)
	auraRow.Parent = auraField
	setGenerated(auraRow)

	local auraPrevButton = self:_createSandboxButton(auraRow, "PrevButton", "<", UDim2.fromOffset(38, 36), function()
		self:_cycleGrantAura(-1)
	end)

	local auraValue = Instance.new("TextLabel")
	auraValue.Name = "ValueLabel"
	auraValue.BackgroundTransparency = 1
	auraValue.Position = UDim2.fromOffset(48, 0)
	auraValue.Size = UDim2.new(1, -96, 1, 0)
	auraValue.Font = Enum.Font.GothamSemibold
	auraValue.TextColor3 = Color3.fromRGB(244, 247, 255)
	auraValue.TextSize = 14
	auraValue.TextWrapped = true
	auraValue.TextXAlignment = Enum.TextXAlignment.Left
	auraValue.TextYAlignment = Enum.TextYAlignment.Top
	auraValue.Parent = auraRow
	setGenerated(auraValue)

	local auraNextButton = self:_createSandboxButton(auraRow, "NextButton", ">", UDim2.fromOffset(38, 36), function()
		self:_cycleGrantAura(1)
	end)
	auraNextButton.Position = UDim2.new(1, -38, 0, 0)

	local grantAuraButton = self:_createSandboxButton(card, "GrantAuraButton", "Grant Selected Aura", UDim2.new(1, 0, 0, 40), function()
		self:_grantSelectedAura()
	end)

	self._grantUi = {
		bodyPartPrevButton = bodyPartPrevButton,
		bodyPartNextButton = bodyPartNextButton,
		bodyPartValue = bodyPartValue,
		grantBodyPartButton = grantBodyPartButton,
		auraPrevButton = auraPrevButton,
		auraNextButton = auraNextButton,
		auraValue = auraValue,
		grantAuraButton = grantAuraButton,
	}

	self:_syncGrantUi()
end

function AdminPanelController:_createRuntimeInspectorSection(parent: ScrollingFrame)
	self:_createSectionHeader(parent, "Runtime Loadout", "Inspect the live runtime state, equip owned body parts into the session loadout, validate computed bonuses, and clear or unequip regions without leaving the admin panel.")

	local card = Instance.new("Frame")
	card.Name = "RuntimeLoadoutCard"
	card.BackgroundColor3 = SANDBOX_CARD_COLOR
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Size = UDim2.new(1, -4, 0, 0)
	card.Parent = parent
	setGenerated(card)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = card
	setGenerated(corner)

	local stroke = Instance.new("UIStroke")
	stroke.Color = SANDBOX_STROKE_COLOR
	stroke.Transparency = 0.14
	stroke.Parent = card
	setGenerated(stroke)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 14)
	padding.PaddingBottom = UDim.new(0, 14)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = card
	setGenerated(padding)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Padding = UDim.new(0, 10)
	layout.Parent = card
	setGenerated(layout)

	local ownedField = self:_createSandboxField(card, "Owned Body Part")
	local ownedRow = Instance.new("Frame")
	ownedRow.Name = "ValueRow"
	ownedRow.BackgroundTransparency = 1
	ownedRow.Size = UDim2.new(1, 0, 0, 108)
	ownedRow.Parent = ownedField
	setGenerated(ownedRow)

	local ownedPrevButton = self:_createSandboxButton(ownedRow, "PrevButton", "<", UDim2.fromOffset(38, 36), function()
		self:_cycleRuntimeOwned(-1)
	end)

	local ownedValue = Instance.new("TextLabel")
	ownedValue.Name = "ValueLabel"
	ownedValue.BackgroundTransparency = 1
	ownedValue.Position = UDim2.fromOffset(48, 0)
	ownedValue.Size = UDim2.new(1, -96, 1, 0)
	ownedValue.Font = Enum.Font.GothamSemibold
	ownedValue.TextColor3 = Color3.fromRGB(244, 247, 255)
	ownedValue.TextSize = 14
	ownedValue.TextWrapped = true
	ownedValue.TextXAlignment = Enum.TextXAlignment.Left
	ownedValue.TextYAlignment = Enum.TextYAlignment.Top
	ownedValue.Parent = ownedRow
	setGenerated(ownedValue)

	local ownedNextButton = self:_createSandboxButton(ownedRow, "NextButton", ">", UDim2.fromOffset(38, 36), function()
		self:_cycleRuntimeOwned(1)
	end)
	ownedNextButton.Position = UDim2.new(1, -38, 0, 0)

	local scaleField = self:_createSandboxField(card, "Equip Scale")
	local scaleInput = Instance.new("TextBox")
	scaleInput.Name = "ScaleInput"
	scaleInput.BackgroundColor3 = Color3.fromRGB(15, 20, 39)
	scaleInput.ClearTextOnFocus = false
	scaleInput.PlaceholderText = "1.0"
	scaleInput.Size = UDim2.new(1, 0, 0, 38)
	scaleInput.Font = Enum.Font.GothamSemibold
	scaleInput.Text = self._runtimeScaleText
	scaleInput.TextColor3 = Color3.fromRGB(245, 248, 255)
	scaleInput.TextSize = 16
	scaleInput.TextXAlignment = Enum.TextXAlignment.Left
	scaleInput.Parent = scaleField
	setGenerated(scaleInput)

	local scaleInputCorner = Instance.new("UICorner")
	scaleInputCorner.CornerRadius = UDim.new(0, 10)
	scaleInputCorner.Parent = scaleInput
	setGenerated(scaleInputCorner)

	local scaleInputStroke = Instance.new("UIStroke")
	scaleInputStroke.Color = SANDBOX_STROKE_COLOR
	scaleInputStroke.Transparency = 0.2
	scaleInputStroke.Parent = scaleInput
	setGenerated(scaleInputStroke)

	local scaleInputPadding = Instance.new("UIPadding")
	scaleInputPadding.PaddingLeft = UDim.new(0, 12)
	scaleInputPadding.PaddingRight = UDim.new(0, 12)
	scaleInputPadding.Parent = scaleInput
	setGenerated(scaleInputPadding)

	scaleInput.FocusLost:Connect(function()
		self._runtimeScaleText = scaleInput.Text
	end)

	local regionField = self:_createSandboxField(card, "Unequip Region")
	local regionRow = Instance.new("Frame")
	regionRow.Name = "ValueRow"
	regionRow.BackgroundTransparency = 1
	regionRow.Size = UDim2.new(1, 0, 0, 36)
	regionRow.Parent = regionField
	setGenerated(regionRow)

	local regionPrevButton = self:_createSandboxButton(regionRow, "PrevButton", "<", UDim2.fromOffset(38, 36), function()
		self:_cycleRuntimeRegion(-1)
	end)

	local regionValue = Instance.new("TextLabel")
	regionValue.Name = "ValueLabel"
	regionValue.BackgroundTransparency = 1
	regionValue.Position = UDim2.fromOffset(48, 0)
	regionValue.Size = UDim2.new(1, -96, 1, 0)
	regionValue.Font = Enum.Font.GothamSemibold
	regionValue.TextColor3 = Color3.fromRGB(244, 247, 255)
	regionValue.TextSize = 16
	regionValue.TextXAlignment = Enum.TextXAlignment.Center
	regionValue.Parent = regionRow
	setGenerated(regionValue)

	local regionNextButton = self:_createSandboxButton(regionRow, "NextButton", ">", UDim2.fromOffset(38, 36), function()
		self:_cycleRuntimeRegion(1)
	end)
	regionNextButton.Position = UDim2.new(1, -38, 0, 0)

	local equippedField = self:_createSandboxField(card, "Equipped Regions")
	local equippedValue = Instance.new("TextLabel")
	equippedValue.Name = "ValueLabel"
	equippedValue.BackgroundTransparency = 1
	equippedValue.Size = UDim2.new(1, 0, 0, 118)
	equippedValue.Font = Enum.Font.GothamSemibold
	equippedValue.TextColor3 = Color3.fromRGB(244, 247, 255)
	equippedValue.TextSize = 14
	equippedValue.TextWrapped = true
	equippedValue.TextXAlignment = Enum.TextXAlignment.Left
	equippedValue.TextYAlignment = Enum.TextYAlignment.Top
	equippedValue.Parent = equippedField
	setGenerated(equippedValue)

	local bonusesField = self:_createSandboxField(card, "Computed Bonuses")
	local bonusesValue = Instance.new("TextLabel")
	bonusesValue.Name = "ValueLabel"
	bonusesValue.BackgroundTransparency = 1
	bonusesValue.Size = UDim2.new(1, 0, 0, 86)
	bonusesValue.Font = Enum.Font.GothamSemibold
	bonusesValue.TextColor3 = Color3.fromRGB(244, 247, 255)
	bonusesValue.TextSize = 14
	bonusesValue.TextWrapped = true
	bonusesValue.TextXAlignment = Enum.TextXAlignment.Left
	bonusesValue.TextYAlignment = Enum.TextYAlignment.Top
	bonusesValue.Parent = bonusesField
	setGenerated(bonusesValue)

	local actionRow = Instance.new("Frame")
	actionRow.Name = "ActionRow"
	actionRow.BackgroundTransparency = 1
	actionRow.AutomaticSize = Enum.AutomaticSize.Y
	actionRow.Size = UDim2.new(1, 0, 0, 0)
	actionRow.Parent = card
	setGenerated(actionRow)

	local actionLayout = Instance.new("UIGridLayout")
	actionLayout.CellPadding = UDim2.fromOffset(10, 10)
	actionLayout.CellSize = UDim2.new(0.5, -5, 0, 40)
	actionLayout.FillDirectionMaxCells = 2
	actionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	actionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	actionLayout.Parent = actionRow
	setGenerated(actionLayout)

	local refreshButton = self:_createSandboxButton(actionRow, "RefreshButton", "Refresh Runtime State", UDim2.new(0, 0, 0, 40), function()
		self:_refreshRuntimeState()
	end)

	local equipButton = self:_createSandboxButton(actionRow, "EquipButton", "Equip Selected Owned Part", UDim2.new(0, 0, 0, 40), function()
		self:_equipSelectedOwnedBodyPart()
	end)

	local unequipButton = self:_createSandboxButton(actionRow, "UnequipButton", "Unequip Selected Region", UDim2.new(0, 0, 0, 40), function()
		self:_unequipSelectedRuntimeRegion()
	end)

	local clearButton = self:_createSandboxButton(actionRow, "ClearButton", "Clear Runtime Loadout", UDim2.new(0, 0, 0, 40), function()
		self:_clearRuntimeLoadout()
	end)

	self._runtimeUi = {
		ownedPrevButton = ownedPrevButton,
		ownedNextButton = ownedNextButton,
		ownedValue = ownedValue,
		scaleInput = scaleInput,
		regionPrevButton = regionPrevButton,
		regionNextButton = regionNextButton,
		regionValue = regionValue,
		equippedValue = equippedValue,
		bonusesValue = bonusesValue,
		refreshButton = refreshButton,
		equipButton = equipButton,
		unequipButton = unequipButton,
		clearButton = clearButton,
	}

	self:_syncRuntimeUi()
end

function AdminPanelController:_createPlayerStatsInspectorSection(parent: ScrollingFrame)
	self:_createSectionHeader(parent, "Player Stats", "Select any player in the current server and load their lifetime tracked stats, economy totals, roll history, and monetization counters.")

	local card = Instance.new("Frame")
	card.Name = "PlayerStatsCard"
	card.BackgroundColor3 = SANDBOX_CARD_COLOR
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Size = UDim2.new(1, -4, 0, 0)
	card.Parent = parent
	setGenerated(card)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = card
	setGenerated(corner)

	local stroke = Instance.new("UIStroke")
	stroke.Color = SANDBOX_STROKE_COLOR
	stroke.Transparency = 0.14
	stroke.Parent = card
	setGenerated(stroke)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 14)
	padding.PaddingBottom = UDim.new(0, 14)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = card
	setGenerated(padding)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Padding = UDim.new(0, 10)
	layout.Parent = card
	setGenerated(layout)

	local description = Instance.new("TextLabel")
	description.Name = "DescriptionLabel"
	description.BackgroundTransparency = 1
	description.Size = UDim2.new(1, 0, 0, 34)
	description.AutomaticSize = Enum.AutomaticSize.Y
	description.Font = Enum.Font.Gotham
	description.Text = "This reads the same inspect summary used by the in-world player inspect flow, so the admin panel and live inspect modal stay in sync."
	description.TextWrapped = true
	description.TextSize = 14
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.TextColor3 = Color3.fromRGB(184, 196, 227)
	description.Parent = card
	setGenerated(description)

	local playerField = self:_createSandboxField(card, "Target Player")
	local playerRow = Instance.new("Frame")
	playerRow.Name = "ValueRow"
	playerRow.BackgroundTransparency = 1
	playerRow.Size = UDim2.new(1, 0, 0, 36)
	playerRow.Parent = playerField
	setGenerated(playerRow)

	local playerPrevButton = self:_createSandboxButton(playerRow, "PrevButton", "<", UDim2.fromOffset(38, 36), function()
		self:_cyclePlayerStatsTarget(-1)
	end)

	local playerValue = Instance.new("TextLabel")
	playerValue.Name = "ValueLabel"
	playerValue.BackgroundTransparency = 1
	playerValue.Position = UDim2.fromOffset(48, 0)
	playerValue.Size = UDim2.new(1, -96, 1, 0)
	playerValue.Font = Enum.Font.GothamSemibold
	playerValue.TextColor3 = Color3.fromRGB(244, 247, 255)
	playerValue.TextSize = 16
	playerValue.TextWrapped = true
	playerValue.TextXAlignment = Enum.TextXAlignment.Center
	playerValue.TextYAlignment = Enum.TextYAlignment.Center
	playerValue.Parent = playerRow
	setGenerated(playerValue)

	local playerNextButton = self:_createSandboxButton(playerRow, "NextButton", ">", UDim2.fromOffset(38, 36), function()
		self:_cyclePlayerStatsTarget(1)
	end)
	playerNextButton.Position = UDim2.new(1, -38, 0, 0)

	local refreshButton = self:_createSandboxButton(card, "RefreshButton", "Load Selected Player Stats", UDim2.new(1, 0, 0, 40), function()
		self:_loadSelectedPlayerStats(true)
	end)

	local overviewField = self:_createSandboxField(card, "Overview")
	local overviewValue = self:_createSandboxValueLabel(overviewField)

	local economyField = self:_createSandboxField(card, "Economy")
	local economyValue = self:_createSandboxValueLabel(economyField)

	local rollsField = self:_createSandboxField(card, "Rolls")
	local rollsValue = self:_createSandboxValueLabel(rollsField)

	local collectionField = self:_createSandboxField(card, "Collection")
	local collectionValue = self:_createSandboxValueLabel(collectionField)

	local monetizationField = self:_createSandboxField(card, "Monetization")
	local monetizationValue = self:_createSandboxValueLabel(monetizationField)

	local settingsField = self:_createSandboxField(card, "Settings")
	local settingsValue = self:_createSandboxValueLabel(settingsField)

	self._playerStatsUi = {
		playerPrevButton = playerPrevButton,
		playerNextButton = playerNextButton,
		playerValue = playerValue,
		refreshButton = refreshButton,
		overviewValue = overviewValue,
		economyValue = economyValue,
		rollsValue = rollsValue,
		collectionValue = collectionValue,
		monetizationValue = monetizationValue,
		settingsValue = settingsValue,
	}

	self:_syncPlayerStatsUi()
end

function AdminPanelController:_createActionCard(parent: Instance, tabId: string, action: any, template: GuiButton)
	local card = template:Clone()
	card.Name = string.format("%sCard", action.id)
	card.Visible = true
	card.Parent = parent
	setGenerated(card)

	local titleLabel = card:FindFirstChild("TitleLabel")
	if titleLabel and titleLabel:IsA("TextLabel") then
		titleLabel.Text = action.title
	end

	local descriptionLabel = card:FindFirstChild("DescriptionLabel")
	if descriptionLabel and descriptionLabel:IsA("TextLabel") then
		descriptionLabel.Text = action.description
	end

	local badgeLabel = card:FindFirstChild("ActionBadge")
	if badgeLabel and badgeLabel:IsA("TextLabel") then
		badgeLabel.Text = "Stub"
	end

	UIController:CreateButton(card, function()
		self:_invokeAction(tabId, action.id, action.title)
	end)
end

function AdminPanelController:_buildPage(tabDefinition: any, page: ScrollingFrame, actionTemplate: GuiButton)
	for _, child in ipairs(page:GetChildren()) do
		if child:GetAttribute("GeneratedAdminPanel") == true then
			child:Destroy()
		end
	end

	if tabDefinition.id == BODY_PARTS_TAB_ID then
		self:_createGrantInventorySection(page)
		self:_createSpacer(page, 8)
		self:_createRuntimeInspectorSection(page)
		self:_createSpacer(page, 8)
		self:_createVisualSandboxSection(page)
		page.Visible = false
		page.CanvasPosition = Vector2.zero
		return
	end

	if tabDefinition.id == PLAYERS_TAB_ID then
		self:_createPlayerStatsInspectorSection(page)
		self:_createSpacer(page, 8)
	end

	for sectionIndex, section in ipairs(tabDefinition.sections) do
		self:_createSectionHeader(page, section.title, section.description)

		for _, action in ipairs(section.actions) do
			if not (tabDefinition.id == PLAYERS_TAB_ID and action.id == "inspect_player_profile") then
				self:_createActionCard(page, tabDefinition.id, action, actionTemplate)
			end
		end

		if sectionIndex < #tabDefinition.sections then
			self:_createSpacer(page, 8)
		end
	end

	page.Visible = false
	page.CanvasPosition = Vector2.zero
end

function AdminPanelController:_buildTabs(tabRail: Instance, tabTemplate: GuiButton)
	for _, child in ipairs(tabRail:GetChildren()) do
		if child:GetAttribute("GeneratedAdminPanel") == true then
			child:Destroy()
		end
	end

	self._tabButtons = {}

	for _, tabDefinition in ipairs(AdminPanelDefinitions.Tabs) do
		local button = tabTemplate:Clone()
		button.Name = string.format("%sTabButton", tabDefinition.pageName)
		button.Visible = true
		button.Parent = tabRail
		setGenerated(button)

		local titleLabel = button:FindFirstChild("TitleLabel")
		if titleLabel and titleLabel:IsA("TextLabel") then
			titleLabel.Text = tabDefinition.title
		end

		local subtitleLabel = button:FindFirstChild("SubtitleLabel")
		if subtitleLabel and subtitleLabel:IsA("TextLabel") then
			subtitleLabel.Text = tabDefinition.subtitle
		end

		self._tabButtons[tabDefinition.id] = button

		UIController:CreateButton(button, function()
			self:_setTab(tabDefinition.id)
		end)
	end
end

function AdminPanelController:_buildInterface(panel: Frame)
	local templates = panel:WaitForChild("Templates")
	local tabTemplate = templates:WaitForChild("TabButtonTemplate")
	local actionTemplate = templates:WaitForChild("ActionCardTemplate")

	if not (tabTemplate:IsA("GuiButton") and actionTemplate:IsA("GuiButton")) then
		error("AdminPanel templates are missing required button types.")
	end

	local body = panel:WaitForChild("Body")
	local tabRail = body:WaitForChild("TabRail"):WaitForChild("TabList")
	local content = body:WaitForChild("Content")
	local pages = content:WaitForChild("Pages")

	self._pageTitleLabel = content:WaitForChild("PageTitleLabel") :: TextLabel
	self._pageSubtitleLabel = content:WaitForChild("PageSubtitleLabel") :: TextLabel
	self._statusLabel = panel:WaitForChild("Footer"):WaitForChild("StatusLabel") :: TextLabel

	self:_buildTabs(tabRail, tabTemplate)
	self._pages = {}

	for _, tabDefinition in ipairs(AdminPanelDefinitions.Tabs) do
		local page = pages:WaitForChild(tabDefinition.pageName)
		if not page:IsA("ScrollingFrame") then
			error(string.format("AdminPanel page %s must be a ScrollingFrame.", tabDefinition.pageName))
		end

		self._pages[tabDefinition.id] = page
		self:_buildPage(tabDefinition, page, actionTemplate)
	end

	self:_setTab(AdminPanelDefinitions.Tabs[1].id)
end

function AdminPanelController:_refreshAccess()
	self._authorized = LOCAL_PLAYER:GetAttribute(ACCESS_ATTRIBUTE) == true

	if not self._authorized and self:_isWindowOpen() then
		HUDWindowController:CloseWindow(WINDOW_NAME, true)
	end

	if self._authorized then
		self:_setStatus("Press P to open the admin panel.")
	else
		self:_setStatus("You do not currently have access to the admin panel.", ERROR_COLOR)
	end
end

function AdminPanelController:_togglePanel()
	if not self:_isAuthorized() then
		return
	end

	HUDWindowController:ToggleWindow(WINDOW_NAME)

	if self:_isWindowOpen() then
		local selectedTabId = self._selectedTabId or AdminPanelDefinitions.Tabs[1].id
		self:_setTab(selectedTabId)
	end
end

function AdminPanelController:_bindInput(closeButton: GuiButton, dimmer: GuiButton)
	if self._inputConnection then
		self._inputConnection:Disconnect()
	end

	self._inputConnection = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
		if gameProcessedEvent then
			return
		end

		if UserInputService:GetFocusedTextBox() then
			return
		end

		if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == TOGGLE_KEY then
			self:_togglePanel()
		end
	end)

	UIController:CreateButton(closeButton, function()
		HUDWindowController:CloseWindow(WINDOW_NAME)
	end)

	dimmer.AutoButtonColor = false
	dimmer.Text = ""
	dimmer.Activated:Connect(function()
		HUDWindowController:CloseWindow(WINDOW_NAME)
	end)
end

function AdminPanelController:OnStart()
	self:_ensureState()

	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	local screenGui = playerGui:WaitForChild("AdminPanel", 30)
	if not (screenGui and screenGui:IsA("ScreenGui")) then
		warn("[AdminPanelController] AdminPanel ScreenGui was not found in PlayerGui.")
		return
	end

	self._screenGui = screenGui

	local windowRoot = screenGui:WaitForChild("WindowRoot", 30)
	if not (windowRoot and windowRoot:IsA("GuiObject")) then
		warn("[AdminPanelController] WindowRoot was not found under AdminPanel.")
		return
	end

	self._windowRoot = windowRoot

	local dimmer = windowRoot:WaitForChild("Dimmer", 30)
	local panel = windowRoot:WaitForChild("Panel", 30)
	if not ((dimmer and dimmer:IsA("GuiButton")) and (panel and panel:IsA("Frame"))) then
		warn("[AdminPanelController] AdminPanel is missing required Dimmer or Panel instances.")
		return
	end

	local closeButton = panel:WaitForChild("Header"):WaitForChild("CloseButton", 30)
	if not (closeButton and closeButton:IsA("GuiButton")) then
		warn("[AdminPanelController] AdminPanel close button is missing.")
		return
	end

	self:_buildInterface(panel)

	if not self._windowRegistered then
		HUDWindowController:RegisterWindow(WINDOW_NAME, windowRoot)
		self._windowRegistered = true
	end

	self:_bindInput(closeButton, dimmer)
	self:_refreshAccess()

	if self._accessConnection then
		self._accessConnection:Disconnect()
	end

	self._accessConnection = LOCAL_PLAYER:GetAttributeChangedSignal(ACCESS_ATTRIBUTE):Connect(function()
		self:_refreshAccess()
	end)
end

return AdminPanelController
