local MarketplaceState = {}

MarketplaceState.VERSION = 1

local LEGACY_OFFER_KEY_MAP = {
	StarterPack = "starter_pack",
}

local function toWholeNumber(value: any, minimum: number?): number
	local numberValue = math.floor(tonumber(value) or 0)
	if minimum ~= nil then
		return math.max(minimum, numberValue)
	end

	return numberValue
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

local function normalizeOfferKey(value: any): string
	local normalized = normalizeString(value)
	if normalized == "" then
		return ""
	end

	return LEGACY_OFFER_KEY_MAP[normalized] or normalized
end

local function clonePurchaseRecord(record: any)
	if typeof(record) ~= "table" then
		return nil
	end

	local offerKey = normalizeOfferKey(record.offerKey)
	local saleKind = normalizeString(record.saleKind)
	local purchaseKind = normalizeString(record.purchaseKind)
	local saleRobloxId = tonumber(record.saleRobloxId)
	if offerKey == "" or saleKind == "" or purchaseKind == "" or saleRobloxId == nil then
		return nil
	end

	return {
		offerKey = offerKey,
		saleKind = saleKind,
		purchaseKind = purchaseKind,
		saleRobloxId = math.floor(saleRobloxId),
		processedAt = math.max(0, toWholeNumber(record.processedAt, 0)),
	}
end

local function cloneOwnershipRecord(record: any)
	if typeof(record) ~= "table" then
		return nil
	end

	return {
		ownedAt = math.max(0, toWholeNumber(record.ownedAt, 0)),
		source = normalizeString(record.source),
		saleRobloxId = math.max(0, toWholeNumber(record.saleRobloxId, 0)),
		purchaseId = normalizeString(record.purchaseId),
		senderUserId = math.max(0, toWholeNumber(record.senderUserId, 0)),
		recipientUserId = math.max(0, toWholeNumber(record.recipientUserId, 0)),
	}
end

local function clonePendingGiftRecord(record: any)
	if typeof(record) ~= "table" then
		return nil
	end

	local offerKey = normalizeOfferKey(record.offerKey)
	local recipientUserId = tonumber(record.recipientUserId)
	if offerKey == "" or recipientUserId == nil then
		return nil
	end

	return {
		offerKey = offerKey,
		recipientUserId = math.floor(recipientUserId),
		createdAt = math.max(0, toWholeNumber(record.createdAt, 0)),
	}
end

local function cloneGiftRecord(record: any)
	if typeof(record) ~= "table" then
		return nil
	end

	local giftId = normalizeString(record.giftId)
	local offerKey = normalizeOfferKey(record.offerKey)
	local status = normalizeString(record.status)
	if giftId == "" or offerKey == "" then
		return nil
	end

	return {
		giftId = giftId,
		offerKey = offerKey,
		senderUserId = math.max(0, toWholeNumber(record.senderUserId, 0)),
		recipientUserId = math.max(0, toWholeNumber(record.recipientUserId, 0)),
		saleRobloxId = math.max(0, toWholeNumber(record.saleRobloxId, 0)),
		purchaseId = normalizeString(record.purchaseId),
		status = if status ~= "" then status else "pending",
		createdAt = math.max(0, toWholeNumber(record.createdAt, 0)),
		deliveredAt = math.max(0, toWholeNumber(record.deliveredAt, 0)),
	}
end

function MarketplaceState.CreateEmpty()
	return {
		version = MarketplaceState.VERSION,
		purchaseIds = {},
		entitlementsByKey = {},
		oneTimePurchasesByKey = {},
		pendingGiftPromptsByProductId = {},
		gifts = {
			inboxById = {},
			historyById = {},
			failedById = {},
		},
	}
end

function MarketplaceState.Normalize(value: any, legacyPurchaseLog: any?)
	local normalized = MarketplaceState.CreateEmpty()
	local source = if typeof(value) == "table" then value else {}

	normalized.version = MarketplaceState.VERSION

	if typeof(source.purchaseIds) == "table" then
		for purchaseId, record in pairs(source.purchaseIds) do
			local purchaseRecord = clonePurchaseRecord(record)
			if purchaseRecord then
				normalized.purchaseIds[normalizeString(purchaseId)] = purchaseRecord
			end
		end
	end

	if typeof(source.entitlementsByKey) == "table" then
		for offerKey, record in pairs(source.entitlementsByKey) do
			local normalizedOfferKey = normalizeOfferKey(offerKey)
			local ownershipRecord = cloneOwnershipRecord(record)
			if normalizedOfferKey ~= "" and ownershipRecord then
				normalized.entitlementsByKey[normalizedOfferKey] = ownershipRecord
			end
		end
	end

	if typeof(source.oneTimePurchasesByKey) == "table" then
		for offerKey, record in pairs(source.oneTimePurchasesByKey) do
			local normalizedOfferKey = normalizeOfferKey(offerKey)
			local ownershipRecord = cloneOwnershipRecord(record)
			if normalizedOfferKey ~= "" and ownershipRecord then
				normalized.oneTimePurchasesByKey[normalizedOfferKey] = ownershipRecord
			end
		end
	end

	if typeof(source.pendingGiftPromptsByProductId) == "table" then
		for productId, record in pairs(source.pendingGiftPromptsByProductId) do
			local pendingGiftRecord = clonePendingGiftRecord(record)
			if pendingGiftRecord then
				normalized.pendingGiftPromptsByProductId[tostring(math.floor(tonumber(productId) or 0))] = pendingGiftRecord
			end
		end
	end

	local gifts = if typeof(source.gifts) == "table" then source.gifts else {}
	if typeof(gifts.inboxById) == "table" then
		for giftId, record in pairs(gifts.inboxById) do
			local giftRecord = cloneGiftRecord(record)
			if giftRecord then
				normalized.gifts.inboxById[normalizeString(giftId)] = giftRecord
			end
		end
	end
	if typeof(gifts.historyById) == "table" then
		for giftId, record in pairs(gifts.historyById) do
			local giftRecord = cloneGiftRecord(record)
			if giftRecord then
				normalized.gifts.historyById[normalizeString(giftId)] = giftRecord
			end
		end
	end
	if typeof(gifts.failedById) == "table" then
		for giftId, record in pairs(gifts.failedById) do
			local giftRecord = cloneGiftRecord(record)
			if giftRecord then
				normalized.gifts.failedById[normalizeString(giftId)] = giftRecord
			end
		end
	end

	local legacy = if typeof(legacyPurchaseLog) == "table" then legacyPurchaseLog else {}
	local legacyProducts = if typeof(legacy.products) == "table" then legacy.products else {}
	for productId, record in pairs(legacyProducts) do
		if typeof(record) == "table" then
			local offerKey = normalizeOfferKey(record.key)
			local saleRobloxId = tonumber(productId)
			if saleRobloxId ~= nil then
				for purchaseId, processedAt in pairs(record) do
					if purchaseId ~= "key" then
						local purchaseIdString = normalizeString(purchaseId)
						if purchaseIdString ~= "" and normalized.purchaseIds[purchaseIdString] == nil then
							normalized.purchaseIds[purchaseIdString] = {
								offerKey = offerKey,
								saleKind = "product",
								purchaseKind = "self",
								saleRobloxId = math.floor(saleRobloxId),
								processedAt = math.max(0, toWholeNumber(processedAt, 0)),
							}
						end
					end
				end
			end

			if offerKey == "starter_pack" and normalized.oneTimePurchasesByKey.starter_pack == nil then
				normalized.oneTimePurchasesByKey.starter_pack = {
					ownedAt = os.time(),
					source = "legacy",
					saleRobloxId = math.max(0, toWholeNumber(productId, 0)),
					purchaseId = "",
					senderUserId = 0,
					recipientUserId = 0,
				}
			end
		end
	end

	local legacyPasses = if typeof(legacy.passes) == "table" then legacy.passes else {}
	for passId, record in pairs(legacyPasses) do
		if typeof(record) == "table" then
			local offerKey = normalizeOfferKey(record.key)
			if offerKey ~= "" and normalized.entitlementsByKey[offerKey] == nil then
				normalized.entitlementsByKey[offerKey] = {
					ownedAt = math.max(0, toWholeNumber(record.firstSeen or record.lastVerified, 0)),
					source = normalizeString(record.via),
					saleRobloxId = math.max(0, toWholeNumber(passId, 0)),
					purchaseId = "",
					senderUserId = 0,
					recipientUserId = 0,
				}
			end
		end
	end

	return normalized
end

return MarketplaceState
