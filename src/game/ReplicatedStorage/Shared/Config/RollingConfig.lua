local RollingConfig = {
	BonusInterval = 10,
	BonusMultiplier = 2,
	VipMultiplier = 1.25,
	PreviewTeasersEnabled = true,
	PreviewTeaserChancePerSlot = 0.25,
	PreviewTeaserMultipliers = {
		{
			multiplier = 25,
			weight = 70,
		},
		{
			multiplier = 50,
			weight = 25,
		},
		{
			multiplier = 100,
			weight = 5,
		},
	},
	DisplayRarityOrder = {
		"Basic",
		"Clean",
		"Prime",
		"Elite",
		"Apex",
	},
	DisplayRarityAliases = {
		Basic = "Basic",
		Common = "Basic",
		Uncommon = "Clean",
		Clean = "Clean",
		Rare = "Prime",
		Epic = "Prime",
		Prime = "Prime",
		Legendary = "Elite",
		Elite = "Elite",
		Apex = "Apex",
	},
}

RollingConfig.DisplayRaritySet = {}
for _, rarity in ipairs(RollingConfig.DisplayRarityOrder) do
	RollingConfig.DisplayRaritySet[rarity] = true
end

function RollingConfig.NormalizeDisplayRarity(value: any): string
	if typeof(value) ~= "string" then
		return "Basic"
	end

	return RollingConfig.DisplayRarityAliases[value] or "Basic"
end

function RollingConfig.ResolveDisplayRarity(value: any): string?
	if typeof(value) ~= "string" then
		return nil
	end

	return RollingConfig.DisplayRarityAliases[value]
end

function RollingConfig.IsValidDisplayRarity(value: any): boolean
	return typeof(value) == "string" and RollingConfig.DisplayRaritySet[value] == true
end

function RollingConfig.CreateDefaultAutoSellState(): { [string]: boolean }
	local state = {}

	for _, rarity in ipairs(RollingConfig.DisplayRarityOrder) do
		state[rarity] = false
	end

	return state
end

function RollingConfig.NormalizeAutoSellState(value: any): { [string]: boolean }
	local normalizedState = RollingConfig.CreateDefaultAutoSellState()

	if typeof(value) ~= "table" then
		return normalizedState
	end

	for _, rarity in ipairs(RollingConfig.DisplayRarityOrder) do
		normalizedState[rarity] = value[rarity] == true
	end

	return normalizedState
end

return table.freeze(RollingConfig)
