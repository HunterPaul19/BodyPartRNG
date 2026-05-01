local TutorialConfig = {}

local Steps = table.freeze({
	Welcome = "welcome",
	RollFree = "roll_free",
	EquipBodyPart = "equip_body_part",
	Completed = "completed",
})

TutorialConfig.Steps = Steps
TutorialConfig.StepOrder = table.freeze({
	Steps.Welcome,
	Steps.RollFree,
	Steps.EquipBodyPart,
	Steps.Completed,
})

TutorialConfig.TextByStepId = table.freeze({
	[Steps.Welcome] = "Welcome!",
	[Steps.RollFree] = "Welcome! Start with a free roll.",
	[Steps.EquipBodyPart] = "Nice roll. Open Inventory and equip that body part.",
	[Steps.Completed] = "",
})

TutorialConfig.LegacyCompletedStepIds = table.freeze({
	select_roll_2 = true,
	paid_rolls = true,
	go_appraise = true,
	go_crafting = true,
	craft_holiday_crown = true,
	equip_holiday_crown = true,
	claim_daily_chest = true,
	use_luck_potion = true,
})

local STEP_INDEX_BY_ID = {}
for index, stepId in ipairs(TutorialConfig.StepOrder) do
	STEP_INDEX_BY_ID[stepId] = index
end
TutorialConfig.StepIndexById = table.freeze(STEP_INDEX_BY_ID)

function TutorialConfig.NormalizeStepId(stepId: any): string
	if typeof(stepId) == "string" and STEP_INDEX_BY_ID[stepId] ~= nil then
		return stepId
	end

	return Steps.Welcome
end

function TutorialConfig.IsLegacyCompletedStepId(stepId: any): boolean
	return typeof(stepId) == "string" and TutorialConfig.LegacyCompletedStepIds[stepId] == true
end

function TutorialConfig.GetStepIndex(stepId: any): number
	return STEP_INDEX_BY_ID[TutorialConfig.NormalizeStepId(stepId)] or 1
end

function TutorialConfig.IsLaterStep(leftStepId: any, rightStepId: any): boolean
	return TutorialConfig.GetStepIndex(leftStepId) > TutorialConfig.GetStepIndex(rightStepId)
end

return table.freeze(TutorialConfig)
