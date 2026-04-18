local BodyPartRegions = require(script.Parent.BodyPartRegions)
local BodyPartsCatalog = require(script.Parent.Parent.Config.BodyParts.Catalog)
local BodyPartLegacyIds = require(script.Parent.Parent.Config.BodyParts.LegacyIds)
local BodyPartRuntimeConfig = require(script.Parent.Parent.Config.BodyParts.Runtime)

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

local function normalizeLoadoutEntry(region: string, entry: any, ownedBodyPartsById: { [string]: any }?): LoadoutEntry?
	if typeof(entry) ~= "table" then
		return nil
	end

	local ownedId = if typeof(entry.ownedId) == "string" and entry.ownedId ~= "" then entry.ownedId else nil
	local pieceId = BodyPartLegacyIds.NormalizePieceId(entry.pieceId)
	if ownedId == nil or pieceId == nil then
		return nil
	end

	local piece = BodyPartsCatalog.GetPiece(pieceId)
	if not piece or piece.region ~= region then
		return nil
	end

	if ownedBodyPartsById ~= nil then
		local ownedRecord = ownedBodyPartsById[ownedId]
		if typeof(ownedRecord) ~= "table" or ownedRecord.pieceId ~= pieceId then
			return nil
		end
	end

	return {
		ownedId = ownedId,
		pieceId = pieceId,
		region = region,
		scale = BodyPartRuntimeConfig.ClampScale(pieceId, entry.scale),
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

function BodyPartLoadout.NormalizeEquippedState(equippedState: any, ownedBodyPartsById: { [string]: any }?): EquippedState
	local normalized = BodyPartLoadout.CreateEmptyEquippedState()

	if typeof(equippedState) ~= "table" then
		return normalized
	end

	for _, region in ipairs(BodyPartRegions.Order) do
		normalized[region] = normalizeLoadoutEntry(region, equippedState[region], ownedBodyPartsById)
	end

	return normalized
end

function BodyPartLoadout.AreEquippedStatesEqual(left: EquippedState?, right: EquippedState?): boolean
	for _, region in ipairs(BodyPartRegions.Order) do
		local leftEntry = left and left[region] or nil
		local rightEntry = right and right[region] or nil

		if leftEntry == nil or rightEntry == nil then
			if leftEntry ~= rightEntry then
				return false
			end
		elseif leftEntry.ownedId ~= rightEntry.ownedId
			or leftEntry.pieceId ~= rightEntry.pieceId
			or leftEntry.region ~= rightEntry.region
			or leftEntry.scale ~= rightEntry.scale
		then
			return false
		end
	end

	return true
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
