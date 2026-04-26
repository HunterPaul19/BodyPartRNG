local HeadAccessoryConfig = {}

export type AccessoryBonusConfig = {
	passiveIncomePerSecondBonus: number?,
	passiveIncomeMultiplier: number?,
	luckBonus: number?,
	luckMultiplier: number?,
	rollSpeedBonus: number?,
	speedBonus: number?,
	damageBonus: number?,
	healthBonus: number?,
}

export type HeadAccessoryConfigEntry = {
	id: string,
	slot: "HeadAccessory",
	label: string,
	description: string,
	tierLabel: string,
	sortOrder: number,
	displayColor: Color3,
	assetModelName: string?,
	iconTexture: string?,
	bonuses: AccessoryBonusConfig,
}

local ENTRIES: { HeadAccessoryConfigEntry } = {
	{
		id = "paper_crown",
		slot = "HeadAccessory",
		label = "Paper Crown",
		description = "A placeholder head accessory for early crafting tests.",
		tierLabel = "Common",
		sortOrder = 10,
		displayColor = Color3.fromRGB(255, 221, 95),
		assetModelName = nil,
		iconTexture = "",
		bonuses = {
			luckBonus = 0.05,
			passiveIncomePerSecondBonus = 0.25,
			healthBonus = 5,
		},
	},
	{
		id = "lucky_visor",
		slot = "HeadAccessory",
		label = "Lucky Visor",
		description = "A placeholder head accessory with stronger luck scaling.",
		tierLabel = "Uncommon",
		sortOrder = 20,
		displayColor = Color3.fromRGB(116, 192, 255),
		assetModelName = nil,
		iconTexture = "",
		bonuses = {
			luckBonus = 0.10,
			luckMultiplier = 1.05,
			rollSpeedBonus = 0.03,
		},
	},
}

local entriesById: { [string]: HeadAccessoryConfigEntry } = {}
for _, entry in ipairs(ENTRIES) do
	entriesById[string.lower(entry.id)] = table.freeze(entry)
end
for index, entry in ipairs(ENTRIES) do
	ENTRIES[index] = entriesById[string.lower(entry.id)]
end
table.freeze(ENTRIES)

local function normalizeId(accessoryId: any): string?
	if typeof(accessoryId) ~= "string" then
		return nil
	end

	local trimmed = string.match(accessoryId, "^%s*(.-)%s*$")
	if not trimmed or trimmed == "" then
		return nil
	end

	local entry = entriesById[string.lower(trimmed)]
	return if entry then entry.id else nil
end

function HeadAccessoryConfig.NormalizeId(accessoryId: any): string?
	return normalizeId(accessoryId)
end

function HeadAccessoryConfig.Get(accessoryId: any): HeadAccessoryConfigEntry?
	local normalizedId = normalizeId(accessoryId)
	return if normalizedId then entriesById[string.lower(normalizedId)] else nil
end

function HeadAccessoryConfig.GetAll(): { HeadAccessoryConfigEntry }
	local results = table.create(#ENTRIES)
	for index, entry in ipairs(ENTRIES) do
		results[index] = entry
	end
	return results
end

return table.freeze(HeadAccessoryConfig)
