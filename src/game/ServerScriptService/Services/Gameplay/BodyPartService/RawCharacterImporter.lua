local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssetPaths = require(ReplicatedStorage.Shared.Assets.GameAssetPaths)
local GameAssetResolver = require(ReplicatedStorage.Shared.Assets.GameAssetResolver)
local Workspace = game:GetService("Workspace")

local BodyPartRegions = require(ReplicatedStorage.Shared.Character.BodyPartRegions)
local BodyPartSets = require(ReplicatedStorage.Shared.Config.BodyParts.Sets)

local RawCharacterImporter = {}

local RAW_CHARACTERS_FOLDER_NAME = "RawCharacters"
local ROOT_FALLBACK_REGION = "Torso"

local ASSEMBLY_ANCHOR_PART_NAME_ATTRIBUTE = "AssemblyAnchorPartName"
local ASSEMBLY_ANCHOR_OFFSET_ATTRIBUTE = "AssemblyAnchorOffset"
local ASSEMBLY_OWNING_REGION_ATTRIBUTE = "AssemblyOwningRegion"
local ASSEMBLY_SOURCE_NAME_ATTRIBUTE = "AssemblySourceName"
local ASSEMBLY_TARGET_PART_NAME_ATTRIBUTE = "AssemblyTargetPartName"
local ASSEMBLY_ANCHOR_PART_ATTRIBUTE = "AssemblyAnchor"
local HAS_IMPORTED_BODY_COLORS_ATTRIBUTE = "HasImportedBodyColors"

local REGION_PARTS = {
	Head = { "Head" },
	Torso = { "UpperTorso", "LowerTorso" },
	LeftArm = { "LeftUpperArm", "LeftLowerArm", "LeftHand" },
	RightArm = { "RightUpperArm", "RightLowerArm", "RightHand" },
	LeftLeg = { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot" },
	RightLeg = { "RightUpperLeg", "RightLowerLeg", "RightFoot" },
}

local REGION_PART_TO_REGION = {}
local REGION_PRIORITY = {}
local RIG_PART_NAMES = {
	HumanoidRootPart = true,
}

for index, region in ipairs(BodyPartRegions.Order) do
	REGION_PRIORITY[region] = index
	for _, partName in ipairs(REGION_PARTS[region]) do
		REGION_PART_TO_REGION[partName] = region
		RIG_PART_NAMES[partName] = true
	end
end

local ALLOWED_VISUAL_CHILD_CLASSES = {
	Attachment = true,
	Beam = true,
	Decal = true,
	FaceControls = true,
	ParticleEmitter = true,
	SpecialMesh = true,
	SurfaceAppearance = true,
	Texture = true,
	WrapTarget = true,
}

local EFFECT_INSTANCE_CLASSES = {
	Beam = true,
	ParticleEmitter = true,
}

local REMOVED_INSTANCE_CLASSES = {
	AnimationConstraint = true,
	AnimationController = true,
	Animator = true,
	BodyColors = true,
	Humanoid = true,
	LocalScript = true,
	Model = false,
	ModuleScript = true,
	Motor6D = true,
	Script = true,
	Weld = true,
	WeldConstraint = true,
}

local VALIDATION_FORBIDDEN_CLASSES = {
	AnimationConstraint = true,
	AnimationController = true,
	Animator = true,
	BodyColors = true,
	Humanoid = true,
	LocalScript = true,
	ModuleScript = true,
	Motor6D = true,
	Script = true,
}

local GRAPH_JOINT_CLASSES = {
	Motor6D = true,
	Weld = true,
	WeldConstraint = true,
}

local BODY_COLORS_PROPERTY_BY_PART = {
	Head = "HeadColor3",
	UpperTorso = "TorsoColor3",
	LowerTorso = "TorsoColor3",
	LeftUpperArm = "LeftArmColor3",
	LeftLowerArm = "LeftArmColor3",
	LeftHand = "LeftArmColor3",
	RightUpperArm = "RightArmColor3",
	RightLowerArm = "RightArmColor3",
	RightHand = "RightArmColor3",
	LeftUpperLeg = "LeftLegColor3",
	LeftLowerLeg = "LeftLegColor3",
	LeftFoot = "LeftLegColor3",
	RightUpperLeg = "RightLegColor3",
	RightLowerLeg = "RightLegColor3",
	RightFoot = "RightLegColor3",
}

local function getBodyPartsRoot(): Folder
	local gameAssets = assert(ReplicatedStorage:FindFirstChild("GameAssets"), "ReplicatedStorage.GameAssets is missing.")
	local bodyParts = assert(GameAssetResolver.FindFirst({ GameAssetPaths.Models.BodyParts, GameAssetPaths.Legacy.BodyParts }), "ReplicatedStorage.GameAssets.Models.BodyParts is missing.")
	assert(bodyParts:IsA("Folder"), "ReplicatedStorage.GameAssets.Models.BodyParts must be a Folder.")
	return bodyParts
end

local function getBundlesRoot(): Folder
	local bodyParts = getBodyPartsRoot()
	local bundles = bodyParts:FindFirstChild("Bundles")
	assert(bundles and bundles:IsA("Folder"), "ReplicatedStorage.GameAssets.Models.BodyParts.Bundles is missing.")
	return bundles
end

local function getRawCharactersFolder(): Folder
	local folder = Workspace:FindFirstChild(RAW_CHARACTERS_FOLDER_NAME)
	assert(folder and folder:IsA("Folder"), "Workspace.RawCharacters is missing.")
	return folder
end

local function normalizeOptions(options)
	local normalized = {
		stripEffects = true,
		cleanupUnexpectedImportedModels = nil,
		setIds = nil,
	}

	if typeof(options) == "table" then
		if typeof(options.stripEffects) == "boolean" then
			normalized.stripEffects = options.stripEffects
		end

		if typeof(options.cleanupUnexpectedImportedModels) == "boolean" then
			normalized.cleanupUnexpectedImportedModels = options.cleanupUnexpectedImportedModels
		end

		if typeof(options.setIds) == "table" then
			normalized.setIds = {}
			for _, setId in ipairs(options.setIds) do
				if typeof(setId) == "string" and setId ~= "" then
					table.insert(normalized.setIds, setId)
				end
			end
		end
	end

	if normalized.cleanupUnexpectedImportedModels == nil then
		normalized.cleanupUnexpectedImportedModels = normalized.setIds == nil
	end

	return normalized
end

local function getSourceDefinitions(selectedSetIds)
	local imported = {}
	local selectedSetLookup = nil

	if typeof(selectedSetIds) == "table" then
		selectedSetLookup = {}
		for _, setId in ipairs(selectedSetIds) do
			if typeof(setId) == "string" and setId ~= "" then
				selectedSetLookup[setId] = true
			end
		end
	end

	for setId, setDefinition in pairs(BodyPartSets) do
		if typeof(setDefinition.sourceModelName) == "string"
			and (selectedSetLookup == nil or selectedSetLookup[setId] == true)
		then
			imported[setId] = setDefinition
		end
	end
	return imported
end

local function sortKeys(map)
	local keys = {}
	for key in pairs(map) do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

local function buildExpectedAssetModels(sourceDefinitions)
	local expected = {}
	for _, setDefinition in pairs(sourceDefinitions) do
		expected[setDefinition.assetModel] = true
	end
	return expected
end

local function findDescendantByName(model: Model, name: string): Instance?
	local direct = model:FindFirstChild(name)
	if direct then
		return direct
	end
	return model:FindFirstChild(name, true)
end

local function getRelativePath(root: Instance, instance: Instance): string
	if instance == root then
		return ""
	end

	local names = {}
	local current = instance
	while current and current ~= root do
		table.insert(names, 1, current.Name)
		current = current.Parent
	end

	return table.concat(names, "/")
end

local function findDescendantByRelativePath(root: Instance, relativePath: string): Instance?
	if relativePath == "" then
		return root
	end

	local current = root
	for token in string.gmatch(relativePath, "[^/]+") do
		current = current:FindFirstChild(token)
		if not current then
			return nil
		end
	end

	return current
end

local function registerCloneInstanceMap(originalRoot: Instance, cloneRoot: Instance, instanceMap)
	instanceMap[originalRoot] = cloneRoot

	for _, originalDescendant in ipairs(originalRoot:GetDescendants()) do
		local relativePath = getRelativePath(originalRoot, originalDescendant)
		local cloneDescendant = findDescendantByRelativePath(cloneRoot, relativePath)
		if cloneDescendant then
			instanceMap[originalDescendant] = cloneDescendant
		end
	end
end

local function stripEffectsRecursive(root: Instance): number
	local removed = 0
	for _, descendant in ipairs(root:GetDescendants()) do
		if EFFECT_INSTANCE_CLASSES[descendant.ClassName] then
			descendant:Destroy()
			removed += 1
		end
	end
	return removed
end

local function sanitizePartClone(part: BasePart, options): number
	for _, child in ipairs(part:GetDescendants()) do
		if REMOVED_INSTANCE_CLASSES[child.ClassName] then
			child:Destroy()
		elseif child.Parent == part and not (ALLOWED_VISUAL_CHILD_CLASSES[child.ClassName] or child:IsA("ValueBase")) then
			child:Destroy()
		end
	end

	if options.stripEffects then
		return stripEffectsRecursive(part)
	end

	return 0
end

local function sanitizeAccessoryClone(accessory: Accessory, options): number
	for _, descendant in ipairs(accessory:GetDescendants()) do
		if REMOVED_INSTANCE_CLASSES[descendant.ClassName] then
			descendant:Destroy()
		end
	end

	if options.stripEffects then
		return stripEffectsRecursive(accessory)
	end

	return 0
end

local function sanitizeAssemblyPartClone(part: BasePart, options): number
	for _, descendant in ipairs(part:GetDescendants()) do
		if descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint") then
			descendant:Destroy()
		elseif REMOVED_INSTANCE_CLASSES[descendant.ClassName] then
			descendant:Destroy()
		elseif descendant.Parent == part and not (ALLOWED_VISUAL_CHILD_CLASSES[descendant.ClassName] or descendant:IsA("ValueBase")) then
			descendant:Destroy()
		end
	end

	if options.stripEffects then
		return stripEffectsRecursive(part)
	end

	return 0
end

local function getRawBodyColor(bodyColors: BodyColors?, partName: string): Color3?
	if not bodyColors then
		return nil
	end

	local propertyName = BODY_COLORS_PROPERTY_BY_PART[partName]
	if propertyName == nil then
		return nil
	end

	local value = (bodyColors :: any)[propertyName]
	if typeof(value) == "Color3" then
		return value
	end

	return nil
end

local function applyRawBodyColor(part: BasePart, bodyColors: BodyColors?, partName: string): boolean
	local color = getRawBodyColor(bodyColors, partName)
	if color == nil then
		return false
	end

	part.Color = color
	return true
end

local function getAccessoryAttachmentName(accessory: Accessory): string?
	local handle = accessory:FindFirstChild("Handle")
	if not (handle and handle:IsA("BasePart")) then
		return nil
	end

	local attachmentName = nil
	for _, descendant in ipairs(handle:GetDescendants()) do
		if descendant:IsA("Attachment") then
			if attachmentName then
				return nil
			end
			attachmentName = descendant.Name
		end
	end

	return attachmentName
end

local function getAccessoryRegion(model: Model, accessory: Accessory): string?
	local attachmentName = getAccessoryAttachmentName(accessory)
	if not attachmentName then
		return nil
	end

	local matchingRegion = nil
	for _, region in ipairs(BodyPartRegions.Order) do
		for _, partName in ipairs(REGION_PARTS[region]) do
			local part = findDescendantByName(model, partName)
			if part and part:IsA("BasePart") then
				local attachment = part:FindFirstChild(attachmentName)
				if attachment and attachment:IsA("Attachment") then
					if matchingRegion and matchingRegion ~= region then
						return nil
					end
					matchingRegion = region
				end
			end
		end
	end

	return matchingRegion
end

local function getAccessoryBaseParts(accessory: Accessory): { BasePart }
	local parts = {}
	for _, descendant in ipairs(accessory:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

local function getJointEndpoints(sourceModel: Model, instance: Instance): (BasePart?, BasePart?)
	local part0 = nil
	local part1 = nil

	if instance:IsA("JointInstance") then
		part0 = instance.Part0
		part1 = instance.Part1
	elseif instance:IsA("WeldConstraint") then
		part0 = instance.Part0
		part1 = instance.Part1
	end

	if part0 and part1 and part0:IsDescendantOf(sourceModel) and part1:IsDescendantOf(sourceModel) then
		return part0, part1
	end

	return nil, nil
end

local function buildJointGraph(sourceModel: Model)
	local adjacency = {}
	local jointRecords = {}

	local function ensureAdjacencyEntry(part: BasePart)
		local entry = adjacency[part]
		if entry == nil then
			entry = {}
			adjacency[part] = entry
		end
		return entry
	end

	for _, descendant in ipairs(sourceModel:GetDescendants()) do
		if GRAPH_JOINT_CLASSES[descendant.ClassName] then
			local part0, part1 = getJointEndpoints(sourceModel, descendant)
			if part0 and part1 and part0 ~= part1 then
				table.insert(ensureAdjacencyEntry(part0), part1)
				table.insert(ensureAdjacencyEntry(part1), part0)
				table.insert(jointRecords, {
					instance = descendant,
					part0 = part0,
					part1 = part1,
				})
			end
		end
	end

	return adjacency, jointRecords
end

local function resolvePartRegion(part: BasePart): string?
	if part.Name == "HumanoidRootPart" then
		return ROOT_FALLBACK_REGION
	end
	return REGION_PART_TO_REGION[part.Name]
end

local function chooseWinningRegion(regionCounts): string?
	local bestRegion = nil
	local bestCount = -1

	for _, region in ipairs(BodyPartRegions.Order) do
		local count = regionCounts[region] or 0
		if count > bestCount then
			bestRegion = region
			bestCount = count
		end
	end

	if bestCount <= 0 then
		return nil
	end

	return bestRegion
end

local function chooseWinningPartName(region: string, partCounts): string?
	local bestPartName = nil
	local bestCount = -1

	for _, partName in ipairs(REGION_PARTS[region]) do
		local count = partCounts[partName] or 0
		if count > bestCount then
			bestPartName = partName
			bestCount = count
		end
	end

	if bestPartName then
		return bestPartName
	end

	return REGION_PARTS[region][1]
end

local function chooseAssemblyAnchorPartName(componentPartCounts, componentParts): string?
	local bestPart = nil
	local bestCount = -1

	table.sort(componentParts, function(left, right)
		if left.Name == right.Name then
			return left:GetFullName() < right:GetFullName()
		end
		return left.Name < right.Name
	end)

	for _, part in ipairs(componentParts) do
		local count = componentPartCounts[part] or 0
		if count > bestCount then
			bestPart = part
			bestCount = count
		end
	end

	return bestPart and bestPart.Name or componentParts[1].Name
end

local function getAssemblySourceNames(sourceModel: Model, componentParts): string
	local names = {}
	local seen = {}

	for _, part in ipairs(componentParts) do
		local current = part
		while current.Parent and current.Parent ~= sourceModel do
			current = current.Parent
		end

		if current ~= sourceModel and not seen[current.Name] then
			seen[current.Name] = true
			table.insert(names, current.Name)
		end
	end

	table.sort(names)
	return if #names > 0 then table.concat(names, "+") else componentParts[1].Name
end

local function getAssemblySourceRoots(sourceModel: Model, componentParts): { Instance }
	local roots = {}
	local seen = {}

	for _, part in ipairs(componentParts) do
		local current = part
		while current.Parent and current.Parent ~= sourceModel do
			current = current.Parent
		end

		if current ~= sourceModel and not seen[current] then
			seen[current] = true
			table.insert(roots, current)
		end
	end

	table.sort(roots, function(left, right)
		return left.Name < right.Name
	end)

	return roots
end

local function createAssemblyModelName(index: number, sourceName: string): string
	local sanitized = string.gsub(sourceName, "%s+", "_")
	sanitized = string.gsub(sanitized, "[^%w_%-+]", "")
	if sanitized == "" then
		sanitized = "Assembly"
	end
	return string.format("Assembly_%02d_%s", index, sanitized)
end

local function recreateAssemblyJoint(originalJoint: Instance, clonedPart0: BasePart, clonedPart1: BasePart)
	local recreated = nil

	if originalJoint:IsA("WeldConstraint") then
		recreated = Instance.new("WeldConstraint")
		recreated.Part0 = clonedPart0
		recreated.Part1 = clonedPart1
	elseif originalJoint:IsA("Motor6D") or originalJoint:IsA("Weld") then
		recreated = Instance.new("Weld")
		recreated.Part0 = clonedPart0
		recreated.Part1 = clonedPart1
		if originalJoint:IsA("JointInstance") then
			recreated.C0 = originalJoint.C0
			recreated.C1 = originalJoint.C1
		end
	end

	if recreated then
		recreated.Name = originalJoint.Name
		recreated.Parent = clonedPart0
	end
end

local function remapBeamAttachments(instanceMap)
	for original, clone in pairs(instanceMap) do
		if original:IsA("Beam") and clone:IsA("Beam") then
			local originalAttachment0 = original.Attachment0
			local originalAttachment1 = original.Attachment1
			if originalAttachment0 and instanceMap[originalAttachment0] and instanceMap[originalAttachment0]:IsA("Attachment") then
				clone.Attachment0 = instanceMap[originalAttachment0]
			end
			if originalAttachment1 and instanceMap[originalAttachment1] and instanceMap[originalAttachment1]:IsA("Attachment") then
				clone.Attachment1 = instanceMap[originalAttachment1]
			end
		end
	end
end

local function buildImportPlanForSourceModel(sourceModel: Model, setDefinition, report)
	local simpleAccessoriesByRegion = {}
	local simpleAccessoryPartSet = {}

	for _, region in ipairs(BodyPartRegions.Order) do
		simpleAccessoriesByRegion[region] = {}
	end

	for _, child in ipairs(sourceModel:GetChildren()) do
		if child:IsA("Accessory") then
			local region = getAccessoryRegion(sourceModel, child)
			if region then
				table.insert(simpleAccessoriesByRegion[region], child)
				for _, part in ipairs(getAccessoryBaseParts(child)) do
					simpleAccessoryPartSet[part] = true
				end
			end
		end
	end

	local adjacency, jointRecords = buildJointGraph(sourceModel)
	local allowedParts = {}
	local orderedParts = {}

	for _, descendant in ipairs(sourceModel:GetDescendants()) do
		if descendant:IsA("BasePart") and not RIG_PART_NAMES[descendant.Name] and not simpleAccessoryPartSet[descendant] then
			allowedParts[descendant] = true
			table.insert(orderedParts, descendant)
		end
	end

	table.sort(orderedParts, function(left, right)
		return left:GetFullName() < right:GetFullName()
	end)

	local components = {}
	local componentIndexByPart = {}
	local visited = {}

	for _, startingPart in ipairs(orderedParts) do
		if not visited[startingPart] then
			local queue = { startingPart }
			local head = 1
			local componentParts = {}
			visited[startingPart] = true

			while head <= #queue do
				local current = queue[head]
				head += 1
				table.insert(componentParts, current)

				for _, neighbor in ipairs(adjacency[current] or {}) do
					if allowedParts[neighbor] and not visited[neighbor] then
						visited[neighbor] = true
						table.insert(queue, neighbor)
					end
				end
			end

			local component = {
				parts = componentParts,
				partSet = {},
				connectionCountsByRegion = {},
				connectionCountsByPart = {},
				componentPartConnectionCounts = {},
			}

			for _, part in ipairs(componentParts) do
				component.partSet[part] = true
			end

			table.insert(components, component)
			local componentIndex = #components
			for _, part in ipairs(componentParts) do
				componentIndexByPart[part] = componentIndex
			end
		end
	end

	for _, jointRecord in ipairs(jointRecords) do
		local componentIndex0 = componentIndexByPart[jointRecord.part0]
		local componentIndex1 = componentIndexByPart[jointRecord.part1]

		if componentIndex0 and componentIndex0 == componentIndex1 then
			-- Internal assembly joints are preserved later, but they should not influence region ownership.
		elseif componentIndex0 and resolvePartRegion(jointRecord.part1) then
			local component = components[componentIndex0]
			local region = resolvePartRegion(jointRecord.part1)
			component.connectionCountsByRegion[region] = (component.connectionCountsByRegion[region] or 0) + 1
			if REGION_PART_TO_REGION[jointRecord.part1.Name] == region then
				component.connectionCountsByPart[jointRecord.part1.Name] =
					(component.connectionCountsByPart[jointRecord.part1.Name] or 0) + 1
			end
			component.componentPartConnectionCounts[jointRecord.part0] =
				(component.componentPartConnectionCounts[jointRecord.part0] or 0) + 1
		elseif componentIndex1 and resolvePartRegion(jointRecord.part0) then
			local component = components[componentIndex1]
			local region = resolvePartRegion(jointRecord.part0)
			component.connectionCountsByRegion[region] = (component.connectionCountsByRegion[region] or 0) + 1
			if REGION_PART_TO_REGION[jointRecord.part0.Name] == region then
				component.connectionCountsByPart[jointRecord.part0.Name] =
					(component.connectionCountsByPart[jointRecord.part0.Name] or 0) + 1
			end
			component.componentPartConnectionCounts[jointRecord.part1] =
				(component.componentPartConnectionCounts[jointRecord.part1] or 0) + 1
		end
	end

	local genericAssembliesByRegion = {}
	for _, region in ipairs(BodyPartRegions.Order) do
		genericAssembliesByRegion[region] = {}
	end

	local skippedAccessoryNames = {}
	for _, child in ipairs(sourceModel:GetChildren()) do
		if child:IsA("Accessory") and getAccessoryRegion(sourceModel, child) == nil then
			skippedAccessoryNames[child.Name] = true
		end
	end

	for componentIndex, component in ipairs(components) do
		local region = chooseWinningRegion(component.connectionCountsByRegion)
		if not region then
			table.insert(
				report.skippedAssemblies,
				string.format("%s: skipped assembly '%s'.", setDefinition.id, getAssemblySourceNames(sourceModel, component.parts))
			)
			continue
		end

		local connectedRegions = 0
		for _, candidate in ipairs(BodyPartRegions.Order) do
			if (component.connectionCountsByRegion[candidate] or 0) > 0 then
				connectedRegions += 1
			end
		end

		local targetPartName = chooseWinningPartName(region, component.connectionCountsByPart)
		local anchorPartName = chooseAssemblyAnchorPartName(component.componentPartConnectionCounts, component.parts)
		local anchorSourcePart = nil
		for _, part in ipairs(component.parts) do
			if part.Name == anchorPartName then
				anchorSourcePart = part
				break
			end
		end
		if not anchorSourcePart then
			anchorSourcePart = component.parts[1]
			anchorPartName = anchorSourcePart.Name
		end

		local targetSourcePart = findDescendantByName(sourceModel, targetPartName)
		if not (targetSourcePart and targetSourcePart:IsA("BasePart")) then
			table.insert(
				report.skippedAssemblies,
				string.format("%s: skipped assembly '%s' (missing target part %s).", setDefinition.id, getAssemblySourceNames(sourceModel, component.parts), targetPartName)
			)
			continue
		end

		if connectedRegions > 1 then
			table.insert(
				report.autoAssignedAssemblies,
				string.format(
					"%s: auto-assigned assembly '%s' to %s.",
					setDefinition.id,
					getAssemblySourceNames(sourceModel, component.parts),
					region
				)
			)
		end

		table.insert(genericAssembliesByRegion[region], {
			componentIndex = componentIndex,
			sourceName = getAssemblySourceNames(sourceModel, component.parts),
			sourceRoots = getAssemblySourceRoots(sourceModel, component.parts),
			parts = component.parts,
			partSet = component.partSet,
			jointRecords = jointRecords,
			anchorPartName = anchorPartName,
			anchorSourcePart = anchorSourcePart,
			targetPartName = targetPartName,
			targetSourcePart = targetSourcePart,
			offset = targetSourcePart.CFrame:ToObjectSpace(anchorSourcePart.CFrame),
		})

		for _, root in ipairs(getAssemblySourceRoots(sourceModel, component.parts)) do
			if root:IsA("Accessory") then
				skippedAccessoryNames[root.Name] = nil
			end
		end
	end

	for accessoryName in pairs(skippedAccessoryNames) do
		table.insert(report.skippedAccessories, string.format("%s: skipped accessory '%s'.", setDefinition.id, accessoryName))
	end

	return {
		simpleAccessoriesByRegion = simpleAccessoriesByRegion,
		genericAssembliesByRegion = genericAssembliesByRegion,
	}
end

local function ensureAssetGroupFolder(region: string, assetGroup: string): Folder
	local bundlesRoot = getBundlesRoot()
	local regionFolder = bundlesRoot:FindFirstChild(region)
	assert(regionFolder and regionFolder:IsA("Folder"), string.format("Missing bundles region folder '%s'.", region))

	local assetGroupFolder = regionFolder:FindFirstChild(assetGroup)
	if assetGroupFolder and assetGroupFolder:IsA("Folder") then
		return assetGroupFolder
	end
	if assetGroupFolder then
		assetGroupFolder:Destroy()
	end

	assetGroupFolder = Instance.new("Folder")
	assetGroupFolder.Name = assetGroup
	assetGroupFolder.Parent = regionFolder
	return assetGroupFolder
end

local function buildGenericAssemblyModel(assemblyDefinition, setDefinition, options)
	local assemblyModel = Instance.new("Model")
	assemblyModel.Name = createAssemblyModelName(assemblyDefinition.componentIndex, assemblyDefinition.sourceName)
	assemblyModel:SetAttribute(ASSEMBLY_ANCHOR_PART_NAME_ATTRIBUTE, assemblyDefinition.anchorPartName)
	assemblyModel:SetAttribute(ASSEMBLY_ANCHOR_OFFSET_ATTRIBUTE, assemblyDefinition.offset)
	assemblyModel:SetAttribute(ASSEMBLY_OWNING_REGION_ATTRIBUTE, setDefinition.region)
	assemblyModel:SetAttribute(ASSEMBLY_SOURCE_NAME_ATTRIBUTE, assemblyDefinition.sourceName)
	assemblyModel:SetAttribute(ASSEMBLY_TARGET_PART_NAME_ATTRIBUTE, assemblyDefinition.targetPartName)

	local originalToClonePart = {}
	local instanceMap = {}
	local strippedEffects = 0

	local sortedParts = table.clone(assemblyDefinition.parts)
	table.sort(sortedParts, function(left, right)
		return left:GetFullName() < right:GetFullName()
	end)

	for _, originalPart in ipairs(sortedParts) do
		local clonePart = originalPart:Clone()
		registerCloneInstanceMap(originalPart, clonePart, instanceMap)
		strippedEffects += sanitizeAssemblyPartClone(clonePart, options)
		clonePart.Parent = assemblyModel
		originalToClonePart[originalPart] = clonePart
	end

	remapBeamAttachments(instanceMap)

	for _, jointRecord in ipairs(assemblyDefinition.jointRecords) do
		local clonePart0 = originalToClonePart[jointRecord.part0]
		local clonePart1 = originalToClonePart[jointRecord.part1]
		if clonePart0 and clonePart1 then
			recreateAssemblyJoint(jointRecord.instance, clonePart0, clonePart1)
		end
	end

	local anchorClone = nil
	for originalPart, clonePart in pairs(originalToClonePart) do
		if originalPart == assemblyDefinition.anchorSourcePart then
			anchorClone = clonePart
			break
		end
	end

	assert(anchorClone, string.format("Assembly '%s' is missing its anchor clone.", assemblyDefinition.sourceName))
	anchorClone:SetAttribute(ASSEMBLY_ANCHOR_PART_ATTRIBUTE, true)

	return assemblyModel, strippedEffects
end

local function buildRegionModel(sourceModel: Model, region: string, setDefinition, importPlan, options): (Model, number)
	local regionModel = Instance.new("Model")
	regionModel.Name = setDefinition.assetModel
	regionModel:SetAttribute("ImportedSetId", setDefinition.id)
	regionModel:SetAttribute("SourceModelName", setDefinition.sourceModelName)
	regionModel:SetAttribute("BodyPartRegion", region)

	local strippedEffects = 0
	local hasImportedBodyColors = false
	local sourceBodyColors = sourceModel:FindFirstChildOfClass("BodyColors")

	for _, partName in ipairs(REGION_PARTS[region]) do
		local sourcePart = findDescendantByName(sourceModel, partName)
		assert(sourcePart and sourcePart:IsA("BasePart"), string.format("Source model '%s' is missing part '%s'.", sourceModel.Name, partName))
		local clone = sourcePart:Clone()
		clone.Name = partName
		hasImportedBodyColors = applyRawBodyColor(clone, sourceBodyColors, partName) or hasImportedBodyColors
		strippedEffects += sanitizePartClone(clone, options)
		clone.Parent = regionModel
	end

	for _, accessory in ipairs(importPlan.simpleAccessoriesByRegion[region]) do
		local accessoryClone = accessory:Clone()
		strippedEffects += sanitizeAccessoryClone(accessoryClone, options)
		accessoryClone.Parent = regionModel
	end

	for _, assemblyDefinition in ipairs(importPlan.genericAssembliesByRegion[region]) do
		local assemblyModel, removedEffects = buildGenericAssemblyModel(assemblyDefinition, {
			id = setDefinition.id,
			region = region,
			sourceModelName = setDefinition.sourceModelName,
		}, options)
		strippedEffects += removedEffects
		assemblyModel.Parent = regionModel
	end

	regionModel:SetAttribute(HAS_IMPORTED_BODY_COLORS_ATTRIBUTE, hasImportedBodyColors)

	return regionModel, strippedEffects
end

local function validateGenericAssemblyModel(regionModel: Model, region: string): string?
	for _, child in ipairs(regionModel:GetChildren()) do
		if child:IsA("Model") then
			local anchorPartName = child:GetAttribute(ASSEMBLY_ANCHOR_PART_NAME_ATTRIBUTE)
			local anchorOffset = child:GetAttribute(ASSEMBLY_ANCHOR_OFFSET_ATTRIBUTE)
			local owningRegion = child:GetAttribute(ASSEMBLY_OWNING_REGION_ATTRIBUTE)
			local sourceName = child:GetAttribute(ASSEMBLY_SOURCE_NAME_ATTRIBUTE)
			local targetPartName = child:GetAttribute(ASSEMBLY_TARGET_PART_NAME_ATTRIBUTE)

			if typeof(anchorPartName) ~= "string" or anchorPartName == "" then
				return string.format("Assembly '%s' in region '%s' is missing %s.", child.Name, region, ASSEMBLY_ANCHOR_PART_NAME_ATTRIBUTE)
			end
			if typeof(anchorOffset) ~= "CFrame" then
				return string.format("Assembly '%s' in region '%s' is missing %s.", child.Name, region, ASSEMBLY_ANCHOR_OFFSET_ATTRIBUTE)
			end
			if owningRegion ~= region then
				return string.format("Assembly '%s' in region '%s' has invalid owning region '%s'.", child.Name, region, tostring(owningRegion))
			end
			if typeof(sourceName) ~= "string" or sourceName == "" then
				return string.format("Assembly '%s' in region '%s' is missing %s.", child.Name, region, ASSEMBLY_SOURCE_NAME_ATTRIBUTE)
			end
			if typeof(targetPartName) ~= "string" or REGION_PART_TO_REGION[targetPartName] ~= region then
				return string.format("Assembly '%s' in region '%s' has invalid target part '%s'.", child.Name, region, tostring(targetPartName))
			end

			local anchorPart = child:FindFirstChild(anchorPartName, true)
			if not (anchorPart and anchorPart:IsA("BasePart")) then
				return string.format("Assembly '%s' in region '%s' is missing anchor part '%s'.", child.Name, region, anchorPartName)
			end
		end
	end

	return nil
end

local function validateRegionModel(regionModel: Model, region: string): string?
	for _, partName in ipairs(REGION_PARTS[region]) do
		local part = regionModel:FindFirstChild(partName)
		if not (part and part:IsA("BasePart")) then
			return string.format("Region '%s' model '%s' is missing part '%s'.", region, regionModel.Name, partName)
		end
	end

	local assemblyError = validateGenericAssemblyModel(regionModel, region)
	if assemblyError then
		return assemblyError
	end

	for _, descendant in ipairs(regionModel:GetDescendants()) do
		if VALIDATION_FORBIDDEN_CLASSES[descendant.ClassName] then
			return string.format("Region '%s' model '%s' still contains forbidden instance '%s'.", region, regionModel.Name, descendant.ClassName)
		end
	end

	return nil
end

function RawCharacterImporter.ImportAll(options)
	local normalizedOptions = normalizeOptions(options)
	local rawCharactersFolder = getRawCharactersFolder()
	local sourceDefinitions = getSourceDefinitions(normalizedOptions.setIds)
	local expectedAssetModels = buildExpectedAssetModels(sourceDefinitions)
	local report = {
		autoAssignedAssemblies = {},
		invalidSets = {},
		packagedSets = {},
		skippedAccessories = {},
		skippedAssemblies = {},
		strippedEffectCount = 0,
		stripEffectsEnabled = normalizedOptions.stripEffects,
	}

	if normalizedOptions.cleanupUnexpectedImportedModels then
		for _, region in ipairs(BodyPartRegions.Order) do
			local regionFolder = getBundlesRoot():FindFirstChild(region)
			if regionFolder and regionFolder:IsA("Folder") then
				for _, assetGroupFolder in ipairs(regionFolder:GetChildren()) do
					if assetGroupFolder:IsA("Folder") and string.sub(assetGroupFolder.Name, 1, 8) == "Imported" then
						for _, child in ipairs(assetGroupFolder:GetChildren()) do
							if child:IsA("Model") and not expectedAssetModels[child.Name] then
								child:Destroy()
							end
						end
					end
				end
			end
		end
	end

	for _, setId in ipairs(sortKeys(sourceDefinitions)) do
		local setDefinition = sourceDefinitions[setId]
		local sourceModel = rawCharactersFolder:FindFirstChild(setDefinition.sourceModelName)
		if not (sourceModel and sourceModel:IsA("Model")) then
			table.insert(report.invalidSets, string.format("%s: missing source model '%s'.", setId, tostring(setDefinition.sourceModelName)))
			continue
		end

		local importPlan = buildImportPlanForSourceModel(sourceModel, setDefinition, report)
		local packaged = true

		for _, region in ipairs(BodyPartRegions.Order) do
			local assetGroupFolder = ensureAssetGroupFolder(region, setDefinition.assetGroup)
			local existing = assetGroupFolder:FindFirstChild(setDefinition.assetModel)
			if existing then
				existing:Destroy()
			end

			local ok, result, strippedEffects = pcall(function()
				local regionModel, removedEffects = buildRegionModel(sourceModel, region, setDefinition, importPlan, normalizedOptions)
				local validationError = validateRegionModel(regionModel, region)
				if validationError then
					Logger.Error(validationError)
				end
				regionModel.Parent = assetGroupFolder
				return regionModel, removedEffects
			end)

			if not ok then
				packaged = false
				table.insert(report.invalidSets, string.format("%s/%s: %s", setId, region, tostring(result)))
				break
			end

			report.strippedEffectCount += strippedEffects
		end

		if packaged then
			table.insert(report.packagedSets, setId)
		end
	end

	table.sort(report.autoAssignedAssemblies)
	table.sort(report.invalidSets)
	table.sort(report.packagedSets)
	table.sort(report.skippedAccessories)
	table.sort(report.skippedAssemblies)

	return report
end

function RawCharacterImporter.ImportSetIds(setIds, options)
	local mergedOptions = {}
	if typeof(options) == "table" then
		for key, value in pairs(options) do
			mergedOptions[key] = value
		end
	end

	mergedOptions.setIds = setIds
	mergedOptions.cleanupUnexpectedImportedModels = false

	return RawCharacterImporter.ImportAll(mergedOptions)
end

function RawCharacterImporter.FormatReport(report)
	local lines = {
		string.format("Packaged sets: %d", #report.packagedSets),
		string.format("Invalid sets: %d", #report.invalidSets),
		string.format("Skipped accessories: %d", #report.skippedAccessories),
		string.format("Skipped assemblies: %d", #report.skippedAssemblies),
		string.format("Auto-assigned assemblies: %d", #report.autoAssignedAssemblies),
		string.format("Strip effects enabled: %s", tostring(report.stripEffectsEnabled == true)),
		string.format("Stripped ParticleEmitters/Beams: %d", report.strippedEffectCount or 0),
	}

	if #report.invalidSets > 0 then
		table.insert(lines, "Invalid set details:")
		for _, line in ipairs(report.invalidSets) do
			table.insert(lines, "- " .. line)
		end
	end

	if #report.skippedAccessories > 0 then
		table.insert(lines, "Skipped accessories:")
		for _, line in ipairs(report.skippedAccessories) do
			table.insert(lines, "- " .. line)
		end
	end

	if #report.skippedAssemblies > 0 then
		table.insert(lines, "Skipped assemblies:")
		for _, line in ipairs(report.skippedAssemblies) do
			table.insert(lines, "- " .. line)
		end
	end

	if #report.autoAssignedAssemblies > 0 then
		table.insert(lines, "Auto-assigned assemblies:")
		for _, line in ipairs(report.autoAssignedAssemblies) do
			table.insert(lines, "- " .. line)
		end
	end

	return table.concat(lines, "\n")
end

return RawCharacterImporter
