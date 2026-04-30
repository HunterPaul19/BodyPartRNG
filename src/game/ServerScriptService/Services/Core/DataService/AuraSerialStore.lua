local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Globals = require(ReplicatedStorage.Lists.Globals)
local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local RateLimitTelemetry = require(script.Parent.Parent.Common.RateLimitTelemetry)

local STORE_NAME = "AuraSerials"
local REUSABLE_STORE_NAME = "AuraSerialReusableRanges"
local EXISTENCE_SNAPSHOT_STORE_NAME = "AuraSerialExistenceSnapshots"
local EXISTENCE_SNAPSHOT_KEY = "all"
local EXISTENCE_SNAPSHOT_VERSION = 1
local SERIAL_BLOCK_SIZE = 500
local EXISTENCE_CACHE_REFRESH_SECONDS = 60 * 60
local EXISTENCE_BACKFILL_PACING_SECONDS = 1
local EXISTENCE_SNAPSHOT_SAVE_DEBOUNCE_SECONDS = 10

local AuraSerialStore = {}

local serialStore = DataStoreService:GetDataStore(STORE_NAME, Globals.SCOPE)
local reusableSerialStore = DataStoreService:GetDataStore(REUSABLE_STORE_NAME, Globals.SCOPE)
local existenceSnapshotStore = DataStoreService:GetDataStore(EXISTENCE_SNAPSHOT_STORE_NAME, Globals.SCOPE)
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
		refreshedAt: number,
	},
} = {}
local existenceCacheLoaded = false
local existenceCacheRefreshedAt = 0
local existenceSnapshotRefreshInFlight = false
local existenceBackfillStarted = false
local existenceSnapshotSaveScheduled = false
local existenceRefreshLoopStarted = false

local function validateAuraId(auraId: string): string?
	if typeof(auraId) ~= "string" or auraId == "" then
		return "auraId is required"
	end

	if not AuraConfig.Get(auraId) then
		return string.format("Unknown auraId '%s'.", auraId)
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

local function cacheHighWater(auraId: string, value: number)
	cachedHighWaterByAuraId[auraId] = {
		value = math.max(0, math.floor(tonumber(value) or 0)),
		refreshedAt = os.clock(),
	}
end

local function getCachedHighWater(auraId: string): number?
	local cachedEntry = cachedHighWaterByAuraId[auraId]
	if cachedEntry == nil then
		return nil
	end

	return cachedEntry.value
end

local function loadExistenceForAura(auraId: string): (number?, string?)
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

local function normalizeSnapshotCounts(value: any): { [string]: number }
	local sourceCounts = nil
	if typeof(value) == "table" and typeof(value.countsByAuraId) == "table" then
		sourceCounts = value.countsByAuraId
	elseif typeof(value) == "table" then
		sourceCounts = value
	end

	local countsByAuraId = {}
	if typeof(sourceCounts) ~= "table" then
		return countsByAuraId
	end

	for auraId, rawValue in pairs(sourceCounts) do
		if typeof(auraId) == "string" and AuraConfig.Get(auraId) then
			countsByAuraId[auraId] = math.max(0, math.floor(tonumber(rawValue) or 0))
		end
	end

	return countsByAuraId
end

local function copyCachedCounts(): { [string]: number }
	local countsByAuraId = {}
	for _, auraConfig in ipairs(AuraConfig.GetOrdered()) do
		local auraId = auraConfig.id
		if typeof(auraId) == "string" and auraId ~= "" then
			countsByAuraId[auraId] = getCachedHighWater(auraId) or 0
		end
	end

	return countsByAuraId
end

local function markExistenceCacheRefreshed()
	existenceCacheLoaded = true
	existenceCacheRefreshedAt = os.clock()
end

local function applySnapshotCounts(countsByAuraId: { [string]: number })
	for _, auraConfig in ipairs(AuraConfig.GetOrdered()) do
		local auraId = auraConfig.id
		if typeof(auraId) == "string" and auraId ~= "" then
			cacheHighWater(auraId, math.max(countsByAuraId[auraId] or 0, getCachedHighWater(auraId) or 0))
		end
	end
	markExistenceCacheRefreshed()
end

local function persistExistenceSnapshotNow(): (boolean, string?)
	local countsByAuraId = copyCachedCounts()
	local success, result = pcall(function()
		return existenceSnapshotStore:UpdateAsync(EXISTENCE_SNAPSHOT_KEY, function(currentValue)
			local mergedCounts = normalizeSnapshotCounts(currentValue)
			for auraId, count in pairs(countsByAuraId) do
				mergedCounts[auraId] = math.max(tonumber(mergedCounts[auraId]) or 0, count)
			end

			return {
				version = EXISTENCE_SNAPSHOT_VERSION,
				updatedAtUnix = os.time(),
				countsByAuraId = mergedCounts,
			}
		end)
	end)

	if not success then
		RateLimitTelemetry.Increment("data_store_error", "serial_aura_snapshot_write", 1)
		return false, tostring(result)
	end

	return true, nil
end

local function scheduleExistenceSnapshotPersist()
	if RunService:IsStudio() then
		return
	end
	if existenceSnapshotSaveScheduled then
		return
	end

	existenceSnapshotSaveScheduled = true
	task.delay(EXISTENCE_SNAPSHOT_SAVE_DEBOUNCE_SECONDS, function()
		existenceSnapshotSaveScheduled = false
		persistExistenceSnapshotNow()
	end)
end

local function startLegacyBackfill()
	if existenceBackfillStarted or RunService:IsStudio() then
		return
	end

	existenceBackfillStarted = true
	task.spawn(function()
		local didLoadAny = false
		for _, auraConfig in ipairs(AuraConfig.GetOrdered()) do
			local auraId = auraConfig.id
			if typeof(auraId) == "string" and auraId ~= "" then
				local value = loadExistenceForAura(auraId)
				if value ~= nil then
					didLoadAny = true
				end
				task.wait(EXISTENCE_BACKFILL_PACING_SECONDS)
			end
		end

		if didLoadAny then
			markExistenceCacheRefreshed()
			persistExistenceSnapshotNow()
		end
	end)
end

local function refreshExistenceSnapshotFromStore()
	if existenceSnapshotRefreshInFlight then
		return
	end

	existenceSnapshotRefreshInFlight = true
	local success, result = pcall(function()
		return existenceSnapshotStore:GetAsync(EXISTENCE_SNAPSHOT_KEY)
	end)
	existenceSnapshotRefreshInFlight = false

	if success then
		local countsByAuraId = normalizeSnapshotCounts(result)
		applySnapshotCounts(countsByAuraId)
		if next(countsByAuraId) == nil then
			startLegacyBackfill()
		end
		return
	end

	RateLimitTelemetry.Increment("data_store_error", "serial_aura_snapshot_read", 1)
	markExistenceCacheRefreshed()
	if RunService:IsStudio() then
		applySnapshotCounts({})
	end
end

local function refreshExistenceSnapshotFromStoreAsync()
	if existenceSnapshotRefreshInFlight then
		return
	end

	task.spawn(refreshExistenceSnapshotFromStore)
end

local function ensureExistenceCacheFreshAsync()
	if existenceSnapshotRefreshInFlight then
		return
	end

	if not existenceCacheLoaded or os.clock() - existenceCacheRefreshedAt >= EXISTENCE_CACHE_REFRESH_SECONDS then
		refreshExistenceSnapshotFromStoreAsync()
	end
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

local function reserveReusableRange(auraId: string): (number?, string?)
	local claimedRange: { startSerial: number, maxSerial: number }? = nil
	local success, result = pcall(function()
		return reusableSerialStore:UpdateAsync(auraId, function(currentValue)
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
		RateLimitTelemetry.Increment("data_store_error", "serial_aura_reuse_pop", 1)
		return nil, tostring(result)
	end

	if claimedRange == nil then
		return nil, nil
	end

	reservedSerialRangesByAuraId[auraId] = {
		nextSerial = claimedRange.startSerial,
		maxSerial = claimedRange.maxSerial,
	}
	return consumeReservedSerial(auraId), nil
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
	markExistenceCacheRefreshed()
	scheduleExistenceSnapshotPersist()
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

	local reusableSerial = reserveReusableRange(auraId)
	if reusableSerial ~= nil then
		return reusableSerial, nil
	end

	local reservedRangeSerial, reserveError = reserveSerialRange(auraId)
	if reservedRangeSerial ~= nil then
		return reservedRangeSerial, nil
	end

	if RunService:IsStudio() then
		local nextSerial = (studioFallbackCounters[auraId] or 0) + 1
		studioFallbackCounters[auraId] = nextSerial
		cacheHighWater(auraId, nextSerial)
		markExistenceCacheRefreshed()
		return nextSerial, nil
	end

	return nil, reserveError
end

local function returnReusableRange(auraId: string, startSerial: number, maxSerial: number): (boolean, string?)
	startSerial = math.max(1, math.floor(tonumber(startSerial) or 0))
	maxSerial = math.max(1, math.floor(tonumber(maxSerial) or 0))
	if startSerial > maxSerial then
		return true, nil
	end

	local success, result = pcall(function()
		return reusableSerialStore:UpdateAsync(auraId, function(currentValue)
			local ranges = normalizeReusableRanges(currentValue)
			table.insert(ranges, {
				startSerial = startSerial,
				maxSerial = maxSerial,
			})
			return normalizeReusableRanges(ranges)
		end)
	end)

	if not success then
		RateLimitTelemetry.Increment("data_store_error", "serial_aura_reuse_flush", 1)
		return false, tostring(result)
	end

	return true, nil
end

function AuraSerialStore:FlushUnusedReservedSerials(): boolean
	local didFlushAll = true
	for auraId, reservedRange in pairs(reservedSerialRangesByAuraId) do
		local nextSerial = math.max(1, math.floor(tonumber(reservedRange.nextSerial) or 0))
		local maxSerial = math.max(1, math.floor(tonumber(reservedRange.maxSerial) or 0))
		if nextSerial > maxSerial then
			reservedSerialRangesByAuraId[auraId] = nil
			continue
		end

		local didReturn = returnReusableRange(auraId, nextSerial, maxSerial)
		if didReturn then
			reservedSerialRangesByAuraId[auraId] = nil
		else
			didFlushAll = false
		end
	end

	return didFlushAll
end

function AuraSerialStore:GetTotalInExistenceForAura(auraId: string): (number?, string?)
	local validationError = validateAuraId(auraId)
	if validationError then
		return nil, validationError
	end

	ensureExistenceCacheFreshAsync()
	return getCachedHighWater(auraId) or 0, nil
end

function AuraSerialStore:StartExistenceRefreshLoop()
	if existenceRefreshLoopStarted then
		return
	end

	existenceRefreshLoopStarted = true
	task.spawn(function()
		refreshExistenceSnapshotFromStore()
	end)
end

return AuraSerialStore
