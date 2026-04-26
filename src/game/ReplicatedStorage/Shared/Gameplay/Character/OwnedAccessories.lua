local OwnedAccessories = {}

OwnedAccessories.MAX_OWNED_COUNT = 100

OwnedAccessories.Slots = table.freeze({
	HeadAccessory = true,
	ArmAccessory = true,
})

OwnedAccessories.SlotOrder = table.freeze({
	"HeadAccessory",
	"ArmAccessory",
})

export type AccessorySlot = "HeadAccessory" | "ArmAccessory"

export type OwnedAccessoryRecord = {
	ownedId: string,
	accessoryId: string,
	slot: AccessorySlot,
	isFavorite: boolean,
}

export type OwnedAccessoryGrantPayload = {
	accessoryId: string,
}

export type OwnedAccessoriesState = {
	ownedById: { [string]: OwnedAccessoryRecord },
	nextOwnedId: number,
}

export type EquippedAccessoriesState = {
	[string]: string?,
}

function OwnedAccessories.CreateEmptyState(): OwnedAccessoriesState
	return {
		ownedById = {},
		nextOwnedId = 1,
	}
end

function OwnedAccessories.CreateEmptyEquippedState(): EquippedAccessoriesState
	return {
		HeadAccessory = nil,
		ArmAccessory = nil,
	}
end

function OwnedAccessories.CreateOwnedId(nextOwnedId: number): string
	return `accessory_{nextOwnedId}`
end

function OwnedAccessories.NormalizeSlot(slot: any): AccessorySlot?
	if slot == "HeadAccessory" or slot == "ArmAccessory" then
		return slot
	end

	return nil
end

function OwnedAccessories.CountOwnedRecords(recordsById: { [string]: OwnedAccessoryRecord }?): number
	if typeof(recordsById) ~= "table" then
		return 0
	end

	local total = 0
	for _ in pairs(recordsById) do
		total += 1
	end

	return total
end

function OwnedAccessories.CountOwned(state: OwnedAccessoriesState?): number
	if typeof(state) ~= "table" then
		return 0
	end

	return OwnedAccessories.CountOwnedRecords(state.ownedById)
end

return OwnedAccessories
