local PotionConfig = {}

export type PotionFamilyId = "money" | "luck" | "rollSpeed"

export type PotionConfigEntry = {
	id: string,
	familyId: PotionFamilyId,
	familyLabel: string,
	tier: number,
	tierLabel: string,
	label: string,
	assetModelName: string,
	buyPrice: number,
	durationSeconds: number,
	sortOrder: number,
	passiveIncomeMultiplier: number?,
	luckBonus: number?,
	rollSpeedBonus: number?,
}

type PotionFamilyDefinition = {
	id: PotionFamilyId,
	label: string,
	assetPrefix: string,
	sortOrder: number,
}

type PotionTierDefinition = {
	tier: number,
	tierLabel: string,
	buyPrice: number,
	durationSeconds: number,
	passiveIncomeMultiplier: number?,
	luckBonus: number?,
	rollSpeedBonus: number?,
}

local LEGACY_ID_ALIASES = {
	money = "money3",
	luck = "luck3",
	rollspeed = "rollSpeed3",
}

local FAMILY_DEFINITIONS: { PotionFamilyDefinition } = {
	{
		id = "money",
		label = "Money",
		assetPrefix = "Money",
		sortOrder = 1,
	},
	{
		id = "luck",
		label = "Luck",
		assetPrefix = "Luck",
		sortOrder = 2,
	},
	{
		id = "rollSpeed",
		label = "Roll Speed",
		assetPrefix = "RollSpeed",
		sortOrder = 3,
	},
}

local TIER_DEFINITIONS: { PotionTierDefinition } = {
	{
		tier = 1,
		tierLabel = "I",
		buyPrice = 1000,
		durationSeconds = 300,
		passiveIncomeMultiplier = 1.25,
		luckBonus = 0.25,
		rollSpeedBonus = 0.20,
	},
	{
		tier = 2,
		tierLabel = "II",
		buyPrice = 4000,
		durationSeconds = 300,
		passiveIncomeMultiplier = 1.50,
		luckBonus = 0.50,
		rollSpeedBonus = 0.40,
	},
	{
		tier = 3,
		tierLabel = "III",
		buyPrice = 12000,
		durationSeconds = 300,
		passiveIncomeMultiplier = 2.00,
		luckBonus = 1.00,
		rollSpeedBonus = 1.00,
	},
	{
		tier = 4,
		tierLabel = "IV",
		buyPrice = 40000,
		durationSeconds = 300,
		passiveIncomeMultiplier = 2.75,
		luckBonus = 1.50,
		rollSpeedBonus = 1.60,
	},
	{
		tier = 5,
		tierLabel = "V",
		buyPrice = 125000,
		durationSeconds = 300,
		passiveIncomeMultiplier = 4.00,
		luckBonus = 2.25,
		rollSpeedBonus = 2.40,
	},
}

local familyIds = table.create(#FAMILY_DEFINITIONS)
local familyLabelsById: { [string]: string } = {}
local familyEntriesById: { [string]: { PotionConfigEntry } } = {}
local ENTRIES: { PotionConfigEntry } = {}
local entriesById: { [string]: PotionConfigEntry } = {}

for familyIndex, family in ipairs(FAMILY_DEFINITIONS) do
	familyIds[familyIndex] = family.id
	familyLabelsById[family.id] = family.label
	familyEntriesById[family.id] = {}

	for _, tierDefinition in ipairs(TIER_DEFINITIONS) do
		local entry: PotionConfigEntry = {
			id = string.format("%s%d", family.id, tierDefinition.tier),
			familyId = family.id,
			familyLabel = family.label,
			tier = tierDefinition.tier,
			tierLabel = tierDefinition.tierLabel,
			label = string.format("%s Potion %s", family.label, tierDefinition.tierLabel),
			assetModelName = string.format("%s%d", family.assetPrefix, tierDefinition.tier),
			buyPrice = tierDefinition.buyPrice,
			durationSeconds = tierDefinition.durationSeconds,
			sortOrder = ((family.sortOrder - 1) * #TIER_DEFINITIONS) + tierDefinition.tier,
			passiveIncomeMultiplier = if family.id == "money" then tierDefinition.passiveIncomeMultiplier else nil,
			luckBonus = if family.id == "luck" then tierDefinition.luckBonus else nil,
			rollSpeedBonus = if family.id == "rollSpeed" then tierDefinition.rollSpeedBonus else nil,
		}

		local frozenEntry = table.freeze(entry)
		table.insert(ENTRIES, frozenEntry)
		table.insert(familyEntriesById[family.id], frozenEntry)
		entriesById[string.lower(entry.id)] = frozenEntry
	end
end

local function trimAndLower(value: any): string?
	if typeof(value) ~= "string" then
		return nil
	end

	local trimmed = string.match(value, "^%s*(.-)%s*$")
	if not trimmed or trimmed == "" then
		return nil
	end

	return string.lower(trimmed)
end

local function normalizeId(potionId: any): string?
	local lowered = trimAndLower(potionId)
	if not lowered then
		return nil
	end

	local aliasId = LEGACY_ID_ALIASES[lowered]
	if aliasId ~= nil then
		return aliasId
	end

	local entry = entriesById[lowered]
	return if entry then entry.id else nil
end

function PotionConfig.NormalizeId(potionId: any): string?
	return normalizeId(potionId)
end

function PotionConfig.NormalizeFamilyId(familyId: any): PotionFamilyId?
	local lowered = trimAndLower(familyId)
	if not lowered then
		return nil
	end

	for _, resolvedFamilyId in ipairs(familyIds) do
		if string.lower(resolvedFamilyId) == lowered then
			return resolvedFamilyId
		end
	end

	return nil
end

function PotionConfig.Get(potionId: any): PotionConfigEntry?
	local normalizedId = normalizeId(potionId)
	return if normalizedId then entriesById[string.lower(normalizedId)] else nil
end

function PotionConfig.GetAll(): { PotionConfigEntry }
	local results = table.create(#ENTRIES)
	for index, entry in ipairs(ENTRIES) do
		results[index] = entry
	end
	return results
end

function PotionConfig.GetFamilyId(potionId: any): PotionFamilyId?
	local entry = PotionConfig.Get(potionId)
	return if entry then entry.familyId else nil
end

function PotionConfig.GetFamilyLabel(familyId: any): string?
	local normalizedFamilyId = PotionConfig.NormalizeFamilyId(familyId)
	return if normalizedFamilyId then familyLabelsById[normalizedFamilyId] else nil
end

function PotionConfig.GetFamilyIds(): { PotionFamilyId }
	local results = table.create(#familyIds)
	for index, familyId in ipairs(familyIds) do
		results[index] = familyId
	end
	return results
end

function PotionConfig.GetFamilyEntries(familyId: any): { PotionConfigEntry }
	local normalizedFamilyId = PotionConfig.NormalizeFamilyId(familyId)
	if not normalizedFamilyId then
		return {}
	end

	local entries = familyEntriesById[normalizedFamilyId] or {}
	local results = table.create(#entries)
	for index, entry in ipairs(entries) do
		results[index] = entry
	end
	return results
end

function PotionConfig.GetDefaultTierIdForFamily(familyId: any): string?
	local normalizedFamilyId = PotionConfig.NormalizeFamilyId(familyId)
	if not normalizedFamilyId then
		return nil
	end

	return string.format("%s3", normalizedFamilyId)
end

function PotionConfig.GetSellPrice(potionId: any): number
	local entry = PotionConfig.Get(potionId)
	if not entry then
		return 0
	end

	return math.max(0, math.floor((tonumber(entry.buyPrice) or 0) / 2))
end

return table.freeze(PotionConfig)
