local PotionConfig = require(script.Parent.PotionConfig)

local MerchantShopConfig = {}

export type MerchantShopEntry = {
	potionId: string,
	shopLabel: string,
	description: string,
	sortOrder: number,
	appearanceChance: number,
	stockPerRefresh: number,
	priceInTimeShards: number,
}

local TIER_STOCK_BY_TIER = {
	[1] = {
		appearanceChance = 0.50,
		stockPerRefresh = 1,
	},
	[2] = {
		appearanceChance = 0.30,
		stockPerRefresh = 1,
	},
	[3] = {
		appearanceChance = 0.167,
		stockPerRefresh = 1,
	},
	[4] = {
		appearanceChance = 0.028,
		stockPerRefresh = 1,
	},
	[5] = {
		appearanceChance = 0.021,
		stockPerRefresh = 1,
	},
}

local function resolveStockPerRefresh(rawStockPerRefresh: any): number
	return math.clamp(math.floor(tonumber(rawStockPerRefresh) or 0), 0, 1)
end

local FAMILY_DESCRIPTIONS = {
	money = {
		"A lean starter brew for squeezing a little more cash out of every passive tick.",
		"A steadier profit tonic for players trying to climb into the next spending bracket.",
		"The merchant's dependable income mixer when you want your pockets filling fast.",
		"A premium vault-strength draught that turns a short grind window into a payout spike.",
		"A black-market liquid jackpot meant for massive bursts of passive income.",
	},
	luck = {
		"A beginner's fortune bottle that nudges the odds without breaking the bank.",
		"A sharper luck blend for when you want the next stretch of rolls to feel noticeably better.",
		"The merchant's favorite lucky mix for serious progression pushes.",
		"A potent charm tonic that makes high-value hits much more realistic for a short run.",
		"An ultra-rare fortune brew reserved for players chasing the biggest upgrades in the game.",
	},
	size = {
		"A starter size charm that nudges rolls away from smaller limbs.",
		"A stronger size-luck mix for chasing larger body part variants.",
		"A dependable size draught when you want bigger finds more often.",
		"A premium size blend that makes huge limbs more realistic for a short run.",
		"The merchant's rarest size stock, built for chasing the biggest variants.",
	},
	rollSpeed = {
		"A light-speed sip for cutting some drag off your early roll cadence.",
		"A stronger accelerator that keeps your rolls moving when the grind starts to drag.",
		"A workhorse speed potion for players who want noticeably faster loops right away.",
		"A volatile fast-roll formula for burst farming sessions and rapid pull chains.",
		"The merchant's rarest speed stock, built for all-out high-tier rolling windows.",
	},
}

local ENTRIES: { MerchantShopEntry } = {}
local entriesByPotionId: { [string]: MerchantShopEntry } = {}

for _, potionConfig in ipairs(PotionConfig.GetAll()) do
	local tierStock = TIER_STOCK_BY_TIER[potionConfig.tier]
	local familyDescriptions = FAMILY_DESCRIPTIONS[potionConfig.familyId]
	local entry: MerchantShopEntry = {
		potionId = potionConfig.id,
		shopLabel = potionConfig.label,
		description = potionConfig.merchantDescription
			or potionConfig.effectDescription
			or (familyDescriptions and familyDescriptions[potionConfig.tier])
			or string.format("%s in short supply.", potionConfig.label),
		sortOrder = potionConfig.sortOrder,
		appearanceChance = tonumber(potionConfig.merchantAppearanceChance)
			or (tierStock and tierStock.appearanceChance)
			or 0,
		stockPerRefresh = resolveStockPerRefresh(
			tonumber(potionConfig.merchantStockPerRefresh)
				or (tierStock and tierStock.stockPerRefresh)
				or 0
		),
		priceInTimeShards = math.max(
			0,
			math.floor(tonumber(potionConfig.merchantPriceInTimeShards) or tonumber(potionConfig.buyPrice) or 0)
		),
	}

	local frozenEntry = table.freeze(entry)
	table.insert(ENTRIES, frozenEntry)
	entriesByPotionId[potionConfig.id] = frozenEntry
end

table.sort(ENTRIES, function(left, right)
	if left.sortOrder ~= right.sortOrder then
		return left.sortOrder < right.sortOrder
	end

	return left.potionId < right.potionId
end)

function MerchantShopConfig.GetAll(): { MerchantShopEntry }
	local results = table.create(#ENTRIES)
	for index, entry in ipairs(ENTRIES) do
		results[index] = entry
	end
	return results
end

function MerchantShopConfig.GetByPotionId(potionId: string): MerchantShopEntry?
	local normalizedPotionId = PotionConfig.NormalizeId(potionId)
	return if normalizedPotionId then entriesByPotionId[normalizedPotionId] else nil
end

function MerchantShopConfig.GetMaxStockForPotionId(potionId: string): number
	local entry = MerchantShopConfig.GetByPotionId(potionId)
	return math.max(0, math.floor(tonumber(entry and entry.stockPerRefresh) or 0))
end

function MerchantShopConfig.GetPriceInTimeShards(potionId: string): number
	local entry = MerchantShopConfig.GetByPotionId(potionId)
	return math.max(0, math.floor(tonumber(entry and entry.priceInTimeShards) or 0))
end

return table.freeze(MerchantShopConfig)
