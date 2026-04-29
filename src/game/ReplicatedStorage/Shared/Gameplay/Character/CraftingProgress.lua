local CraftingRecipeConfig = require(script.Parent.Parent.Config.CraftingRecipeConfig)
local CraftingMaterialConfig = require(script.Parent.Parent.Config.CraftingMaterialConfig)

local CraftingProgress = {}

export type RecipeProgress = {
	bodyPartsByIngredientKey: { [string]: number },
	materialsByMaterialId: { [string]: number },
}

export type CraftingProgressState = {
	autoRecipeIds: { [string]: boolean },
	autoReadyNotifiedRecipeIds: { [string]: boolean },
	recipesById: { [string]: RecipeProgress },
}

local function toWholeAmount(value: any): number
	return math.max(0, math.floor(tonumber(value) or 0))
end

function CraftingProgress.GetBodyPartIngredientKey(ingredient: any): string
	if typeof(ingredient) ~= "table" then
		return "unknown"
	end
	if typeof(ingredient.pieceId) == "string" and ingredient.pieceId ~= "" then
		return "piece:" .. ingredient.pieceId
	end
	if typeof(ingredient.setId) == "string" and ingredient.setId ~= "" then
		if typeof(ingredient.region) == "string" and ingredient.region ~= "" then
			return string.format("set:%s:%s", ingredient.setId, ingredient.region)
		end
		return "set:" .. ingredient.setId
	end
	return "unknown"
end

function CraftingProgress.CreateEmptyRecipeProgress(): RecipeProgress
	return {
		bodyPartsByIngredientKey = {},
		materialsByMaterialId = {},
	}
end

function CraftingProgress.CreateEmptyState(): CraftingProgressState
	return {
		autoRecipeIds = {},
		autoReadyNotifiedRecipeIds = {},
		recipesById = {},
	}
end

function CraftingProgress.NormalizeRecipeProgress(value: any): RecipeProgress
	local progress = CraftingProgress.CreateEmptyRecipeProgress()
	if typeof(value) ~= "table" then
		return progress
	end

	if typeof(value.bodyPartsByIngredientKey) == "table" then
		for key, amount in pairs(value.bodyPartsByIngredientKey) do
			if typeof(key) == "string" and key ~= "" then
				local normalizedAmount = toWholeAmount(amount)
				if normalizedAmount > 0 then
					progress.bodyPartsByIngredientKey[key] = normalizedAmount
				end
			end
		end
	end

	if typeof(value.materialsByMaterialId) == "table" then
		for materialId, amount in pairs(value.materialsByMaterialId) do
			local normalizedMaterialId = CraftingMaterialConfig.NormalizeId(materialId)
			local normalizedAmount = toWholeAmount(amount)
			if normalizedMaterialId and normalizedAmount > 0 then
				progress.materialsByMaterialId[normalizedMaterialId] =
					(progress.materialsByMaterialId[normalizedMaterialId] or 0) + normalizedAmount
			end
		end
	end

	return progress
end

function CraftingProgress.NormalizeState(value: any): CraftingProgressState
	local state = CraftingProgress.CreateEmptyState()
	if typeof(value) ~= "table" then
		return state
	end

	if typeof(value.autoRecipeIds) == "table" then
		for recipeId, enabled in pairs(value.autoRecipeIds) do
			local normalizedRecipeId = CraftingRecipeConfig.NormalizeId(recipeId)
			if normalizedRecipeId and enabled == true then
				state.autoRecipeIds[normalizedRecipeId] = true
			end
		end
	end

	if typeof(value.autoReadyNotifiedRecipeIds) == "table" then
		for recipeId, notified in pairs(value.autoReadyNotifiedRecipeIds) do
			local normalizedRecipeId = CraftingRecipeConfig.NormalizeId(recipeId)
			if normalizedRecipeId and notified == true then
				state.autoReadyNotifiedRecipeIds[normalizedRecipeId] = true
			end
		end
	end

	if typeof(value.recipesById) == "table" then
		for recipeId, recipeProgress in pairs(value.recipesById) do
			local normalizedRecipeId = CraftingRecipeConfig.NormalizeId(recipeId)
			if normalizedRecipeId then
				local normalizedProgress = CraftingProgress.NormalizeRecipeProgress(recipeProgress)
				if next(normalizedProgress.bodyPartsByIngredientKey) ~= nil
					or next(normalizedProgress.materialsByMaterialId) ~= nil
				then
					state.recipesById[normalizedRecipeId] = normalizedProgress
				end
			end
		end
	end

	return state
end

function CraftingProgress.GetRecipeProgress(state: CraftingProgressState?, recipeId: string): RecipeProgress
	if typeof(state) ~= "table" or typeof(state.recipesById) ~= "table" then
		return CraftingProgress.CreateEmptyRecipeProgress()
	end

	return CraftingProgress.NormalizeRecipeProgress(state.recipesById[recipeId])
end

function CraftingProgress.SetRecipeProgress(state: CraftingProgressState, recipeId: string, progress: RecipeProgress?)
	local normalizedProgress = CraftingProgress.NormalizeRecipeProgress(progress)
	if next(normalizedProgress.bodyPartsByIngredientKey) == nil
		and next(normalizedProgress.materialsByMaterialId) == nil
	then
		state.recipesById[recipeId] = nil
	else
		state.recipesById[recipeId] = normalizedProgress
	end
end

return table.freeze(CraftingProgress)
