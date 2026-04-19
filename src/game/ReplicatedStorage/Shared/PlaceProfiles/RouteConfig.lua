local RouteConfig = {}

-- Populate these with the real production PlaceIds before publishing the
-- multi-place universe. Leaving them at 0 keeps Studio on the main profile
-- and makes unknown live places fail closed.
RouteConfig.PlaceIds = {
	main = 112885520797200,
	boss_lobby = 88973634790707,
	boss_arena = 109745823794982,
}

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

function RouteConfig.BuildRoutesForProfile(profileId: string): { [string]: { placeId: number, profileId: string } }
	local routes = {}
	local routeTargets = RouteConfig.RouteGraph[profileId]
	if typeof(routeTargets) ~= "table" then
		return routes
	end

	for routeId, targetProfileId in pairs(routeTargets) do
		routes[routeId] = {
			placeId = math.max(0, math.floor(tonumber(RouteConfig.PlaceIds[targetProfileId]) or 0)),
			profileId = targetProfileId,
		}
	end

	return routes
end

return table.freeze(RouteConfig)
