local OwnedBodyParts = require(script.Parent.Parent.Shared.Character.OwnedBodyParts)
local OwnedAuras = require(script.Parent.Parent.Shared.Character.OwnedAuras)
local OwnedPotions = require(script.Parent.Parent.Shared.Character.OwnedPotions)
local MerchantShopState = require(script.Parent.Parent.Shared.Character.MerchantShopState)
local MarketplaceState = require(script.Parent.Parent.Shared.Marketplace.State)
local BodyPartLoadout = require(script.Parent.Parent.Shared.Character.BodyPartLoadout)
local RollTargetRegions = require(script.Parent.Parent.Shared.Character.RollTargetRegions)
local RollSelection = require(script.Parent.Parent.Shared.Character.OwnedRollTypes)
local RollingConfig = require(script.Parent.Parent.Shared.Config.RollingConfig)
local AchievementState = require(script.Parent.Parent.Shared.Titles.AchievementState)
local PlayerStats = require(script.Parent.Parent.Shared.Stats.PlayerStats)

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

	Stats = {
		key = "stats",
		value = PlayerStats.CreateEmpty(),
	},

	BodyParts = {
		key = "bodyParts",
		value = OwnedBodyParts.CreateEmptyState(),
	},

	Auras = {
		key = "auras",
		value = OwnedAuras.CreateEmptyState(),
	},

	Potions = {
		key = "potions",
		value = OwnedPotions.CreateEmptyState(),
	},

	MerchantShop = {
		key = "merchantShop",
		value = MerchantShopState.CreateEmptyState(),
	},

	Marketplace = {
		key = "marketplace",
		value = MarketplaceState.CreateEmpty(),
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

	EquippedAuraId = {
		key = "equippedAuraId",
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

	VipPlusOwned = {
		key = "vipPlusOwned",
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

	AutoSizeEnabled = {
		key = "autoSizeEnabled",
		value = false,
	},

	AutoSellRarities = {
		key = "autoSellRarities",
		value = RollingConfig.CreateDefaultAutoSellState(),
	},
}
