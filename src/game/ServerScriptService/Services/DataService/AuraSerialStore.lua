local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Globals = require(ReplicatedStorage.Lists.Globals)
local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)

local STORE_NAME = "AuraSerials"

local AuraSerialStore = {}

local serialStore = DataStoreService:GetDataStore(STORE_NAME, Globals.SCOPE)
local studioFallbackCounters: { [string]: number } = {}

local function validateAuraId(auraId: string): string?
	if typeof(auraId) ~= "string" or auraId == "" then
		return "auraId is required"
	end

	if not AuraConfig.Get(auraId) then
		return string.format("Unknown auraId '%s'.", auraId)
	end

	return nil
end

function AuraSerialStore:GetNextSerialForAura(auraId: string): (number?, string?)
	local validationError = validateAuraId(auraId)
	if validationError then
		return nil, validationError
	end

	local success, result = pcall(function()
		return serialStore:UpdateAsync(auraId, function(currentValue)
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
		local nextSerial = (studioFallbackCounters[auraId] or 0) + 1
		studioFallbackCounters[auraId] = nextSerial
		return nextSerial, nil
	end

	return nil, tostring(result)
end

function AuraSerialStore:GetTotalInExistenceForAura(auraId: string): (number?, string?)
	local validationError = validateAuraId(auraId)
	if validationError then
		return nil, validationError
	end

	local success, result = pcall(function()
		return serialStore:GetAsync(auraId)
	end)

	if success then
		return math.max(0, math.floor(tonumber(result) or 0)), nil
	end

	if RunService:IsStudio() then
		return studioFallbackCounters[auraId] or 0, nil
	end

	return nil, tostring(result)
end

return AuraSerialStore
