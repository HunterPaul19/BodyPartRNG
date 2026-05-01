local TutorialConfig = require(script.Parent.Parent.Config.TutorialConfig)

local TutorialState = {}

export type TutorialStateValue = {
	completed: boolean,
	stepId: string,
	adminReplay: boolean,
}

function TutorialState.CreateEmptyState(): TutorialStateValue
	return {
		completed = false,
		stepId = TutorialConfig.Steps.Welcome,
		adminReplay = false,
	}
end

function TutorialState.CreateCompletedState(): TutorialStateValue
	local state = TutorialState.CreateEmptyState()
	state.completed = true
	state.stepId = TutorialConfig.Steps.Completed
	return state
end

function TutorialState.Normalize(value: any): TutorialStateValue
	local state = TutorialState.CreateEmptyState()
	if typeof(value) ~= "table" then
		return state
	end

	state.completed = value.completed == true or TutorialConfig.IsLegacyCompletedStepId(value.stepId)
	state.stepId = if state.completed
		then TutorialConfig.Steps.Completed
		else TutorialConfig.NormalizeStepId(value.stepId)
	state.adminReplay = value.adminReplay == true and state.completed ~= true
	return state
end

function TutorialState.CloneState(value: any): TutorialStateValue
	return TutorialState.Normalize(value)
end

function TutorialState.IsCompleted(value: any): boolean
	return TutorialState.Normalize(value).completed == true
end

return table.freeze(TutorialState)
