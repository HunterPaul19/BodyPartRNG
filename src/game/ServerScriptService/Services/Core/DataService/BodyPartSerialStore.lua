local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Globals = require(ReplicatedStorage.Lists.Globals)
local Catalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local RateLimitTelemetry = require(script.Parent.Parent.Common.RateLimitTelemetry)

local STORE_NAME = "BodyPartSerials"
local REUSABLE_STORE_NAME = "BodyPartSerialReusableRanges"
local SERIAL_BLOCK_SIZE = 500
local EXISTENCE_CACHE_REFRESH_SECONDS = 60 * 60
local EXISTENCE_REFRESH_SET_PACING_SECONDS = 0.1
local EXISTENCE_REFRESH_PIECE_PACING_SECONDS = 0.1
local EXISTENCE_REFRESH_WAIT_TIMEOUT_SECONDS = 30

local BodyPartSerialStore = {}

local serialStore = DataStoreService:GetDataStore(STORE_NAME, Globals.SCOPE)
local reusableSerialStore = DataStoreService:GetDataStore(REUSABLE_STORE_NAME, Globals.SCOPE)
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
		refreshedAt: number,
	},
} = {}
local refreshingSetIds: { [string]: boolean } = {}
local existenceRefreshLoopStarted = false

local function validatePieceId(pieceId: string): string?
	if typeof(pieceId) ~= "string" or pieceId == "" then
		return "pieceId is required"
	end

	if not Catalog.GetPiece(pieceId) then
		return string.format("Unknown body part pieceId '%s'.", pieceId)
	end

	return nil
end

local function normalizeReusableRanges(value: any): { { startSerial: number, maxSerial: number } }
	local ranges = {}
	if typeof(value) ~= "table" then
		return ranges
	end

	for _, range in pairs(value) do
		if typeof(range) ~= "table" then
			continue
		end

		local rawStartSerial = tonumber(range.startSerial)
		local rawMaxSerial = tonumber(range.maxSerial)
		if rawStartSerial == nil or rawMaxSerial == nil then
			continue
		end

		local startSerial = math.max(1, math.floor(rawStartSerial))
		local maxSerial = math.max(1, math.floor(rawMaxSerial))
		if startSerial <= maxSerial then
			table.insert(ranges, {
				startSerial = startSerial,
				maxSerial = maxSerial,
			})
		end
	end

	table.sort(ranges, function(a, b)
		if a.startSerial ~= b.startSerial then
			return a.startSerial < b.startSerial
		end
		return a.maxSerial < b.maxSerial
	end)

	local merged = {}
	for _, range in ipairs(ranges) do
		local previous = merged[#merged]
		if previous and range.startSerial <= previous.maxSerial + 1 then
			previous.maxSerial = math.max(previous.maxSerial, range.maxSerial)
		else
			table.insert(merged, {
				startSerial = range.startSerial,
				maxSerial = range.maxSerial,
			})
		end
	end

	return merged
end

local function cacheHighWater(pieceId: string, value: number)
	cachedHighWaterByPieceId[pieceId] = {
		value = math.max(0, math.floor(tonumber(value) or 0)),
		refreshedAt = os.clock(),
	}
end

local function getCachedHighWater(pieceId: string): number?
	local cachedEntry = cachedHighWaterByPieceId[pieceId]
	if cachedEntry == nil then
		return nil
	end

	return cachedEntry.value
end

local function waitForSetRefresh(setId: string): boolean
	local timeoutAt = os.clock() + EXISTENCE_REFRESH_WAIT_TIMEOUT_SECONDS
	while refreshingSetIds[setId] == true and os.clock() < timeoutAt do
		task.wait()
	end

	return refreshingSetIds[setId] ~= true
end

local function loadExistenceForPiece(pieceId: string): (number?, string?)
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

local function refreshExistenceForSet(setId: string): (boolean, string?)
	if refreshingSetIds[setId] == true then
		if waitForSetRefresh(setId) then
			return true, nil
		end

		return false, string.format("Timed out waiting for body part set '%s' existence refresh.", setId)
	end

	local pieces = Catalog.GetPiecesForSet(setId)
	if pieces == nil then
		return false, string.format("Unknown body part setId '%s'.", setId)
	end

	refreshingSetIds[setId] = true
	local success, didRefreshAny, lastError = pcall(function()
		local refreshedAny = false
		local refreshError = nil

		for _, pieceConfig in ipairs(pieces) do
			local pieceId = pieceConfig.id
			if typeof(pieceId) == "string" and pieceId ~= "" then
				local value, message = loadExistenceForPiece(pieceId)
				if value ~= nil then
					refreshedAny = true
				else
					refreshError = message
				end
				task.wait(EXISTENCE_REFRESH_PIECE_PACING_SECONDS)
			end
		end

		return refreshedAny, refreshError
	end)
	refreshingSetIds[setId] = nil

	if not success then
		return false, tostring(didRefreshAny)
	end

	return didRefreshAny == true, lastError
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

local function reserveReusableRange(pieceId: string): (number?, string?)
	local claimedRange: { startSerial: number, maxSerial: number }? = nil
	local success, result = pcall(function()
		return reusableSerialStore:UpdateAsync(pieceId, function(currentValue)
			claimedRange = nil
			local ranges = normalizeReusableRanges(currentValue)
			local range = ranges[1]
			if range == nil then
				return currentValue
			end

			claimedRange = {
				startSerial = range.startSerial,
				maxSerial = range.maxSerial,
			}
			table.remove(ranges, 1)
			return ranges
		end)
	end)

	if not success then
		RateLimitTelemetry.Increment("data_store_error", "serial_body_part_reuse_pop", 1)
		return nil, tostring(result)
	end

	if claimedRange == nil then
		return nil, nil
	end

	reservedSerialRangesByPieceId[pieceId] = {
		nextSerial = claimedRange.startSerial,
		maxSerial = claimedRange.maxSerial,
	}
	return consumeReservedSerial(pieceId), nil
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

	local reusableSerial = reserveReusableRange(pieceId)
	if reusableSerial ~= nil then
		return reusableSerial, nil
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

local function returnReusableRange(pieceId: string, startSerial: number, maxSerial: number): (boolean, string?)
	startSerial = math.max(1, math.floor(tonumber(startSerial) or 0))
	maxSerial = math.max(1, math.floor(tonumber(maxSerial) or 0))
	if startSerial > maxSerial then
		return true, nil
	end

	local success, result = pcall(function()
		return reusableSerialStore:UpdateAsync(pieceId, function(currentValue)
			local ranges = normalizeReusableRanges(currentValue)
			table.insert(ranges, {
				startSerial = startSerial,
				maxSerial = maxSerial,
			})
			return normalizeReusableRanges(ranges)
		end)
	end)

	if not success then
		RateLimitTelemetry.Increment("data_store_error", "serial_body_part_reuse_flush", 1)
		return false, tostring(result)
	end

	return true, nil
end

function BodyPartSerialStore:ReleaseSerialRangeForPiece(
	pieceId: string,
	startSerial: number,
	maxSerial: number
): (boolean, string?)
	local validationError = validatePieceId(pieceId)
	if validationError then
		return false, validationError
	end

	return returnReusableRange(pieceId, startSerial, maxSerial)
end

function BodyPartSerialStore:ReleaseSerialForPiece(pieceId: string, serialNumber: number): (boolean, string?)
	local resolvedSerialNumber = math.floor(tonumber(serialNumber) or 0)
	if resolvedSerialNumber <= 0 then
		return false, "serialNumber is required."
	end

	return self:ReleaseSerialRangeForPiece(pieceId, resolvedSerialNumber, resolvedSerialNumber)
end

function BodyPartSerialStore:ReleaseSerialsForPiece(pieceId: string, serialNumbers: { number }): (boolean, string?)
	local validationError = validatePieceId(pieceId)
	if validationError then
		return false, validationError
	end
	if typeof(serialNumbers) ~= "table" then
		return false, "serialNumbers must be a table."
	end

	local normalizedSerials = {}
	local seenSerials = {}
	for _, serialNumber in ipairs(serialNumbers) do
		local resolvedSerialNumber = math.floor(tonumber(serialNumber) or 0)
		if resolvedSerialNumber > 0 and seenSerials[resolvedSerialNumber] ~= true then
			seenSerials[resolvedSerialNumber] = true
			table.insert(normalizedSerials, resolvedSerialNumber)
		end
	end

	table.sort(normalizedSerials)

	local didReleaseAll = true
	local lastError = nil
	local rangeStart = nil
	local previousSerial = nil
	local function flushRange()
		if rangeStart == nil or previousSerial == nil then
			return
		end

		local didRelease, releaseError = returnReusableRange(pieceId, rangeStart, previousSerial)
		if not didRelease then
			didReleaseAll = false
			lastError = releaseError
		end
	end

	for _, serialNumber in ipairs(normalizedSerials) do
		if rangeStart == nil then
			rangeStart = serialNumber
			previousSerial = serialNumber
		elseif previousSerial ~= nil and serialNumber == previousSerial + 1 then
			previousSerial = serialNumber
		else
			flushRange()
			rangeStart = serialNumber
			previousSerial = serialNumber
		end
	end
	flushRange()

	return didReleaseAll, lastError
end

function BodyPartSerialStore:FlushUnusedReservedSerials(): boolean
	local didFlushAll = true
	for pieceId, reservedRange in pairs(reservedSerialRangesByPieceId) do
		local nextSerial = math.max(1, math.floor(tonumber(reservedRange.nextSerial) or 0))
		local maxSerial = math.max(1, math.floor(tonumber(reservedRange.maxSerial) or 0))
		if nextSerial > maxSerial then
			reservedSerialRangesByPieceId[pieceId] = nil
			continue
		end

		local didReturn = returnReusableRange(pieceId, nextSerial, maxSerial)
		if didReturn then
			reservedSerialRangesByPieceId[pieceId] = nil
		else
			didFlushAll = false
		end
	end

	return didFlushAll
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

	local pieceConfig = Catalog.GetPiece(pieceId)
	local setId = pieceConfig and pieceConfig.setId
	if typeof(setId) ~= "string" or setId == "" then
		return nil, string.format("Body part piece '%s' is missing a setId.", pieceId)
	end

	local _, refreshError = refreshExistenceForSet(setId)
	cachedHighWater = getCachedHighWater(pieceId)
	if cachedHighWater ~= nil then
		return cachedHighWater, nil
	end

	return nil, refreshError or "Failed to refresh body part existence count."
end

function BodyPartSerialStore:StartExistenceRefreshLoop()
	if existenceRefreshLoopStarted then
		return
	end

	existenceRefreshLoopStarted = true
	task.spawn(function()
		while true do
			for _, setConfig in ipairs(Catalog.GetAllSets()) do
				refreshExistenceForSet(setConfig.id)
				task.wait(EXISTENCE_REFRESH_SET_PACING_SECONDS)
			end

			task.wait(EXISTENCE_CACHE_REFRESH_SECONDS)
		end
	end)
end

return BodyPartSerialStore
