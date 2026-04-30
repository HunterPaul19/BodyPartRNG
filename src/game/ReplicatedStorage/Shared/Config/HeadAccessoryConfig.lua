local HeadAccessoryConfig = {}

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

export type HeadAccessoryConfigEntry = {
	id: string,
	slot: "HeadAccessory",
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

local SELL_PRICES_BY_ID: { [string]: number } = table.freeze({
	paper_crown = 250,
	lucky_visor = 750,
	holiday_crown = 500,
	the_fire_crown = 62500,
	pirate_captains_hat = 250000,
	blue_hydromage_wizard_hat = 750000,
	the_bull = 2500000,
	lava_monster_warrior = 7500000,
	green_laurel_wreath = 17500000,
	grandpappy_computer = 50000000,
	fiery_horns_of_the_netherworld = 125000000,
	telamons_chicken_suit = 325000000,
	rainbow_hatbot = 750000000,
	black_iron_antlers = 1500000,
	valkyrie_helm = 12500000,
	empyrean_reignment = 75000000,
	silver_king_of_the_night = 200000000,
	lord_of_the_federation = 600000000,
})

local function percentBonus(percent: number): number
	return (tonumber(percent) or 0) / 100
end

local function percentMultiplier(percent: number): number
	return 1 + percentBonus(percent)
end

local function headAccessory(
	id: string,
	label: string,
	rarity: string,
	sortOrder: number,
	assetId: number,
	luckPercent: number,
	rollSpeedPercent: number,
	moneyPerSecondPercent: number,
	assetModelName: string?,
	bossId: string?,
	recipeCardColor: Color3
): HeadAccessoryConfigEntry
	return {
		id = id,
		slot = "HeadAccessory",
		label = label,
		description = "A craftable head accessory that increases progression stats.",
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
			luckBonus = percentBonus(luckPercent),
			rollSpeedBonus = percentBonus(rollSpeedPercent),
			passiveIncomeMultiplier = percentMultiplier(moneyPerSecondPercent),
		},
	}
end

local ENTRIES: { HeadAccessoryConfigEntry } = {
	{
		id = "paper_crown",
		slot = "HeadAccessory",
		label = "Paper Crown",
		description = "A placeholder head accessory for early crafting tests.",
		tierLabel = "Common",
		sortOrder = 10,
		displayColor = Color3.fromRGB(255, 221, 95),
		recipeCardColor = Color3.fromRGB(255, 221, 95),
		assetId = nil,
		bossId = nil,
		assetModelName = nil,
		iconTexture = "",
		sellPrice = SELL_PRICES_BY_ID.paper_crown,
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
		recipeCardColor = Color3.fromRGB(116, 192, 255),
		assetId = nil,
		bossId = nil,
		assetModelName = nil,
		iconTexture = "",
		sellPrice = SELL_PRICES_BY_ID.lucky_visor,
		bonuses = {
			luckBonus = 0.10,
			luckMultiplier = 1.05,
			rollSpeedBonus = 0.03,
		},
	},

	headAccessory("holiday_crown", "Holiday Crown", "Basic", 30, 139152472, 10, 5, 10, "Holiday Crown", nil, Color3.fromRGB(255, 221, 95)),

	headAccessory("the_fire_crown", "The Fire Crown", "Basic", 100, 362032819, 75, 25, 50, "The Fire Crown", "Flame Guard General", Color3.fromRGB(255, 110, 51)),
	headAccessory("pirate_captains_hat", "Pirate Captain's Hat", "Clean", 110, 1028859, 100, 35, 75, "Pirate Captains Hat", "Captain Squid", Color3.fromRGB(70, 124, 191)),
	headAccessory("blue_hydromage_wizard_hat", "Blue Hydromage Wizard Hat", "Clean", 120, 13149601, 150, 50, 100, "Blue Hydromage Wizard Hat", "Merfin the Great", Color3.fromRGB(70, 174, 255)),
	headAccessory("the_bull", "The Bull", "Prime", 130, 102627792, 200, 30, 175, "The Bull", "Oinan Thickhoof", Color3.fromRGB(176, 100, 60)),
	headAccessory("lava_monster_warrior", "Lava Monster Warrior", "Prime", 140, 31765469, 275, 60, 175, "Lava Monster Warrior", "Magma Fiend", Color3.fromRGB(255, 84, 45)),
	headAccessory("green_laurel_wreath", "Green Laurel Wreath", "Elite", 150, 20721173, 350, 70, 250, "Green Laurel Wreath", "Broccoli Bro", Color3.fromRGB(105, 190, 105)),
	headAccessory("grandpappy_computer", "Grandpappy Computer", "Elite", 160, 1046282284, 450, 100, 325, "Grandpappy Computer", "Destroyer 3000", Color3.fromRGB(80, 220, 220)),
	headAccessory("fiery_horns_of_the_netherworld", "Fiery Horns of the Netherworld", "Elite", 170, 215718515, 600, 125, 450, "Fiery Horns of the Netherworld", "Agrynoth", Color3.fromRGB(255, 73, 73)),
	headAccessory("telamons_chicken_suit", "Telamon's Chicken Suit", "Apex", 180, 24112667, 700, 100, 700, "Telamons Chicken Suit", "Massive Geezer", Color3.fromRGB(255, 213, 74)),
	headAccessory("rainbow_hatbot", "Rainbow Hatbot", "Apex", 190, 149594188, 1000, 175, 900, "Rainbow Hatbot", "Cat Mech Elite", Color3.fromRGB(186, 103, 255)),

	headAccessory("black_iron_antlers", "Black Iron Antlers", "Clean", 300, 398674411, 125, 40, 150, "Black Iron Antlers", nil, Color3.fromRGB(90, 104, 120)),
	headAccessory("valkyrie_helm", "Valkyrie Helm", "Prime", 310, 1365767, 225, 65, 225, "Valkyrie Helm", nil, Color3.fromRGB(168, 200, 255)),
	headAccessory("empyrean_reignment", "Empyrean Reignment", "Elite", 320, 15967743, 350, 80, 400, "Empyrean Reignment", nil, Color3.fromRGB(255, 210, 120)),
	headAccessory("silver_king_of_the_night", "Silver King of the Night", "Elite", 330, 439945661, 500, 90, 650, "Silver King of the Night", nil, Color3.fromRGB(190, 204, 220)),
	headAccessory("lord_of_the_federation", "Lord of the Federation", "Apex", 340, 88885069, 850, 150, 800, "Lord of the Federation", nil, Color3.fromRGB(190, 112, 255)),
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

function HeadAccessoryConfig.GetSellPrice(accessoryId: any): number
	local entry = HeadAccessoryConfig.Get(accessoryId)
	if not entry then
		return 0
	end

	return math.max(0, math.floor(tonumber(entry.sellPrice) or 0))
end

return table.freeze(HeadAccessoryConfig)
