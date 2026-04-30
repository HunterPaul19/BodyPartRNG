local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local CraftingMaterialConfig = require(ReplicatedStorage.Shared.Config.CraftingMaterialConfig)
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

export type MaterialDropTier = "Common" | "Rare" | "Epic"

export type BossMaterialDropEntry = {
	materialId: string,
	dropTier: MaterialDropTier,
	chance: number,
	amountMin: number,
	amountMax: number,
}

export type BossMaterialDropProfile = {
	bossId: string,
	drops: { BossMaterialDropEntry },
}

export type BossRewardPreviewKind = "bossPart" | "material"

export type BossRewardPreviewEntry = {
	kind: BossRewardPreviewKind,
	pieceId: string?,
	setId: string?,
	materialId: string?,
	displayName: string,
	displayRarity: string?,
	dropTier: MaterialDropTier?,
	chance: number,
	isBossPart: boolean?,
	bundleModel: Model?,
	displayColor: Color3?,
	iconTexture: string?,
}

local BossRewards = {}

local VALID_MATERIAL_DROP_TIERS = {
	Common = true,
	Rare = true,
	Epic = true,
}

local function normalizeMaterialDropTier(value: any): MaterialDropTier
	if typeof(value) == "string" and VALID_MATERIAL_DROP_TIERS[value] == true then
		return value :: MaterialDropTier
	end

	Logger.Error(string.format("[BossRewards] Unknown material drop tier '%s'.", tostring(value)), 0)
	return "Common"
end

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
		{ displayRarity = "Elite", probability = 0.9995045272866096 },
		{ displayRarity = "Apex", probability = 0.000495472713390365 },
	}),
}

local CHEST_VISUAL_BY_LOOT_FLOOR = table.freeze({
	["Basic+"] = "BossTier1",
	["Clean+"] = "BossTier1",
	["Prime+"] = "BossTier2",
	["Elite+"] = "BossTier3",
})

local DEFAULT_BOSS_PART_CHANCE = 0.01
local ELITE_PLUS_BOSS_PART_CHANCE = 0.00199791031654431
local BOSS_PART_PREVIEW_DISPLAY_CHANCE = 0.01
local BOSS_PART_PREVIEW_COUNT = 5

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

local MATERIAL_DROP_SPECS = {
	["Flame Guard General"] = {
		{ materialId = "ember_shard", dropTier = "Common", chance = 1, amountMin = 4, amountMax = 7 },
		{ materialId = "blazesteel_fragment", dropTier = "Rare", chance = 0.45, amountMin = 1, amountMax = 2 },
		{ materialId = "infernal_crown", dropTier = "Epic", chance = 0.10, amountMin = 1, amountMax = 1 },
	},
	["Captain Squid"] = {
		{ materialId = "blue_tentacle", dropTier = "Common", chance = 1, amountMin = 4, amountMax = 7 },
		{ materialId = "pirate_hook", dropTier = "Rare", chance = 0.45, amountMin = 1, amountMax = 2 },
		{ materialId = "abyssal_compass", dropTier = "Epic", chance = 0.10, amountMin = 1, amountMax = 1 },
	},
	["Merfin the Great"] = {
		{ materialId = "mystic_fish_scale", dropTier = "Common", chance = 1, amountMin = 5, amountMax = 8 },
		{ materialId = "tidal_staff", dropTier = "Rare", chance = 0.40, amountMin = 1, amountMax = 2 },
		{ materialId = "tome_of_the_deep", dropTier = "Epic", chance = 0.10, amountMin = 1, amountMax = 1 },
	},
	["Oinan Thickhoof"] = {
		{ materialId = "divine_leather", dropTier = "Common", chance = 1, amountMin = 5, amountMax = 9 },
		{ materialId = "titanic_bull_horn", dropTier = "Rare", chance = 0.38, amountMin = 1, amountMax = 2 },
		{ materialId = "mighty_axe", dropTier = "Epic", chance = 0.09, amountMin = 1, amountMax = 1 },
	},
	["Magma Fiend"] = {
		{ materialId = "molten_chunk", dropTier = "Common", chance = 1, amountMin = 6, amountMax = 10 },
		{ materialId = "ember_core", dropTier = "Rare", chance = 0.35, amountMin = 1, amountMax = 2 },
		{ materialId = "volcanic_heart", dropTier = "Epic", chance = 0.08, amountMin = 1, amountMax = 1 },
	},
	["Broccoli Bro"] = {
		{ materialId = "broccoli", dropTier = "Common", chance = 1, amountMin = 6, amountMax = 10 },
		{ materialId = "mixed_salad", dropTier = "Rare", chance = 0.35, amountMin = 1, amountMax = 2 },
		{ materialId = "golden_broccoli", dropTier = "Epic", chance = 0.08, amountMin = 1, amountMax = 1 },
	},
	["Destroyer 3000"] = {
		{ materialId = "alloy_plate", dropTier = "Common", chance = 1, amountMin = 7, amountMax = 12 },
		{ materialId = "power_cell", dropTier = "Rare", chance = 0.32, amountMin = 1, amountMax = 2 },
		{ materialId = "reactor_core", dropTier = "Epic", chance = 0.07, amountMin = 1, amountMax = 1 },
	},
	["Agrynoth"] = {
		{ materialId = "bone_shard", dropTier = "Common", chance = 1, amountMin = 8, amountMax = 14 },
		{ materialId = "cursed_ribcage", dropTier = "Rare", chance = 0.30, amountMin = 1, amountMax = 2 },
		{ materialId = "lich_skull", dropTier = "Epic", chance = 0.06, amountMin = 1, amountMax = 1 },
	},
	["Massive Geezer"] = {
		{ materialId = "chicken_bone", dropTier = "Common", chance = 1, amountMin = 9, amountMax = 15 },
		{ materialId = "mac_n_cheese", dropTier = "Rare", chance = 0.28, amountMin = 1, amountMax = 2 },
		{ materialId = "titanic_tooth", dropTier = "Epic", chance = 0.05, amountMin = 1, amountMax = 1 },
	},
	["Cat Mech Elite"] = {
		{ materialId = "rainbow_prism", dropTier = "Common", chance = 1, amountMin = 10, amountMax = 18 },
		{ materialId = "meow_engine", dropTier = "Rare", chance = 0.25, amountMin = 1, amountMax = 2 },
		{ materialId = "orbital_laser_cannon", dropTier = "Epic", chance = 0.04, amountMin = 1, amountMax = 1 },
	},
}

local ALL_PROFILES = {}
local PROFILES_BY_BOSS_ID = {}
local MATERIAL_DROP_PROFILES_BY_BOSS_ID: { [string]: BossMaterialDropProfile } = {}

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
		bossPartChance = if spec.lootFloorId == "Elite+" then ELITE_PLUS_BOSS_PART_CHANCE else DEFAULT_BOSS_PART_CHANCE,
	})

	if PROFILES_BY_BOSS_ID[frozenProfile.bossId] ~= nil then
		Logger.Error(string.format("[BossRewards] Duplicate boss reward profile for '%s'.", frozenProfile.bossId), 0)
	end

	PROFILES_BY_BOSS_ID[frozenProfile.bossId] = frozenProfile
	table.insert(ALL_PROFILES, frozenProfile)
end

for bossId, drops in pairs(MATERIAL_DROP_SPECS) do
	if PROFILES_BY_BOSS_ID[bossId] == nil then
		Logger.Error(string.format("[BossRewards] Material drops reference unknown boss '%s'.", bossId), 0)
	end

	local normalizedDrops = table.create(#drops)
	for _, drop in ipairs(drops) do
		local materialId = CraftingMaterialConfig.NormalizeId(drop.materialId)
		if not materialId then
			Logger.Error(string.format(
				"[BossRewards] Boss '%s' references unknown crafting material '%s'.",
				bossId,
				tostring(drop.materialId)
			), 0)
		else
			local amountMin = math.max(1, math.floor(tonumber(drop.amountMin) or 1))
			local amountMax = math.max(amountMin, math.floor(tonumber(drop.amountMax) or amountMin))
			table.insert(normalizedDrops, table.freeze({
				materialId = materialId,
				dropTier = normalizeMaterialDropTier(drop.dropTier),
				chance = math.clamp(tonumber(drop.chance) or 0, 0, 1),
				amountMin = amountMin,
				amountMax = amountMax,
			}))
		end
	end

	MATERIAL_DROP_PROFILES_BY_BOSS_ID[bossId] = table.freeze({
		bossId = bossId,
		drops = table.freeze(normalizedDrops),
	})
end

table.freeze(FLOOR_PRESETS)
table.freeze(PROFILES_BY_BOSS_ID)
table.freeze(ALL_PROFILES)
table.freeze(MATERIAL_DROP_PROFILES_BY_BOSS_ID)

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

function BossRewards.GetBossChestVisualId(bossId: string): string
	local profile = BossRewards.GetBossRewardProfile(bossId)
	local lootFloorId = if profile then profile.lootFloorId else nil
	if typeof(lootFloorId) == "string" then
		local visualId = CHEST_VISUAL_BY_LOOT_FLOOR[lootFloorId]
		if typeof(visualId) == "string" and visualId ~= "" then
			return visualId
		end
	end

	return "BossTier1"
end

function BossRewards.GetAllBossRewardProfiles(): { BossRewardProfile }
	return ALL_PROFILES
end

function BossRewards.GetBossMaterialDropProfile(bossId: string): BossMaterialDropProfile?
	if typeof(bossId) ~= "string" or bossId == "" then
		return nil
	end

	return MATERIAL_DROP_PROFILES_BY_BOSS_ID[bossId]
end

function BossRewards.GetBossMaterialDrops(bossId: string): { BossMaterialDropEntry }
	local profile = BossRewards.GetBossMaterialDropProfile(bossId)
	return if profile then profile.drops else table.freeze({})
end

local function pushBossPartPreviewEntries(entries: { BossRewardPreviewEntry }, profile: BossRewardProfile)
	local setConfig = BodyPartsCatalog.GetSet(profile.bossSetId)
	if setConfig == nil then
		return
	end

	local pieces = BodyPartsCatalog.GetPiecesForSet(profile.bossSetId)
	if pieces == nil then
		return
	end

	local previewCount = math.min(BOSS_PART_PREVIEW_COUNT, #pieces)
	for index = 1, previewCount do
		local piece = pieces[index]
		if piece == nil then
			continue
		end

		table.insert(entries, table.freeze({
			kind = "bossPart",
			pieceId = piece.id,
			setId = profile.bossSetId,
			displayName = tostring(piece.displayName or setConfig.rollDisplay.displayName or setConfig.displayName or profile.bossSetId),
			displayRarity = tostring(setConfig.rollDisplay.rarity or "Basic"),
			chance = BOSS_PART_PREVIEW_DISPLAY_CHANCE,
			isBossPart = true,
			bundleModel = BodyPartsCatalog.ResolveBundleModel(piece.id),
		}))
	end
end

local function pushMaterialPreviewEntries(entries: { BossRewardPreviewEntry }, bossId: string)
	for _, drop in ipairs(BossRewards.GetBossMaterialDrops(bossId)) do
		local materialConfig = CraftingMaterialConfig.Get(drop.materialId)
		if materialConfig == nil then
			continue
		end

		table.insert(entries, table.freeze({
			kind = "material",
			materialId = materialConfig.id,
			displayName = materialConfig.label,
			dropTier = drop.dropTier,
			chance = math.clamp(tonumber(drop.chance) or 0, 0, 1),
			displayColor = materialConfig.displayColor,
			iconTexture = CraftingMaterialConfig.ResolveIconTexture(materialConfig),
		}))
	end
end

function BossRewards.GetBossRewardPreviewEntries(bossId: string): { BossRewardPreviewEntry }
	local profile = BossRewards.GetBossRewardProfile(bossId)
	if profile == nil then
		return table.freeze({})
	end

	local entries = {}
	pushBossPartPreviewEntries(entries, profile)
	pushMaterialPreviewEntries(entries, profile.bossId)

	return table.freeze(entries)
end

return table.freeze(BossRewards)
