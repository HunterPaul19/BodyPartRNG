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
	mainInterfaceRoots: { string }?,
	modalRootRoots: { string }?,
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
	dialogue = {
		mainInterfaceRoots = { "DialogueUI" },
	},
	leaderboard = {
		mainInterfaceRoots = { "Leaderboard" },
	},
	rolling = {
		mainInterfaceRoots = { "Roll", "RollWarning" },
		modalRootRoots = { "AutoSell" },
		gameAssetPaths = { "UI/RollCutscene" },
	},
	appraisal = {
		mainInterfaceRoots = { "RollWarning" },
		modalRootRoots = { "AppraisalUI", "ConfirmationFrame" },
		gameAssetPaths = { "Models/BodyParts", "UI/Index" },
	},
	inventory = {
		modalRootRoots = { "Inventory", "PotionSellFrame", "SellWarningFrame", "ConfirmationFrame" },
		gameAssetPaths = { "Models/BodyParts", "Effects/Auras", "UI/Icons/Auras", "Tools/Potions", "UI/Index", "Effects/Mutations" },
	},
	loadout = {
		modalRootRoots = { "Inventory" },
		gameAssetPaths = { "Models/BodyParts", "UI/Index", "Effects/Mutations" },
	},
	merchant_shop = {
		modalRootRoots = { "MerchantTeleportFrame", "ShopUI" },
		gameAssetPaths = { "Tools/Potions" },
	},
	marketplace = {
		mainInterfaceRoots = { "Gifting", "RobuxStore" },
	},
	titles = {
		modalRootRoots = { "Titles" },
	},
	potions = {
		mainInterfaceRoots = { "BuffsHolder", "StatusEffectHover" },
		gameAssetPaths = { "Tools/Potions", "Effects/Screen" },
	},
	help = {
		modalRootRoots = { "Help" },
	},
	index = {
		modalRootRoots = { "Index", "ConfirmationFrame" },
		gameAssetPaths = { "Models/BodyParts", "UI/Index" },
	},
	player_inspect = {
		modalRootRoots = { "PlayerInfo" },
		gameAssetPaths = { "Models/BodyParts", "Effects/Auras", "UI/Icons/Auras", "UI/Index", "Effects/Mutations" },
	},
	boss_fight_flow = {
		mainInterfaceRoots = { "BossHealthBar", "CombatHUD" },
		gameAssetPaths = { "Models/Bosses", "Models/Worlds/BossArenas" },
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

local function addRootSpecs(target: { PreloadRootSpec }, seen: { [string]: boolean }, rootNames: { string }?)
	if typeof(rootNames) ~= "table" then
		return
	end

	for _, rootName in ipairs(rootNames) do
		if typeof(rootName) == "string" and rootName ~= "" and seen[rootName] ~= true then
			seen[rootName] = true
			table.insert(target, {
				name = rootName,
				required = true,
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
