export type AchievementTriggerType =
	"successful_rolls"
	| "current_money"
	| "play_time_seconds"
	| "new_discovered_pieces"
	| "new_completed_sets"

export type AchievementConfigEntry = {
	id: string,
	titleId: string,
	triggerType: AchievementTriggerType,
	targetValue: number,
	timeUnit: string?,
}

local rawOrdered: { AchievementConfigEntry } = {
	{
		id = "warm_up_winner",
		titleId = "warm_up_winner",
		triggerType = "successful_rolls",
		targetValue = 10,
	},
	{
		id = "part_hunter",
		titleId = "part_hunter",
		triggerType = "successful_rolls",
		targetValue = 100,
	},
	{
		id = "rng_engine",
		titleId = "rng_engine",
		triggerType = "successful_rolls",
		targetValue = 500,
	},
	{
		id = "assembly_line",
		titleId = "assembly_line",
		triggerType = "successful_rolls",
		targetValue = 2500,
	},
	{
		id = "pocket_upgrade",
		titleId = "pocket_upgrade",
		triggerType = "current_money",
		targetValue = 2500,
	},
	{
		id = "well_funded",
		titleId = "well_funded",
		triggerType = "current_money",
		targetValue = 75000,
	},
	{
		id = "vault_keeper",
		titleId = "vault_keeper",
		triggerType = "current_money",
		targetValue = 2500000,
	},
	{
		id = "clocked_in",
		titleId = "clocked_in",
		triggerType = "play_time_seconds",
		targetValue = 30 * 60,
		timeUnit = "seconds",
	},
	{
		id = "still_rolling",
		titleId = "still_rolling",
		triggerType = "play_time_seconds",
		targetValue = 2 * 60 * 60,
		timeUnit = "seconds",
	},
	{
		id = "iron_session",
		titleId = "iron_session",
		triggerType = "play_time_seconds",
		targetValue = 10 * 60 * 60,
		timeUnit = "seconds",
	},
	{
		id = "patch_collector",
		titleId = "patch_collector",
		triggerType = "new_discovered_pieces",
		targetValue = 10,
	},
	{
		id = "body_archivist",
		titleId = "body_archivist",
		triggerType = "new_discovered_pieces",
		targetValue = 30,
	},
	{
		id = "full_build",
		titleId = "full_build",
		triggerType = "new_completed_sets",
		targetValue = 1,
	},
	{
		id = "set_sovereign",
		titleId = "set_sovereign",
		triggerType = "new_completed_sets",
		targetValue = 5,
	},
}

local byId: { [string]: AchievementConfigEntry } = {}
local ordered = table.clone(rawOrdered)

for _, entry in ipairs(ordered) do
	byId[entry.id] = table.freeze(table.clone(entry))
end

local frozenOrdered = table.create(#ordered)
for index, entry in ipairs(ordered) do
	frozenOrdered[index] = byId[entry.id]
end

table.freeze(byId)
table.freeze(frozenOrdered)

local AchievementConfig = {}

function AchievementConfig.Get(id: string): AchievementConfigEntry?
	return byId[id]
end

function AchievementConfig.GetOrdered(): { AchievementConfigEntry }
	return frozenOrdered
end

return table.freeze(AchievementConfig)
