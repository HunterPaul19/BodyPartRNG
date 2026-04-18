local RollingConfig = require(script.Parent.Parent.Config.RollingConfig)

local RollCutsceneConfig = {
	DefaultDuration = 5,
	TierByRarity = {
		Basic = 1,
		Clean = 2,
		Prime = 3,
		Elite = 4,
		Apex = 5,
	},
	AlwaysPlaySetIds = {
		["67_brainrot"] = true,
		absolute_unit = true,
		bastion_mech_robot_recolorable = true,
		cat_mech = true,
		celestial_titan = true,
		deer_monster_99_nights_in_the_forest = true,
		handsome_squidward = true,
		mahoraga = true,
		the_rulk_custom_colour = true,
	},
}

function RollCutsceneConfig.NormalizeDisplayRarity(value: any): string
	return RollingConfig.NormalizeDisplayRarity(value)
end

function RollCutsceneConfig.ResolveTier(value: any): number
	local normalizedRarity = RollCutsceneConfig.NormalizeDisplayRarity(value)
	return RollCutsceneConfig.TierByRarity[normalizedRarity] or 1
end

function RollCutsceneConfig.IsEligibleRarity(value: any): boolean
	return RollCutsceneConfig.ResolveTier(value) >= RollCutsceneConfig.TierByRarity.Clean
end

function RollCutsceneConfig.IsAlwaysPlaySetId(setId: any): boolean
	return typeof(setId) == "string" and RollCutsceneConfig.AlwaysPlaySetIds[setId] == true
end

function RollCutsceneConfig.ShouldPlayForSet(rarityValue: any, setId: any, hasSeenCutscene: boolean?): boolean
	if not RollCutsceneConfig.IsEligibleRarity(rarityValue) then
		return false
	end

	if RollCutsceneConfig.IsAlwaysPlaySetId(setId) then
		return true
	end

	return hasSeenCutscene ~= true
end

return table.freeze(RollCutsceneConfig)
