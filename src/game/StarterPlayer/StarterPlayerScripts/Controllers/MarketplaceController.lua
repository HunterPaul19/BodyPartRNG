local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FrameController = require(script.Parent.FrameController)
local UIController = require(script.Parent.UIController)
local Notify = require(ReplicatedStorage.Shared.UI.Notify)

local LOCAL_PLAYER = Players.LocalPlayer
local TAG_NAME = "marketplace"
local PRICE_LABEL_TAG_NAME = "marketplace_price_label"
local FRAME_TAG_NAME = "frame"
local CLOSE_TAG_NAME = "close"
local MODAL_NAME = "Gifting"
local STORE_NAME = "RobuxStore"
local REMOTES_FOLDER_NAME = "Remotes"
local MARKETPLACE_FOLDER_NAME = "Marketplace"
local GET_OFFER_INFO_REMOTE_NAME = "GetOfferInfo"
local GET_OFFER_PRESENTATIONS_REMOTE_NAME = "GetOfferPresentations"
local PROMPT_OFFER_PURCHASE_REMOTE_NAME = "PromptOfferPurchase"
local PROMPT_GIFT_PURCHASE_REMOTE_NAME = "PromptGiftPurchase"
local MARKETPLACE_UPDATED_REMOTE_NAME = "Updated"
local OFFER_KEY_ATTR = "MarketplaceOfferKey"
local IS_GIFT_ATTR = "MarketplaceIsGift"
local GIFT_RECIPIENT_USER_ID_ATTR = "MarketplaceGiftRecipientUserId"
local THUMBNAIL_TYPE = Enum.ThumbnailType.HeadShot
local THUMBNAIL_SIZE = Enum.ThumbnailSize.Size150x150

local MarketplaceController = {}

local function normalizeString(value: any): string
	if typeof(value) ~= "string" then
		return ""
	end

	local trimmed = string.match(value, "^%s*(.-)%s*$")
	if not trimmed or trimmed == "" then
		return ""
	end

	return trimmed
end

local function formatWholeRobux(value: number): string
	local digits = tostring(math.max(0, math.floor(value)))
	local length = #digits
	if length <= 3 then
		return digits
	end

	local parts = table.create(math.ceil(length / 3))
	local index = length
	while index > 0 do
		local startIndex = math.max(1, index - 2)
		table.insert(parts, 1, string.sub(digits, startIndex, index))
		index = startIndex - 1
	end

	return table.concat(parts, ",")
end

local function getProductInfoType(saleKind: string): Enum.InfoType?
	if saleKind == "pass" then
		return Enum.InfoType.GamePass
	end
	if saleKind == "product" then
		return Enum.InfoType.Product
	end

	return nil
end

local function getMarketplaceRemotesFolder(): Folder
	local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, 30)
	assert(remotesFolder and remotesFolder:IsA("Folder"), "ReplicatedStorage.Remotes is missing.")
	local marketplaceFolder = remotesFolder:WaitForChild(MARKETPLACE_FOLDER_NAME, 30)
	assert(marketplaceFolder and marketplaceFolder:IsA("Folder"), "ReplicatedStorage.Remotes.Marketplace is missing.")
	return marketplaceFolder
end

local function getRemoteFunction(name: string): RemoteFunction
	local marketplaceFolder = getMarketplaceRemotesFolder()
	local remote = marketplaceFolder:WaitForChild(name, 30)
	assert(remote and remote:IsA("RemoteFunction"), string.format("Marketplace remote %s is missing.", name))
	return remote
end

local function sortPlayers(playersList: { Player })
	table.sort(playersList, function(a: Player, b: Player)
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
end

local function buildGiftPromptText(displayName: string, hasRecipients: boolean): string
	local resolvedName = normalizeString(displayName)
	if resolvedName == "" then
		resolvedName = "Gift"
	end

	if hasRecipients then
		return string.format("Choose player to receive gift: %s", resolvedName)
	end

	return string.format("No other players available to receive gift: %s", resolvedName)
end

function MarketplaceController:_ensureState()
	if self._started then
		return
	end

	self._started = true
	self._playerGui = nil
	self._giftRoot = nil
	self._buttonConnections = {}
	self._trackedButtons = {}
	self._giftButtonConnections = {}
	self._giftOffer = nil
	self._giftReturnFrameName = nil
	self._giftRowsByUserId = {}
	self._thumbnailRequestIds = {}
	self._remotes = nil
	self._marketplaceUpdatedConnection = nil
	self._ui = {}
	self._trackedPriceLabels = {}
	self._authoredPriceTextByLabel = {}
	self._priceRefreshQueued = false
	self._pendingPriceOfferKeys = {}
	self._storeVisibilityConnections = {}
end

function MarketplaceController:_getPlayerGui(): PlayerGui
	self:_ensureState()
	if self._playerGui and self._playerGui.Parent then
		return self._playerGui
	end

	self._playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	return self._playerGui
end

function MarketplaceController:_getRemotes()
	self:_ensureState()
	if self._remotes then
		return self._remotes
	end

	self._remotes = {
		getOfferInfo = getRemoteFunction(GET_OFFER_INFO_REMOTE_NAME),
		getOfferPresentations = getRemoteFunction(GET_OFFER_PRESENTATIONS_REMOTE_NAME),
		promptOfferPurchase = getRemoteFunction(PROMPT_OFFER_PURCHASE_REMOTE_NAME),
		promptGiftPurchase = getRemoteFunction(PROMPT_GIFT_PURCHASE_REMOTE_NAME),
		marketplaceUpdated = getMarketplaceRemotesFolder():WaitForChild(MARKETPLACE_UPDATED_REMOTE_NAME, 30),
	}

	assert(
		self._remotes.marketplaceUpdated and self._remotes.marketplaceUpdated:IsA("RemoteEvent"),
		"Marketplace remote Updated is missing."
	)

	return self._remotes
end

function MarketplaceController:_tagCloseButton(root: GuiObject)
	local closeButton = root:FindFirstChild("CloseButton", true)
	if closeButton and closeButton:IsA("GuiButton") then
		CollectionService:AddTag(closeButton, CLOSE_TAG_NAME)
	end
end

function MarketplaceController:_ensureRuntimeModal(mainInterface: ScreenGui, modalRoot: ScreenGui): GuiObject
	local existing = modalRoot:FindFirstChild(MODAL_NAME)
	if existing and existing:IsA("GuiObject") then
		existing.Visible = false
		CollectionService:AddTag(existing, FRAME_TAG_NAME)
		self:_tagCloseButton(existing)
		return existing
	end

	local source = mainInterface:FindFirstChild(MODAL_NAME)
	if not (source and source:IsA("GuiObject")) then
		error("PlayerGui.MainInterface.Gifting is missing.")
	end

	local clone = source:Clone()
	clone.Name = MODAL_NAME
	clone.Visible = false
	clone.Parent = modalRoot
	CollectionService:AddTag(clone, FRAME_TAG_NAME)
	self:_tagCloseButton(clone)

	return clone
end

function MarketplaceController:_ensurePromptLabel(line: Instance?): TextLabel?
	if not (line and line:IsA("GuiObject")) then
		return nil
	end

	local promptLabel = line:FindFirstChild("PromptLabel")
	if promptLabel and promptLabel:IsA("TextLabel") then
		return promptLabel
	end
	if promptLabel then
		promptLabel:Destroy()
	end

	promptLabel = Instance.new("TextLabel")
	promptLabel.Name = "PromptLabel"
	promptLabel.BackgroundTransparency = 1
	promptLabel.Size = UDim2.fromScale(1, 1)
	promptLabel.Position = UDim2.fromScale(0, 0)
	promptLabel.Text = "Choose player to receive gift"
	promptLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	promptLabel.TextScaled = true
	promptLabel.Font = Enum.Font.GothamBold
	promptLabel.Parent = line

	return promptLabel
end

function MarketplaceController:_cacheUi()
	local playerGui = self:_getPlayerGui()
	local mainInterface = playerGui:WaitForChild("MainInterface", 30)
	local modalRoot = playerGui:WaitForChild("ModalRoot", 30)
	assert(mainInterface and mainInterface:IsA("ScreenGui"), "PlayerGui.MainInterface is missing.")
	assert(modalRoot and modalRoot:IsA("ScreenGui"), "PlayerGui.ModalRoot is missing.")

	local giftRoot = self:_ensureRuntimeModal(mainInterface, modalRoot)
	local topbar = giftRoot:WaitForChild("Topbar", 30)
	local scrollingFrame = giftRoot:WaitForChild("ScrollingFrame", 30)
	local template = scrollingFrame:WaitForChild("Template", 30)
	local line = giftRoot:FindFirstChild("Line")
	local header = topbar:WaitForChild("Header", 30)
	local bottomBar = topbar:FindFirstChild("BottomBar")
	local bottomBarContent = bottomBar and bottomBar:FindFirstChild("Content")

	assert(topbar and topbar:IsA("Frame"), "Gifting.Topbar is missing.")
	assert(scrollingFrame and scrollingFrame:IsA("ScrollingFrame"), "Gifting.ScrollingFrame is missing.")
	assert(template and template:IsA("Frame"), "Gifting.ScrollingFrame.Template is missing.")
	assert(header and header:IsA("TextLabel"), "Gifting.Topbar.Header is missing.")

	local promptLabel = nil
	if bottomBarContent and bottomBarContent:IsA("TextLabel") then
		promptLabel = bottomBarContent
	else
		promptLabel = self:_ensurePromptLabel(line)
	end
	self._giftRoot = giftRoot
	self._ui = {
		header = header,
		promptLabel = promptLabel,
		scrollingFrame = scrollingFrame,
		template = template,
	}
end

function MarketplaceController:_getOfferInfo(offerKey: string)
	local offerKeyString = normalizeString(offerKey)
	if offerKeyString == "" then
		return nil, "MarketplaceOfferKey is required."
	end

	local remotes = self:_getRemotes()
	local ok, result = pcall(function()
		return remotes.getOfferInfo:InvokeServer(offerKeyString)
	end)
	if not ok then
		return nil, tostring(result)
	end
	if typeof(result) ~= "table" then
		return nil, "Marketplace lookup returned an invalid response."
	end
	if result.ok ~= true or typeof(result.offer) ~= "table" then
		return nil, tostring(result.message or "That offer does not exist.")
	end

	return result.offer, nil
end

function MarketplaceController:_rememberAuthoredPriceText(label: TextLabel)
	if self._authoredPriceTextByLabel[label] == nil then
		self._authoredPriceTextByLabel[label] = label.Text
	end
end

function MarketplaceController:_restoreAuthoredPriceText(label: TextLabel)
	self:_rememberAuthoredPriceText(label)
	local authoredText = self._authoredPriceTextByLabel[label]
	if typeof(authoredText) == "string" then
		label.Text = authoredText
	end
end

function MarketplaceController:_setPriceLabelText(label: TextLabel, text: string)
	if not (label and label:IsA("TextLabel")) then
		return
	end

	label.Text = text
end

function MarketplaceController:_getTrackedPriceLabelsForOffer(offerKey: string): { TextLabel }
	local labels = {}
	for label in pairs(self._trackedPriceLabels) do
		if label.Parent and normalizeString(label:GetAttribute(OFFER_KEY_ATTR)) == offerKey then
			table.insert(labels, label)
		end
	end
	return labels
end

function MarketplaceController:_collectTrackedPriceOfferKeys(filterOfferKeys: { [string]: boolean }?): { string }
	local offerKeys = {}
	local seen = {}

	for label in pairs(self._trackedPriceLabels) do
		if label.Parent then
			local offerKey = normalizeString(label:GetAttribute(OFFER_KEY_ATTR))
			if offerKey ~= "" and not seen[offerKey] and (filterOfferKeys == nil or filterOfferKeys[offerKey] == true) then
				seen[offerKey] = true
				table.insert(offerKeys, offerKey)
			end
		end
	end

	table.sort(offerKeys)
	return offerKeys
end

function MarketplaceController:_getOfferPresentations(offerKeys: { string })
	if #offerKeys == 0 then
		return {}, nil
	end

	local remotes = self:_getRemotes()
	local ok, result = pcall(function()
		return remotes.getOfferPresentations:InvokeServer(offerKeys)
	end)
	if not ok then
		return nil, tostring(result)
	end
	if typeof(result) ~= "table" or result.ok ~= true or typeof(result.offers) ~= "table" then
		return nil, "Marketplace label lookup returned an invalid response."
	end

	return result.offers, nil
end

function MarketplaceController:_resolvePriceLabelText(presentation: any): (string?, string?)
	if typeof(presentation) ~= "table" then
		return nil, "Marketplace presentation data is invalid."
	end
	if presentation.isOwned == true then
		return "Owned", nil
	end
	if presentation.exists ~= true then
		return nil, string.format("Marketplace offer '%s' does not exist.", tostring(presentation.offerKey))
	end
	if presentation.selfConfigured ~= true then
		return nil, string.format("Marketplace offer '%s' is missing self-purchase configuration.", tostring(presentation.offerKey))
	end

	local saleKind = normalizeString(presentation.saleKind)
	local saleRobloxId = tonumber(presentation.saleRobloxId)
	local infoType = getProductInfoType(saleKind)
	if saleRobloxId == nil or infoType == nil then
		return nil, string.format("Marketplace offer '%s' returned invalid sale metadata.", tostring(presentation.offerKey))
	end

	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(math.floor(saleRobloxId), infoType)
	end)
	if not ok then
		return nil, tostring(info)
	end
	if typeof(info) ~= "table" then
		return nil, "MarketplaceService:GetProductInfo returned invalid metadata."
	end

	local priceInRobux = tonumber(info.PriceInRobux)
	if priceInRobux == nil then
		return nil, string.format("Marketplace offer '%s' does not currently expose a Robux price.", tostring(presentation.offerKey))
	end

	return string.format("%s R$", formatWholeRobux(priceInRobux)), nil
end

function MarketplaceController:_requestPriceLabelRefresh(offerKeys: { string }?)
	if typeof(offerKeys) == "table" then
		for _, offerKey in ipairs(offerKeys) do
			local normalizedOfferKey = normalizeString(offerKey)
			if normalizedOfferKey ~= "" then
				self._pendingPriceOfferKeys[normalizedOfferKey] = true
			end
		end
	else
		self._pendingPriceOfferKeys = {}
	end

	if self._priceRefreshQueued then
		return
	end

	self._priceRefreshQueued = true
	task.defer(function()
		self:_flushPendingPriceLabelRefresh()
	end)
end

function MarketplaceController:_flushPendingPriceLabelRefresh()
	self._priceRefreshQueued = false

	local filterOfferKeys = nil
	if next(self._pendingPriceOfferKeys) ~= nil then
		filterOfferKeys = self._pendingPriceOfferKeys
	end
	self._pendingPriceOfferKeys = {}

	local offerKeys = self:_collectTrackedPriceOfferKeys(filterOfferKeys)
	if #offerKeys == 0 then
		return
	end

	local presentations, err = self:_getOfferPresentations(offerKeys)
	if presentations == nil then
		warn(string.format("[MarketplaceController] Failed to fetch marketplace label data: %s", tostring(err)))
		for label in pairs(self._trackedPriceLabels) do
			if label.Parent then
				local offerKey = normalizeString(label:GetAttribute(OFFER_KEY_ATTR))
				if filterOfferKeys == nil or filterOfferKeys[offerKey] == true then
					self:_restoreAuthoredPriceText(label)
				end
			end
		end
		return
	end

	for _, offerKey in ipairs(offerKeys) do
		local labels = self:_getTrackedPriceLabelsForOffer(offerKey)
		local presentation = presentations[offerKey]
		local resolvedText, resolveError = self:_resolvePriceLabelText(presentation)

		if resolvedText then
			for _, label in ipairs(labels) do
				self:_setPriceLabelText(label, resolvedText)
			end
		else
			if resolveError then
				warn(string.format(
					"[MarketplaceController] Failed to resolve marketplace label '%s': %s",
					offerKey,
					tostring(resolveError)
				))
			end
			for _, label in ipairs(labels) do
				self:_restoreAuthoredPriceText(label)
			end
		end
	end
end

function MarketplaceController:_bindPriceLabel(instance: Instance)
	local playerGui = self:_getPlayerGui()
	if not (instance and instance:IsA("TextLabel") and instance:IsDescendantOf(playerGui)) then
		return
	end
	if self._trackedPriceLabels[instance] then
		return
	end

	self._trackedPriceLabels[instance] = true
	self:_rememberAuthoredPriceText(instance)
	self:_requestPriceLabelRefresh({ normalizeString(instance:GetAttribute(OFFER_KEY_ATTR)) })
end

function MarketplaceController:_unbindPriceLabel(instance: Instance)
	if instance and instance:IsA("TextLabel") then
		self._trackedPriceLabels[instance] = nil
		self._authoredPriceTextByLabel[instance] = nil
	end
end

function MarketplaceController:_refreshTaggedPriceLabels()
	local playerGui = self:_getPlayerGui()
	local activeLabels = {}
	for _, instance in ipairs(CollectionService:GetTagged(PRICE_LABEL_TAG_NAME)) do
		if instance:IsDescendantOf(playerGui) and instance:IsA("TextLabel") then
			activeLabels[instance] = true
			self:_bindPriceLabel(instance)
		end
	end

	for label in pairs(self._trackedPriceLabels) do
		if not activeLabels[label] or not label.Parent then
			self:_unbindPriceLabel(label)
		end
	end
end

function MarketplaceController:_trackStoreRoot(instance: Instance)
	if not (instance and instance:IsA("GuiObject") and instance.Name == STORE_NAME) then
		return
	end
	if self._storeVisibilityConnections[instance] then
		return
	end

	self._storeVisibilityConnections[instance] = instance:GetPropertyChangedSignal("Visible"):Connect(function()
		if instance.Visible then
			self:_requestPriceLabelRefresh()
		end
	end)

	if instance.Visible then
		self:_requestPriceLabelRefresh()
	end
end

function MarketplaceController:_untrackStoreRoot(instance: Instance)
	local connection = self._storeVisibilityConnections[instance]
	if connection then
		connection:Disconnect()
		self._storeVisibilityConnections[instance] = nil
	end
end

function MarketplaceController:_refreshTrackedStoreRoots()
	local playerGui = self:_getPlayerGui()
	local activeRoots = {}

	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant.Name == STORE_NAME and descendant:IsA("GuiObject") then
			activeRoots[descendant] = true
			self:_trackStoreRoot(descendant)
		end
	end

	for instance in pairs(self._storeVisibilityConnections) do
		if not activeRoots[instance] or not instance.Parent then
			self:_untrackStoreRoot(instance)
		end
	end
end

function MarketplaceController:_invokePromptOfferPurchase(offerKey: string): (boolean, string?, boolean)
	local remotes = self:_getRemotes()
	local ok, result = pcall(function()
		return remotes.promptOfferPurchase:InvokeServer(offerKey)
	end)
	if not ok then
		return false, tostring(result), false
	end
	if typeof(result) ~= "table" then
		return false, "Marketplace purchase returned an invalid response.", false
	end

	return result.ok == true, tostring(result.message or "Failed to open the purchase prompt."), result.promptOpened == true
end

function MarketplaceController:_invokePromptGiftPurchase(offerKey: string, recipientUserId: number): (boolean, string?)
	local remotes = self:_getRemotes()
	local ok, result = pcall(function()
		return remotes.promptGiftPurchase:InvokeServer({
			offerKey = offerKey,
			recipientUserId = recipientUserId,
		})
	end)
	if not ok then
		return false, tostring(result)
	end
	if typeof(result) ~= "table" then
		return false, "Gift purchase returned an invalid response."
	end

	return result.ok == true, tostring(result.message or "Failed to open the gift prompt.")
end

function MarketplaceController:_resolveGiftRecipientUserId(instance: Instance?): number?
	if not instance then
		return nil
	end

	local recipientUserId = tonumber(instance:GetAttribute(GIFT_RECIPIENT_USER_ID_ATTR))
	if recipientUserId ~= nil then
		return math.floor(recipientUserId)
	end

	local parent = instance.Parent
	if parent then
		recipientUserId = tonumber(parent:GetAttribute(GIFT_RECIPIENT_USER_ID_ATTR))
		if recipientUserId ~= nil then
			return math.floor(recipientUserId)
		end
	end

	return nil
end

function MarketplaceController:_setGiftHeader(displayName: string)
	local ui = self._ui
	if ui.header and ui.header:IsA("TextLabel") then
		ui.header.Text = displayName
	end

	if ui.promptLabel and ui.promptLabel:IsA("TextLabel") then
		ui.promptLabel.Text = buildGiftPromptText(displayName, true)
	end
end

function MarketplaceController:_clearGiftRows()
	local ui = self._ui
	local scrollingFrame = ui.scrollingFrame
	local template = ui.template
	if not (scrollingFrame and template) then
		return
	end

	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child:IsA("Frame") and child ~= template then
			child:Destroy()
		end
	end

	self._giftRowsByUserId = {}
	self._giftButtonConnections = {}
	self._thumbnailRequestIds = {}
	template.Visible = false
end

function MarketplaceController:_loadThumbnail(imageLabel: ImageLabel, player: Player)
	local requestId = (self._thumbnailRequestIds[player.UserId] or 0) + 1
	self._thumbnailRequestIds[player.UserId] = requestId
	imageLabel.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"

	task.spawn(function()
		local ok, content, isReady = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, THUMBNAIL_TYPE, THUMBNAIL_SIZE)
		end)
		if not ok or self._thumbnailRequestIds[player.UserId] ~= requestId or not imageLabel.Parent then
			return
		end
		if isReady == false or typeof(content) ~= "string" or content == "" then
			return
		end

		imageLabel.Image = content
	end)
end

function MarketplaceController:_buildGiftPlayerEntries()
	local ui = self._ui
	local template = ui.template
	local scrollingFrame = ui.scrollingFrame
	if not (template and template:IsA("Frame") and scrollingFrame and scrollingFrame:IsA("ScrollingFrame")) then
		return
	end

	self:_clearGiftRows()

	local playersList = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LOCAL_PLAYER then
			table.insert(playersList, player)
		end
	end

	sortPlayers(playersList)
	if ui.promptLabel and ui.promptLabel:IsA("TextLabel") then
		ui.promptLabel.Text = buildGiftPromptText(tostring(self._giftOffer and self._giftOffer.displayName or "Gift"), #playersList > 0)
	end

	for _, player in ipairs(playersList) do
		local row = template:Clone()
		row.Name = string.format("Player_%d", player.UserId)
		row.Visible = true
		row.Parent = scrollingFrame

		local displayNameLabel = row:FindFirstChild("DisplayName", true)
		local usernameLabel = row:FindFirstChild("Username", true)
		local playerIconFrame = row:FindFirstChild("PlayerIcon", true)
		local giftButton = row:FindFirstChild("GiftButton", true)
		local imageLabel = playerIconFrame and playerIconFrame:FindFirstChild("Image", true)

		if displayNameLabel and displayNameLabel:IsA("TextLabel") then
			displayNameLabel.Text = player.DisplayName
		end
		if usernameLabel and usernameLabel:IsA("TextLabel") then
			usernameLabel.Text = "@" .. player.Name
		end
		if imageLabel and imageLabel:IsA("ImageLabel") then
			self:_loadThumbnail(imageLabel, player)
		end
		row:SetAttribute(GIFT_RECIPIENT_USER_ID_ATTR, player.UserId)
		if giftButton and giftButton:IsA("GuiButton") then
			giftButton:SetAttribute(GIFT_RECIPIENT_USER_ID_ATTR, player.UserId)
			UIController:CreateButton(giftButton, function()
				self:_onGiftPlayerSelected(giftButton)
			end)
		end

		self._giftRowsByUserId[player.UserId] = row
	end

end

function MarketplaceController:_deriveReturnFrameName(button: GuiButton): string?
	local current = button
	while current do
		if current.Name == STORE_NAME then
			return STORE_NAME
		end
		current = current.Parent
	end

	return nil
end

function MarketplaceController:_showMessage(message: string)
	local text = normalizeString(message)
	if text == "" then
		return
	end

	Notify.Show(text, {
		channel = "marketplace",
		duration = 4,
	})
end

function MarketplaceController:_openGiftingFlow(offerKey: string, sourceButton: GuiButton)
	local offer, err = self:_getOfferInfo(offerKey)
	if not offer then
		self:_showMessage(err or "That offer could not be loaded.")
		return
	end
	if offer.giftable ~= true then
		self:_showMessage(string.format("%s cannot be gifted.", tostring(offer.displayName or offer.offerKey or "That offer")))
		return
	end

	self._giftOffer = offer
	self._giftReturnFrameName = self:_deriveReturnFrameName(sourceButton)
	self:_setGiftHeader(tostring(offer.displayName or offer.offerKey or "Gift"))
	self:_buildGiftPlayerEntries()
	FrameController:OpenFrame(MODAL_NAME)
end

function MarketplaceController:_onGiftPlayerSelected(sourceInstance: Instance)
	local offer = self._giftOffer
	if typeof(offer) ~= "table" then
		self:_showMessage("No gift offer is selected.")
		return
	end

	local recipientUserId = self:_resolveGiftRecipientUserId(sourceInstance)
	if recipientUserId == nil or recipientUserId <= 0 then
		self:_showMessage("That recipient could not be resolved. Reopen the gift list and try again.")
		return
	end
	if recipientUserId == LOCAL_PLAYER.UserId then
		self:_showMessage("Pick a different player to receive that gift.")
		return
	end

	local ok, message = self:_invokePromptGiftPurchase(offer.offerKey, recipientUserId)
	if not ok then
		self:_showMessage(message or "Failed to open the gift prompt.")
		return
	end

	if self._giftReturnFrameName then
		FrameController:OpenFrame(self._giftReturnFrameName)
	else
		FrameController:CloseFrame(MODAL_NAME)
	end
end

function MarketplaceController:_handleMarketplaceButton(button: GuiButton)
	local offerKey = normalizeString(button:GetAttribute(OFFER_KEY_ATTR))
	if offerKey == "" then
		self:_showMessage("Marketplace button is missing MarketplaceOfferKey.")
		return
	end

	local isGift = button:GetAttribute(IS_GIFT_ATTR) == true
	if isGift then
		self:_openGiftingFlow(offerKey, button)
		return
	end

	local offer, err = self:_getOfferInfo(offerKey)
	if not offer then
		self:_showMessage(err or "That offer could not be loaded.")
		return
	end
	if offer.selfConfigured ~= true then
		self:_showMessage(string.format("%s is not configured for direct purchase.", tostring(offer.displayName or offer.offerKey or "That offer")))
		return
	end

	local ok, message, promptOpened = self:_invokePromptOfferPurchase(offerKey)
	if not ok or promptOpened ~= true then
		self:_showMessage(message or "Failed to open the purchase prompt.")
	end
end

function MarketplaceController:PromptOfferPurchase(offerKey: string): (boolean, string?, boolean)
	self:_ensureState()

	local normalizedOfferKey = normalizeString(offerKey)
	if normalizedOfferKey == "" then
		return false, "MarketplaceOfferKey is required.", false
	end

	local offer, err = self:_getOfferInfo(normalizedOfferKey)
	if not offer then
		return false, err or "That offer could not be loaded.", false
	end
	if offer.selfConfigured ~= true then
		return false,
			string.format(
				"%s is not configured for direct purchase.",
				tostring(offer.displayName or offer.offerKey or "That offer")
			),
			false
	end

	return self:_invokePromptOfferPurchase(normalizedOfferKey)
end

function MarketplaceController:_bindButton(button: Instance)
	local playerGui = self:_getPlayerGui()
	if not (button and button:IsA("GuiButton") and button:IsDescendantOf(playerGui)) then
		return
	end
	if self._trackedButtons[button] then
		return
	end

	self._trackedButtons[button] = true
	UIController:CreateButton(button, function()
		self:_handleMarketplaceButton(button)
	end)
end

function MarketplaceController:_unbindButton(button: Instance)
	self._trackedButtons[button] = nil
end

function MarketplaceController:_refreshTaggedButtons()
	local playerGui = self:_getPlayerGui()
	local activeButtons = {}
	for _, instance in ipairs(CollectionService:GetTagged(TAG_NAME)) do
		if instance:IsDescendantOf(playerGui) and instance:IsA("GuiButton") then
			activeButtons[instance] = true
			self:_bindButton(instance)
		end
	end

	for button in pairs(self._trackedButtons) do
		if not activeButtons[button] or not button.Parent then
			self:_unbindButton(button)
		end
	end
end

function MarketplaceController:OnStart()
	self:_ensureState()
	self:_cacheUi()
	local remotes = self:_getRemotes()
	local playerGui = self:_getPlayerGui()

	if self._marketplaceUpdatedConnection then
		self._marketplaceUpdatedConnection:Disconnect()
	end
	self._marketplaceUpdatedConnection = remotes.marketplaceUpdated.OnClientEvent:Connect(function()
		self:_requestPriceLabelRefresh()
	end)

	CollectionService:GetInstanceAddedSignal(TAG_NAME):Connect(function(instance)
		self:_bindButton(instance)
	end)
	CollectionService:GetInstanceRemovedSignal(TAG_NAME):Connect(function(instance)
		self:_unbindButton(instance)
	end)
	CollectionService:GetInstanceAddedSignal(PRICE_LABEL_TAG_NAME):Connect(function(instance)
		self:_bindPriceLabel(instance)
	end)
	CollectionService:GetInstanceRemovedSignal(PRICE_LABEL_TAG_NAME):Connect(function(instance)
		self:_unbindPriceLabel(instance)
	end)
	playerGui.DescendantAdded:Connect(function(instance)
		if CollectionService:HasTag(instance, TAG_NAME) then
			self:_bindButton(instance)
		end
		if CollectionService:HasTag(instance, PRICE_LABEL_TAG_NAME) then
			self:_bindPriceLabel(instance)
		end
		if instance.Name == STORE_NAME and instance:IsA("GuiObject") then
			self:_trackStoreRoot(instance)
		end
	end)
	playerGui.DescendantRemoving:Connect(function(instance)
		if CollectionService:HasTag(instance, TAG_NAME) then
			self:_unbindButton(instance)
		end
		if CollectionService:HasTag(instance, PRICE_LABEL_TAG_NAME) then
			self:_unbindPriceLabel(instance)
		end
		if instance.Name == STORE_NAME and instance:IsA("GuiObject") then
			self:_untrackStoreRoot(instance)
		end
	end)

	Players.PlayerAdded:Connect(function()
		if FrameController:IsOpen(MODAL_NAME) then
			self:_buildGiftPlayerEntries()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		if FrameController:IsOpen(MODAL_NAME) then
			task.defer(function()
				self:_buildGiftPlayerEntries()
			end)
		end
	end)

	self:_refreshTaggedButtons()
	self:_refreshTaggedPriceLabels()
	self:_refreshTrackedStoreRoots()
	self:_requestPriceLabelRefresh()
end

return MarketplaceController
