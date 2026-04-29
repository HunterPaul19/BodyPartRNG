local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AccessoryConfig = require(ReplicatedStorage.Shared.Config.AccessoryConfig)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local BodyPartLegacyIds = require(ReplicatedStorage.Shared.Config.BodyParts.LegacyIds)
local CraftingMaterialConfig = require(ReplicatedStorage.Shared.Config.CraftingMaterialConfig)

local CraftingRecipeConfig = {}

export type BodyPartIngredientConfig = {
	pieceId: string?,
	setId: string?,
	region: BodyPartsCatalog.BodyRegion?,
	amount: number,
}

export type MaterialIngredientConfig = {
	materialId: string,
	amount: number,
}

export type CraftingRecipeYield =
	{
		kind: "accessory",
		accessoryId: string,
	}
	| {
		kind: "bodyPart",
		bodyPartGrant: {
			pieceId: string,
			rarityDenominator: number?,
			displayRarity: string?,
		},
	}

export type CraftingRecipeEntry = {
	id: string,
	label: string,
	description: string,
	sortOrder: number,
	moneyCost: number,
	bodyParts: { BodyPartIngredientConfig },
	materials: { MaterialIngredientConfig },
	yield: CraftingRecipeYield,
}

local function setIngredient(setId: string, amount: number): BodyPartIngredientConfig
	return {
		setId = setId,
		amount = amount,
	}
end

local function materialIngredient(materialId: string, amount: number): MaterialIngredientConfig
	return {
		materialId = materialId,
		amount = amount,
	}
end

local function accessoryRecipe(
	id: string,
	label: string,
	sortOrder: number,
	moneyCost: number,
	bodyParts: { BodyPartIngredientConfig },
	materials: { MaterialIngredientConfig }?
): CraftingRecipeEntry
	return {
		id = id,
		label = label,
		description = string.format("Craft %s.", label),
		sortOrder = sortOrder,
		moneyCost = moneyCost,
		bodyParts = bodyParts,
		materials = materials or {},
		yield = {
			kind = "accessory",
			accessoryId = id,
		},
	}
end

local RAW_ENTRIES: { CraftingRecipeEntry } = {
	accessoryRecipe("holiday_crown", "Holiday Crown", 30, 1000, {
		setIngredient("roblox_boy", 1),
		setIngredient("roblox_girl", 1),
		setIngredient("man", 1),
	}),
	accessoryRecipe("mystic_sword_of_the_flames", "Mystic Sword of the Flames", 100, 100000, {
		setIngredient("flame_guard_general", 1),
		setIngredient("knights_of_redcliff_paladin", 2),
		setIngredient("billy", 2),
		setIngredient("rig", 1),
	}, {
		materialIngredient("ember_shard", 20),
		materialIngredient("blazesteel_fragment", 8),
		materialIngredient("infernal_crown", 2),
	}),
	accessoryRecipe("the_fire_crown", "The Fire Crown", 105, 125000, {
		setIngredient("flame_guard_general", 1),
		setIngredient("knights_of_redcliff_paladin", 2),
		setIngredient("billy", 1),
		setIngredient("potato_boy", 1),
	}, {
		materialIngredient("ember_shard", 20),
		materialIngredient("blazesteel_fragment", 8),
		materialIngredient("infernal_crown", 2),
	}),
	accessoryRecipe("pirate_lieutenants_cutlass", "Pirate Lieutenant's Cutlass", 110, 350000, {
		setIngredient("captain_squid", 1),
		setIngredient("pirate_swashbuckler", 3),
		setIngredient("skeleton", 2),
		setIngredient("penguin", 1),
	}, {
		materialIngredient("blue_tentacle", 24),
		materialIngredient("pirate_hook", 10),
		materialIngredient("abyssal_compass", 2),
	}),
	accessoryRecipe("pirate_captains_hat", "Pirate Captain's Hat", 115, 500000, {
		setIngredient("captain_squid", 1),
		setIngredient("pirate_swashbuckler", 2),
		setIngredient("penguin", 2),
		setIngredient("skeleton", 2),
	}, {
		materialIngredient("blue_tentacle", 24),
		materialIngredient("pirate_hook", 10),
		materialIngredient("abyssal_compass", 2),
	}),
	accessoryRecipe("mythic_sword_of_the_tides", "Mythic Sword of the Tides", 120, 1000000, {
		setIngredient("merfin_the_great", 1),
		setIngredient("penguin", 2),
		setIngredient("snow_queen", 2),
		setIngredient("tentacled_alien", 2),
	}, {
		materialIngredient("mystic_fish_scale", 30),
		materialIngredient("tidal_staff", 12),
		materialIngredient("tome_of_the_deep", 3),
	}),
	accessoryRecipe("blue_hydromage_wizard_hat", "Blue Hydromage Wizard Hat", 125, 1500000, {
		setIngredient("merfin_the_great", 1),
		setIngredient("snow_queen", 2),
		setIngredient("tentacled_alien", 2),
		setIngredient("korblox_mage", 1),
	}, {
		materialIngredient("mystic_fish_scale", 32),
		materialIngredient("tidal_staff", 12),
		materialIngredient("tome_of_the_deep", 3),
	}),
	accessoryRecipe("axe_of_the_divine_flame", "Axe of the Divine Flame", 130, 3000000, {
		setIngredient("oinan_thickhoof", 1),
		setIngredient("superhero", 2),
		setIngredient("capybara", 2),
		setIngredient("ud_zal", 2),
	}, {
		materialIngredient("divine_leather", 36),
		materialIngredient("titanic_bull_horn", 14),
		materialIngredient("mighty_axe", 4),
	}),
	accessoryRecipe("the_bull", "The Bull", 135, 5000000, {
		setIngredient("oinan_thickhoof", 1),
		setIngredient("capybara", 2),
		setIngredient("ud_zal", 2),
		setIngredient("supreme_claus", 1),
	}, {
		materialIngredient("divine_leather", 40),
		materialIngredient("titanic_bull_horn", 14),
		materialIngredient("mighty_axe", 4),
	}),
	accessoryRecipe("flaming_orb_of_divine_pain", "Flaming Orb of Divine Pain", 140, 10000000, {
		setIngredient("magma_fiend", 1),
		setIngredient("frost_guard_general", 2),
		setIngredient("elemental_crystal_golem", 2),
		setIngredient("iron_slayer", 2),
	}, {
		materialIngredient("molten_chunk", 45),
		materialIngredient("ember_core", 18),
		materialIngredient("volcanic_heart", 5),
	}),
	accessoryRecipe("lava_monster_warrior", "Lava Monster Warrior", 145, 15000000, {
		setIngredient("magma_fiend", 1),
		setIngredient("frost_guard_general", 2),
		setIngredient("iron_slayer", 2),
		setIngredient("elemental_crystal_golem", 1),
	}, {
		materialIngredient("molten_chunk", 50),
		materialIngredient("ember_core", 18),
		materialIngredient("volcanic_heart", 5),
	}),
	accessoryRecipe("mythic_sword_of_the_earth", "Mythic Sword of the Earth", 150, 25000000, {
		setIngredient("broccoli_bro", 1),
		setIngredient("the_gnomsky_brothers", 2),
		setIngredient("elemental_crystal_golem", 2),
		setIngredient("heart", 2),
	}, {
		materialIngredient("broccoli", 55),
		materialIngredient("mixed_salad", 22),
		materialIngredient("golden_broccoli", 6),
	}),
	accessoryRecipe("green_laurel_wreath", "Green Laurel Wreath", 155, 35000000, {
		setIngredient("broccoli_bro", 1),
		setIngredient("the_gnomsky_brothers", 2),
		setIngredient("heart", 2),
		setIngredient("capybara", 1),
	}, {
		materialIngredient("broccoli", 60),
		materialIngredient("mixed_salad", 22),
		materialIngredient("golden_broccoli", 6),
	}),
	accessoryRecipe("red_laser_scythe", "Red Laser Scythe", 160, 75000000, {
		setIngredient("destroyer_3000", 1),
		setIngredient("mr_roboto", 2),
		setIngredient("noob_attack_mech_mobility", 2),
		setIngredient("mech_golem", 2),
	}, {
		materialIngredient("alloy_plate", 70),
		materialIngredient("power_cell", 26),
		materialIngredient("reactor_core", 7),
	}),
	accessoryRecipe("grandpappy_computer", "Grandpappy Computer", 165, 100000000, {
		setIngredient("destroyer_3000", 1),
		setIngredient("mr_roboto", 2),
		setIngredient("noob_attack_mech_mobility", 2),
		setIngredient("mech_golem", 2),
	}, {
		materialIngredient("alloy_plate", 75),
		materialIngredient("power_cell", 28),
		materialIngredient("reactor_core", 8),
	}),
	accessoryRecipe("crescendo_the_soul_stealer", "Crescendo, The Soul Stealer", 170, 200000000, {
		setIngredient("agrynoth", 1),
		setIngredient("skeleton", 2),
		setIngredient("korblox_deathspeaker", 2),
		setIngredient("mahoraga", 2),
	}, {
		materialIngredient("bone_shard", 90),
		materialIngredient("cursed_ribcage", 32),
		materialIngredient("lich_skull", 8),
	}),
	accessoryRecipe("fiery_horns_of_the_netherworld", "Fiery Horns of the Netherworld", 175, 250000000, {
		setIngredient("agrynoth", 1),
		setIngredient("korblox_deathspeaker", 2),
		setIngredient("headless_horseman", 2),
		setIngredient("mahoraga", 2),
	}, {
		materialIngredient("bone_shard", 95),
		materialIngredient("cursed_ribcage", 34),
		materialIngredient("lich_skull", 9),
	}),
	accessoryRecipe("pizza_sword", "Pizza Sword", 180, 500000000, {
		setIngredient("massive_geezer", 1),
		setIngredient("shrek", 2),
		setIngredient("the_rulk_custom_colour", 2),
		setIngredient("absolute_unit", 1),
	}, {
		materialIngredient("chicken_bone", 110),
		materialIngredient("mac_n_cheese", 38),
		materialIngredient("titanic_tooth", 10),
	}),
	accessoryRecipe("telamons_chicken_suit", "Telamon's Chicken Suit", 185, 650000000, {
		setIngredient("massive_geezer", 1),
		setIngredient("shrek", 2),
		setIngredient("absolute_unit", 2),
		setIngredient("deer_monster_99_nights_in_the_forest", 1),
	}, {
		materialIngredient("chicken_bone", 125),
		materialIngredient("mac_n_cheese", 42),
		materialIngredient("titanic_tooth", 12),
	}),
	accessoryRecipe("rainbow_periastron_omega", "Rainbow Periastron Omega", 190, 1250000000, {
		setIngredient("cat_mech_elite", 1),
		setIngredient("cat_mech", 2),
		setIngredient("bastion_mech_robot_recolorable", 2),
		setIngredient("muscle_insane_chad_8_pack_body", 1),
	}, {
		materialIngredient("rainbow_prism", 140),
		materialIngredient("meow_engine", 45),
		materialIngredient("orbital_laser_cannon", 12),
	}),
	accessoryRecipe("rainbow_hatbot", "Rainbow Hatbot", 195, 1500000000, {
		setIngredient("cat_mech_elite", 1),
		setIngredient("cat_mech", 2),
		setIngredient("bastion_mech_robot_recolorable", 2),
		setIngredient("muscle_insane_chad_8_pack_body", 1),
	}, {
		materialIngredient("rainbow_prism", 150),
		materialIngredient("meow_engine", 50),
		materialIngredient("orbital_laser_cannon", 14),
	}),
	accessoryRecipe("bombos_survival_knife", "Bombo's Survival Knife", 200, 75000, {
		setIngredient("billy", 2),
		setIngredient("pirate_swashbuckler", 2),
		setIngredient("skeleton", 1),
	}),
	accessoryRecipe("dark_spell_book_of_the_forgotten", "Dark Spell Book of the Forgotten", 210, 6000000, {
		setIngredient("korblox_mage", 2),
		setIngredient("skeleton", 2),
		setIngredient("tentacled_alien", 1),
		setIngredient("headless_horseman", 1),
	}),
	accessoryRecipe("epsilon_energy_sword", "Epsilon Energy Sword", 220, 30000000, {
		setIngredient("mr_roboto", 2),
		setIngredient("noob_attack_mech_mobility", 2),
		setIngredient("elemental_crystal_golem", 2),
		setIngredient("mech_golem", 1),
	}),
	accessoryRecipe("illumina", "Illumina", 230, 150000000, {
		setIngredient("knights_of_redcliff_paladin", 2),
		setIngredient("snow_queen", 2),
		setIngredient("headless_horseman", 2),
		setIngredient("67_brainrot", 1),
	}),
	accessoryRecipe("telamonster_the_chaos_edge", "Telamonster: The Chaos Edge", 240, 800000000, {
		setIngredient("the_rulk_custom_colour", 2),
		setIngredient("cat_mech", 2),
		setIngredient("mahoraga", 2),
		setIngredient("bastion_mech_robot_recolorable", 1),
		setIngredient("muscle_insane_chad_8_pack_body", 1),
	}),
	accessoryRecipe("black_iron_antlers", "Black Iron Antlers", 250, 3000000, {
		setIngredient("junkbot", 2),
		setIngredient("mr_roboto", 2),
		setIngredient("noob_attack_mech_mobility", 1),
		setIngredient("iron_slayer", 1),
	}),
	accessoryRecipe("valkyrie_helm", "Valkyrie Helm", 260, 25000000, {
		setIngredient("knights_of_redcliff_paladin", 2),
		setIngredient("frost_guard_general", 2),
		setIngredient("snow_queen", 2),
		setIngredient("iron_slayer", 1),
	}),
	accessoryRecipe("empyrean_reignment", "Empyrean Reignment", 270, 150000000, {
		setIngredient("supreme_claus", 2),
		setIngredient("ud_zal", 2),
		setIngredient("heart", 2),
		setIngredient("davy_bazooka", 1),
	}),
	accessoryRecipe("silver_king_of_the_night", "Silver King of the Night", 280, 400000000, {
		setIngredient("headless_horseman", 2),
		setIngredient("korblox_deathspeaker", 2),
		setIngredient("deer_monster_99_nights_in_the_forest", 2),
		setIngredient("mahoraga", 1),
	}),
	accessoryRecipe("lord_of_the_federation", "Lord of the Federation", 290, 1200000000, {
		setIngredient("bastion_mech_robot_recolorable", 2),
		setIngredient("absolute_unit", 2),
		setIngredient("muscle_insane_chad_8_pack_body", 2),
		setIngredient("deer_monster_99_nights_in_the_forest", 2),
	}),
}

local entriesById: { [string]: CraftingRecipeEntry } = {}
local orderedEntries: { CraftingRecipeEntry } = {}
local VALID_REGIONS: { [string]: boolean } = table.freeze({
	Head = true,
	Torso = true,
	LeftArm = true,
	RightArm = true,
	LeftLeg = true,
	RightLeg = true,
})

local function normalizeAmount(value: any): number
	return math.max(1, math.floor(tonumber(value) or 1))
end

local function trimString(value: any): string?
	if typeof(value) ~= "string" then
		return nil
	end

	local trimmed = string.match(value, "^%s*(.-)%s*$")
	return if trimmed and trimmed ~= "" then trimmed else nil
end

local function normalizeSetId(setId: any): string?
	local trimmed = trimString(setId)
	if not trimmed then
		return nil
	end

	local normalizedId = BodyPartLegacyIds.NormalizeSetId(string.lower(trimmed))
	local setConfig = BodyPartsCatalog.GetSet(normalizedId)
	return if setConfig then setConfig.id else nil
end

local function normalizeRegion(region: any): BodyPartsCatalog.BodyRegion?
	local trimmed = trimString(region)
	if not trimmed then
		return nil
	end

	if VALID_REGIONS[trimmed] then
		return trimmed :: BodyPartsCatalog.BodyRegion
	end

	return nil
end

local function normalizeRecipe(rawEntry: CraftingRecipeEntry): CraftingRecipeEntry?
	if typeof(rawEntry) ~= "table" or typeof(rawEntry.id) ~= "string" or rawEntry.id == "" then
		return nil
	end

	local bodyParts = {}
	for _, ingredient in ipairs(rawEntry.bodyParts or {}) do
		local hasRawPieceId = trimString(ingredient.pieceId) ~= nil
		local hasRawSetId = trimString(ingredient.setId) ~= nil
		if hasRawPieceId == hasRawSetId then
			return nil
		end

		local pieceId = BodyPartLegacyIds.NormalizePieceId(ingredient.pieceId)
		local setId = normalizeSetId(ingredient.setId)
		local hasPieceId = pieceId ~= nil and BodyPartsCatalog.GetPiece(pieceId) ~= nil
		local hasSetId = setId ~= nil

		if hasRawPieceId and not hasRawSetId and hasPieceId then
			table.insert(bodyParts, {
				pieceId = pieceId,
				amount = normalizeAmount(ingredient.amount),
			})
		elseif hasRawPieceId then
			return nil
		elseif hasRawSetId and not hasRawPieceId and hasSetId then
			local region = normalizeRegion(ingredient.region)
			if ingredient.region ~= nil and region == nil then
				return nil
			end
			table.insert(bodyParts, {
				setId = setId,
				region = region,
				amount = normalizeAmount(ingredient.amount),
			})
		elseif hasRawSetId then
			return nil
		end
	end

	local materials = {}
	for _, ingredient in ipairs(rawEntry.materials or {}) do
		local materialId = CraftingMaterialConfig.NormalizeId(ingredient.materialId)
		if not materialId then
			return nil
		end
		table.insert(materials, {
			materialId = materialId,
			amount = normalizeAmount(ingredient.amount),
		})
	end

	local recipeYield = rawEntry.yield
	if typeof(recipeYield) ~= "table" then
		return nil
	end

	local normalizedYield = nil
	if recipeYield.kind == "accessory" then
		local accessoryId = AccessoryConfig.NormalizeId(recipeYield.accessoryId)
		if not accessoryId then
			return nil
		end
		normalizedYield = {
			kind = "accessory",
			accessoryId = accessoryId,
		}
	elseif recipeYield.kind == "bodyPart" and typeof(recipeYield.bodyPartGrant) == "table" then
		local pieceId = BodyPartLegacyIds.NormalizePieceId(recipeYield.bodyPartGrant.pieceId)
		if not pieceId or not BodyPartsCatalog.GetPiece(pieceId) then
			return nil
		end
		normalizedYield = {
			kind = "bodyPart",
			bodyPartGrant = {
				pieceId = pieceId,
				rarityDenominator = math.max(1, math.floor(tonumber(recipeYield.bodyPartGrant.rarityDenominator) or 1)),
				displayRarity = if typeof(recipeYield.bodyPartGrant.displayRarity) == "string"
					then recipeYield.bodyPartGrant.displayRarity
					else nil,
			},
		}
	else
		return nil
	end

	return table.freeze({
		id = rawEntry.id,
		label = if typeof(rawEntry.label) == "string" and rawEntry.label ~= "" then rawEntry.label else rawEntry.id,
		description = if typeof(rawEntry.description) == "string" then rawEntry.description else "",
		sortOrder = math.floor(tonumber(rawEntry.sortOrder) or 0),
		moneyCost = math.max(0, math.floor(tonumber(rawEntry.moneyCost) or 0)),
		bodyParts = table.freeze(bodyParts),
		materials = table.freeze(materials),
		yield = table.freeze(normalizedYield),
	})
end

for _, rawEntry in ipairs(RAW_ENTRIES) do
	local entry = normalizeRecipe(rawEntry)
	if entry then
		entriesById[string.lower(entry.id)] = entry
		table.insert(orderedEntries, entry)
	end
end

table.sort(orderedEntries, function(left, right)
	if left.sortOrder ~= right.sortOrder then
		return left.sortOrder < right.sortOrder
	end
	return left.id < right.id
end)
table.freeze(orderedEntries)

local function normalizeId(recipeId: any): string?
	if typeof(recipeId) ~= "string" then
		return nil
	end

	local trimmed = string.match(recipeId, "^%s*(.-)%s*$")
	if not trimmed or trimmed == "" then
		return nil
	end

	local entry = entriesById[string.lower(trimmed)]
	return if entry then entry.id else nil
end

function CraftingRecipeConfig.NormalizeId(recipeId: any): string?
	return normalizeId(recipeId)
end

function CraftingRecipeConfig.Get(recipeId: any): CraftingRecipeEntry?
	local normalizedId = normalizeId(recipeId)
	return if normalizedId then entriesById[string.lower(normalizedId)] else nil
end

function CraftingRecipeConfig.GetAll(): { CraftingRecipeEntry }
	local results = table.create(#orderedEntries)
	for index, entry in ipairs(orderedEntries) do
		results[index] = entry
	end
	return results
end

return table.freeze(CraftingRecipeConfig)
