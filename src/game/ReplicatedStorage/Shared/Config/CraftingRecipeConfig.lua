local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AccessoryConfig = require(ReplicatedStorage.Shared.Config.AccessoryConfig)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local BodyPartLegacyIds = require(ReplicatedStorage.Shared.Config.BodyParts.LegacyIds)
local CraftingMaterialConfig = require(ReplicatedStorage.Shared.Config.CraftingMaterialConfig)

local CraftingRecipeConfig = {}

export type BodyPartIngredientConfig = {
	pieceId: string,
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
	bodyParts: { BodyPartIngredientConfig },
	materials: { MaterialIngredientConfig },
	yield: CraftingRecipeYield,
}

local RAW_ENTRIES: { CraftingRecipeEntry } = {
	{
		id = "paper_crown",
		label = "Paper Crown",
		description = "Craft a starter head accessory from a basic head and scrap.",
		sortOrder = 10,
		bodyParts = {
			{
				pieceId = "classic_head",
				amount = 1,
			},
		},
		materials = {
			{
				materialId = "scrap",
				amount = 3,
			},
		},
		yield = {
			kind = "accessory",
			accessoryId = "paper_crown",
		},
	},
	{
		id = "training_bracer",
		label = "Training Bracer",
		description = "Craft a starter arm accessory from a basic arm and scrap.",
		sortOrder = 20,
		bodyParts = {
			{
				pieceId = "classic_left_arm",
				amount = 1,
			},
		},
		materials = {
			{
				materialId = "scrap",
				amount = 2,
			},
		},
		yield = {
			kind = "accessory",
			accessoryId = "training_bracer",
		},
	},
	{
		id = "crafted_head",
		label = "Crafted Head",
		description = "Craft a replacement default head from materials.",
		sortOrder = 30,
		bodyParts = {},
		materials = {
			{
				materialId = "scrap",
				amount = 5,
			},
		},
		yield = {
			kind = "bodyPart",
			bodyPartGrant = {
				pieceId = "classic_head",
				rarityDenominator = 1,
				displayRarity = "Crafted",
			},
		},
	},
}

local entriesById: { [string]: CraftingRecipeEntry } = {}
local orderedEntries: { CraftingRecipeEntry } = {}

local function normalizeAmount(value: any): number
	return math.max(1, math.floor(tonumber(value) or 1))
end

local function normalizeRecipe(rawEntry: CraftingRecipeEntry): CraftingRecipeEntry?
	if typeof(rawEntry) ~= "table" or typeof(rawEntry.id) ~= "string" or rawEntry.id == "" then
		return nil
	end

	local bodyParts = {}
	for _, ingredient in ipairs(rawEntry.bodyParts or {}) do
		local pieceId = BodyPartLegacyIds.NormalizePieceId(ingredient.pieceId)
		if pieceId and BodyPartsCatalog.GetPiece(pieceId) then
			table.insert(bodyParts, {
				pieceId = pieceId,
				amount = normalizeAmount(ingredient.amount),
			})
		end
	end

	local materials = {}
	for _, ingredient in ipairs(rawEntry.materials or {}) do
		local materialId = CraftingMaterialConfig.NormalizeId(ingredient.materialId)
		if materialId then
			table.insert(materials, {
				materialId = materialId,
				amount = normalizeAmount(ingredient.amount),
			})
		end
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
