local RollingConfig = {
	BonusInterval = 10,
	BonusMultiplier = 2,
	VipMultiplier = 1.25,
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

function RollingConfig.NormalizeDisplayRarity(value: any): string
	if typeof(value) ~= "string" then
		return "Basic"
	end

	return RollingConfig.DisplayRarityAliases[value] or "Basic"
end

function RollingConfig.GetRarityEffectiveness(displayRarity: any): number
	local normalized = RollingConfig.NormalizeDisplayRarity(displayRarity)
	return RollingConfig.RarityEffectiveness[normalized] or RollingConfig.RarityEffectiveness.Basic
end

return table.freeze(RollingConfig)
