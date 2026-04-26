local OwnedPotions = {}

export type OwnedPotionRecord = {
	potionId: string,
	amount: number,
	isFavorite: boolean,
}

export type OwnedPotionsState = {
	ownedByPotionId: { [string]: OwnedPotionRecord },
	activeByPotionId: { [string]: number },
}

function OwnedPotions.CreateEmptyState(): OwnedPotionsState
	return {
		ownedByPotionId = {},
		activeByPotionId = {},
	}
end

return OwnedPotions
