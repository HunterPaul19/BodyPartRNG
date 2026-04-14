local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Globals = require(ReplicatedStorage.Lists.Globals)
local MerchantShopConfig = require(ReplicatedStorage.Shared.Config.MerchantShopConfig)
local PotionConfig = require(ReplicatedStorage.Shared.Config.PotionConfig)
local PotionPresentation = require(ReplicatedStorage.Shared.UI.PotionPresentation)
local ViewportModelRenderer = require(ReplicatedStorage.Shared.UI.ViewportModelRenderer)

local MerchantPresentationController = require(script.Parent.MerchantPresentationController)
local UIController = require(script.Parent.UIController)

local LOCAL_PLAYER = Players.LocalPlayer
local REMOTES_FOLDER_NAME = "Remotes"
local MERCHANT_SHOP_FOLDER_NAME = "MerchantShop"
local GET_SHOP_STATE_REMOTE_NAME = "GetShopState"
local PURCHASE_SHOP_ITEM_REMOTE_NAME = "PurchaseShopItem"
local SHOP_FRAME_NAME = "ShopUI"
local STOCK_CAP = 10

type MerchantShopState = {
	cycleId: number,
	refreshesAt: number,
	stockByPotionId: { [string]: number },
}

type MerchantShopUi = {
	root: GuiObject,
	itemName: TextLabel,
	itemDescLabel: TextLabel,
	stocksLabel: TextLabel,
	priceLabel: TextLabel,
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
	_runtimeButtonsByPotionId = {} :: { [string]: GuiButton },
	_remotes = nil,
	_shopState = nil :: MerchantShopState?,
	_selectedPotionId = nil :: string?,
	_isShopOpen = false,
	_refreshConnection = nil :: RBXScriptConnection?,
	_suppressAmountFocus = false,
}

local function normalizeWhole(value: any): number
	return math.max(0, math.floor(tonumber(value) or 0))
end

local function buildEmptyState(): MerchantShopState
	local stockByPotionId = {}
	for _, entry in ipairs(MerchantShopConfig.GetAll()) do
		stockByPotionId[entry.potionId] = STOCK_CAP
	end

	return {
		cycleId = -1,
		refreshesAt = 0,
		stockByPotionId = stockByPotionId,
	}
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
		warn(string.format("[MerchantShopController] Remote %s failed: %s", remote.Name, tostring(result)))
		return nil
	end

	return result
end

function MerchantShopController:_cloneShopState(shopState: any): MerchantShopState
	local cloned = buildEmptyState()
	if typeof(shopState) ~= "table" then
		return cloned
	end

	cloned.cycleId = math.floor(tonumber(shopState.cycleId) or cloned.cycleId)
	cloned.refreshesAt = tonumber(shopState.refreshesAt) or cloned.refreshesAt

	if typeof(shopState.stockByPotionId) == "table" then
		for _, entry in ipairs(MerchantShopConfig.GetAll()) do
			cloned.stockByPotionId[entry.potionId] = math.clamp(normalizeWhole(shopState.stockByPotionId[entry.potionId]), 0, STOCK_CAP)
		end
	end

	return cloned
end

function MerchantShopController:_getSelectedEntry()
	local potionId = self._selectedPotionId or "luck"
	return MerchantShopConfig.GetByPotionId(potionId) or MerchantShopConfig.GetByPotionId("luck")
end

function MerchantShopController:_getSelectedPotionConfig()
	local entry = self:_getSelectedEntry()
	return if entry then PotionConfig.Get(entry.potionId) else nil
end

function MerchantShopController:_getSelectedStock(): number
	local entry = self:_getSelectedEntry()
	local shopState = self._shopState or buildEmptyState()
	if not entry then
		return 0
	end

	return math.clamp(normalizeWhole(shopState.stockByPotionId[entry.potionId]), 0, STOCK_CAP)
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
	local rendered = ViewportModelRenderer.RenderBundle(viewportFrame, bundleModel)
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

function MerchantShopController:_showFailureMessage(message: string)
	local ui = self:_ensureUi()
	ui.messageRoot.Visible = true
	if ui.messageTitle then
		ui.messageTitle.Text = "Purchase Failed"
	end
	if ui.messageDescription then
		ui.messageDescription.Text = message
	end
end

function MerchantShopController:_refreshText()
	local ui = self:_ensureUi()
	local entry = self:_getSelectedEntry()
	local potionConfig = self:_getSelectedPotionConfig()
	local stock = self:_getSelectedStock()
	local amount = self:_sanitizeAmountText()
	local totalPrice = if potionConfig then math.max(0, potionConfig.buyPrice) * amount else 0

	ui.itemName.Text = if entry then entry.shopLabel else "Item Name"
	ui.itemDescLabel.Text = if entry then entry.description else "Item Description"
	ui.stocksLabel.Text = string.format("[Stock: %d/%d]", stock, STOCK_CAP)
	ui.priceLabel.Text = string.format("%s$ in total", Globals.formatNumber(totalPrice))
	if ui.purchaseButtonLabel then
		ui.purchaseButtonLabel.Text = "Purchase"
	end
end

function MerchantShopController:_applySelection(potionId: string)
	local entry = MerchantShopConfig.GetByPotionId(potionId)
	if not entry then
		return
	end

	self._selectedPotionId = entry.potionId
	self:_refreshButtonStates()

	local ui = self:_ensureUi()
	local stock = self:_getSelectedStock()
	self._suppressAmountFocus = true
	ui.amountBox.Text = tostring(if stock > 0 then 1 else 0)
	self._suppressAmountFocus = false

	self:_refreshText()
	self:_renderViewport()
end

function MerchantShopController:_refreshButtonStates()
	for potionId, button in pairs(self._runtimeButtonsByPotionId) do
		if button:IsA("ImageButton") then
			button.ImageTransparency = if potionId == self._selectedPotionId then 0 else 0.2
		end
	end
end

function MerchantShopController:_buildSelectionButtons()
	local ui = self:_ensureUi()
	if next(self._runtimeButtonsByPotionId) ~= nil then
		return
	end

	local layoutOrder = 1
	for _, entry in ipairs(MerchantShopConfig.GetAll()) do
		local button = ui.buttonTemplate:Clone()
		button.Name = string.format("MerchantShop_%s", entry.potionId)
		button.Visible = true
		button.Active = true
		button.AutoButtonColor = false
		button.LayoutOrder = layoutOrder
		layoutOrder += 1

		local content = button:FindFirstChild("Content")
		if content and content:IsA("TextLabel") then
			content.Text = entry.shopLabel
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
		self._shopState = self:_cloneShopState(result.shopState)
		return true
	end

	return result.ok == true
end

function MerchantShopController:_purchaseSelectedItem()
	if not self._isShopOpen then
		return
	end
	if not self:_ensureRemotes() then
		self:_showFailureMessage("The merchant is not ready right now.")
		return
	end

	local entry = self:_getSelectedEntry()
	if not entry then
		self:_showFailureMessage("Select an item first.")
		return
	end

	local quantity = self:_sanitizeAmountText()
	local result = self:_invokeRemote(self._remotes.purchaseShopItem, {
		potionId = entry.potionId,
		quantity = quantity,
	})
	if typeof(result) ~= "table" then
		self:_showFailureMessage("The purchase could not be completed.")
		return
	end

	if typeof(result.shopState) == "table" then
		self._shopState = self:_cloneShopState(result.shopState)
	end

	if result.ok == true then
		self:_hideMessage()
		self:_refreshText()
		self:_renderViewport()
		return
	end

	self:_refreshText()
	self:_renderViewport()
	self:_showFailureMessage(tostring(result.message or "The purchase could not be completed."))
end

function MerchantShopController:_bindUi()
	local ui = self:_ensureUi()
	self:_buildSelectionButtons()
	self:_hideMessage()
	self:_clearViewport()

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

		local shopState = self._shopState
		if not shopState or shopState.refreshesAt <= 0 then
			return
		end

		if Workspace:GetServerTimeNow() < shopState.refreshesAt then
			return
		end

		if self:_requestShopState() then
			local entry = self:_getSelectedEntry()
			self:_applySelection(if entry then entry.potionId else "luck")
		end
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
	self:_hideMessage()
	self:_requestShopState()
	self:_applySelection("luck")
	self:_startRefreshWatcher()
end

function MerchantShopController:_handleShopClosed(frameName: string)
	if frameName ~= SHOP_FRAME_NAME then
		return
	end

	self._isShopOpen = false
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

	MerchantPresentationController.FramePrepared:Connect(function(frameName: string, root: GuiObject)
		self:_handleShopPrepared(frameName, root)
	end)

	MerchantPresentationController.Closed:Connect(function(frameName: string)
		self:_handleShopClosed(frameName)
	end)
end

return MerchantShopController
