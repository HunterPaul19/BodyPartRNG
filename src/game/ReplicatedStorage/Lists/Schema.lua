local OwnedBodyParts = require(script.Parent.Parent.Shared.Character.OwnedBodyParts)
local BodyPartLoadout = require(script.Parent.Parent.Shared.Character.BodyPartLoadout)
local RollTargetRegions = require(script.Parent.Parent.Shared.Character.RollTargetRegions)
local RollSelection = require(script.Parent.Parent.Shared.Character.OwnedRollTypes)
local RollingConfig = require(script.Parent.Parent.Shared.Config.RollingConfig)
local AchievementState = require(script.Parent.Parent.Shared.Titles.AchievementState)

return {
	Money = {
		key = "money",
		value = 200,
	},

	TimePlayed = {
		key = "timePlayed",
		value = 0,
	},

	Diagnostics = {
		key = "diagnostics",
		value = {},
	},

	BodyParts = {
		key = "bodyParts",
		value = OwnedBodyParts.CreateEmptyState(),
	},

	EquippedLoadout = {
		key = "equippedLoadout",
		value = BodyPartLoadout.CreateEmptyEquippedState(),
	},

	SuccessfulRollCount = {
		key = "successfulRollCount",
		value = 0,
	},

	EquippedTitleId = {
		key = "equippedTitleId",
		value = "",
	},

	Achievements = {
		key = "achievements",
		value = AchievementState.CreateEmptyState(),
	},

	VipOwned = {
		key = "vipOwned",
		value = false,
	},

	SelectedRollType = {
		key = "selectedRollType",
		value = RollSelection.GetDefaultSelectedRollTypeId(),
	},

	SelectedRollRegion = {
		key = "selectedRollRegion",
		value = RollTargetRegions.Default,
	},

	QuickRollEnabled = {
		key = "quickRollEnabled",
		value = false,
	},

	AutoSellRarities = {
		key = "autoSellRarities",
		value = RollingConfig.CreateDefaultAutoSellState(),
	},
}
