local MerchantShopConfig = {}

export type MerchantShopEntry = {
	potionId: string,
	shopLabel: string,
	description: string,
	sortOrder: number,
}

local ENTRIES: { MerchantShopEntry } = {
	{
		potionId = "luck",
		shopLabel = "Luck Potion",
		description = "Barto keeps this bottle corked tight. Crack it open when you want fortune to start leaning your way.",
		sortOrder = 1,
	},
	{
		potionId = "rollSpeed",
		shopLabel = "Roll Potion",
		description = "For rollers with no patience left. One sip and the next pull comes around a whole lot quicker.",
		sortOrder = 2,
	},
	{
		potionId = "money",
		shopLabel = "Money Potion",
		description = "A sharp little brew for turning steady work into heavier pockets before the next upgrade run.",
		sortOrder = 3,
	},
}

local entriesByPotionId: { [string]: MerchantShopEntry } = {}

for _, entry in ipairs(ENTRIES) do
	entriesByPotionId[entry.potionId] = table.freeze(entry)
end

function MerchantShopConfig.GetAll(): { MerchantShopEntry }
	local results = table.create(#ENTRIES)
	for index, entry in ipairs(ENTRIES) do
		results[index] = entry
	end
	return results
end

function MerchantShopConfig.GetByPotionId(potionId: string): MerchantShopEntry?
	return entriesByPotionId[potionId]
end

return table.freeze(MerchantShopConfig)
