local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local RollingConfig = require(script.Parent.Parent.Config.RollingConfig)

local RARITY_SORT_RANK = {}
for index, rarity in ipairs(RollingConfig.DisplayRarityOrder) do
	RARITY_SORT_RANK[rarity] = index
end

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

export type BossRewardPreviewEntry = {
	pieceId: string,
	setId: string,
	displayName: string,
	displayRarity: string,
	chance: number,
	isBossPart: boolean,
	bundleModel: Model?,
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

local function buildAllowedRaritySet(profile: BossRewardProfile): { [string]: boolean }
	local allowed = {}

	for _, rarity in ipairs(profile.allowedRarities) do
		allowed[rarity] = true
	end

	return allowed
end

local function pushPreviewEntriesForSet(
	entries: { BossRewardPreviewEntry },
	setId: string,
	chance: number,
	isBossPart: boolean
)
	local pieces = BodyPartsCatalog.GetPiecesForSet(setId)
	local setConfig = BodyPartsCatalog.GetSet(setId)
	if setConfig == nil or pieces == nil or #pieces <= 0 then
		return
	end

	local pieceChance = math.max(0, tonumber(chance) or 0) / #pieces
	local displayRarity = tostring(setConfig.rollDisplay.rarity or "Basic")

	for _, piece in ipairs(pieces) do
		table.insert(entries, table.freeze({
			pieceId = piece.id,
			setId = setId,
			displayName = tostring(piece.displayName or piece.id),
			displayRarity = displayRarity,
			chance = pieceChance,
			isBossPart = isBossPart,
			bundleModel = BodyPartsCatalog.ResolveBundleModel(piece.id),
		}))
	end
end

function BossRewards.GetBossRewardPreviewEntries(bossId: string): { BossRewardPreviewEntry }
	local profile = BossRewards.GetBossRewardProfile(bossId)
	if profile == nil then
		return table.freeze({})
	end

	local floorPreset = BossRewards.GetLootFloorPreset(profile.lootFloorId)
	if floorPreset == nil then
		return table.freeze({})
	end

	local entries = {}
	local bossPartChance = math.clamp(tonumber(profile.bossPartChance) or 0, 0, 1)
	pushPreviewEntriesForSet(entries, profile.bossSetId, bossPartChance, true)

	local allowedRarities = buildAllowedRaritySet(profile)
	local poolsByRarity = {}
	for _, rollEntry in ipairs(BodyPartsCatalog.GetRollEntries()) do
		local setId = rollEntry.id
		local displayRarity = tostring(rollEntry.rollDisplay.rarity or "Basic")
		if setId ~= profile.bossSetId and allowedRarities[displayRarity] == true then
			local pool = poolsByRarity[displayRarity]
			if pool == nil then
				pool = {
					entries = {},
					totalWeight = 0,
				}
				poolsByRarity[displayRarity] = pool
			end

			local weight = math.max(0, tonumber(rollEntry.baseChance) or 0)
			if weight > 0 then
				pool.totalWeight += weight
				table.insert(pool.entries, rollEntry)
			end
		end
	end

	local eligibleTierProbability = 0
	for _, tierEntry in ipairs(floorPreset.tierOddsOrdered) do
		local pool = poolsByRarity[tierEntry.displayRarity]
		local tierProbability = math.max(0, tonumber(tierEntry.probability) or 0)
		if pool ~= nil and pool.totalWeight > 0 and tierProbability > 0 then
			eligibleTierProbability += tierProbability
		end
	end

	if eligibleTierProbability > 0 then
		local normalRollChance = 1 - bossPartChance
		for _, tierEntry in ipairs(floorPreset.tierOddsOrdered) do
			local pool = poolsByRarity[tierEntry.displayRarity]
			local tierProbability = math.max(0, tonumber(tierEntry.probability) or 0)
			if pool ~= nil and pool.totalWeight > 0 and tierProbability > 0 then
				local normalizedTierChance = tierProbability / eligibleTierProbability
				for _, rollEntry in ipairs(pool.entries) do
					local setChance = normalRollChance
						* normalizedTierChance
						* (math.max(0, tonumber(rollEntry.baseChance) or 0) / pool.totalWeight)
					pushPreviewEntriesForSet(entries, rollEntry.id, setChance, false)
				end
			end
		end
	end

	table.sort(entries, function(a, b)
		local rarityRankA = RARITY_SORT_RANK[RollingConfig.NormalizeDisplayRarity(a.displayRarity)] or 0
		local rarityRankB = RARITY_SORT_RANK[RollingConfig.NormalizeDisplayRarity(b.displayRarity)] or 0
		if rarityRankA ~= rarityRankB then
			return rarityRankA > rarityRankB
		end
		if a.chance ~= b.chance then
			return a.chance > b.chance
		end
		return a.displayName < b.displayName
	end)

	return table.freeze(entries)
end

return table.freeze(BossRewards)
