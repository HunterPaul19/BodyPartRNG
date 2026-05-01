local OwnedBodyParts = require(script.Parent.Parent.Shared.Character.OwnedBodyParts)
local OwnedAccessories = require(script.Parent.Parent.Shared.Character.OwnedAccessories)
local OwnedAuras = require(script.Parent.Parent.Shared.Character.OwnedAuras)
local OwnedCraftingMaterials = require(script.Parent.Parent.Shared.Character.OwnedCraftingMaterials)
local CraftingProgress = require(script.Parent.Parent.Shared.Character.CraftingProgress)
local OwnedPotions = require(script.Parent.Parent.Shared.Character.OwnedPotions)
local MerchantShopState = require(script.Parent.Parent.Shared.Character.MerchantShopState)
local MarketplaceState = require(script.Parent.Parent.Shared.Marketplace.State)
local BodyPartLoadout = require(script.Parent.Parent.Shared.Character.BodyPartLoadout)
local RollTargetRegions = require(script.Parent.Parent.Shared.Character.RollTargetRegions)
local RollSelection = require(script.Parent.Parent.Shared.Character.OwnedRollTypes)
local TimeShardState = require(script.Parent.Parent.Shared.Character.TimeShardState)
local DailyChestState = require(script.Parent.Parent.Shared.Character.DailyChestState)
local TutorialState = require(script.Parent.Parent.Shared.Character.TutorialState)
local BossWorldGuideState = require(script.Parent.Parent.Shared.Character.BossWorldGuideState)
local QuestState = require(script.Parent.Parent.Shared.Character.QuestState)
local RollingConfig = require(script.Parent.Parent.Shared.Config.RollingConfig)
local AchievementState = require(script.Parent.Parent.Shared.Titles.AchievementState)
local PlayerStats = require(script.Parent.Parent.Shared.Stats.PlayerStats)

return {
	Money = {
		key = "money",
		value = 1000,
	},

	TimePlayed = {
		key = "timePlayed",
		value = 0,
	},

	TimeShards = {
		key = "timeShards",
		value = TimeShardState.CreateEmptyState(),
	},

	DailyChests = {
		key = "dailyChests",
		value = DailyChestState.CreateEmptyState(),
	},

	Tutorial = {
		key = "tutorial",
		value = TutorialState.CreateEmptyState(),
	},

	BossWorldGuide = {
		key = "bossWorldGuide",
		value = BossWorldGuideState.CreateEmptyState(),
	},

	Quests = {
		key = "quests",
		value = QuestState.CreateEmptyState(),
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

	Accessories = {
		key = "accessories",
		value = OwnedAccessories.CreateEmptyState(),
	},

	EquippedAccessories = {
		key = "equippedAccessories",
		value = OwnedAccessories.CreateEmptyEquippedState(),
	},

	CraftingMaterials = {
		key = "craftingMaterials",
		value = OwnedCraftingMaterials.CreateEmptyState(),
	},

	CraftingProgress = {
		key = "craftingProgress",
		value = CraftingProgress.CreateEmptyState(),
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

	AutoEquipBestEnabled = {
		key = "autoEquipBestEnabled",
		value = false,
	},

	AutoSizeEnabled = {
		key = "autoSizeEnabled",
		value = false,
	},

	MusicEnabled = {
		key = "musicEnabled",
		value = true,
	},

	AutoSellRarities = {
		key = "autoSellRarities",
		value = RollingConfig.CreateDefaultAutoSellState(),
	},

	CutsceneRarities = {
		key = "cutsceneRarities",
		value = RollingConfig.CreateDefaultCutsceneState(),
	},
}
