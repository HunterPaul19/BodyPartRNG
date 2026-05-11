local RollingConfig = require(script.Parent.RollingConfig)

export type BadgeConfigEntry = {
	key: string,
	badgeId: number,
	displayRarity: string?,
}

local rawOrdered: { BadgeConfigEntry } = {
	{
		key = "played_game",
		badgeId = 875246158934891,
	},
	{
		key = "obtained_basic_rarity_item",
		badgeId = 1250978235750975,
		displayRarity = "Basic",
	},
	{
		key = "obtained_clean_rarity_item",
		badgeId = 2822948900359357,
		displayRarity = "Clean",
	},
	{
		key = "obtained_prime_rarity_item",
		badgeId = 799694308006392,
		displayRarity = "Prime",
	},
	{
		key = "obtained_elite_rarity_item",
		badgeId = 4454156418968971,
		displayRarity = "Elite",
	},
	{
		key = "obtained_apex_rarity_item",
		badgeId = 4001998890002608,
		displayRarity = "Apex",
	},
}

local byKey: { [string]: BadgeConfigEntry } = {}
local byDisplayRarity: { [string]: BadgeConfigEntry } = {}
local ordered = table.create(#rawOrdered)

for _, rawEntry in ipairs(rawOrdered) do
	local entry: BadgeConfigEntry = table.freeze(table.clone(rawEntry))
	byKey[entry.key] = entry
	table.insert(ordered, entry)

	if typeof(entry.displayRarity) == "string" and entry.displayRarity ~= "" then
		byDisplayRarity[RollingConfig.NormalizeDisplayRarity(entry.displayRarity)] = entry
	end
end

table.freeze(byKey)
table.freeze(byDisplayRarity)
table.freeze(ordered)

local BadgeConfig = {}

function BadgeConfig.Get(key: string): BadgeConfigEntry?
	return byKey[key]
end

function BadgeConfig.GetPlayedGame(): BadgeConfigEntry?
	return byKey.played_game
end

function BadgeConfig.GetForDisplayRarity(displayRarity: any): BadgeConfigEntry?
	local normalizedDisplayRarity = RollingConfig.ResolveDisplayRarity(displayRarity)
	if normalizedDisplayRarity == nil then
		return nil
	end

	return byDisplayRarity[normalizedDisplayRarity]
end

function BadgeConfig.GetOrdered(): { BadgeConfigEntry }
	return ordered
end

return table.freeze(BadgeConfig)
