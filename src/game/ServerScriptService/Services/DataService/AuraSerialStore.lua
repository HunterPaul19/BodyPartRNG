local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Globals = require(ReplicatedStorage.Lists.Globals)
local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local RateLimitTelemetry = require(script.Parent.Parent.Common.RateLimitTelemetry)

local STORE_NAME = "AuraSerials"
local SERIAL_BLOCK_SIZE = 500
local EXISTENCE_CACHE_TTL_SECONDS = 45

local AuraSerialStore = {}

local serialStore = DataStoreService:GetDataStore(STORE_NAME, Globals.SCOPE)
local studioFallbackCounters: { [string]: number } = {}
local reservedSerialRangesByAuraId: {
	[string]: {
		nextSerial: number,
		maxSerial: number,
	},
} = {}
local cachedHighWaterByAuraId: {
	[string]: {
		value: number,
		expiresAt: number,
	},
} = {}

local function validateAuraId(auraId: string): string?
	if typeof(auraId) ~= "string" or auraId == "" then
		return "auraId is required"
	end

	if not AuraConfig.Get(auraId) then
		return string.format("Unknown auraId '%s'.", auraId)
	end

	return nil
end

local function cacheHighWater(auraId: string, value: number, ttlSeconds: number?)
	cachedHighWaterByAuraId[auraId] = {
		value = math.max(0, math.floor(tonumber(value) or 0)),
		expiresAt = os.clock() + math.max(1, math.floor(tonumber(ttlSeconds) or EXISTENCE_CACHE_TTL_SECONDS)),
	}
end

local function getCachedHighWater(auraId: string): number?
	local cachedEntry = cachedHighWaterByAuraId[auraId]
	if cachedEntry == nil then
		return nil
	end

	if os.clock() >= cachedEntry.expiresAt then
		cachedHighWaterByAuraId[auraId] = nil
		return nil
	end

	return cachedEntry.value
end

local function consumeReservedSerial(auraId: string): number?
	local reservedRange = reservedSerialRangesByAuraId[auraId]
	if reservedRange == nil or reservedRange.nextSerial > reservedRange.maxSerial then
		return nil
	end

	local serialNumber = reservedRange.nextSerial
	reservedRange.nextSerial += 1
	return serialNumber
end

local function reserveSerialRange(auraId: string): (number?, string?)
	local success, result = pcall(function()
		return serialStore:UpdateAsync(auraId, function(currentValue)
			local currentSerial = math.max(0, math.floor(tonumber(currentValue) or 0))
			return currentSerial + SERIAL_BLOCK_SIZE
		end)
	end)

	if not success then
		RateLimitTelemetry.Increment("data_store_error", "serial_aura_standard_write", 1)
		return nil, tostring(result)
	end

	local maxSerial = tonumber(result)
	if maxSerial == nil then
		RateLimitTelemetry.Increment("data_store_error", "serial_aura_standard_write_invalid", 1)
		return nil, "Serial store returned an invalid serial range."
	end

	maxSerial = math.max(1, math.floor(maxSerial))
	local nextSerial = math.max(1, maxSerial - SERIAL_BLOCK_SIZE + 1)
	reservedSerialRangesByAuraId[auraId] = {
		nextSerial = nextSerial,
		maxSerial = maxSerial,
	}
	cacheHighWater(auraId, maxSerial)
	return consumeReservedSerial(auraId), nil
end

function AuraSerialStore:GetNextSerialForAura(auraId: string): (number?, string?)
	local validationError = validateAuraId(auraId)
	if validationError then
		return nil, validationError
	end

	local reservedSerial = consumeReservedSerial(auraId)
	if reservedSerial ~= nil then
		return reservedSerial, nil
	end

	local reservedRangeSerial, reserveError = reserveSerialRange(auraId)
	if reservedRangeSerial ~= nil then
		return reservedRangeSerial, nil
	end

	if RunService:IsStudio() then
		local nextSerial = (studioFallbackCounters[auraId] or 0) + 1
		studioFallbackCounters[auraId] = nextSerial
		cacheHighWater(auraId, nextSerial)
		return nextSerial, nil
	end

	return nil, reserveError
end

function AuraSerialStore:GetTotalInExistenceForAura(auraId: string): (number?, string?)
	local validationError = validateAuraId(auraId)
	if validationError then
		return nil, validationError
	end

	local cachedHighWater = getCachedHighWater(auraId)
	if cachedHighWater ~= nil then
		return cachedHighWater, nil
	end

	local success, result = pcall(function()
		return serialStore:GetAsync(auraId)
	end)

	if success then
		local totalInExistence = math.max(0, math.floor(tonumber(result) or 0))
		cacheHighWater(auraId, totalInExistence)
		return totalInExistence, nil
	end

	if RunService:IsStudio() then
		local totalInExistence = studioFallbackCounters[auraId] or 0
		cacheHighWater(auraId, totalInExistence)
		return totalInExistence, nil
	end

	RateLimitTelemetry.Increment("data_store_error", "serial_aura_standard_read", 1)
	return nil, tostring(result)
end

return AuraSerialStore
