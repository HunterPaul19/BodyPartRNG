local PreloadProfiles = {}

export type PreloadRootSpec = {
	name: string,
	required: boolean,
}

export type PreloadSpec = {
	mainInterfaceRoots: { PreloadRootSpec },
	modalRootRoots: { PreloadRootSpec },
	gameAssetPaths: { string },
}

type FeaturePreloadContribution = {
	mainInterfaceRoots: { string | PreloadRootSpec }?,
	modalRootRoots: { string | PreloadRootSpec }?,
	gameAssetPaths: { string }?,
}

type BuildPreloadSpecOptions = {
	requiresMainInterface: boolean,
	excludedFeatures: { [string]: boolean },
}

local FEATURE_ORDER = {
	"main_hub",
	"dialogue",
	"leaderboard",
	"rolling",
	"appraisal",
	"inventory",
	"loadout",
	"crafting",
	"merchant_shop",
	"marketplace",
	"titles",
	"potions",
	"help",
	"index",
	"player_inspect",
	"auto_sell",
	"boss_lobby_flow",
	"boss_fight_flow",
	"player_data_replica",
}

local BASE_MAIN_INTERFACE_ROOTS = {
	"Black",
	"Black2",
}

local FEATURE_TO_PRELOAD_CONTRIBUTIONS: { [string]: FeaturePreloadContribution } = {
	main_hub = {
		mainInterfaceRoots = { "Main" },
	},
	rolling = {
		mainInterfaceRoots = { "Roll", "RollWarning" },
		gameAssetPaths = { "UI/RollCutscene" },
	},
	appraisal = {
		modalRootRoots = { "AppraisalUI" },
	},
	inventory = {
		modalRootRoots = { "Inventory" },
	},
	loadout = {
		modalRootRoots = { "Inventory" },
	},
	crafting = {
		modalRootRoots = { "CraftingMenu" },
	},
	merchant_shop = {
		modalRootRoots = { "MerchantTeleportFrame", "ShopUI" },
	},
	marketplace = {
		modalRootRoots = { "Gifting", "RobuxStore" },
	},
	titles = {
		modalRootRoots = { "Titles" },
	},
	potions = {
		mainInterfaceRoots = {
			{ name = "BuffsHolder", required = false },
			{ name = "StatusEffectHover", required = false },
		},
	},
	help = {
		modalRootRoots = { "Help" },
	},
	index = {
		modalRootRoots = { "Index" },
	},
	player_inspect = {
		modalRootRoots = { "PlayerInfo" },
	},
	auto_sell = {
		modalRootRoots = { "AutoSell" },
	},
	boss_fight_flow = {
		mainInterfaceRoots = { "BossHealthBar", "CombatHUD" },
	},
}

local function freezeRootSpecs(rootSpecs: { PreloadRootSpec }): { PreloadRootSpec }
	for index, rootSpec in ipairs(rootSpecs) do
		rootSpecs[index] = table.freeze(rootSpec)
	end

	return table.freeze(rootSpecs)
end

local function freezeStringArray(values: { string }): { string }
	return table.freeze(values)
end

local function addRootSpecs(target: { PreloadRootSpec }, seen: { [string]: boolean }, rootSpecs: { string | PreloadRootSpec }?)
	if typeof(rootSpecs) ~= "table" then
		return
	end

	for _, rootSpec in ipairs(rootSpecs) do
		local rootName: string? = nil
		local isRequired = true

		if typeof(rootSpec) == "string" then
			rootName = rootSpec
		elseif typeof(rootSpec) == "table" then
			local typedRootSpec = rootSpec :: PreloadRootSpec
			rootName = typedRootSpec.name
			isRequired = typedRootSpec.required == true
		end

		if typeof(rootName) == "string" and rootName ~= "" and seen[rootName] ~= true then
			seen[rootName] = true
			table.insert(target, {
				name = rootName,
				required = isRequired,
			})
		end
	end
end

local function addAssetPaths(target: { string }, seen: { [string]: boolean }, assetPaths: { string }?)
	if typeof(assetPaths) ~= "table" then
		return
	end

	for _, assetPath in ipairs(assetPaths) do
		if typeof(assetPath) == "string" and assetPath ~= "" and seen[assetPath] ~= true then
			seen[assetPath] = true
			table.insert(target, assetPath)
		end
	end
end

function PreloadProfiles.BuildPreloadSpec(options: BuildPreloadSpecOptions): PreloadSpec
	local resolvedOptions = if typeof(options) == "table" then options else {
		requiresMainInterface = false,
		excludedFeatures = {},
	}
	local excludedFeatures = if typeof(resolvedOptions.excludedFeatures) == "table"
		then resolvedOptions.excludedFeatures
		else {}

	local mainInterfaceRoots = {}
	local modalRootRoots = {}
	local gameAssetPaths = {}

	local seenMainInterfaceRoots = {}
	local seenModalRootRoots = {}
	local seenGameAssetPaths = {}

	if resolvedOptions.requiresMainInterface == true then
		addRootSpecs(mainInterfaceRoots, seenMainInterfaceRoots, BASE_MAIN_INTERFACE_ROOTS)
	end

	for _, featureId in ipairs(FEATURE_ORDER) do
		if excludedFeatures[featureId] == true then
			continue
		end

		local contribution = FEATURE_TO_PRELOAD_CONTRIBUTIONS[featureId]
		if contribution then
			addRootSpecs(mainInterfaceRoots, seenMainInterfaceRoots, contribution.mainInterfaceRoots)
			addRootSpecs(modalRootRoots, seenModalRootRoots, contribution.modalRootRoots)
			addAssetPaths(gameAssetPaths, seenGameAssetPaths, contribution.gameAssetPaths)
		end
	end

	return table.freeze({
		mainInterfaceRoots = freezeRootSpecs(mainInterfaceRoots),
		modalRootRoots = freezeRootSpecs(modalRootRoots),
		gameAssetPaths = freezeStringArray(gameAssetPaths),
	})
end

return table.freeze(PreloadProfiles)
