local OwnedBodyParts = {}
OwnedBodyParts.MAX_OWNED_COUNT = 100

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
	seenCutsceneSetIds: { [string]: boolean },
	nextOwnedId: number,
}

function OwnedBodyParts.CreateEmptyState(): OwnedBodyPartsState
	return {
		ownedById = {},
		discoveredPieceIds = {},
		seenCutsceneSetIds = {},
		nextOwnedId = 1,
	}
end

function OwnedBodyParts.CreateOwnedId(nextOwnedId: number): string
	return `bp_{nextOwnedId}`
end

function OwnedBodyParts.CountOwnedRecords(recordsById: { [string]: OwnedBodyPartRecord }?): number
	if typeof(recordsById) ~= "table" then
		return 0
	end

	local total = 0
	for _ in pairs(recordsById) do
		total += 1
	end

	return total
end

function OwnedBodyParts.CountOwned(state: OwnedBodyPartsState?): number
	if typeof(state) ~= "table" then
		return 0
	end

	return OwnedBodyParts.CountOwnedRecords(state.ownedById)
end

return OwnedBodyParts
