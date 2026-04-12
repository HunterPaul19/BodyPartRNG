local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BodyPartRegions = require(ReplicatedStorage.Shared.Character.BodyPartRegions)
local BodyPartSets = require(ReplicatedStorage.Shared.Config.BodyParts.Sets)

local RawCharacterImporter = {}

local RAW_CHARACTERS_FOLDER_NAME = "RawCharacters"

local REGION_PARTS = {
	Head = { "Head" },
	Torso = { "UpperTorso", "LowerTorso" },
	LeftArm = { "LeftUpperArm", "LeftLowerArm", "LeftHand" },
	RightArm = { "RightUpperArm", "RightLowerArm", "RightHand" },
	LeftLeg = { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot" },
	RightLeg = { "RightUpperLeg", "RightLowerLeg", "RightFoot" },
}

local ALLOWED_VISUAL_CHILD_CLASSES = {
	Attachment = true,
	Decal = true,
	Texture = true,
	SurfaceAppearance = true,
	WrapTarget = true,
	SpecialMesh = true,
	FaceControls = true,
}

local REMOVED_INSTANCE_CLASSES = {
	Script = true,
	LocalScript = true,
	ModuleScript = true,
	Humanoid = true,
	AnimationController = true,
	Animator = true,
	BodyColors = true,
	Motor6D = true,
	AnimationConstraint = true,
	BallSocketConstraint = true,
	Weld = true,
	WeldConstraint = true,
}

local function getBodyPartsRoot(): Folder
	local gameAssets = assert(ReplicatedStorage:FindFirstChild("GameAssets"), "ReplicatedStorage.GameAssets is missing.")
	local bodyParts = assert(gameAssets:FindFirstChild("BodyParts"), "ReplicatedStorage.GameAssets.BodyParts is missing.")
	assert(bodyParts:IsA("Folder"), "ReplicatedStorage.GameAssets.BodyParts must be a Folder.")
	return bodyParts
end

local function getBundlesRoot(): Folder
	local bodyParts = getBodyPartsRoot()
	local bundles = bodyParts:FindFirstChild("Bundles")
	assert(bundles and bundles:IsA("Folder"), "ReplicatedStorage.GameAssets.BodyParts.Bundles is missing.")
	return bundles
end

local function getRawCharactersFolder(): Folder
	local folder = Workspace:FindFirstChild(RAW_CHARACTERS_FOLDER_NAME)
	assert(folder and folder:IsA("Folder"), "Workspace.RawCharacters is missing.")
	return folder
end

local function getSourceDefinitions()
	local definitions = BodyPartSets
	local imported = {}
	for setId, setDefinition in pairs(definitions) do
		if typeof(setDefinition.sourceModelName) == "string" then
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

local function sanitizePartClone(part: BasePart)
	for _, child in ipairs(part:GetDescendants()) do
		if REMOVED_INSTANCE_CLASSES[child.ClassName] then
			child:Destroy()
		elseif child.Parent == part and not (ALLOWED_VISUAL_CHILD_CLASSES[child.ClassName] or child:IsA("ValueBase")) then
			child:Destroy()
		end
	end
end

local function sanitizeAccessoryClone(accessory: Accessory)
	for _, descendant in ipairs(accessory:GetDescendants()) do
		if REMOVED_INSTANCE_CLASSES[descendant.ClassName] then
			descendant:Destroy()
		end
	end
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

local function buildRegionModel(sourceModel: Model, region: string, setDefinition): Model
	local regionModel = Instance.new("Model")
	regionModel.Name = setDefinition.assetModel
	regionModel:SetAttribute("ImportedSetId", setDefinition.id)
	regionModel:SetAttribute("SourceModelName", setDefinition.sourceModelName)
	regionModel:SetAttribute("BodyPartRegion", region)

	for _, partName in ipairs(REGION_PARTS[region]) do
		local sourcePart = findDescendantByName(sourceModel, partName)
		assert(sourcePart and sourcePart:IsA("BasePart"), string.format("Source model '%s' is missing part '%s'.", sourceModel.Name, partName))
		local clone = sourcePart:Clone()
		clone.Name = partName
		sanitizePartClone(clone)
		clone.Parent = regionModel
	end

	for _, child in ipairs(sourceModel:GetChildren()) do
		if child:IsA("Accessory") then
			local regionMatch = getAccessoryRegion(sourceModel, child)
			if regionMatch == region then
				local accessoryClone = child:Clone()
				sanitizeAccessoryClone(accessoryClone)
				accessoryClone.Parent = regionModel
			end
		end
	end

	return regionModel
end

local function validateRegionModel(regionModel: Model, region: string): string?
	for _, partName in ipairs(REGION_PARTS[region]) do
		local part = regionModel:FindFirstChild(partName)
		if not (part and part:IsA("BasePart")) then
			return string.format("Region '%s' model '%s' is missing part '%s'.", region, regionModel.Name, partName)
		end
	end

	for _, descendant in ipairs(regionModel:GetDescendants()) do
		if REMOVED_INSTANCE_CLASSES[descendant.ClassName] then
			return string.format("Region '%s' model '%s' still contains forbidden instance '%s'.", region, regionModel.Name, descendant.ClassName)
		end
	end

	return nil
end

function RawCharacterImporter.ImportAll()
	local rawCharactersFolder = getRawCharactersFolder()
	local sourceDefinitions = getSourceDefinitions()
	local expectedAssetModels = buildExpectedAssetModels(sourceDefinitions)
	local report = {
		packagedSets = {},
		invalidSets = {},
		skippedAccessories = {},
	}

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

	for _, setId in ipairs(sortKeys(sourceDefinitions)) do
		local setDefinition = sourceDefinitions[setId]
		local sourceModel = rawCharactersFolder:FindFirstChild(setDefinition.sourceModelName)
		if not (sourceModel and sourceModel:IsA("Model")) then
			table.insert(report.invalidSets, string.format("%s: missing source model '%s'.", setId, tostring(setDefinition.sourceModelName)))
			continue
		end

		local packaged = true
		for _, region in ipairs(BodyPartRegions.Order) do
			local assetGroupFolder = ensureAssetGroupFolder(region, setDefinition.assetGroup)
			local existing = assetGroupFolder:FindFirstChild(setDefinition.assetModel)
			if existing then
				existing:Destroy()
			end

			local ok, result = pcall(function()
				local regionModel = buildRegionModel(sourceModel, region, setDefinition)
				local validationError = validateRegionModel(regionModel, region)
				if validationError then
					error(validationError)
				end
				regionModel.Parent = assetGroupFolder
			end)

			if not ok then
				packaged = false
				table.insert(report.invalidSets, string.format("%s/%s: %s", setId, region, tostring(result)))
				break
			end
		end

		for _, child in ipairs(sourceModel:GetChildren()) do
			if child:IsA("Accessory") then
				local regionMatch = getAccessoryRegion(sourceModel, child)
				if not regionMatch then
					table.insert(report.skippedAccessories, string.format("%s: skipped accessory '%s'.", setId, child.Name))
				end
			end
		end

		if packaged then
			table.insert(report.packagedSets, setId)
		end
	end

	table.sort(report.packagedSets)
	table.sort(report.invalidSets)
	table.sort(report.skippedAccessories)
	return report
end

function RawCharacterImporter.FormatReport(report)
	local lines = {
		string.format("Packaged sets: %d", #report.packagedSets),
		string.format("Invalid sets: %d", #report.invalidSets),
		string.format("Skipped accessories: %d", #report.skippedAccessories),
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

	return table.concat(lines, "\n")
end

return RawCharacterImporter
