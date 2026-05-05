local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local RunService = game:GetService("RunService")

local RouteConfig = {}
local runtimeEnvironmentFallbackWarningEmitted = false

export type RuntimeEnvironment = "dev" | "production"

type PlaceIdRecord = {
	dev: number,
	production: number,
}

type RouteEntry = {
	placeId: number,
	devPlaceId: number,
	productionPlaceId: number,
	profileId: string,
}

RouteConfig.PlaceIds = table.freeze({
	dev = table.freeze({
		main = 112885520797200,
		boss_lobby = 88973634790707,
		boss_arena = 109745823794982,
	}),
	production = table.freeze({
		main = 121799557644828,
		boss_lobby = 102448641384655,
		boss_arena = 104595548892209,
	}),
})

RouteConfig.RouteGraph = {
	main = {
		enter_boss_lobby = "boss_lobby",
		return_to_main = "main",
	},
	boss_lobby = {
		enter_boss_fight = "boss_arena",
		return_to_main = "main",
		return_from_boss_fight = "boss_lobby",
	},
	boss_arena = {
		return_to_boss_lobby = "boss_lobby",
		final_return_to_main = "main",
	},
}

local function normalizePlaceId(placeId: any): number
	return math.max(0, math.floor(tonumber(placeId) or 0))
end

local function getConfiguredProfileIds(): { string }
	local orderedProfileIds = {}
	local seenProfileIds = {}

	for profileId, routeTargets in pairs(RouteConfig.RouteGraph) do
		if seenProfileIds[profileId] ~= true then
			seenProfileIds[profileId] = true
			table.insert(orderedProfileIds, profileId)
		end

		if typeof(routeTargets) == "table" then
			for _, targetProfileId in pairs(routeTargets) do
				if typeof(targetProfileId) == "string" and targetProfileId ~= "" and seenProfileIds[targetProfileId] ~= true then
					seenProfileIds[targetProfileId] = true
					table.insert(orderedProfileIds, targetProfileId)
				end
			end
		end
	end

	table.sort(orderedProfileIds)
	return orderedProfileIds
end

local function resolveEnvironmentForPlaceId(placeId: number): RuntimeEnvironment?
	if placeId <= 0 then
		return nil
	end

	for _, configuredPlaceId in pairs(RouteConfig.PlaceIds.dev) do
		if normalizePlaceId(configuredPlaceId) == placeId then
			return "dev"
		end
	end

	for _, configuredPlaceId in pairs(RouteConfig.PlaceIds.production) do
		if normalizePlaceId(configuredPlaceId) == placeId then
			return "production"
		end
	end

	return nil
end

local function validatePlaceIds()
	local configuredProfileIds = getConfiguredProfileIds()

	for _, environment in ipairs({ "dev", "production" }) do
		local configuredPlaceIds = RouteConfig.PlaceIds[environment]
		local seenPlaceIds = {}

		for _, profileId in ipairs(configuredProfileIds) do
			local resolvedPlaceId = normalizePlaceId(if configuredPlaceIds then configuredPlaceIds[profileId] else 0)
			if resolvedPlaceId <= 0 then
				Logger.Error(
					string.format("[RouteConfig] Missing %s place id for profile '%s'.", environment, profileId),
					0
				)
			end
			if seenPlaceIds[resolvedPlaceId] ~= nil then
				Logger.Error(
					string.format(
						"[RouteConfig] Duplicate %s place id %d for profiles '%s' and '%s'.",
						environment,
						resolvedPlaceId,
						seenPlaceIds[resolvedPlaceId],
						profileId
					),
					0
				)
			end

			seenPlaceIds[resolvedPlaceId] = profileId
		end
	end
end

function RouteConfig.GetRuntimeEnvironment(): RuntimeEnvironment
	if RunService:IsStudio() then
		return "dev"
	end

	local placeEnvironment = resolveEnvironmentForPlaceId(normalizePlaceId(game.PlaceId))
	if placeEnvironment then
		return placeEnvironment
	end

	if not runtimeEnvironmentFallbackWarningEmitted then
		runtimeEnvironmentFallbackWarningEmitted = true
		Logger.Warn(string.format(
			"[RouteConfig] No configured runtime environment matched PlaceId %d. Falling back to production routes.",
			normalizePlaceId(game.PlaceId)
		))
	end
	return "production"
end

function RouteConfig.GetPlaceIdsForProfile(profileId: string): PlaceIdRecord
	local devPlaceIds = RouteConfig.PlaceIds.dev
	local productionPlaceIds = RouteConfig.PlaceIds.production

	return table.freeze({
		dev = normalizePlaceId(if devPlaceIds then devPlaceIds[profileId] else 0),
		production = normalizePlaceId(if productionPlaceIds then productionPlaceIds[profileId] else 0),
	})
end

function RouteConfig.GetPlaceId(profileId: string, environment: RuntimeEnvironment?): number
	local resolvedEnvironment = environment or RouteConfig.GetRuntimeEnvironment()
	local placeIds = RouteConfig.GetPlaceIdsForProfile(profileId)

	if resolvedEnvironment == "dev" then
		return placeIds.dev
	end

	return placeIds.production
end

function RouteConfig.BuildRoutesForProfile(
	profileId: string,
	environment: RuntimeEnvironment?
): { [string]: RouteEntry }
	local routes = {}
	local routeTargets = RouteConfig.RouteGraph[profileId]
	if typeof(routeTargets) ~= "table" then
		return table.freeze(routes)
	end

	local resolvedEnvironment = environment or RouteConfig.GetRuntimeEnvironment()

	for routeId, targetProfileId in pairs(routeTargets) do
		local placeIds = RouteConfig.GetPlaceIdsForProfile(targetProfileId)
		routes[routeId] = table.freeze({
			placeId = RouteConfig.GetPlaceId(targetProfileId, resolvedEnvironment),
			devPlaceId = placeIds.dev,
			productionPlaceId = placeIds.production,
			profileId = targetProfileId,
		})
	end

	return table.freeze(routes)
end

validatePlaceIds()

return table.freeze(RouteConfig)
