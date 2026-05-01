local QuestConfig = {}

export type QuestKind = "main" | "side" | "repeatable" | "unlock" | "test"
export type ObjectiveKind = "event" | "state"
export type CompletionMode = "turnIn" | "autoClaim"

export type QuestObjective = {
	id: string,
	kind: ObjectiveKind,
	description: string,
	targetValue: number,
	eventType: string?,
	stateType: string?,
	countField: string?,
	filters: { [string]: any }?,
	retroactive: boolean?,
}

export type QuestRewards = {
	money: number?,
	materials: { { materialId: string, amount: number } }?,
	potions: { { potionId: string, amount: number } }?,
	bodyParts: { any }?,
	accessories: { any }?,
	auras: { any }?,
	achievementIds: { string }?,
	unlockFlags: { string }?,
}

export type QuestDefinition = {
	id: string,
	displayName: string,
	description: string,
	kind: QuestKind,
	providerIds: { string },
	adminOnly: boolean?,
	hidden: boolean?,
	abandonable: boolean?,
	completionMode: CompletionMode?,
	repeatable: boolean?,
	cooldownSeconds: number?,
	prerequisites: any?,
	objectives: { QuestObjective },
	rewards: QuestRewards,
}

local DEFAULT_REPEATABLE_COOLDOWN_SECONDS = 0

local DEFINITIONS: { QuestDefinition } = {
	{
		id = "test_roll_once",
		displayName = "Test: Roll Once",
		description = "Admin-only quest used to validate roll objective progress.",
		kind = "test",
		providerIds = { "admin_dev", "quest_test_board" },
		adminOnly = true,
		abandonable = true,
		objectives = {
			{
				id = "roll_once",
				kind = "event",
				eventType = "roll_completed",
				description = "Complete 1 roll.",
				targetValue = 1,
			},
		},
		rewards = {
			money = 100,
			unlockFlags = { "test_roll_once_completed" },
		},
	},
	{
		id = "test_equip_body_part",
		displayName = "Test: Equip a Body Part",
		description = "Admin-only quest used to validate equip objective progress.",
		kind = "test",
		providerIds = { "admin_dev", "quest_test_board" },
		adminOnly = true,
		abandonable = true,
		objectives = {
			{
				id = "equip_once",
				kind = "event",
				eventType = "body_part_equipped",
				description = "Equip 1 body part.",
				targetValue = 1,
			},
		},
		rewards = {
			money = 125,
		},
	},
	{
		id = "test_sell_body_part_repeatable",
		displayName = "Test: Sell Body Parts",
		description = "Admin-only repeatable quest used to validate repeatable turn-ins.",
		kind = "repeatable",
		providerIds = { "admin_dev", "quest_test_board" },
		adminOnly = true,
		abandonable = true,
		repeatable = true,
		cooldownSeconds = DEFAULT_REPEATABLE_COOLDOWN_SECONDS,
		objectives = {
			{
				id = "sell_body_parts",
				kind = "event",
				eventType = "body_part_sold",
				countField = "amount",
				description = "Sell 2 body parts.",
				targetValue = 2,
			},
		},
		rewards = {
			money = 250,
			materials = {
				{
					materialId = "scrap",
					amount = 1,
				},
			},
		},
	},
	{
		id = "test_hold_money_state",
		displayName = "Test: Hold Money",
		description = "Admin-only quest used to validate retroactive state objectives.",
		kind = "test",
		providerIds = { "admin_dev", "quest_test_board" },
		adminOnly = true,
		abandonable = true,
		objectives = {
			{
				id = "hold_money",
				kind = "state",
				stateType = "current_money",
				description = "Have $1,000.",
				targetValue = 1000,
				retroactive = true,
			},
		},
		rewards = {
			potions = {
				{
					potionId = "luck1",
					amount = 1,
				},
			},
		},
	},
}

local definitionsById: { [string]: QuestDefinition } = {}
for _, definition in ipairs(DEFINITIONS) do
	definitionsById[definition.id] = table.freeze(definition)
end
for index, definition in ipairs(DEFINITIONS) do
	DEFINITIONS[index] = definitionsById[definition.id]
end
table.freeze(DEFINITIONS)

function QuestConfig.Get(questId: any): QuestDefinition?
	if typeof(questId) ~= "string" then
		return nil
	end

	return definitionsById[questId]
end

function QuestConfig.GetAll(): { QuestDefinition }
	local results = table.create(#DEFINITIONS)
	for index, definition in ipairs(DEFINITIONS) do
		results[index] = definition
	end
	return results
end

function QuestConfig.GetDefaultRepeatableCooldownSeconds(): number
	return DEFAULT_REPEATABLE_COOLDOWN_SECONDS
end

function QuestConfig.IsRepeatable(definition: QuestDefinition): boolean
	return definition.repeatable == true or definition.kind == "repeatable"
end

function QuestConfig.GetCooldownSeconds(definition: QuestDefinition): number
	if not QuestConfig.IsRepeatable(definition) then
		return 0
	end

	return math.max(0, math.floor(tonumber(definition.cooldownSeconds) or DEFAULT_REPEATABLE_COOLDOWN_SECONDS))
end

function QuestConfig.IsAbandonable(definition: QuestDefinition): boolean
	if definition.abandonable ~= nil then
		return definition.abandonable == true
	end

	return definition.kind == "side" or definition.kind == "repeatable" or definition.kind == "test"
end

function QuestConfig.GetCompletionMode(definition: QuestDefinition): CompletionMode
	return if definition.completionMode == "autoClaim" then "autoClaim" else "turnIn"
end

return table.freeze(QuestConfig)
