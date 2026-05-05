local QuestConfig = {}

export type QuestKind = "main" | "side" | "repeatable" | "unlock" | "daily"
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
	timeShards: number?,
	dailyChests: { { chestId: string, amount: number } }?,
	materials: { { materialId: string, amount: number } }?,
	potions: { { potionId: string, amount: number } }?,
	bodyParts: { any }?,
	accessories: { any }?,
	auras: { any }?,
	achievementIds: { string }?,
	unlockFlags: { string }?,
}

export type QuestPart = {
	id: string?,
	description: string?,
	objectives: { QuestObjective },
}

export type QuestDefinition = {
	id: string,
	displayName: string,
	description: string,
	kind: QuestKind,
	providerIds: { string },
	boardVisible: boolean?,
	adminOnly: boolean?,
	hidden: boolean?,
	abandonable: boolean?,
	completionMode: CompletionMode?,
	repeatable: boolean?,
	cooldownSeconds: number?,
	prerequisites: any?,
	parts: { QuestPart }?,
	objectives: { QuestObjective }?,
	rewards: QuestRewards,
}

local DEFAULT_REPEATABLE_COOLDOWN_SECONDS = 0
local DAILY_TIME_SHARD_REWARD = 10

local CLEAN_PLUS_FILTER = table.freeze({
	Clean = true,
	Prime = true,
	Elite = true,
	Apex = true,
})

local PRIME_PLUS_FILTER = table.freeze({
	Prime = true,
	Elite = true,
	Apex = true,
})

local BODY_REGIONS = table.freeze({
	"Head",
	"Torso",
	"LeftArm",
	"RightArm",
	"LeftLeg",
	"RightLeg",
})

local function appendDailyQuest(
	definitions: { QuestDefinition },
	id: string,
	displayName: string,
	description: string,
	objective: QuestObjective
)
	table.insert(definitions, {
		id = id,
		displayName = displayName,
		description = description,
		kind = "daily",
		providerIds = { "daily_board" },
		boardVisible = true,
		abandonable = false,
		completionMode = "autoClaim",
		objectives = {
			objective,
		},
		rewards = {
			timeShards = DAILY_TIME_SHARD_REWARD,
		},
	})
end

local function appendRollCountDailyQuest(definitions: { QuestDefinition }, targetValue: number)
	appendDailyQuest(definitions, string.format("daily_roll_%d_times", targetValue), string.format("Roll %d Times", targetValue), string.format(
		"Complete %d body-part rolls.",
		targetValue
	), {
		id = "roll_count",
		kind = "event",
		eventType = "roll_completed",
		description = string.format("Complete %d rolls.", targetValue),
		targetValue = targetValue,
	})
end

local function appendRollRegionDailyQuest(definitions: { QuestDefinition }, region: string)
	appendDailyQuest(definitions, "daily_roll_region_" .. region, "Roll " .. region, "Roll body parts for this slot.", {
		id = "roll_region",
		kind = "event",
		eventType = "roll_completed",
		description = "Roll 3 " .. region .. " parts.",
		targetValue = 3,
		filters = {
			rollRegion = region,
		},
	})
end

local function appendRollRarityDailyQuest(
	definitions: { QuestDefinition },
	idSuffix: string,
	displayRarityText: string,
	targetValue: number,
	displayRarityFilter: any
)
	appendDailyQuest(
		definitions,
		"daily_roll_" .. idSuffix,
		"Roll " .. displayRarityText,
		"Roll body parts in the " .. displayRarityText .. " rarity band.",
		{
			id = "roll_rarity",
			kind = "event",
			eventType = "roll_completed",
			description = string.format("Roll %d %s parts.", targetValue, displayRarityText),
			targetValue = targetValue,
			filters = {
				displayRarity = displayRarityFilter,
			},
		}
	)
end

local function appendEquipCountDailyQuest(definitions: { QuestDefinition }, targetValue: number)
	appendDailyQuest(definitions, string.format("daily_equip_%d_body_parts", targetValue), string.format("Equip %d Body Parts", targetValue), string.format(
		"Equip %d body parts.",
		targetValue
	), {
		id = "equip_count",
		kind = "event",
		eventType = "body_part_equipped",
		description = string.format("Equip %d body parts.", targetValue),
		targetValue = targetValue,
	})
end

local function appendEquipRegionDailyQuest(definitions: { QuestDefinition }, region: string)
	appendDailyQuest(definitions, "daily_equip_region_" .. region, "Equip " .. region, "Equip a body part in this slot.", {
		id = "equip_region",
		kind = "event",
		eventType = "body_part_equipped",
		description = "Equip 1 " .. region .. " part.",
		targetValue = 1,
		filters = {
			region = region,
		},
	})
end

local function appendSellCountDailyQuest(definitions: { QuestDefinition }, targetValue: number)
	appendDailyQuest(definitions, string.format("daily_sell_%d_body_parts", targetValue), string.format("Sell %d Body Parts", targetValue), string.format(
		"Sell %d body parts.",
		targetValue
	), {
		id = "sell_count",
		kind = "event",
		eventType = "body_part_sold",
		countField = "amount",
		description = string.format("Sell %d body parts.", targetValue),
		targetValue = targetValue,
	})
end

local function appendAppraiseCountDailyQuest(definitions: { QuestDefinition }, targetValue: number)
	appendDailyQuest(definitions, string.format("daily_appraise_%d_body_parts", targetValue), string.format("Appraise %d Body Parts", targetValue), string.format(
		"Appraise %d body parts.",
		targetValue
	), {
		id = "appraise_count",
		kind = "event",
		eventType = "body_part_appraised",
		description = string.format("Appraise %d body parts.", targetValue),
		targetValue = targetValue,
	})
end

local function appendDailyQuestDefinitions(definitions: { QuestDefinition })
	for _, targetValue in ipairs({ 5, 10, 15, 20, 25 }) do
		appendRollCountDailyQuest(definitions, targetValue)
	end
	for _, region in ipairs(BODY_REGIONS) do
		appendRollRegionDailyQuest(definitions, region)
	end
	appendRollRarityDailyQuest(definitions, "5_basic", "Basic", 5, "Basic")
	appendRollRarityDailyQuest(definitions, "3_clean_plus", "Clean+", 3, CLEAN_PLUS_FILTER)
	appendRollRarityDailyQuest(definitions, "1_prime_plus", "Prime+", 1, PRIME_PLUS_FILTER)
	for _, targetValue in ipairs({ 1, 3, 5 }) do
		appendEquipCountDailyQuest(definitions, targetValue)
	end
	for _, region in ipairs(BODY_REGIONS) do
		appendEquipRegionDailyQuest(definitions, region)
	end
	for _, targetValue in ipairs({ 3, 5, 10, 15 }) do
		appendSellCountDailyQuest(definitions, targetValue)
	end
	for _, targetValue in ipairs({ 1, 2, 3 }) do
		appendAppraiseCountDailyQuest(definitions, targetValue)
	end
end

local DEFINITIONS: { QuestDefinition } = {
	{
		id = "stan_paid_roll_intro",
		displayName = "Rolling Lesson",
		description = "Learn how stronger rolls lead to stronger body parts.",
		kind = "main",
		providerIds = { "quest_board" },
		boardVisible = true,
		abandonable = false,
		parts = {
			{
				id = "paid_roll",
				description = "Use a paid roll to try for a stronger result.",
				objectives = {
					{
						id = "use_paid_roll",
						kind = "state",
						stateType = "paid_roll_count",
						description = "Use a paid roll",
						targetValue = 1,
						retroactive = true,
					},
				},
			},
			{
				id = "roll_clean_plus",
				description = "Roll a Clean or better body part.",
				objectives = {
					{
						id = "roll_clean_plus",
						kind = "state",
						stateType = "clean_plus_roll_count",
						description = "Roll a Clean+ body part",
						targetValue = 1,
						retroactive = true,
					},
				},
			},
			{
				id = "equip_clean_plus",
				description = "Equip a Clean or better body part so your build can start scaling.",
				objectives = {
					{
						id = "equip_clean_plus",
						kind = "state",
						stateType = "equipped_clean_plus_body_part_count",
						description = "Equip a Clean+ body part",
						targetValue = 1,
						retroactive = true,
					},
				},
			},
		},
		rewards = {
			dailyChests = {
				{
					chestId = "DailyFree",
					amount = 1,
				},
			},
		},
	},
	{
		id = "stan_man_aura_intro",
		displayName = "Man Aura Lesson",
		description = "Complete the Man set and equip its aura.",
		kind = "main",
		providerIds = { "quest_board" },
		boardVisible = true,
		abandonable = false,
		parts = {
			{
				id = "complete_man_set",
				description = "Roll more times to complete the Man set.",
				objectives = {
					{
						id = "complete_man_set",
						kind = "state",
						stateType = "set_discovered_piece_count",
						description = "Complete the Man set.",
						targetValue = 6,
						filters = {
							setId = "man",
						},
						retroactive = true,
					},
				},
			},
			{
				id = "equip_man_aura",
				description = "You completed the Man set and unlocked the Man aura. Equip it from your inventory.",
				objectives = {
					{
						id = "equip_man_aura",
						kind = "state",
						stateType = "equipped_aura_id",
						description = "Equip the Man aura.",
						targetValue = 1,
						filters = {
							auraId = "man",
						},
						retroactive = true,
					},
				},
			},
		},
		rewards = {
			dailyChests = {
				{
					chestId = "DailyFree",
					amount = 1,
				},
			},
		},
	},
	{
		id = "stan_appraisal_intro",
		displayName = "Appraisal Tour",
		description = "Learn how appraisal can make a good body part even better.",
		kind = "main",
		providerIds = { "quest_board" },
		boardVisible = true,
		abandonable = false,
		parts = {
			{
				id = "talk_to_appraiser",
				description = "Find the Appraiser and say hello.",
				objectives = {
					{
						id = "talk_to_appraiser",
						kind = "event",
						eventType = "dialogue_prompt_triggered",
						description = "Talk to the Appraiser",
						targetValue = 1,
						filters = {
							dialogueId = "appraiser_default",
						},
					},
				},
			},
			{
				id = "appraise_body_part",
				description = "Appraise one equipped body part to see how it changes.",
				objectives = {
					{
						id = "appraise_body_part",
						kind = "state",
						stateType = "appraisal_count",
						description = "Appraise your first body part",
						targetValue = 1,
						retroactive = true,
					},
				},
			},
		},
		rewards = {
			dailyChests = {
				{
					chestId = "DailyFree",
					amount = 1,
				},
			},
		},
	},
	{
		id = "stan_crafting_intro",
		displayName = "Crafting Tour",
		description = "Learn how crafting turns extra parts into bigger goals.",
		kind = "main",
		providerIds = { "quest_board" },
		boardVisible = true,
		abandonable = false,
		parts = {
			{
				id = "talk_to_crafter",
				description = "Find the Crafter and say hello.",
				objectives = {
					{
						id = "talk_to_crafter",
						kind = "event",
						eventType = "crafting_menu_opened",
						description = "Talk to the Crafter",
						targetValue = 1,
					},
				},
			},
			{
				id = "open_crown_recipe",
				description = "Open the Holiday Crown recipe to see what parts it needs.",
				objectives = {
					{
						id = "open_crown_recipe",
						kind = "event",
						eventType = "crafting_recipe_opened",
						description = "Open the Crown recipe",
						targetValue = 1,
						filters = {
							recipeId = "holiday_crown",
						},
					},
				},
			},
			{
				id = "craft_crown",
				description = "Craft the Holiday Crown to finish the lesson.",
				objectives = {
					{
						id = "craft_crown",
						kind = "event",
						eventType = "crafting_completed",
						description = "Craft the Crown",
						targetValue = 1,
						filters = {
							recipeId = "holiday_crown",
						},
					},
				},
			},
		},
		rewards = {
			dailyChests = {
				{
					chestId = "DailyFree",
					amount = 1,
				},
			},
		},
	},
	{
		id = "stan_boss_intro",
		displayName = "Boss World Tour",
		description = "Learn where the boss world starts and how boss rewards work.",
		kind = "main",
		providerIds = { "quest_board" },
		boardVisible = true,
		abandonable = false,
		parts = {
			{
				id = "go_to_boss_world",
				description = "Use the boss portal to enter the boss world.",
				objectives = {
					{
						id = "go_to_boss_world",
						kind = "event",
						eventType = "boss_world_entered",
						description = "Go to the boss world",
						targetValue = 1,
						filters = {
							bossId = "Flame Guard General",
							portalId = "boss_world_tutorial",
							sourceFlow = "boss_world_tutorial",
						},
					},
				},
			},
			{
				id = "defeat_first_boss",
				description = "Defeat your first boss to see how boss rewards work.",
				objectives = {
					{
						id = "defeat_first_boss",
						kind = "event",
						eventType = "boss_victory",
						description = "Defeat your first boss",
						targetValue = 1,
						filters = {
							bossId = "Flame Guard General",
							portalId = "boss_world_tutorial",
							sourceFlow = "boss_world_tutorial",
						},
					},
				},
			},
			{
				id = "craft_first_gear",
				description = "Craft Bombo's Survival Knife.",
				objectives = {
					{
						id = "craft_first_gear",
						kind = "event",
						eventType = "crafting_completed",
						description = "Craft Bombo's Survival Knife.",
						targetValue = 1,
						filters = {
							recipeId = "bombos_survival_knife",
						},
					},
				},
			},
		},
		rewards = {
			dailyChests = {
				{
					chestId = "DailyFree",
					amount = 1,
				},
			},
		},
	},
}

appendDailyQuestDefinitions(DEFINITIONS)

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

function QuestConfig.GetParts(definition: QuestDefinition): { QuestPart }
	if typeof(definition.parts) == "table" and #definition.parts > 0 then
		return definition.parts
	end

	return {
		{
			id = "part_1",
			description = definition.description,
			objectives = definition.objectives or {},
		},
	}
end

function QuestConfig.GetPartCount(definition: QuestDefinition): number
	return math.max(1, #QuestConfig.GetParts(definition))
end

function QuestConfig.GetPart(definition: QuestDefinition, partIndex: number): QuestPart
	local parts = QuestConfig.GetParts(definition)
	local index = math.clamp(math.floor(tonumber(partIndex) or 1), 1, #parts)
	return parts[index]
end

function QuestConfig.GetPartObjectives(definition: QuestDefinition, partIndex: number): { QuestObjective }
	local part = QuestConfig.GetPart(definition, partIndex)
	if typeof(part.objectives) == "table" then
		return part.objectives
	end

	return {}
end

function QuestConfig.GetPartDescription(definition: QuestDefinition, partIndex: number): string
	local part = QuestConfig.GetPart(definition, partIndex)
	if typeof(part.description) == "string" and part.description ~= "" then
		return part.description
	end

	return definition.description
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

	return definition.kind == "side" or definition.kind == "repeatable"
end

function QuestConfig.GetCompletionMode(definition: QuestDefinition): CompletionMode
	return if definition.completionMode == "autoClaim" then "autoClaim" else "turnIn"
end

return table.freeze(QuestConfig)
