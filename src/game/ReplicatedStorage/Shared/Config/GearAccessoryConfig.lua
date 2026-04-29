local GearAccessoryConfig = {}

export type AccessoryBonusConfig = {
	passiveIncomePerSecondBonus: number?,
	passiveIncomeMultiplier: number?,
	luckBonus: number?,
	luckMultiplier: number?,
	rollSpeedBonus: number?,
	speedBonus: number?,
	speedMultiplier: number?,
	damageBonus: number?,
	damageMultiplier: number?,
	healthBonus: number?,
	healthMultiplier: number?,
}

export type GearAccessoryConfigEntry = {
	id: string,
	slot: "GearAccessory",
	label: string,
	description: string,
	tierLabel: string,
	sortOrder: number,
	displayColor: Color3,
	recipeCardColor: Color3,
	assetId: number?,
	bossId: string?,
	assetModelName: string?,
	iconTexture: string?,
	sellPrice: number,
	bonuses: AccessoryBonusConfig,
}

local RARITY_COLORS = table.freeze({
	Basic = Color3.fromRGB(172, 180, 190),
	Clean = Color3.fromRGB(116, 192, 255),
	Prime = Color3.fromRGB(176, 96, 255),
	Elite = Color3.fromRGB(255, 184, 77),
	Apex = Color3.fromRGB(255, 97, 97),
})

local ID_ALIASES = table.freeze({
	bombos_survival_knfe = "bombos_survival_knife",
	dark_spellbook_of_the_forgotten = "dark_spell_book_of_the_forgotten",
	spec_epsilon_biograft_energy_sword = "epsilon_energy_sword",
})

local SELL_PRICES_BY_ID: { [string]: number } = table.freeze({
	training_bracer = 250,
	golden_gauntlet = 750,
	mystic_sword_of_the_flames = 50000,
	pirate_lieutenants_cutlass = 175000,
	mythic_sword_of_the_tides = 500000,
	axe_of_the_divine_flame = 1500000,
	flaming_orb_of_divine_pain = 5000000,
	mythic_sword_of_the_earth = 12500000,
	red_laser_scythe = 37500000,
	crescendo_the_soul_stealer = 100000000,
	pizza_sword = 250000000,
	rainbow_periastron_omega = 625000000,
	bombos_survival_knife = 37500,
	dark_spell_book_of_the_forgotten = 3000000,
	epsilon_energy_sword = 15000000,
	illumina = 75000000,
	telamonster_the_chaos_edge = 400000000,
})

local function percentMultiplier(percent: number): number
	return 1 + (tonumber(percent) or 0) / 100
end

local function gear(
	id: string,
	label: string,
	rarity: string,
	sortOrder: number,
	assetId: number?,
	bossId: string?,
	damagePercent: number,
	healthPercent: number,
	speedPercent: number,
	assetModelName: string?,
	recipeCardColor: Color3
): GearAccessoryConfigEntry
	return {
		id = id,
		slot = "GearAccessory",
		label = label,
		description = "A craftable gear accessory that increases combat stats.",
		tierLabel = rarity,
		sortOrder = sortOrder,
		displayColor = RARITY_COLORS[rarity] or RARITY_COLORS.Basic,
		recipeCardColor = recipeCardColor,
		assetId = assetId,
		bossId = bossId,
		assetModelName = assetModelName,
		iconTexture = "",
		sellPrice = SELL_PRICES_BY_ID[id] or 0,
		bonuses = {
			damageMultiplier = percentMultiplier(damagePercent),
			healthMultiplier = percentMultiplier(healthPercent),
			speedMultiplier = percentMultiplier(speedPercent),
		},
	}
end

local ENTRIES: { GearAccessoryConfigEntry } = {
	{
		id = "training_bracer",
		slot = "GearAccessory",
		label = "Training Bracer",
		description = "A placeholder gear accessory for early crafting tests.",
		tierLabel = "Common",
		sortOrder = 10,
		displayColor = Color3.fromRGB(113, 230, 139),
		recipeCardColor = Color3.fromRGB(113, 230, 139),
		assetId = nil,
		bossId = nil,
		assetModelName = nil,
		iconTexture = "",
		sellPrice = SELL_PRICES_BY_ID.training_bracer,
		bonuses = {
			damageBonus = 3,
			speedBonus = 0.5,
			passiveIncomePerSecondBonus = 0.15,
		},
	},
	{
		id = "golden_gauntlet",
		slot = "GearAccessory",
		label = "Golden Gauntlet",
		description = "A placeholder gear accessory that improves income and strength.",
		tierLabel = "Uncommon",
		sortOrder = 20,
		displayColor = Color3.fromRGB(255, 184, 77),
		recipeCardColor = Color3.fromRGB(255, 184, 77),
		assetId = nil,
		bossId = nil,
		assetModelName = nil,
		iconTexture = "",
		sellPrice = SELL_PRICES_BY_ID.golden_gauntlet,
		bonuses = {
			passiveIncomeMultiplier = 1.05,
			damageBonus = 6,
			healthBonus = 10,
		},
	},

	gear("mystic_sword_of_the_flames", "Mystic Sword of the Flames", "Basic", 100, 241511828, "Flame Guard General", 50, 25, 10, "Mystic Sword of the Flames", Color3.fromRGB(255, 103, 48)),
	gear("pirate_lieutenants_cutlass", "Pirate Lieutenant's Cutlass", "Clean", 110, 48159648, "Captain Squid", 75, 30, 30, "Pirate Lieutenants Cutlass", Color3.fromRGB(112, 161, 196)),
	gear("mythic_sword_of_the_tides", "Mythic Sword of the Tides", "Clean", 120, 241017568, "Merfin the Great", 100, 50, 40, "Mythic Sword of the Tides", Color3.fromRGB(66, 190, 255)),
	gear("axe_of_the_divine_flame", "Axe of the Divine Flame", "Prime", 130, 181550181, "Oinan Thickhoof", 150, 150, 10, "Axe of the Divine Flame", Color3.fromRGB(255, 197, 77)),
	gear("flaming_orb_of_divine_pain", "Flaming Orb of Divine Pain", "Prime", 140, 461488745, "Magma Fiend", 225, 100, 20, "Flaming Orb of Divine Pain", Color3.fromRGB(255, 77, 43)),
	gear("mythic_sword_of_the_earth", "Mythic Sword of the Earth", "Elite", 150, 241512134, "Broccoli Bro", 250, 250, 25, "Mythic Sword of the Earth", Color3.fromRGB(94, 171, 92)),
	gear("red_laser_scythe", "Red Laser Scythe", "Elite", 160, 1609498185, "Destroyer 3000", 400, 250, 15, "Red Laser Scythe", Color3.fromRGB(255, 64, 84)),
	gear("crescendo_the_soul_stealer", "Crescendo, The Soul Stealer", "Elite", 170, 94794774, "Agrynoth", 550, 350, 25, "Crescendo The Soul Stealer", Color3.fromRGB(157, 94, 255)),
	gear("pizza_sword", "Pizza Sword", "Apex", 180, 602146440, "Massive Geezer", 500, 800, 5, "Pizza Sword", Color3.fromRGB(255, 152, 64)),
	gear("rainbow_periastron_omega", "Rainbow Periastron Omega", "Apex", 190, 159229806, "Cat Mech Elite", 800, 550, 50, "Rainbow Periastron Omega", Color3.fromRGB(126, 111, 255)),

	gear("bombos_survival_knife", "Bombo's Survival Knife", "Basic", 300, 121946387, nil, 40, 10, 25, "Bombos Survival Knife", Color3.fromRGB(131, 156, 82)),
	gear("dark_spell_book_of_the_forgotten", "Dark Spell Book of the Forgotten", "Prime", 310, 56561579, nil, 125, 50, 15, "Dark Spellbook of the Forgotten", Color3.fromRGB(94, 72, 142)),
	gear("epsilon_energy_sword", "Epsilon Energy Sword", "Prime", 320, 23727705, nil, 250, 125, 30, "Spec Epsilon Biograft Energy Sword", Color3.fromRGB(84, 207, 255)),
	gear("illumina", "Illumina", "Elite", 330, 16641274, nil, 400, 200, 50, "Illumina", Color3.fromRGB(255, 245, 170)),
	gear("telamonster_the_chaos_edge", "Telamonster: The Chaos Edge", "Apex", 340, 93136746, nil, 650, 400, 35, "Telamonster the Chaos Edge", Color3.fromRGB(199, 67, 255)),
}

local entriesById: { [string]: GearAccessoryConfigEntry } = {}
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

	local lowered = string.lower(trimmed)
	local aliasedId = ID_ALIASES[lowered] or lowered
	local entry = entriesById[aliasedId]
	return if entry then entry.id else nil
end

function GearAccessoryConfig.NormalizeId(accessoryId: any): string?
	return normalizeId(accessoryId)
end

function GearAccessoryConfig.Get(accessoryId: any): GearAccessoryConfigEntry?
	local normalizedId = normalizeId(accessoryId)
	return if normalizedId then entriesById[string.lower(normalizedId)] else nil
end

function GearAccessoryConfig.GetAll(): { GearAccessoryConfigEntry }
	local results = table.create(#ENTRIES)
	for index, entry in ipairs(ENTRIES) do
		results[index] = entry
	end
	return results
end

function GearAccessoryConfig.GetSellPrice(accessoryId: any): number
	local entry = GearAccessoryConfig.Get(accessoryId)
	if not entry then
		return 0
	end

	return math.max(0, math.floor(tonumber(entry.sellPrice) or 0))
end

return table.freeze(GearAccessoryConfig)
