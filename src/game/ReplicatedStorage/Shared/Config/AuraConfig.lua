local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameAssetPaths = require(ReplicatedStorage.Shared.Assets.GameAssetPaths)
local GameAssetResolver = require(ReplicatedStorage.Shared.Assets.GameAssetResolver)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)

export type AuraBonusConfig = {
	luckBonus: number,
	rollSpeedBonus: number,
	moneyMultiplier: number,
	passiveIncomePerSecondBonus: number,
}

export type AuraConfigEntry = {
	id: string,
	setId: string,
	label: string,
	description: string,
	tierLabel: string,
	displayColor: Color3,
	sortOrder: number,
	assetModelName: string,
	iconName: string,
	bonuses: AuraBonusConfig,
}

local SUPPORTED_AURA_TARGET_PART_NAMES = table.freeze({
	Head = true,
	UpperTorso = true,
	LowerTorso = true,
	LeftUpperArm = true,
	LeftLowerArm = true,
	LeftHand = true,
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
	LeftUpperLeg = true,
	LeftLowerLeg = true,
	LeftFoot = true,
	RightUpperLeg = true,
	RightLowerLeg = true,
	RightFoot = true,
	HumanoidRootPart = true,
})

local ATTACHMENT_REFERENCE_PROPERTIES_BY_CLASS = table.freeze({
	Beam = { "Attachment0", "Attachment1" },
	Trail = { "Attachment0", "Attachment1" },
})

type RawAuraConfigEntry = {
	id: string,
	setId: string,
	label: string,
	sortOrder: number,
	assetModelName: string,
	iconName: string,
	bonuses: AuraBonusConfig,
}

local function withTrailingSpaces(value: string, count: number): string
	return value .. string.rep(" ", count)
end

local INTENTIONALLY_UNCONFIGURED_AURA_MODELS = table.freeze({
	["Brick Body R6"] = true,
	["Davy Bazooka"] = true,
	["TUNG TUNG  SAHUR"] = true,
})

local MODEL_NAME_ALIAS_BY_SET_ID = table.freeze({
	korblox_deathspeaker = "Korblox Deathspeaker",
})

local rawOrdered: { RawAuraConfigEntry } = {
	{
		id = "roblox_boy",
		setId = "roblox_boy",
		label = "Boy",
		sortOrder = 10,
		assetModelName = "ROBLOX Boy",
		iconName = "Boy (2)",
		bonuses = {
			luckBonus = 0.01,
			rollSpeedBonus = 0.005,
			moneyMultiplier = 1.01,
			passiveIncomePerSecondBonus = 5,
		},
	},
	{
		id = "roblox_girl",
		setId = "roblox_girl",
		label = "Girl",
		sortOrder = 20,
		assetModelName = withTrailingSpaces("ROBLOX Girl", 3),
		iconName = "Girl (2)",
		bonuses = {
			luckBonus = 0.011,
			rollSpeedBonus = 0.0055,
			moneyMultiplier = 1.012,
			passiveIncomePerSecondBonus = 5,
		},
	},
	{
		id = "man",
		setId = "man",
		label = "Man",
		sortOrder = 30,
		assetModelName = withTrailingSpaces("Man", 3),
		iconName = "Man",
		bonuses = {
			luckBonus = 0.012,
			rollSpeedBonus = 0.006,
			moneyMultiplier = 1.014,
			passiveIncomePerSecondBonus = 5,
		},
	},
	{
		id = "woman",
		setId = "woman",
		label = "Woman",
		sortOrder = 40,
		assetModelName = "Woman",
		iconName = "Woman",
		bonuses = {
			luckBonus = 0.014,
			rollSpeedBonus = 0.007,
			moneyMultiplier = 1.017,
			passiveIncomePerSecondBonus = 5,
		},
	},
	{
		id = "robloxian_2_0",
		setId = "robloxian_2_0",
		label = "Robloxian",
		sortOrder = 50,
		assetModelName = "Robloxian 2.0",
		iconName = "Robloxian",
		bonuses = {
			luckBonus = 0.016,
			rollSpeedBonus = 0.008,
			moneyMultiplier = 1.02,
			passiveIncomePerSecondBonus = 5,
		},
	},
	{
		id = "junkbot",
		setId = "junkbot",
		label = "Junkbot",
		sortOrder = 60,
		assetModelName = "Junkbot",
		iconName = "Junkbot",
		bonuses = {
			luckBonus = 0.019,
			rollSpeedBonus = 0.0095,
			moneyMultiplier = 1.024,
			passiveIncomePerSecondBonus = 5,
		},
	},
	{
		id = "knights_of_redcliff_paladin",
		setId = "knights_of_redcliff_paladin",
		label = "Paladin",
		sortOrder = 70,
		assetModelName = "Knights of Redcliff: Paladin",
		iconName = "Paladin",
		bonuses = {
			luckBonus = 0.023,
			rollSpeedBonus = 0.0115,
			moneyMultiplier = 1.029,
			passiveIncomePerSecondBonus = 5,
		},
	},
	{
		id = "billy",
		setId = "billy",
		label = "Billy",
		sortOrder = 80,
		assetModelName = "Billy",
		iconName = "Billy",
		bonuses = {
			luckBonus = 0.028,
			rollSpeedBonus = 0.014,
			moneyMultiplier = 1.035,
			passiveIncomePerSecondBonus = 5,
		},
	},
	{
		id = "potato_boy",
		setId = "potato_boy",
		label = "Potato Boy",
		sortOrder = 90,
		assetModelName = "Potato boy",
		iconName = "PotatoBoy",
		bonuses = {
			luckBonus = 0.032,
			rollSpeedBonus = 0.016,
			moneyMultiplier = 1.04,
			passiveIncomePerSecondBonus = 12,
		},
	},
	{
		id = "werewolf",
		setId = "werewolf",
		label = "Werewolf",
		sortOrder = 100,
		assetModelName = "Werewolf",
		iconName = "Werewolf",
		bonuses = {
			luckBonus = 0.034,
			rollSpeedBonus = 0.017,
			moneyMultiplier = 1.043,
			passiveIncomePerSecondBonus = 12,
		},
	},
	{
		id = "superhero",
		setId = "superhero",
		label = "Superhero",
		sortOrder = 110,
		assetModelName = "Superhero",
		iconName = "Superhero",
		bonuses = {
			luckBonus = 0.036,
			rollSpeedBonus = 0.018,
			moneyMultiplier = 1.047,
			passiveIncomePerSecondBonus = 12,
		},
	},
	{
		id = "zombie",
		setId = "zombie",
		label = "Zombie",
		sortOrder = 120,
		assetModelName = "Zombie",
		iconName = "Zombie",
		bonuses = {
			luckBonus = 0.038,
			rollSpeedBonus = 0.019,
			moneyMultiplier = 1.051,
			passiveIncomePerSecondBonus = 12,
		},
	},
	{
		id = "pirate_swashbuckler",
		setId = "pirate_swashbuckler",
		label = "Pirate",
		sortOrder = 130,
		assetModelName = "Pirate Swashbuckler",
		iconName = "Pirate",
		bonuses = {
			luckBonus = 0.041,
			rollSpeedBonus = 0.0205,
			moneyMultiplier = 1.056,
			passiveIncomePerSecondBonus = 12,
		},
	},
	{
		id = "penguin",
		setId = "penguin",
		label = "Penguin",
		sortOrder = 140,
		assetModelName = "Penguin",
		iconName = "Penguin",
		bonuses = {
			luckBonus = 0.044,
			rollSpeedBonus = 0.022,
			moneyMultiplier = 1.062,
			passiveIncomePerSecondBonus = 12,
		},
	},
	{
		id = "gingerbread_man",
		setId = "gingerbread_man",
		label = "Gingerbread",
		sortOrder = 150,
		assetModelName = "Gingerbread Man",
		iconName = "Gingerbread",
		bonuses = {
			luckBonus = 0.047,
			rollSpeedBonus = 0.0235,
			moneyMultiplier = 1.068,
			passiveIncomePerSecondBonus = 12,
		},
	},
	{
		id = "skeleton",
		setId = "skeleton",
		label = "Skeleton",
		sortOrder = 160,
		assetModelName = "Skeleton",
		iconName = "Skeleton",
		bonuses = {
			luckBonus = 0.051,
			rollSpeedBonus = 0.0255,
			moneyMultiplier = 1.075,
			passiveIncomePerSecondBonus = 12,
		},
	},
	{
		id = "mr_roboto",
		setId = "mr_roboto",
		label = "Robot",
		sortOrder = 170,
		assetModelName = "Mr. Roboto",
		iconName = "Robot",
		bonuses = {
			luckBonus = 0.055,
			rollSpeedBonus = 0.0275,
			moneyMultiplier = 1.083,
			passiveIncomePerSecondBonus = 12,
		},
	},
	{
		id = "snow_gentleman",
		setId = "snow_gentleman",
		label = "Snowman",
		sortOrder = 180,
		assetModelName = "Snow Gentleman",
		iconName = "Snowman",
		bonuses = {
			luckBonus = 0.06,
			rollSpeedBonus = 0.03,
			moneyMultiplier = 1.092,
			passiveIncomePerSecondBonus = 12,
		},
	},
	{
		id = "frost_guard_general",
		setId = "frost_guard_general",
		label = "Frost Guard",
		sortOrder = 190,
		assetModelName = "Frost Guard General",
		iconName = "Frost Guard",
		bonuses = {
			luckBonus = 0.065,
			rollSpeedBonus = 0.0325,
			moneyMultiplier = 1.102,
			passiveIncomePerSecondBonus = 12,
		},
	},
	{
		id = "snow_queen",
		setId = "snow_queen",
		label = "Snow Queen",
		sortOrder = 200,
		assetModelName = "Snow Queen",
		iconName = "SnowQueen",
		bonuses = {
			luckBonus = 0.071,
			rollSpeedBonus = 0.0355,
			moneyMultiplier = 1.113,
			passiveIncomePerSecondBonus = 12,
		},
	},
	{
		id = "tentacled_alien",
		setId = "tentacled_alien",
		label = "Alien",
		sortOrder = 210,
		assetModelName = withTrailingSpaces("Tentacled Alien", 2),
		iconName = "Alien",
		bonuses = {
			luckBonus = 0.078,
			rollSpeedBonus = 0.039,
			moneyMultiplier = 1.125,
			passiveIncomePerSecondBonus = 12,
		},
	},
	{
		id = "mr_toilet",
		setId = "mr_toilet",
		label = "Toilet",
		sortOrder = 220,
		assetModelName = "Mr. Toilet",
		iconName = "Toilet",
		bonuses = {
			luckBonus = 0.086,
			rollSpeedBonus = 0.043,
			moneyMultiplier = 1.138,
			passiveIncomePerSecondBonus = 12,
		},
	},
	{
		id = "paper_sketch_boy_animated",
		setId = "paper_sketch_boy_animated",
		label = "Paper Boy",
		sortOrder = 230,
		assetModelName = "Paper Sketch Boy Animated",
		iconName = "PaperBoy",
		bonuses = {
			luckBonus = 0.095,
			rollSpeedBonus = 0.0475,
			moneyMultiplier = 1.152,
			passiveIncomePerSecondBonus = 12,
		},
	},
	{
		id = "noob_attack_mech_mobility",
		setId = "noob_attack_mech_mobility",
		label = "Mech",
		sortOrder = 240,
		assetModelName = "Noob Attack: Mech Mobility",
		iconName = "Mech",
		bonuses = {
			luckBonus = 0.105,
			rollSpeedBonus = 0.0525,
			moneyMultiplier = 1.168,
			passiveIncomePerSecondBonus = 12,
		},
	},
	{
		id = "korblox_mage",
		setId = "korblox_mage",
		label = "Korblox Mage",
		sortOrder = 250,
		assetModelName = "Korblox Mage",
		iconName = "KorbloxMage",
		bonuses = {
			luckBonus = 0.115,
			rollSpeedBonus = 0.058,
			moneyMultiplier = 1.18,
			passiveIncomePerSecondBonus = 45,
		},
	},
	{
		id = "the_overseer",
		setId = "the_overseer",
		label = "Overseer",
		sortOrder = 260,
		assetModelName = "The Overseer",
		iconName = "Overseer",
		bonuses = {
			luckBonus = 0.12,
			rollSpeedBonus = 0.06,
			moneyMultiplier = 1.188,
			passiveIncomePerSecondBonus = 45,
		},
	},
	{
		id = "korblox_deathspeaker",
		setId = "korblox_deathspeaker",
		label = "Korblox Deathspeaker",
		sortOrder = 270,
		assetModelName = "Korblox Deathspeaker",
		iconName = "Deathspeaker",
		bonuses = {
			luckBonus = 0.126,
			rollSpeedBonus = 0.063,
			moneyMultiplier = 1.197,
			passiveIncomePerSecondBonus = 45,
		},
	},
	{
		id = "headless_horseman",
		setId = "headless_horseman",
		label = "Headless Horseman",
		sortOrder = 280,
		assetModelName = "Headless Horseman",
		iconName = "HeadlessHorseman",
		bonuses = {
			luckBonus = 0.132,
			rollSpeedBonus = 0.066,
			moneyMultiplier = 1.207,
			passiveIncomePerSecondBonus = 45,
		},
	},
	{
		id = "supreme_claus",
		setId = "supreme_claus",
		label = "Supreme Claus",
		sortOrder = 290,
		assetModelName = "Supreme Claus",
		iconName = "SupremeClaus",
		bonuses = {
			luckBonus = 0.139,
			rollSpeedBonus = 0.0695,
			moneyMultiplier = 1.218,
			passiveIncomePerSecondBonus = 45,
		},
	},
	{
		id = "capybara",
		setId = "capybara",
		label = "Capybara",
		sortOrder = 300,
		assetModelName = "Capybara",
		iconName = "Capybara",
		bonuses = {
			luckBonus = 0.146,
			rollSpeedBonus = 0.073,
			moneyMultiplier = 1.23,
			passiveIncomePerSecondBonus = 45,
		},
	},
	{
		id = "gang_o_fries",
		setId = "gang_o_fries",
		label = "Fries",
		sortOrder = 310,
		assetModelName = "Gang O' Fries",
		iconName = "Fries",
		bonuses = {
			luckBonus = 0.154,
			rollSpeedBonus = 0.077,
			moneyMultiplier = 1.243,
			passiveIncomePerSecondBonus = 45,
		},
	},
	{
		id = "the_gnomsky_brothers",
		setId = "the_gnomsky_brothers",
		label = "Gnomsky Brothers",
		sortOrder = 320,
		assetModelName = "The Gnomsky Brothers",
		iconName = "GnomskyBrothers",
		bonuses = {
			luckBonus = 0.163,
			rollSpeedBonus = 0.0815,
			moneyMultiplier = 1.257,
			passiveIncomePerSecondBonus = 45,
		},
	},
	{
		id = "elemental_crystal_golem",
		setId = "elemental_crystal_golem",
		label = "Elemental Crystal Golem",
		sortOrder = 330,
		assetModelName = "Elemental Crystal Golem",
		iconName = "ElementalCrystalGolem",
		bonuses = {
			luckBonus = 0.173,
			rollSpeedBonus = 0.0865,
			moneyMultiplier = 1.272,
			passiveIncomePerSecondBonus = 45,
		},
	},
	{
		id = "ud_zal",
		setId = "ud_zal",
		label = "Udzal",
		sortOrder = 340,
		assetModelName = "Ud'zal",
		iconName = "Ud'zal",
		bonuses = {
			luckBonus = 0.184,
			rollSpeedBonus = 0.092,
			moneyMultiplier = 1.288,
			passiveIncomePerSecondBonus = 45,
		},
	},
	{
		id = "werner_weenie",
		setId = "werner_weenie",
		label = "Werner Weenie",
		sortOrder = 350,
		assetModelName = "Werner Weenie",
		iconName = "WernerWeenie",
		bonuses = {
			luckBonus = 0.196,
			rollSpeedBonus = 0.098,
			moneyMultiplier = 1.305,
			passiveIncomePerSecondBonus = 45,
		},
	},
	{
		id = "steamboat_mouse",
		setId = "steamboat_mouse",
		label = "Steamboat Willie",
		sortOrder = 360,
		assetModelName = "Steamboat Mouse",
		iconName = "SteamboatWillie",
		bonuses = {
			luckBonus = 0.209,
			rollSpeedBonus = 0.1045,
			moneyMultiplier = 1.323,
			passiveIncomePerSecondBonus = 45,
		},
	},
	{
		id = "iron_slayer",
		setId = "iron_slayer",
		label = "Iron Slayer",
		sortOrder = 370,
		assetModelName = "Iron Slayer",
		iconName = "IronSlayer",
		bonuses = {
			luckBonus = 0.223,
			rollSpeedBonus = 0.1115,
			moneyMultiplier = 1.342,
			passiveIncomePerSecondBonus = 45,
		},
	},
	{
		id = "chef_tortrdee",
		setId = "chef_tortrdee",
		label = "Chef Tortrdee",
		sortOrder = 380,
		assetModelName = "Chef Tortrdee",
		iconName = "Chef Tortrdee",
		bonuses = {
			luckBonus = 0.238,
			rollSpeedBonus = 0.119,
			moneyMultiplier = 1.362,
			passiveIncomePerSecondBonus = 45,
		},
	},
	{
		id = "el_gato",
		setId = "el_gato",
		label = "El Gato",
		sortOrder = 390,
		assetModelName = "El Gato",
		iconName = "ElGato",
		bonuses = {
			luckBonus = 0.254,
			rollSpeedBonus = 0.127,
			moneyMultiplier = 1.383,
			passiveIncomePerSecondBonus = 45,
		},
	},
	{
		id = "mech_golem",
		setId = "mech_golem",
		label = "Mech Golem",
		sortOrder = 400,
		assetModelName = "Mech Golem",
		iconName = "Mech (2)",
		bonuses = {
			luckBonus = 0.271,
			rollSpeedBonus = 0.1355,
			moneyMultiplier = 1.405,
			passiveIncomePerSecondBonus = 45,
		},
	},
	{
		id = "los_tralaleritos_brainrot",
		setId = "los_tralaleritos_brainrot",
		label = "Los Tralaleritos",
		sortOrder = 410,
		assetModelName = "Los Tralaleritos (Brainrot)",
		iconName = "Tralalerito",
		bonuses = {
			luckBonus = 0.289,
			rollSpeedBonus = 0.1445,
			moneyMultiplier = 1.428,
			passiveIncomePerSecondBonus = 45,
		},
	},
	{
		id = "smiling_freak",
		setId = "smiling_freak",
		label = "Smiling Freak",
		sortOrder = 420,
		assetModelName = "Smiling Freak",
		iconName = "SmilingFreak",
		bonuses = {
			luckBonus = 0.308,
			rollSpeedBonus = 0.154,
			moneyMultiplier = 1.452,
			passiveIncomePerSecondBonus = 45,
		},
	},
	{
		id = "heart",
		setId = "heart",
		label = "Heart",
		sortOrder = 430,
		assetModelName = "Heart",
		iconName = "Heart (2)",
		bonuses = {
			luckBonus = 0.328,
			rollSpeedBonus = 0.164,
			moneyMultiplier = 1.477,
			passiveIncomePerSecondBonus = 45,
		},
	},
	{
		id = "stinky_monkey",
		setId = "stinky_monkey",
		label = "Stinky Monkey",
		sortOrder = 440,
		assetModelName = "Stinky Monkey",
		iconName = "StinkyMonkey",
		bonuses = {
			luckBonus = 0.35,
			rollSpeedBonus = 0.175,
			moneyMultiplier = 1.5,
			passiveIncomePerSecondBonus = 25,
		},
	},
	{
		id = "shrek",
		setId = "shrek",
		label = "Shrek",
		sortOrder = 450,
		assetModelName = "SHREK",
		iconName = "Shrek",
		bonuses = {
			luckBonus = 0.375,
			rollSpeedBonus = 0.1875,
			moneyMultiplier = 1.525,
			passiveIncomePerSecondBonus = 25,
		},
	},
	{
		id = "banana_bro",
		setId = "banana_bro",
		label = "Banana Bro",
		sortOrder = 460,
		assetModelName = "Banana Bro",
		iconName = "BananaBro",
		bonuses = {
			luckBonus = 0.402,
			rollSpeedBonus = 0.201,
			moneyMultiplier = 1.552,
			passiveIncomePerSecondBonus = 25,
		},
	},
	{
		id = "the_rulk_custom_colour",
		setId = "the_rulk_custom_colour",
		label = "The Rulk",
		sortOrder = 470,
		assetModelName = "The Rulk - Custom Colour",
		iconName = "TheRulk",
		bonuses = {
			luckBonus = 0.431,
			rollSpeedBonus = 0.2155,
			moneyMultiplier = 1.58,
			passiveIncomePerSecondBonus = 25,
		},
	},
	{
		id = "cat_mech",
		setId = "cat_mech",
		label = "Cat Mech",
		sortOrder = 480,
		assetModelName = "Cat Mech",
		iconName = "CatMech",
		bonuses = {
			luckBonus = 0.463,
			rollSpeedBonus = 0.2315,
			moneyMultiplier = 1.61,
			passiveIncomePerSecondBonus = 25,
		},
	},
	{
		id = "handsome_squidward",
		setId = "handsome_squidward",
		label = "Handsome Squidward",
		sortOrder = 490,
		assetModelName = "Handsome Squidward",
		iconName = "Squid",
		bonuses = {
			luckBonus = 0.497,
			rollSpeedBonus = 0.2485,
			moneyMultiplier = 1.642,
			passiveIncomePerSecondBonus = 25,
		},
	},
	{
		id = "67_brainrot",
		setId = "67_brainrot",
		label = "67",
		sortOrder = 500,
		assetModelName = "67 (Brainrot)",
		iconName = "67",
		bonuses = {
			luckBonus = 0.534,
			rollSpeedBonus = 0.267,
			moneyMultiplier = 1.676,
			passiveIncomePerSecondBonus = 25,
		},
	},
	{
		id = "deer_monster_99_nights_in_the_forest",
		setId = "deer_monster_99_nights_in_the_forest",
		label = "99 Nights",
		sortOrder = 510,
		assetModelName = "Deer Monster (99 Nights in the Forest)",
		iconName = "99Nights",
		bonuses = {
			luckBonus = 0.575,
			rollSpeedBonus = 0.2875,
			moneyMultiplier = 1.712,
			passiveIncomePerSecondBonus = 25,
		},
	},
	{
		id = "bastion_mech_robot_recolorable",
		setId = "bastion_mech_robot_recolorable",
		label = "Giant Mech",
		sortOrder = 520,
		assetModelName = "Bastion mech robot [recolorable]",
		iconName = "GiantMech",
		bonuses = {
			luckBonus = 0.62,
			rollSpeedBonus = 0.31,
			moneyMultiplier = 1.76,
			passiveIncomePerSecondBonus = 90,
		},
	},
	{
		id = "absolute_unit",
		setId = "absolute_unit",
		label = "Absolute Unit",
		sortOrder = 530,
		assetModelName = "Absolute Unit",
		iconName = "AbsoluteUnit",
		bonuses = {
			luckBonus = 0.69,
			rollSpeedBonus = 0.345,
			moneyMultiplier = 1.84,
			passiveIncomePerSecondBonus = 90,
		},
	},
	{
		id = "muscle_insane_chad_8_pack_body",
		setId = "muscle_insane_chad_8_pack_body",
		label = "Celestial Titan",
		sortOrder = 540,
		assetModelName = "Muscle Insane Chad 8 Pack Body",
		iconName = "Chad",
		bonuses = {
			luckBonus = 0.78,
			rollSpeedBonus = 0.39,
			moneyMultiplier = 1.95,
			passiveIncomePerSecondBonus = 90,
		},
	},
	{
		id = "flame_guard_general",
		setId = "flame_guard_general",
		label = "Flame Guard General",
		sortOrder = 550,
		assetModelName = "Flame Guard General",
		iconName = "FlameGuardGeneral",
		bonuses = {
			luckBonus = 0.86,
			rollSpeedBonus = 0.43,
			moneyMultiplier = 2.06,
			passiveIncomePerSecondBonus = 125,
		},
	},
	{
		id = "captain_squid",
		setId = "captain_squid",
		label = "Captain Squid",
		sortOrder = 560,
		assetModelName = "Captain Squid",
		iconName = "CaptainSquid",
		bonuses = {
			luckBonus = 0.95,
			rollSpeedBonus = 0.475,
			moneyMultiplier = 2.18,
			passiveIncomePerSecondBonus = 150,
		},
	},
	{
		id = "merfin_the_great",
		setId = "merfin_the_great",
		label = "Merfin the Great",
		sortOrder = 570,
		assetModelName = "Merfin the Great",
		iconName = "MerfinTheGreat",
		bonuses = {
			luckBonus = 1.05,
			rollSpeedBonus = 0.525,
			moneyMultiplier = 2.32,
			passiveIncomePerSecondBonus = 175,
		},
	},
	{
		id = "oinan_thickhoof",
		setId = "oinan_thickhoof",
		label = "Oinan Thickhoof",
		sortOrder = 580,
		assetModelName = "Oinan Thickhoof",
		iconName = "OinanThickhoof",
		bonuses = {
			luckBonus = 1.17,
			rollSpeedBonus = 0.585,
			moneyMultiplier = 2.48,
			passiveIncomePerSecondBonus = 225,
		},
	},
	{
		id = "magma_fiend",
		setId = "magma_fiend",
		label = "Magma Fiend",
		sortOrder = 590,
		assetModelName = "Magma Fiend",
		iconName = "MagmaFiend",
		bonuses = {
			luckBonus = 1.3,
			rollSpeedBonus = 0.65,
			moneyMultiplier = 2.66,
			passiveIncomePerSecondBonus = 275,
		},
	},
	{
		id = "broccoli_bro",
		setId = "broccoli_bro",
		label = "Broccoli Bro",
		sortOrder = 600,
		assetModelName = "Broccoli Bro",
		iconName = "BroccoliBro",
		bonuses = {
			luckBonus = 1.45,
			rollSpeedBonus = 0.725,
			moneyMultiplier = 2.86,
			passiveIncomePerSecondBonus = 350,
		},
	},
	{
		id = "destroyer_3000",
		setId = "destroyer_3000",
		label = "Destroyer 3000",
		sortOrder = 610,
		assetModelName = "Mech Armoured Mobile Suit Biped Colourable",
		iconName = "Destroyer3000",
		bonuses = {
			luckBonus = 1.62,
			rollSpeedBonus = 0.81,
			moneyMultiplier = 3.08,
			passiveIncomePerSecondBonus = 450,
		},
	},
	{
		id = "agrynoth",
		setId = "agrynoth",
		label = "Agrynoth",
		sortOrder = 620,
		assetModelName = "Agrynoth",
		iconName = "Agrynoth",
		bonuses = {
			luckBonus = 1.82,
			rollSpeedBonus = 0.91,
			moneyMultiplier = 3.34,
			passiveIncomePerSecondBonus = 600,
		},
	},
	{
		id = "massive_geezer",
		setId = "massive_geezer",
		label = "Massive Geezer",
		sortOrder = 630,
		assetModelName = "Massive Geezer RECOLORABLE",
		iconName = "MassiveGeezer",
		bonuses = {
			luckBonus = 2.05,
			rollSpeedBonus = 1.025,
			moneyMultiplier = 3.65,
			passiveIncomePerSecondBonus = 850,
		},
	},
	{
		id = "cat_mech_elite",
		setId = "cat_mech_elite",
		label = "Cat Mech Elite",
		sortOrder = 640,
		assetModelName = "Cat Mech Elite",
		iconName = "CatMechDestroyer",
		bonuses = {
			luckBonus = 2.3,
			rollSpeedBonus = 1.15,
			moneyMultiplier = 4,
			passiveIncomePerSecondBonus = 1200,
		},
	},
}

local function buildDescription(label: string): string
	return string.format("A set aura earned by completing the %s index.", label)
end

local function getAurasFolder(): Folder?
	local auras = GameAssetResolver.Wait(GameAssetPaths.Effects.Auras, 10)
		or GameAssetResolver.Wait(GameAssetPaths.Legacy.Auras, 10)
	if auras and auras:IsA("Folder") then
		return auras
	end

	return nil
end

local function getAuraIconsFolder(): Folder?
	local auraIcons = GameAssetResolver.Wait({ "UI", "Icons", "Auras" }, 10)
		or GameAssetResolver.Wait({ "UI", "AuraIcons" }, 10)
	if auraIcons and auraIcons:IsA("Folder") then
		return auraIcons
	end

	return nil
end

local function buildExpectedSetIdByModelName(): { [string]: string }
	local expected = {}

	for _, setConfig in ipairs(BodyPartsCatalog.GetAllSets()) do
		local candidateNames = {}
		local alias = MODEL_NAME_ALIAS_BY_SET_ID[setConfig.id]
		if alias then
			table.insert(candidateNames, alias)
		end
		if typeof(setConfig.sourceModelName) == "string" and setConfig.sourceModelName ~= "" then
			table.insert(candidateNames, setConfig.sourceModelName)
		end
		if typeof(setConfig.displayName) == "string" and setConfig.displayName ~= "" then
			table.insert(candidateNames, setConfig.displayName)
		end

		for _, modelName in ipairs(candidateNames) do
			if expected[modelName] == nil then
				expected[modelName] = setConfig.id
			end
		end
	end

	return expected
end

local function isAuraSourceContainer(part: Instance, auraModel: Model): boolean
	if not (part and part:IsA("BasePart")) then
		return false
	end
	if not SUPPORTED_AURA_TARGET_PART_NAMES[part.Name] then
		return false
	end

	local current = part.Parent
	while current and current ~= auraModel do
		if current:IsA("BasePart") then
			return false
		end
		current = current.Parent
	end

	return current == auraModel
end

local function findOwningAuraSourceContainer(instance: Instance, auraModel: Model): BasePart?
	local current = instance.Parent
	while current and current ~= auraModel do
		if current:IsA("BasePart") and isAuraSourceContainer(current, auraModel) then
			return current
		end
		current = current.Parent
	end

	return nil
end

local function validateAuraAssetModel(auraModel: Model, errors: { string })
	local auraAttachments = {}

	for _, descendant in ipairs(auraModel:GetDescendants()) do
		if descendant:IsA("BasePart")
			and not isAuraSourceContainer(descendant, auraModel)
			and findOwningAuraSourceContainer(descendant, auraModel) == nil
		then
			table.insert(
				errors,
				string.format(
					'Aura model "%s" contains unsupported target part "%s".',
					auraModel.Name,
					descendant:GetFullName()
				)
			)
		elseif descendant:IsA("Attachment") then
			auraAttachments[descendant] = true

			local owningPart = findOwningAuraSourceContainer(descendant, auraModel)
			if owningPart == nil then
				table.insert(
					errors,
					string.format(
						'Aura model "%s" has attachment "%s" outside any supported source part.',
						auraModel.Name,
						descendant:GetFullName()
					)
				)
			end
		end
	end

	for _, descendant in ipairs(auraModel:GetDescendants()) do
		local referenceProperties = ATTACHMENT_REFERENCE_PROPERTIES_BY_CLASS[descendant.ClassName]
		if referenceProperties then
			for _, propertyName in ipairs(referenceProperties) do
				local attachment = descendant[propertyName]
				if attachment ~= nil and not auraAttachments[attachment] then
					table.insert(
						errors,
						string.format(
							'Aura model "%s" has %s "%s" referencing attachment "%s" outside the aura model.',
							auraModel.Name,
							descendant.ClassName,
							descendant:GetFullName(),
							attachment:GetFullName()
						)
					)
				end
			end
		end
	end
end

local function validateAndBuild(): ({ [string]: AuraConfigEntry }, { AuraConfigEntry }, { [string]: AuraConfigEntry })
	local errors = {}
	local byId: { [string]: AuraConfigEntry } = {}
	local bySetId: { [string]: AuraConfigEntry } = {}
	local ordered: { AuraConfigEntry } = {}
	local seenAssetModelNames = {}
	local aurasFolder = getAurasFolder()
	local auraIconsFolder = getAuraIconsFolder()
	local auraModelsByName = {}
	local expectedSetIdByModelName = buildExpectedSetIdByModelName()

	if not aurasFolder then
		Logger.Error('AuraConfig validation failed: missing "ReplicatedStorage.GameAssets.Effects.Auras" folder.')
	end
	if not auraIconsFolder then
		Logger.Error('AuraConfig validation failed: missing "ReplicatedStorage.GameAssets.UI.Icons.Auras" folder.')
	end

	for _, child in ipairs(aurasFolder:GetChildren()) do
		if child:IsA("Model") then
			auraModelsByName[child.Name] = child
		end
	end

	for _, rawEntry in ipairs(rawOrdered) do
		if rawEntry.id ~= rawEntry.setId then
			table.insert(errors, string.format('Aura "%s" must reuse its set id as the aura id.', tostring(rawEntry.id)))
		end

		if byId[rawEntry.id] ~= nil then
			table.insert(errors, string.format('Duplicate aura id "%s".', rawEntry.id))
		end

		if bySetId[rawEntry.setId] ~= nil then
			table.insert(errors, string.format('Duplicate aura setId "%s".', rawEntry.setId))
		end

		if seenAssetModelNames[rawEntry.assetModelName] then
			table.insert(errors, string.format('Duplicate aura asset model "%s".', rawEntry.assetModelName))
		else
			seenAssetModelNames[rawEntry.assetModelName] = true
		end

		local setConfig = BodyPartsCatalog.GetSet(rawEntry.setId)
		if not setConfig then
			table.insert(errors, string.format('Aura "%s" references missing set "%s".', rawEntry.id, rawEntry.setId))
			continue
		end

		if rawEntry.label ~= setConfig.displayName then
			table.insert(
				errors,
				string.format(
					'Aura "%s" label "%s" must match the set display name "%s".',
					rawEntry.id,
					rawEntry.label,
					setConfig.displayName
				)
			)
		end

		local auraModel = auraModelsByName[rawEntry.assetModelName]
		if not auraModel then
			table.insert(
				errors,
				string.format(
					'Aura "%s" references missing model "ReplicatedStorage.GameAssets.Effects.Auras.%s".',
					rawEntry.id,
					rawEntry.assetModelName
				)
			)
			continue
		end

		validateAuraAssetModel(auraModel, errors)

		local expectedSetId = expectedSetIdByModelName[rawEntry.assetModelName]
		if expectedSetId ~= nil and expectedSetId ~= rawEntry.setId then
			table.insert(
				errors,
				string.format(
					'Aura model "%s" maps to set "%s", but aura "%s" points to "%s".',
					rawEntry.assetModelName,
					expectedSetId,
					rawEntry.id,
					rawEntry.setId
				)
			)
		end

		local auraIcon = auraIconsFolder:FindFirstChild(rawEntry.iconName)
		if not auraIcon then
			table.insert(
				errors,
				string.format(
					'Aura "%s" references missing icon "ReplicatedStorage.GameAssets.UI.Icons.Auras.%s".',
					rawEntry.id,
					rawEntry.iconName
				)
			)
		elseif not auraIcon:IsA("Decal") then
			table.insert(
				errors,
				string.format(
					'Aura "%s" icon "ReplicatedStorage.GameAssets.UI.Icons.Auras.%s" must be a Decal.',
					rawEntry.id,
					rawEntry.iconName
				)
			)
		end

		local entry: AuraConfigEntry = table.freeze({
			id = rawEntry.id,
			setId = rawEntry.setId,
			label = rawEntry.label,
			description = buildDescription(rawEntry.label),
			tierLabel = string.format("%s Aura", setConfig.rollDisplay.rarity),
			displayColor = setConfig.rollDisplay.color,
			sortOrder = rawEntry.sortOrder,
			assetModelName = rawEntry.assetModelName,
			iconName = rawEntry.iconName,
			bonuses = table.freeze(table.clone(rawEntry.bonuses)),
		})

		byId[entry.id] = entry
		bySetId[entry.setId] = entry
		table.insert(ordered, entry)
	end

	for modelName, setId in pairs(expectedSetIdByModelName) do
		if auraModelsByName[modelName] ~= nil
			and not INTENTIONALLY_UNCONFIGURED_AURA_MODELS[modelName]
			and bySetId[setId] == nil
		then
			table.insert(
				errors,
				string.format('Set "%s" has a matching aura model "%s" but no configured aura entry.', setId, modelName)
			)
		end
	end

	if #errors > 0 then
		Logger.Error("AuraConfig validation failed:\n- " .. table.concat(errors, "\n- "))
	end

	table.sort(ordered, function(a, b)
		if a.sortOrder ~= b.sortOrder then
			return a.sortOrder < b.sortOrder
		end
		return a.id < b.id
	end)

	return table.freeze(byId), table.freeze(ordered), table.freeze(bySetId)
end

local BY_ID, ORDERED, BY_SET_ID = validateAndBuild()

local AuraConfig = {}

function AuraConfig.Get(id: string): AuraConfigEntry?
	return BY_ID[id]
end

function AuraConfig.NormalizeId(value: any): string?
	if typeof(value) ~= "string" or value == "" then
		return nil
	end

	return if BY_ID[value] then value else nil
end

function AuraConfig.GetOrdered(): { AuraConfigEntry }
	return ORDERED
end

function AuraConfig.GetBySetId(setId: string): AuraConfigEntry?
	return BY_SET_ID[setId]
end

function AuraConfig.ResolveModel(auraConfigOrId: AuraConfigEntry | string): Model?
	local auraConfig = if typeof(auraConfigOrId) == "string"
		then AuraConfig.Get(auraConfigOrId)
		else auraConfigOrId
	if not auraConfig then
		return nil
	end

	local aurasFolder = getAurasFolder()
	if not aurasFolder then
		return nil
	end

	local model = aurasFolder:FindFirstChild(auraConfig.assetModelName)
	if model and model:IsA("Model") then
		return model
	end

	return nil
end

function AuraConfig.ResolveIcon(auraConfigOrId: AuraConfigEntry | string): Decal?
	local auraConfig = if typeof(auraConfigOrId) == "string"
		then AuraConfig.Get(auraConfigOrId)
		else auraConfigOrId
	if not auraConfig then
		return nil
	end

	local auraIconsFolder = getAuraIconsFolder()
	if not auraIconsFolder then
		return nil
	end

	local icon = auraIconsFolder:FindFirstChild(auraConfig.iconName)
	if icon and icon:IsA("Decal") then
		return icon
	end

	return nil
end

function AuraConfig.ResolveIconTexture(auraConfigOrId: AuraConfigEntry | string): string?
	local icon = AuraConfig.ResolveIcon(auraConfigOrId)
	if not icon then
		return nil
	end

	local texture = icon.Texture
	if texture == "" then
		return nil
	end

	return texture
end

return table.freeze(AuraConfig)
