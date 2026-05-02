local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local RunService = game:GetService("RunService")

local PreloadProfiles = require(script.Parent.PreloadProfiles)
local RouteConfig = require(script.Parent.RouteConfig)

local ALL_SERVICE_NAMES = {
	"AchievementService",
	"AdminService",
	"AppraisalService",
	"AudioSettingsService",
	"AuraService",
	"BodyPartService",
	"BossWorldGuideService",
	"ChatNotificationService",
	"ChatTagService",
	"CombatPhysicsBootstrapService",
	"CraftingService",
	"DailyChestService",
	"DataService",
	"DayNightCycleService",
	"DashService",
	"DiagnosticsService",
	"DialogueActionService",
	"MarketplaceHandlers",
	"MerchantShopService",
	"OfflineEarningsService",
	"PassiveIncomeService",
	"PlayerLoadoutStatsService",
	"PotionService",
	"PremiumBenefitsService",
	"PreviewAppearanceService",
	"PurchaseReceiptService",
	"PvpService",
	"RollService",
	"StatsService",
	"TestService",
	"TimeShardService",
	"TitleService",
	"TutorialAnalyticsService",
	"TutorialService",
	"VoidRecoveryService",
}

local ALL_CONTROLLER_NAMES = {
	"AdminPanelController",
	"AppraisalController",
	"AutoSellController",
	"AutoSellRollController",
	"BodyPartBuildLockController",
	"BossWorldGuideController",
	"BossArenaMovePresentationController",
	"BossLobbyRewardPreviewController",
	"BossArenaStudioTestSuiteController",
	"ChatNotificationController",
	"ChatTagController",
	"CombatAudioController",
	"CombatPhysicsController",
	"CraftingController",
	"DailyChestController",
	"DataController",
	"DashController",
	"DayNightCycleController",
	"DialogueHandlerController",
	"DialogueController",
	"DialogueInteractionController",
	"FoliageController",
	"FootstepController",
	"FrameController",
	"HelpController",
	"HUDWindowController",
	"IndexController",
	"InventoryController",
	"LeaderboardController",
	"MarketplaceController",
	"MerchantPresentationController",
	"MerchantShopController",
	"MerchantTeleportController",
	"MusicTopBarController",
	"MoneyHUDController",
	"OverheadTitleController",
	"PlayerInspectController",
	"ProximityPromptReachController",
	"PotionController",
	"PvpController",
	"PvpHitFlashController",
	"QuestBoardOnboardingGuideController",
	"SlotCardRenderer",
	"StoreController",
	"TestController",
	"TimeShardsHUDController",
	"TitleController",
	"TutorialController",
	"UIController",
}

local ALL_PANEL_NAMES = {
	"Main",
	"Dialogue",
	"Leaderboard",
	"Roll",
}

local ALL_FRAME_NAMES = {
	"AdminPanel",
	"AppraisalUI",
	"AutoSell",
	"CraftingMenu",
	"Gifting",
	"Help",
	"Index",
	"Inventory",
	"MerchantTeleportFrame",
	"PlayerInfo",
	"RobuxStore",
	"ShopUI",
	"Titles",
}

local FEATURE_DISPLAY_NAMES = {
	rolling = "Rolling",
	leaderboard = "The leaderboard",
	dialogue = "Dialogue",
	appraisal = "Appraisal",
	inventory = "Inventory",
	loadout = "Loadout management",
	crafting = "Crafting",
	merchant_shop = "The merchant shop",
	marketplace = "The marketplace",
	titles = "Titles",
	potions = "Potions",
	pvp = "PvP",
	time_shards = "Time Shards",
	help = "Help",
	index = "The index",
	player_inspect = "Player inspect",
	main_hub = "The main hub UI",
	auto_sell = "Auto-sell",
	boss_lobby_flow = "The boss lobby flow",
	boss_fight_flow = "The boss fight flow",
	day_night_cycle = "The day/night cycle",
	player_data_replica = "Shared player data",
}

local FEATURE_TO_EXCLUSIONS = {
	rolling = {
		panels = { "Roll" },
		frames = { "AutoSell" },
		controllers = { "AutoSellController", "AutoSellRollController" },
	},
	leaderboard = {
		panels = { "Leaderboard" },
		controllers = { "LeaderboardController" },
	},
	dialogue = {
		panels = { "Dialogue" },
		controllers = { "DialogueController", "DialogueHandlerController", "DialogueInteractionController" },
		services = { "DialogueActionService" },
	},
	appraisal = {
		frames = { "AppraisalUI" },
		controllers = { "AppraisalController" },
		services = { "AppraisalService" },
	},
	inventory = {
		frames = { "Inventory" },
		controllers = { "InventoryController" },
	},
	loadout = {
		frames = { "Inventory" },
		controllers = { "InventoryController" },
	},
	crafting = {
		frames = { "CraftingMenu" },
		controllers = { "CraftingController" },
		services = { "CraftingService" },
	},
	merchant_shop = {
		frames = { "MerchantTeleportFrame", "ShopUI" },
		controllers = {
			"MerchantPresentationController",
			"MerchantShopController",
			"MerchantTeleportController",
		},
		services = { "MerchantShopService" },
	},
	marketplace = {
		frames = { "Gifting", "RobuxStore" },
		controllers = { "MarketplaceController", "StoreController" },
	},
	titles = {
		frames = { "Titles" },
		controllers = { "TitleController" },
		services = { "TitleService" },
	},
	potions = {
		controllers = { "PotionController" },
		services = { "PotionService" },
	},
	pvp = {
		controllers = { "PvpController", "PvpHitFlashController" },
		services = { "PvpService" },
	},
	time_shards = {
		controllers = { "TimeShardsHUDController" },
		services = { "TimeShardService" },
	},
	help = {
		frames = { "Help" },
		controllers = { "HelpController" },
	},
	index = {
		frames = { "Index" },
		controllers = { "IndexController" },
	},
	player_inspect = {
		frames = { "PlayerInfo" },
		controllers = { "PlayerInspectController" },
	},
	main_hub = {
		panels = { "Main" },
		controllers = { "MoneyHUDController" },
	},
	auto_sell = {
		frames = { "AutoSell" },
		controllers = { "AutoSellController", "AutoSellRollController" },
	},
	player_data_replica = {
		controllers = { "DataController" },
	},
	day_night_cycle = {
		services = { "DayNightCycleService" },
		controllers = { "DayNightCycleController" },
	},
}

type PreloadRootSpec = {
	name: string,
	required: boolean,
}

type PreloadSpec = {
	mainInterfaceRoots: { PreloadRootSpec },
	modalRootRoots: { PreloadRootSpec },
	gameAssetPaths: { string },
}

type PlaceProfileShape = {
	id: string,
	displayName: string,
	placeIds: { number },
	requiresMainInterface: boolean,
	requiresPlayerDataReplica: boolean,
	excludedFeatures: { [string]: boolean },
	excludedPanels: { [string]: boolean },
	excludedFrames: { [string]: boolean },
	excludedServices: { [string]: boolean },
	excludedControllers: { [string]: boolean },
	preloadSpec: PreloadSpec,
	routes: { [string]: { placeId: number, devPlaceId: number, productionPlaceId: number, profileId: string } },
}

local PROFILE_DEFINITIONS = {
	main = {
		displayName = "Main Place",
		placeIds = RouteConfig.GetPlaceIdsForProfile("main"),
		requiresMainInterface = true,
		requiresPlayerDataReplica = true,
		excludedFeatures = {
			"boss_fight_flow",
			"boss_lobby_flow",
		},
		excludedPanels = {},
		excludedFrames = {},
		excludedServices = {},
		excludedControllers = {},
	},
	boss_lobby = {
		displayName = "Boss Lobby",
		placeIds = RouteConfig.GetPlaceIdsForProfile("boss_lobby"),
		requiresMainInterface = true,
		requiresPlayerDataReplica = true,
		excludedFeatures = {
			"boss_fight_flow",
			"day_night_cycle",
			"pvp",
			"rolling",
		},
		excludedPanels = {},
		excludedFrames = {},
		excludedServices = {},
		excludedControllers = {},
	},
	boss_arena = {
		displayName = "Boss Fight Arena",
		placeIds = RouteConfig.GetPlaceIdsForProfile("boss_arena"),
		requiresMainInterface = true,
		requiresPlayerDataReplica = true,
		excludedFeatures = {
			"appraisal",
			"day_night_cycle",
			"dialogue",
			"help",
			"index",
			"inventory",
			"loadout",
			"main_hub",
			"marketplace",
			"merchant_shop",
			"player_inspect",
			"player_data_replica",
			"pvp",
			"rolling",
			"time_shards",
			"titles",
		},
		excludedPanels = {},
		excludedFrames = {},
		excludedServices = {},
		excludedControllers = {},
	},
	unknown = {
		displayName = "Unknown Place",
		placeIds = {},
		requiresMainInterface = false,
		requiresPlayerDataReplica = false,
		excludedFeatures = {
			"appraisal",
			"auto_sell",
			"boss_fight_flow",
			"boss_lobby_flow",
			"dialogue",
			"help",
			"index",
			"inventory",
			"leaderboard",
			"loadout",
			"main_hub",
			"marketplace",
			"merchant_shop",
			"player_inspect",
			"player_data_replica",
			"potions",
			"pvp",
			"rolling",
			"time_shards",
			"titles",
		},
		excludedPanels = ALL_PANEL_NAMES,
		excludedFrames = ALL_FRAME_NAMES,
		excludedServices = ALL_SERVICE_NAMES,
		excludedControllers = ALL_CONTROLLER_NAMES,
	},
}

local PROFILE_ORDER = { "main", "boss_lobby", "boss_arena" }
local PLACE_ID_SETS: { [string]: { [number]: boolean } } = {}
local PROFILES_BY_ID: { [string]: PlaceProfileShape } = {}
local studioDiagnosticEmitted = false
local studioUnknownPlaceWarningEmitted = false

local function listToSet(values: { any }?): { [string]: boolean }
	local result = {}
	if typeof(values) ~= "table" then
		return result
	end

	for _, value in ipairs(values) do
		if typeof(value) == "string" and value ~= "" then
			result[value] = true
		end
	end

	return result
end

local function buildPlaceIdSet(placeIds: { number }?): { [number]: boolean }
	local result = {}
	if typeof(placeIds) ~= "table" then
		return result
	end

	for _, placeId in ipairs(placeIds) do
		local resolvedPlaceId = math.floor(tonumber(placeId) or 0)
		if resolvedPlaceId > 0 then
			result[resolvedPlaceId] = true
		end
	end

	return result
end

local function addExclusionList(targetSet: { [string]: boolean }, values: { string }?)
	if typeof(values) ~= "table" then
		return
	end

	for _, value in ipairs(values) do
		if typeof(value) == "string" and value ~= "" then
			targetSet[value] = true
		end
	end
end

local function buildProfile(profileId: string, definition: any): PlaceProfileShape
	local excludedFeatures = listToSet(definition.excludedFeatures)
	local excludedPanels = listToSet(definition.excludedPanels)
	local excludedFrames = listToSet(definition.excludedFrames)
	local excludedServices = listToSet(definition.excludedServices)
	local excludedControllers = listToSet(definition.excludedControllers)

	for featureId in pairs(excludedFeatures) do
		local mappedExclusions = FEATURE_TO_EXCLUSIONS[featureId]
		if mappedExclusions then
			addExclusionList(excludedPanels, mappedExclusions.panels)
			addExclusionList(excludedFrames, mappedExclusions.frames)
			if profileId == "unknown" then
				addExclusionList(excludedServices, mappedExclusions.services)
				addExclusionList(excludedControllers, mappedExclusions.controllers)
			end
		end
	end

	local placeIds = {}
	local seenPlaceIds = {}
	local configuredPlaceIds = if typeof(definition.placeIds) == "table" then definition.placeIds else {}

	for _, environment in ipairs({ "dev", "production" }) do
		local resolvedPlaceId = math.max(0, math.floor(tonumber(configuredPlaceIds[environment]) or 0))
		if resolvedPlaceId > 0 and seenPlaceIds[resolvedPlaceId] ~= true then
			seenPlaceIds[resolvedPlaceId] = true
			table.insert(placeIds, resolvedPlaceId)
		end
	end

	local profile = {
		id = profileId,
		displayName = definition.displayName or profileId,
		placeIds = table.freeze(placeIds),
		requiresMainInterface = definition.requiresMainInterface == true,
		requiresPlayerDataReplica = definition.requiresPlayerDataReplica == true,
		excludedFeatures = table.freeze(excludedFeatures),
		excludedPanels = table.freeze(excludedPanels),
		excludedFrames = table.freeze(excludedFrames),
		excludedServices = table.freeze(excludedServices),
		excludedControllers = table.freeze(excludedControllers),
		preloadSpec = PreloadProfiles.BuildPreloadSpec({
			requiresMainInterface = definition.requiresMainInterface == true,
			excludedFeatures = excludedFeatures,
		}),
		routes = RouteConfig.BuildRoutesForProfile(profileId, RouteConfig.GetRuntimeEnvironment()),
	}

	PLACE_ID_SETS[profileId] = buildPlaceIdSet(placeIds)
	return table.freeze(profile)
end

for profileId, definition in pairs(PROFILE_DEFINITIONS) do
	PROFILES_BY_ID[profileId] = buildProfile(profileId, definition)
end

local resolvedActiveProfile: PlaceProfileShape? = nil

local PlaceProfile = {}

local function resolveProfileForPlaceId(placeId: number): PlaceProfileShape?
	for _, profileId in ipairs(PROFILE_ORDER) do
		local placeIdSet = PLACE_ID_SETS[profileId]
		if placeIdSet and placeIdSet[placeId] == true then
			return PROFILES_BY_ID[profileId]
		end
	end

	return nil
end

local function emitStudioDiagnostic(profile: PlaceProfileShape, placeId: number)
	if studioDiagnosticEmitted then
		return
	end

	studioDiagnosticEmitted = true
	Logger.Print(string.format(
		"[PlaceProfile][Studio] Resolved profile '%s' for PlaceId %d.",
		profile.id,
		placeId
	))
end

local function resolveLiveProfile(): PlaceProfileShape
	local placeId = math.max(0, math.floor(tonumber(game.PlaceId) or 0))
	local mappedProfile = resolveProfileForPlaceId(placeId)
	if mappedProfile then
		return mappedProfile
	end

	return PROFILES_BY_ID.unknown
end

function PlaceProfile.GetActiveProfile(): PlaceProfileShape
	if resolvedActiveProfile then
		return resolvedActiveProfile
	end

	local placeId = math.max(0, math.floor(tonumber(game.PlaceId) or 0))

	if RunService:IsStudio() then
		if placeId == 0 then
			resolvedActiveProfile = PROFILES_BY_ID.main
			emitStudioDiagnostic(resolvedActiveProfile, placeId)
			return resolvedActiveProfile
		end

		local mappedProfile = resolveProfileForPlaceId(placeId)
		if mappedProfile then
			resolvedActiveProfile = mappedProfile
			emitStudioDiagnostic(resolvedActiveProfile, placeId)
			return resolvedActiveProfile
		end

		resolvedActiveProfile = PROFILES_BY_ID.unknown
		if not studioUnknownPlaceWarningEmitted then
			studioUnknownPlaceWarningEmitted = true
			Logger.Warn(string.format(
				"[PlaceProfile][Studio] No mapped profile exists for PlaceId %d. Falling back to 'unknown'.",
				placeId
			))
		end
		emitStudioDiagnostic(resolvedActiveProfile, placeId)
		return resolvedActiveProfile
	end

	resolvedActiveProfile = resolveLiveProfile()
	return resolvedActiveProfile
end

function PlaceProfile.GetRoutes(): { [string]: { placeId: number, devPlaceId: number, productionPlaceId: number, profileId: string } }
	return PlaceProfile.GetActiveProfile().routes
end

function PlaceProfile.RequiresMainInterface(): boolean
	return PlaceProfile.GetActiveProfile().requiresMainInterface == true
end

function PlaceProfile.RequiresPlayerDataReplica(): boolean
	return PlaceProfile.GetActiveProfile().requiresPlayerDataReplica == true
end

function PlaceProfile.GetPreloadSpec(): PreloadSpec
	return PlaceProfile.GetActiveProfile().preloadSpec
end

function PlaceProfile.GetFeatureUnavailableMessage(featureId: string): string
	local activeProfile = PlaceProfile.GetActiveProfile()
	local featureLabel = FEATURE_DISPLAY_NAMES[featureId] or "This feature"
	return string.format("%s is unavailable in %s.", featureLabel, activeProfile.displayName)
end

function PlaceProfile.IsFeatureEnabled(featureId: string): boolean
	if typeof(featureId) ~= "string" or featureId == "" then
		return true
	end

	return PlaceProfile.GetActiveProfile().excludedFeatures[featureId] ~= true
end

function PlaceProfile.IsPanelEnabled(panelName: string): boolean
	if typeof(panelName) ~= "string" or panelName == "" then
		return true
	end

	return PlaceProfile.GetActiveProfile().excludedPanels[panelName] ~= true
end

function PlaceProfile.IsFrameEnabled(frameName: string): boolean
	if typeof(frameName) ~= "string" or frameName == "" then
		return true
	end

	return PlaceProfile.GetActiveProfile().excludedFrames[frameName] ~= true
end

function PlaceProfile.ShouldLoadService(moduleName: string): boolean
	if typeof(moduleName) ~= "string" or moduleName == "" then
		return true
	end

	local activeProfile = PlaceProfile.GetActiveProfile()
	if activeProfile.id ~= "unknown" then
		return true
	end

	return activeProfile.excludedServices[moduleName] ~= true
end

function PlaceProfile.ShouldLoadController(moduleName: string): boolean
	if typeof(moduleName) ~= "string" or moduleName == "" then
		return true
	end

	local activeProfile = PlaceProfile.GetActiveProfile()
	if activeProfile.id ~= "unknown" then
		return true
	end

	return activeProfile.excludedControllers[moduleName] ~= true
end

return table.freeze(PlaceProfile)
