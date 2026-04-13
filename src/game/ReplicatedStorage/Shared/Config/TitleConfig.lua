export type TitleConfigEntry = {
	id: string,
	label: string,
	description: string,
	howToGet: string,
	displayColor: Color3,
	achievementId: string,
	sortOrder: number,
}

local rawOrdered: { TitleConfigEntry } = {
	{
		id = "warm_up_winner",
		label = "Warm-Up Winner",
		description = "You found your footing and started the chase.",
		howToGet = "Earn 10 successful rolls after the title system launch.",
		displayColor = Color3.fromRGB(255, 255, 255),
		achievementId = "warm_up_winner",
		sortOrder = 1,
	},
	{
		id = "part_hunter",
		label = "Part Hunter",
		description = "You keep rolling long after the easy wins.",
		howToGet = "Earn 100 successful rolls after the title system launch.",
		displayColor = Color3.fromRGB(136, 219, 255),
		achievementId = "part_hunter",
		sortOrder = 2,
	},
	{
		id = "rng_engine",
		label = "RNG Engine",
		description = "The roll button is part of your routine now.",
		howToGet = "Earn 500 successful rolls after the title system launch.",
		displayColor = Color3.fromRGB(118, 255, 193),
		achievementId = "rng_engine",
		sortOrder = 3,
	},
	{
		id = "assembly_line",
		label = "Assembly Line",
		description = "You turn luck into throughput.",
		howToGet = "Earn 2,500 successful rolls after the title system launch.",
		displayColor = Color3.fromRGB(255, 223, 111),
		achievementId = "assembly_line",
		sortOrder = 4,
	},
	{
		id = "pocket_upgrade",
		label = "Pocket Upgrade",
		description = "Your wallet finally feels useful.",
		howToGet = "Reach 2,500 current money on an upward crossing after the title system launch.",
		displayColor = Color3.fromRGB(169, 255, 126),
		achievementId = "pocket_upgrade",
		sortOrder = 5,
	},
	{
		id = "well_funded",
		label = "Well Funded",
		description = "You can bankroll real progression now.",
		howToGet = "Reach 75,000 current money on an upward crossing after the title system launch.",
		displayColor = Color3.fromRGB(79, 255, 160),
		achievementId = "well_funded",
		sortOrder = 6,
	},
	{
		id = "vault_keeper",
		label = "Vault Keeper",
		description = "Late-game buying power sits in your pocket.",
		howToGet = "Reach 2,500,000 current money on an upward crossing after the title system launch.",
		displayColor = Color3.fromRGB(255, 190, 71),
		achievementId = "vault_keeper",
		sortOrder = 7,
	},
	{
		id = "clocked_in",
		label = "Clocked In",
		description = "The grind officially started.",
		howToGet = "Spend 30 minutes in-game after the title system launch.",
		displayColor = Color3.fromRGB(153, 198, 255),
		achievementId = "clocked_in",
		sortOrder = 8,
	},
	{
		id = "still_rolling",
		label = "Still Rolling",
		description = "You can settle into the long session.",
		howToGet = "Spend 2 hours in-game after the title system launch.",
		displayColor = Color3.fromRGB(193, 160, 255),
		achievementId = "still_rolling",
		sortOrder = 9,
	},
	{
		id = "iron_session",
		label = "Iron Session",
		description = "You are built for marathon farming.",
		howToGet = "Spend 10 hours in-game after the title system launch.",
		displayColor = Color3.fromRGB(255, 115, 115),
		achievementId = "iron_session",
		sortOrder = 10,
	},
	{
		id = "patch_collector",
		label = "Patch Collector",
		description = "New pieces keep landing in the scrapbook.",
		howToGet = "Discover 10 new body-part pieces after the title system launch.",
		displayColor = Color3.fromRGB(130, 236, 255),
		achievementId = "patch_collector",
		sortOrder = 11,
	},
	{
		id = "body_archivist",
		label = "Body Archivist",
		description = "Your collection is becoming a real library.",
		howToGet = "Discover 30 new body-part pieces after the title system launch.",
		displayColor = Color3.fromRGB(105, 165, 255),
		achievementId = "body_archivist",
		sortOrder = 12,
	},
	{
		id = "full_build",
		label = "Full Build",
		description = "Your first fresh full set comes together.",
		howToGet = "Complete 1 new full set after the title system launch.",
		displayColor = Color3.fromRGB(255, 147, 219),
		achievementId = "full_build",
		sortOrder = 13,
	},
	{
		id = "set_sovereign",
		label = "Set Sovereign",
		description = "Multiple fresh set completions prove real collector status.",
		howToGet = "Complete 5 new full sets after the title system launch.",
		displayColor = Color3.fromRGB(255, 91, 171),
		achievementId = "set_sovereign",
		sortOrder = 14,
	},
}

table.sort(rawOrdered, function(a, b)
	if a.sortOrder ~= b.sortOrder then
		return a.sortOrder < b.sortOrder
	end

	return a.id < b.id
end)

local byId: { [string]: TitleConfigEntry } = {}
local byAchievementId: { [string]: TitleConfigEntry } = {}

for _, entry in ipairs(rawOrdered) do
	local frozen = table.freeze(table.clone(entry))
	byId[entry.id] = frozen
	byAchievementId[entry.achievementId] = frozen
end

local frozenOrdered = table.create(#rawOrdered)
for index, entry in ipairs(rawOrdered) do
	frozenOrdered[index] = byId[entry.id]
end

table.freeze(byId)
table.freeze(byAchievementId)
table.freeze(frozenOrdered)

local TitleConfig = {}

function TitleConfig.Get(id: string): TitleConfigEntry?
	return byId[id]
end

function TitleConfig.GetOrdered(): { TitleConfigEntry }
	return frozenOrdered
end

function TitleConfig.GetByAchievementId(achievementId: string): TitleConfigEntry?
	return byAchievementId[achievementId]
end

return table.freeze(TitleConfig)
