local OwnedBodyParts = {}

export type OwnedBodyPartRecord = {
	ownedId: string,
	pieceId: string,
	rarityDenominator: number,
	rolledSetId: string?,
	rolledSetDisplayName: string?,
	displayOddsDenominator: number?,
	displayRarity: string?,
	mutationId: string?,
	mutation: string,
	mutationMultiplier: number?,
	sizeId: string?,
	sizeMultiplier: number,
	variantMultiplier: number?,
	finalPassiveIncomePerSecond: number?,
	serialNumber: number,
	isFavorite: boolean,
}

export type OwnedBodyPartGrantPayload = {
	pieceId: string,
	rarityDenominator: number,
	rolledSetId: string?,
	rolledSetDisplayName: string?,
	displayOddsDenominator: number?,
	displayRarity: string?,
	mutationId: string?,
	mutation: string?,
	mutationMultiplier: number?,
	sizeId: string?,
	sizeMultiplier: number?,
	variantMultiplier: number?,
	finalPassiveIncomePerSecond: number?,
}

export type OwnedBodyPartsState = {
	ownedById: { [string]: OwnedBodyPartRecord },
	discoveredPieceIds: { [string]: boolean },
	nextOwnedId: number,
}

function OwnedBodyParts.CreateEmptyState(): OwnedBodyPartsState
	return {
		ownedById = {},
		discoveredPieceIds = {},
		nextOwnedId = 1,
	}
end

function OwnedBodyParts.CreateOwnedId(nextOwnedId: number): string
	return `bp_{nextOwnedId}`
end

return OwnedBodyParts
