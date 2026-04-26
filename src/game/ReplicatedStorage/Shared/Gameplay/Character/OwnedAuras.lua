local OwnedAuras = {}

export type OwnedAuraRecord = {
	ownedId: string,
	auraId: string,
	serialNumber: number,
	isFavorite: boolean,
}

export type OwnedAuraGrantPayload = {
	auraId: string,
}

export type OwnedAurasState = {
	ownedById: { [string]: OwnedAuraRecord },
	ownedAuraIdByAuraId: { [string]: string },
	nextOwnedId: number,
}

function OwnedAuras.CreateEmptyState(): OwnedAurasState
	return {
		ownedById = {},
		ownedAuraIdByAuraId = {},
		nextOwnedId = 1,
	}
end

function OwnedAuras.CreateOwnedId(nextOwnedId: number): string
	return `aura_{nextOwnedId}`
end

return OwnedAuras
