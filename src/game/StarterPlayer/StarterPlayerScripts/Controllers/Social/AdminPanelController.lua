local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local NumberFormatter = require(ReplicatedStorage.Shared.Formatting.NumberFormatter)
local AccessoryConfig = require(ReplicatedStorage.Shared.Config.AccessoryConfig)
local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local CraftingMaterialConfig = require(ReplicatedStorage.Shared.Config.CraftingMaterialConfig)
local SizeConfig = require(ReplicatedStorage.Shared.Config.SizeConfig)
local BodyPartRegions = require(ReplicatedStorage.Shared.Character.BodyPartRegions)
local MarketplaceCatalog = require(ReplicatedStorage.Lists.RobuxPurchases)
local AdminPanelDefinitions = require(ReplicatedStorage.Shared.UI.AdminPanelDefinitions)
local ChestOpeningSequence = require(ReplicatedStorage.Shared.UI.ChestOpeningSequence)
local PlayerStatsPresentation = require(ReplicatedStorage.Shared.UI.PlayerStatsPresentation)
local DialogueController = require(script.Parent.DialogueController)
local HUDWindowController = require(script.Parent.HUDWindowController)
local ObjectiveGuideController = require(script.Parent.ObjectiveGuideController)
local UIController = require(script.Parent.UIController)

local LOCAL_PLAYER = Players.LocalPlayer
local ACCESS_ATTRIBUTE = "CanUseAdminPanel"
local OVERVIEW_TAB_ID = "overview"
local PLAYERS_TAB_ID = "players"
local PURCHASES_TAB_ID = "purchases"
local PROGRESSION_TAB_ID = "progression"
local BODY_PARTS_TAB_ID = "bodyParts"
local ROLL_SOURCES_TAB_ID = "cases"
local HEAD_ACCESSORY_SLOT = "HeadAccessory"
local GEAR_ACCESSORY_SLOT = "GearAccessory"
local WINDOW_NAME = "AdminPanel"
local TOGGLE_KEY = Enum.KeyCode.P
local SUCCESS_COLOR = Color3.fromRGB(120, 255, 178)
local ERROR_COLOR = Color3.fromRGB(255, 141, 141)
local DEFAULT_STATUS_COLOR = Color3.fromRGB(178, 187, 211)
local NOTIFICATION_DEFAULT_DURATION = "4"
local NOTIFICATION_MIN_DURATION = 1
local NOTIFICATION_MAX_DURATION = 10
local PANEL_BACKGROUND_COLOR = Color3.fromRGB(12, 15, 23)
local PANEL_SURFACE_COLOR = Color3.fromRGB(16, 20, 30)
local PANEL_SURFACE_ALT_COLOR = Color3.fromRGB(21, 26, 38)
local PANEL_STROKE_COLOR = Color3.fromRGB(61, 72, 97)
local PANEL_ACCENT_COLOR = Color3.fromRGB(111, 159, 255)
local SANDBOX_CARD_COLOR = PANEL_SURFACE_COLOR
local SANDBOX_STROKE_COLOR = PANEL_STROKE_COLOR
local SANDBOX_FIELD_COLOR = PANEL_SURFACE_ALT_COLOR
local SANDBOX_BUTTON_COLOR = Color3.fromRGB(42, 53, 76)
local SANDBOX_BUTTON_TEXT_COLOR = Color3.fromRGB(235, 240, 255)
local DESTRUCTIVE_STROKE_COLOR = Color3.fromRGB(201, 91, 91)
local MUTATING_BADGE_COLOR = Color3.fromRGB(196, 148, 69)
local SAFE_BADGE_COLOR = Color3.fromRGB(84, 162, 116)
local COMPACT_CORNER_RADIUS = UDim.new(0, 6)
local PANEL_CORNER_RADIUS = UDim.new(0, 8)
local COMPACT_BUTTON_HEIGHT = 36
local DEFAULT_CRAFTING_MATERIAL_GRANT_AMOUNT = "25"
local PURCHASE_SELECTOR_BUTTON_COUNT = 6
local ADMIN_CHEST_TRIGGER_ACTION_IDS = table.freeze({
	trigger_daily_free_chest = true,
	trigger_vip_chest = true,
	trigger_vip_plus_chest = true,
})

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
	self._grantSelectedHeadAccessoryId = nil :: string?
	self._grantSelectedGearAccessoryId = nil :: string?
	self._grantSelectedCraftingMaterialId = nil :: string?
	self._grantCraftingMaterialAmountText = DEFAULT_CRAFTING_MATERIAL_GRANT_AMOUNT
	self._grantUi = {}
	self._playerStatsSelectedUserId = nil
	self._playerStatsSummary = nil
	self._playerStatsUi = {}
	self._notificationTargetKey = "self"
	self._notificationMessageText = ""
	self._notificationDurationText = NOTIFICATION_DEFAULT_DURATION
	self._notificationUi = {}
	self._luckOverrideInputText = ""
	self._luckOverrideState = nil
	self._luckOverrideUi = {}
	self._purchaseTargetUserIdText = tostring(LOCAL_PLAYER.UserId)
	self._purchaseSelectedGamepassKey = nil :: string?
	self._purchaseSelectedDevProductKey = nil :: string?
	self._purchaseGamepassSearchText = ""
	self._purchaseDevProductSearchText = ""
	self._purchaseDevProductCountText = "1"
	self._purchasesUi = {}
	self._actionFormInputs = {}
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

local function getOrCreateChild(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end

	local child = Instance.new(className)
	child.Name = name
	child.Parent = parent
	return child
end

local function getOrCreateFirstChildOfClass(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChildWhichIsA(className)
	if existing then
		return existing
	end

	local child = Instance.new(className)
	child.Name = name
	child.Parent = parent
	return child
end

local function getRiskBadgeText(action: any): string
	if action.risk == "destructive" then
		return "Live gated"
	end
	if action.risk == "mutating" then
		return "Mutating"
	end
	return "Safe"
end

local function getRiskBadgeColor(action: any): Color3
	if action.risk == "destructive" then
		return DESTRUCTIVE_STROKE_COLOR
	end
	if action.risk == "mutating" then
		return MUTATING_BADGE_COLOR
	end
	return SAFE_BADGE_COLOR
end

local function compactHeight(height: number): number
	if height >= 38 and height <= 44 then
		return 34
	end
	return height
end

local function firstLine(value: string): string
	return (string.match(value, "^[^\n]+") or value)
end

local function normalizeSearchText(value: any): string
	local normalized = tostring(value or "")
	normalized = string.gsub(normalized, "\r\n", "\n")
	normalized = string.gsub(normalized, "\r", "\n")
	return string.lower(string.match(normalized, "^%s*(.-)%s*$") or "")
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

local function formatLuckMultiplier(value: number?): string
	local numericValue = tonumber(value)
	if numericValue == nil or numericValue ~= numericValue then
		return "N/A"
	end

	return string.format("%sx", formatNumberish(numericValue))
end

local function formatPlayerDisplay(player: Player?): string
	if not player then
		return "No player selected"
	end

	return string.format("%s (@%s)", player.DisplayName, player.Name)
end

local function trimText(value: any): string
	if typeof(value) ~= "string" then
		return ""
	end

	local normalized = string.gsub(value, "\r\n", "\n")
	normalized = string.gsub(normalized, "\r", "\n")
	return string.match(normalized, "^%s*(.-)%s*$") or ""
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
		Logger.Warn(string.format("[AdminPanelController] AdminAction invoke failed: %s", tostring(result)))
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

function AdminPanelController:_handlePostAdminAction(tabId: string, actionId: string, result: any)
	if not (result and result.ok == true) then
		return
	end

	if tabId == OVERVIEW_TAB_ID and actionId == "test_dialogue" then
		local data = if typeof(result.data) == "table" then result.data else {}
		local dialogueId = if typeof(data.dialogueId) == "string" and data.dialogueId ~= "" then data.dialogueId else "merchant_default"
		local context = if typeof(data.context) == "table" then data.context else {}

		HUDWindowController:CloseWindow(WINDOW_NAME, true)
		task.defer(function()
			DialogueController.StartDialogue(dialogueId, context)
		end)
		return
	end

	if tabId == OVERVIEW_TAB_ID and actionId == "guide_to_crafting" then
		local data = if typeof(result.data) == "table" then result.data else {}
		local objectiveId = if typeof(data.objectiveId) == "string" and data.objectiveId ~= "" then data.objectiveId else "crafting"
		local targetPath = if typeof(data.targetPath) == "string" and data.targetPath ~= "" then data.targetPath else "Workspace.Crafting"
		local fallbackTargetPath = if typeof(data.fallbackTargetPath) == "string" and data.fallbackTargetPath ~= ""
			then data.fallbackTargetPath
			else "Workspace.Crafting"

		HUDWindowController:CloseWindow(WINDOW_NAME, true)
		task.defer(function()
			ObjectiveGuideController.ShowObjective(objectiveId, targetPath, {
				fallbackTargetPath = fallbackTargetPath,
			})
		end)
		return
	end

	if tabId == ROLL_SOURCES_TAB_ID and actionId == "preview_chest_opening" then
		local data = if typeof(result.data) == "table" then result.data else {}
		local chestId = if typeof(data.chestId) == "string" and data.chestId ~= "" then data.chestId else "Basic"
		local rewards = if typeof(data.rewards) == "table" then data.rewards else {}

		HUDWindowController:CloseWindow(WINDOW_NAME, true)
		task.defer(function()
			local ok, errorMessage = pcall(function()
				ChestOpeningSequence.OpenChest(chestId, rewards)
			end)
			if not ok then
				Logger.Warn(string.format("[AdminPanelController] Chest preview failed: %s", tostring(errorMessage)))
				self:_setStatus("Chest preview failed. Check the output for details.", ERROR_COLOR)
			end
		end)
	end

	if tabId == ROLL_SOURCES_TAB_ID and ADMIN_CHEST_TRIGGER_ACTION_IDS[actionId] == true then
		local data = if typeof(result.data) == "table" then result.data else {}
		local visualChestId = if typeof(data.visualChestId) == "string" and data.visualChestId ~= ""
			then data.visualChestId
			else if typeof(data.chestId) == "string" and data.chestId ~= "" then data.chestId else "Basic"
		local rewards = if typeof(data.rewards) == "table" then data.rewards else {}

		HUDWindowController:CloseWindow(WINDOW_NAME, true)
		task.defer(function()
			local ok, errorMessage = pcall(function()
				ChestOpeningSequence.OpenChestAsync(visualChestId, rewards)
			end)
			if not ok then
				Logger.Warn(string.format("[AdminPanelController] Admin chest trigger failed: %s", tostring(errorMessage)))
				self:_setStatus("Admin chest trigger failed. Check the output for details.", ERROR_COLOR)
			end
		end)
	end
end

function AdminPanelController:_styleCompactCard(card: GuiObject, risk: string?)
	card.BackgroundColor3 = SANDBOX_CARD_COLOR
	card.BackgroundTransparency = 0
	card.BorderSizePixel = 0
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Size = UDim2.new(1, -2, 0, 0)

	local corner = getOrCreateFirstChildOfClass(card, "UICorner", "CompactCorner") :: UICorner
	corner.CornerRadius = COMPACT_CORNER_RADIUS

	local stroke = getOrCreateFirstChildOfClass(card, "UIStroke", "CompactStroke") :: UIStroke
	stroke.Color = if risk == "destructive" then DESTRUCTIVE_STROKE_COLOR else SANDBOX_STROKE_COLOR
	stroke.Transparency = if risk == "destructive" then 0.08 else 0.28
	stroke.Thickness = 1

	local padding = getOrCreateFirstChildOfClass(card, "UIPadding", "CompactPadding") :: UIPadding
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)

	local layout = getOrCreateFirstChildOfClass(card, "UIListLayout", "CompactLayout") :: UIListLayout
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 7)
end

function AdminPanelController:_styleActionCard(card: GuiButton, action: any)
	self:_styleCompactCard(card, action.risk)
	card.AutoButtonColor = false
	if card:IsA("TextButton") then
		card.Text = ""
	end

	local titleLabel = card:FindFirstChild("TitleLabel")
	if titleLabel and titleLabel:IsA("TextLabel") then
		titleLabel.BackgroundTransparency = 1
		titleLabel.Font = Enum.Font.GothamBold
		titleLabel.TextSize = 15
		titleLabel.TextColor3 = Color3.fromRGB(242, 246, 255)
		titleLabel.TextWrapped = true
		titleLabel.TextXAlignment = Enum.TextXAlignment.Left
		titleLabel.AutomaticSize = Enum.AutomaticSize.Y
		titleLabel.Size = UDim2.new(1, 0, 0, 0)
		titleLabel.LayoutOrder = 1
	end

	local descriptionLabel = card:FindFirstChild("DescriptionLabel")
	if descriptionLabel and descriptionLabel:IsA("TextLabel") then
		descriptionLabel.BackgroundTransparency = 1
		descriptionLabel.Font = Enum.Font.Gotham
		descriptionLabel.TextSize = 13
		descriptionLabel.TextColor3 = Color3.fromRGB(168, 179, 207)
		descriptionLabel.TextWrapped = true
		descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
		descriptionLabel.TextYAlignment = Enum.TextYAlignment.Top
		descriptionLabel.AutomaticSize = Enum.AutomaticSize.Y
		descriptionLabel.Size = UDim2.new(1, 0, 0, 0)
		descriptionLabel.LayoutOrder = 3
	end

	local badgeLabel = card:FindFirstChild("ActionBadge")
	if badgeLabel and badgeLabel:IsA("TextLabel") then
		badgeLabel.BackgroundColor3 = getRiskBadgeColor(action)
		badgeLabel.BackgroundTransparency = 0.82
		badgeLabel.BorderSizePixel = 0
		badgeLabel.Font = Enum.Font.GothamBold
		badgeLabel.TextColor3 = getRiskBadgeColor(action)
		badgeLabel.TextSize = 11
		badgeLabel.TextXAlignment = Enum.TextXAlignment.Left
		badgeLabel.AutomaticSize = Enum.AutomaticSize.XY
		badgeLabel.Size = UDim2.fromOffset(0, 20)
		badgeLabel.LayoutOrder = 2

		local badgeCorner = getOrCreateFirstChildOfClass(badgeLabel, "UICorner", "BadgeCorner") :: UICorner
		badgeCorner.CornerRadius = UDim.new(0, 5)

		local badgePadding = getOrCreateFirstChildOfClass(badgeLabel, "UIPadding", "BadgePadding") :: UIPadding
		badgePadding.PaddingLeft = UDim.new(0, 7)
		badgePadding.PaddingRight = UDim.new(0, 7)
		badgePadding.PaddingTop = UDim.new(0, 2)
		badgePadding.PaddingBottom = UDim.new(0, 2)
	end
end

function AdminPanelController:_applyCompactPanelLayout(panel: Frame)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.86, 0.82)
	panel.BackgroundColor3 = PANEL_BACKGROUND_COLOR
	panel.BackgroundTransparency = 0
	panel.BorderSizePixel = 0
	panel.ClipsDescendants = true

	local sizeConstraint = getOrCreateChild(panel, "UISizeConstraint", "CompactModalSize") :: UISizeConstraint
	sizeConstraint.MinSize = Vector2.new(680, 500)
	sizeConstraint.MaxSize = Vector2.new(1180, 760)

	local panelCorner = getOrCreateFirstChildOfClass(panel, "UICorner", "PanelCorner") :: UICorner
	panelCorner.CornerRadius = PANEL_CORNER_RADIUS

	local panelStroke = getOrCreateFirstChildOfClass(panel, "UIStroke", "PanelStroke") :: UIStroke
	panelStroke.Color = Color3.fromRGB(80, 92, 124)
	panelStroke.Transparency = 0.2
	panelStroke.Thickness = 1

	local header = panel:FindFirstChild("Header")
	if header and header:IsA("GuiObject") then
		header.BackgroundColor3 = Color3.fromRGB(15, 18, 27)
		header.BackgroundTransparency = 0
		header.BorderSizePixel = 0
		header.Position = UDim2.fromOffset(0, 0)
		header.Size = UDim2.new(1, 0, 0, 48)

		for _, descendant in ipairs(header:GetDescendants()) do
			if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
				descendant.TextSize = math.min(descendant.TextSize, 18)
			end
		end
	end

	local footer = panel:FindFirstChild("Footer")
	if footer and footer:IsA("GuiObject") then
		footer.BackgroundColor3 = Color3.fromRGB(13, 16, 24)
		footer.BackgroundTransparency = 0
		footer.BorderSizePixel = 0
		footer.Position = UDim2.new(0, 0, 1, -34)
		footer.Size = UDim2.new(1, 0, 0, 34)
	end

	local body = panel:FindFirstChild("Body")
	if not (body and body:IsA("GuiObject")) then
		return
	end

	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(0, 48)
	body.Size = UDim2.new(1, 0, 1, -82)

	local bodyPadding = getOrCreateFirstChildOfClass(body, "UIPadding", "BodyPadding") :: UIPadding
	bodyPadding.PaddingTop = UDim.new(0, 10)
	bodyPadding.PaddingBottom = UDim.new(0, 10)
	bodyPadding.PaddingLeft = UDim.new(0, 12)
	bodyPadding.PaddingRight = UDim.new(0, 12)

	local bodyLayout = getOrCreateFirstChildOfClass(body, "UIListLayout", "BodyLayout") :: UIListLayout
	bodyLayout.FillDirection = Enum.FillDirection.Vertical
	bodyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Padding = UDim.new(0, 10)

	local tabRail = body:FindFirstChild("TabRail")
	if tabRail and tabRail:IsA("GuiObject") then
		tabRail.BackgroundTransparency = 1
		tabRail.BorderSizePixel = 0
		tabRail.Size = UDim2.new(1, 0, 0, 44)
		tabRail.LayoutOrder = 1
	end

	local tabList = tabRail and tabRail:FindFirstChild("TabList")
	if tabList and tabList:IsA("GuiObject") then
		tabList.BackgroundTransparency = 1
		tabList.BorderSizePixel = 0
		tabList.Size = UDim2.fromScale(1, 1)
		tabList.ClipsDescendants = true

		local tabPadding = getOrCreateFirstChildOfClass(tabList, "UIPadding", "TabListPadding") :: UIPadding
		tabPadding.PaddingTop = UDim.new(0, 1)
		tabPadding.PaddingBottom = UDim.new(0, 1)
		tabPadding.PaddingLeft = UDim.new(0, 1)
		tabPadding.PaddingRight = UDim.new(0, 1)

		local tabLayout = getOrCreateFirstChildOfClass(tabList, "UIListLayout", "TabListLayout") :: UIListLayout
		tabLayout.FillDirection = Enum.FillDirection.Horizontal
		tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
		tabLayout.Padding = UDim.new(0, 6)
	end

	local content = body:FindFirstChild("Content")
	if content and content:IsA("GuiObject") then
		content.BackgroundColor3 = Color3.fromRGB(13, 16, 24)
		content.BackgroundTransparency = 0
		content.BorderSizePixel = 0
		content.Size = UDim2.new(1, 0, 1, -54)
		content.LayoutOrder = 2

		local contentCorner = getOrCreateFirstChildOfClass(content, "UICorner", "ContentCorner") :: UICorner
		contentCorner.CornerRadius = COMPACT_CORNER_RADIUS

		local contentStroke = getOrCreateFirstChildOfClass(content, "UIStroke", "ContentStroke") :: UIStroke
		contentStroke.Color = SANDBOX_STROKE_COLOR
		contentStroke.Transparency = 0.42
		contentStroke.Thickness = 1

		local contentPadding = getOrCreateFirstChildOfClass(content, "UIPadding", "ContentPadding") :: UIPadding
		contentPadding.PaddingTop = UDim.new(0, 10)
		contentPadding.PaddingBottom = UDim.new(0, 10)
		contentPadding.PaddingLeft = UDim.new(0, 10)
		contentPadding.PaddingRight = UDim.new(0, 10)

		local contentLayout = getOrCreateFirstChildOfClass(content, "UIListLayout", "ContentLayout") :: UIListLayout
		contentLayout.FillDirection = Enum.FillDirection.Vertical
		contentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
		contentLayout.Padding = UDim.new(0, 4)
	end
end

function AdminPanelController:_createSimpleMenuLayout(panel: Frame): any
	local oldCompactSize = panel:FindFirstChild("CompactModalSize")
	if oldCompactSize then
		oldCompactSize:Destroy()
	end

	for _, child in ipairs(panel:GetChildren()) do
		if child.Name ~= "Templates" and child.Name ~= "SimpleMenuRoot" and child:IsA("GuiObject") then
			child.Visible = false
		end
	end

	local existingRoot = panel:FindFirstChild("SimpleMenuRoot")
	if existingRoot then
		existingRoot:Destroy()
	end

	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.86, 0.82)
	panel.BackgroundColor3 = Color3.fromRGB(13, 16, 24)
	panel.BackgroundTransparency = 0
	panel.BorderSizePixel = 0
	panel.ClipsDescendants = true

	local sizeConstraint = getOrCreateChild(panel, "UISizeConstraint", "SimpleMenuSize") :: UISizeConstraint
	sizeConstraint.MinSize = Vector2.new(560, 420)
	sizeConstraint.MaxSize = Vector2.new(1120, 720)

	local panelCorner = getOrCreateFirstChildOfClass(panel, "UICorner", "SimpleMenuCorner") :: UICorner
	panelCorner.CornerRadius = UDim.new(0, 6)

	local panelStroke = getOrCreateFirstChildOfClass(panel, "UIStroke", "SimpleMenuStroke") :: UIStroke
	panelStroke.Color = Color3.fromRGB(70, 80, 105)
	panelStroke.Transparency = 0.24
	panelStroke.Thickness = 1

	local root = Instance.new("Frame")
	root.Name = "SimpleMenuRoot"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = panel
	setGenerated(root)

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundColor3 = Color3.fromRGB(17, 21, 31)
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, 0, 0, 42)
	header.Parent = root
	setGenerated(header)

	local headerPadding = Instance.new("UIPadding")
	headerPadding.PaddingLeft = UDim.new(0, 14)
	headerPadding.PaddingRight = UDim.new(0, 8)
	headerPadding.Parent = header
	setGenerated(headerPadding)

	local title = Instance.new("TextLabel")
	title.Name = "TitleLabel"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -44, 1, 0)
	title.Font = Enum.Font.GothamBold
	title.Text = "Admin"
	title.TextColor3 = Color3.fromRGB(242, 245, 252)
	title.TextSize = 17
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header
	setGenerated(title)

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.AnchorPoint = Vector2.new(1, 0.5)
	closeButton.Position = UDim2.new(1, 0, 0.5, 0)
	closeButton.Size = UDim2.fromOffset(32, 28)
	closeButton.BackgroundColor3 = Color3.fromRGB(28, 34, 48)
	closeButton.BorderSizePixel = 0
	closeButton.Font = Enum.Font.GothamBold
	closeButton.Text = "X"
	closeButton.TextColor3 = Color3.fromRGB(220, 226, 240)
	closeButton.TextSize = 13
	closeButton.Parent = header
	setGenerated(closeButton)

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 5)
	closeCorner.Parent = closeButton
	setGenerated(closeCorner)

	UIController:CreateButton(closeButton, function()
		HUDWindowController:CloseWindow(WINDOW_NAME)
	end)

	local tabList = Instance.new("Frame")
	tabList.Name = "TabList"
	tabList.BackgroundColor3 = Color3.fromRGB(12, 15, 22)
	tabList.BorderSizePixel = 0
	tabList.Position = UDim2.fromOffset(0, 42)
	tabList.Size = UDim2.new(1, 0, 0, 38)
	tabList.Parent = root
	setGenerated(tabList)

	local tabPadding = Instance.new("UIPadding")
	tabPadding.PaddingTop = UDim.new(0, 6)
	tabPadding.PaddingBottom = UDim.new(0, 6)
	tabPadding.PaddingLeft = UDim.new(0, 10)
	tabPadding.PaddingRight = UDim.new(0, 10)
	tabPadding.Parent = tabList
	setGenerated(tabPadding)

	local tabLayout = Instance.new("UIGridLayout")
	tabLayout.CellPadding = UDim2.fromOffset(6, 0)
	tabLayout.CellSize = UDim2.new(1 / #AdminPanelDefinitions.Tabs, -5, 1, 0)
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.FillDirectionMaxCells = #AdminPanelDefinitions.Tabs
	tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabList
	setGenerated(tabLayout)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(0, 80)
	content.Size = UDim2.new(1, 0, 1, -110)
	content.Parent = root
	setGenerated(content)

	local contentPadding = Instance.new("UIPadding")
	contentPadding.PaddingTop = UDim.new(0, 10)
	contentPadding.PaddingLeft = UDim.new(0, 12)
	contentPadding.PaddingRight = UDim.new(0, 12)
	contentPadding.PaddingBottom = UDim.new(0, 8)
	contentPadding.Parent = content
	setGenerated(contentPadding)

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.FillDirection = Enum.FillDirection.Vertical
	contentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Padding = UDim.new(0, 4)
	contentLayout.Parent = content
	setGenerated(contentLayout)

	local pageTitle = Instance.new("TextLabel")
	pageTitle.Name = "PageTitleLabel"
	pageTitle.BackgroundTransparency = 1
	pageTitle.Size = UDim2.new(1, 0, 0, 24)
	pageTitle.Font = Enum.Font.GothamBold
	pageTitle.TextColor3 = Color3.fromRGB(242, 245, 252)
	pageTitle.TextSize = 18
	pageTitle.TextXAlignment = Enum.TextXAlignment.Left
	pageTitle.LayoutOrder = 1
	pageTitle.Parent = content
	setGenerated(pageTitle)

	local pageSubtitle = Instance.new("TextLabel")
	pageSubtitle.Name = "PageSubtitleLabel"
	pageSubtitle.BackgroundTransparency = 1
	pageSubtitle.Size = UDim2.new(1, 0, 0, 18)
	pageSubtitle.Font = Enum.Font.Gotham
	pageSubtitle.TextColor3 = Color3.fromRGB(145, 156, 185)
	pageSubtitle.TextSize = 12
	pageSubtitle.TextXAlignment = Enum.TextXAlignment.Left
	pageSubtitle.TextTruncate = Enum.TextTruncate.AtEnd
	pageSubtitle.LayoutOrder = 2
	pageSubtitle.Parent = content
	setGenerated(pageSubtitle)

	local pages = Instance.new("Frame")
	pages.Name = "Pages"
	pages.BackgroundTransparency = 1
	pages.Size = UDim2.new(1, 0, 1, -50)
	pages.LayoutOrder = 3
	pages.Parent = content
	setGenerated(pages)

	local footer = Instance.new("Frame")
	footer.Name = "Footer"
	footer.BackgroundColor3 = Color3.fromRGB(12, 15, 22)
	footer.BorderSizePixel = 0
	footer.Position = UDim2.new(0, 0, 1, -30)
	footer.Size = UDim2.new(1, 0, 0, 30)
	footer.Parent = root
	setGenerated(footer)

	local status = Instance.new("TextLabel")
	status.Name = "StatusLabel"
	status.BackgroundTransparency = 1
	status.Size = UDim2.new(1, -24, 1, 0)
	status.Position = UDim2.fromOffset(12, 0)
	status.Font = Enum.Font.Gotham
	status.TextColor3 = DEFAULT_STATUS_COLOR
	status.TextSize = 12
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextTruncate = Enum.TextTruncate.AtEnd
	status.Parent = footer
	setGenerated(status)

	return {
		tabList = tabList,
		content = content,
		pages = pages,
		pageTitle = pageTitle,
		pageSubtitle = pageSubtitle,
		status = status,
	}
end

function AdminPanelController:_styleTabButton(button: GuiButton, selected: boolean)
	local titleLabel = button:FindFirstChild("TitleLabel")
	local subtitleLabel = button:FindFirstChild("SubtitleLabel")
	local stroke = button:FindFirstChildWhichIsA("UIStroke")

	button.BackgroundColor3 = if selected then Color3.fromRGB(34, 44, 64) else Color3.fromRGB(20, 25, 36)
	button.BackgroundTransparency = 0
	button.BorderSizePixel = 0
	button.Size = UDim2.fromScale(1, 1)
	button.AutoButtonColor = false
	if button:IsA("TextButton") then
		button.Text = ""
	end

	local corner = getOrCreateFirstChildOfClass(button, "UICorner", "TabCorner") :: UICorner
	corner.CornerRadius = UDim.new(0, 5)

	if stroke then
		stroke.Color = if selected then PANEL_ACCENT_COLOR else SANDBOX_STROKE_COLOR
		stroke.Transparency = if selected then 0.18 else 0.7
		stroke.Thickness = 1
	end

	if titleLabel and titleLabel:IsA("TextLabel") then
		titleLabel.BackgroundTransparency = 1
		titleLabel.Font = Enum.Font.GothamBold
		titleLabel.TextSize = 13
		titleLabel.TextColor3 = if selected then Color3.fromRGB(246, 249, 255) else Color3.fromRGB(178, 188, 214)
		titleLabel.TextXAlignment = Enum.TextXAlignment.Center
		titleLabel.TextYAlignment = Enum.TextYAlignment.Center
		titleLabel.Size = UDim2.fromScale(1, 1)
		titleLabel.Position = UDim2.fromScale(0, 0)
		titleLabel.LayoutOrder = 1
		setTextStroke(titleLabel, 1)
	end

	if subtitleLabel and subtitleLabel:IsA("TextLabel") then
		subtitleLabel.Visible = false
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
	elseif tabId == PROGRESSION_TAB_ID then
		self:_syncLuckOverrideUi()
		self:_loadLuckOverrideState(true)
	elseif tabId == PURCHASES_TAB_ID then
		self:_syncPurchasesUi()
	elseif tabId == OVERVIEW_TAB_ID then
		self:_syncNotificationUi()
	end
end

function AdminPanelController:_createSectionHeader(parent: Instance, title: string, description: string)
	local container = Instance.new("Frame")
	container.Name = title:gsub("%s+", "") .. "Section"
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(1, 0, 0, 22)
	container.Parent = parent
	setGenerated(container)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.new(1, 0, 0, 20)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Text = title
	titleLabel.TextSize = 16
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextColor3 = Color3.fromRGB(247, 249, 255)
	titleLabel.Parent = container
	setGenerated(titleLabel)

	local descriptionLabel = Instance.new("TextLabel")
	descriptionLabel.Name = "DescriptionLabel"
	descriptionLabel.BackgroundTransparency = 1
	descriptionLabel.Visible = false
	descriptionLabel.Position = UDim2.fromOffset(0, 21)
	descriptionLabel.Size = UDim2.new(1, 0, 0, 26)
	descriptionLabel.AutomaticSize = Enum.AutomaticSize.Y
	descriptionLabel.Font = Enum.Font.Gotham
	descriptionLabel.Text = description
	descriptionLabel.TextWrapped = true
	descriptionLabel.TextSize = 13
	descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
	descriptionLabel.TextYAlignment = Enum.TextYAlignment.Top
	descriptionLabel.TextColor3 = Color3.fromRGB(145, 156, 185)
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
	if tabId == PLAYERS_TAB_ID and actionId == "repair_marketplace_entitlement" then
		self:_repairSelectedPlayerVipPlus()
		return
	end

	local ok, result = self:_invokeAdminRequest(tabId, actionId, string.format("Sending %s", actionTitle), {})
	if not ok or not result then
		return
	end

	self:_handlePostAdminAction(tabId, actionId, result)

	local message = tostring(result.message or "No response message provided.")
	self:_setStatus(message, if result.ok then SUCCESS_COLOR else ERROR_COLOR)
end

function AdminPanelController:_styleSandboxButton(button: GuiButton, callback: () -> ())
	button.AutoButtonColor = false
	button.BackgroundColor3 = SANDBOX_BUTTON_COLOR
	button.BackgroundTransparency = 0
	button.BorderSizePixel = 0
	button.TextColor3 = SANDBOX_BUTTON_TEXT_COLOR
	button.Font = Enum.Font.GothamSemibold
	button.TextSize = 13

	local corner = Instance.new("UICorner")
	corner.CornerRadius = COMPACT_CORNER_RADIUS
	corner.Parent = button
	setGenerated(corner)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(78, 91, 124)
	stroke.Transparency = 0.32
	stroke.Thickness = 1
	stroke.Parent = button
	setGenerated(stroke)

	UIController:CreateButton(button, callback)
end

function AdminPanelController:_createSandboxButton(parent: Instance, name: string, text: string, size: UDim2, callback: () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.new(size.X.Scale, size.X.Offset, size.Y.Scale, compactHeight(size.Y.Offset))
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
	corner.CornerRadius = COMPACT_CORNER_RADIUS
	corner.Parent = field
	setGenerated(corner)

	local stroke = Instance.new("UIStroke")
	stroke.Color = SANDBOX_STROKE_COLOR
	stroke.Transparency = 0.42
	stroke.Thickness = 1
	stroke.Parent = field
	setGenerated(stroke)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
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
	label.Size = UDim2.new(1, 0, 0, 16)
	label.Font = Enum.Font.GothamBold
	label.Text = labelText
	label.TextColor3 = Color3.fromRGB(218, 226, 246)
	label.TextSize = 13
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
	valueLabel.TextColor3 = Color3.fromRGB(232, 237, 250)
	valueLabel.TextSize = 13
	valueLabel.TextWrapped = true
	valueLabel.TextXAlignment = Enum.TextXAlignment.Left
	valueLabel.TextYAlignment = Enum.TextYAlignment.Top
	valueLabel.Parent = parent
	setGenerated(valueLabel)

	return valueLabel
end

function AdminPanelController:_createSandboxTextInput(
	parent: Instance,
	name: string,
	initialText: string,
	placeholderText: string,
	height: number,
	isMultiLine: boolean?
): TextBox
	local input = Instance.new("TextBox")
	input.Name = name
	input.BackgroundColor3 = Color3.fromRGB(11, 14, 23)
	input.BorderSizePixel = 0
	input.ClearTextOnFocus = false
	input.MultiLine = isMultiLine == true
	input.PlaceholderText = placeholderText
	input.Size = UDim2.new(1, 0, 0, compactHeight(height))
	input.Font = Enum.Font.GothamSemibold
	input.Text = initialText
	input.TextColor3 = Color3.fromRGB(245, 248, 255)
	input.TextSize = if isMultiLine == true then 13 else 14
	input.TextWrapped = isMultiLine == true
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.TextYAlignment = if isMultiLine == true then Enum.TextYAlignment.Top else Enum.TextYAlignment.Center
	input.Parent = parent
	setGenerated(input)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = COMPACT_CORNER_RADIUS
	corner.Parent = input
	setGenerated(corner)

	local stroke = Instance.new("UIStroke")
	stroke.Color = SANDBOX_STROKE_COLOR
	stroke.Transparency = 0.34
	stroke.Thickness = 1
	stroke.Parent = input
	setGenerated(stroke)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, if isMultiLine == true then 10 else 0)
	padding.PaddingBottom = UDim.new(0, if isMultiLine == true then 10 else 0)
	padding.Parent = input
	setGenerated(padding)

	return input
end

function AdminPanelController:_getSelectedAdminTargetUserId(): number
	local selectedPlayer = select(1, self:_getSelectedPlayerStatsTarget())
	if selectedPlayer then
		return selectedPlayer.UserId
	end

	return LOCAL_PLAYER.UserId
end

function AdminPanelController:_resolveActionFieldDefault(field: any): string
	local defaultValue = field and field.defaultValue
	if defaultValue == "$selectedPlayerUserId" then
		return tostring(self:_getSelectedAdminTargetUserId())
	end
	if defaultValue == "$localPlayerUserId" then
		return tostring(LOCAL_PLAYER.UserId)
	end
	if defaultValue == nil then
		return ""
	end
	return tostring(defaultValue)
end

function AdminPanelController:_collectActionPayload(actionKey: string, action: any): any
	local payload = {}
	local inputs = self._actionFormInputs[actionKey] or {}

	for _, field in ipairs(action.fields or {}) do
		local input = inputs[field.id]
		local rawValue = if input and input:IsA("TextBox") then input.Text else self:_resolveActionFieldDefault(field)
		local trimmedValue = trimText(rawValue)

		if field.kind == "number" then
			if trimmedValue ~= "" then
				payload[field.id] = tonumber(trimmedValue)
			end
		elseif field.kind == "boolean" then
			local lowered = string.lower(trimmedValue)
			payload[field.id] = lowered == "true" or lowered == "yes" or lowered == "1" or lowered == "on"
		elseif field.kind == "player" then
			local resolvedUserId = tonumber(trimmedValue)
			payload[field.id] = if resolvedUserId then math.floor(resolvedUserId) else self:_getSelectedAdminTargetUserId()
		else
			payload[field.id] = trimmedValue
		end
	end

	return payload
end

function AdminPanelController:_createActionFormCard(parent: Instance, tabId: string, action: any)
	local card = Instance.new("Frame")
	card.Name = string.format("%sFormCard", action.id)
	card.Parent = parent
	setGenerated(card)
	self:_styleCompactCard(card, action.risk)

	local title = Instance.new("TextLabel")
	title.Name = "TitleLabel"
	title.BackgroundTransparency = 1
	title.AutomaticSize = Enum.AutomaticSize.Y
	title.Size = UDim2.new(1, 0, 0, 0)
	title.Font = Enum.Font.GothamBold
	title.Text = action.title
	title.TextColor3 = Color3.fromRGB(247, 249, 255)
	title.TextSize = 15
	title.TextWrapped = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.LayoutOrder = 1
	title.Parent = card
	setGenerated(title)

	local badge = Instance.new("TextLabel")
	badge.Name = "RiskBadge"
	badge.BackgroundColor3 = getRiskBadgeColor(action)
	badge.BackgroundTransparency = 0.82
	badge.BorderSizePixel = 0
	badge.AutomaticSize = Enum.AutomaticSize.XY
	badge.Size = UDim2.fromOffset(0, 20)
	badge.Font = Enum.Font.GothamBold
	badge.Text = getRiskBadgeText(action)
	badge.TextColor3 = getRiskBadgeColor(action)
	badge.TextSize = 11
	badge.TextXAlignment = Enum.TextXAlignment.Left
	badge.LayoutOrder = 2
	badge.Parent = card
	setGenerated(badge)

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 5)
	badgeCorner.Parent = badge
	setGenerated(badgeCorner)

	local badgePadding = Instance.new("UIPadding")
	badgePadding.PaddingLeft = UDim.new(0, 7)
	badgePadding.PaddingRight = UDim.new(0, 7)
	badgePadding.PaddingTop = UDim.new(0, 2)
	badgePadding.PaddingBottom = UDim.new(0, 2)
	badgePadding.Parent = badge
	setGenerated(badgePadding)

	local description = Instance.new("TextLabel")
	description.Name = "DescriptionLabel"
	description.BackgroundTransparency = 1
	description.Visible = false
	description.AutomaticSize = Enum.AutomaticSize.Y
	description.Size = UDim2.new(1, 0, 0, 0)
	description.Font = Enum.Font.Gotham
	description.Text = action.description
	description.TextColor3 = Color3.fromRGB(184, 196, 227)
	description.TextSize = 13
	description.TextWrapped = true
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.LayoutOrder = 3
	description.Parent = card
	setGenerated(description)

	local actionKey = string.format("%s:%s", tabId, action.id)
	self._actionFormInputs[actionKey] = {}

	for fieldIndex, field in ipairs(action.fields or {}) do
		local fieldContainer = self:_createSandboxField(card, field.label or field.id)
		fieldContainer.LayoutOrder = fieldIndex + 3
		local input = self:_createSandboxTextInput(
			fieldContainer,
			string.format("%sInput", tostring(field.id)),
			self:_resolveActionFieldDefault(field),
			tostring(field.placeholder or ""),
			38,
			field.multiline == true
		)
		self._actionFormInputs[actionKey][field.id] = input
	end

	local buttonText = if action.risk == "destructive" then "Run Destructive Action" else "Run Action"
	local runButton = self:_createSandboxButton(card, "RunButton", buttonText, UDim2.new(1, 0, 0, 40), function()
		local payload = self:_collectActionPayload(actionKey, action)
		local ok, result = self:_invokeAdminRequest(tabId, action.id, string.format("Running %s", action.title), payload)
		if not ok or not result then
			return
		end

		self:_handlePostAdminAction(tabId, action.id, result)
		self:_setStatus(tostring(result.message or "No response message provided."), if result.ok then SUCCESS_COLOR else ERROR_COLOR)
	end)
	runButton.LayoutOrder = 100
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

function AdminPanelController:_repairSelectedPlayerVipPlus(): boolean
	local selectedPlayer = select(1, self:_getSelectedPlayerStatsTarget())
	if not selectedPlayer then
		self:_setStatus("No players are currently available to repair.", ERROR_COLOR)
		return false
	end

	local ok, result = self:_invokeAdminRequest(PLAYERS_TAB_ID, "repair_marketplace_entitlement", "Repairing VIP+", {
		userId = selectedPlayer.UserId,
		offerKey = "vip_plus",
		reason = "admin_panel_vip_plus_repair",
	})
	if not ok or not result then
		return false
	end

	self:_setStatus(tostring(result.message or "Marketplace entitlement repair completed."), if result.ok then SUCCESS_COLOR else ERROR_COLOR)
	if result.ok == true then
		self:_loadSelectedPlayerStats(true)
	end

	return result.ok == true
end

function AdminPanelController:_getNotificationTargets(): { [number]: any }
	local targets = {
		{
			key = "self",
			targetKind = "self",
			title = "Only Me",
			description = "Send the notification only to your admin client.",
		},
		{
			key = "all",
			targetKind = "all",
			title = "All Players",
			description = string.format("Broadcast the notification to every connected player (%d online).", #Players:GetPlayers()),
		},
	}

	for _, player in ipairs(self:_getPlayerStatsTargets()) do
		if player ~= LOCAL_PLAYER then
			table.insert(targets, {
				key = string.format("player:%d", player.UserId),
				targetKind = "player",
				userId = player.UserId,
				title = formatPlayerDisplay(player),
				description = "Send the notification to one connected player.",
			})
		end
	end

	return targets
end

function AdminPanelController:_getSelectedNotificationTarget(): (any?, { [number]: any })
	local targets = self:_getNotificationTargets()
	if #targets == 0 then
		self._notificationTargetKey = "self"
		return nil, targets
	end

	for _, target in ipairs(targets) do
		if target.key == self._notificationTargetKey then
			return target, targets
		end
	end

	self._notificationTargetKey = targets[1].key
	return targets[1], targets
end

function AdminPanelController:_cycleNotificationTarget(direction: number)
	local selectedTarget, targets = self:_getSelectedNotificationTarget()
	if #targets == 0 then
		self:_syncNotificationUi()
		return
	end

	local currentIndex = 1
	for index, target in ipairs(targets) do
		if selectedTarget and target.key == selectedTarget.key then
			currentIndex = index
			break
		end
	end

	local nextIndex = ((currentIndex - 1 + direction) % #targets) + 1
	self._notificationTargetKey = targets[nextIndex].key
	self:_syncNotificationUi()
end

function AdminPanelController:_getNotificationDuration(): number?
	local ui = self._notificationUi
	if ui.durationInput and ui.durationInput:IsA("TextBox") then
		self._notificationDurationText = ui.durationInput.Text
	end

	local duration = tonumber(self._notificationDurationText)
	if duration == nil or duration ~= duration then
		return nil
	end

	if duration < NOTIFICATION_MIN_DURATION or duration > NOTIFICATION_MAX_DURATION then
		return nil
	end

	return duration
end

function AdminPanelController:_syncNotificationUi()
	local ui = self._notificationUi
	if not ui or next(ui) == nil then
		return
	end

	local selectedTarget, targets = self:_getSelectedNotificationTarget()

	if ui.targetValue and ui.targetValue:IsA("TextLabel") then
		if selectedTarget then
			ui.targetValue.Text = string.format("%s\n%s", selectedTarget.title, selectedTarget.description)
		else
			ui.targetValue.Text = "No notification target is available."
		end
	end

	if ui.messageInput and ui.messageInput:IsA("TextBox") and not ui.messageInput:IsFocused() then
		ui.messageInput.Text = self._notificationMessageText
	end

	if ui.durationInput and ui.durationInput:IsA("TextBox") and not ui.durationInput:IsFocused() then
		ui.durationInput.Text = self._notificationDurationText
	end

	setSandboxButtonEnabled(ui.targetPrevButton, #targets > 1)
	setSandboxButtonEnabled(ui.targetNextButton, #targets > 1)
	setSandboxButtonEnabled(ui.sendButton, selectedTarget ~= nil and trimText(self._notificationMessageText) ~= "")
end

function AdminPanelController:_sendNotification()
	local ui = self._notificationUi
	if ui.messageInput and ui.messageInput:IsA("TextBox") then
		self._notificationMessageText = ui.messageInput.Text
	end

	local target = select(1, self:_getSelectedNotificationTarget())
	if not target then
		self:_setStatus("No notification target is currently available.", ERROR_COLOR)
		return
	end

	local text = trimText(self._notificationMessageText)
	if text == "" then
		self:_setStatus("Enter notification text before sending.", ERROR_COLOR)
		self:_syncNotificationUi()
		return
	end

	local duration = self:_getNotificationDuration()
	if not duration then
		self:_setStatus(
			string.format("Notification duration must be between %d and %d seconds.", NOTIFICATION_MIN_DURATION, NOTIFICATION_MAX_DURATION),
			ERROR_COLOR
		)
		return
	end

	local ok, result = self:_invokeAdminRequest(OVERVIEW_TAB_ID, "send_notification", "Sending notification", {
		targetKind = target.targetKind,
		userId = target.userId,
		text = text,
		duration = duration,
	})
	if not ok or not result then
		return
	end

	self:_setStatus(tostring(result.message or "No response message provided."), if result.ok then SUCCESS_COLOR else ERROR_COLOR)
end

function AdminPanelController:_createNotificationSection(parent: ScrollingFrame)
	self:_createSectionHeader(parent, "Notifications", "Compose a live notification and send it to yourself, one connected player, or the entire server using the same shared notification system the game already uses.")

	local card = Instance.new("Frame")
	card.Name = "NotificationsCard"
	card.BackgroundColor3 = SANDBOX_CARD_COLOR
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Size = UDim2.new(1, -4, 0, 0)
	card.Parent = parent
	setGenerated(card)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = COMPACT_CORNER_RADIUS
	corner.Parent = card
	setGenerated(corner)

	local stroke = Instance.new("UIStroke")
	stroke.Color = SANDBOX_STROKE_COLOR
	stroke.Transparency = 0.14
	stroke.Parent = card
	setGenerated(stroke)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = card
	setGenerated(padding)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Padding = UDim.new(0, 8)
	layout.Parent = card
	setGenerated(layout)

	local description = Instance.new("TextLabel")
	description.Name = "DescriptionLabel"
	description.BackgroundTransparency = 1
	description.Size = UDim2.new(1, 0, 0, 34)
	description.AutomaticSize = Enum.AutomaticSize.Y
	description.Font = Enum.Font.Gotham
	description.Text = "This sends the same in-game toast used by unlocks, receipts, and shared admin notices. Toasts show the message only and use the admin notification color."
	description.TextWrapped = true
	description.TextSize = 13
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.TextColor3 = Color3.fromRGB(184, 196, 227)
	description.Parent = card
	setGenerated(description)

	local targetField = self:_createSandboxField(card, "Target")
	local targetRow = Instance.new("Frame")
	targetRow.Name = "ValueRow"
	targetRow.BackgroundTransparency = 1
	targetRow.Size = UDim2.new(1, 0, 0, 70)
	targetRow.Parent = targetField
	setGenerated(targetRow)

	local targetPrevButton = self:_createSandboxButton(targetRow, "PrevButton", "<", UDim2.fromOffset(38, 36), function()
		self:_cycleNotificationTarget(-1)
	end)

	local targetValue = Instance.new("TextLabel")
	targetValue.Name = "ValueLabel"
	targetValue.BackgroundTransparency = 1
	targetValue.Position = UDim2.fromOffset(48, 0)
	targetValue.Size = UDim2.new(1, -96, 1, 0)
	targetValue.Font = Enum.Font.GothamSemibold
	targetValue.TextColor3 = Color3.fromRGB(244, 247, 255)
	targetValue.TextSize = 13
	targetValue.TextWrapped = true
	targetValue.TextXAlignment = Enum.TextXAlignment.Left
	targetValue.TextYAlignment = Enum.TextYAlignment.Top
	targetValue.Parent = targetRow
	setGenerated(targetValue)

	local targetNextButton = self:_createSandboxButton(targetRow, "NextButton", ">", UDim2.fromOffset(38, 36), function()
		self:_cycleNotificationTarget(1)
	end)
	targetNextButton.Position = UDim2.new(1, -38, 0, 0)

	local messageField = self:_createSandboxField(card, "Message")
	local messageInput = self:_createSandboxTextInput(
		messageField,
		"MessageInput",
		self._notificationMessageText,
		"Type the notification text here.",
		96,
		true
	)
	messageInput.FocusLost:Connect(function()
		self._notificationMessageText = messageInput.Text
		self:_syncNotificationUi()
	end)
	messageInput:GetPropertyChangedSignal("Text"):Connect(function()
		self._notificationMessageText = messageInput.Text
		self:_syncNotificationUi()
	end)

	local durationField = self:_createSandboxField(card, "Duration (Seconds)")
	local durationInput = self:_createSandboxTextInput(
		durationField,
		"DurationInput",
		self._notificationDurationText,
		NOTIFICATION_DEFAULT_DURATION,
		38
	)
	durationInput.FocusLost:Connect(function()
		self._notificationDurationText = durationInput.Text
		self:_syncNotificationUi()
	end)
	durationInput:GetPropertyChangedSignal("Text"):Connect(function()
		self._notificationDurationText = durationInput.Text
	end)

	local sendButton = self:_createSandboxButton(card, "SendButton", "Send Notification", UDim2.new(1, 0, 0, 40), function()
		self:_sendNotification()
	end)

	self._notificationUi = {
		targetPrevButton = targetPrevButton,
		targetNextButton = targetNextButton,
		targetValue = targetValue,
		messageInput = messageInput,
		durationInput = durationInput,
		sendButton = sendButton,
	}

	self:_syncNotificationUi()
end

function AdminPanelController:_syncLuckOverrideUi()
	local ui = self._luckOverrideUi
	if not ui or next(ui) == nil then
		return
	end

	local state = self._luckOverrideState
	local hasOverride = typeof(state) == "table" and state.hasOverride == true
	local overrideLuck = if hasOverride then tonumber(state.overrideLuck) else nil
	local effectiveLuck = if typeof(state) == "table" then tonumber(state.effectiveLuck) else nil
	local computedLuck = if typeof(state) == "table" then tonumber(state.computedLuckWithoutOverride) else nil

	if ui.overrideInput and ui.overrideInput:IsA("TextBox") and not ui.overrideInput:IsFocused() then
		ui.overrideInput.Text = self._luckOverrideInputText
	end

	if ui.currentValue and ui.currentValue:IsA("TextLabel") then
		local lines = {
			string.format("Current Effective Luck: %s", formatLuckMultiplier(effectiveLuck)),
			string.format(
				"Admin Override: %s",
				if hasOverride and overrideLuck ~= nil then formatLuckMultiplier(overrideLuck) else "Off"
			),
			string.format(
				"Computed Luck Without Override: %s",
				formatLuckMultiplier(computedLuck)
			),
		}
		ui.currentValue.Text = table.concat(lines, "\n")
	end

	if ui.breakdownValue and ui.breakdownValue:IsA("TextLabel") then
		local rollTypeName = if typeof(state) == "table" and typeof(state.rollTypeDisplayName) == "string" and state.rollTypeDisplayName ~= ""
			then state.rollTypeDisplayName
			else "Unknown"
		local lines = {
			string.format("Roll Type: %s", rollTypeName),
			string.format("Base Luck: %s", formatLuckMultiplier(if typeof(state) == "table" then tonumber(state.baseLuck) else nil)),
			string.format("Bonus Roll Luck: %s", formatLuckMultiplier(if typeof(state) == "table" then tonumber(state.bonusLuck) else nil)),
			string.format("Potion Luck: %s", formatLuckMultiplier(if typeof(state) == "table" then tonumber(state.potionLuck) else nil)),
			string.format("VIP Luck: %s", formatLuckMultiplier(if typeof(state) == "table" then tonumber(state.vipLuck) else nil)),
			string.format(
				"Equipped Luck Multiplier: %s",
				formatLuckMultiplier(if typeof(state) == "table" then tonumber(state.equippedLuckMultiplier) else nil)
			),
			string.format(
				"Potion Luck Bonus: %s",
				formatSignedPercent(if typeof(state) == "table" then tonumber(state.potionLuckBonus) or 0 else 0)
			),
			string.format(
				"Potion Luck Multiplier: %s",
				formatLuckMultiplier(if typeof(state) == "table" then tonumber(state.potionLuckMultiplier) else nil)
			),
			string.format(
				"Pity Roll Ready: %s",
				if typeof(state) == "table" and state.useBonusRoll == true then "Yes" else "No"
			),
			string.format(
				"VIP Owned: %s",
				if typeof(state) == "table" and state.isVipOwned == true then "Yes" else "No"
			),
		}
		ui.breakdownValue.Text = table.concat(lines, "\n")
	end

	local trimmedInput = trimText(self._luckOverrideInputText)
	local parsedInput = tonumber(trimmedInput)
	local canApply = trimmedInput ~= "" and parsedInput ~= nil and parsedInput == parsedInput

	setSandboxButtonEnabled(ui.refreshButton, true)
	setSandboxButtonEnabled(ui.applyButton, canApply)
	setSandboxButtonEnabled(ui.clearButton, hasOverride)
end

function AdminPanelController:_loadLuckOverrideState(forceRefresh: boolean?): boolean
	if not forceRefresh and self._luckOverrideState ~= nil then
		self:_syncLuckOverrideUi()
		return true
	end

	local ok, result = self:_invokeAdminRequest(PROGRESSION_TAB_ID, "get_luck_override", "Loading current luck override", {})
	if not ok or not result then
		self._luckOverrideState = nil
		self:_syncLuckOverrideUi()
		return false
	end

	if result.ok ~= true or typeof(result.data) ~= "table" then
		self._luckOverrideState = nil
		self:_syncLuckOverrideUi()
		self:_setStatus(tostring(result.message or "Failed to load the current luck override."), ERROR_COLOR)
		return false
	end

	self._luckOverrideState = result.data
	if result.data.hasOverride == true then
		self._luckOverrideInputText = formatNumberish(tonumber(result.data.overrideLuck) or 0)
	elseif trimText(self._luckOverrideInputText) == "" then
		self._luckOverrideInputText = ""
	end

	self:_syncLuckOverrideUi()
	self:_setStatus(tostring(result.message or "Loaded current luck override."), SUCCESS_COLOR)
	return true
end

function AdminPanelController:_applyLuckOverride()
	local ui = self._luckOverrideUi
	if ui.overrideInput and ui.overrideInput:IsA("TextBox") then
		self._luckOverrideInputText = ui.overrideInput.Text
	end

	local rawText = trimText(self._luckOverrideInputText)
	local totalLuck = tonumber(rawText)
	if rawText == "" or totalLuck == nil or totalLuck ~= totalLuck then
		self:_setStatus("Enter a numeric total luck value before applying the override.", ERROR_COLOR)
		self:_syncLuckOverrideUi()
		return
	end

	local ok, result = self:_invokeAdminRequest(PROGRESSION_TAB_ID, "set_luck_override", "Applying luck override", {
		totalLuck = totalLuck,
	})
	if not ok or not result then
		return
	end

	if result.ok == true and typeof(result.data) == "table" then
		self._luckOverrideState = result.data
		if result.data.hasOverride == true then
			self._luckOverrideInputText = formatNumberish(tonumber(result.data.overrideLuck) or totalLuck)
		end
	end

	self:_syncLuckOverrideUi()
	self:_setStatus(tostring(result.message or "No response message provided."), if result.ok then SUCCESS_COLOR else ERROR_COLOR)
end

function AdminPanelController:_clearLuckOverride()
	local ok, result = self:_invokeAdminRequest(PROGRESSION_TAB_ID, "clear_luck_override", "Clearing luck override", {})
	if not ok or not result then
		return
	end

	if result.ok == true and typeof(result.data) == "table" then
		self._luckOverrideState = result.data
		self._luckOverrideInputText = ""
	end

	self:_syncLuckOverrideUi()
	self:_setStatus(tostring(result.message or "No response message provided."), if result.ok then SUCCESS_COLOR else ERROR_COLOR)
end

function AdminPanelController:_createLuckOverrideSection(parent: ScrollingFrame)
	self:_createSectionHeader(parent, "Luck Override", "Set an admin-only total luck override for your own rolls. This replaces the final effective luck used by the roll table after equipment, potions, pity, and VIP are applied.")

	local card = Instance.new("Frame")
	card.Name = "LuckOverrideCard"
	card.BackgroundColor3 = SANDBOX_CARD_COLOR
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Size = UDim2.new(1, -4, 0, 0)
	card.Parent = parent
	setGenerated(card)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = COMPACT_CORNER_RADIUS
	corner.Parent = card
	setGenerated(corner)

	local stroke = Instance.new("UIStroke")
	stroke.Color = SANDBOX_STROKE_COLOR
	stroke.Transparency = 0.14
	stroke.Parent = card
	setGenerated(stroke)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = card
	setGenerated(padding)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Padding = UDim.new(0, 8)
	layout.Parent = card
	setGenerated(layout)

	local description = Instance.new("TextLabel")
	description.Name = "DescriptionLabel"
	description.BackgroundTransparency = 1
	description.Size = UDim2.new(1, 0, 0, 34)
	description.AutomaticSize = Enum.AutomaticSize.Y
	description.Font = Enum.Font.Gotham
	description.Text = "Use whole numbers or decimals like 25 or 25.5. Leaving the override off returns your luck to the normal machine, gear, potion, pity, and VIP calculation."
	description.TextWrapped = true
	description.TextSize = 13
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.TextColor3 = Color3.fromRGB(184, 196, 227)
	description.Parent = card
	setGenerated(description)

	local currentField = self:_createSandboxField(card, "Current State")
	local currentValue = self:_createSandboxValueLabel(currentField)

	local breakdownField = self:_createSandboxField(card, "Breakdown")
	local breakdownValue = self:_createSandboxValueLabel(breakdownField)

	local overrideField = self:_createSandboxField(card, "Override Total Luck")
	local overrideInput = self:_createSandboxTextInput(
		overrideField,
		"OverrideInput",
		self._luckOverrideInputText,
		"Example: 50",
		38
	)
	overrideInput.FocusLost:Connect(function()
		self._luckOverrideInputText = overrideInput.Text
		self:_syncLuckOverrideUi()
	end)
	overrideInput:GetPropertyChangedSignal("Text"):Connect(function()
		self._luckOverrideInputText = overrideInput.Text
		self:_syncLuckOverrideUi()
	end)

	local actionRow = Instance.new("Frame")
	actionRow.Name = "ActionRow"
	actionRow.BackgroundTransparency = 1
	actionRow.AutomaticSize = Enum.AutomaticSize.Y
	actionRow.Size = UDim2.new(1, 0, 0, 0)
	actionRow.Parent = card
	setGenerated(actionRow)

	local actionLayout = Instance.new("UIGridLayout")
	actionLayout.CellPadding = UDim2.fromOffset(8, 8)
	actionLayout.CellSize = UDim2.new(1 / 3, -7, 0, 40)
	actionLayout.FillDirectionMaxCells = 3
	actionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	actionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	actionLayout.Parent = actionRow
	setGenerated(actionLayout)

	local refreshButton = self:_createSandboxButton(actionRow, "RefreshButton", "Refresh", UDim2.new(0, 0, 0, 40), function()
		self:_loadLuckOverrideState(true)
	end)

	local applyButton = self:_createSandboxButton(actionRow, "ApplyButton", "Apply Override", UDim2.new(0, 0, 0, 40), function()
		self:_applyLuckOverride()
	end)

	local clearButton = self:_createSandboxButton(actionRow, "ClearButton", "Clear Override", UDim2.new(0, 0, 0, 40), function()
		self:_clearLuckOverride()
	end)

	self._luckOverrideUi = {
		currentValue = currentValue,
		breakdownValue = breakdownValue,
		overrideInput = overrideInput,
		refreshButton = refreshButton,
		applyButton = applyButton,
		clearButton = clearButton,
	}

	self:_syncLuckOverrideUi()
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

function AdminPanelController:_getGrantAccessoryOptions(slot: string)
	local accessories = {}

	for _, accessoryConfig in ipairs(AccessoryConfig.GetAll()) do
		if accessoryConfig.slot == slot then
			table.insert(accessories, accessoryConfig)
		end
	end

	return accessories
end

function AdminPanelController:_getGrantCraftingMaterialOptions()
	local materials = {}

	for _, materialConfig in ipairs(CraftingMaterialConfig.GetAll()) do
		table.insert(materials, materialConfig)
	end

	return materials
end

function AdminPanelController:_findGrantOption(options: { any }, query: string, getSearchText: (any) -> string): any?
	if #options == 0 then
		return nil
	end

	local normalizedQuery = normalizeSearchText(query)
	if normalizedQuery == "" then
		return options[1]
	end

	for _, option in ipairs(options) do
		if normalizeSearchText(option.id) == normalizedQuery then
			return option
		end
	end

	for _, option in ipairs(options) do
		if string.find(normalizeSearchText(getSearchText(option)), normalizedQuery, 1, true) then
			return option
		end
	end

	return nil
end

function AdminPanelController:_selectGrantBodyPartByQuery(query: string)
	local piece = self:_findGrantOption(self:_getGrantBodyPartOptions(), query, function(option)
		local setConfig = BodyPartsCatalog.GetSetForPiece(option.id)
		return table.concat({
			option.id,
			option.displayName or "",
			option.region or "",
			if setConfig then setConfig.displayName else "",
			if setConfig then setConfig.rollDisplay.rarity else "",
		}, " ")
	end)

	if not piece then
		self:_setStatus("No body part matched that search.", ERROR_COLOR)
		return
	end

	self._grantSelectedPieceId = piece.id
	self:_syncGrantUi()
end

function AdminPanelController:_selectGrantAuraByQuery(query: string)
	local auraConfig = self:_findGrantOption(self:_getGrantAuraOptions(), query, function(option)
		return table.concat({ option.id, option.label or "", option.setId or "", option.tierLabel or "" }, " ")
	end)

	if not auraConfig then
		self:_setStatus("No aura matched that search.", ERROR_COLOR)
		return
	end

	self._grantSelectedAuraId = auraConfig.id
	self:_syncGrantUi()
end

function AdminPanelController:_selectGrantAccessoryByQuery(slot: string, query: string)
	local accessoryConfig = self:_findGrantOption(self:_getGrantAccessoryOptions(slot), query, function(option)
		return table.concat({ option.id, option.label or "", option.tierLabel or "", option.bossId or "" }, " ")
	end)

	if not accessoryConfig then
		self:_setStatus("No accessory matched that search.", ERROR_COLOR)
		return
	end

	self:_setSelectedGrantAccessoryId(slot, accessoryConfig.id)
	self:_syncGrantUi()
end

function AdminPanelController:_selectGrantCraftingMaterialByQuery(query: string)
	local materialConfig = self:_findGrantOption(self:_getGrantCraftingMaterialOptions(), query, function(option)
		return table.concat({ option.id, option.label or "", option.description or "" }, " ")
	end)

	if not materialConfig then
		self:_setStatus("No material matched that search.", ERROR_COLOR)
		return
	end

	self._grantSelectedCraftingMaterialId = materialConfig.id
	self:_syncGrantUi()
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

function AdminPanelController:_getSelectedGrantCraftingMaterial()
	local selectedMaterialId = self._grantSelectedCraftingMaterialId
	for _, materialConfig in ipairs(self:_getGrantCraftingMaterialOptions()) do
		if materialConfig.id == selectedMaterialId then
			return materialConfig
		end
	end

	return nil
end

function AdminPanelController:_getSelectedGrantAccessoryId(slot: string): string?
	if slot == HEAD_ACCESSORY_SLOT then
		return self._grantSelectedHeadAccessoryId
	end
	if slot == GEAR_ACCESSORY_SLOT then
		return self._grantSelectedGearAccessoryId
	end

	return nil
end

function AdminPanelController:_setSelectedGrantAccessoryId(slot: string, accessoryId: string?)
	if slot == HEAD_ACCESSORY_SLOT then
		self._grantSelectedHeadAccessoryId = accessoryId
	elseif slot == GEAR_ACCESSORY_SLOT then
		self._grantSelectedGearAccessoryId = accessoryId
	end
end

function AdminPanelController:_getSelectedGrantAccessory(slot: string)
	local selectedAccessoryId = self:_getSelectedGrantAccessoryId(slot)
	for _, accessoryConfig in ipairs(self:_getGrantAccessoryOptions(slot)) do
		if accessoryConfig.id == selectedAccessoryId then
			return accessoryConfig
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

local function formatAccessoryBonusSummary(accessoryConfig: any): string
	local bonuses = if typeof(accessoryConfig.bonuses) == "table" then accessoryConfig.bonuses else {}
	local parts = {}

	local function addPercent(key: string, label: string)
		local value = tonumber(bonuses[key])
		if value and math.abs(value) > 0.0001 then
			table.insert(parts, string.format("%s %s", label, formatSignedPercent(value)))
		end
	end

	local function addMultiplier(key: string, label: string)
		local value = tonumber(bonuses[key])
		if value and math.abs(value - 1) > 0.0001 then
			table.insert(parts, string.format("%s x%s", label, formatNumberish(value)))
		end
	end

	local function addFlat(key: string, label: string)
		local value = tonumber(bonuses[key])
		if value and math.abs(value) > 0.0001 then
			table.insert(parts, string.format("%s +%s", label, formatNumberish(value)))
		end
	end

	addPercent("luckBonus", "Luck")
	addMultiplier("luckMultiplier", "Luck")
	addPercent("rollSpeedBonus", "Roll Speed")
	addFlat("passiveIncomePerSecondBonus", "Income / s")
	addMultiplier("passiveIncomeMultiplier", "Income")
	addFlat("damageBonus", "Damage")
	addMultiplier("damageMultiplier", "Damage")
	addFlat("healthBonus", "Health")
	addMultiplier("healthMultiplier", "Health")
	addFlat("speedBonus", "Speed")
	addMultiplier("speedMultiplier", "Speed")

	if #parts == 0 then
		return "None"
	end

	return table.concat(parts, ", ")
end

function AdminPanelController:_formatGrantAccessory(accessoryConfig: any): string
	if not accessoryConfig then
		return "No accessories are available."
	end

	local source = if accessoryConfig.bossId and accessoryConfig.bossId ~= "" then accessoryConfig.bossId else "General"

	return table.concat({
		accessoryConfig.label,
		string.format("Accessory ID: %s", accessoryConfig.id),
		string.format("Tier: %s", accessoryConfig.tierLabel),
		string.format("Source: %s", source),
		string.format("Bonuses: %s", formatAccessoryBonusSummary(accessoryConfig)),
	}, "\n")
end

function AdminPanelController:_formatGrantCraftingMaterial(materialConfig: any): string
	if not materialConfig then
		return "No crafting materials are available."
	end

	return table.concat({
		materialConfig.label,
		string.format("Material ID: %s", materialConfig.id),
		materialConfig.description,
	}, "\n")
end

function AdminPanelController:_getGrantCraftingMaterialAmount(): number?
	local amount = tonumber(trimText(self._grantCraftingMaterialAmountText))
	if amount == nil or amount ~= amount then
		return nil
	end

	return math.max(1, math.floor(amount))
end

function AdminPanelController:_syncGrantUi()
	local ui = self._grantUi
	if not ui or next(ui) == nil then
		return
	end

	local bodyPartOptions = self:_getGrantBodyPartOptions()
	local auraOptions = self:_getGrantAuraOptions()
	local headAccessoryOptions = self:_getGrantAccessoryOptions(HEAD_ACCESSORY_SLOT)
	local gearAccessoryOptions = self:_getGrantAccessoryOptions(GEAR_ACCESSORY_SLOT)
	local craftingMaterialOptions = self:_getGrantCraftingMaterialOptions()
	local selectedPiece = self:_getSelectedGrantBodyPart()
	local selectedAura = self:_getSelectedGrantAura()
	local selectedHeadAccessory = self:_getSelectedGrantAccessory(HEAD_ACCESSORY_SLOT)
	local selectedGearAccessory = self:_getSelectedGrantAccessory(GEAR_ACCESSORY_SLOT)
	local selectedCraftingMaterial = self:_getSelectedGrantCraftingMaterial()

	if selectedPiece == nil and bodyPartOptions[1] then
		self._grantSelectedPieceId = bodyPartOptions[1].id
		selectedPiece = bodyPartOptions[1]
	end

	if selectedAura == nil and auraOptions[1] then
		self._grantSelectedAuraId = auraOptions[1].id
		selectedAura = auraOptions[1]
	end

	if selectedHeadAccessory == nil and headAccessoryOptions[1] then
		self._grantSelectedHeadAccessoryId = headAccessoryOptions[1].id
		selectedHeadAccessory = headAccessoryOptions[1]
	end

	if selectedGearAccessory == nil and gearAccessoryOptions[1] then
		self._grantSelectedGearAccessoryId = gearAccessoryOptions[1].id
		selectedGearAccessory = gearAccessoryOptions[1]
	end

	if selectedCraftingMaterial == nil and craftingMaterialOptions[1] then
		self._grantSelectedCraftingMaterialId = craftingMaterialOptions[1].id
		selectedCraftingMaterial = craftingMaterialOptions[1]
	end

	if ui.bodyPartValue and ui.bodyPartValue:IsA("TextLabel") then
		ui.bodyPartValue.Text = self:_formatGrantBodyPart(selectedPiece)
	end

	if ui.smartBodyPartValue and ui.smartBodyPartValue:IsA("TextLabel") then
		ui.smartBodyPartValue.Text = firstLine(self:_formatGrantBodyPart(selectedPiece))
	end
	if ui.smartBodyPartInput and ui.smartBodyPartInput:IsA("TextBox") and not ui.smartBodyPartInput:IsFocused() then
		ui.smartBodyPartInput.Text = if selectedPiece then selectedPiece.id else ""
	end

	if ui.headAccessoryValue and ui.headAccessoryValue:IsA("TextLabel") then
		ui.headAccessoryValue.Text = self:_formatGrantAccessory(selectedHeadAccessory)
	end

	if ui.smartHeadAccessoryValue and ui.smartHeadAccessoryValue:IsA("TextLabel") then
		ui.smartHeadAccessoryValue.Text = firstLine(self:_formatGrantAccessory(selectedHeadAccessory))
	end
	if ui.smartHeadAccessoryInput and ui.smartHeadAccessoryInput:IsA("TextBox") and not ui.smartHeadAccessoryInput:IsFocused() then
		ui.smartHeadAccessoryInput.Text = if selectedHeadAccessory then selectedHeadAccessory.id else ""
	end

	if ui.gearAccessoryValue and ui.gearAccessoryValue:IsA("TextLabel") then
		ui.gearAccessoryValue.Text = self:_formatGrantAccessory(selectedGearAccessory)
	end

	if ui.smartGearAccessoryValue and ui.smartGearAccessoryValue:IsA("TextLabel") then
		ui.smartGearAccessoryValue.Text = firstLine(self:_formatGrantAccessory(selectedGearAccessory))
	end
	if ui.smartGearAccessoryInput and ui.smartGearAccessoryInput:IsA("TextBox") and not ui.smartGearAccessoryInput:IsFocused() then
		ui.smartGearAccessoryInput.Text = if selectedGearAccessory then selectedGearAccessory.id else ""
	end

	if ui.craftingMaterialValue and ui.craftingMaterialValue:IsA("TextLabel") then
		ui.craftingMaterialValue.Text = self:_formatGrantCraftingMaterial(selectedCraftingMaterial)
	end

	if ui.smartCraftingMaterialValue and ui.smartCraftingMaterialValue:IsA("TextLabel") then
		ui.smartCraftingMaterialValue.Text = firstLine(self:_formatGrantCraftingMaterial(selectedCraftingMaterial))
	end
	if
		ui.smartCraftingMaterialInput
		and ui.smartCraftingMaterialInput:IsA("TextBox")
		and not ui.smartCraftingMaterialInput:IsFocused()
	then
		ui.smartCraftingMaterialInput.Text = if selectedCraftingMaterial then selectedCraftingMaterial.id else ""
	end

	if ui.craftingMaterialAmountInput and ui.craftingMaterialAmountInput:IsA("TextBox") and not ui.craftingMaterialAmountInput:IsFocused() then
		ui.craftingMaterialAmountInput.Text = self._grantCraftingMaterialAmountText
	end

	if ui.auraValue and ui.auraValue:IsA("TextLabel") then
		ui.auraValue.Text = self:_formatGrantAura(selectedAura)
	end

	if ui.smartAuraValue and ui.smartAuraValue:IsA("TextLabel") then
		ui.smartAuraValue.Text = firstLine(self:_formatGrantAura(selectedAura))
	end
	if ui.smartAuraInput and ui.smartAuraInput:IsA("TextBox") and not ui.smartAuraInput:IsFocused() then
		ui.smartAuraInput.Text = if selectedAura then selectedAura.id else ""
	end

	local hasBodyPartOptions = #bodyPartOptions > 0
	local hasAuraOptions = #auraOptions > 0
	local hasHeadAccessoryOptions = #headAccessoryOptions > 0
	local hasGearAccessoryOptions = #gearAccessoryOptions > 0
	local hasCraftingMaterialOptions = #craftingMaterialOptions > 0

	for _, button in ipairs({ ui.bodyPartPrevButton, ui.bodyPartNextButton, ui.grantBodyPartButton }) do
		setSandboxButtonEnabled(button, hasBodyPartOptions)
	end
	setSandboxButtonEnabled(ui.smartGrantBodyPartButton, hasBodyPartOptions)

	for _, button in ipairs({ ui.headAccessoryPrevButton, ui.headAccessoryNextButton, ui.grantHeadAccessoryButton }) do
		setSandboxButtonEnabled(button, hasHeadAccessoryOptions)
	end
	setSandboxButtonEnabled(ui.smartGrantHeadAccessoryButton, hasHeadAccessoryOptions)

	for _, button in ipairs({ ui.gearAccessoryPrevButton, ui.gearAccessoryNextButton, ui.grantGearAccessoryButton }) do
		setSandboxButtonEnabled(button, hasGearAccessoryOptions)
	end
	setSandboxButtonEnabled(ui.smartGrantGearAccessoryButton, hasGearAccessoryOptions)

	for _, button in ipairs({
		ui.craftingMaterialPrevButton,
		ui.craftingMaterialNextButton,
		ui.grantCraftingMaterialButton,
		ui.grantAllCraftingMaterialsButton,
	}) do
		setSandboxButtonEnabled(button, hasCraftingMaterialOptions)
	end
	setSandboxButtonEnabled(ui.smartGrantCraftingMaterialButton, hasCraftingMaterialOptions)
	setSandboxButtonEnabled(ui.smartGrantAllCraftingMaterialsButton, hasCraftingMaterialOptions)

	for _, button in ipairs({ ui.auraPrevButton, ui.auraNextButton, ui.grantAuraButton }) do
		setSandboxButtonEnabled(button, hasAuraOptions)
	end
	setSandboxButtonEnabled(ui.smartGrantAuraButton, hasAuraOptions)
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

function AdminPanelController:_cycleGrantAccessory(slot: string, direction: number)
	local options = self:_getGrantAccessoryOptions(slot)
	local slotLabel = if slot == HEAD_ACCESSORY_SLOT then "head accessories" else "gear accessories"
	if #options == 0 then
		self:_setSelectedGrantAccessoryId(slot, nil)
		self:_syncGrantUi()
		self:_setStatus(string.format("No %s are configured to grant.", slotLabel), ERROR_COLOR)
		return
	end

	local currentIndex = 1
	local selectedAccessoryId = self:_getSelectedGrantAccessoryId(slot)
	for index, accessoryConfig in ipairs(options) do
		if accessoryConfig.id == selectedAccessoryId then
			currentIndex = index
			break
		end
	end

	local nextIndex = ((currentIndex - 1 + direction) % #options) + 1
	self:_setSelectedGrantAccessoryId(slot, options[nextIndex].id)
	self:_syncGrantUi()
end

function AdminPanelController:_cycleGrantCraftingMaterial(direction: number)
	local options = self:_getGrantCraftingMaterialOptions()
	if #options == 0 then
		self._grantSelectedCraftingMaterialId = nil
		self:_syncGrantUi()
		self:_setStatus("No crafting materials are configured to grant.", ERROR_COLOR)
		return
	end

	local currentIndex = 1
	for index, materialConfig in ipairs(options) do
		if materialConfig.id == self._grantSelectedCraftingMaterialId then
			currentIndex = index
			break
		end
	end

	local nextIndex = ((currentIndex - 1 + direction) % #options) + 1
	self._grantSelectedCraftingMaterialId = options[nextIndex].id
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

function AdminPanelController:_grantSelectedAccessory(slot: string)
	local selectedAccessory = self:_getSelectedGrantAccessory(slot)
	local slotLabel = if slot == HEAD_ACCESSORY_SLOT then "head accessory" else "gear accessory"
	if not selectedAccessory then
		self:_setStatus(string.format("Select a %s to grant first.", slotLabel), ERROR_COLOR)
		return
	end

	local actionId = if slot == HEAD_ACCESSORY_SLOT then "grant_head_accessory" else "grant_gear_accessory"
	local ok, result = self:_invokeAdminRequest(BODY_PARTS_TAB_ID, actionId, string.format("Granting %s", slotLabel), {
		accessoryId = selectedAccessory.id,
	})
	if not ok or not result then
		return
	end

	self:_setStatus(tostring(result.message or "No response message provided."), if result.ok then SUCCESS_COLOR else ERROR_COLOR)
end

function AdminPanelController:_grantSelectedCraftingMaterial()
	local selectedMaterial = self:_getSelectedGrantCraftingMaterial()
	if not selectedMaterial then
		self:_setStatus("Select a crafting material to grant first.", ERROR_COLOR)
		return
	end

	local amount = self:_getGrantCraftingMaterialAmount()
	if not amount then
		self:_setStatus("Enter a valid material amount.", ERROR_COLOR)
		return
	end

	self._grantCraftingMaterialAmountText = tostring(amount)
	self:_syncGrantUi()

	local ok, result = self:_invokeAdminRequest(BODY_PARTS_TAB_ID, "grant_crafting_material", "Granting crafting material", {
		materialId = selectedMaterial.id,
		amount = amount,
	})
	if not ok or not result then
		return
	end

	self:_setStatus(tostring(result.message or "No response message provided."), if result.ok then SUCCESS_COLOR else ERROR_COLOR)
end

function AdminPanelController:_grantAllCraftingMaterials()
	local amount = self:_getGrantCraftingMaterialAmount()
	if not amount then
		self:_setStatus("Enter a valid material amount.", ERROR_COLOR)
		return
	end

	self._grantCraftingMaterialAmountText = tostring(amount)
	self:_syncGrantUi()

	local ok, result = self:_invokeAdminRequest(BODY_PARTS_TAB_ID, "grant_all_crafting_materials", "Granting crafting materials", {
		amount = amount,
	})
	if not ok or not result then
		return
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
	corner.CornerRadius = COMPACT_CORNER_RADIUS
	corner.Parent = card
	setGenerated(corner)

	local stroke = Instance.new("UIStroke")
	stroke.Color = SANDBOX_STROKE_COLOR
	stroke.Transparency = 0.14
	stroke.Parent = card
	setGenerated(stroke)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = card
	setGenerated(padding)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Padding = UDim.new(0, 8)
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
	description.TextSize = 13
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

function AdminPanelController:_createGrantSmartRow(
	parent: Instance,
	name: string,
	labelText: string,
	placeholderText: string,
	onSearch: (string) -> (),
	onGrant: () -> ()
): (TextBox, TextLabel, TextButton)
	local row = Instance.new("Frame")
	row.Name = name
	row.BackgroundColor3 = SANDBOX_FIELD_COLOR
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, 44)
	row.Parent = parent
	setGenerated(row)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = COMPACT_CORNER_RADIUS
	corner.Parent = row
	setGenerated(corner)

	local stroke = Instance.new("UIStroke")
	stroke.Color = SANDBOX_STROKE_COLOR
	stroke.Transparency = 0.46
	stroke.Thickness = 1
	stroke.Parent = row
	setGenerated(stroke)

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(10, 0)
	label.Size = UDim2.new(0, 130, 1, 0)
	label.Font = Enum.Font.GothamBold
	label.Text = labelText
	label.TextColor3 = Color3.fromRGB(218, 226, 246)
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = row
	setGenerated(label)

	local input = Instance.new("TextBox")
	input.Name = "SearchInput"
	input.BackgroundColor3 = Color3.fromRGB(11, 14, 23)
	input.BorderSizePixel = 0
	input.ClearTextOnFocus = false
	input.PlaceholderText = placeholderText
	input.Position = UDim2.fromOffset(142, 7)
	input.Size = UDim2.new(0.34, -10, 0, 30)
	input.Font = Enum.Font.GothamSemibold
	input.Text = ""
	input.TextColor3 = Color3.fromRGB(245, 248, 255)
	input.TextSize = 13
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.Parent = row
	setGenerated(input)

	local inputCorner = Instance.new("UICorner")
	inputCorner.CornerRadius = UDim.new(0, 5)
	inputCorner.Parent = input
	setGenerated(inputCorner)

	local inputPadding = Instance.new("UIPadding")
	inputPadding.PaddingLeft = UDim.new(0, 8)
	inputPadding.PaddingRight = UDim.new(0, 8)
	inputPadding.Parent = input
	setGenerated(inputPadding)

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = "ValueLabel"
	valueLabel.BackgroundTransparency = 1
	valueLabel.Position = UDim2.new(0.34, 146, 0, 0)
	valueLabel.Size = UDim2.new(0.66, -270, 1, 0)
	valueLabel.Font = Enum.Font.Gotham
	valueLabel.TextColor3 = Color3.fromRGB(186, 196, 222)
	valueLabel.TextSize = 12
	valueLabel.TextXAlignment = Enum.TextXAlignment.Left
	valueLabel.TextTruncate = Enum.TextTruncate.AtEnd
	valueLabel.Parent = row
	setGenerated(valueLabel)

	local grantButton = self:_createSandboxButton(row, "GrantButton", "Grant", UDim2.fromOffset(78, 30), onGrant)
	grantButton.AnchorPoint = Vector2.new(1, 0.5)
	grantButton.Position = UDim2.new(1, -8, 0.5, 0)

	input.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed or trimText(input.Text) ~= "" then
			onSearch(input.Text)
		end
	end)

	return input, valueLabel, grantButton
end

function AdminPanelController:_createGrantInventorySection(parent: ScrollingFrame)
	self:_createSectionHeader(parent, "Grant Inventory", "Grant selected body parts, accessories, or auras directly to your own account for testing without leaving the admin panel.")

	local card = Instance.new("Frame")
	card.Name = "GrantInventoryCard"
	card.BackgroundColor3 = SANDBOX_CARD_COLOR
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Size = UDim2.new(1, -4, 0, 0)
	card.Parent = parent
	setGenerated(card)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = COMPACT_CORNER_RADIUS
	corner.Parent = card
	setGenerated(corner)

	local stroke = Instance.new("UIStroke")
	stroke.Color = SANDBOX_STROKE_COLOR
	stroke.Transparency = 0.14
	stroke.Parent = card
	setGenerated(stroke)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = card
	setGenerated(padding)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Padding = UDim.new(0, 8)
	layout.Parent = card
	setGenerated(layout)

	local description = Instance.new("TextLabel")
	description.Name = "DescriptionLabel"
	description.BackgroundTransparency = 1
	description.Size = UDim2.new(1, 0, 0, 34)
	description.AutomaticSize = Enum.AutomaticSize.Y
	description.Font = Enum.Font.Gotham
	description.Text = "These grants go straight to your live profile data. Body parts use default None/Normal variants, accessories add owned inventory records, materials update crafting amounts, and aura grants reuse the normal unlock path."
	description.TextWrapped = true
	description.TextSize = 13
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.TextColor3 = Color3.fromRGB(184, 196, 227)
	description.Parent = card
	setGenerated(description)

	local smartBodyPartInput, smartBodyPartValue, smartGrantBodyPartButton = self:_createGrantSmartRow(
		card,
		"SmartBodyPartRow",
		"Body Part",
		"Search id/name",
		function(text)
			self:_selectGrantBodyPartByQuery(text)
		end,
		function()
			self:_grantSelectedBodyPart()
		end
	)

	local smartHeadAccessoryInput, smartHeadAccessoryValue, smartGrantHeadAccessoryButton = self:_createGrantSmartRow(
		card,
		"SmartHeadAccessoryRow",
		"Head",
		"Search accessory",
		function(text)
			self:_selectGrantAccessoryByQuery(HEAD_ACCESSORY_SLOT, text)
		end,
		function()
			self:_grantSelectedAccessory(HEAD_ACCESSORY_SLOT)
		end
	)

	local smartGearAccessoryInput, smartGearAccessoryValue, smartGrantGearAccessoryButton = self:_createGrantSmartRow(
		card,
		"SmartGearAccessoryRow",
		"Gear",
		"Search accessory",
		function(text)
			self:_selectGrantAccessoryByQuery(GEAR_ACCESSORY_SLOT, text)
		end,
		function()
			self:_grantSelectedAccessory(GEAR_ACCESSORY_SLOT)
		end
	)

	local smartCraftingMaterialInput, smartCraftingMaterialValue, smartGrantCraftingMaterialButton = self:_createGrantSmartRow(
		card,
		"SmartCraftingMaterialRow",
		"Material",
		"Search material",
		function(text)
			self:_selectGrantCraftingMaterialByQuery(text)
		end,
		function()
			self:_grantSelectedCraftingMaterial()
		end
	)

	local smartAuraInput, smartAuraValue, smartGrantAuraButton = self:_createGrantSmartRow(
		card,
		"SmartAuraRow",
		"Aura",
		"Search aura",
		function(text)
			self:_selectGrantAuraByQuery(text)
		end,
		function()
			self:_grantSelectedAura()
		end
	)

	local smartGrantAllCraftingMaterialsButton = self:_createSandboxButton(
		card,
		"SmartGrantAllCraftingMaterialsButton",
		"Grant All Materials",
		UDim2.new(1, 0, 0, 34),
		function()
			self:_grantAllCraftingMaterials()
		end
	)

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
	bodyPartValue.TextSize = 13
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

	local headAccessoryField = self:_createSandboxField(card, "Grant Head Accessory")
	local headAccessoryRow = Instance.new("Frame")
	headAccessoryRow.Name = "ValueRow"
	headAccessoryRow.BackgroundTransparency = 1
	headAccessoryRow.Size = UDim2.new(1, 0, 0, 104)
	headAccessoryRow.Parent = headAccessoryField
	setGenerated(headAccessoryRow)

	local headAccessoryPrevButton = self:_createSandboxButton(headAccessoryRow, "PrevButton", "<", UDim2.fromOffset(38, 36), function()
		self:_cycleGrantAccessory(HEAD_ACCESSORY_SLOT, -1)
	end)

	local headAccessoryValue = Instance.new("TextLabel")
	headAccessoryValue.Name = "ValueLabel"
	headAccessoryValue.BackgroundTransparency = 1
	headAccessoryValue.Position = UDim2.fromOffset(48, 0)
	headAccessoryValue.Size = UDim2.new(1, -96, 1, 0)
	headAccessoryValue.Font = Enum.Font.GothamSemibold
	headAccessoryValue.TextColor3 = Color3.fromRGB(244, 247, 255)
	headAccessoryValue.TextSize = 13
	headAccessoryValue.TextWrapped = true
	headAccessoryValue.TextXAlignment = Enum.TextXAlignment.Left
	headAccessoryValue.TextYAlignment = Enum.TextYAlignment.Top
	headAccessoryValue.Parent = headAccessoryRow
	setGenerated(headAccessoryValue)

	local headAccessoryNextButton = self:_createSandboxButton(headAccessoryRow, "NextButton", ">", UDim2.fromOffset(38, 36), function()
		self:_cycleGrantAccessory(HEAD_ACCESSORY_SLOT, 1)
	end)
	headAccessoryNextButton.Position = UDim2.new(1, -38, 0, 0)

	local grantHeadAccessoryButton = self:_createSandboxButton(card, "GrantHeadAccessoryButton", "Grant Selected Head Accessory", UDim2.new(1, 0, 0, 40), function()
		self:_grantSelectedAccessory(HEAD_ACCESSORY_SLOT)
	end)

	local gearAccessoryField = self:_createSandboxField(card, "Grant Gear Accessory")
	local gearAccessoryRow = Instance.new("Frame")
	gearAccessoryRow.Name = "ValueRow"
	gearAccessoryRow.BackgroundTransparency = 1
	gearAccessoryRow.Size = UDim2.new(1, 0, 0, 104)
	gearAccessoryRow.Parent = gearAccessoryField
	setGenerated(gearAccessoryRow)

	local gearAccessoryPrevButton = self:_createSandboxButton(gearAccessoryRow, "PrevButton", "<", UDim2.fromOffset(38, 36), function()
		self:_cycleGrantAccessory(GEAR_ACCESSORY_SLOT, -1)
	end)

	local gearAccessoryValue = Instance.new("TextLabel")
	gearAccessoryValue.Name = "ValueLabel"
	gearAccessoryValue.BackgroundTransparency = 1
	gearAccessoryValue.Position = UDim2.fromOffset(48, 0)
	gearAccessoryValue.Size = UDim2.new(1, -96, 1, 0)
	gearAccessoryValue.Font = Enum.Font.GothamSemibold
	gearAccessoryValue.TextColor3 = Color3.fromRGB(244, 247, 255)
	gearAccessoryValue.TextSize = 13
	gearAccessoryValue.TextWrapped = true
	gearAccessoryValue.TextXAlignment = Enum.TextXAlignment.Left
	gearAccessoryValue.TextYAlignment = Enum.TextYAlignment.Top
	gearAccessoryValue.Parent = gearAccessoryRow
	setGenerated(gearAccessoryValue)

	local gearAccessoryNextButton = self:_createSandboxButton(gearAccessoryRow, "NextButton", ">", UDim2.fromOffset(38, 36), function()
		self:_cycleGrantAccessory(GEAR_ACCESSORY_SLOT, 1)
	end)
	gearAccessoryNextButton.Position = UDim2.new(1, -38, 0, 0)

	local grantGearAccessoryButton = self:_createSandboxButton(card, "GrantGearAccessoryButton", "Grant Selected Gear Accessory", UDim2.new(1, 0, 0, 40), function()
		self:_grantSelectedAccessory(GEAR_ACCESSORY_SLOT)
	end)

	local craftingMaterialField = self:_createSandboxField(card, "Grant Crafting Material")
	local craftingMaterialRow = Instance.new("Frame")
	craftingMaterialRow.Name = "ValueRow"
	craftingMaterialRow.BackgroundTransparency = 1
	craftingMaterialRow.Size = UDim2.new(1, 0, 0, 74)
	craftingMaterialRow.Parent = craftingMaterialField
	setGenerated(craftingMaterialRow)

	local craftingMaterialPrevButton = self:_createSandboxButton(craftingMaterialRow, "PrevButton", "<", UDim2.fromOffset(38, 36), function()
		self:_cycleGrantCraftingMaterial(-1)
	end)

	local craftingMaterialValue = Instance.new("TextLabel")
	craftingMaterialValue.Name = "ValueLabel"
	craftingMaterialValue.BackgroundTransparency = 1
	craftingMaterialValue.Position = UDim2.fromOffset(48, 0)
	craftingMaterialValue.Size = UDim2.new(1, -96, 1, 0)
	craftingMaterialValue.Font = Enum.Font.GothamSemibold
	craftingMaterialValue.TextColor3 = Color3.fromRGB(244, 247, 255)
	craftingMaterialValue.TextSize = 13
	craftingMaterialValue.TextWrapped = true
	craftingMaterialValue.TextXAlignment = Enum.TextXAlignment.Left
	craftingMaterialValue.TextYAlignment = Enum.TextYAlignment.Top
	craftingMaterialValue.Parent = craftingMaterialRow
	setGenerated(craftingMaterialValue)

	local craftingMaterialNextButton = self:_createSandboxButton(craftingMaterialRow, "NextButton", ">", UDim2.fromOffset(38, 36), function()
		self:_cycleGrantCraftingMaterial(1)
	end)
	craftingMaterialNextButton.Position = UDim2.new(1, -38, 0, 0)

	local materialAmountField = self:_createSandboxField(card, "Crafting Material Amount")
	local craftingMaterialAmountInput = self:_createSandboxTextInput(
		materialAmountField,
		"CraftingMaterialAmountInput",
		self._grantCraftingMaterialAmountText,
		"25",
		38
	)
	craftingMaterialAmountInput.FocusLost:Connect(function()
		self._grantCraftingMaterialAmountText = craftingMaterialAmountInput.Text
	end)

	local materialActionRow = Instance.new("Frame")
	materialActionRow.Name = "CraftingMaterialActionRow"
	materialActionRow.BackgroundTransparency = 1
	materialActionRow.Size = UDim2.new(1, 0, 0, 40)
	materialActionRow.Parent = card
	setGenerated(materialActionRow)

	local materialActionLayout = Instance.new("UIListLayout")
	materialActionLayout.FillDirection = Enum.FillDirection.Horizontal
	materialActionLayout.Padding = UDim.new(0, 8)
	materialActionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	materialActionLayout.Parent = materialActionRow
	setGenerated(materialActionLayout)

	local materialButtonSize = UDim2.new(0.5, -5, 1, 0)
	local grantCraftingMaterialButton = self:_createSandboxButton(materialActionRow, "GrantCraftingMaterialButton", "Grant Selected Material", materialButtonSize, function()
		self:_grantSelectedCraftingMaterial()
	end)

	local grantAllCraftingMaterialsButton = self:_createSandboxButton(materialActionRow, "GrantAllCraftingMaterialsButton", "Grant All Materials", materialButtonSize, function()
		self:_grantAllCraftingMaterials()
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
	auraValue.TextSize = 13
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
		smartBodyPartInput = smartBodyPartInput,
		smartBodyPartValue = smartBodyPartValue,
		smartGrantBodyPartButton = smartGrantBodyPartButton,
		smartHeadAccessoryInput = smartHeadAccessoryInput,
		smartHeadAccessoryValue = smartHeadAccessoryValue,
		smartGrantHeadAccessoryButton = smartGrantHeadAccessoryButton,
		smartGearAccessoryInput = smartGearAccessoryInput,
		smartGearAccessoryValue = smartGearAccessoryValue,
		smartGrantGearAccessoryButton = smartGrantGearAccessoryButton,
		smartCraftingMaterialInput = smartCraftingMaterialInput,
		smartCraftingMaterialValue = smartCraftingMaterialValue,
		smartGrantCraftingMaterialButton = smartGrantCraftingMaterialButton,
		smartGrantAllCraftingMaterialsButton = smartGrantAllCraftingMaterialsButton,
		smartAuraInput = smartAuraInput,
		smartAuraValue = smartAuraValue,
		smartGrantAuraButton = smartGrantAuraButton,
		bodyPartPrevButton = bodyPartPrevButton,
		bodyPartNextButton = bodyPartNextButton,
		bodyPartValue = bodyPartValue,
		grantBodyPartButton = grantBodyPartButton,
		headAccessoryPrevButton = headAccessoryPrevButton,
		headAccessoryNextButton = headAccessoryNextButton,
		headAccessoryValue = headAccessoryValue,
		grantHeadAccessoryButton = grantHeadAccessoryButton,
		gearAccessoryPrevButton = gearAccessoryPrevButton,
		gearAccessoryNextButton = gearAccessoryNextButton,
		gearAccessoryValue = gearAccessoryValue,
		grantGearAccessoryButton = grantGearAccessoryButton,
		craftingMaterialPrevButton = craftingMaterialPrevButton,
		craftingMaterialNextButton = craftingMaterialNextButton,
		craftingMaterialValue = craftingMaterialValue,
		craftingMaterialAmountInput = craftingMaterialAmountInput,
		grantCraftingMaterialButton = grantCraftingMaterialButton,
		grantAllCraftingMaterialsButton = grantAllCraftingMaterialsButton,
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
	corner.CornerRadius = COMPACT_CORNER_RADIUS
	corner.Parent = card
	setGenerated(corner)

	local stroke = Instance.new("UIStroke")
	stroke.Color = SANDBOX_STROKE_COLOR
	stroke.Transparency = 0.14
	stroke.Parent = card
	setGenerated(stroke)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = card
	setGenerated(padding)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Padding = UDim.new(0, 8)
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
	ownedValue.TextSize = 13
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
	equippedValue.TextSize = 13
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
	bonusesValue.TextSize = 13
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
	actionLayout.CellPadding = UDim2.fromOffset(8, 8)
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
	corner.CornerRadius = COMPACT_CORNER_RADIUS
	corner.Parent = card
	setGenerated(corner)

	local stroke = Instance.new("UIStroke")
	stroke.Color = SANDBOX_STROKE_COLOR
	stroke.Transparency = 0.14
	stroke.Parent = card
	setGenerated(stroke)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = card
	setGenerated(padding)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Padding = UDim.new(0, 8)
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
	description.TextSize = 13
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

function AdminPanelController:_getMarketplaceOfferOptions(kind: string): { any }
	local offers = {}
	for _, offer in pairs(MarketplaceCatalog.Offers) do
		if typeof(offer) == "table" and offer.kind == kind then
			table.insert(offers, offer)
		end
	end

	table.sort(offers, function(a, b)
		local displayA = string.lower(tostring(a.displayName or a.offerKey or ""))
		local displayB = string.lower(tostring(b.displayName or b.offerKey or ""))
		if displayA ~= displayB then
			return displayA < displayB
		end
		return tostring(a.offerKey or "") < tostring(b.offerKey or "")
	end)

	return offers
end

function AdminPanelController:_offerMatchesSearch(offer: any, searchText: string): boolean
	local normalizedSearch = normalizeSearchText(searchText)
	if normalizedSearch == "" then
		return true
	end

	local haystack = normalizeSearchText(string.format(
		"%s %s %s",
		tostring(offer.displayName or ""),
		tostring(offer.offerKey or ""),
		tostring(offer.handlerKey or "")
	))
	return string.find(haystack, normalizedSearch, 1, true) ~= nil
end

function AdminPanelController:_getFilteredMarketplaceOfferOptions(kind: string, searchText: string): { any }
	local filtered = {}
	for _, offer in ipairs(self:_getMarketplaceOfferOptions(kind)) do
		if self:_offerMatchesSearch(offer, searchText) then
			table.insert(filtered, offer)
		end
	end
	return filtered
end

function AdminPanelController:_findMarketplaceOffer(kind: string, offerKey: string?): any?
	if typeof(offerKey) ~= "string" or offerKey == "" then
		return nil
	end

	for _, offer in ipairs(self:_getMarketplaceOfferOptions(kind)) do
		if offer.offerKey == offerKey then
			return offer
		end
	end

	return nil
end

function AdminPanelController:_getSelectedMarketplaceOffer(kind: string): any?
	local selectedKey = if kind == "pass" then self._purchaseSelectedGamepassKey else self._purchaseSelectedDevProductKey
	local selectedOffer = self:_findMarketplaceOffer(kind, selectedKey)
	if selectedOffer then
		return selectedOffer
	end

	local options = self:_getMarketplaceOfferOptions(kind)
	local fallbackOffer = options[1]
	if fallbackOffer then
		if kind == "pass" then
			self._purchaseSelectedGamepassKey = fallbackOffer.offerKey
		else
			self._purchaseSelectedDevProductKey = fallbackOffer.offerKey
		end
	end

	return fallbackOffer
end

function AdminPanelController:_selectMarketplaceOffer(kind: string, offerKey: string)
	if kind == "pass" then
		self._purchaseSelectedGamepassKey = offerKey
	else
		self._purchaseSelectedDevProductKey = offerKey
	end
	self:_syncPurchasesUi()
end

function AdminPanelController:_formatMarketplaceOffer(offer: any?): string
	if not offer then
		return "No configured offer found."
	end

	local sale = offer.selfPurchase
	local saleKind = if typeof(sale) == "table" then tostring(sale.saleKind or "") else ""
	local robloxId = if typeof(sale) == "table" then tostring(sale.robloxId or "") else ""
	local amountText = if tonumber(offer.amount) ~= nil then string.format("\nAmount: %s", tostring(offer.amount)) else ""
	return string.format(
		"%s\n%s | %s %s | %s%s",
		tostring(offer.displayName or offer.offerKey),
		tostring(offer.offerKey),
		saleKind,
		robloxId,
		tostring(offer.grantMode or "grant"),
		amountText
	)
end

function AdminPanelController:_getPurchasesTargetUserId(): number
	local ui = self._purchasesUi
	local targetInput = ui and ui.targetInput
	local rawText = if targetInput and targetInput:IsA("TextBox") then targetInput.Text else self._purchaseTargetUserIdText
	local resolvedUserId = tonumber(trimText(rawText))
	if resolvedUserId then
		self._purchaseTargetUserIdText = tostring(math.floor(resolvedUserId))
		return math.floor(resolvedUserId)
	end

	local fallbackUserId = self:_getSelectedAdminTargetUserId()
	self._purchaseTargetUserIdText = tostring(fallbackUserId)
	return fallbackUserId
end

function AdminPanelController:_cyclePurchasesTarget(direction: number)
	local selectedPlayer, targets = self:_getSelectedPlayerStatsTarget()
	if #targets == 0 then
		self:_syncPurchasesUi()
		self:_setStatus("No live players are available.", ERROR_COLOR)
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
	self._purchaseTargetUserIdText = tostring(targets[nextIndex].UserId)
	self:_syncPurchasesUi()
end

function AdminPanelController:_syncPurchasesUi()
	local ui = self._purchasesUi
	if not ui or next(ui) == nil then
		return
	end

	local targetUserId = self:_getPurchasesTargetUserId()
	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if ui.targetInput and ui.targetInput:IsA("TextBox") and not ui.targetInput:IsFocused() then
		ui.targetInput.Text = tostring(targetUserId)
	end
	if ui.targetValue and ui.targetValue:IsA("TextLabel") then
		ui.targetValue.Text = if targetPlayer
			then string.format("%s\n%d", formatPlayerDisplay(targetPlayer), targetUserId)
			else string.format("Offline or not in this server\n%d", targetUserId)
	end

	local selectedGamepass = self:_getSelectedMarketplaceOffer("pass")
	local selectedDevProduct = self:_getSelectedMarketplaceOffer("product")
	if ui.gamepassValue and ui.gamepassValue:IsA("TextLabel") then
		ui.gamepassValue.Text = self:_formatMarketplaceOffer(selectedGamepass)
	end
	if ui.devProductValue and ui.devProductValue:IsA("TextLabel") then
		ui.devProductValue.Text = self:_formatMarketplaceOffer(selectedDevProduct)
	end

	local gamepassSearch = if ui.gamepassSearchInput and ui.gamepassSearchInput:IsA("TextBox") then ui.gamepassSearchInput.Text else self._purchaseGamepassSearchText
	self._purchaseGamepassSearchText = gamepassSearch
	local gamepassOptions = self:_getFilteredMarketplaceOfferOptions("pass", gamepassSearch)
	for index, button in ipairs(ui.gamepassButtons or {}) do
		local offer = gamepassOptions[index]
		button.Visible = offer ~= nil
		button.Text = offer and tostring(offer.displayName or offer.offerKey) or ""
		button:SetAttribute("OfferKey", offer and offer.offerKey or "")
	end

	local devProductSearch = if ui.devProductSearchInput and ui.devProductSearchInput:IsA("TextBox") then ui.devProductSearchInput.Text else self._purchaseDevProductSearchText
	self._purchaseDevProductSearchText = devProductSearch
	local devProductOptions = self:_getFilteredMarketplaceOfferOptions("product", devProductSearch)
	for index, button in ipairs(ui.devProductButtons or {}) do
		local offer = devProductOptions[index]
		button.Visible = offer ~= nil
		button.Text = offer and tostring(offer.displayName or offer.offerKey) or ""
		button:SetAttribute("OfferKey", offer and offer.offerKey or "")
	end

	if ui.devProductCountInput and ui.devProductCountInput:IsA("TextBox") and not ui.devProductCountInput:IsFocused() then
		ui.devProductCountInput.Text = self._purchaseDevProductCountText
	end
end

function AdminPanelController:_runPurchaseReset()
	local ui = self._purchasesUi
	local confirmationInput = ui and ui.resetConfirmationInput
	local payload = {
		userId = self:_getPurchasesTargetUserId(),
		confirmation = if confirmationInput and confirmationInput:IsA("TextBox") then confirmationInput.Text else "",
	}
	local ok, result = self:_invokeAdminRequest(PURCHASES_TAB_ID, "reset_player_data", "Resetting player data", payload)
	if not ok or not result then
		return
	end

	self:_setStatus(tostring(result.message or "Reset request completed."), if result.ok then SUCCESS_COLOR else ERROR_COLOR)
end

function AdminPanelController:_grantSelectedMarketplaceOffer(kind: string)
	local ui = self._purchasesUi
	local selectedOffer = self:_getSelectedMarketplaceOffer(kind)
	if not selectedOffer then
		self:_setStatus("Select an offer to grant first.", ERROR_COLOR)
		return
	end

	local confirmationInput = if kind == "pass" then ui.gamepassConfirmationInput else ui.devProductConfirmationInput
	local reasonInput = if kind == "pass" then ui.gamepassReasonInput else ui.devProductReasonInput
	local countInput = ui.devProductCountInput
	local actionId = if kind == "pass" then "grant_gamepass" else "grant_devproduct"
	local actionTitle = if kind == "pass" then "Granting gamepass" else "Granting dev product"
	local payload = {
		userId = self:_getPurchasesTargetUserId(),
		offerKey = selectedOffer.offerKey,
		reason = if reasonInput and reasonInput:IsA("TextBox") then reasonInput.Text else "admin grant",
		confirmation = if confirmationInput and confirmationInput:IsA("TextBox") then confirmationInput.Text else "",
	}
	if kind == "product" then
		self._purchaseDevProductCountText = if countInput and countInput:IsA("TextBox") then countInput.Text else self._purchaseDevProductCountText
		payload.count = tonumber(self._purchaseDevProductCountText) or 1
	end

	local ok, result = self:_invokeAdminRequest(PURCHASES_TAB_ID, actionId, actionTitle, payload)
	if not ok or not result then
		return
	end

	self:_setStatus(tostring(result.message or "Marketplace grant completed."), if result.ok then SUCCESS_COLOR else ERROR_COLOR)
end

function AdminPanelController:_createPurchasesOfferSelector(
	parent: Instance,
	kind: string,
	title: string,
	searchPlaceholder: string
): (TextBox, TextLabel, { TextButton })
	local field = self:_createSandboxField(parent, title)

	local searchInput = self:_createSandboxTextInput(field, "SearchInput", "", searchPlaceholder, 36, false)
	searchInput:GetPropertyChangedSignal("Text"):Connect(function()
		if kind == "pass" then
			self._purchaseGamepassSearchText = searchInput.Text
		else
			self._purchaseDevProductSearchText = searchInput.Text
		end
		self:_syncPurchasesUi()
	end)

	local valueLabel = self:_createSandboxValueLabel(field)

	local buttonGrid = Instance.new("Frame")
	buttonGrid.Name = "OfferButtonGrid"
	buttonGrid.BackgroundTransparency = 1
	buttonGrid.Size = UDim2.new(1, 0, 0, 112)
	buttonGrid.Parent = field
	setGenerated(buttonGrid)

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellPadding = UDim2.fromOffset(6, 6)
	gridLayout.CellSize = UDim2.new(0.5, -3, 0, 32)
	gridLayout.FillDirectionMaxCells = 2
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = buttonGrid
	setGenerated(gridLayout)

	local buttons = {}
	for index = 1, PURCHASE_SELECTOR_BUTTON_COUNT do
		local button = self:_createSandboxButton(buttonGrid, string.format("OfferButton%d", index), "", UDim2.fromOffset(0, 32), function()
			local offerKey = tostring(buttons[index]:GetAttribute("OfferKey") or "")
			if offerKey ~= "" then
				self:_selectMarketplaceOffer(kind, offerKey)
			end
		end)
		button.LayoutOrder = index
		table.insert(buttons, button)
	end

	return searchInput, valueLabel, buttons
end

function AdminPanelController:_createPurchasesPanelSection(parent: ScrollingFrame)
	self:_createSectionHeader(parent, "Purchases", "Reset data and grant configured marketplace offers.")

	local card = Instance.new("Frame")
	card.Name = "PurchasesPanelCard"
	card.Parent = parent
	setGenerated(card)
	self:_styleCompactCard(card, "mutating")

	local targetField = self:_createSandboxField(card, "Target Player")
	local targetRow = Instance.new("Frame")
	targetRow.Name = "TargetRow"
	targetRow.BackgroundTransparency = 1
	targetRow.Size = UDim2.new(1, 0, 0, 36)
	targetRow.Parent = targetField
	setGenerated(targetRow)

	local targetLayout = Instance.new("UIListLayout")
	targetLayout.FillDirection = Enum.FillDirection.Horizontal
	targetLayout.Padding = UDim.new(0, 6)
	targetLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	targetLayout.Parent = targetRow
	setGenerated(targetLayout)

	local targetPrevButton = self:_createSandboxButton(targetRow, "PrevButton", "<", UDim2.fromOffset(34, 36), function()
		self:_cyclePurchasesTarget(-1)
	end)
	local targetNextButton = self:_createSandboxButton(targetRow, "NextButton", ">", UDim2.fromOffset(34, 36), function()
		self:_cyclePurchasesTarget(1)
	end)
	local targetInput = self:_createSandboxTextInput(targetRow, "TargetUserIdInput", self._purchaseTargetUserIdText, "UserId", 36, false)
	targetInput.Size = UDim2.new(0, 160, 0, 34)
	targetInput.FocusLost:Connect(function()
		self._purchaseTargetUserIdText = targetInput.Text
		self:_syncPurchasesUi()
	end)

	local targetValue = self:_createSandboxValueLabel(targetField)

	local resetField = self:_createSandboxField(card, "Reset Data")
	local resetConfirmationInput = self:_createSandboxTextInput(resetField, "ResetConfirmationInput", "", "Type RESET", 36, false)
	local resetButton = self:_createSandboxButton(resetField, "ResetButton", "Reset Data", UDim2.new(1, 0, 0, 36), function()
		self:_runPurchaseReset()
	end)
	resetButton.BackgroundColor3 = Color3.fromRGB(104, 38, 46)

	local gamepassSearchInput, gamepassValue, gamepassButtons = self:_createPurchasesOfferSelector(
		card,
		"pass",
		"Grant Gamepass",
		"Search passes"
	)
	local gamepassReasonInput = self:_createSandboxTextInput(card, "GamepassReasonInput", "admin grant", "Reason", 36, false)
	local gamepassConfirmationInput = self:_createSandboxTextInput(card, "GamepassConfirmationInput", "", "Type GRANT", 36, false)
	local grantGamepassButton = self:_createSandboxButton(card, "GrantGamepassButton", "Grant Selected Gamepass", UDim2.new(1, 0, 0, 36), function()
		self:_grantSelectedMarketplaceOffer("pass")
	end)

	local devProductSearchInput, devProductValue, devProductButtons = self:_createPurchasesOfferSelector(
		card,
		"product",
		"Grant Dev Product",
		"Search products"
	)
	local devProductCountInput = self:_createSandboxTextInput(card, "DevProductCountInput", self._purchaseDevProductCountText, "Count (repeatable only)", 36, false)
	devProductCountInput.FocusLost:Connect(function()
		self._purchaseDevProductCountText = devProductCountInput.Text
	end)
	local devProductReasonInput = self:_createSandboxTextInput(card, "DevProductReasonInput", "admin grant", "Reason", 36, false)
	local devProductConfirmationInput = self:_createSandboxTextInput(card, "DevProductConfirmationInput", "", "Type GRANT", 36, false)
	local grantDevProductButton = self:_createSandboxButton(card, "GrantDevProductButton", "Grant Selected Dev Product", UDim2.new(1, 0, 0, 36), function()
		self:_grantSelectedMarketplaceOffer("product")
	end)

	self._purchasesUi = {
		targetPrevButton = targetPrevButton,
		targetNextButton = targetNextButton,
		targetInput = targetInput,
		targetValue = targetValue,
		resetConfirmationInput = resetConfirmationInput,
		resetButton = resetButton,
		gamepassSearchInput = gamepassSearchInput,
		gamepassValue = gamepassValue,
		gamepassButtons = gamepassButtons,
		gamepassReasonInput = gamepassReasonInput,
		gamepassConfirmationInput = gamepassConfirmationInput,
		grantGamepassButton = grantGamepassButton,
		devProductSearchInput = devProductSearchInput,
		devProductValue = devProductValue,
		devProductButtons = devProductButtons,
		devProductCountInput = devProductCountInput,
		devProductReasonInput = devProductReasonInput,
		devProductConfirmationInput = devProductConfirmationInput,
		grantDevProductButton = grantDevProductButton,
	}

	self:_syncPurchasesUi()
end

function AdminPanelController:_createActionCard(parent: Instance, tabId: string, action: any, _template: GuiButton)
	if typeof(action.fields) == "table" and #action.fields > 0 then
		self:_createActionFormCard(parent, tabId, action)
		return
	end

	local card = Instance.new("TextButton")
	card.Name = string.format("%sCard", action.id)
	card.BackgroundColor3 = SANDBOX_CARD_COLOR
	card.BorderSizePixel = 0
	card.AutoButtonColor = false
	card.Text = ""
	card.Size = UDim2.new(1, -2, 0, 42)
	card.Parent = parent
	setGenerated(card)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = card
	setGenerated(corner)

	local stroke = Instance.new("UIStroke")
	stroke.Color = if action.risk == "destructive" then DESTRUCTIVE_STROKE_COLOR else SANDBOX_STROKE_COLOR
	stroke.Transparency = if action.risk == "destructive" then 0.2 else 0.58
	stroke.Thickness = 1
	stroke.Parent = card
	setGenerated(stroke)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.fromOffset(12, 0)
	titleLabel.Size = UDim2.new(1, -122, 1, 0)
	titleLabel.Font = Enum.Font.GothamSemibold
	titleLabel.Text = action.title
	titleLabel.TextColor3 = Color3.fromRGB(232, 237, 250)
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.Parent = card
	setGenerated(titleLabel)

	local badgeLabel = Instance.new("TextLabel")
	badgeLabel.Name = "RiskBadge"
	badgeLabel.AnchorPoint = Vector2.new(1, 0.5)
	badgeLabel.Position = UDim2.new(1, -10, 0.5, 0)
	badgeLabel.Size = UDim2.fromOffset(92, 22)
	badgeLabel.BackgroundColor3 = getRiskBadgeColor(action)
	badgeLabel.BackgroundTransparency = 0.86
	badgeLabel.BorderSizePixel = 0
	badgeLabel.Font = Enum.Font.GothamBold
	badgeLabel.Text = getRiskBadgeText(action)
	badgeLabel.TextColor3 = getRiskBadgeColor(action)
	badgeLabel.TextSize = 11
	badgeLabel.Parent = card
	setGenerated(badgeLabel)

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 5)
	badgeCorner.Parent = badgeLabel
	setGenerated(badgeCorner)

	UIController:CreateButton(card, function()
		self:_invokeAction(tabId, action.id, action.title)
	end)
end

function AdminPanelController:_buildPage(tabDefinition: any, page: ScrollingFrame, actionTemplate: GuiButton)
	for _, child in ipairs(page:GetChildren()) do
		if child:GetAttribute("GeneratedAdminPanel") == true and child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	if tabDefinition.id == BODY_PARTS_TAB_ID then
		self:_createGrantInventorySection(page)
		self:_createSpacer(page, 8)
		self:_createRuntimeInspectorSection(page)
		self:_createSpacer(page, 8)
		self:_createVisualSandboxSection(page)
		self:_createSpacer(page, 8)
	end

	if tabDefinition.id == OVERVIEW_TAB_ID then
		self:_createNotificationSection(page)
		self:_createSpacer(page, 8)
	end

	if tabDefinition.id == PLAYERS_TAB_ID then
		self:_createPlayerStatsInspectorSection(page)
		self:_createSpacer(page, 8)
	end

	if tabDefinition.id == PURCHASES_TAB_ID then
		self:_createPurchasesPanelSection(page)
		page.Visible = false
		page.CanvasPosition = Vector2.zero
		return
	end

	if tabDefinition.id == PROGRESSION_TAB_ID then
		self:_createLuckOverrideSection(page)
		self:_createSpacer(page, 8)
	end

	for sectionIndex, section in ipairs(tabDefinition.sections) do
		self:_createSectionHeader(page, section.title, section.description)

		for _, action in ipairs(section.actions) do
			local isCustomPlayerInspector = tabDefinition.id == PLAYERS_TAB_ID and action.id == "inspect_player_profile"
			local isCustomGrantInventoryAction = tabDefinition.id == BODY_PARTS_TAB_ID
				and (
					action.id == "grant_body_part"
					or action.id == "grant_head_accessory"
					or action.id == "grant_gear_accessory"
					or action.id == "grant_crafting_material"
					or action.id == "grant_all_crafting_materials"
				)
			if not (isCustomPlayerInspector or isCustomGrantInventoryAction) then
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

function AdminPanelController:_buildTabs(tabRail: Instance, _tabTemplate: GuiButton)
	for _, child in ipairs(tabRail:GetChildren()) do
		if child:GetAttribute("GeneratedAdminPanel") == true and child:IsA("GuiButton") then
			child:Destroy()
		end
	end

	self._tabButtons = {}

	for _, tabDefinition in ipairs(AdminPanelDefinitions.Tabs) do
		local button = Instance.new("TextButton")
		button.Name = string.format("%sTabButton", tabDefinition.pageName)
		button.Visible = true
		button.LayoutOrder = table.find(AdminPanelDefinitions.Tabs, tabDefinition) or 0
		button.Size = UDim2.fromScale(1, 1)
		button.Text = ""
		button.Parent = tabRail
		setGenerated(button)

		local titleLabel = Instance.new("TextLabel")
		titleLabel.Name = "TitleLabel"
		titleLabel.BackgroundTransparency = 1
		titleLabel.Size = UDim2.fromScale(1, 1)
		titleLabel.Font = Enum.Font.GothamBold
		titleLabel.Text = tabDefinition.title
		titleLabel.TextSize = 12
		titleLabel.TextXAlignment = Enum.TextXAlignment.Center
		titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
		titleLabel.Parent = button
		setGenerated(titleLabel)

		self._tabButtons[tabDefinition.id] = button

		UIController:CreateButton(button, function()
			self:_setTab(tabDefinition.id)
		end)
	end
end

function AdminPanelController:_simplifyGeneratedPage(page: ScrollingFrame)
	local hiddenGrantControls = {
		GrantBodyPartField = true,
		GrantBodyPartButton = true,
		GrantHeadAccessoryField = true,
		GrantHeadAccessoryButton = true,
		GrantGearAccessoryField = true,
		GrantGearAccessoryButton = true,
		GrantCraftingMaterialField = true,
		CraftingMaterialActionRow = true,
		GrantAuraField = true,
		GrantAuraButton = true,
	}

	for _, descendant in ipairs(page:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			if descendant.Name == "DescriptionLabel" then
				descendant.Visible = false
			elseif descendant.TextSize > 14 then
				descendant.TextSize = 14
			end
		elseif descendant:IsA("GuiButton") then
			descendant.AutoButtonColor = false
		elseif descendant:IsA("Frame") and descendant.Name:find("Card") then
			descendant.BackgroundColor3 = SANDBOX_CARD_COLOR
			descendant.BackgroundTransparency = 0
		end

		if hiddenGrantControls[descendant.Name] and descendant:IsA("GuiObject") then
			descendant.Visible = false
			descendant.Size = UDim2.fromOffset(0, 0)
		end
	end
end

function AdminPanelController:_buildInterface(panel: Frame)
	local templates = panel:WaitForChild("Templates")
	local tabTemplate = templates:WaitForChild("TabButtonTemplate")
	local actionTemplate = templates:WaitForChild("ActionCardTemplate")

	if not (tabTemplate:IsA("GuiButton") and actionTemplate:IsA("GuiButton")) then
		Logger.Error("AdminPanel templates are missing required button types.")
	end

	local simpleLayout = self:_createSimpleMenuLayout(panel)
	local tabRail = simpleLayout.tabList
	local pages = simpleLayout.pages

	self._pageTitleLabel = simpleLayout.pageTitle :: TextLabel
	self._pageSubtitleLabel = simpleLayout.pageSubtitle :: TextLabel
	self._statusLabel = simpleLayout.status :: TextLabel

	self:_buildTabs(tabRail, tabTemplate)
	self._pages = {}

	for _, tabDefinition in ipairs(AdminPanelDefinitions.Tabs) do
		local page = Instance.new("ScrollingFrame")
		page.Name = tabDefinition.pageName
		page.Parent = pages
		setGenerated(page)

		page.BackgroundTransparency = 1
		page.BorderSizePixel = 0
		page.ScrollBarThickness = 6
		page.ScrollBarImageColor3 = Color3.fromRGB(96, 112, 148)
		page.AutomaticCanvasSize = Enum.AutomaticSize.Y
		page.CanvasSize = UDim2.fromOffset(0, 0)
		page.Size = UDim2.fromScale(1, 1)
		page.ScrollingDirection = Enum.ScrollingDirection.Y

		local pagePadding = getOrCreateFirstChildOfClass(page, "UIPadding", "PagePadding") :: UIPadding
		pagePadding.PaddingTop = UDim.new(0, 6)
		pagePadding.PaddingBottom = UDim.new(0, 10)
		pagePadding.PaddingLeft = UDim.new(0, 2)
		pagePadding.PaddingRight = UDim.new(0, 8)

		local pageLayout = getOrCreateFirstChildOfClass(page, "UIListLayout", "PageLayout") :: UIListLayout
		pageLayout.FillDirection = Enum.FillDirection.Vertical
		pageLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
		pageLayout.Padding = UDim.new(0, 6)

		self._pages[tabDefinition.id] = page
		self:_buildPage(tabDefinition, page, actionTemplate)
		self:_simplifyGeneratedPage(page)
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
		Logger.Warn("[AdminPanelController] AdminPanel ScreenGui was not found in PlayerGui.")
		return
	end

	self._screenGui = screenGui

	local windowRoot = screenGui:WaitForChild("WindowRoot", 30)
	if not (windowRoot and windowRoot:IsA("GuiObject")) then
		Logger.Warn("[AdminPanelController] WindowRoot was not found under AdminPanel.")
		return
	end

	self._windowRoot = windowRoot

	local dimmer = windowRoot:WaitForChild("Dimmer", 30)
	local panel = windowRoot:WaitForChild("Panel", 30)
	if not ((dimmer and dimmer:IsA("GuiButton")) and (panel and panel:IsA("Frame"))) then
		Logger.Warn("[AdminPanelController] AdminPanel is missing required Dimmer or Panel instances.")
		return
	end

	local closeButton = panel:WaitForChild("Header"):WaitForChild("CloseButton", 30)
	if not (closeButton and closeButton:IsA("GuiButton")) then
		Logger.Warn("[AdminPanelController] AdminPanel close button is missing.")
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
