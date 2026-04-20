local BodyPartCollection = require(script.Parent.Parent.Character.BodyPartCollection)

local PlayerStats = {}

PlayerStats.VERSION = 1

PlayerStats.EARNED_MONEY_SOURCES = {
	passive_income = true,
	offline_income = true,
	sell_single = true,
	sell_bulk = true,
	purchase_reward = true,
	admin = true,
	other = true,
}

PlayerStats.SPENT_MONEY_SOURCES = {
	roll_cost = true,
	appraisal_cost = true,
	admin = true,
	other = true,
}

PlayerStats.ROLL_FAILURE_REASONS = {
	locked = true,
	insufficient_money = true,
	invalid_selection = true,
	missing_config = true,
	grant_failed = true,
	unexpected_error = true,
}

PlayerStats.LOADOUT_ACTIONS = {
	equip = "equipActions",
	unequip = "unequipActions",
	clear = "clearActions",
}

PlayerStats.SETTING_CHANGE_KINDS = {
	roll_type = "rollTypeChanges",
	roll_region = "rollRegionChanges",
	quick_roll = "quickRollToggleCount",
	auto_sell = "autoSellToggleCount",
	cutscene = "cutsceneToggleCount",
}

local function toWholeNumber(value: any, minimum: number?): number
	local numberValue = math.floor(tonumber(value) or 0)
	if minimum ~= nil then
		return math.max(minimum, numberValue)
	end

	return numberValue
end

local function toPositiveNumber(value: any, fallback: number): number
	local numberValue = tonumber(value)
	if numberValue == nil or numberValue <= 0 or numberValue ~= numberValue then
		return fallback
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

local function cloneBooleanMap(value: any): { [string]: boolean }
	local clone = {}
	if typeof(value) ~= "table" then
		return clone
	end

	for key, child in pairs(value) do
		if child == true and typeof(key) == "string" and key ~= "" then
			clone[key] = true
		end
	end

	return clone
end

local function countBooleanMapEntries(value: any): number
	local total = 0
	if typeof(value) ~= "table" then
		return total
	end

	for _, child in pairs(value) do
		if child == true then
			total += 1
		end
	end

	return total
end

local function cloneCounterMap(value: any): { [string]: number }
	local clone = {}
	if typeof(value) ~= "table" then
		return clone
	end

	for key, child in pairs(value) do
		if typeof(key) == "string" and key ~= "" then
			clone[key] = math.max(0, toWholeNumber(child, 0))
		end
	end

	return clone
end

local function mergeCounterMaps(...)
	local merged = {}
	for _, value in ipairs({ ... }) do
		if typeof(value) == "table" then
			for key, amount in pairs(value) do
				if typeof(key) == "string" and key ~= "" then
					merged[key] = math.max(0, toWholeNumber(merged[key], 0)) + math.max(0, toWholeNumber(amount, 0))
				end
			end
		end
	end

	return merged
end

local function cloneFixedCounterMap(value: any, allowedKeys: { [string]: boolean }): { [string]: number }
	local clone = {}
	for key in pairs(allowedKeys) do
		clone[key] = 0
	end

	if typeof(value) ~= "table" then
		return clone
	end

	for key in pairs(allowedKeys) do
		clone[key] = math.max(0, toWholeNumber(value[key], 0))
	end

	return clone
end

local function countOwnedRecords(state: any): number
	local ownedById = if typeof(state) == "table" then state.ownedById else nil
	local total = 0
	if typeof(ownedById) ~= "table" then
		return total
	end

	for _, record in pairs(ownedById) do
		if typeof(record) == "table" then
			total += 1
		end
	end

	return total
end

local function getCompletedSetIds(bodyPartsState: any): { [string]: boolean }
	local completedSetIds = {}
	for _, summary in ipairs(BodyPartCollection.GetAllSetSummaries(bodyPartsState)) do
		if summary.ownsFullSet then
			completedSetIds[summary.setId] = true
		end
	end

	return completedSetIds
end

local function normalizeBestEver(value: any): any
	local bestEver = if typeof(value) == "table" then value else {}
	return {
		displayedDenominator = math.max(0, toWholeNumber(bestEver.displayedDenominator, 0)),
		pieceId = normalizeString(bestEver.pieceId),
		setId = normalizeString(bestEver.setId),
		displayRarity = normalizeString(bestEver.displayRarity),
		mutationId = normalizeString(bestEver.mutationId),
		sizeId = normalizeString(bestEver.sizeId),
		variantMultiplier = toPositiveNumber(bestEver.variantMultiplier, 1),
		serialNumber = math.max(0, toWholeNumber(bestEver.serialNumber, 0)),
		achievedAt = math.max(0, toWholeNumber(bestEver.achievedAt, 0)),
	}
end

function PlayerStats.CreateEmpty(): any
	return {
		version = PlayerStats.VERSION,
		lifecycle = {
			joinCount = 0,
			firstSeenAt = 0,
			lastJoinAt = 0,
			lastLeaveAt = 0,
			lastSessionLengthSeconds = 0,
			longestSessionSeconds = 0,
		},
		economy = {
			lifetimeEarned = 0,
			lifetimeSpent = 0,
			highestMoneyHeld = 0,
			earnedBySource = cloneFixedCounterMap(nil, PlayerStats.EARNED_MONEY_SOURCES),
			spentBySource = cloneFixedCounterMap(nil, PlayerStats.SPENT_MONEY_SOURCES),
		},
		rolls = {
			totalRequests = 0,
			failedByReason = cloneFixedCounterMap(nil, PlayerStats.ROLL_FAILURE_REASONS),
			byRollType = {},
			byRegion = {},
			byRarity = {},
			bySetId = {},
			byMutationId = {},
			bySizeId = {},
			autoSellQueued = 0,
			autoSold = 0,
			autoSellKept = 0,
			firstTimeDiscoveries = 0,
			bestEver = normalizeBestEver(nil),
		},
		collection = {
			totalBodyPartsAcquired = 0,
			totalBodyPartsSold = 0,
			totalAurasAcquired = 0,
			setsCompletedFirstTime = 0,
			peakOwnedBodyParts = 0,
			seenCompletedSetIds = {},
		},
		loadout = {
			equipActions = 0,
			unequipActions = 0,
			clearActions = 0,
		},
		monetization = {
			firstPurchaseAt = 0,
			firstPurchaseKey = "",
			promptShownByKey = {},
			purchaseGrantedByKey = {},
			selfPurchaseByKey = {},
			giftPurchaseByKey = {},
			giftsSentByKey = {},
			giftsDeliveredByKey = {},
			giftsReceivedByKey = {},
			duplicateGiftBlockedByKey = {},
		},
		settings = {
			rollTypeChanges = 0,
			rollRegionChanges = 0,
			quickRollToggleCount = 0,
			autoSellToggleCount = 0,
			cutsceneToggleCount = 0,
		},
	}
end

function PlayerStats.Normalize(value: any, options: any?): any
	local normalized = PlayerStats.CreateEmpty()
	local source = if typeof(value) == "table" then value else {}
	local lifecycle = if typeof(source.lifecycle) == "table" then source.lifecycle else {}
	local economy = if typeof(source.economy) == "table" then source.economy else {}
	local rolls = if typeof(source.rolls) == "table" then source.rolls else {}
	local collection = if typeof(source.collection) == "table" then source.collection else {}
	local loadout = if typeof(source.loadout) == "table" then source.loadout else {}
	local monetization = if typeof(source.monetization) == "table" then source.monetization else {}
	local settings = if typeof(source.settings) == "table" then source.settings else {}
	local bodyPartsState = if typeof(options) == "table" then options.bodyPartsState else nil
	local aurasState = if typeof(options) == "table" then options.aurasState else nil
	local currentMoney = if typeof(options) == "table" then tonumber(options.currentMoney) else nil
	local diagnostics = if typeof(options) == "table" and typeof(options.diagnostics) == "table" then options.diagnostics else {}
	local successfulRollCount = if typeof(options) == "table" then tonumber(options.successfulRollCount) else nil

	normalized.version = PlayerStats.VERSION

	normalized.lifecycle.joinCount = math.max(
		toWholeNumber(lifecycle.joinCount, 0),
		toWholeNumber(diagnostics.joins, 0)
	)
	normalized.lifecycle.firstSeenAt = math.max(0, toWholeNumber(lifecycle.firstSeenAt, 0))
	normalized.lifecycle.lastJoinAt = math.max(
		toWholeNumber(lifecycle.lastJoinAt, 0),
		toWholeNumber(diagnostics.joinTime, 0)
	)
	normalized.lifecycle.lastLeaveAt = math.max(
		toWholeNumber(lifecycle.lastLeaveAt, 0),
		toWholeNumber(diagnostics.leaveTime, 0)
	)
	normalized.lifecycle.lastSessionLengthSeconds = math.max(0, toWholeNumber(lifecycle.lastSessionLengthSeconds, 0))
	normalized.lifecycle.longestSessionSeconds = math.max(0, toWholeNumber(lifecycle.longestSessionSeconds, 0))

	normalized.economy.lifetimeEarned = math.max(0, toWholeNumber(economy.lifetimeEarned, 0))
	normalized.economy.lifetimeSpent = math.max(0, toWholeNumber(economy.lifetimeSpent, 0))
	normalized.economy.highestMoneyHeld = math.max(
		math.max(0, toWholeNumber(economy.highestMoneyHeld, 0)),
		math.max(0, toWholeNumber(currentMoney, 0))
	)
	normalized.economy.earnedBySource = cloneFixedCounterMap(economy.earnedBySource, PlayerStats.EARNED_MONEY_SOURCES)
	normalized.economy.spentBySource = cloneFixedCounterMap(economy.spentBySource, PlayerStats.SPENT_MONEY_SOURCES)

	normalized.rolls.totalRequests = math.max(
		math.max(0, toWholeNumber(rolls.totalRequests, 0)),
		math.max(0, toWholeNumber(successfulRollCount, 0))
	)
	normalized.rolls.failedByReason = cloneFixedCounterMap(rolls.failedByReason, PlayerStats.ROLL_FAILURE_REASONS)
	normalized.rolls.byRollType = cloneCounterMap(rolls.byRollType)
	normalized.rolls.byRegion = cloneCounterMap(rolls.byRegion)
	normalized.rolls.byRarity = cloneCounterMap(rolls.byRarity)
	normalized.rolls.bySetId = cloneCounterMap(rolls.bySetId)
	normalized.rolls.byMutationId = cloneCounterMap(rolls.byMutationId)
	normalized.rolls.bySizeId = cloneCounterMap(rolls.bySizeId)
	normalized.rolls.autoSellQueued = math.max(0, toWholeNumber(rolls.autoSellQueued, 0))
	normalized.rolls.autoSold = math.max(0, toWholeNumber(rolls.autoSold, 0))
	normalized.rolls.autoSellKept = math.max(0, toWholeNumber(rolls.autoSellKept, 0))
	normalized.rolls.firstTimeDiscoveries = math.max(
		math.max(0, toWholeNumber(rolls.firstTimeDiscoveries, 0)),
		if typeof(bodyPartsState) == "table"
			then countBooleanMapEntries(bodyPartsState.discoveredPieceIds)
			else 0
	)
	normalized.rolls.bestEver = normalizeBestEver(rolls.bestEver)

	normalized.collection.totalBodyPartsAcquired = math.max(
		math.max(0, toWholeNumber(collection.totalBodyPartsAcquired, 0)),
		countOwnedRecords(bodyPartsState)
	)
	normalized.collection.totalBodyPartsSold = math.max(0, toWholeNumber(collection.totalBodyPartsSold, 0))
	normalized.collection.totalAurasAcquired = math.max(
		math.max(0, toWholeNumber(collection.totalAurasAcquired, 0)),
		countOwnedRecords(aurasState)
	)
	normalized.collection.peakOwnedBodyParts = math.max(
		math.max(0, toWholeNumber(collection.peakOwnedBodyParts, 0)),
		countOwnedRecords(bodyPartsState)
	)
	normalized.collection.seenCompletedSetIds = cloneBooleanMap(collection.seenCompletedSetIds)
	if next(normalized.collection.seenCompletedSetIds) == nil and typeof(bodyPartsState) == "table" then
		normalized.collection.seenCompletedSetIds = getCompletedSetIds(bodyPartsState)
	end
	normalized.collection.setsCompletedFirstTime = math.max(
		math.max(0, toWholeNumber(collection.setsCompletedFirstTime, 0)),
		countBooleanMapEntries(normalized.collection.seenCompletedSetIds)
	)

	normalized.loadout.equipActions = math.max(0, toWholeNumber(loadout.equipActions, 0))
	normalized.loadout.unequipActions = math.max(0, toWholeNumber(loadout.unequipActions, 0))
	normalized.loadout.clearActions = math.max(0, toWholeNumber(loadout.clearActions, 0))

	normalized.monetization.firstPurchaseAt = math.max(0, toWholeNumber(monetization.firstPurchaseAt, 0))
	normalized.monetization.firstPurchaseKey = normalizeString(monetization.firstPurchaseKey)
	normalized.monetization.promptShownByKey = mergeCounterMaps(
		cloneCounterMap(monetization.promptShownByKey),
		cloneCounterMap(monetization.passPromptShownByKey)
	)
	normalized.monetization.purchaseGrantedByKey = mergeCounterMaps(
		cloneCounterMap(monetization.purchaseGrantedByKey),
		cloneCounterMap(monetization.passPurchasedByKey),
		cloneCounterMap(monetization.productPurchasedByKey)
	)
	normalized.monetization.selfPurchaseByKey = mergeCounterMaps(
		cloneCounterMap(monetization.selfPurchaseByKey),
		cloneCounterMap(monetization.passPurchasedByKey),
		cloneCounterMap(monetization.productPurchasedByKey)
	)
	normalized.monetization.giftPurchaseByKey = cloneCounterMap(monetization.giftPurchaseByKey)
	normalized.monetization.giftsSentByKey = cloneCounterMap(monetization.giftsSentByKey)
	normalized.monetization.giftsDeliveredByKey = cloneCounterMap(monetization.giftsDeliveredByKey)
	normalized.monetization.giftsReceivedByKey = cloneCounterMap(monetization.giftsReceivedByKey)
	normalized.monetization.duplicateGiftBlockedByKey = cloneCounterMap(monetization.duplicateGiftBlockedByKey)

	normalized.settings.rollTypeChanges = math.max(0, toWholeNumber(settings.rollTypeChanges, 0))
	normalized.settings.rollRegionChanges = math.max(0, toWholeNumber(settings.rollRegionChanges, 0))
	normalized.settings.quickRollToggleCount = math.max(0, toWholeNumber(settings.quickRollToggleCount, 0))
	normalized.settings.autoSellToggleCount = math.max(0, toWholeNumber(settings.autoSellToggleCount, 0))
	normalized.settings.cutsceneToggleCount = math.max(0, toWholeNumber(settings.cutsceneToggleCount, 0))

	return normalized
end

function PlayerStats.GetCompletedSetIds(bodyPartsState: any): { [string]: boolean }
	return getCompletedSetIds(bodyPartsState)
end

function PlayerStats.CountOwnedBodyParts(bodyPartsState: any): number
	return countOwnedRecords(bodyPartsState)
end

function PlayerStats.CountOwnedAuras(aurasState: any): number
	return countOwnedRecords(aurasState)
end

function PlayerStats.NormalizeEarnedMoneySource(source: any): string
	local normalizedSource = normalizeString(source)
	if PlayerStats.EARNED_MONEY_SOURCES[normalizedSource] == true then
		return normalizedSource
	end

	return "other"
end

function PlayerStats.NormalizeSpentMoneySource(source: any): string
	local normalizedSource = normalizeString(source)
	if PlayerStats.SPENT_MONEY_SOURCES[normalizedSource] == true then
		return normalizedSource
	end

	return "other"
end

function PlayerStats.NormalizeRollFailureReason(reason: any): string
	local normalizedReason = normalizeString(reason)
	if PlayerStats.ROLL_FAILURE_REASONS[normalizedReason] == true then
		return normalizedReason
	end

	return "unexpected_error"
end

function PlayerStats.NormalizeLoadoutAction(action: any): string?
	local normalizedAction = normalizeString(action)
	return PlayerStats.LOADOUT_ACTIONS[normalizedAction]
end

function PlayerStats.NormalizeSettingChangeKind(kind: any): string?
	local normalizedKind = normalizeString(kind)
	return PlayerStats.SETTING_CHANGE_KINDS[normalizedKind]
end

function PlayerStats.ShouldReplaceBestEver(currentBestEver: any, candidateBestEver: any): boolean
	local current = normalizeBestEver(currentBestEver)
	local candidate = normalizeBestEver(candidateBestEver)

	if candidate.displayedDenominator ~= current.displayedDenominator then
		return candidate.displayedDenominator > current.displayedDenominator
	end

	if candidate.variantMultiplier ~= current.variantMultiplier then
		return candidate.variantMultiplier > current.variantMultiplier
	end

	if current.serialNumber <= 0 then
		return candidate.serialNumber > 0
	end
	if candidate.serialNumber <= 0 then
		return false
	end

	return candidate.serialNumber < current.serialNumber
end

return PlayerStats
