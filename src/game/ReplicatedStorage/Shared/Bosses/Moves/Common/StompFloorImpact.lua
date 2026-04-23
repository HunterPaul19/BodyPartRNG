local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local FLOOR_RAYCAST_START_HEIGHT = 20
local FLOOR_RAYCAST_DISTANCE = 2048

local StompFloorImpact = {}

local function addUniqueInstance(instances: { Instance }, seen: { [Instance]: boolean }, instance: Instance?)
	if instance == nil or instance.Parent == nil or seen[instance] == true then
		return
	end

	seen[instance] = true
	table.insert(instances, instance)
end

local function addLivePlayerCharacters(instances: { Instance }, seen: { [Instance]: boolean })
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			addUniqueInstance(instances, seen, character)
		end
	end
end

local function addAliveTargetCharacters(instances: { Instance }, seen: { [Instance]: boolean }, context: any)
	local aliveTargets = context.aliveTargets
	if typeof(aliveTargets) ~= "table" then
		return
	end

	for _, target in ipairs(aliveTargets) do
		if typeof(target) == "table" then
			addUniqueInstance(instances, seen, target.character)
		end
	end
end

local function addVisualDebugFolders(instances: { Instance }, seen: { [Instance]: boolean })
	local visuals = Workspace:FindFirstChild("Visuals")
	local visualizedHitboxes = visuals and visuals:FindFirstChild("VisualizedHitboxes")
	addUniqueInstance(instances, seen, visualizedHitboxes)
	addUniqueInstance(instances, seen, visuals and visuals:FindFirstChild("CharacterBodyParts"))

	addUniqueInstance(instances, seen, Workspace:FindFirstChild("BossMoveClientEffects"))
	addUniqueInstance(instances, seen, Workspace:FindFirstChild("CharacterBodyParts"))
end

local function buildRaycastParams(context: any): RaycastParams
	local excludedInstances = {}
	local seen = {}

	addUniqueInstance(excludedInstances, seen, context.bossModel)
	addUniqueInstance(excludedInstances, seen, context.targetCharacter)
	addAliveTargetCharacters(excludedInstances, seen, context)
	addLivePlayerCharacters(excludedInstances, seen)
	addVisualDebugFolders(excludedInstances, seen)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = excludedInstances
	raycastParams.IgnoreWater = true
	return raycastParams
end

local function raycastFloor(context: any, position: Vector3): RaycastResult?
	local rayOrigin = position + Vector3.new(0, FLOOR_RAYCAST_START_HEIGHT, 0)
	local rayDirection = Vector3.new(0, -(FLOOR_RAYCAST_START_HEIGHT + FLOOR_RAYCAST_DISTANCE), 0)
	return Workspace:Raycast(rayOrigin, rayDirection, buildRaycastParams(context))
end

function StompFloorImpact.resolveImpactCFrames(context: any, rawImpactCFrame: CFrame, warnPrefix: string): (CFrame, CFrame?)
	local fallbackImpactCFrame = CFrame.new(rawImpactCFrame.Position)
	local floorResult = raycastFloor(context, rawImpactCFrame.Position)
	if floorResult == nil then
		warn(string.format("%s Could not raycast stomp floor. Skipping floor VFX and using foot/root fallback for gameplay.", warnPrefix))
		return fallbackImpactCFrame, nil
	end

	local floorImpactCFrame = CFrame.new(floorResult.Position)
	return floorImpactCFrame, floorImpactCFrame
end

return table.freeze(StompFloorImpact)
