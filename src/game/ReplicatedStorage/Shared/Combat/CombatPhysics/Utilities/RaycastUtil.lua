local CollectionService = game:GetService("CollectionService")

local RaycastUtil = {}
local cache = {}

local function shallowCopy(list)
	local out = {}
	for i = 1, #list do
		out[i] = list[i]
	end
	return out
end

local function appendInstances(target, extra)
	if type(extra) ~= "table" then
		return target
	end
	for _, instance in ipairs(extra) do
		if typeof(instance) == "Instance" then
			table.insert(target, instance)
		end
	end
	return target
end

local function buildMapIncludeList()
	local include = { workspace.Terrain }
	local hasExplicitMap = false

	local activeBossArena = workspace:FindFirstChild("ActiveBossArena")
	if activeBossArena then
		table.insert(include, activeBossArena)
		hasExplicitMap = true
	end

	local workspaceMap = workspace:FindFirstChild("Map")
	if workspaceMap then
		table.insert(include, workspaceMap)
		hasExplicitMap = true
	end

	local world = workspace:FindFirstChild("World")
	local worldMap = world and world:FindFirstChild("Map")
	if worldMap then
		for _, mapChild in ipairs(worldMap:GetChildren()) do
			table.insert(include, mapChild)
			hasExplicitMap = true
		end
	end

	return include, hasExplicitMap
end

local function buildBaseParams(profileName)
	local params = RaycastParams.new()
	params.IgnoreWater = true

	if profileName == "Map" then
		local include, hasExplicitMap = buildMapIncludeList()
		if hasExplicitMap then
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = include
		else
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = {}
		end
		return params
	end

	local tagged = CollectionService:GetTagged(profileName)
	if #tagged > 0 then
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = tagged
	else
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {}
	end

	return params
end

function RaycastUtil.getParams(profile, options)
	if typeof(profile) == "RaycastParams" then
		return profile
	end

	local profileName = typeof(profile) == "string" and profile or "Map"
	local useCache = options == nil
	local params

	if useCache then
		params = cache[profileName]
		if not params then
			params = buildBaseParams(profileName)
			cache[profileName] = params
		end
		return params
	end

	params = buildBaseParams(profileName)
	if options and options.filterList then
		params.FilterDescendantsInstances = shallowCopy(options.filterList)
	end
	if options and options.filterType then
		params.FilterType = options.filterType
	end
	if options and options.ignoreWater ~= nil then
		params.IgnoreWater = options.ignoreWater
	end

	return params
end

function RaycastUtil.getGroundParams(character)
	local mapParams = RaycastUtil.getParams("Map")
	if mapParams.FilterType == Enum.RaycastFilterType.Include then
		return mapParams
	end

	local params = RaycastParams.new()
	params.IgnoreWater = mapParams.IgnoreWater
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = character and { character } or {}
	return params
end

function RaycastUtil.getDeterministicGroundParams(options)
	local params = RaycastParams.new()
	local include, hasExplicitMap = buildMapIncludeList()
	if not hasExplicitMap then
		include = { workspace.Terrain }
	end
	appendInstances(include, options and options.extraInclude)
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	params.IgnoreWater = options and options.ignoreWater ~= nil and options.ignoreWater or true
	return params
end

function RaycastUtil.clearCache()
	table.clear(cache)
end

return RaycastUtil
