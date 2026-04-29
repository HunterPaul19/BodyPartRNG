local DailyChestState = {}

export type DailyChestStateValue = {
	localUtcOffsetMinutes: number?,
	lastClaimedLocalDayByChestId: { [string]: number },
}

local MIN_UTC_OFFSET_MINUTES = -14 * 60
local MAX_UTC_OFFSET_MINUTES = 14 * 60
local SECONDS_PER_DAY = 24 * 60 * 60

local function normalizeWhole(value: any): number
	return math.floor(tonumber(value) or 0)
end

function DailyChestState.NormalizeOffsetMinutes(value: any): number?
	local numericValue = tonumber(value)
	if numericValue == nil or numericValue ~= numericValue then
		return nil
	end

	return math.clamp(math.floor(numericValue), MIN_UTC_OFFSET_MINUTES, MAX_UTC_OFFSET_MINUTES)
end

function DailyChestState.CreateEmptyState(): DailyChestStateValue
	return {
		localUtcOffsetMinutes = nil,
		lastClaimedLocalDayByChestId = {},
	}
end

function DailyChestState.Normalize(value: any): DailyChestStateValue
	local state = DailyChestState.CreateEmptyState()
	if typeof(value) ~= "table" then
		return state
	end

	state.localUtcOffsetMinutes = DailyChestState.NormalizeOffsetMinutes(value.localUtcOffsetMinutes)

	if typeof(value.lastClaimedLocalDayByChestId) == "table" then
		for chestId, localDay in pairs(value.lastClaimedLocalDayByChestId) do
			if typeof(chestId) == "string" and chestId ~= "" then
				state.lastClaimedLocalDayByChestId[chestId] = math.max(0, normalizeWhole(localDay))
			end
		end
	end

	return state
end

function DailyChestState.CloneState(value: any): DailyChestStateValue
	return DailyChestState.Normalize(value)
end

function DailyChestState.GetLocalDay(unixTime: number?, offsetMinutes: number?): number
	local resolvedTime = math.max(0, math.floor(tonumber(unixTime) or os.time()))
	local resolvedOffset = DailyChestState.NormalizeOffsetMinutes(offsetMinutes) or 0
	return math.floor((resolvedTime + (resolvedOffset * 60)) / SECONDS_PER_DAY)
end

function DailyChestState.IsClaimedForLocalDay(stateValue: any, chestId: string, localDay: number): boolean
	local state = DailyChestState.Normalize(stateValue)
	return state.lastClaimedLocalDayByChestId[chestId] == math.max(0, normalizeWhole(localDay))
end

function DailyChestState.MarkClaimedForLocalDay(
	stateValue: any,
	chestId: string,
	localDay: number
): DailyChestStateValue
	local state = DailyChestState.Normalize(stateValue)
	if typeof(chestId) == "string" and chestId ~= "" then
		state.lastClaimedLocalDayByChestId[chestId] = math.max(0, normalizeWhole(localDay))
	end
	return state
end

return table.freeze(DailyChestState)
