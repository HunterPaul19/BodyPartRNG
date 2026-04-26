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
		description = "Your run is off to a strong start.",
		howToGet = "Reach 10 rolls.",
		displayColor = Color3.fromRGB(255, 255, 255),
		achievementId = "warm_up_winner",
		sortOrder = 1,
	},
	{
		id = "part_hunter",
		label = "Part Hunter",
		description = "You know how to keep the hunt going.",
		howToGet = "Reach 100 rolls.",
		displayColor = Color3.fromRGB(136, 219, 255),
		achievementId = "part_hunter",
		sortOrder = 2,
	},
	{
		id = "rng_engine",
		label = "RNG Engine",
		description = "Rolling has become part of your rhythm.",
		howToGet = "Reach 500 rolls.",
		displayColor = Color3.fromRGB(118, 255, 193),
		achievementId = "rng_engine",
		sortOrder = 3,
	},
	{
		id = "assembly_line",
		label = "Assembly Line",
		description = "You turn every session into steady progress.",
		howToGet = "Reach 2,500 rolls.",
		displayColor = Color3.fromRGB(255, 223, 111),
		achievementId = "assembly_line",
		sortOrder = 4,
	},
	{
		id = "pocket_upgrade",
		label = "Pocket Upgrade",
		description = "Your earnings are starting to matter.",
		howToGet = "Reach 2,500 money.",
		displayColor = Color3.fromRGB(169, 255, 126),
		achievementId = "pocket_upgrade",
		sortOrder = 5,
	},
	{
		id = "well_funded",
		label = "Well Funded",
		description = "You have the cash to push your build further.",
		howToGet = "Reach 75,000 money.",
		displayColor = Color3.fromRGB(79, 255, 160),
		achievementId = "well_funded",
		sortOrder = 6,
	},
	{
		id = "vault_keeper",
		label = "Vault Keeper",
		description = "Your stack is big enough to change the game.",
		howToGet = "Reach 2,500,000 money.",
		displayColor = Color3.fromRGB(255, 190, 71),
		achievementId = "vault_keeper",
		sortOrder = 7,
	},
	{
		id = "clocked_in",
		label = "Clocked In",
		description = "You are settling into the grind.",
		howToGet = "Play for 30 minutes.",
		displayColor = Color3.fromRGB(153, 198, 255),
		achievementId = "clocked_in",
		sortOrder = 8,
	},
	{
		id = "still_rolling",
		label = "Still Rolling",
		description = "Long sessions are starting to pay off.",
		howToGet = "Play for 2 hours.",
		displayColor = Color3.fromRGB(193, 160, 255),
		achievementId = "still_rolling",
		sortOrder = 9,
	},
	{
		id = "iron_session",
		label = "Iron Session",
		description = "You can outlast the grind and keep climbing.",
		howToGet = "Play for 10 hours.",
		displayColor = Color3.fromRGB(255, 115, 115),
		achievementId = "iron_session",
		sortOrder = 10,
	},
	{
		id = "patch_collector",
		label = "Patch Collector",
		description = "Your collection is starting to take shape.",
		howToGet = "Discover 10 body parts.",
		displayColor = Color3.fromRGB(130, 236, 255),
		achievementId = "patch_collector",
		sortOrder = 11,
	},
	{
		id = "body_archivist",
		label = "Body Archivist",
		description = "Your collection is deep enough to stand out.",
		howToGet = "Discover 30 body parts.",
		displayColor = Color3.fromRGB(105, 165, 255),
		achievementId = "body_archivist",
		sortOrder = 12,
	},
	{
		id = "full_build",
		label = "Full Build",
		description = "You pulled together a full set worth showing off.",
		howToGet = "Complete 1 full set.",
		displayColor = Color3.fromRGB(255, 147, 219),
		achievementId = "full_build",
		sortOrder = 13,
	},
	{
		id = "set_sovereign",
		label = "Set Sovereign",
		description = "Your set collection shows real collector status.",
		howToGet = "Complete 5 full sets.",
		displayColor = Color3.fromRGB(255, 91, 171),
		achievementId = "set_sovereign",
		sortOrder = 14,
	},
	{
		id = "met_developer",
		label = "You Met a Developer",
		description = "You crossed paths with someone building Body Part RNG.",
		howToGet = "Be in a server with a developer.",
		displayColor = Color3.fromRGB(255, 82, 82),
		achievementId = "met_developer",
		sortOrder = 15,
	},
	{
		id = "launch_week_player",
		label = "You Played Within a Week of Release",
		description = "You were here when the hunt first began.",
		howToGet = "Play during the first week of release.",
		displayColor = Color3.fromRGB(255, 214, 76),
		achievementId = "launch_week_player",
		sortOrder = 16,
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
