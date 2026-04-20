local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Signal = require(ReplicatedStorage.Common.Signal)
local Trove = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Utilities.Trove)

local Hitbox = {}
Hitbox.__index = Hitbox
Hitbox._activeHitboxes = {}
Hitbox.HitboxTypes = {}

local VISUALIZER_FOLDER_NAME = "VisualizedHitboxes"
local GROUND_DISTANCE = 200
local GROUND_STATE_THRESHOLD = 2
local ROOT_PART_NAMES = { "HumanoidRootPart", "UpperTorso", "LowerTorso", "Torso", "Head" }
local CHARACTER_CONTAINER_NAMES = { "Mobs", "Characters", "NPCs", "ActiveBoss" }

local function spawnSafe(callback, ...)
	if typeof(callback) ~= "function" then
		return
	end

	local packed = table.pack(...)
	task.spawn(function()
		local ok, err = pcall(function()
			callback(table.unpack(packed, 1, packed.n))
		end)
		if not ok then
			warn("[Hitbox] Callback error:", err)
		end
	end)
end

local function resolveValue(source)
	if typeof(source) == "function" then
		local ok, result = pcall(source)
		if ok then
			return result, nil
		end
		return nil, result
	end

	return source, nil
end

local function resolveCFrame(source)
	local value, err = resolveValue(source)
	if value == nil then
		return nil, err or "missing cframe source"
	end

	if typeof(value) == "CFrame" then
		return value, nil
	end

	if typeof(value) == "Instance" then
		if value:IsA("Attachment") then
			return value.WorldCFrame, nil
		end
		if value:IsA("PVInstance") then
			return value:GetPivot(), nil
		end
		if value:IsA("BasePart") then
			return value.CFrame, nil
		end
	end

	if typeof(value) == "table" and typeof(value.CFrame) == "CFrame" then
		return value.CFrame, nil
	end

	return nil, "invalid cframe source"
end

local function resolveSize(source)
	local value, err = resolveValue(source)
	if value == nil then
		return nil, err or "missing size source"
	end
	if typeof(value) == "Vector3" then
		return value, nil
	end
	return nil, "invalid size source"
end

local function resolveNumber(source)
	local value, err = resolveValue(source)
	if value == nil then
		return nil, err or "missing number source"
	end
	if typeof(value) == "number" then
		return value, nil
	end
	return nil, "invalid number source"
end

local function removeFromArray(array, value)
	local index = table.find(array, value)
	if index then
		table.remove(array, index)
	end
end

local function getVisualizerFolder()
	local visuals = Workspace:FindFirstChild("Visuals")
	if not visuals then
		return Workspace
	end

	local folder = visuals:FindFirstChild(VISUALIZER_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = VISUALIZER_FOLDER_NAME
	folder.Parent = visuals
	return folder
end

local function resolveHumanoid(model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return nil
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid
	end

	local nested = model:FindFirstChildWhichIsA("Humanoid", true)
	if nested and nested:IsA("Humanoid") then
		return nested
	end

	return nil
end

local function resolveRootPart(model, humanoid)
	if humanoid and typeof(humanoid.RootPart) == "Instance" and humanoid.RootPart:IsA("BasePart") then
		return humanoid.RootPart
	end

	for _, partName in ipairs(ROOT_PART_NAMES) do
		local candidate = model:FindFirstChild(partName, true)
		if typeof(candidate) == "Instance" and candidate:IsA("BasePart") then
			return candidate
		end
	end

	if typeof(model.PrimaryPart) == "Instance" and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function resolveCharacterModelFromInstance(instance)
	if typeof(instance) ~= "Instance" then
		return nil, nil, nil
	end

	local currentModel = if instance:IsA("Model") then instance else instance:FindFirstAncestorOfClass("Model")

	while currentModel and currentModel:IsA("Model") do
		local humanoid = resolveHumanoid(currentModel)
		if humanoid and humanoid.Health > 0 then
			return currentModel, humanoid, resolveRootPart(currentModel, humanoid)
		end

		local parent = currentModel.Parent
		while parent and not parent:IsA("Model") do
			parent = parent.Parent
		end
		currentModel = parent
	end

	return nil, nil, nil
end

local function resolveCharacterSource(dataCharacter, attack)
	if typeof(dataCharacter) == "Instance" and dataCharacter:IsA("Model") then
		return dataCharacter
	end

	if typeof(attack) == "table" then
		if typeof(attack.Character) == "Instance" and attack.Character:IsA("Model") then
			return attack.Character
		end
		if typeof(attack.Character) == "table" and typeof(attack.Character.Instance) == "Instance"
			and attack.Character.Instance:IsA("Model") then
			return attack.Character.Instance
		end
		if typeof(attack.CharacterProfile) == "table"
			and typeof(attack.CharacterProfile._character) == "Instance"
			and attack.CharacterProfile._character:IsA("Model") then
			return attack.CharacterProfile._character
		end
	end

	return nil
end

local function getOwnerKey(model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return nil
	end

	local player = Players:GetPlayerFromCharacter(model)
	if player then
		return "player:" .. tostring(player.UserId)
	end

	local owner = model:GetAttribute("Owner")
	if typeof(owner) == "string" and owner ~= "" then
		return "owner:" .. owner
	end
	if typeof(owner) == "number" then
		return "owner:" .. tostring(owner)
	end

	return nil
end

local function areFriendly(sourceModel, targetModel)
	if typeof(sourceModel) ~= "Instance" or typeof(targetModel) ~= "Instance" then
		return false
	end

	local sourceOwner = getOwnerKey(sourceModel)
	local targetOwner = getOwnerKey(targetModel)
	if sourceOwner and targetOwner and sourceOwner == targetOwner then
		return true
	end

	local sourceTeam = sourceModel:GetAttribute("Team")
	local targetTeam = targetModel:GetAttribute("Team")
	if sourceTeam ~= nil and targetTeam ~= nil and sourceTeam == targetTeam then
		return true
	end

	return false
end

local function buildIncludeParams(instances, maxParts)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = instances
	if typeof(maxParts) == "number" and maxParts > 0 then
		params.MaxParts = math.floor(maxParts)
	end
	return params
end

local function buildExcludeParams(instances, maxParts)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = instances
	if typeof(maxParts) == "number" and maxParts > 0 then
		params.MaxParts = math.floor(maxParts)
	end
	return params
end

local function appendMapRoots(target)
	local activeBossArena = Workspace:FindFirstChild("ActiveBossArena")
	if activeBossArena then
		table.insert(target, activeBossArena)
	end

	local map = Workspace:FindFirstChild("Map")
	if map then
		table.insert(target, map)
	end

	local world = Workspace:FindFirstChild("World")
	local worldMap = world and world:FindFirstChild("Map")
	if worldMap then
		for _, child in ipairs(worldMap:GetChildren()) do
			table.insert(target, child)
		end
	end

	if Workspace.Terrain then
		table.insert(target, Workspace.Terrain)
	end
end

local function getCharacterContainers()
	local containers = {}
	for _, folderName in ipairs(CHARACTER_CONTAINER_NAMES) do
		local folder = Workspace:FindFirstChild(folderName)
		if folder then
			table.insert(containers, folder)
		end
	end
	return containers
end

local function buildMapOverlapParams(maxParts)
	local include = {}
	appendMapRoots(include)
	return buildIncludeParams(include, maxParts)
end

local function buildBreakablesOverlapParams(maxParts)
	local include = {}

	local activeBossArena = Workspace:FindFirstChild("ActiveBossArena")
	local arenaBreakables = activeBossArena and activeBossArena:FindFirstChild("Breakables", true)
	if arenaBreakables then
		table.insert(include, arenaBreakables)
	end

	local map = Workspace:FindFirstChild("Map")
	if map then
		local breakables = map:FindFirstChild("Breakables")
		if breakables then
			table.insert(include, breakables)
		else
			table.insert(include, map)
		end
	end

	if #include <= 0 then
		appendMapRoots(include)
	end

	return buildIncludeParams(include, maxParts)
end

local function buildCharacterOverlapParams(excludeInstances, maxParts)
	local containers = getCharacterContainers()
	if #containers > 0 then
		return buildIncludeParams(containers, maxParts)
	end
	return buildExcludeParams(excludeInstances, maxParts)
end

local function buildMapAndCharactersOverlapParams(excludeInstances, maxParts)
	local include = getCharacterContainers()
	appendMapRoots(include)

	if #include > 0 then
		return buildIncludeParams(include, maxParts)
	end

	return buildExcludeParams(excludeInstances, maxParts)
end

local function buildMapRaycastParams(ignoreInstances)
	local params = RaycastParams.new()
	local include = {}
	appendMapRoots(include)

	if #include > 0 then
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = include
	else
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = ignoreInstances or {}
	end

	params.IgnoreWater = false
	return params
end

local function getGroundDistance(model, rootPart)
	if typeof(rootPart) ~= "Instance" or not rootPart:IsA("BasePart") then
		return math.huge
	end

	local result = Workspace:Raycast(rootPart.Position, Vector3.new(0, -GROUND_DISTANCE, 0), buildMapRaycastParams({ model }))
	if result then
		return (result.Position - rootPart.Position).Magnitude
	end

	return math.huge
end

function Hitbox:_warnInvalidQuery(reason)
	if self._invalidQueryReason == reason then
		return
	end
	self._invalidQueryReason = reason
	warn("[Hitbox] " .. tostring(reason))
end

function Hitbox:_usesRadiusQuery()
	return self.Data.HitboxShape == "Radius"
		or self.Data.QueryShape == "Radius"
		or self.Data.Shape == "Radius"
		or self.Data.HitboxRadius ~= nil
		or self.Data.Radius ~= nil
end

function Hitbox:_resolveRadius(hitboxSize)
	local radius, radiusError = resolveNumber(self.Data.HitboxRadius or self.Data.Radius)
	if radius then
		return math.max(0, radius), nil
	end
	if hitboxSize then
		return math.max(hitboxSize.X, hitboxSize.Y, hitboxSize.Z) * 0.5, nil
	end
	return nil, radiusError or "missing radius source"
end

function Hitbox:_resolveQueryData()
	local hitboxCFrame, cframeError = resolveCFrame(self.Data.HitboxCFrame)
	if not hitboxCFrame then
		self:_warnInvalidQuery("Missing or invalid HitboxCFrame (" .. tostring(cframeError) .. ")")
		return nil, nil, nil
	end

	local hitboxSize = nil
	local sizeError = nil
	if self.Data.HitboxSize ~= nil then
		hitboxSize, sizeError = resolveSize(self.Data.HitboxSize)
	end

	if not hitboxSize and not self:_usesRadiusQuery() then
		self:_warnInvalidQuery("Missing or invalid HitboxSize (" .. tostring(sizeError) .. ")")
		return nil, nil, nil
	end

	local hitboxRadius = nil
	if self:_usesRadiusQuery() then
		hitboxRadius, sizeError = self:_resolveRadius(hitboxSize)
		if not hitboxRadius then
			self:_warnInvalidQuery("Missing or invalid HitboxRadius (" .. tostring(sizeError) .. ")")
			return nil, nil, nil
		end
		if not hitboxSize then
			hitboxSize = Vector3.one * (hitboxRadius * 2)
		end
	end

	local hitboxOffset = self.Data.HitboxOffset or CFrame.new()
	return hitboxCFrame * hitboxOffset, hitboxSize, hitboxRadius
end

function Hitbox:_buildExcludeList()
	local exclude = {}
	local character = self:GetCharacter()
	if character then
		table.insert(exclude, character)
	end

	local visuals = Workspace:FindFirstChild("Visuals")
	if visuals then
		table.insert(exclude, visuals)
	end

	if self.Visualizer then
		table.insert(exclude, self.Visualizer)
	end

	if typeof(self.Data.IgnoreInstances) == "table" then
		for _, instance in ipairs(self.Data.IgnoreInstances) do
			if typeof(instance) == "Instance" then
				table.insert(exclude, instance)
			end
		end
	end

	return exclude
end

function Hitbox:_resolveOverlapParams(request)
	if typeof(request) == "OverlapParams" then
		return request
	end

	local requestName = request or "Characters"
	local maxParts = self.Data.MaxParts
	local exclude = self:_buildExcludeList()

	if requestName == "Map" then
		return buildMapOverlapParams(maxParts)
	end
	if requestName == "Breakables" then
		return buildBreakablesOverlapParams(maxParts)
	end
	if requestName == "MapAndCharacters" then
		return buildMapAndCharactersOverlapParams(exclude, maxParts)
	end

	return buildCharacterOverlapParams(exclude, maxParts)
end

function Hitbox:_queryParts(request)
	local hitboxLocation, hitboxSize, hitboxRadius = self:_resolveQueryData()
	if not hitboxLocation or not hitboxSize then
		return {}, nil, nil, nil
	end

	local overlapParams = self:_resolveOverlapParams(request)
	local parts
	if hitboxRadius and Workspace.GetPartBoundsInRadius then
		parts = Workspace:GetPartBoundsInRadius(hitboxLocation.Position, hitboxRadius, overlapParams)
	else
		parts = Workspace:GetPartBoundsInBox(hitboxLocation, hitboxSize, overlapParams)
	end

	return parts or {}, hitboxLocation, hitboxSize, hitboxRadius
end

function Hitbox:_scheduleCacheRelease(target)
	if typeof(self.Data.TickTime) ~= "number" or self.Data.TickTime <= 0 then
		return
	end

	task.delay(self.Data.TickTime, function()
		removeFromArray(self.HitCache, target)
	end)
end

function Hitbox:_dispatch(primaryName, ...)
	local callbacks = {}
	if self.Callbacks and self.Callbacks[primaryName] then
		table.insert(callbacks, self.Callbacks[primaryName])
	end
	if typeof(self.Data.Callback) == "function" then
		table.insert(callbacks, self.Data.Callback)
	end

	for _, callback in ipairs(callbacks) do
		spawnSafe(callback, ...)
	end
end

function Hitbox:GetCharacter()
	return resolveCharacterSource(self.Data.Character, self.Attack)
end

function Hitbox:_shouldIgnoreState(characterModel, rootPart, attributeName)
	local ignore = self.Data.Ignore
	if not ignore or not characterModel:GetAttribute(attributeName) then
		return false
	end

	local mode = ignore[attributeName]
	if mode == nil then
		return true
	end

	local groundDistance = getGroundDistance(characterModel, rootPart)
	if mode == "Air" then
		return groundDistance <= GROUND_STATE_THRESHOLD
	elseif mode == "Ground" then
		return groundDistance > GROUND_STATE_THRESHOLD
	end

	return false
end

function Hitbox:CheckCanHit(characterModel)
	if table.find(self.HitCache, characterModel) then
		return nil
	end
	if typeof(characterModel) ~= "Instance" or not characterModel:IsA("Model") or not characterModel.Parent then
		return nil
	end
	if characterModel:GetAttribute("HardDeath")
		or characterModel:GetAttribute("HardIFrames")
		or characterModel:GetAttribute("Disabled")
		or characterModel:GetAttribute("Dead")
		or characterModel:GetAttribute("Died") then
		return nil
	end

	local attackerCharacter = self:GetCharacter()
	if not attackerCharacter or attackerCharacter == characterModel then
		return nil
	end
	if not self.Data.AllowFriendlyFire and areFriendly(attackerCharacter, characterModel) then
		return nil
	end

	local humanoid = resolveHumanoid(characterModel)
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	local rootPart = resolveRootPart(characterModel, humanoid)
	if self:_shouldIgnoreState(characterModel, rootPart, "Ragdoll") then
		return nil
	end
	if self:_shouldIgnoreState(characterModel, rootPart, "IFrames") then
		return nil
	end

	return true
end

function Hitbox.HitboxTypes.ReturnMapBaseParts(self)
	self.HitboxTrove:Connect(RunService.Heartbeat, function()
		local hitAssets = self:_queryParts("Map")
		for _, asset in ipairs(hitAssets) do
			if asset:IsA("BasePart") and not table.find(self.HitCache, asset) then
				table.insert(self.HitCache, asset)
				self:_scheduleCacheRelease(asset)
				self:_dispatch("HitObject", asset, { TimeHit = os.clock() })
			end
		end
	end)
end

function Hitbox.HitboxTypes.ReturnHitboxPart(self)
	if not self.Visualizer then
		self:Visible(true)
	end

	self.HitboxTrove:Connect(RunService.Heartbeat, function()
		local hitboxLocation, hitboxSize, hitboxRadius = self:_resolveQueryData()
		if not hitboxLocation or not self.Visualizer then
			return
		end

		if hitboxRadius then
			self.Visualizer.Shape = Enum.PartType.Ball
			self.Visualizer.Size = Vector3.one * (hitboxRadius * 2)
		else
			self.Visualizer.Shape = Enum.PartType.Block
			self.Visualizer.Size = hitboxSize
		end
		self.Visualizer.CFrame = hitboxLocation
		self:_dispatch("HitObject", self.Visualizer, { TimeHit = os.clock() })
	end)
end

function Hitbox.HitboxTypes.CustomSpacialQuery(self)
	self.HitboxTrove:Connect(RunService.Heartbeat, function()
		local overlapRequest = self.Data.OverlapParams
		if overlapRequest == nil then
			overlapRequest = "Characters"
		end

		local hitParts = self:_queryParts(overlapRequest)
		for _, hitPart in ipairs(hitParts) do
			if not self.Data.Character or not hitPart:IsDescendantOf(self.Data.Character) then
				self:_dispatch("CustomHit", hitPart, { TimeHit = os.clock() })
			end
		end
	end)
end

function Hitbox.HitboxTypes.SpacialQuery(self)
	self.HitboxTrove:Connect(RunService.Heartbeat, function()
		if self.Destroyed then
			return
		end

		local hitParts, hitboxLocation, hitboxSize, hitboxRadius = self:_queryParts("Hitbox")
		if self.Data.EnvironmentDestruction then
			if hitboxRadius then
				self:EnvironmentDestruction(hitboxLocation, Vector3.one * (hitboxRadius * 2))
			else
				self:EnvironmentDestruction(hitboxLocation, hitboxSize)
			end
		end

		if self.Visualizer then
			if hitboxRadius then
				self.Visualizer.Shape = Enum.PartType.Ball
				self.Visualizer.Size = Vector3.one * (hitboxRadius * 2)
			else
				self.Visualizer.Shape = Enum.PartType.Block
				self.Visualizer.Size = hitboxSize
			end
			self.Visualizer.CFrame = hitboxLocation
		end

		self.HitCharacters = {}
		local seenThisFrame = {}
		for _, hitPart in ipairs(hitParts) do
			if self.Destroyed then
				return
			end

			if self.Data.Character and hitPart:IsDescendantOf(self.Data.Character) then
				continue
			end

			if self.Data.CrystalDamage and hitPart:GetAttribute("Health") ~= nil and CollectionService:HasTag(hitPart, "Crystal")
				and not self.CrystalCD then
				self.CrystalCD = true
				if typeof(self.Data.TickTime) == "number" and self.Data.TickTime > 0 then
					task.delay(self.Data.TickTime, function()
						self.CrystalCD = nil
					end)
				end
				hitPart:SetAttribute("Health", (tonumber(hitPart:GetAttribute("Health")) or 0) - (self.Data.CrystalDamage or 10))
			else
				local characterModel = resolveCharacterModelFromInstance(hitPart)
				if characterModel and not seenThisFrame[characterModel] and self:CheckCanHit(characterModel) then
					seenThisFrame[characterModel] = true
					self.HasTargets = true
					table.insert(self.HitCache, characterModel)
					self:_scheduleCacheRelease(characterModel)
					if #self.HitCache == 1 and self.Callbacks and self.Callbacks.FirstHitTarget then
						spawnSafe(self.Callbacks.FirstHitTarget, characterModel)
					end
					table.insert(self.HitCharacters, characterModel)
				end
			end
		end

		for _, characterModel in ipairs(self.HitCharacters) do
			self:_dispatch("HitTarget", characterModel, { TimeHit = os.clock() })
		end
	end)
end

function Hitbox.HitboxTypes.Breakables(self)
	self.HitboxTrove:Connect(RunService.Heartbeat, function()
		if self.Destroyed then
			return
		end

		local hitObjects, hitboxLocation, hitboxSize, hitboxRadius = self:_queryParts("Breakables")
		if self.Visualizer then
			if hitboxRadius then
				self.Visualizer.Shape = Enum.PartType.Ball
				self.Visualizer.Size = Vector3.one * (hitboxRadius * 2)
			else
				self.Visualizer.Shape = Enum.PartType.Block
				self.Visualizer.Size = hitboxSize
			end
			self.Visualizer.CFrame = hitboxLocation
		end

		for _, object in ipairs(hitObjects) do
			if self.Destroyed then
				return
			end
			if self.Data.Character and object:IsDescendantOf(self.Data.Character) then
				continue
			end

			local returnObject = object
			if object.Parent and object.Parent:IsA("Model") then
				returnObject = object.Parent
			end

			local parsedObject = nil
			if self.Data.EnvironmentDestruction then
				parsedObject = self:ParseObjectByPart(returnObject, self.Data.EnvironmentDestruction.Priority, true, nil)
			end

			if self.Data.EnvironmentDestruction and self.Data.EnvironmentDestruction.ReturnClones and parsedObject then
				spawnSafe(self.Data.EnvironmentDestruction.ReturnClones, returnObject)
			elseif self.Callbacks and self.Callbacks.HitObject then
				spawnSafe(self.Callbacks.HitObject, returnObject, { TimeHit = os.clock() })
			end
		end
	end)
end

function Hitbox.new(data, callbacks)
	data = data or {}

	local self = setmetatable({}, Hitbox)
	self.HitboxId = HttpService:GenerateGUID(false)
	self.HitCache = {}
	self.HitCharacters = {}
	self.Attack = data.Attack
	self.Type = data.Type
	self.Data = data
	self.Callbacks = callbacks or {}
	self.Destroying = Signal.new()
	self.HitboxTrove = Trove.new()
	self.HitboxState = Instance.new("StringValue")
	self.HitboxState.Value = "InActive"
	self.Data.HitboxOffset = self.Data.HitboxOffset or CFrame.new()

	Hitbox._activeHitboxes[self.HitboxId] = self

	if RunService:IsServer() and typeof(self.Attack) == "table" and typeof(self.Attack.CharacterProfile) == "table" then
		self.Attack.CharacterProfile._activeHitboxes = self.Attack.CharacterProfile._activeHitboxes or {}
		self.Attack.CharacterProfile._activeHitboxes[self.HitboxId] = self
	end

	if typeof(self.Data.StartDelay) == "number" and self.Data.StartDelay > 0 then
		task.delay(self.Data.StartDelay, function()
			if not self.Destroyed then
				self:Init()
			end
		end)
	else
		self:Init()
	end

	return self
end

function Hitbox:Init()
	if self.Destroyed then
		return
	end

	self.HitboxState.Value = "Active"
	self.HitboxInitilization = os.clock()

	local localPlayer = if RunService:IsClient() then Players.LocalPlayer else nil
	if localPlayer and localPlayer:GetAttribute("DisplayHitbox") then
		self:Visible(true)
	end

	local hitboxTypeName = self.Data.HitboxType or "SpacialQuery"
	local hitboxType = Hitbox.HitboxTypes[hitboxTypeName]
	if not hitboxType then
		warn("[Hitbox] Unknown HitboxType: " .. tostring(hitboxTypeName))
		return
	end

	if typeof(self.Data.Time) == "number" and self.Data.Time > 0 then
		task.delay(self.Data.Time, function()
			self:Destroy()
		end)
	end

	hitboxType(self)
end

function Hitbox:EnvironmentDestruction(location, size)
	if self.Data.Debug then
		warn("[Hitbox] EnvironmentDestruction is not wired for this project", location, size)
	end
	return nil
end

function Hitbox:ParseObjectByPart(detected)
	return detected
end

function Hitbox:Visible(enabled)
	if enabled then
		if self.Visualizer then
			return self
		end

		if not self.HitboxInitilization then
			repeat
				task.wait()
			until self.HitboxInitilization or self.Destroyed
		end
		if self.Destroyed then
			return self
		end

		local visualizer = Instance.new("Part")
		visualizer.Name = "HitboxVisualizer"
		visualizer.Anchored = true
		visualizer.CanCollide = false
		visualizer.CanTouch = false
		visualizer.CanQuery = false
		visualizer.Color = Color3.fromRGB(170, 0, 0)
		visualizer.Transparency = 0.5
		visualizer.Massless = true

		local _, hitboxSize, hitboxRadius = self:_resolveQueryData()
		if hitboxRadius then
			visualizer.Shape = Enum.PartType.Ball
			visualizer.Size = Vector3.one * (hitboxRadius * 2)
		elseif hitboxSize then
			visualizer.Shape = Enum.PartType.Block
			visualizer.Size = hitboxSize
		else
			return self
		end

		visualizer.Parent = getVisualizerFolder()
		self.HitboxTrove:Add(visualizer)
		self.Visualizer = visualizer
	else
		if self.Visualizer then
			self.HitboxTrove:Remove(self.Visualizer)
			self.Visualizer:Destroy()
			self.Visualizer = nil
		end
	end

	return self
end

function Hitbox:Destroy()
	if self.Destroyed then
		return
	end

	self.Destroyed = true
	self.Destroying:Fire()
	self.HitboxTrove:Destroy()
	self.HitboxState.Value = "InActive"

	if self.Callbacks and self.Callbacks.HitboxDestroy then
		spawnSafe(self.Callbacks.HitboxDestroy, self.HitCache)
	end

	Hitbox._activeHitboxes[self.HitboxId] = nil
	if RunService:IsServer()
		and typeof(self.Attack) == "table"
		and typeof(self.Attack.CharacterProfile) == "table"
		and typeof(self.Attack.CharacterProfile._activeHitboxes) == "table" then
		self.Attack.CharacterProfile._activeHitboxes[self.HitboxId] = nil
	end

	if self.Destroying and self.Destroying.DisconnectAll then
		self.Destroying:DisconnectAll()
	end
end

return Hitbox
