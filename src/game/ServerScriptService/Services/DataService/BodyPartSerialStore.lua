local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Globals = require(ReplicatedStorage.Lists.Globals)
local Catalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)

local STORE_NAME = "BodyPartSerials"

local BodyPartSerialStore = {}

local serialStore = DataStoreService:GetDataStore(STORE_NAME, Globals.SCOPE)
local studioFallbackCounters: { [string]: number } = {}

local function validatePieceId(pieceId: string): string?
	if typeof(pieceId) ~= "string" or pieceId == "" then
		return "pieceId is required"
	end

	if not Catalog.GetPiece(pieceId) then
		return string.format("Unknown body part pieceId '%s'.", pieceId)
	end

	return nil
end

function BodyPartSerialStore:GetNextSerialForPiece(pieceId: string): (number?, string?)
	local validationError = validatePieceId(pieceId)
	if validationError then
		return nil, validationError
	end

	local success, result = pcall(function()
		return serialStore:UpdateAsync(pieceId, function(currentValue)
			local currentSerial = math.max(0, math.floor(tonumber(currentValue) or 0))
			return currentSerial + 1
		end)
	end)

	if success then
		local serialNumber = tonumber(result)
		if serialNumber then
			return math.max(1, math.floor(serialNumber)), nil
		end
	end

	if RunService:IsStudio() then
		local nextSerial = (studioFallbackCounters[pieceId] or 0) + 1
		studioFallbackCounters[pieceId] = nextSerial
		return nextSerial, nil
	end

	return nil, tostring(result)
end

function BodyPartSerialStore:GetTotalInExistenceForPiece(pieceId: string): (number?, string?)
	local validationError = validatePieceId(pieceId)
	if validationError then
		return nil, validationError
	end

	local success, result = pcall(function()
		return serialStore:GetAsync(pieceId)
	end)

	if success then
		return math.max(0, math.floor(tonumber(result) or 0)), nil
	end

	if RunService:IsStudio() then
		return studioFallbackCounters[pieceId] or 0, nil
	end

	return nil, tostring(result)
end

return BodyPartSerialStore
