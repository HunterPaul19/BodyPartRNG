local TimeShardState = {}

export type TimeShardStateValue = {
	balance: number,
	awardedMinutes: number,
}

local function normalizeWhole(value: any): number
	return math.max(0, math.floor(tonumber(value) or 0))
end

function TimeShardState.CreateEmptyState(): TimeShardStateValue
	return {
		balance = 0,
		awardedMinutes = 0,
	}
end

function TimeShardState.Normalize(value: any): TimeShardStateValue
	local emptyState = TimeShardState.CreateEmptyState()
	if typeof(value) ~= "table" then
		return emptyState
	end

	return {
		balance = normalizeWhole(value.balance),
		awardedMinutes = normalizeWhole(value.awardedMinutes),
	}
end

function TimeShardState.CloneState(value: any): TimeShardStateValue
	return TimeShardState.Normalize(value)
end

return table.freeze(TimeShardState)
