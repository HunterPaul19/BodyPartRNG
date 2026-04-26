local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Signal = require(ReplicatedStorage.Common.Signal)
local Trove = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Utilities.Trove)

local Hitbox = {}
Hitbox.__index = Hitbox
Hitbox._activeHitboxes = {}
Hitbox.HitboxTypes = {}

local VISUALIZER_FOLDER_NAME = "VisualizedHitboxes"
local BODY_PART_VISUALS_FOLDER_NAME = "CharacterBodyParts"
local GROUND_DISTANCE = 200
local GROUND_STATE_THRESHOLD = 2
local OBB_EPSILON = 1e-6
local PYRAMID_DEFAULT_LAYERS = 8
local PYRAMID_MIN_LAYERS = 1
local PYRAMID_MAX_LAYERS = 24
local GROUND_SHOCKWAVE_RAYCAST_LIFT = 8
local GROUND_SHOCKWAVE_SPECIAL_MESH_DIAMETER_PER_PART_STUD = 85
local ROOT_PART_NAMES = { "HumanoidRootPart", "UpperTorso", "LowerTorso", "Torso", "Head" }
local CHARACTER_CONTAINER_NAMES = { "Bosses", "Mobs", "Characters", "NPCs", "ActiveBoss", "ActiveBossMinions" }

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
			Logger.Warn("[Hitbox] Callback error:", err)
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

local function addUniqueInstance(target, seen, instance)
	if typeof(instance) ~= "Instance" or seen[instance] == true then
		return
	end

	seen[instance] = true
	table.insert(target, instance)
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

local function appendLivePlayerCharacters(target, seen)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character and character.Parent then
			addUniqueInstance(target, seen, character)
		end
	end
end

local function appendWorkspaceCharacterModels(target, seen)
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("Model") and resolveHumanoid(child) then
			addUniqueInstance(target, seen, child)
		end
	end
end

local function getCharacterQueryRoots()
	local roots = {}
	local seen = {}

	appendLivePlayerCharacters(roots, seen)
	appendWorkspaceCharacterModels(roots, seen)

	for _, container in ipairs(getCharacterContainers()) do
		addUniqueInstance(roots, seen, container)
	end

	return roots
end

local function collectPotentialCharacterModels()
	local characters = {}
	local seen = {}

	appendLivePlayerCharacters(characters, seen)
	appendWorkspaceCharacterModels(characters, seen)

	for _, container in ipairs(getCharacterContainers()) do
		if container:IsA("Model") and resolveHumanoid(container) then
			addUniqueInstance(characters, seen, container)
		end

		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Model") and resolveHumanoid(child) then
				addUniqueInstance(characters, seen, child)
			end
		end
	end

	return characters
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
	local roots = getCharacterQueryRoots()
	if #roots > 0 then
		return buildIncludeParams(roots, maxParts)
	end
	return buildExcludeParams(excludeInstances, maxParts)
end

local function buildMapAndCharactersOverlapParams(excludeInstances, maxParts)
	local include = getCharacterQueryRoots()
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

local function addUniquePart(target, seen, part)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or seen[part] == true then
		return
	end

	seen[part] = true
	table.insert(target, part)
end

local function resolveGroundAlignedPosition(sourcePosition, ignoreInstances)
	local rayOrigin = sourcePosition + Vector3.new(0, GROUND_SHOCKWAVE_RAYCAST_LIFT, 0)
	local rayDirection = Vector3.new(0, -(GROUND_DISTANCE + (GROUND_SHOCKWAVE_RAYCAST_LIFT * 2)), 0)
	local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, buildMapRaycastParams(ignoreInstances))

	if raycastResult then
		return raycastResult.Position
	end

	return sourcePosition
end

local function updateStandardVisualizer(visualizer, hitboxLocation, hitboxSize, hitboxRadius)
	if typeof(visualizer) ~= "Instance" or not visualizer:IsA("BasePart") or not hitboxLocation then
		return
	end

	if hitboxRadius then
		visualizer.Shape = Enum.PartType.Ball
		visualizer.Size = Vector3.one * (hitboxRadius * 2)
	else
		visualizer.Shape = Enum.PartType.Block
		visualizer.Size = hitboxSize
	end

	visualizer.CFrame = hitboxLocation
end

local function isPyramidShape(data)
	local shape = data.HitboxShape or data.QueryShape or data.Shape
	return shape == "Pyramid" or shape == "Cone"
end

local function resolvePyramidLayers(self)
	local hitboxCFrame, cframeError = resolveCFrame(self.Data.HitboxCFrame)
	if not hitboxCFrame then
		self:_warnInvalidQuery("Missing or invalid HitboxCFrame (" .. tostring(cframeError) .. ")")
		return nil
	end

	local distance, distanceError = resolveNumber(self.Data.PyramidDistance or self.Data.ConeDistance)
	if not distance then
		self:_warnInvalidQuery("Missing or invalid PyramidDistance (" .. tostring(distanceError) .. ")")
		return nil
	end

	local width, widthError = resolveNumber(self.Data.PyramidWidth or self.Data.ConeWidth or self.Data.BottomWidth)
	if not width then
		self:_warnInvalidQuery("Missing or invalid PyramidWidth (" .. tostring(widthError) .. ")")
		return nil
	end

	distance = math.max(0, distance)
	width = math.max(0, width)
	if distance <= 0 or width <= 0 then
		self:_warnInvalidQuery("PyramidDistance and PyramidWidth must be greater than zero.")
		return nil
	end

	local layerCount = math.floor(tonumber(self.Data.PyramidLayers) or PYRAMID_DEFAULT_LAYERS)
	layerCount = math.clamp(layerCount, PYRAMID_MIN_LAYERS, PYRAMID_MAX_LAYERS)

	local apexCFrame = hitboxCFrame * (self.Data.HitboxOffset or CFrame.new())
	local layerDepth = distance / layerCount
	local layers = {}

	for index = 1, layerCount do
		local farDistance = layerDepth * index
		local midpointDistance = farDistance - (layerDepth * 0.5)
		local layerWidth = math.max(0.001, width * (farDistance / distance))

		table.insert(layers, {
			CFrame = apexCFrame * CFrame.new(0, 0, -midpointDistance),
			Size = Vector3.new(layerWidth, layerWidth, layerDepth),
		})
	end

	return {
		ApexCFrame = apexCFrame,
		Distance = distance,
		Width = width,
		LayerCount = layerCount,
		Layers = layers,
	}
end

local function updatePyramidVisualizer(self, pyramidState)
	local visualizer = self.Visualizer
	if typeof(visualizer) ~= "Instance" or not visualizer:IsA("Folder") or not pyramidState then
		return
	end

	for index, layer in ipairs(pyramidState.Layers) do
		local part = visualizer:FindFirstChild(string.format("Layer%02d", index))
		if not (part and part:IsA("BasePart")) then
			part = Instance.new("Part")
			part.Name = string.format("Layer%02d", index)
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Color = Color3.fromRGB(170, 0, 0)
			part.Transparency = 0.5
			part.Massless = true
			part.Parent = visualizer
		end

		part.Shape = Enum.PartType.Block
		part.Size = layer.Size
		part.CFrame = layer.CFrame
	end

	for _, child in ipairs(visualizer:GetChildren()) do
		if child:IsA("BasePart") then
			local layerIndex = tonumber(string.match(child.Name, "^Layer(%d+)$"))
			if not layerIndex or layerIndex > pyramidState.LayerCount then
				child:Destroy()
			end
		end
	end
end

local function buildPyramidVisualizer(self, pyramidState)
	local visualizer = Instance.new("Folder")
	visualizer.Name = "PyramidHitboxVisualizer"
	visualizer.Parent = getVisualizerFolder()
	self.HitboxTrove:Add(visualizer)
	self.Visualizer = visualizer

	updatePyramidVisualizer(self, pyramidState)
end

local function resolveInstanceByPath(path)
	if typeof(path) ~= "string" or path == "" then
		return nil
	end

	local current = game
	for segment in string.gmatch(path, "[^%.]+") do
		current = current:FindFirstChild(segment)
		if current == nil then
			return nil
		end
	end

	return current
end

local function resolveGroundShockwaveVisualTemplate(self)
	local template = self.Data.VisualTemplate
	if typeof(template) == "function" then
		local ok, resolved = pcall(template)
		if ok then
			template = resolved
		else
			template = nil
		end
	end

	if typeof(template) == "Instance" then
		return template
	end

	local templatePath = self.Data.VisualTemplatePath
	if typeof(templatePath) == "string" and templatePath ~= "" then
		return resolveInstanceByPath(templatePath)
	end

	return nil
end

local function resolveGroundShockwaveState(self)
	local hitboxCFrame, cframeError = resolveCFrame(self.Data.HitboxCFrame)
	if not hitboxCFrame then
		self:_warnInvalidQuery("Missing or invalid HitboxCFrame (" .. tostring(cframeError) .. ")")
		return nil
	end

	local startRadius, startRadiusError = resolveNumber(self.Data.StartRadius)
	if not startRadius then
		self:_warnInvalidQuery("Missing or invalid StartRadius (" .. tostring(startRadiusError) .. ")")
		return nil
	end

	local endRadius = startRadius
	if self.Data.EndRadius ~= nil then
		local resolvedEndRadius, endRadiusError = resolveNumber(self.Data.EndRadius)
		if not resolvedEndRadius then
			self:_warnInvalidQuery("Missing or invalid EndRadius (" .. tostring(endRadiusError) .. ")")
			return nil
		end
		endRadius = resolvedEndRadius
	end

	local ringThickness, thicknessError = resolveNumber(self.Data.RingThickness)
	if not ringThickness then
		self:_warnInvalidQuery("Missing or invalid RingThickness (" .. tostring(thicknessError) .. ")")
		return nil
	end

	local hitboxHeight, heightError = resolveNumber(self.Data.HitboxHeight)
	if not hitboxHeight then
		self:_warnInvalidQuery("Missing or invalid HitboxHeight (" .. tostring(heightError) .. ")")
		return nil
	end

	local groundOffset = tonumber(self.Data.GroundOffset)
	if groundOffset == nil then
		groundOffset = 0.15
	end

	local sourceCFrame = hitboxCFrame * (self.Data.HitboxOffset or CFrame.new())
	local ignoreInstances = {}
	local character = self:GetCharacter()
	if character then
		table.insert(ignoreInstances, character)
	end
	if self.Visualizer then
		table.insert(ignoreInstances, self.Visualizer)
	end

	local alignedGroundPosition = resolveGroundAlignedPosition(sourceCFrame.Position, ignoreInstances)
	local groundPosition = Vector3.new(
		sourceCFrame.Position.X,
		alignedGroundPosition.Y + groundOffset,
		sourceCFrame.Position.Z
	)

	local duration = tonumber(self.Data.Time) or 0
	local alpha = 1
	if duration > 0 and self.HitboxInitilization then
		alpha = math.clamp((os.clock() - self.HitboxInitilization) / duration, 0, 1)
	end

	local currentRadius = math.max(0, startRadius + ((endRadius - startRadius) * alpha))
	local outerRadius = math.max(0, currentRadius + (ringThickness * 0.5))
	local queryPosition = groundPosition + Vector3.new(0, hitboxHeight * 0.5, 0)

	return {
		Alpha = alpha,
		GroundPosition = groundPosition,
		QueryCFrame = CFrame.new(queryPosition),
		QuerySize = Vector3.new(outerRadius * 2, hitboxHeight, outerRadius * 2),
		GroundY = groundPosition.Y,
		CurrentRadius = currentRadius,
		InnerRadius = math.max(0, currentRadius - (ringThickness * 0.5)),
		OuterRadius = outerRadius,
		HitboxHeight = math.max(0.1, hitboxHeight),
		RingThickness = math.max(0.1, ringThickness),
	}
end

local function resolveGroundShockwaveVisualizerSize(baseSize, usesSpecialMeshScale, outerRadius, hitboxHeight)
	local baseDiameter = math.max(baseSize.X, baseSize.Z)
	if baseDiameter <= 0.001 then
		return nil
	end

	local scale = (outerRadius * 2) / baseDiameter
	local visualHeight = math.max(baseSize.Y, hitboxHeight)
	local resolvedSize = Vector3.new(baseSize.X * scale, visualHeight, baseSize.Z * scale)
	if usesSpecialMeshScale == true then
		resolvedSize = resolvedSize / GROUND_SHOCKWAVE_SPECIAL_MESH_DIAMETER_PER_PART_STUD
	end

	return resolvedSize
end

local function buildGroundShockwaveVisualizer(self, shockwaveState)
	local template = resolveGroundShockwaveVisualTemplate(self)
	if typeof(template) ~= "Instance" then
		Logger.Warn("[Hitbox] GroundShockwave missing VisualTemplate/VisualTemplatePath asset.")
		return
	end

	local visualizer = template:Clone()
	visualizer.Name = "GroundShockwaveVisualizer"

	if visualizer:IsA("BasePart") then
		visualizer.Anchored = true
		visualizer.CanCollide = false
		visualizer.CanTouch = false
		visualizer.CanQuery = false
		visualizer.CastShadow = false
		visualizer.Massless = true
		local specialMesh = visualizer:FindFirstChildOfClass("SpecialMesh")
		if specialMesh then
			self._groundShockwaveVisualizerBaseSize = Vector3.new(
				GROUND_SHOCKWAVE_SPECIAL_MESH_DIAMETER_PER_PART_STUD,
				GROUND_SHOCKWAVE_SPECIAL_MESH_DIAMETER_PER_PART_STUD,
				GROUND_SHOCKWAVE_SPECIAL_MESH_DIAMETER_PER_PART_STUD
			)
			self._groundShockwaveVisualizerUsesSpecialMeshScale = true
		else
			self._groundShockwaveVisualizerBaseSize = visualizer.Size
			self._groundShockwaveVisualizerUsesSpecialMeshScale = false
		end
	elseif visualizer:IsA("Model") then
		for _, descendant in ipairs(visualizer:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanTouch = false
				descendant.CanQuery = false
				descendant.CastShadow = false
				descendant.Massless = true
			end
		end
		local _, baseSize = visualizer:GetBoundingBox()
		self._groundShockwaveVisualizerBaseSize = baseSize
		self._groundShockwaveVisualizerUsesSpecialMeshScale = false
	else
		Logger.Warn("[Hitbox] GroundShockwave visual asset must be a BasePart or Model.")
		visualizer:Destroy()
		return
	end

	visualizer.Parent = getVisualizerFolder()
	self.HitboxTrove:Add(visualizer)
	self.Visualizer = visualizer

	if visualizer:IsA("BasePart") then
		local duration = math.max(0, tonumber(self.Data.Time) or 0)
		local startSize = resolveGroundShockwaveVisualizerSize(
			self._groundShockwaveVisualizerBaseSize,
			self._groundShockwaveVisualizerUsesSpecialMeshScale,
			shockwaveState.OuterRadius,
			shockwaveState.HitboxHeight
		)
		if startSize then
			visualizer.Size = startSize
			local visualHeight = math.max(startSize.Y, shockwaveState.HitboxHeight)
			local position = shockwaveState.GroundPosition + Vector3.new(0, visualHeight * 0.5, 0)
			local rotation = if typeof(self.Data.VisualRotation) == "CFrame" then self.Data.VisualRotation else CFrame.new()
			visualizer.CFrame = CFrame.new(position) * rotation
		end
		if duration > 0 and startSize then
			local endRadius = select(1, resolveNumber(self.Data.EndRadius))
			local ringThickness = select(1, resolveNumber(self.Data.RingThickness)) or shockwaveState.RingThickness
			local hitboxHeight = select(1, resolveNumber(self.Data.HitboxHeight)) or shockwaveState.HitboxHeight
			local finalOuterRadius = math.max(0, (endRadius or shockwaveState.CurrentRadius) + (ringThickness * 0.5))
			local finalSize = resolveGroundShockwaveVisualizerSize(
				self._groundShockwaveVisualizerBaseSize,
				self._groundShockwaveVisualizerUsesSpecialMeshScale,
				finalOuterRadius,
				math.max(0.1, hitboxHeight)
			)

			if finalSize then
				local tween = TweenService:Create(
					visualizer,
					TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
					{ Size = finalSize }
				)
				self.HitboxTrove:Add(tween)
				tween:Play()
				self._groundShockwaveVisualizerTween = tween
			end
		end
	end
end

local function updateGroundShockwaveVisualizer(self, shockwaveState, visualizerOverride)
	local visualizer = visualizerOverride or self.Visualizer
	if typeof(visualizer) ~= "Instance" then
		return
	end

	local baseSize = self._groundShockwaveVisualizerBaseSize
	if typeof(baseSize) ~= "Vector3" then
		return
	end

	local baseDiameter = math.max(baseSize.X, baseSize.Z)
	if baseDiameter <= 0.001 then
		return
	end

	local resolvedSize = resolveGroundShockwaveVisualizerSize(
		baseSize,
		self._groundShockwaveVisualizerUsesSpecialMeshScale,
		shockwaveState.OuterRadius,
		shockwaveState.HitboxHeight
	)
	if not resolvedSize then
		return
	end
	local position = shockwaveState.GroundPosition + Vector3.new(0, resolvedSize.Y * 0.5, 0)
	local rotation = if typeof(self.Data.VisualRotation) == "CFrame" then self.Data.VisualRotation else CFrame.new()

	if visualizer:IsA("BasePart") then
		if not self._groundShockwaveVisualizerTween then
			visualizer.Size = resolvedSize
		end
		visualizer.CFrame = CFrame.new(position) * rotation
	elseif visualizer:IsA("Model") then
		local scale = (shockwaveState.OuterRadius * 2) / baseDiameter
		visualizer:ScaleTo(scale)
		visualizer:PivotTo(CFrame.new(position) * rotation)
	end

	return resolvedSize
end

local function getVisualProxyParts(characterModel)
	if typeof(characterModel) ~= "Instance" or not characterModel:IsA("Model") then
		return {}
	end

	local folder = characterModel:FindFirstChild(BODY_PART_VISUALS_FOLDER_NAME)
	if not (folder and folder:IsA("Folder")) then
		return {}
	end

	local parts = {}
	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	return parts
end

local function partIntersectsGroundShockwave(part, shockwaveState)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return false
	end

	local halfHeight = math.abs(part.Size.Y) * 0.5
	local minY = part.Position.Y - halfHeight
	local maxY = part.Position.Y + halfHeight
	local hitboxMinY = shockwaveState.GroundY
	local hitboxMaxY = shockwaveState.GroundY + shockwaveState.HitboxHeight
	if maxY < hitboxMinY or minY > hitboxMaxY then
		return false
	end

	local planarOffset = Vector3.new(
		part.Position.X - shockwaveState.GroundPosition.X,
		0,
		part.Position.Z - shockwaveState.GroundPosition.Z
	)
	local planarDistance = planarOffset.Magnitude
	local planarPadding = math.max(math.abs(part.Size.X), math.abs(part.Size.Z)) * 0.5

	if planarDistance + planarPadding < shockwaveState.InnerRadius then
		return false
	end
	if planarDistance - planarPadding > shockwaveState.OuterRadius then
		return false
	end

	return true
end

local function characterIntersectsGroundShockwave(self, characterModel, shockwaveState, initialParts)
	local humanoid = resolveHumanoid(characterModel)
	local rootPart = resolveRootPart(characterModel, humanoid)
	local parts = {}
	local seen = {}

	addUniquePart(parts, seen, rootPart)

	if typeof(initialParts) == "table" then
		for _, part in ipairs(initialParts) do
			addUniquePart(parts, seen, part)
		end
	end

	if self:_shouldDetectVisualProxyParts() then
		for _, proxyPart in ipairs(getVisualProxyParts(characterModel)) do
			addUniquePart(parts, seen, proxyPart)
		end
	end

	for _, part in ipairs(parts) do
		if partIntersectsGroundShockwave(part, shockwaveState) then
			return true
		end
	end

	return false
end

local function pointToObjectSpace(cframe, point)
	return cframe:PointToObjectSpace(point)
end

local function sphereIntersectsBox(position, radius, boxCFrame, boxSize)
	local half = boxSize * 0.5
	local localPoint = pointToObjectSpace(boxCFrame, position)
	local clampedX = math.clamp(localPoint.X, -half.X, half.X)
	local clampedY = math.clamp(localPoint.Y, -half.Y, half.Y)
	local clampedZ = math.clamp(localPoint.Z, -half.Z, half.Z)
	local deltaX = localPoint.X - clampedX
	local deltaY = localPoint.Y - clampedY
	local deltaZ = localPoint.Z - clampedZ

	return (deltaX * deltaX) + (deltaY * deltaY) + (deltaZ * deltaZ) <= (radius * radius)
end

local function boxesIntersect(cframeA, sizeA, cframeB, sizeB)
	local a = { math.abs(sizeA.X) * 0.5, math.abs(sizeA.Y) * 0.5, math.abs(sizeA.Z) * 0.5 }
	local b = { math.abs(sizeB.X) * 0.5, math.abs(sizeB.Y) * 0.5, math.abs(sizeB.Z) * 0.5 }

	local axesA = { cframeA.XVector, cframeA.YVector, cframeA.ZVector }
	local axesB = { cframeB.XVector, cframeB.YVector, cframeB.ZVector }
	local rotation = { {}, {}, {} }
	local absRotation = { {}, {}, {} }

	for i = 1, 3 do
		for j = 1, 3 do
			local value = axesA[i]:Dot(axesB[j])
			rotation[i][j] = value
			absRotation[i][j] = math.abs(value) + OBB_EPSILON
		end
	end

	local translationVector = cframeB.Position - cframeA.Position
	local translation = {
		translationVector:Dot(axesA[1]),
		translationVector:Dot(axesA[2]),
		translationVector:Dot(axesA[3]),
	}

	for i = 1, 3 do
		local radiusA = a[i]
		local radiusB = b[1] * absRotation[i][1] + b[2] * absRotation[i][2] + b[3] * absRotation[i][3]
		if math.abs(translation[i]) > radiusA + radiusB then
			return false
		end
	end

	for j = 1, 3 do
		local radiusA = a[1] * absRotation[1][j] + a[2] * absRotation[2][j] + a[3] * absRotation[3][j]
		local radiusB = b[j]
		local projectedTranslation =
			math.abs(translation[1] * rotation[1][j] + translation[2] * rotation[2][j] + translation[3] * rotation[3][j])
		if projectedTranslation > radiusA + radiusB then
			return false
		end
	end

	local radiusA = a[2] * absRotation[3][1] + a[3] * absRotation[2][1]
	local radiusB = b[2] * absRotation[1][3] + b[3] * absRotation[1][2]
	if math.abs(translation[3] * rotation[2][1] - translation[2] * rotation[3][1]) > radiusA + radiusB then
		return false
	end

	radiusA = a[2] * absRotation[3][2] + a[3] * absRotation[2][2]
	radiusB = b[1] * absRotation[1][3] + b[3] * absRotation[1][1]
	if math.abs(translation[3] * rotation[2][2] - translation[2] * rotation[3][2]) > radiusA + radiusB then
		return false
	end

	radiusA = a[2] * absRotation[3][3] + a[3] * absRotation[2][3]
	radiusB = b[1] * absRotation[1][2] + b[2] * absRotation[1][1]
	if math.abs(translation[3] * rotation[2][3] - translation[2] * rotation[3][3]) > radiusA + radiusB then
		return false
	end

	radiusA = a[1] * absRotation[3][1] + a[3] * absRotation[1][1]
	radiusB = b[2] * absRotation[2][3] + b[3] * absRotation[2][2]
	if math.abs(translation[1] * rotation[3][1] - translation[3] * rotation[1][1]) > radiusA + radiusB then
		return false
	end

	radiusA = a[1] * absRotation[3][2] + a[3] * absRotation[1][2]
	radiusB = b[1] * absRotation[2][3] + b[3] * absRotation[2][1]
	if math.abs(translation[1] * rotation[3][2] - translation[3] * rotation[1][2]) > radiusA + radiusB then
		return false
	end

	radiusA = a[1] * absRotation[3][3] + a[3] * absRotation[1][3]
	radiusB = b[1] * absRotation[2][2] + b[2] * absRotation[2][1]
	if math.abs(translation[1] * rotation[3][3] - translation[3] * rotation[1][3]) > radiusA + radiusB then
		return false
	end

	radiusA = a[1] * absRotation[2][1] + a[2] * absRotation[1][1]
	radiusB = b[2] * absRotation[3][3] + b[3] * absRotation[3][2]
	if math.abs(translation[2] * rotation[1][1] - translation[1] * rotation[2][1]) > radiusA + radiusB then
		return false
	end

	radiusA = a[1] * absRotation[2][2] + a[2] * absRotation[1][2]
	radiusB = b[1] * absRotation[3][3] + b[3] * absRotation[3][1]
	if math.abs(translation[2] * rotation[1][2] - translation[1] * rotation[2][2]) > radiusA + radiusB then
		return false
	end

	radiusA = a[1] * absRotation[2][3] + a[2] * absRotation[1][3]
	radiusB = b[1] * absRotation[3][2] + b[2] * absRotation[3][1]
	if math.abs(translation[2] * rotation[1][3] - translation[1] * rotation[2][3]) > radiusA + radiusB then
		return false
	end

	return true
end

local function intersectsPartBounds(hitboxLocation, hitboxSize, hitboxRadius, part)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return false
	end

	if hitboxRadius then
		return sphereIntersectsBox(hitboxLocation.Position, hitboxRadius, part.CFrame, part.Size)
	end

	return boxesIntersect(hitboxLocation, hitboxSize, part.CFrame, part.Size)
end

local function intersectsPyramidLayers(pyramidState, part)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or typeof(pyramidState) ~= "table" then
		return false
	end

	for _, layer in ipairs(pyramidState.Layers or {}) do
		if boxesIntersect(layer.CFrame, layer.Size, part.CFrame, part.Size) then
			return true
		end
	end

	return false
end

function Hitbox:_warnInvalidQuery(reason)
	if self._invalidQueryReason == reason then
		return
	end
	self._invalidQueryReason = reason
	Logger.Warn("[Hitbox] " .. tostring(reason))
end

function Hitbox:_usesPyramidQuery()
	return isPyramidShape(self.Data)
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

	if not hitboxSize and not self:_usesRadiusQuery() and not self:_usesPyramidQuery() then
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
	if self:_usesPyramidQuery() then
		local pyramidState = resolvePyramidLayers(self)
		if not pyramidState then
			return {}, nil, nil, nil, nil
		end

		local overlapParams = self:_resolveOverlapParams(request)
		local parts = {}
		local seen = {}
		for _, layer in ipairs(pyramidState.Layers) do
			local layerParts = Workspace:GetPartBoundsInBox(layer.CFrame, layer.Size, overlapParams)
			for _, part in ipairs(layerParts or {}) do
				addUniquePart(parts, seen, part)
			end
		end

		return parts, pyramidState.ApexCFrame, nil, nil, pyramidState
	end

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

function Hitbox:_shouldDetectVisualProxyParts()
	return self.Data.DetectVisualProxyParts ~= false
end

function Hitbox:_hasDebugVisibilityAttribute()
	return typeof(self.Data.DebugVisibilityAttribute) == "string" and self.Data.DebugVisibilityAttribute ~= ""
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

function Hitbox:_registerHitCharacter(characterModel, seenThisFrame)
	if typeof(characterModel) ~= "Instance" or not characterModel:IsA("Model") then
		return false
	end
	if seenThisFrame[characterModel] or not self:CheckCanHit(characterModel) then
		return false
	end

	seenThisFrame[characterModel] = true
	self.HasTargets = true
	table.insert(self.HitCache, characterModel)
	self:_scheduleCacheRelease(characterModel)
	if #self.HitCache == 1 and self.Callbacks and self.Callbacks.FirstHitTarget then
		spawnSafe(self.Callbacks.FirstHitTarget, characterModel)
	end
	table.insert(self.HitCharacters, characterModel)
	return true
end

function Hitbox:_detectVisualProxyHits(hitboxLocation, hitboxSize, hitboxRadius, seenThisFrame, pyramidState)
	if not self:_shouldDetectVisualProxyParts() then
		return
	end

	for _, characterModel in ipairs(collectPotentialCharacterModels()) do
		if not seenThisFrame[characterModel] and self:CheckCanHit(characterModel) then
			for _, proxyPart in ipairs(getVisualProxyParts(characterModel)) do
				local intersects = if pyramidState
					then intersectsPyramidLayers(pyramidState, proxyPart)
					else intersectsPartBounds(hitboxLocation, hitboxSize, hitboxRadius, proxyPart)
				if intersects then
					self:_registerHitCharacter(characterModel, seenThisFrame)
					break
				end
			end
		end
	end
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
	if not self.Visualizer and not self:_hasDebugVisibilityAttribute() then
		self:Visible(true)
	end

	self.HitboxTrove:Connect(RunService.Heartbeat, function()
		local _, hitboxLocation, hitboxSize, hitboxRadius, pyramidState = self:_queryParts("Hitbox")
		if (not hitboxLocation and not pyramidState) or not self.Visualizer then
			return
		end

		if pyramidState then
			updatePyramidVisualizer(self, pyramidState)
		else
			updateStandardVisualizer(self.Visualizer, hitboxLocation, hitboxSize, hitboxRadius)
		end
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

		local hitParts, hitboxLocation, hitboxSize, hitboxRadius, pyramidState = self:_queryParts("Hitbox")
		if not hitboxLocation and not pyramidState then
			return
		end

		if self.Data.EnvironmentDestruction then
			if pyramidState then
				self:EnvironmentDestruction(hitboxLocation, Vector3.new(pyramidState.Width, pyramidState.Width, pyramidState.Distance))
			elseif hitboxRadius then
				self:EnvironmentDestruction(hitboxLocation, Vector3.one * (hitboxRadius * 2))
			else
				self:EnvironmentDestruction(hitboxLocation, hitboxSize)
			end
		end

		if self.Visualizer then
			if pyramidState then
				updatePyramidVisualizer(self, pyramidState)
			else
				updateStandardVisualizer(self.Visualizer, hitboxLocation, hitboxSize, hitboxRadius)
			end
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
				if characterModel then
					self:_registerHitCharacter(characterModel, seenThisFrame)
				end
			end
		end

		self:_detectVisualProxyHits(hitboxLocation, hitboxSize, hitboxRadius, seenThisFrame, pyramidState)

		for _, characterModel in ipairs(self.HitCharacters) do
			self:_dispatch("HitTarget", characterModel, { TimeHit = os.clock() })
		end
	end)
end

function Hitbox.HitboxTypes.GroundShockwave(self)
	if not self.Visualizer and not self:_hasDebugVisibilityAttribute() then
		self:Visible(true)
	end

	self.HitboxTrove:Connect(RunService.Heartbeat, function()
		if self.Destroyed then
			return
		end

		local shockwaveState = resolveGroundShockwaveState(self)
		if not shockwaveState then
			return
		end

		if self.Visualizer then
			updateGroundShockwaveVisualizer(self, shockwaveState)
		end

		local overlapParams = self:_resolveOverlapParams("Hitbox")
		local hitParts = {}
		if Workspace.GetPartBoundsInRadius then
			hitParts = Workspace:GetPartBoundsInRadius(shockwaveState.QueryCFrame.Position, shockwaveState.OuterRadius, overlapParams)
				or {}
		else
			hitParts = Workspace:GetPartBoundsInBox(shockwaveState.QueryCFrame, shockwaveState.QuerySize, overlapParams) or {}
		end

		self.HitCharacters = {}
		local seenThisFrame = {}
		local partsByCharacter = {}

		for _, hitPart in ipairs(hitParts) do
			if self.Destroyed then
				return
			end

			if self.Data.Character and hitPart:IsDescendantOf(self.Data.Character) then
				continue
			end

			local characterModel = resolveCharacterModelFromInstance(hitPart)
			if characterModel then
				partsByCharacter[characterModel] = partsByCharacter[characterModel] or {}
				if hitPart:IsA("BasePart") then
					table.insert(partsByCharacter[characterModel], hitPart)
				end
			end
		end

		for characterModel, candidateParts in pairs(partsByCharacter) do
			if self:CheckCanHit(characterModel)
				and characterIntersectsGroundShockwave(self, characterModel, shockwaveState, candidateParts) then
				self:_registerHitCharacter(characterModel, seenThisFrame)
			end
		end

		if self:_shouldDetectVisualProxyParts() then
			for _, characterModel in ipairs(collectPotentialCharacterModels()) do
				if not seenThisFrame[characterModel]
					and partsByCharacter[characterModel] == nil
					and self:CheckCanHit(characterModel)
					and characterIntersectsGroundShockwave(self, characterModel, shockwaveState, nil) then
					self:_registerHitCharacter(characterModel, seenThisFrame)
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

		local hitObjects, hitboxLocation, hitboxSize, hitboxRadius, pyramidState = self:_queryParts("Breakables")
		if self.Visualizer then
			if pyramidState then
				updatePyramidVisualizer(self, pyramidState)
			else
				updateStandardVisualizer(self.Visualizer, hitboxLocation, hitboxSize, hitboxRadius)
			end
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

	if self:_hasDebugVisibilityAttribute() then
		local debugVisibilityAttribute = self.Data.DebugVisibilityAttribute
		local function syncDebugVisibility()
			if self.Destroyed then
				return
			end

			self:Visible(Workspace:GetAttribute(debugVisibilityAttribute) == true)
		end

		self.HitboxTrove:Connect(Workspace:GetAttributeChangedSignal(debugVisibilityAttribute), syncDebugVisibility)
		syncDebugVisibility()
	end

	local hitboxTypeName = self.Data.HitboxType or "SpacialQuery"
	local hitboxType = Hitbox.HitboxTypes[hitboxTypeName]
	if not hitboxType then
		Logger.Warn("[Hitbox] Unknown HitboxType: " .. tostring(hitboxTypeName))
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
		Logger.Warn("[Hitbox] EnvironmentDestruction is not wired for this project", location, size)
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

		local hitboxTypeName = self.Data.HitboxType or "SpacialQuery"
		if hitboxTypeName == "GroundShockwave" then
			local shockwaveState = resolveGroundShockwaveState(self)
			if not shockwaveState then
				return self
			end

			buildGroundShockwaveVisualizer(self, shockwaveState)
			updateGroundShockwaveVisualizer(self, shockwaveState)
			return self
		end

		if self:_usesPyramidQuery() then
			local pyramidState = resolvePyramidLayers(self)
			if not pyramidState then
				return self
			end

			buildPyramidVisualizer(self, pyramidState)
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
		self._groundShockwaveVisualizerBaseSize = nil
		self._groundShockwaveVisualizerTween = nil
		self._groundShockwaveVisualizerUsesSpecialMeshScale = nil
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
