local HeadAccessoryConfig = require(script.Parent.HeadAccessoryConfig)
local ArmAccessoryConfig = require(script.Parent.ArmAccessoryConfig)

local AccessoryConfig = {}

AccessoryConfig.Slots = table.freeze({
	HeadAccessory = true,
	ArmAccessory = true,
})

AccessoryConfig.SlotOrder = table.freeze({
	"HeadAccessory",
	"ArmAccessory",
})

export type AccessorySlot = "HeadAccessory" | "ArmAccessory"
export type AccessoryConfigEntry = HeadAccessoryConfig.HeadAccessoryConfigEntry | ArmAccessoryConfig.ArmAccessoryConfigEntry

local entriesById: { [string]: AccessoryConfigEntry } = {}
local orderedEntries: { AccessoryConfigEntry } = {}

local function addEntries(entries: { AccessoryConfigEntry })
	for _, entry in ipairs(entries) do
		entriesById[string.lower(entry.id)] = entry
		table.insert(orderedEntries, entry)
	end
end

addEntries(HeadAccessoryConfig.GetAll())
addEntries(ArmAccessoryConfig.GetAll())

table.sort(orderedEntries, function(left, right)
	if left.slot ~= right.slot then
		return left.slot < right.slot
	end
	if left.sortOrder ~= right.sortOrder then
		return left.sortOrder < right.sortOrder
	end
	return left.id < right.id
end)
table.freeze(orderedEntries)

local function trimAndLower(value: any): string?
	if typeof(value) ~= "string" then
		return nil
	end

	local trimmed = string.match(value, "^%s*(.-)%s*$")
	if not trimmed or trimmed == "" then
		return nil
	end

	return string.lower(trimmed)
end

function AccessoryConfig.NormalizeId(accessoryId: any): string?
	local lowered = trimAndLower(accessoryId)
	local entry = if lowered then entriesById[lowered] else nil
	return if entry then entry.id else nil
end

function AccessoryConfig.Get(accessoryId: any): AccessoryConfigEntry?
	local normalizedId = AccessoryConfig.NormalizeId(accessoryId)
	return if normalizedId then entriesById[string.lower(normalizedId)] else nil
end

function AccessoryConfig.GetAll(): { AccessoryConfigEntry }
	local results = table.create(#orderedEntries)
	for index, entry in ipairs(orderedEntries) do
		results[index] = entry
	end
	return results
end

function AccessoryConfig.NormalizeSlot(slot: any): AccessorySlot?
	if typeof(slot) ~= "string" then
		return nil
	end

	if slot == "HeadAccessory" or slot == "ArmAccessory" then
		return slot
	end

	return nil
end

function AccessoryConfig.GetSlot(accessoryId: any): AccessorySlot?
	local entry = AccessoryConfig.Get(accessoryId)
	return if entry then entry.slot else nil
end

return table.freeze(AccessoryConfig)
