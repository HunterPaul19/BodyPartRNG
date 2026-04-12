local BodyPartRegions = require(script.Parent.BodyPartRegions)

local BodyPartLoadout = {}

export type LoadoutEntry = {
	ownedId: string,
	pieceId: string,
	region: string,
	scale: number,
}

export type EquippedState = {
	[string]: LoadoutEntry?,
}

local function cloneLoadoutEntry(entry: LoadoutEntry?): LoadoutEntry?
	if typeof(entry) ~= "table" then
		return nil
	end

	return {
		ownedId = entry.ownedId,
		pieceId = entry.pieceId,
		region = entry.region,
		scale = entry.scale,
	}
end

function BodyPartLoadout.CreateEmptyEquippedState(): EquippedState
	local equipped = {}
	for _, region in ipairs(BodyPartRegions.Order) do
		equipped[region] = nil
	end
	return equipped
end

function BodyPartLoadout.CloneLoadoutEntry(entry: LoadoutEntry?): LoadoutEntry?
	return cloneLoadoutEntry(entry)
end

function BodyPartLoadout.CloneEquippedState(equippedState: EquippedState?): EquippedState
	local clone = BodyPartLoadout.CreateEmptyEquippedState()

	if typeof(equippedState) ~= "table" then
		return clone
	end

	for _, region in ipairs(BodyPartRegions.Order) do
		clone[region] = cloneLoadoutEntry(equippedState[region])
	end

	return clone
end

function BodyPartLoadout.HasAnyEquipped(equippedState: EquippedState?): boolean
	if typeof(equippedState) ~= "table" then
		return false
	end

	for _, region in ipairs(BodyPartRegions.Order) do
		if equippedState[region] ~= nil then
			return true
		end
	end

	return false
end

return BodyPartLoadout
