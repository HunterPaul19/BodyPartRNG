local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.DataService)
local StatsService = require(script.Parent.StatsService)
local MarketplaceHandlers = require(script.Parent.MarketplaceHandlers)
local Schema = require(ReplicatedStorage.Lists.Schema)
local Signal = require(ReplicatedStorage.Common.Signal)
local MarketplaceCatalog = require(ReplicatedStorage.Lists.RobuxPurchases)
local MarketplaceState = require(ReplicatedStorage.Shared.Marketplace.State)
local Notify = require(ReplicatedStorage.Shared.UI.Notify)

local MARKETPLACE_KEY = Schema.Marketplace and Schema.Marketplace.key or "marketplace"
local REMOTES_FOLDER_NAME = "Remotes"
local PLAY_CLIENT_SOUND_REMOTE_NAME = "PlayClientSound"
local MARKETPLACE_FOLDER_NAME = "Marketplace"
local GET_OFFER_INFO_REMOTE_NAME = "GetOfferInfo"
local GET_OFFER_PRESENTATIONS_REMOTE_NAME = "GetOfferPresentations"
local PROMPT_OFFER_PURCHASE_REMOTE_NAME = "PromptOfferPurchase"
local PROMPT_GIFT_PURCHASE_REMOTE_NAME = "PromptGiftPurchase"
local MARKETPLACE_UPDATED_REMOTE_NAME = "Updated"

local PurchaseReceipt = {}

PurchaseReceipt.RobuxPurchases = MarketplaceCatalog
PurchaseReceipt.PurchaseProcessed = Signal.new()
PurchaseReceipt.OwnedPassesReady = Signal.new()
PurchaseReceipt.OwnedEntitlementsReady = Signal.new()
PurchaseReceipt.GiftSent = Signal.new()
PurchaseReceipt.GiftDelivered = Signal.new()
PurchaseReceipt.DuplicateGiftBlocked = Signal.new()

local remotesFolder: Folder? = nil
local playClientSoundRemote: RemoteEvent? = nil
local marketplaceRemotesFolder: Folder? = nil
local getOfferInfoRemote: RemoteFunction? = nil
local getOfferPresentationsRemote: RemoteFunction? = nil
local promptOfferPurchaseRemote: RemoteFunction? = nil
local promptGiftPurchaseRemote: RemoteFunction? = nil
local marketplaceUpdatedRemote: RemoteEvent? = nil
local ownedOfferCache: { [Player]: { [string]: boolean } } = {}
local invalidPassWarnings: { [string]: boolean } = {}

local function ensureRemotesFolder(): Folder
	if remotesFolder and remotesFolder.Parent == ReplicatedStorage then
		return remotesFolder
	end

	local existing = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		remotesFolder = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = REMOTES_FOLDER_NAME
	folder.Parent = ReplicatedStorage
	remotesFolder = folder
	return folder
end

local function ensurePlayClientSoundRemote(): RemoteEvent
	local folder = ensureRemotesFolder()

	if playClientSoundRemote and playClientSoundRemote.Parent == folder then
		return playClientSoundRemote
	end

	local existing = folder:FindFirstChild(PLAY_CLIENT_SOUND_REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		playClientSoundRemote = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = PLAY_CLIENT_SOUND_REMOTE_NAME
	remote.Parent = folder
	playClientSoundRemote = remote
	return remote
end

local function ensureMarketplaceRemotesFolder(): Folder
	local folder = ensureRemotesFolder()
	if marketplaceRemotesFolder and marketplaceRemotesFolder.Parent == folder then
		return marketplaceRemotesFolder
	end

	local existing = folder:FindFirstChild(MARKETPLACE_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		marketplaceRemotesFolder = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local childFolder = Instance.new("Folder")
	childFolder.Name = MARKETPLACE_FOLDER_NAME
	childFolder.Parent = folder
	marketplaceRemotesFolder = childFolder
	return childFolder
end

local function ensureMarketplaceRemoteFunction(cachedRemote: RemoteFunction?, remoteName: string): RemoteFunction
	local folder = ensureMarketplaceRemotesFolder()
	if cachedRemote and cachedRemote.Parent == folder then
		return cachedRemote
	end

	local existing = folder:FindFirstChild(remoteName)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = remoteName
	remote.Parent = folder
	return remote
end

local function ensureMarketplaceRemoteEvent(cachedRemote: RemoteEvent?, remoteName: string): RemoteEvent
	local folder = ensureMarketplaceRemotesFolder()
	if cachedRemote and cachedRemote.Parent == folder then
		return cachedRemote
	end

	local existing = folder:FindFirstChild(remoteName)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = remoteName
	remote.Parent = folder
	return remote
end

local function sendClientSound(player: Player, soundName: string)
	if typeof(soundName) ~= "string" or soundName == "" then
		return
	end

	ensurePlayClientSoundRemote():FireClient(player, soundName)
end

local function normalizeString(value: any): string
	if typeof(value) ~= "string" then
		return ""
	end

	local trimmed = string.match(value, "%S.*")
	if not trimmed then
		return ""
	end

	return trimmed
end

local function getOffer(offerKey: string)
	return MarketplaceCatalog.GetOffer(offerKey)
end

local function getOfferDisplayName(offerKey: string?): string
	local offer = if typeof(offerKey) == "string" then getOffer(offerKey) else nil
	local displayName = offer and offer.displayName or offerKey or "purchase"
	return normalizeString(displayName) ~= "" and tostring(displayName) or "purchase"
end

local function warnInvalidGiftRecipient(player: Player, offerKey: string, recipientUserId: any, reason: string)
	warn(string.format(
		"[PurchaseReceipt] Gift recipient rejected (%s): sender=%s(%d), recipient=%s, offer=%s",
		tostring(reason),
		player.Name,
		player.UserId,
		tostring(recipientUserId),
		tostring(offerKey)
	))
end

local function buildOfferClientPayload(offer: any): any
	if typeof(offer) ~= "table" then
		return nil
	end

	local selfPurchase = offer.selfPurchase
	local giftPurchase = offer.giftPurchase
	return {
		offerKey = offer.offerKey,
		displayName = getOfferDisplayName(offer.offerKey),
		giftable = offer.giftable == true,
		selfConfigured = typeof(selfPurchase) == "table" and typeof(selfPurchase.robloxId) == "number",
		giftConfigured = typeof(giftPurchase) == "table"
			and giftPurchase.saleKind == "product"
			and typeof(giftPurchase.robloxId) == "number",
	}
end

local function getMarketplaceState(player: Player)
	local legacyPurchaseLog = DataService:Get(player, "purchaseLog")
	return MarketplaceState.Normalize(DataService:Get(player, MARKETPLACE_KEY), legacyPurchaseLog)
end

local function mutateMarketplaceState(player: Player, mutator: (any) -> ())
	local finalState = nil
	local legacyPurchaseLog = DataService:Get(player, "purchaseLog")
	DataService:Set(player, MARKETPLACE_KEY, function(currentState)
		local state = MarketplaceState.Normalize(currentState, legacyPurchaseLog)
		mutator(state)
		finalState = MarketplaceState.Normalize(state)
		return finalState
	end)

	return finalState
end

local function rebuildOwnedOfferCache(player: Player, state: any?)
	local normalizedState = MarketplaceState.Normalize(state or getMarketplaceState(player))
	local owned = {}

	for offerKey in pairs(normalizedState.entitlementsByKey) do
		owned[offerKey] = true
	end

	for offerKey in pairs(normalizedState.oneTimePurchasesByKey) do
		owned[offerKey] = true
	end

	ownedOfferCache[player] = owned
	return owned
end

local function getOwnedOffers(player: Player)
	return ownedOfferCache[player] or rebuildOwnedOfferCache(player)
end

local function getOwnedPassOfferMap(player: Player)
	local ownedPasses = {}
	for offerKey, isOwned in pairs(getOwnedOffers(player)) do
		local offer = getOffer(offerKey)
		if isOwned == true and offer and offer.kind == "pass" then
			ownedPasses[offerKey] = true
		end
	end
	return ownedPasses
end

local function hasPermanentOwnershipInState(state: any, offer: any): boolean
	if typeof(state) ~= "table" or typeof(offer) ~= "table" then
		return false
	end

	local offerKey = offer.offerKey
	if offer.grantMode == "one_time" then
		return typeof(state.oneTimePurchasesByKey) == "table" and state.oneTimePurchasesByKey[offerKey] ~= nil
	end

	return typeof(state.entitlementsByKey) == "table" and state.entitlementsByKey[offerKey] ~= nil
end

local function validatePassSale(offer: any, sale: any): (boolean, string?)
	if typeof(offer) ~= "table" then
		return false, "Marketplace offer is missing."
	end
	if typeof(sale) ~= "table" then
		return false, string.format("%s is missing its gamepass sale data.", getOfferDisplayName(offer.offerKey))
	end
	if typeof(sale.robloxId) ~= "number" then
		return false, string.format("%s is missing a numeric gamepass id.", getOfferDisplayName(offer.offerKey))
	end

	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(sale.robloxId, Enum.InfoType.GamePass)
	end)
	if ok and typeof(info) == "table" then
		return true, nil
	end

	local failureMessage = if ok
		then string.format(
			"%s gamepass id %d returned invalid product metadata.",
			getOfferDisplayName(offer.offerKey),
			sale.robloxId
		)
		else string.format(
			"%s gamepass id %d failed validation: %s",
			getOfferDisplayName(offer.offerKey),
			sale.robloxId,
			tostring(info)
		)

	local warningKey = string.format("%s:%s", tostring(offer.offerKey), tostring(sale.robloxId))
	if invalidPassWarnings[warningKey] ~= true then
		invalidPassWarnings[warningKey] = true
		warn(string.format(
			"[PurchaseReceipt] Invalid pass configuration for key '%s' with id '%s': %s",
			tostring(offer.offerKey),
			tostring(sale.robloxId),
			failureMessage
		))
	end

	return false, failureMessage
end

local function getSaleDefinition(offer: any, purchaseKind: string)
	if typeof(offer) ~= "table" then
		return nil
	end
	if purchaseKind == "gift" then
		return offer.giftPurchase
	end
	return offer.selfPurchase
end

local function makeOwnershipRecord(context: any, sale: any)
	return {
		ownedAt = os.time(),
		source = tostring(context and context.source or "unknown"),
		saleRobloxId = math.max(0, math.floor(tonumber(sale and sale.robloxId) or 0)),
		purchaseId = normalizeString(context and context.purchaseId),
		senderUserId = math.max(0, math.floor(tonumber(context and context.senderUserId) or 0)),
		recipientUserId = math.max(0, math.floor(tonumber(context and context.recipientUserId) or 0)),
	}
end

local function markPurchaseRecorded(player: Player, offer: any, sale: any, context: any)
	local purchaseId = normalizeString(context and context.purchaseId)
	local purchaseWasNew = false
	local ownershipWasNew = false
	local finalState = mutateMarketplaceState(player, function(state)
		if purchaseId ~= "" and state.purchaseIds[purchaseId] == nil then
			purchaseWasNew = true
			state.purchaseIds[purchaseId] = {
				offerKey = offer.offerKey,
				saleKind = tostring(sale.saleKind),
				purchaseKind = tostring(context.purchaseKind or "self"),
				saleRobloxId = math.max(0, math.floor(tonumber(sale.robloxId) or 0)),
				processedAt = os.time(),
			}
		end

		if context.markOwned == true then
			if offer.grantMode == "one_time" then
				if state.oneTimePurchasesByKey[offer.offerKey] == nil then
					ownershipWasNew = true
				end
				state.oneTimePurchasesByKey[offer.offerKey] = makeOwnershipRecord(context, sale)
			else
				if state.entitlementsByKey[offer.offerKey] == nil then
					ownershipWasNew = true
				end
				state.entitlementsByKey[offer.offerKey] = makeOwnershipRecord(context, sale)
			end
		end
	end)

	rebuildOwnedOfferCache(player, finalState)

	if offer.grantMode == "repeatable" then
		return purchaseWasNew, finalState
	end

	return ownershipWasNew, finalState
end

local function addPendingGiftPrompt(player: Player, saleRobloxId: number, offerKey: string, recipientUserId: number)
	local productIdKey = tostring(math.floor(saleRobloxId))
	mutateMarketplaceState(player, function(state)
		state.pendingGiftPromptsByProductId[productIdKey] = {
			offerKey = offerKey,
			recipientUserId = math.floor(recipientUserId),
			createdAt = os.time(),
		}
	end)
end

local function getPendingGiftPrompt(player: Player, saleRobloxId: number)
	local state = getMarketplaceState(player)
	return typeof(state.pendingGiftPromptsByProductId) == "table" and state.pendingGiftPromptsByProductId[tostring(math.floor(saleRobloxId))] or nil
end

local function clearPendingGiftPrompt(player: Player, saleRobloxId: number)
	local productIdKey = tostring(math.floor(saleRobloxId))
	mutateMarketplaceState(player, function(state)
		state.pendingGiftPromptsByProductId[productIdKey] = nil
	end)
end

local function addGiftInboxEntry(player: Player, giftRecord: any)
	mutateMarketplaceState(player, function(state)
		local gifts = state.gifts
		local giftId = giftRecord.giftId
		if gifts.historyById[giftId] or gifts.failedById[giftId] then
			return
		end

		gifts.inboxById[giftId] = giftRecord
	end)
end

local function moveGiftToFinalState(player: Player, giftRecord: any, finalBucket: string, status: string)
	local finalState = mutateMarketplaceState(player, function(state)
		local gifts = state.gifts
		local giftId = giftRecord.giftId
		local finalRecord = {
			giftId = giftId,
			offerKey = giftRecord.offerKey,
			senderUserId = math.max(0, math.floor(tonumber(giftRecord.senderUserId) or 0)),
			recipientUserId = math.max(0, math.floor(tonumber(giftRecord.recipientUserId) or 0)),
			saleRobloxId = math.max(0, math.floor(tonumber(giftRecord.saleRobloxId) or 0)),
			purchaseId = normalizeString(giftRecord.purchaseId),
			status = status,
			createdAt = math.max(0, math.floor(tonumber(giftRecord.createdAt) or 0)),
			deliveredAt = os.time(),
		}

		gifts.inboxById[giftId] = nil
		gifts.historyById[giftId] = nil
		gifts.failedById[giftId] = nil
		gifts[finalBucket][giftId] = finalRecord
	end)

	return finalState
end

local function callHandler(offer: any, hookName: string, player: Player, context: any)
	if typeof(offer) ~= "table" or typeof(offer.handlerKey) ~= "string" then
		return true, nil
	end

	local handler = MarketplaceHandlers.Get(offer.handlerKey)
	if typeof(handler) ~= "table" then
		warn(string.format("[PurchaseReceipt] Missing marketplace handler '%s' for offer '%s'.", tostring(offer.handlerKey), tostring(offer.offerKey)))
		return false, "Marketplace handler missing."
	end

	local hook = handler[hookName]
	if typeof(hook) ~= "function" then
		return true, nil
	end

	local ok, handlerResult, handlerMessage = pcall(hook, player, context)
	if not ok then
		warn(string.format("[PurchaseReceipt] %s for offer '%s' failed: %s", tostring(hookName), tostring(offer.offerKey), tostring(handlerResult)))
		return false, tostring(handlerResult)
	end

	if handlerResult == false then
		return false, tostring(handlerMessage or "Marketplace handler rejected the request.")
	end

	return true, handlerMessage
end

local function makePurchaseContext(offer: any, sale: any, context: any?)
	local source = if typeof(context) == "table" and typeof(context.source) == "string" then context.source else "unknown"
	local purchaseKind = if typeof(context) == "table" and typeof(context.purchaseKind) == "string"
		then context.purchaseKind
		else "self"
	return {
		offerKey = offer.offerKey,
		offerKind = offer.kind,
		saleKind = sale.saleKind,
		purchaseKind = purchaseKind,
		robloxId = sale.robloxId,
		purchaseId = if typeof(context) == "table" then context.purchaseId else nil,
		senderUserId = if typeof(context) == "table" then context.senderUserId else nil,
		recipientUserId = if typeof(context) == "table" then context.recipientUserId else nil,
		source = source,
		markOwned = offer.grantMode ~= "repeatable",
		isNew = false,
	}
end

local function sendPurchaseThanks(player: Player, offerKey: string, source: string, purchaseKind: string)
	if purchaseKind == "gift" then
		if source == "gift_delivery" then
			Notify.Send(player, string.format("You received %s as a gift!", getOfferDisplayName(offerKey)), {
				channel = "marketplace",
			})
		end
		return
	end

	if source == "prompt" or source == "receipt" then
		Notify.Send(player, string.format("Thanks for purchasing %s!", getOfferDisplayName(offerKey)), {
			channel = "marketplace",
		})
	end
end

local function isPlayerLoaded(player: Player): boolean
	return DataService:Get(player) ~= nil
end

local function resolvePassOwnership(player: Player, offer: any): boolean
	if typeof(offer) ~= "table" then
		return false
	end

	local sale = offer.selfPurchase
	if typeof(sale) ~= "table" or sale.saleKind ~= "pass" or typeof(sale.robloxId) ~= "number" then
		return getOwnedOffers(player)[offer.offerKey] == true
	end

	local ok, has = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, sale.robloxId)
	if ok and has then
		local context = makePurchaseContext(offer, sale, {
			source = "join",
			purchaseKind = "self",
			recipientUserId = player.UserId,
		})
		context.isNew = markPurchaseRecorded(player, offer, sale, context)
		return true
	end

	return getOwnedOffers(player)[offer.offerKey] == true
end

local function ownsOffer(player: Player, offer: any): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") or typeof(offer) ~= "table" then
		return false
	end

	if getOwnedOffers(player)[offer.offerKey] == true then
		return true
	end

	if offer.kind == "pass" then
		return resolvePassOwnership(player, offer)
	end

	return false
end

local function buildOfferPresentationPayload(player: Player, offer: any): any
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end
	if typeof(offer) ~= "table" then
		return nil
	end

	local selfPurchase = offer.selfPurchase
	local saleKind = if typeof(selfPurchase) == "table" then normalizeString(selfPurchase.saleKind) else ""
	local saleRobloxId = if typeof(selfPurchase) == "table" then tonumber(selfPurchase.robloxId) else nil

	return {
		offerKey = offer.offerKey,
		exists = true,
		selfConfigured = saleKind ~= "" and saleRobloxId ~= nil,
		saleKind = saleKind,
		saleRobloxId = if saleRobloxId ~= nil then math.floor(saleRobloxId) else nil,
		isOwned = ownsOffer(player, offer),
	}
end

local function hasDuplicateGiftOwnership(recipientUserId: number, offer: any): boolean
	local recipientPlayer = Players:GetPlayerByUserId(recipientUserId)
	if recipientPlayer then
		return ownsOffer(recipientPlayer, offer)
	end

	local sale = offer and offer.selfPurchase
	if offer and offer.kind == "pass" and typeof(sale) == "table" and sale.saleKind == "pass" and typeof(sale.robloxId) == "number" then
		local ok, has = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, recipientUserId, sale.robloxId)
		if ok and has then
			return true
		end
	end

	return false
end

local function promptProductPurchase(player: Player, robloxId: number): (boolean, string?)
	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, robloxId)
	end)
	if not ok then
		return false, tostring(err)
	end

	return true, nil
end

local function promptPassPurchase(player: Player, robloxId: number): (boolean, string?)
	local ok, err = pcall(function()
		MarketplaceService:PromptGamePassPurchase(player, robloxId)
	end)
	if not ok then
		return false, tostring(err)
	end

	return true, nil
end

local function filterPassOwnedKeys(player: Player)
	return table.freeze(getOwnedPassOfferMap(player))
end

local function emitOwnedEvents(player: Player)
	PurchaseReceipt.OwnedPassesReady:Fire(player, filterPassOwnedKeys(player))
	PurchaseReceipt.OwnedEntitlementsReady:Fire(player, table.freeze(getOwnedOffers(player)))

	if marketplaceUpdatedRemote then
		marketplaceUpdatedRemote:FireClient(player)
	end
end

local function reconcileOwnedOffersOnJoin(player: Player)
	if not isPlayerLoaded(player) then
		return
	end

	for _, offer in pairs(MarketplaceCatalog.Offers) do
		if offer.kind == "pass" then
			resolvePassOwnership(player, offer)
		end
	end

	local owned = getOwnedOffers(player)
	for _, offer in pairs(MarketplaceCatalog.Offers) do
		local _, _ = callHandler(offer, "reconcileOnJoin", player, {
			offerKey = offer.offerKey,
			isOwned = owned[offer.offerKey] == true,
		})
	end

	emitOwnedEvents(player)
end

local function resolvePassOffer(passIdOrKey: any)
	if typeof(passIdOrKey) == "number" then
		return MarketplaceCatalog.PassOffersById[math.floor(passIdOrKey)]
	end

	if typeof(passIdOrKey) == "string" then
		local offer = getOffer(passIdOrKey)
		if offer and offer.kind == "pass" then
			return offer
		end
	end

	return nil
end

local function processEntitlementGrant(player: Player, offer: any, sale: any, context: any)
	local ok, err = callHandler(offer, "grant", player, context)
	if not ok then
		return false, err or "Failed to apply offer grant."
	end

	local isNew = markPurchaseRecorded(player, offer, sale, context)
	context.isNew = isNew == true

	if context.isNew then
		StatsService:RecordPurchaseProcessed(player, context)
		PurchaseReceipt.PurchaseProcessed:Fire(player, offer.offerKey, context)
		sendClientSound(player, "Kaching")
	end

	sendPurchaseThanks(player, offer.offerKey, context.source, context.purchaseKind)
	return true, nil
end

local function processGiftDelivery(player: Player, giftRecord: any)
	local offer = getOffer(giftRecord.offerKey)
	if not offer then
		moveGiftToFinalState(player, giftRecord, "failedById", "missing_offer")
		return
	end

	addGiftInboxEntry(player, giftRecord)

	if offer.grantMode ~= "repeatable" and hasDuplicateGiftOwnership(player.UserId, offer) then
		moveGiftToFinalState(player, giftRecord, "failedById", "blocked_duplicate")
		PurchaseReceipt.DuplicateGiftBlocked:Fire(player, offer.offerKey, {
			offerKey = offer.offerKey,
			purchaseKind = "gift",
			source = "gift_delivery",
			senderUserId = giftRecord.senderUserId,
			recipientUserId = player.UserId,
			purchaseId = giftRecord.purchaseId,
			robloxId = giftRecord.saleRobloxId,
			isNew = false,
		})
		return
	end

	local sale = {
		saleKind = "product",
		robloxId = giftRecord.saleRobloxId,
	}
	local context = makePurchaseContext(offer, sale, {
		source = "gift_delivery",
		purchaseKind = "gift",
		purchaseId = giftRecord.purchaseId,
		senderUserId = giftRecord.senderUserId,
		recipientUserId = player.UserId,
	})
	local granted, err = processEntitlementGrant(player, offer, sale, context)
	if not granted then
		moveGiftToFinalState(player, giftRecord, "failedById", "grant_failed")
		if err then
			warn(string.format("[PurchaseReceipt] Gift delivery failed for '%s': %s", tostring(offer.offerKey), tostring(err)))
		end
		return
	end

	moveGiftToFinalState(player, giftRecord, "historyById", "delivered")
	StatsService:RecordGiftDelivered(player, offer.offerKey)
	PurchaseReceipt.GiftDelivered:Fire(player, offer.offerKey, context)
	emitOwnedEvents(player)
end

local function processMarketplaceGiftUpdate(player: Player, data: any)
	if typeof(data) ~= "table" or data.updateType ~= "MarketplaceGift" or typeof(data.data) ~= "table" then
		return
	end

	local gift = data.data
	local giftId = normalizeString(gift.giftId)
	local offerKey = normalizeString(gift.offerKey)
	if giftId == "" or offerKey == "" then
		return
	end

	processGiftDelivery(player, {
		giftId = giftId,
		offerKey = offerKey,
		senderUserId = math.max(0, math.floor(tonumber(gift.senderUserId or data.senderId) or 0)),
		recipientUserId = player.UserId,
		saleRobloxId = math.max(0, math.floor(tonumber(gift.saleRobloxId) or 0)),
		purchaseId = normalizeString(gift.purchaseId),
		status = "pending",
		createdAt = math.max(0, math.floor(tonumber(gift.createdAt or data.sendTime) or 0)),
		deliveredAt = 0,
	})
end

local function processProductReceipt(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not isPlayerLoaded(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local sale = MarketplaceCatalog.GetSaleByRobloxId(receiptInfo.ProductId)
	if not sale or sale.saleKind ~= "product" then
		warn("[PurchaseReceipt] Unknown product id:", receiptInfo.ProductId)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local offer = getOffer(sale.offerKey)
	if not offer then
		warn("[PurchaseReceipt] Missing offer for product id:", receiptInfo.ProductId)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local senderContext = makePurchaseContext(offer, sale, {
		source = "receipt",
		purchaseKind = sale.purchaseKind,
		purchaseId = receiptInfo.PurchaseId,
		senderUserId = player.UserId,
		recipientUserId = player.UserId,
	})

	local senderState = getMarketplaceState(player)
	local purchaseId = normalizeString(receiptInfo.PurchaseId)
	if purchaseId ~= "" and typeof(senderState.purchaseIds) == "table" and senderState.purchaseIds[purchaseId] ~= nil then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	if sale.purchaseKind == "gift" then
		local pendingGift = getPendingGiftPrompt(player, sale.robloxId)
		if not pendingGift or pendingGift.offerKey ~= offer.offerKey then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		senderContext.recipientUserId = pendingGift.recipientUserId
		senderContext.markOwned = false
		local giftId = purchaseId ~= "" and purchaseId or string.format("%d:%d:%d", player.UserId, sale.robloxId, os.time())
		local recorded = markPurchaseRecorded(player, offer, sale, senderContext)
		clearPendingGiftPrompt(player, sale.robloxId)
		if recorded then
			local payload = {
				giftId = giftId,
				offerKey = offer.offerKey,
				senderUserId = player.UserId,
				recipientUserId = pendingGift.recipientUserId,
				saleRobloxId = sale.robloxId,
				purchaseId = purchaseId,
				createdAt = os.time(),
			}
			DataService:SendGlobalUpdate(player, pendingGift.recipientUserId, "MarketplaceGift", payload)
			StatsService:RecordGiftSent(player, offer.offerKey)
			PurchaseReceipt.GiftSent:Fire(player, offer.offerKey, senderContext)
		end

		Notify.Send(player, string.format("Sent %s as a gift.", getOfferDisplayName(offer.offerKey)), {
			channel = "marketplace",
		})
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local granted, err = processEntitlementGrant(player, offer, sale, senderContext)
	if not granted then
		if err then
			warn(string.format("[PurchaseReceipt] Product receipt failed for '%s': %s", tostring(offer.offerKey), tostring(err)))
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	emitOwnedEvents(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function unpackPromptGamePassArgs(a, b, c)
	local player = nil
	local gamePassId = nil
	local wasPurchased = false

	if typeof(a) == "Instance" and a:IsA("Player") then
		player = a
		gamePassId = tonumber(b)
		wasPurchased = c == true
	elseif typeof(a) == "number" and typeof(b) == "number" and typeof(c) == "boolean" then
		player = Players:GetPlayerByUserId(a)
		gamePassId = b
		wasPurchased = c
	else
		gamePassId = tonumber(a)
		wasPurchased = b == true or c == true
		if typeof(b) == "Instance" and b:IsA("Player") then
			player = b
		elseif typeof(c) == "Instance" and c:IsA("Player") then
			player = c
		end
	end

	return player, gamePassId, wasPurchased
end

local function onPromptGamePassFinished(a, b, c)
	local player, gamePassId, wasPurchased = unpackPromptGamePassArgs(a, b, c)
	if not player or not gamePassId or not wasPurchased or not isPlayerLoaded(player) then
		return
	end

	local offer = MarketplaceCatalog.PassOffersById[gamePassId]
	if not offer then
		warn("[PurchaseReceipt] Unknown pass id:", gamePassId)
		return
	end

	local sale = offer.selfPurchase
	local context = makePurchaseContext(offer, sale, {
		source = "prompt",
		purchaseKind = "self",
		senderUserId = player.UserId,
		recipientUserId = player.UserId,
	})
	local granted, err = processEntitlementGrant(player, offer, sale, context)
	if not granted then
		if err then
			warn(string.format("[PurchaseReceipt] Pass prompt grant failed for '%s': %s", tostring(offer.offerKey), tostring(err)))
		end
		return
	end

	emitOwnedEvents(player)
end

function PurchaseReceipt:OnStart()
	ensurePlayClientSoundRemote()
	getOfferInfoRemote = ensureMarketplaceRemoteFunction(getOfferInfoRemote, GET_OFFER_INFO_REMOTE_NAME)
	getOfferPresentationsRemote =
		ensureMarketplaceRemoteFunction(getOfferPresentationsRemote, GET_OFFER_PRESENTATIONS_REMOTE_NAME)
	promptOfferPurchaseRemote = ensureMarketplaceRemoteFunction(promptOfferPurchaseRemote, PROMPT_OFFER_PURCHASE_REMOTE_NAME)
	promptGiftPurchaseRemote = ensureMarketplaceRemoteFunction(promptGiftPurchaseRemote, PROMPT_GIFT_PURCHASE_REMOTE_NAME)
	marketplaceUpdatedRemote = ensureMarketplaceRemoteEvent(marketplaceUpdatedRemote, MARKETPLACE_UPDATED_REMOTE_NAME)
	MarketplaceService.ProcessReceipt = processProductReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPromptGamePassFinished)
	getOfferInfoRemote.OnServerInvoke = function(_player: Player, offerKey: string)
		local payload = self:GetOfferClientView(offerKey)
		if payload then
			return {
				ok = true,
				offer = payload,
			}
		end

		return {
			ok = false,
			message = "That offer does not exist.",
		}
	end
	getOfferPresentationsRemote.OnServerInvoke = function(player: Player, offerKeys: any)
		return {
			ok = true,
			offers = self:GetOfferPresentations(player, offerKeys),
		}
	end
	promptOfferPurchaseRemote.OnServerInvoke = function(player: Player, offerKey: string)
		local ok, message, promptOpened = self:PromptOfferPurchase(player, offerKey)
		return {
			ok = ok,
			message = message,
			promptOpened = promptOpened == true,
			offer = self:GetOfferClientView(offerKey),
		}
	end
	promptGiftPurchaseRemote.OnServerInvoke = function(player: Player, payload: any)
		if typeof(payload) ~= "table" then
			return {
				ok = false,
				message = "Gift payload must be a table.",
			}
		end

		local ok, message = self:PromptGiftPurchase(player, payload.offerKey, payload.recipientUserId)
		return {
			ok = ok,
			message = message,
			offer = self:GetOfferClientView(payload.offerKey),
		}
	end
	DataService.GlobalUpdateProcessed:Connect(function(player: Player, _profile: any, data: any)
		processMarketplaceGiftUpdate(player, data)
	end)
end

function PurchaseReceipt:OnPlayerAdded(player: Player)
	reconcileOwnedOffersOnJoin(player)
end

function PurchaseReceipt:OnPlayerRemoving(player: Player)
	ownedOfferCache[player] = nil
end

function PurchaseReceipt:GetOffer(offerKey: string)
	return getOffer(offerKey)
end

function PurchaseReceipt:GetOfferClientView(offerKey: string)
	return buildOfferClientPayload(getOffer(offerKey))
end

function PurchaseReceipt:GetOfferPresentations(player: Player, offerKeys: any)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return {}
	end

	local presentations = {}
	if typeof(offerKeys) ~= "table" then
		return presentations
	end

	local seenOfferKeys = {}
	for _, offerKeyValue in ipairs(offerKeys) do
		local offerKey = normalizeString(offerKeyValue)
		if offerKey ~= "" and not seenOfferKeys[offerKey] then
			seenOfferKeys[offerKey] = true
			local offer = getOffer(offerKey)
			if offer then
				presentations[offerKey] = buildOfferPresentationPayload(player, offer)
			else
				presentations[offerKey] = {
					offerKey = offerKey,
					exists = false,
					selfConfigured = false,
					saleKind = "",
					saleRobloxId = nil,
					isOwned = false,
				}
			end
		end
	end

	return presentations
end

function PurchaseReceipt:GetOwnedEntitlements(player: Player)
	return getOwnedOffers(player)
end

function PurchaseReceipt:HasEntitlement(player: Player, offerKey: string): boolean
	local offer = getOffer(offerKey)
	if not offer then
		return false
	end

	return ownsOffer(player, offer)
end

function PurchaseReceipt:HasPass(player: Player, passIdOrKey: any): boolean
	local offer = resolvePassOffer(passIdOrKey)
	if not offer then
		return false
	end

	return ownsOffer(player, offer)
end

function PurchaseReceipt:GetOwnedPasses(player: Player)
	return getOwnedPassOfferMap(player)
end

function PurchaseReceipt:PromptOfferPurchase(player: Player, offerKey: string): (boolean, string?, boolean)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "A valid player is required.", false
	end
	if not isPlayerLoaded(player) then
		return false, "Player data is not loaded.", false
	end

	local offer = getOffer(offerKey)
	if not offer then
		return false, "That offer does not exist.", false
	end

	local sale = getSaleDefinition(offer, "self")
	if typeof(sale) ~= "table" or typeof(sale.robloxId) ~= "number" then
		return false, string.format("%s is not configured for self purchase.", getOfferDisplayName(offerKey)), false
	end

	if offer.grantMode ~= "repeatable" and ownsOffer(player, offer) then
		return true, string.format("%s already owned.", getOfferDisplayName(offerKey)), false
	end

	local ok, err = callHandler(offer, "canPurchase", player, {
		offerKey = offerKey,
		purchaseKind = "self",
		recipientUserId = player.UserId,
	})
	if not ok then
		return false, err or "This purchase is not available right now.", false
	end

	local prompted = false
	if sale.saleKind == "pass" then
		local isValidPass, validationError = validatePassSale(offer, sale)
		if not isValidPass then
			return false, validationError or string.format("%s is not configured correctly right now.", getOfferDisplayName(offerKey)), false
		end
		prompted, err = promptPassPurchase(player, sale.robloxId)
	else
		prompted, err = promptProductPurchase(player, sale.robloxId)
	end

	if not prompted then
		return false, err or "Failed to open the purchase prompt.", false
	end

	StatsService:RecordPurchasePrompt(player, offerKey)
	return true, "Purchase prompt opened.", true
end

function PurchaseReceipt:PromptGiftPurchase(player: Player, offerKey: string, recipientUserId: number): (boolean, string?)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "A valid player is required."
	end
	if not isPlayerLoaded(player) then
		return false, "Player data is not loaded."
	end

	local offer = getOffer(offerKey)
	if not offer then
		return false, "That offer does not exist."
	end
	if offer.giftable ~= true then
		return false, string.format("%s cannot be gifted.", getOfferDisplayName(offerKey))
	end

	local resolvedRecipientUserId = tonumber(recipientUserId)
	if resolvedRecipientUserId == nil then
		warnInvalidGiftRecipient(player, offerKey, recipientUserId, "invalid_recipient")
		return false, "A valid recipient userId is required."
	end
	resolvedRecipientUserId = math.floor(resolvedRecipientUserId)
	if resolvedRecipientUserId <= 0 then
		warnInvalidGiftRecipient(player, offerKey, resolvedRecipientUserId, "invalid_recipient")
		return false, "A valid recipient userId is required."
	end
	if resolvedRecipientUserId == player.UserId then
		warnInvalidGiftRecipient(player, offerKey, resolvedRecipientUserId, "self_recipient")
		return false, "Pick a different player to receive that gift."
	end

	local sale = getSaleDefinition(offer, "gift")
	if typeof(sale) ~= "table" or sale.saleKind ~= "product" then
		return false, string.format("%s is not configured for gifting.", getOfferDisplayName(offerKey))
	end
	if typeof(sale.robloxId) ~= "number" then
		return false, string.format("%s is missing its dedicated gift product id.", getOfferDisplayName(offerKey))
	end

	if offer.grantMode ~= "repeatable" and hasDuplicateGiftOwnership(resolvedRecipientUserId, offer) then
		StatsService:RecordDuplicateGiftBlocked(player, offerKey)
		PurchaseReceipt.DuplicateGiftBlocked:Fire(player, offerKey, {
			offerKey = offerKey,
			purchaseKind = "gift",
			source = "gift_precheck",
			senderUserId = player.UserId,
			recipientUserId = resolvedRecipientUserId,
			robloxId = sale.robloxId,
			isNew = false,
		})
		return false, string.format("That player already owns %s.", getOfferDisplayName(offerKey))
	end

	local ok, err = callHandler(offer, "canGift", player, {
		offerKey = offerKey,
		purchaseKind = "gift",
		recipientUserId = resolvedRecipientUserId,
	})
	if not ok then
		return false, err or "This gift is not available right now."
	end

	addPendingGiftPrompt(player, sale.robloxId, offerKey, resolvedRecipientUserId)
	local prompted, promptError = promptProductPurchase(player, sale.robloxId)
	if not prompted then
		clearPendingGiftPrompt(player, sale.robloxId)
		return false, promptError or "Failed to open the gift purchase prompt."
	end

	StatsService:RecordPurchasePrompt(player, offerKey)
	return true, "Gift purchase prompt opened."
end

function PurchaseReceipt:PromptPassPurchase(player: Player, passIdOrKey: any): (boolean, string?)
	local offer = resolvePassOffer(passIdOrKey)
	if not offer then
		return false, "That pass does not exist."
	end

	return self:PromptOfferPurchase(player, offer.offerKey)
end

return PurchaseReceipt
