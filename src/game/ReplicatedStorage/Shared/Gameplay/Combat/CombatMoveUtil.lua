local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local CombatMoveUtil = {}

export type AliveTargetLike = {
	player: Player?,
	character: Model?,
	humanoid: Humanoid?,
	rootPart: BasePart?,
	distance: number?,
	distanceToBoss: number?,
	distanceToSource: number?,
}

export type DamageTargetInfo = {
	player: Player?,
	character: Model,
	humanoid: Humanoid,
	rootPart: BasePart?,
}

export type BossEncounterScalingLike = {
	damageMultiplier: number?,
}

export type BossDamageContextLike = {
	encounterScaling: BossEncounterScalingLike?,
}

export type FloorRaycastOptions = {
	sourceModel: Model?,
	targetCharacter: Model?,
	excludeRoots: { Instance }?,
	startHeight: number?,
	distance: number?,
	ignoreWater: boolean?,
}

local DEFAULT_FLOOR_RAYCAST_START_HEIGHT = 20
local DEFAULT_FLOOR_RAYCAST_DISTANCE = 350

local function addUniqueInstance(instances: { Instance }, seen: { [Instance]: boolean }, instance: Instance?)
	if instance == nil or instance.Parent == nil or seen[instance] == true then
		return
	end

	seen[instance] = true
	table.insert(instances, instance)
end

function CombatMoveUtil.ResolveHumanoid(model: Model?, requireAlive: boolean?): Humanoid?
	if model == nil then
		return nil
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return nil
	end
	if requireAlive == true and humanoid.Health <= 0 then
		return nil
	end

	return humanoid
end

function CombatMoveUtil.ResolveRootPart(model: Model?): BasePart?
	if model == nil then
		return nil
	end

	local rootPart = model:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	local primaryPart = model.PrimaryPart
	if primaryPart then
		return primaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

function CombatMoveUtil.ResolveNamedPart(root: Instance?, candidateNames: { string }, recursive: boolean?): BasePart?
	if root == nil then
		return nil
	end

	local shouldRecurse = recursive ~= false
	for _, partName in ipairs(candidateNames) do
		local part = root:FindFirstChild(partName, shouldRecurse)
		if part and part:IsA("BasePart") then
			return part
		end
	end

	return nil
end

function CombatMoveUtil.ResolveNamedAttachment(root: Instance?, attachmentName: string): Attachment?
	if root == nil then
		return nil
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Attachment") and descendant.Name == attachmentName then
			return descendant
		end
	end

	return nil
end

function CombatMoveUtil.ResolveStandingHeight(humanoid: Humanoid?, rootPart: BasePart): number
	if humanoid == nil then
		return rootPart.Size.Y
	end

	return math.max((rootPart.Size.Y * 0.5) + humanoid.HipHeight, rootPart.Size.Y)
end

function CombatMoveUtil.ResolvePlanarDirection(
	fromPosition: Vector3,
	toPosition: Vector3?,
	fallbackDirection: Vector3?
): Vector3
	if typeof(toPosition) == "Vector3" then
		local offset = toPosition - fromPosition
		local planarOffset = Vector3.new(offset.X, 0, offset.Z)
		if planarOffset.Magnitude > 0.001 then
			return planarOffset.Unit
		end
	end

	if typeof(fallbackDirection) == "Vector3" then
		local planarFallback = Vector3.new(fallbackDirection.X, 0, fallbackDirection.Z)
		if planarFallback.Magnitude > 0.001 then
			return planarFallback.Unit
		end
	end

	return Vector3.new(0, 0, -1)
end

function CombatMoveUtil.ResolvePlanarForward(rootPart: BasePart, targetPosition: Vector3?): Vector3
	return CombatMoveUtil.ResolvePlanarDirection(rootPart.Position, targetPosition, rootPart.CFrame.LookVector)
end

function CombatMoveUtil.ResolvePlanarBasis(sourceRootPart: BasePart, targetPosition: Vector3?): (Vector3, Vector3)
	local forward = CombatMoveUtil.ResolvePlanarForward(sourceRootPart, targetPosition)
	local right = forward:Cross(Vector3.yAxis)
	if right.Magnitude <= 0.001 then
		right = Vector3.xAxis
	else
		right = right.Unit
	end

	return right, forward
end

function CombatMoveUtil.BuildRadialKnockbackDirection(options: {
	impactPosition: Vector3,
	targetRootPart: BasePart?,
	fallbackPosition: Vector3?,
	speed: number,
	upwardSpeed: number,
}): Vector3
	local direction = Vector3.new(0, 0, -1)
	local targetRootPart = options.targetRootPart
	if targetRootPart and targetRootPart.Parent ~= nil then
		local offset = targetRootPart.Position - options.impactPosition
		local planarOffset = Vector3.new(offset.X, 0, offset.Z)
		if planarOffset.Magnitude <= 0.001 and typeof(options.fallbackPosition) == "Vector3" then
			offset = targetRootPart.Position - options.fallbackPosition
			planarOffset = Vector3.new(offset.X, 0, offset.Z)
		end
		if planarOffset.Magnitude > 0.001 then
			direction = planarOffset.Unit
		end
	end

	return (direction * math.max(0, tonumber(options.speed) or 0))
		+ Vector3.new(0, math.max(0, tonumber(options.upwardSpeed) or 0), 0)
end

function CombatMoveUtil.BuildFloorRaycastParams(options: FloorRaycastOptions): RaycastParams
	local excludedInstances = {}
	local seen = {}
	local raycastParams = RaycastParams.new()
	addUniqueInstance(excludedInstances, seen, options.sourceModel)
	addUniqueInstance(excludedInstances, seen, options.targetCharacter)
	for _, root in ipairs(options.excludeRoots or {}) do
		addUniqueInstance(excludedInstances, seen, root)
	end

	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = excludedInstances
	raycastParams.IgnoreWater = options.ignoreWater == true

	return raycastParams
end

function CombatMoveUtil.BuildExcludingCharactersRaycastParams(options: {
	sourceModel: Model?,
	targetCharacter: Model?,
	aliveTargets: { AliveTargetLike }?,
	excludeLivePlayerCharacters: boolean?,
	excludeRoots: { Instance }?,
	ignoreWater: boolean?,
}): RaycastParams
	local excludedInstances = {}
	local seen = {}

	addUniqueInstance(excludedInstances, seen, options.sourceModel)
	addUniqueInstance(excludedInstances, seen, options.targetCharacter)

	for _, target in ipairs(options.aliveTargets or {}) do
		addUniqueInstance(excludedInstances, seen, target.character)
	end

	if options.excludeLivePlayerCharacters == true then
		for _, player in ipairs(Players:GetPlayers()) do
			addUniqueInstance(excludedInstances, seen, player.Character)
		end
	end

	for _, root in ipairs(options.excludeRoots or {}) do
		addUniqueInstance(excludedInstances, seen, root)
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = excludedInstances
	raycastParams.IgnoreWater = options.ignoreWater == true
	return raycastParams
end

function CombatMoveUtil.RaycastGroundNear(position: Vector3, options: FloorRaycastOptions): Vector3?
	local startHeight = math.max(0, tonumber(options.startHeight) or DEFAULT_FLOOR_RAYCAST_START_HEIGHT)
	local distance = math.max(0, tonumber(options.distance) or DEFAULT_FLOOR_RAYCAST_DISTANCE)
	local raycastParams = CombatMoveUtil.BuildFloorRaycastParams(options)
	local rayOrigin = position + Vector3.new(0, startHeight, 0)
	local rayDirection = Vector3.new(0, -(startHeight + distance), 0)
	local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	if raycastResult == nil then
		return nil
	end

	return raycastResult.Position
end

function CombatMoveUtil.RaycastGroundNearWithParams(
	position: Vector3,
	raycastParams: RaycastParams,
	startHeight: number?,
	distance: number?
): Vector3?
	local resolvedStartHeight = math.max(0, tonumber(startHeight) or DEFAULT_FLOOR_RAYCAST_START_HEIGHT)
	local resolvedDistance = math.max(0, tonumber(distance) or DEFAULT_FLOOR_RAYCAST_DISTANCE)
	local rayOrigin = position + Vector3.new(0, resolvedStartHeight, 0)
	local rayDirection = Vector3.new(0, -(resolvedStartHeight + resolvedDistance), 0)
	local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	if raycastResult == nil then
		return nil
	end

	return raycastResult.Position
end

function CombatMoveUtil.ResolveFloorImpactCFrames(options: {
	rawImpactCFrame: CFrame,
	sourceModel: Model?,
	targetCharacter: Model?,
	aliveTargets: { AliveTargetLike }?,
	warnPrefix: string?,
	startHeight: number?,
	distance: number?,
	excludeRoots: { Instance }?,
	visualOffsetY: number?,
}): (CFrame, CFrame?)
	local fallbackImpactCFrame = CFrame.new(options.rawImpactCFrame.Position)
	local raycastParams = CombatMoveUtil.BuildFloorRaycastParams({
		sourceModel = options.sourceModel,
		targetCharacter = options.targetCharacter,
		excludeRoots = options.excludeRoots,
		ignoreWater = true,
	})
	local floorPosition = CombatMoveUtil.RaycastGroundNearWithParams(
		options.rawImpactCFrame.Position,
		raycastParams,
		options.startHeight,
		options.distance
	)
	if floorPosition == nil then
		local warnPrefix = if typeof(options.warnPrefix) == "string" and options.warnPrefix ~= "" then options.warnPrefix else "[CombatMoveUtil]"
		Logger.Warn(string.format(
			"%s Could not raycast impact floor. Skipping floor VFX and using fallback for gameplay.",
			warnPrefix
		))
		return fallbackImpactCFrame, nil
	end

	local floorImpactCFrame = CFrame.new(floorPosition)
	local visualImpactCFrame = CFrame.new(floorPosition + Vector3.new(0, options.visualOffsetY or 0, 0))
	return floorImpactCFrame, visualImpactCFrame
end

function CombatMoveUtil.ResolveNearestAliveTarget(
	sourcePosition: Vector3,
	targets: { AliveTargetLike },
	maxDistance: number?
): AliveTargetLike?
	local nearestTarget = nil
	local nearestDistance = nil

	for _, target in ipairs(targets) do
		local humanoid = target.humanoid or CombatMoveUtil.ResolveHumanoid(target.character, true)
		local rootPart = target.rootPart or CombatMoveUtil.ResolveRootPart(target.character)
		if humanoid == nil or humanoid.Health <= 0 or rootPart == nil or rootPart.Parent == nil then
			continue
		end

		local distance = (rootPart.Position - sourcePosition).Magnitude
		if maxDistance ~= nil and distance > maxDistance then
			continue
		end

		if nearestDistance == nil or distance < nearestDistance then
			nearestTarget = target
			nearestDistance = distance
		end
	end

	return nearestTarget
end

function CombatMoveUtil.CollectAliveTargets(targets: { AliveTargetLike }): { AliveTargetLike }
	local aliveTargets = {}
	for _, target in ipairs(targets) do
		local humanoid = target.humanoid or CombatMoveUtil.ResolveHumanoid(target.character, true)
		local rootPart = target.rootPart or CombatMoveUtil.ResolveRootPart(target.character)
		if target.player ~= nil
			and target.character ~= nil
			and humanoid ~= nil
			and humanoid.Health > 0
			and rootPart ~= nil
			and rootPart.Parent ~= nil then
			table.insert(aliveTargets, {
				player = target.player,
				character = target.character,
				humanoid = humanoid,
				rootPart = rootPart,
				distance = target.distance or target.distanceToSource or target.distanceToBoss,
			})
		end
	end

	return aliveTargets
end

function CombatMoveUtil.ResolveDamageTarget(targetModel: Model?, requirePlayerCharacter: boolean?): DamageTargetInfo?
	if targetModel == nil then
		return nil
	end

	local player = Players:GetPlayerFromCharacter(targetModel)
	if requirePlayerCharacter ~= false and player == nil then
		return nil
	end

	local humanoid = CombatMoveUtil.ResolveHumanoid(targetModel, true)
	if humanoid == nil then
		return nil
	end

	return {
		player = player,
		character = targetModel,
		humanoid = humanoid,
		rootPart = CombatMoveUtil.ResolveRootPart(targetModel),
	}
end

function CombatMoveUtil.ResolveScaledBossDamage(context: BossDamageContextLike?, baseDamage: number): number
	local resolvedBaseDamage = math.max(0, tonumber(baseDamage) or 0)
	local damageMultiplier = 1

	if typeof(context) == "table" and typeof(context.encounterScaling) == "table" then
		damageMultiplier = tonumber(context.encounterScaling.damageMultiplier) or damageMultiplier
	end

	return math.max(0, math.round(resolvedBaseDamage * damageMultiplier))
end

function CombatMoveUtil.DamageOnce(
	hitTargets: { [Model]: boolean },
	targetModel: Model,
	damage: number,
	requirePlayerCharacter: boolean?
): DamageTargetInfo?
	if hitTargets[targetModel] == true then
		return nil
	end

	local targetInfo = CombatMoveUtil.ResolveDamageTarget(targetModel, requirePlayerCharacter)
	if targetInfo == nil then
		return nil
	end

	hitTargets[targetModel] = true
	targetInfo.humanoid:TakeDamage(math.max(0, tonumber(damage) or 0))
	return targetInfo
end

return table.freeze(CombatMoveUtil)
