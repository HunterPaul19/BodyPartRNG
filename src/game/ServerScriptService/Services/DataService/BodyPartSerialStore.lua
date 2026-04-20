local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Globals = require(ReplicatedStorage.Lists.Globals)
local Catalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local RateLimitTelemetry = require(script.Parent.Parent.Common.RateLimitTelemetry)

local STORE_NAME = "BodyPartSerials"
local SERIAL_BLOCK_SIZE = 500
local EXISTENCE_CACHE_TTL_SECONDS = 45

local BodyPartSerialStore = {}

local serialStore = DataStoreService:GetDataStore(STORE_NAME, Globals.SCOPE)
local studioFallbackCounters: { [string]: number } = {}
local reservedSerialRangesByPieceId: {
	[string]: {
		nextSerial: number,
		maxSerial: number,
	},
} = {}
local cachedHighWaterByPieceId: {
	[string]: {
		value: number,
		expiresAt: number,
	},
} = {}

local function validatePieceId(pieceId: string): string?
	if typeof(pieceId) ~= "string" or pieceId == "" then
		return "pieceId is required"
	end

	if not Catalog.GetPiece(pieceId) then
		return string.format("Unknown body part pieceId '%s'.", pieceId)
	end

	return nil
end

local function cacheHighWater(pieceId: string, value: number, ttlSeconds: number?)
	cachedHighWaterByPieceId[pieceId] = {
		value = math.max(0, math.floor(tonumber(value) or 0)),
		expiresAt = os.clock() + math.max(1, math.floor(tonumber(ttlSeconds) or EXISTENCE_CACHE_TTL_SECONDS)),
	}
end

local function getCachedHighWater(pieceId: string): number?
	local cachedEntry = cachedHighWaterByPieceId[pieceId]
	if cachedEntry == nil then
		return nil
	end

	if os.clock() >= cachedEntry.expiresAt then
		cachedHighWaterByPieceId[pieceId] = nil
		return nil
	end

	return cachedEntry.value
end

local function consumeReservedSerial(pieceId: string): number?
	local reservedRange = reservedSerialRangesByPieceId[pieceId]
	if reservedRange == nil or reservedRange.nextSerial > reservedRange.maxSerial then
		return nil
	end

	local serialNumber = reservedRange.nextSerial
	reservedRange.nextSerial += 1
	return serialNumber
end

local function reserveSerialRange(pieceId: string): (number?, string?)
	local success, result = pcall(function()
		return serialStore:UpdateAsync(pieceId, function(currentValue)
			local currentSerial = math.max(0, math.floor(tonumber(currentValue) or 0))
			return currentSerial + SERIAL_BLOCK_SIZE
		end)
	end)

	if not success then
		RateLimitTelemetry.Increment("data_store_error", "serial_body_part_standard_write", 1)
		return nil, tostring(result)
	end

	local maxSerial = tonumber(result)
	if maxSerial == nil then
		RateLimitTelemetry.Increment("data_store_error", "serial_body_part_standard_write_invalid", 1)
		return nil, "Serial store returned an invalid serial range."
	end

	maxSerial = math.max(1, math.floor(maxSerial))
	local nextSerial = math.max(1, maxSerial - SERIAL_BLOCK_SIZE + 1)
	reservedSerialRangesByPieceId[pieceId] = {
		nextSerial = nextSerial,
		maxSerial = maxSerial,
	}
	cacheHighWater(pieceId, maxSerial)
	return consumeReservedSerial(pieceId), nil
end

function BodyPartSerialStore:GetNextSerialForPiece(pieceId: string): (number?, string?)
	local validationError = validatePieceId(pieceId)
	if validationError then
		return nil, validationError
	end

	local reservedSerial = consumeReservedSerial(pieceId)
	if reservedSerial ~= nil then
		return reservedSerial, nil
	end

	local reservedRangeSerial, reserveError = reserveSerialRange(pieceId)
	if reservedRangeSerial ~= nil then
		return reservedRangeSerial, nil
	end

	if RunService:IsStudio() then
		local nextSerial = (studioFallbackCounters[pieceId] or 0) + 1
		studioFallbackCounters[pieceId] = nextSerial
		cacheHighWater(pieceId, nextSerial)
		return nextSerial, nil
	end

	return nil, reserveError
end

function BodyPartSerialStore:GetTotalInExistenceForPiece(pieceId: string): (number?, string?)
	local validationError = validatePieceId(pieceId)
	if validationError then
		return nil, validationError
	end

	local cachedHighWater = getCachedHighWater(pieceId)
	if cachedHighWater ~= nil then
		return cachedHighWater, nil
	end

	local success, result = pcall(function()
		return serialStore:GetAsync(pieceId)
	end)

	if success then
		local totalInExistence = math.max(0, math.floor(tonumber(result) or 0))
		cacheHighWater(pieceId, totalInExistence)
		return totalInExistence, nil
	end

	if RunService:IsStudio() then
		local totalInExistence = studioFallbackCounters[pieceId] or 0
		cacheHighWater(pieceId, totalInExistence)
		return totalInExistence, nil
	end

	RateLimitTelemetry.Increment("data_store_error", "serial_body_part_standard_read", 1)
	return nil, tostring(result)
end

return BodyPartSerialStore
