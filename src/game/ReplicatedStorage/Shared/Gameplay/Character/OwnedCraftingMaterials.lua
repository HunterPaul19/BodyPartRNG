local OwnedCraftingMaterials = {}

export type CraftingMaterialsState = {
	amountByMaterialId: { [string]: number },
}

function OwnedCraftingMaterials.CreateEmptyState(): CraftingMaterialsState
	return {
		amountByMaterialId = {},
	}
end

function OwnedCraftingMaterials.CountTotal(state: CraftingMaterialsState?): number
	if typeof(state) ~= "table" or typeof(state.amountByMaterialId) ~= "table" then
		return 0
	end

	local total = 0
	for _, amount in pairs(state.amountByMaterialId) do
		total += math.max(0, math.floor(tonumber(amount) or 0))
	end
	return total
end

return OwnedCraftingMaterials
