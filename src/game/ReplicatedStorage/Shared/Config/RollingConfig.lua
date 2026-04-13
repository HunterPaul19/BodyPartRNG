local RollingConfig = {
	BonusInterval = 10,
	BonusMultiplier = 2,
	VipMultiplier = 1.25,
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
		Elite = "Apex",
		Apex = "Apex",
	},
	RarityEffectiveness = {
		Basic = 1.0,
		Clean = 0.70,
		Prime = 0.40,
		Elite = 0.15,
		Apex = 0.05,
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

function RollingConfig.GetRarityEffectiveness(displayRarity: any): number
	local normalized = RollingConfig.NormalizeDisplayRarity(displayRarity)
	return RollingConfig.RarityEffectiveness[normalized] or RollingConfig.RarityEffectiveness.Basic
end

return table.freeze(RollingConfig)
