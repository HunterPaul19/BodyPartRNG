local PotionConfig = {}

export type PotionConfigEntry = {
	id: string,
	label: string,
	assetModelName: string,
	buyPrice: number,
	durationSeconds: number,
	sortOrder: number,
	passiveIncomeMultiplier: number?,
	luckBonus: number?,
	rollSpeedBonus: number?,
}

local ENTRIES: { PotionConfigEntry } = {
	{
		id = "money",
		label = "Money Potion",
		assetModelName = "Money",
		buyPrice = 1000,
		durationSeconds = 300,
		sortOrder = 1,
		passiveIncomeMultiplier = 2,
	},
	{
		id = "luck",
		label = "Luck Potion",
		assetModelName = "Luck",
		buyPrice = 1000,
		durationSeconds = 300,
		sortOrder = 2,
		luckBonus = 1.0,
	},
	{
		id = "rollSpeed",
		label = "Roll Speed Potion",
		assetModelName = "Roll Speed",
		buyPrice = 1000,
		durationSeconds = 300,
		sortOrder = 3,
		rollSpeedBonus = 1.0,
	},
}

local entriesById: { [string]: PotionConfigEntry } = {}

for _, entry in ipairs(ENTRIES) do
	entriesById[entry.id] = table.freeze(entry)
end

local function normalizeId(potionId: any): string?
	if typeof(potionId) ~= "string" then
		return nil
	end

	local trimmed = string.match(string.lower(potionId), "%S.*")
	if not trimmed or trimmed == "" then
		return nil
	end

	return if entriesById[trimmed] then trimmed else nil
end

function PotionConfig.NormalizeId(potionId: any): string?
	return normalizeId(potionId)
end

function PotionConfig.Get(potionId: any): PotionConfigEntry?
	local normalizedId = normalizeId(potionId)
	return if normalizedId then entriesById[normalizedId] else nil
end

function PotionConfig.GetAll(): { PotionConfigEntry }
	local results = table.create(#ENTRIES)
	for index, entry in ipairs(ENTRIES) do
		results[index] = entry
	end
	return results
end

function PotionConfig.GetSellPrice(potionId: any): number
	local entry = PotionConfig.Get(potionId)
	if not entry then
		return 0
	end

	return math.max(0, math.floor((tonumber(entry.buyPrice) or 0) / 2))
end

return table.freeze(PotionConfig)
