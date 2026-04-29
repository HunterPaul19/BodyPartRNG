local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameAssetResolver = require(ReplicatedStorage.Shared.Assets.GameAssetResolver)

local CraftingMaterialConfig = {}

local COMMON_COLOR = Color3.fromRGB(172, 180, 190)
local RARE_COLOR = Color3.fromRGB(116, 192, 255)
local EPIC_COLOR = Color3.fromRGB(255, 184, 77)

export type CraftingMaterialConfigEntry = {
	id: string,
	label: string,
	description: string,
	sortOrder: number,
	displayColor: Color3,
	iconName: string?,
	iconTexture: string?,
}

local ICON_NAMES_BY_ID: { [string]: string } = {
	ember_shard = "Embershard",
	blazesteel_fragment = "BlazesteelFragment",
	infernal_crown = "InfernalCrown",
	blue_tentacle = "BlueTentacle",
	pirate_hook = "PirateHook",
	abyssal_compass = "AbyssalCompass",
	mystic_fish_scale = "MysticFishScale",
	tidal_staff = "TidalStaff",
	tome_of_the_deep = "TomeOfTheDeep",
	divine_leather = "DivineLeather",
	titanic_bull_horn = "TitanicBullHorn",
	mighty_axe = "MightyAxe",
	molten_chunk = "MoltenChunk",
	ember_core = "EmberCore",
	volcanic_heart = "VolcanicHeart",
	broccoli = "Broccoli",
	mixed_salad = "MixedSalad",
	golden_broccoli = "GoldenBroccoli",
	alloy_plate = "AlloyPlate",
	power_cell = "PowerCell",
	reactor_core = "ReactorCore",
	bone_shard = "BoneShard",
	cursed_ribcage = "CursedRibcage",
	lich_skull = "LichSkull",
	chicken_bone = "ChickenBone",
	mac_n_cheese = "MacNCheese",
	titanic_tooth = "TitanicTooth",
	rainbow_prism = "RainbowPrism",
	meow_engine = "MeowEngine",
	orbital_laser_cannon = "OrbitalLaserCannon",
}

local function material(
	id: string,
	label: string,
	description: string,
	sortOrder: number,
	displayColor: Color3
): CraftingMaterialConfigEntry
	return {
		id = id,
		label = label,
		description = description,
		sortOrder = sortOrder,
		displayColor = displayColor,
		iconName = ICON_NAMES_BY_ID[id],
		iconTexture = "",
	}
end

local ENTRIES: { CraftingMaterialConfigEntry } = {
	{
		id = "scrap",
		label = "Scrap",
		description = "A common placeholder crafting material.",
		sortOrder = 10,
		displayColor = COMMON_COLOR,
		iconName = nil,
		iconTexture = "",
	},
	{
		id = "lucky_thread",
		label = "Lucky Thread",
		description = "A placeholder material used for luck-focused recipes.",
		sortOrder = 20,
		displayColor = RARE_COLOR,
		iconName = nil,
		iconTexture = "",
	},
	material("ember_shard", "Ember Shard", "A common crafting material dropped by Flame Guard General.", 100, COMMON_COLOR),
	material("blazesteel_fragment", "Blazesteel Fragment", "A rare crafting material dropped by Flame Guard General.", 110, RARE_COLOR),
	material("infernal_crown", "Infernal Crown", "An epic crafting material dropped by Flame Guard General.", 120, EPIC_COLOR),
	material("blue_tentacle", "Blue Tentacle", "A common crafting material dropped by Captain Squid.", 200, COMMON_COLOR),
	material("pirate_hook", "Pirate Hook", "A rare crafting material dropped by Captain Squid.", 210, RARE_COLOR),
	material("abyssal_compass", "Abyssal Compass", "An epic crafting material dropped by Captain Squid.", 220, EPIC_COLOR),
	material("mystic_fish_scale", "Mystic Fish Scale", "A common crafting material dropped by Merfin the Great.", 300, COMMON_COLOR),
	material("tidal_staff", "Tidal Staff", "A rare crafting material dropped by Merfin the Great.", 310, RARE_COLOR),
	material("tome_of_the_deep", "Tome of the Deep", "An epic crafting material dropped by Merfin the Great.", 320, EPIC_COLOR),
	material("divine_leather", "Divine Leather", "A common crafting material dropped by Oinan Thickhoof.", 400, COMMON_COLOR),
	material("titanic_bull_horn", "Titanic Bull Horn", "A rare crafting material dropped by Oinan Thickhoof.", 410, RARE_COLOR),
	material("mighty_axe", "Mighty Axe", "An epic crafting material dropped by Oinan Thickhoof.", 420, EPIC_COLOR),
	material("molten_chunk", "Molten Chunk", "A common crafting material dropped by Magma Fiend.", 500, COMMON_COLOR),
	material("ember_core", "Ember Core", "A rare crafting material dropped by Magma Fiend.", 510, RARE_COLOR),
	material("volcanic_heart", "Volcanic Heart", "An epic crafting material dropped by Magma Fiend.", 520, EPIC_COLOR),
	material("broccoli", "Broccoli", "A common crafting material dropped by Broccoli Bro.", 600, COMMON_COLOR),
	material("mixed_salad", "Mixed Salad", "A rare crafting material dropped by Broccoli Bro.", 610, RARE_COLOR),
	material("golden_broccoli", "Golden Broccoli", "An epic crafting material dropped by Broccoli Bro.", 620, EPIC_COLOR),
	material("alloy_plate", "Alloy Plate", "A common crafting material dropped by Destroyer 3000.", 700, COMMON_COLOR),
	material("power_cell", "Power Cell", "A rare crafting material dropped by Destroyer 3000.", 710, RARE_COLOR),
	material("reactor_core", "Reactor Core", "An epic crafting material dropped by Destroyer 3000.", 720, EPIC_COLOR),
	material("bone_shard", "Bone Shard", "A common crafting material dropped by Agrynoth.", 800, COMMON_COLOR),
	material("cursed_ribcage", "Cursed Ribcage", "A rare crafting material dropped by Agrynoth.", 810, RARE_COLOR),
	material("lich_skull", "Lich Skull", "An epic crafting material dropped by Agrynoth.", 820, EPIC_COLOR),
	material("chicken_bone", "Chicken Bone", "A common crafting material dropped by Massive Geezer.", 900, COMMON_COLOR),
	material("mac_n_cheese", "Mac n Cheese", "A rare crafting material dropped by Massive Geezer.", 910, RARE_COLOR),
	material("titanic_tooth", "Titanic Tooth", "An epic crafting material dropped by Massive Geezer.", 920, EPIC_COLOR),
	material("rainbow_prism", "Rainbow Prism", "A common crafting material dropped by Cat Mech Elite.", 1000, COMMON_COLOR),
	material("meow_engine", "Meow Engine", "A rare crafting material dropped by Cat Mech Elite.", 1010, RARE_COLOR),
	material("orbital_laser_cannon", "Orbital Laser Cannon", "An epic crafting material dropped by Cat Mech Elite.", 1020, EPIC_COLOR),
}

local entriesById: { [string]: CraftingMaterialConfigEntry } = {}
for _, entry in ipairs(ENTRIES) do
	entriesById[string.lower(entry.id)] = table.freeze(entry)
end
for index, entry in ipairs(ENTRIES) do
	ENTRIES[index] = entriesById[string.lower(entry.id)]
end
table.freeze(ENTRIES)

local function normalizeId(materialId: any): string?
	if typeof(materialId) ~= "string" then
		return nil
	end

	local trimmed = string.match(materialId, "^%s*(.-)%s*$")
	if not trimmed or trimmed == "" then
		return nil
	end

	local entry = entriesById[string.lower(trimmed)]
	return if entry then entry.id else nil
end

function CraftingMaterialConfig.NormalizeId(materialId: any): string?
	return normalizeId(materialId)
end

function CraftingMaterialConfig.Get(materialId: any): CraftingMaterialConfigEntry?
	local normalizedId = normalizeId(materialId)
	return if normalizedId then entriesById[string.lower(normalizedId)] else nil
end

function CraftingMaterialConfig.GetAll(): { CraftingMaterialConfigEntry }
	local results = table.create(#ENTRIES)
	for index, entry in ipairs(ENTRIES) do
		results[index] = entry
	end
	return results
end

function CraftingMaterialConfig.ResolveIcon(configOrId: CraftingMaterialConfigEntry | string): Decal?
	local config = if typeof(configOrId) == "string" then CraftingMaterialConfig.Get(configOrId) else configOrId
	if not config then
		return nil
	end

	local iconName = config.iconName
	if typeof(iconName) ~= "string" or iconName == "" then
		return nil
	end

	local icon = GameAssetResolver.Find({ "UI", "CraftingIcons" }, iconName)
	if icon and icon:IsA("Decal") then
		return icon
	end

	return nil
end

function CraftingMaterialConfig.ResolveIconTexture(configOrId: CraftingMaterialConfigEntry | string): string?
	local config = if typeof(configOrId) == "string" then CraftingMaterialConfig.Get(configOrId) else configOrId
	if not config then
		return nil
	end

	if typeof(config.iconTexture) == "string" and config.iconTexture ~= "" then
		return config.iconTexture
	end

	local icon = CraftingMaterialConfig.ResolveIcon(config)
	if not icon then
		return nil
	end

	local texture = icon.Texture
	return if typeof(texture) == "string" and texture ~= "" then texture else nil
end

return table.freeze(CraftingMaterialConfig)
