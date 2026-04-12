local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BodyPartRegions = require(script.Parent.BodyPartRegions)
local OwnedBodyParts = require(script.Parent.OwnedBodyParts)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)

export type CollectionInput = {
	ownedById: { [string]: OwnedBodyParts.OwnedBodyPartRecord }?,
	discoveredPieceIds: { [string]: boolean }?,
}

export type SetSummary = {
	setId: string,
	setConfig: BodyPartsCatalog.SetConfig,
	discoveredCount: number,
	ownedCount: number,
	discoveredPieceIdsByRegion: { [string]: string },
	ownedPieceIdsByRegion: { [string]: string },
	ownsFullSet: boolean,
}

local BodyPartCollection = {}

local function getDiscoveredPieceIds(collectionState: CollectionInput): { [string]: boolean }
	if typeof(collectionState) == "table" and typeof(collectionState.discoveredPieceIds) == "table" then
		return collectionState.discoveredPieceIds
	end

	return {}
end

local function buildOwnedPieceIdsByRegion(ownedById: { [string]: OwnedBodyParts.OwnedBodyPartRecord }?): { [string]: { [string]: string } }
	local ownedPieceIdsByRegionBySetId = {}
	if typeof(ownedById) ~= "table" then
		return ownedPieceIdsByRegionBySetId
	end

	for _, record in pairs(ownedById) do
		if typeof(record) ~= "table" then
			continue
		end

		local piece = typeof(record.pieceId) == "string" and BodyPartsCatalog.GetPiece(record.pieceId) or nil
		if not piece then
			continue
		end

		local ownedPieceIdsByRegion = ownedPieceIdsByRegionBySetId[piece.setId]
		if not ownedPieceIdsByRegion then
			ownedPieceIdsByRegion = {}
			ownedPieceIdsByRegionBySetId[piece.setId] = ownedPieceIdsByRegion
		end

		ownedPieceIdsByRegion[piece.region] = piece.id
	end

	return ownedPieceIdsByRegionBySetId
end

local function createSetSummary(
	setConfig: BodyPartsCatalog.SetConfig,
	discoveredPieceIds: { [string]: boolean },
	ownedPieceIdsByRegionBySetId: { [string]: { [string]: string } }
): SetSummary
	local ownedPieceIdsByRegion = ownedPieceIdsByRegionBySetId[setConfig.id] or {}
	local discoveredPieceIdsByRegion = {}
	local discoveredCount = 0
	local ownedCount = 0

	for _, region in ipairs(BodyPartRegions.Order) do
		local pieceId = setConfig.piecesByRegion[region]
		if typeof(pieceId) == "string" and discoveredPieceIds[pieceId] == true then
			discoveredPieceIdsByRegion[region] = pieceId
			discoveredCount += 1
		end

		if typeof(ownedPieceIdsByRegion[region]) == "string" then
			ownedCount += 1
		end
	end

	return {
		setId = setConfig.id,
		setConfig = setConfig,
		discoveredCount = discoveredCount,
		ownedCount = ownedCount,
		discoveredPieceIdsByRegion = discoveredPieceIdsByRegion,
		ownedPieceIdsByRegion = ownedPieceIdsByRegion,
		ownsFullSet = ownedCount == #BodyPartRegions.Order,
	}
end

function BodyPartCollection.GetSetSummary(collectionState: CollectionInput, setId: string): SetSummary?
	local setConfig = BodyPartsCatalog.GetSet(setId)
	if not setConfig then
		return nil
	end

	local discoveredPieceIds = getDiscoveredPieceIds(collectionState)
	local ownedPieceIdsByRegionBySetId = buildOwnedPieceIdsByRegion(if typeof(collectionState) == "table" then collectionState.ownedById else nil)
	return createSetSummary(setConfig, discoveredPieceIds, ownedPieceIdsByRegionBySetId)
end

function BodyPartCollection.GetAllSetSummaries(collectionState: CollectionInput): { SetSummary }
	local summaries = table.create(#BodyPartsCatalog.GetAllSets())
	local discoveredPieceIds = getDiscoveredPieceIds(collectionState)
	local ownedPieceIdsByRegionBySetId = buildOwnedPieceIdsByRegion(if typeof(collectionState) == "table" then collectionState.ownedById else nil)

	for _, setConfig in ipairs(BodyPartsCatalog.GetAllSets()) do
		table.insert(summaries, createSetSummary(setConfig, discoveredPieceIds, ownedPieceIdsByRegionBySetId))
	end

	return summaries
end

function BodyPartCollection.OwnsFullSet(collectionState: CollectionInput, setId: string): boolean
	local summary = BodyPartCollection.GetSetSummary(collectionState, setId)
	return summary ~= nil and summary.ownsFullSet
end

return table.freeze(BodyPartCollection)
