local BossWorldGuideState = {}

export type BossWorldGuideStateValue = {
	prompted: boolean,
	completed: boolean,
	tutorialArenaEntered: boolean,
	promptedAtUnix: number,
	completedAtUnix: number,
	tutorialArenaEnteredAtUnix: number,
}

local function whole(value: any): number
	return math.max(0, math.floor(tonumber(value) or 0))
end

function BossWorldGuideState.CreateEmptyState(): BossWorldGuideStateValue
	return {
		prompted = false,
		completed = false,
		tutorialArenaEntered = false,
		promptedAtUnix = 0,
		completedAtUnix = 0,
		tutorialArenaEnteredAtUnix = 0,
	}
end

function BossWorldGuideState.Normalize(value: any): BossWorldGuideStateValue
	local state = BossWorldGuideState.CreateEmptyState()
	if typeof(value) ~= "table" then
		return state
	end

	state.prompted = value.prompted == true
	state.completed = value.completed == true
	state.tutorialArenaEntered = value.tutorialArenaEntered == true
	if state.completed then
		state.prompted = true
	end
	state.promptedAtUnix = whole(value.promptedAtUnix)
	state.completedAtUnix = whole(value.completedAtUnix)
	state.tutorialArenaEnteredAtUnix = whole(value.tutorialArenaEnteredAtUnix)

	return state
end

function BossWorldGuideState.CloneState(value: any): BossWorldGuideStateValue
	return BossWorldGuideState.Normalize(value)
end

return table.freeze(BossWorldGuideState)
