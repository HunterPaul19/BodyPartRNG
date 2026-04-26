local CraftingMaterials = {}

export type CraftingMaterialsState = {
	amountsByMaterialId: { [string]: number },
}

function CraftingMaterials.CreateEmptyState(): CraftingMaterialsState
	return {
		amountsByMaterialId = {},
	}
end

return CraftingMaterials
