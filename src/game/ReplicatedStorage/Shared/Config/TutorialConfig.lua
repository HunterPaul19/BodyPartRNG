local TutorialConfig = {}

local Steps = table.freeze({
	Welcome = "welcome",
	RollFree = "roll_free",
	EquipBodyPart = "equip_body_part",
	SelectRoll2 = "select_roll_2",
	PaidRolls = "paid_rolls",
	GoAppraise = "go_appraise",
	GoCrafting = "go_crafting",
	CraftHolidayCrown = "craft_holiday_crown",
	EquipHolidayCrown = "equip_holiday_crown",
	ClaimDailyChest = "claim_daily_chest",
	UseLuckPotion = "use_luck_potion",
	Completed = "completed",
})

TutorialConfig.Steps = Steps
TutorialConfig.StepOrder = table.freeze({
	Steps.Welcome,
	Steps.RollFree,
	Steps.EquipBodyPart,
	Steps.SelectRoll2,
	Steps.PaidRolls,
	Steps.GoAppraise,
	Steps.GoCrafting,
	Steps.CraftHolidayCrown,
	Steps.EquipHolidayCrown,
	Steps.ClaimDailyChest,
	Steps.UseLuckPotion,
	Steps.Completed,
})

TutorialConfig.TargetRollTypeId = "roll_2"
TutorialConfig.PaidRollGoal = 5
TutorialConfig.LuckBoostPercent = 5000
TutorialConfig.LuckBoostRawBonus = 50
TutorialConfig.Roll2MoneyGrantAmount = 500
TutorialConfig.AppraisalGuaranteedSizeId = "huge"
TutorialConfig.TargetRecipeId = "holiday_crown"
TutorialConfig.TargetAccessoryId = "holiday_crown"
TutorialConfig.TargetAccessorySlot = "HeadAccessory"
TutorialConfig.CraftGuaranteeMaxRolls = 10
TutorialConfig.TutorialChestId = "DailyFree"
TutorialConfig.TutorialPotionId = "luck1"
TutorialConfig.CraftSetIds = table.freeze({
	"roblox_boy",
	"roblox_girl",
	"man",
})

TutorialConfig.TextByStepId = table.freeze({
	[Steps.Welcome] = "Welcome!",
	[Steps.RollFree] = "Welcome! Start with a free roll.",
	[Steps.EquipBodyPart] = "Nice roll. Open Inventory and equip that body part.",
	[Steps.SelectRoll2] = "Select Roll 2. It costs more, but the odds are better.",
	[Steps.PaidRolls] = "Roll 5 times",
	[Steps.GoAppraise] = "Talk to the appraiser",
	[Steps.GoCrafting] = "Go to Crafting and select the first Head Accessory recipe: Holiday Crown.",
	[Steps.CraftHolidayCrown] = "Keep rolling until you can craft Holiday Crown!",
	[Steps.EquipHolidayCrown] = "Open Inventory and equip your Holiday Crown head accessory.",
	[Steps.ClaimDailyChest] = "Here is your free daily chest.",
	[Steps.UseLuckPotion] = "Open Inventory, go to Potions, and use Luck Potion I.",
	[Steps.Completed] = "",
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

function TutorialConfig.GetStepIndex(stepId: any): number
	return STEP_INDEX_BY_ID[TutorialConfig.NormalizeStepId(stepId)] or 1
end

function TutorialConfig.IsLaterStep(leftStepId: any, rightStepId: any): boolean
	return TutorialConfig.GetStepIndex(leftStepId) > TutorialConfig.GetStepIndex(rightStepId)
end

return table.freeze(TutorialConfig)
