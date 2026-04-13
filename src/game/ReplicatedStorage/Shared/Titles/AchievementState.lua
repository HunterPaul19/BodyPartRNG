local AchievementState = {}

export type AchievementsState = {
	initialized: boolean,
	completedIds: { [string]: boolean },
	rollsSinceInit: number,
	playTimeSinceInit: number,
	seenDiscoveredPieceIds: { [string]: boolean },
	seenCompletedSetIds: { [string]: boolean },
	newDiscoveredCountSinceInit: number,
	newCompletedSetCountSinceInit: number,
}

local function cloneBooleanMap(value: any): { [string]: boolean }
	local copy = {}
	if typeof(value) ~= "table" then
		return copy
	end

	for key, child in pairs(value) do
		if child == true and typeof(key) == "string" and key ~= "" then
			copy[key] = true
		end
	end

	return copy
end

function AchievementState.CreateEmptyState(): AchievementsState
	return {
		initialized = false,
		completedIds = {},
		rollsSinceInit = 0,
		playTimeSinceInit = 0,
		seenDiscoveredPieceIds = {},
		seenCompletedSetIds = {},
		newDiscoveredCountSinceInit = 0,
		newCompletedSetCountSinceInit = 0,
	}
end

function AchievementState.Normalize(value: any): AchievementsState
	local emptyState = AchievementState.CreateEmptyState()
	if typeof(value) ~= "table" then
		return emptyState
	end

	return {
		initialized = value.initialized == true,
		completedIds = cloneBooleanMap(value.completedIds),
		rollsSinceInit = math.max(0, math.floor(tonumber(value.rollsSinceInit) or 0)),
		playTimeSinceInit = math.max(0, math.floor(tonumber(value.playTimeSinceInit) or 0)),
		seenDiscoveredPieceIds = cloneBooleanMap(value.seenDiscoveredPieceIds),
		seenCompletedSetIds = cloneBooleanMap(value.seenCompletedSetIds),
		newDiscoveredCountSinceInit = math.max(0, math.floor(tonumber(value.newDiscoveredCountSinceInit) or 0)),
		newCompletedSetCountSinceInit = math.max(0, math.floor(tonumber(value.newCompletedSetCountSinceInit) or 0)),
	}
end

function AchievementState.HasCompleted(state: any, achievementId: string): boolean
	local normalized = AchievementState.Normalize(state)
	return normalized.completedIds[achievementId] == true
end

return table.freeze(AchievementState)
