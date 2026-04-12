local OwnedBodyParts = require(script.Parent.Parent.Shared.Character.OwnedBodyParts)
local RollTargetRegions = require(script.Parent.Parent.Shared.Character.RollTargetRegions)
local RollSelection = require(script.Parent.Parent.Shared.Character.OwnedRollTypes)

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

	SuccessfulRollCount = {
		key = "successfulRollCount",
		value = 0,
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
}
