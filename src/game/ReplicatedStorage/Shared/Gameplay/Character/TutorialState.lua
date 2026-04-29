local TutorialConfig = require(script.Parent.Parent.Config.TutorialConfig)

local TutorialState = {}

export type TutorialStateValue = {
	completed: boolean,
	stepId: string,
	paidRollCount: number,
	luckBoostConsumed: boolean,
	appraisalGuaranteeConsumed: boolean,
	craftGuaranteeRollCount: number,
	tutorialChestClaimed: boolean,
	roll2MoneyGranted: boolean,
	adminReplay: boolean,
}

local function whole(value: any): number
	return math.max(0, math.floor(tonumber(value) or 0))
end

function TutorialState.CreateEmptyState(): TutorialStateValue
	return {
		completed = false,
		stepId = TutorialConfig.Steps.Welcome,
		paidRollCount = 0,
		luckBoostConsumed = false,
		appraisalGuaranteeConsumed = false,
		craftGuaranteeRollCount = 0,
		tutorialChestClaimed = false,
		roll2MoneyGranted = false,
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

	state.completed = value.completed == true
	state.stepId = if state.completed
		then TutorialConfig.Steps.Completed
		else TutorialConfig.NormalizeStepId(value.stepId)
	state.paidRollCount = math.min(whole(value.paidRollCount), TutorialConfig.PaidRollGoal)
	state.luckBoostConsumed = value.luckBoostConsumed == true
	state.appraisalGuaranteeConsumed = value.appraisalGuaranteeConsumed == true
	state.craftGuaranteeRollCount = math.min(whole(value.craftGuaranteeRollCount), TutorialConfig.CraftGuaranteeMaxRolls)
	state.tutorialChestClaimed = value.tutorialChestClaimed == true
	state.roll2MoneyGranted = value.roll2MoneyGranted == true
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
