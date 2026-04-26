local ArmAccessoryConfig = {}

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

export type ArmAccessoryConfigEntry = {
	id: string,
	slot: "ArmAccessory",
	label: string,
	description: string,
	tierLabel: string,
	sortOrder: number,
	displayColor: Color3,
	assetModelName: string?,
	iconTexture: string?,
	bonuses: AccessoryBonusConfig,
}

local ENTRIES: { ArmAccessoryConfigEntry } = {
	{
		id = "training_bracer",
		slot = "ArmAccessory",
		label = "Training Bracer",
		description = "A placeholder arm accessory for early crafting tests.",
		tierLabel = "Common",
		sortOrder = 10,
		displayColor = Color3.fromRGB(113, 230, 139),
		assetModelName = nil,
		iconTexture = "",
		bonuses = {
			damageBonus = 3,
			speedBonus = 0.5,
			passiveIncomePerSecondBonus = 0.15,
		},
	},
	{
		id = "golden_gauntlet",
		slot = "ArmAccessory",
		label = "Golden Gauntlet",
		description = "A placeholder arm accessory that improves income and strength.",
		tierLabel = "Uncommon",
		sortOrder = 20,
		displayColor = Color3.fromRGB(255, 184, 77),
		assetModelName = nil,
		iconTexture = "",
		bonuses = {
			passiveIncomeMultiplier = 1.05,
			damageBonus = 6,
			healthBonus = 10,
		},
	},
}

local entriesById: { [string]: ArmAccessoryConfigEntry } = {}
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

function ArmAccessoryConfig.NormalizeId(accessoryId: any): string?
	return normalizeId(accessoryId)
end

function ArmAccessoryConfig.Get(accessoryId: any): ArmAccessoryConfigEntry?
	local normalizedId = normalizeId(accessoryId)
	return if normalizedId then entriesById[string.lower(normalizedId)] else nil
end

function ArmAccessoryConfig.GetAll(): { ArmAccessoryConfigEntry }
	local results = table.create(#ENTRIES)
	for index, entry in ipairs(ENTRIES) do
		results[index] = entry
	end
	return results
end

return table.freeze(ArmAccessoryConfig)
