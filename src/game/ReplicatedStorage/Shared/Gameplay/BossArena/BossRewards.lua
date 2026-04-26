local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local RollingConfig = require(script.Parent.Parent.Config.RollingConfig)

export type LootFloorPreset = {
	id: string,
	allowedRarities: { string },
	tierOddsByRarity: { [string]: number },
	tierOddsOrdered: { {
		displayRarity: string,
		probability: number,
	} },
}

export type BossRewardProfile = {
	bossId: string,
	bossSetId: string,
	lootFloorId: string,
	allowedRarities: { string },
	slotCount: number,
	bossPartChance: number,
}

local BossRewards = {}

local function freezeStringArray(values: { string }): { string }
	local frozen = table.create(#values)
	for index, value in ipairs(values) do
		frozen[index] = value
	end
	return table.freeze(frozen)
end

local function freezeTierOdds(entries: { { displayRarity: string, probability: number } })
	local frozenEntries = table.create(#entries)
	local tierOddsByRarity = {}

	for index, entry in ipairs(entries) do
		local normalizedEntry = table.freeze({
			displayRarity = entry.displayRarity,
			probability = math.max(0, tonumber(entry.probability) or 0),
		})
		frozenEntries[index] = normalizedEntry
		tierOddsByRarity[normalizedEntry.displayRarity] = normalizedEntry.probability
	end

	return table.freeze(tierOddsByRarity), table.freeze(frozenEntries)
end

local function createFloorPreset(
	id: string,
	allowedRarities: { string },
	tierOddsEntries: { { displayRarity: string, probability: number } }
): LootFloorPreset
	local tierOddsByRarity, tierOddsOrdered = freezeTierOdds(tierOddsEntries)
	return table.freeze({
		id = id,
		allowedRarities = freezeStringArray(allowedRarities),
		tierOddsByRarity = tierOddsByRarity,
		tierOddsOrdered = tierOddsOrdered,
	})
end

local FLOOR_PRESETS: { [string]: LootFloorPreset } = {
	["Basic+"] = createFloorPreset("Basic+", { "Basic", "Clean", "Prime", "Elite", "Apex" }, {
		{ displayRarity = "Basic", probability = 0.599 },
		{ displayRarity = "Clean", probability = 0.389 },
		{ displayRarity = "Prime", probability = 0.0124 },
		{ displayRarity = "Elite", probability = 0.00042 },
		{ displayRarity = "Apex", probability = 0.000005 },
	}),
	["Clean+"] = createFloorPreset("Clean+", { "Clean", "Prime", "Elite", "Apex" }, {
		{ displayRarity = "Clean", probability = 0.9680 },
		{ displayRarity = "Prime", probability = 0.0309 },
		{ displayRarity = "Elite", probability = 0.00105 },
		{ displayRarity = "Apex", probability = 0.000013 },
	}),
	["Prime+"] = createFloorPreset("Prime+", { "Prime", "Elite", "Apex" }, {
		{ displayRarity = "Prime", probability = 0.9666 },
		{ displayRarity = "Elite", probability = 0.0330 },
		{ displayRarity = "Apex", probability = 0.000408 },
	}),
	["Elite+"] = createFloorPreset("Elite+", { "Elite", "Apex" }, {
		{ displayRarity = "Elite", probability = 0.9975 },
		{ displayRarity = "Apex", probability = 0.0025 },
	}),
}

local PROFILE_SPECS = {
	{
		bossId = "Flame Guard General",
		bossSetId = "flame_guard_general",
		lootFloorId = "Basic+",
		allowedRarities = { "Basic", "Clean", "Prime", "Elite", "Apex" },
	},
	{
		bossId = "Captain Squid",
		bossSetId = "captain_squid",
		lootFloorId = "Basic+",
		allowedRarities = { "Clean", "Prime", "Elite", "Apex" },
	},
	{
		bossId = "Merfin the Great",
		bossSetId = "merfin_the_great",
		lootFloorId = "Clean+",
		allowedRarities = { "Clean", "Prime", "Elite", "Apex" },
	},
	{
		bossId = "Oinan Thickhoof",
		bossSetId = "oinan_thickhoof",
		lootFloorId = "Clean+",
		allowedRarities = { "Clean", "Prime", "Elite", "Apex" },
	},
	{
		bossId = "Magma Fiend",
		bossSetId = "magma_fiend",
		lootFloorId = "Prime+",
		allowedRarities = { "Prime", "Elite", "Apex" },
	},
	{
		bossId = "Broccoli Bro",
		bossSetId = "broccoli_bro",
		lootFloorId = "Prime+",
		allowedRarities = { "Prime", "Elite", "Apex" },
	},
	{
		bossId = "Destroyer 3000",
		bossSetId = "destroyer_3000",
		lootFloorId = "Prime+",
		allowedRarities = { "Prime", "Elite", "Apex" },
	},
	{
		bossId = "Agrynoth",
		bossSetId = "agrynoth",
		lootFloorId = "Prime+",
		allowedRarities = { "Elite", "Apex" },
	},
	{
		bossId = "Massive Geezer",
		bossSetId = "massive_geezer",
		lootFloorId = "Elite+",
		allowedRarities = { "Elite", "Apex" },
	},
	{
		bossId = "Cat Mech Elite",
		bossSetId = "cat_mech_elite",
		lootFloorId = "Elite+",
		allowedRarities = { "Elite", "Apex" },
	},
}

local ALL_PROFILES = {}
local PROFILES_BY_BOSS_ID = {}

for _, spec in ipairs(PROFILE_SPECS) do
	local floorPreset = FLOOR_PRESETS[spec.lootFloorId]
	if floorPreset == nil then
		Logger.Error(string.format("[BossRewards] Unknown loot floor '%s'.", tostring(spec.lootFloorId)), 0)
	end

	local allowedRarities = table.create(#spec.allowedRarities)
	local seenRarities = {}
	for _, rarity in ipairs(spec.allowedRarities) do
		local normalizedRarity = RollingConfig.NormalizeDisplayRarity(rarity)
		if seenRarities[normalizedRarity] ~= true then
			seenRarities[normalizedRarity] = true
			table.insert(allowedRarities, normalizedRarity)
		end
	end

	local frozenProfile: BossRewardProfile = table.freeze({
		bossId = spec.bossId,
		bossSetId = spec.bossSetId,
		lootFloorId = spec.lootFloorId,
		allowedRarities = freezeStringArray(allowedRarities),
		slotCount = 5,
		bossPartChance = 0.01,
	})

	if PROFILES_BY_BOSS_ID[frozenProfile.bossId] ~= nil then
		Logger.Error(string.format("[BossRewards] Duplicate boss reward profile for '%s'.", frozenProfile.bossId), 0)
	end

	PROFILES_BY_BOSS_ID[frozenProfile.bossId] = frozenProfile
	table.insert(ALL_PROFILES, frozenProfile)
end

table.freeze(FLOOR_PRESETS)
table.freeze(PROFILES_BY_BOSS_ID)
table.freeze(ALL_PROFILES)

function BossRewards.GetLootFloorPreset(lootFloorId: string): LootFloorPreset?
	if typeof(lootFloorId) ~= "string" or lootFloorId == "" then
		return nil
	end

	return FLOOR_PRESETS[lootFloorId]
end

function BossRewards.GetBossRewardProfile(bossId: string): BossRewardProfile?
	if typeof(bossId) ~= "string" or bossId == "" then
		return nil
	end

	return PROFILES_BY_BOSS_ID[bossId]
end

function BossRewards.GetAllBossRewardProfiles(): { BossRewardProfile }
	return ALL_PROFILES
end

return table.freeze(BossRewards)
