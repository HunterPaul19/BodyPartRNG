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

local function buildExcludeList(character, extraExclude)
	local exclude = {}
	if character then
		table.insert(exclude, character)
	end
	appendInstances(exclude, extraExclude)
	return exclude
end

local function createExcludeParams(filterList, ignoreWater)
	local params = RaycastParams.new()
	params.IgnoreWater = ignoreWater ~= nil and ignoreWater or true
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = shallowCopy(filterList)
	return params
end

local function findHumanoidModel(instance)
	local current = instance
	while current and current ~= workspace do
		if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function isTransientSupportPart(instance)
	if not instance or not instance:IsA("BasePart") then
		return false
	end

	if instance.Name == "CombatPhysicsDebug" or instance.Name == "RagdollCollider" then
		return true
	end

	local visuals = workspace:FindFirstChild("Visuals")
	if visuals and instance:IsDescendantOf(visuals) and not instance.CanCollide then
		return true
	end

	return false
end

local function isValidSupportSurface(result, character)
	local instance = result and result.Instance
	if not instance then
		return false
	end

	if instance == workspace.Terrain then
		return true
	end

	if not instance:IsA("BasePart") then
		return false
	end

	if character and instance:IsDescendantOf(character) then
		return false
	end

	if isTransientSupportPart(instance) then
		return false
	end

	if not instance.CanCollide then
		return false
	end

	local humanoidModel = findHumanoidModel(instance)
	if humanoidModel then
		return false
	end

	return true
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

function RaycastUtil.getBroadGroundParams(character, options)
	options = type(options) == "table" and options or {}
	return createExcludeParams(
		buildExcludeList(character, options.extraExclude),
		options.ignoreWater
	)
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

function RaycastUtil.raycastSupportSurface(origin, direction, options)
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" or direction.Magnitude <= 0 then
		return nil
	end

	options = type(options) == "table" and options or {}
	local character = options.character
	local ignoreWater = options.ignoreWater
	local maxHits = math.max(1, options.maxHits or 12)
	local stepOffset = math.max(0.01, options.stepOffset or 0.05)
	local excludeList = buildExcludeList(character, options.extraExclude)
	local currentOrigin = origin
	local rayUnit = direction.Unit
	local remainingDistance = direction.Magnitude

	for _ = 1, maxHits do
		local result = workspace:Raycast(
			currentOrigin,
			rayUnit * remainingDistance,
			createExcludeParams(excludeList, ignoreWater)
		)
		if not result then
			break
		end

		if isValidSupportSurface(result, character) then
			return result
		end

		if result.Instance then
			table.insert(excludeList, result.Instance)
		end

		local travelled = (result.Position - currentOrigin).Magnitude
		remainingDistance -= travelled + stepOffset
		if remainingDistance <= 0 then
			break
		end

		currentOrigin = result.Position + (rayUnit * stepOffset)
	end

	if options.fallbackToMap == false then
		return nil
	end

	local fallbackParams = RaycastUtil.getDeterministicGroundParams({
		ignoreWater = ignoreWater,
		extraInclude = options.extraInclude,
	})
	return workspace:Raycast(origin, direction, fallbackParams)
end

function RaycastUtil.clearCache()
	table.clear(cache)
end

return RaycastUtil
