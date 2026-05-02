local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Globals = require(ReplicatedStorage.Lists.Globals)
local Schema = require(ReplicatedStorage.Lists.Schema)
local MerchantShopConfig = require(ReplicatedStorage.Shared.Config.MerchantShopConfig)
local PotionConfig = require(ReplicatedStorage.Shared.Config.PotionConfig)
local TimeShardState = require(ReplicatedStorage.Shared.Character.TimeShardState)
local LocalizationKeys = require(ReplicatedStorage.Shared.Localization.Keys)
local TranslationHelper = require(ReplicatedStorage.Shared.Localization.TranslationHelper)
local PotionPresentation = require(ReplicatedStorage.Shared.UI.PotionPresentation)
local ViewportModelRenderer = require(ReplicatedStorage.Shared.UI.ViewportModelRenderer)

local DataController = require(script.Parent.DataController)
local MerchantPresentationController = require(script.Parent.MerchantPresentationController)
local UIController = require(script.Parent.UIController)

local LOCAL_PLAYER = Players.LocalPlayer
local REMOTES_FOLDER_NAME = "Remotes"
local MERCHANT_SHOP_FOLDER_NAME = "MerchantShop"
local GET_SHOP_STATE_REMOTE_NAME = "GetShopState"
local PURCHASE_SHOP_ITEM_REMOTE_NAME = "PurchaseShopItem"
local SHOP_FRAME_NAME = "ShopUI"
local TIME_SHARDS_KEY = Schema.TimeShards and Schema.TimeShards.key or nil

type MerchantShopState = {
	windowId: number,
	isActive: boolean,
	appearsAt: number,
	departsAt: number,
	nextAppearsAt: number,
	stockByPotionId: { [string]: number },
}

type MerchantShopUi = {
	root: GuiObject,
	itemName: TextLabel,
	itemDescLabel: TextLabel,
	stocksLabel: TextLabel,
	priceLabel: TextLabel,
	timeShardsLabel: TextLabel?,
	viewportFrame: ViewportFrame?,
	selectionScrollingFrame: ScrollingFrame,
	buttonTemplate: ImageButton,
	purchaseButton: GuiButton,
	purchaseButtonLabel: TextLabel?,
	amountBox: TextBox,
	messageRoot: GuiButton,
	messageTitle: TextLabel?,
	messageDescription: TextLabel?,
	messageClose: GuiButton?,
}

local MerchantShopController = {
	_started = false,
	_ui = nil :: MerchantShopUi?,
	_runtimeButtonsByPotionId = {} :: { [string]: ImageButton },
	_remotes = nil,
	_shopState = nil :: MerchantShopState?,
	_selectedPotionId = nil :: string?,
	_isShopOpen = false,
	_refreshConnection = nil :: RBXScriptConnection?,
	_suppressAmountFocus = false,
	_lastCountdownSecond = -1,
	_warnedMissingTimeShardsLabel = false,
}

local function normalizeWhole(value: any): number
	return math.max(0, math.floor(tonumber(value) or 0))
end

local function getUtcNowSeconds(): number
	return math.floor(DateTime.now().UnixTimestampMillis / 1000)
end

local function formatCountdown(targetTimestamp: number): string
	local remainingSeconds = math.max(0, math.floor(tonumber(targetTimestamp) or 0) - getUtcNowSeconds())
	local minutes = math.floor(remainingSeconds / 60)
	local seconds = remainingSeconds % 60
	return string.format("%02d:%02d", minutes, seconds)
end

local function formatTimeShards(value: any): string
	return TranslationHelper.formatByKey(LocalizationKeys.MerchantShop.Common.TimeShards, {
		Amount = Globals.formatNumber(value),
	})
end

local function formatCost(value: any): string
	return TranslationHelper.formatByKey(LocalizationKeys.MerchantShop.Common.Cost, {
		Cost = formatTimeShards(value),
	})
end

local function buildEmptyState(): MerchantShopState
	local stockByPotionId = {}
	for _, entry in ipairs(MerchantShopConfig.GetAll()) do
		stockByPotionId[entry.potionId] = 0
	end

	return {
		windowId = -1,
		isActive = false,
		appearsAt = 0,
		departsAt = 0,
		nextAppearsAt = 0,
		stockByPotionId = stockByPotionId,
	}
end

local function resolveTimeShardsLabel(root: GuiObject): TextLabel?
	local timeShards = root:FindFirstChild("TimeShards", true)
	if timeShards and timeShards:IsA("TextLabel") then
		return timeShards
	end

	if not timeShards then
		return nil
	end

	local quantity = timeShards:FindFirstChild("Quantity", true)
	if quantity and quantity:IsA("TextLabel") then
		return quantity
	end

	local fallbackLabel = timeShards:FindFirstChildWhichIsA("TextLabel", true)
	return if fallbackLabel and fallbackLabel:IsA("TextLabel") then fallbackLabel else nil
end

function MerchantShopController:_getPlayerGui(): PlayerGui
	return LOCAL_PLAYER:WaitForChild("PlayerGui")
end

function MerchantShopController:_ensureUi(): MerchantShopUi
	if self._ui and self._ui.root.Parent then
		return self._ui
	end

	local modalRoot = self:_getPlayerGui():WaitForChild("ModalRoot", 30)
	assert(modalRoot and modalRoot:IsA("ScreenGui"), "PlayerGui.ModalRoot is missing.")

	local root = modalRoot:WaitForChild(SHOP_FRAME_NAME, 30)
	assert(root and root:IsA("GuiObject"), "PlayerGui.ModalRoot.ShopUI is missing.")

	local itemName = root:FindFirstChild("ItemName", true)
	assert(itemName and itemName:IsA("TextLabel"), "ShopUI.ItemName is missing.")

	local itemDesc = root:FindFirstChild("ItemDesc", true)
	assert(itemDesc and itemDesc:IsA("Frame"), "ShopUI.ItemDesc is missing.")

	local itemDescLabel = itemDesc:FindFirstChildWhichIsA("TextLabel")
	assert(itemDescLabel, "ShopUI.ItemDesc.TextLabel is missing.")

	local stocksLabel = root:FindFirstChild("Stocks", true)
	assert(stocksLabel and stocksLabel:IsA("TextLabel"), "ShopUI.Stocks is missing.")

	local priceLabel = root:FindFirstChild("Price", true)
	assert(priceLabel and priceLabel:IsA("TextLabel"), "ShopUI.Price is missing.")

	local timeShardsLabel = resolveTimeShardsLabel(root)
	if not timeShardsLabel and not self._warnedMissingTimeShardsLabel then
		self._warnedMissingTimeShardsLabel = true
		Logger.Warn("[MerchantShopController] ShopUI.TimeShards label is missing; time shard balance will not render.")
	end

	local viewportFrame = root:FindFirstChild("ViewportFrame", true)
	if viewportFrame and not viewportFrame:IsA("ViewportFrame") then
		viewportFrame = nil
	end

	local selection = root:FindFirstChild("Selection", true)
	assert(selection and selection:IsA("Frame"), "ShopUI.Selection is missing.")
	local scrollingFrame = selection:FindFirstChild("ScrollingFrame", true)
	assert(scrollingFrame and scrollingFrame:IsA("ScrollingFrame"), "ShopUI.Selection.ScrollingFrame is missing.")

	local buttonTemplate = nil :: ImageButton?
	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child:IsA("ImageButton") then
			buttonTemplate = buttonTemplate or child
			child.Visible = false
			child.Active = false
			child.AutoButtonColor = false
		end
	end

	assert(buttonTemplate, "ShopUI.Selection.ScrollingFrame.Button is missing.")

	local purchaseButton = root:FindFirstChild("PurchaseButton", true)
	assert(purchaseButton and purchaseButton:IsA("GuiButton"), "ShopUI.PurchaseButton is missing.")

	local purchaseButtonLabel = purchaseButton:FindFirstChildWhichIsA("TextLabel")
	local amountBox = purchaseButton:FindFirstChild("Amount", true)
	assert(amountBox and amountBox:IsA("TextBox"), "ShopUI.PurchaseButton.Amount is missing.")

	local messageRoot = root:FindFirstChild("MessageUI", true)
	assert(messageRoot and messageRoot:IsA("GuiButton"), "ShopUI.MessageUI is missing.")
	local messageFrame = messageRoot:FindFirstChild("Message", true)
	local messageTitle = if messageFrame then messageFrame:FindFirstChild("Title") else nil
	local messageDescription = if messageFrame then messageFrame:FindFirstChild("Description") else nil
	local messageClose = if messageFrame then messageFrame:FindFirstChild("Close") else nil

	self._ui = {
		root = root,
		itemName = itemName,
		itemDescLabel = itemDescLabel,
		stocksLabel = stocksLabel,
		priceLabel = priceLabel,
		timeShardsLabel = timeShardsLabel,
		viewportFrame = viewportFrame,
		selectionScrollingFrame = scrollingFrame,
		buttonTemplate = buttonTemplate,
		purchaseButton = purchaseButton,
		purchaseButtonLabel = if purchaseButtonLabel and purchaseButtonLabel:IsA("TextLabel") then purchaseButtonLabel else nil,
		amountBox = amountBox,
		messageRoot = messageRoot,
		messageTitle = if messageTitle and messageTitle:IsA("TextLabel") then messageTitle else nil,
		messageDescription = if messageDescription and messageDescription:IsA("TextLabel") then messageDescription else nil,
		messageClose = if messageClose and messageClose:IsA("GuiButton") then messageClose else nil,
	}

	return self._ui
end

function MerchantShopController:_ensureRemotes(): boolean
	if self._remotes and self._remotes.getShopState and self._remotes.purchaseShopItem then
		return true
	end

	local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if not (remotesFolder and remotesFolder:IsA("Folder")) then
		return false
	end

	local merchantShopFolder = remotesFolder:FindFirstChild(MERCHANT_SHOP_FOLDER_NAME)
	if not (merchantShopFolder and merchantShopFolder:IsA("Folder")) then
		return false
	end

	local getShopState = merchantShopFolder:FindFirstChild(GET_SHOP_STATE_REMOTE_NAME)
	local purchaseShopItem = merchantShopFolder:FindFirstChild(PURCHASE_SHOP_ITEM_REMOTE_NAME)
	if not (getShopState and getShopState:IsA("RemoteFunction")) then
		return false
	end
	if not (purchaseShopItem and purchaseShopItem:IsA("RemoteFunction")) then
		return false
	end

	self._remotes = {
		getShopState = getShopState,
		purchaseShopItem = purchaseShopItem,
	}
	return true
end

function MerchantShopController:_invokeRemote(remote: RemoteFunction, payload: any?): any?
	local ok, result = pcall(function()
		if payload ~= nil then
			return remote:InvokeServer(payload)
		end

		return remote:InvokeServer()
	end)
	if not ok then
		Logger.Warn(string.format("[MerchantShopController] Remote %s failed: %s", remote.Name, tostring(result)))
		return nil
	end

	return result
end

function MerchantShopController:_cloneShopState(shopState: any): MerchantShopState
	local cloned = buildEmptyState()
	if typeof(shopState) ~= "table" then
		return cloned
	end

	cloned.windowId = math.floor(tonumber(shopState.windowId or shopState.cycleId) or cloned.windowId)
	cloned.isActive = shopState.isActive == true
	cloned.appearsAt = math.floor(tonumber(shopState.appearsAt) or cloned.appearsAt)
	cloned.departsAt = math.floor(tonumber(shopState.departsAt) or cloned.departsAt)
	cloned.nextAppearsAt = math.floor(tonumber(shopState.nextAppearsAt) or cloned.nextAppearsAt)

	if typeof(shopState.stockByPotionId) == "table" then
		for _, entry in ipairs(MerchantShopConfig.GetAll()) do
			cloned.stockByPotionId[entry.potionId] = math.clamp(
				normalizeWhole(shopState.stockByPotionId[entry.potionId]),
				0,
				MerchantShopConfig.GetMaxStockForPotionId(entry.potionId)
			)
		end
	end

	return cloned
end

function MerchantShopController:_getVisibleEntries(): { MerchantShopConfig.MerchantShopEntry }
	local results = {}
	local shopState = self._shopState or buildEmptyState()
	if not shopState.isActive then
		return results
	end

	for _, entry in ipairs(MerchantShopConfig.GetAll()) do
		if normalizeWhole(shopState.stockByPotionId[entry.potionId]) > 0 then
			table.insert(results, entry)
		end
	end
	return results
end

function MerchantShopController:_getSelectedEntry()
	if self._selectedPotionId == nil then
		return nil
	end

	return MerchantShopConfig.GetByPotionId(self._selectedPotionId)
end

function MerchantShopController:_getSelectedPotionConfig()
	local entry = self:_getSelectedEntry()
	return if entry then PotionConfig.Get(entry.potionId) else nil
end

function MerchantShopController:_getSelectedStock(): number
	local entry = self:_getSelectedEntry()
	local shopState = self._shopState or buildEmptyState()
	if not entry or not shopState.isActive then
		return 0
	end

	return math.clamp(
		normalizeWhole(shopState.stockByPotionId[entry.potionId]),
		0,
		MerchantShopConfig.GetMaxStockForPotionId(entry.potionId)
	)
end

function MerchantShopController:_setPurchaseEnabled(isEnabled: boolean)
	local ui = self:_ensureUi()
	ui.purchaseButton.Active = isEnabled
	ui.purchaseButton.AutoButtonColor = isEnabled
	if ui.purchaseButtonLabel then
		TranslationHelper.setKeyText(
			ui.purchaseButtonLabel,
			if isEnabled then LocalizationKeys.MerchantShop.Action.Purchase else LocalizationKeys.MerchantShop.Action.Unavailable
		)
	end
end

function MerchantShopController:_sanitizeAmountText()
	local ui = self:_ensureUi()
	local stock = self:_getSelectedStock()
	local requestedAmount = normalizeWhole(ui.amountBox.Text)
	local resolvedAmount = 0

	if stock > 0 then
		resolvedAmount = math.clamp(requestedAmount, 1, stock)
	end

	self._suppressAmountFocus = true
	ui.amountBox.Text = tostring(resolvedAmount)
	self._suppressAmountFocus = false

	return resolvedAmount
end

function MerchantShopController:_renderViewport()
	local ui = self:_ensureUi()
	local viewportFrame = ui.viewportFrame
	if not viewportFrame then
		return
	end

	local potionConfig = self:_getSelectedPotionConfig()
	local bundleModel = if potionConfig then PotionPresentation.GetBundleModel(potionConfig) else nil
	local rendered = ViewportModelRenderer.RenderPotion(viewportFrame, bundleModel)
	viewportFrame.Visible = rendered
	if not rendered then
		ViewportModelRenderer.Clear(viewportFrame)
	end
end

function MerchantShopController:_clearViewport()
	local ui = self:_ensureUi()
	local viewportFrame = ui.viewportFrame
	if not viewportFrame then
		return
	end

	ViewportModelRenderer.Clear(viewportFrame)
	viewportFrame.Visible = false
end

function MerchantShopController:_hideMessage()
	local ui = self:_ensureUi()
	ui.messageRoot.Visible = false
end

function MerchantShopController:_showMessage(title: string, message: string)
	local ui = self:_ensureUi()
	ui.messageRoot.Visible = true
	if ui.messageTitle then
		TranslationHelper.setLiteralText(ui.messageTitle, title)
	end
	if ui.messageDescription then
		TranslationHelper.setLiteralText(ui.messageDescription, message)
	end
end

function MerchantShopController:_showFailureMessage(message: string)
	self:_showMessage(TranslationHelper.formatByKey(LocalizationKeys.MerchantShop.Message.PurchaseFailedTitle), message)
end

function MerchantShopController:_refreshTimeShards()
	local ui = self:_ensureUi()
	local label = ui.timeShardsLabel
	if not label then
		return
	end

	local stateValue = if TIME_SHARDS_KEY then DataController:Get(TIME_SHARDS_KEY) else nil
	local normalizedState = TimeShardState.Normalize(stateValue)
	TranslationHelper.setLiteralText(label, formatTimeShards(normalizedState.balance))
end

function MerchantShopController:_refreshText()
	local ui = self:_ensureUi()
	local shopState = self._shopState or buildEmptyState()
	if not shopState.isActive then
		TranslationHelper.setKeyText(ui.itemName, LocalizationKeys.MerchantShop.State.UnavailableName)
		TranslationHelper.setKeyText(
			ui.itemDescLabel,
			if shopState.nextAppearsAt > 0
				then LocalizationKeys.MerchantShop.Message.ReturnsIn
				else LocalizationKeys.MerchantShop.Message.NotHere,
			{ Countdown = formatCountdown(shopState.nextAppearsAt) }
		)
		TranslationHelper.setKeyText(ui.stocksLabel, LocalizationKeys.MerchantShop.State.ReturnsSoon)
		TranslationHelper.setLiteralText(ui.priceLabel, formatCost(0))
		self:_setPurchaseEnabled(false)
		return
	end

	local entry = self:_getSelectedEntry()
	local stock = self:_getSelectedStock()
	local amount = self:_sanitizeAmountText()
	local totalPrice = if entry then MerchantShopConfig.GetPriceInTimeShards(entry.potionId) * amount else 0
	local stockCap = if entry then MerchantShopConfig.GetMaxStockForPotionId(entry.potionId) else 0
	local departureText = formatCountdown(shopState.departsAt)

	if entry then
		TranslationHelper.setSourceText(ui.itemName, entry.shopLabel)
		TranslationHelper.setSourceText(ui.itemDescLabel, entry.description)
		TranslationHelper.setKeyText(ui.stocksLabel, LocalizationKeys.MerchantShop.Common.StockSummary, {
			Stock = tostring(stock),
			StockCap = tostring(stockCap),
			DepartureTime = departureText,
		})
	else
		TranslationHelper.setKeyText(ui.itemName, LocalizationKeys.MerchantShop.State.StockEmptyName)
		TranslationHelper.setKeyText(ui.itemDescLabel, LocalizationKeys.MerchantShop.State.StockEmptyDesc, {
			DepartureTime = departureText,
		})
		TranslationHelper.setKeyText(ui.stocksLabel, LocalizationKeys.MerchantShop.Common.LeavesIn, {
			DepartureTime = departureText,
		})
	end
	TranslationHelper.setLiteralText(ui.priceLabel, formatCost(totalPrice))
	self:_setPurchaseEnabled(entry ~= nil and stock > 0)
end

function MerchantShopController:_refreshButtonStates()
	for potionId, button in pairs(self._runtimeButtonsByPotionId) do
		if button:IsA("ImageButton") then
			button.ImageTransparency = if potionId == self._selectedPotionId then 0 else 0.2
		end
	end
end

function MerchantShopController:_refreshVisibleButtons()
	local layoutOrder = 1
	local shopState = self._shopState or buildEmptyState()
	for _, entry in ipairs(MerchantShopConfig.GetAll()) do
		local button = self._runtimeButtonsByPotionId[entry.potionId]
		if button then
			local isVisible = shopState.isActive and normalizeWhole(shopState.stockByPotionId[entry.potionId]) > 0
			button.Visible = isVisible
			button.Active = isVisible
			button.AutoButtonColor = false
			if isVisible then
				button.LayoutOrder = layoutOrder
				layoutOrder += 1
			end
		end
	end

	self:_refreshButtonStates()
end

function MerchantShopController:_findSelectableEntry(preferredPotionId: string?): MerchantShopConfig.MerchantShopEntry?
	local visibleEntries = self:_getVisibleEntries()
	if #visibleEntries == 0 then
		return nil
	end

	if preferredPotionId then
		for _, entry in ipairs(visibleEntries) do
			if entry.potionId == preferredPotionId then
				return entry
			end
		end
	end

	if self._selectedPotionId then
		for _, entry in ipairs(visibleEntries) do
			if entry.potionId == self._selectedPotionId then
				return entry
			end
		end
	end

	return visibleEntries[1]
end

function MerchantShopController:_applySoldOutState()
	local ui = self:_ensureUi()
	self._selectedPotionId = nil
	self:_refreshButtonStates()
	self:_clearViewport()

	self._suppressAmountFocus = true
	ui.amountBox.Text = "0"
	self._suppressAmountFocus = false

	self:_refreshText()
	self:_showMessage(
		TranslationHelper.formatByKey(LocalizationKeys.MerchantShop.Message.OutOfStockTitle),
		TranslationHelper.formatByKey(LocalizationKeys.MerchantShop.Message.OutOfStockBody)
	)
end

function MerchantShopController:_applyInactiveState()
	local ui = self:_ensureUi()
	self._selectedPotionId = nil
	self:_refreshVisibleButtons()
	self:_clearViewport()

	self._suppressAmountFocus = true
	ui.amountBox.Text = "0"
	self._suppressAmountFocus = false

	self:_refreshText()
	self:_showMessage(
		TranslationHelper.formatByKey(LocalizationKeys.MerchantShop.Message.UnavailableTitle),
		if (self._shopState or buildEmptyState()).nextAppearsAt > 0
			then TranslationHelper.formatByKey(LocalizationKeys.MerchantShop.Message.ReturnsIn, {
				Countdown = formatCountdown((self._shopState or buildEmptyState()).nextAppearsAt),
			})
			else TranslationHelper.formatByKey(LocalizationKeys.MerchantShop.Message.NotHere)
	)
end

function MerchantShopController:_applySelection(potionId: string)
	local entry = MerchantShopConfig.GetByPotionId(potionId)
	if not entry or normalizeWhole((self._shopState or buildEmptyState()).stockByPotionId[entry.potionId]) <= 0 then
		local fallbackEntry = self:_findSelectableEntry(potionId)
		if fallbackEntry then
			self:_applySelection(fallbackEntry.potionId)
		else
			self:_applySoldOutState()
		end
		return
	end

	self._selectedPotionId = entry.potionId
	self:_refreshButtonStates()

	local ui = self:_ensureUi()
	local stock = self:_getSelectedStock()
	self._suppressAmountFocus = true
	ui.amountBox.Text = tostring(if stock > 0 then 1 else 0)
	self._suppressAmountFocus = false

	self:_hideMessage()
	self:_refreshText()
	self:_renderViewport()
end

function MerchantShopController:_applyShopState(shopState: any, preferredPotionId: string?)
	self._shopState = self:_cloneShopState(shopState)
	self:_refreshVisibleButtons()

	if not self._shopState.isActive then
		self:_applyInactiveState()
		return
	end

	local entry = self:_findSelectableEntry(preferredPotionId)
	if entry then
		self:_applySelection(entry.potionId)
	else
		self:_applySoldOutState()
	end
end

function MerchantShopController:_buildSelectionButtons()
	local ui = self:_ensureUi()
	if next(self._runtimeButtonsByPotionId) ~= nil then
		return
	end

	for _, entry in ipairs(MerchantShopConfig.GetAll()) do
		local button = ui.buttonTemplate:Clone()
		button.Name = string.format("MerchantShop_%s", entry.potionId)
		button.Visible = false
		button.Active = false
		button.AutoButtonColor = false

		local content = button:FindFirstChild("Content")
		if content and content:IsA("TextLabel") then
			TranslationHelper.setSourceText(content, entry.shopLabel)
		end

		button.Parent = ui.selectionScrollingFrame
		self._runtimeButtonsByPotionId[entry.potionId] = button

		UIController:CreateButton(button, function()
			MerchantShopController:_applySelection(entry.potionId)
		end)
	end
end

function MerchantShopController:_requestShopState(): boolean
	if not self:_ensureRemotes() then
		return false
	end

	local result = self:_invokeRemote(self._remotes.getShopState)
	if typeof(result) ~= "table" then
		return false
	end

	if typeof(result.shopState) == "table" then
		self:_applyShopState(result.shopState, self._selectedPotionId)
		return true
	end

	return result.ok == true
end

function MerchantShopController:_purchaseSelectedItem()
	if not self._isShopOpen then
		return
	end
	if not self:_ensureRemotes() then
		self:_showFailureMessage(TranslationHelper.formatByKey(LocalizationKeys.MerchantShop.Message.NotReady))
		return
	end

	local entry = self:_getSelectedEntry()
	if not entry then
		if (self._shopState or buildEmptyState()).isActive then
			self:_applySoldOutState()
		else
			self:_applyInactiveState()
		end
		return
	end

	local quantity = self:_sanitizeAmountText()
	local result = self:_invokeRemote(self._remotes.purchaseShopItem, {
		potionId = entry.potionId,
		quantity = quantity,
	})
	if typeof(result) ~= "table" then
		self:_showFailureMessage(TranslationHelper.formatByKey(LocalizationKeys.MerchantShop.Message.PurchaseUnavailable))
		return
	end

	if typeof(result.shopState) == "table" then
		self:_applyShopState(result.shopState, entry.potionId)
	end

	if result.ok == true then
		self:_refreshTimeShards()
		if self._selectedPotionId ~= nil then
			self:_hideMessage()
		end
		return
	end

	self:_showFailureMessage(
		tostring(result.message or TranslationHelper.formatByKey(LocalizationKeys.MerchantShop.Message.PurchaseUnavailable))
	)
end

function MerchantShopController:_bindUi()
	local ui = self:_ensureUi()
	self:_buildSelectionButtons()
	self:_hideMessage()
	self:_clearViewport()
	self:_refreshVisibleButtons()
	self:_refreshTimeShards()

	UIController:CreateButton(ui.purchaseButton, function()
		MerchantShopController:_purchaseSelectedItem()
	end)

	ui.amountBox.FocusLost:Connect(function(enterPressed: boolean)
		if self._suppressAmountFocus then
			return
		end

		self:_sanitizeAmountText()
		self:_refreshText()
		if enterPressed then
			self:_purchaseSelectedItem()
		end
	end)

	if ui.messageClose then
		UIController:CreateButton(ui.messageClose, function()
			MerchantShopController:_hideMessage()
		end)
	end
end

function MerchantShopController:_startRefreshWatcher()
	if self._refreshConnection then
		self._refreshConnection:Disconnect()
		self._refreshConnection = nil
	end

	self._refreshConnection = RunService.Heartbeat:Connect(function()
		if not self._isShopOpen then
			return
		end

		local now = getUtcNowSeconds()
		if self._lastCountdownSecond ~= now then
			self._lastCountdownSecond = now
			self:_refreshText()
		end

		local shopState = self._shopState
		if not shopState then
			return
		end

		local transitionAt = if shopState.isActive then shopState.departsAt else shopState.nextAppearsAt
		if transitionAt <= 0 or now < transitionAt then
			return
		end

		self:_requestShopState()
	end)
end

function MerchantShopController:_stopRefreshWatcher()
	if self._refreshConnection then
		self._refreshConnection:Disconnect()
		self._refreshConnection = nil
	end
end

function MerchantShopController:_handleShopPrepared(frameName: string, root: GuiObject)
	if frameName ~= SHOP_FRAME_NAME or not root.Parent then
		return
	end

	self._isShopOpen = true
	self._lastCountdownSecond = -1
	self:_hideMessage()
	self:_refreshTimeShards()
	if not self:_requestShopState() then
		self:_applyShopState(buildEmptyState())
		self:_showFailureMessage("The merchant is not ready right now.")
	end
	self:_startRefreshWatcher()
end

function MerchantShopController:_handleShopClosed(frameName: string)
	if frameName ~= SHOP_FRAME_NAME then
		return
	end

	self._isShopOpen = false
	self._lastCountdownSecond = -1
	self:_stopRefreshWatcher()
	self:_hideMessage()
	self:_clearViewport()
	self._shopState = nil
	self._selectedPotionId = nil

	local ui = self:_ensureUi()
	self._suppressAmountFocus = true
	ui.amountBox.Text = ""
	self._suppressAmountFocus = false
end

function MerchantShopController:OnStart()
	if self._started then
		return
	end

	self._started = true
	self:_ensureUi()
	self:_bindUi()

	DataController.DataReceived:Connect(function()
		self:_refreshTimeShards()
	end)

	DataController.DataUpdated:Connect(function(key)
		if key == TIME_SHARDS_KEY then
			self:_refreshTimeShards()
		end
	end)

	MerchantPresentationController.FramePrepared:Connect(function(frameName: string, root: GuiObject)
		self:_handleShopPrepared(frameName, root)
	end)

	MerchantPresentationController.Closed:Connect(function(frameName: string)
		self:_handleShopClosed(frameName)
	end)
end

return MerchantShopController
