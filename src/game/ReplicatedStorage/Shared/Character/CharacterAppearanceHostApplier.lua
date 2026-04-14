local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local BodyPartRegions = require(script.Parent.BodyPartRegions)

local CharacterAppearanceHostApplier = {}

local APPLIED_FOLDER_NAME = "CharacterBodyParts"
local APPEARANCE_FOLDER_NAME = "CharacterBodyPartAppearance"
local HIDDEN_NATIVE_ROOT_NAME = "CharacterAppearanceHiddenStorage"
local SNAPSHOT_ROOT_NAME = "CharacterAppearanceSnapshotStorage"
local HIDDEN_NATIVE_KEY_ATTRIBUTE = "AppearanceTransferHiddenKey"
local APPLIED_ACCESSORIES_FOLDER_NAME = "AppliedAccessories"
local SNAPSHOT_SOURCE_FOLDER_NAME = "AppearanceSource"

local MANAGED_ATTRIBUTE = "AppearanceTransferApplied"
local SOURCE_ATTRIBUTE = "AppearanceTransferSource"
local COMPATIBLE_ATTRIBUTE = "AppearanceTransferCompatible"
local REASON_ATTRIBUTE = "AppearanceTransferReason"

local ALL_RIG_PARTS = {
	"Head",
	"UpperTorso",
	"LowerTorso",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
}

local CLOTHING_CLASS_NAMES = {
	Shirt = true,
	Pants = true,
	ShirtGraphic = true,
	BodyColors = true,
}

local REGION_CLOTHING_CLASSES = {
	Head = {
		BodyColors = true,
	},
	Torso = {
		Shirt = true,
		Pants = true,
		ShirtGraphic = true,
		BodyColors = true,
	},
	LeftArm = {
		Shirt = true,
		BodyColors = true,
	},
	RightArm = {
		Shirt = true,
		BodyColors = true,
	},
	LeftLeg = {
		Pants = true,
		BodyColors = true,
	},
	RightLeg = {
		Pants = true,
		BodyColors = true,
	},
}

local ATTACHMENT_REGION_LOOKUP = {
	HairAttachment = "Head",
	HatAttachment = "Head",
	FaceFrontAttachment = "Head",
	FaceCenterAttachment = "Head",
	BodyFrontAttachment = "Torso",
	BodyBackAttachment = "Torso",
	NeckAttachment = "Torso",
	LeftCollarAttachment = "Torso",
	RightCollarAttachment = "Torso",
	WaistFrontAttachment = "Torso",
	WaistCenterAttachment = "Torso",
	WaistBackAttachment = "Torso",
}

local function isManagedClone(instance: Instance): boolean
	return instance:GetAttribute(MANAGED_ATTRIBUTE) == true
end

local function ensureFolder(parent: Instance, name: string): Folder
	local folder = parent:FindFirstChild(name)
	if folder and folder:IsA("Folder") then
		return folder
	end

	if folder then
		folder:Destroy()
	end

	folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function getHiddenStorageRoot(): Folder
	return ensureFolder(ServerStorage, HIDDEN_NATIVE_ROOT_NAME)
end

local function getSnapshotStorageRoot(): Folder
	return ensureFolder(ServerStorage, SNAPSHOT_ROOT_NAME)
end

local function getHiddenKey(character: Model): string
	local key = character:GetAttribute(HIDDEN_NATIVE_KEY_ATTRIBUTE)
	if type(key) == "string" and key ~= "" then
		return key
	end

	key = HttpService:GenerateGUID(false)
	character:SetAttribute(HIDDEN_NATIVE_KEY_ATTRIBUTE, key)
	return key
end

local function ensureHiddenNativeFolder(character: Model): Folder
	local key = getHiddenKey(character)
	local hiddenRoot = getHiddenStorageRoot()
	local hiddenFolder = hiddenRoot:FindFirstChild(key)
	if hiddenFolder and hiddenFolder:IsA("Folder") then
		return hiddenFolder
	end

	if hiddenFolder then
		hiddenFolder:Destroy()
	end

	hiddenFolder = Instance.new("Folder")
	hiddenFolder.Name = key
	hiddenFolder.Parent = hiddenRoot
	return hiddenFolder
end

local function ensureSnapshotFolder(character: Model): Folder
	local key = getHiddenKey(character)
	local snapshotRoot = getSnapshotStorageRoot()
	local snapshotFolder = snapshotRoot:FindFirstChild(key)
	if snapshotFolder and snapshotFolder:IsA("Folder") then
		return snapshotFolder
	end

	if snapshotFolder then
		snapshotFolder:Destroy()
	end

	snapshotFolder = Instance.new("Folder")
	snapshotFolder.Name = key
	snapshotFolder.Parent = snapshotRoot
	return snapshotFolder
end

local function ensureSnapshotSourceFolder(character: Model): Folder
	local snapshotFolder = ensureSnapshotFolder(character)
	return ensureFolder(snapshotFolder, SNAPSHOT_SOURCE_FOLDER_NAME)
end

local function ensureAppearanceFolders(character: Model): (Folder, Folder, Folder)
	local appearanceFolder = ensureFolder(character, APPEARANCE_FOLDER_NAME)
	local accessoriesFolder = ensureFolder(appearanceFolder, APPLIED_ACCESSORIES_FOLDER_NAME)
	appearanceFolder:SetAttribute(MANAGED_ATTRIBUTE, true)
	return appearanceFolder, ensureHiddenNativeFolder(character), accessoriesFolder
end

local function clearManagedCharacterClothing(character: Model)
	for _, child in ipairs(character:GetChildren()) do
		if CLOTHING_CLASS_NAMES[child.ClassName] and isManagedClone(child) then
			child:Destroy()
		end
	end
end

local function clearAppliedAccessories(accessoriesFolder: Folder)
	for _, child in ipairs(accessoriesFolder:GetChildren()) do
		child:Destroy()
	end
end

local function clearManagedRegionHosts(character: Model)
	local appliedFolder = character:FindFirstChild(APPLIED_FOLDER_NAME)
	if not appliedFolder then
		return
	end

	for _, regionFolder in ipairs(appliedFolder:GetChildren()) do
		if regionFolder:IsA("Model") then
			for _, child in ipairs(regionFolder:GetChildren()) do
				if isManagedClone(child) then
					child:Destroy()
				end
			end
			regionFolder:SetAttribute("HasAppearanceHost", false)
			regionFolder:SetAttribute("AppearanceHostClothingClasses", "")
			regionFolder:SetAttribute("AppearanceSnapshotReady", false)
		end
	end
end

local function restoreHiddenNative(hiddenFolder: Folder, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	for _, child in ipairs(hiddenFolder:GetChildren()) do
		child:SetAttribute(SOURCE_ATTRIBUTE, nil)
		child:SetAttribute(COMPATIBLE_ATTRIBUTE, nil)
		child:SetAttribute(REASON_ATTRIBUTE, nil)
		if child:IsA("Accessory") and humanoid then
			humanoid:AddAccessory(child)
		else
			child.Parent = character
		end
	end
end

local function setDebugAttributes(instance: Instance, source: string, compatible: boolean, reason: string)
	instance:SetAttribute(MANAGED_ATTRIBUTE, true)
	instance:SetAttribute(SOURCE_ATTRIBUTE, source)
	instance:SetAttribute(COMPATIBLE_ATTRIBUTE, compatible)
	instance:SetAttribute(REASON_ATTRIBUTE, reason)
end

local function buildVisualPartLookup(character: Model): { [string]: BasePart }
	local partsByName = {}
	local appliedFolder = character:FindFirstChild(APPLIED_FOLDER_NAME)
	if not appliedFolder then
		return partsByName
	end

	for _, descendant in ipairs(appliedFolder:GetDescendants()) do
		if descendant:IsA("BasePart") and partsByName[descendant.Name] == nil then
			partsByName[descendant.Name] = descendant
		end
	end

	return partsByName
end

local function hideNativeInstance(hiddenFolder: Folder, instance: Instance, reason: string)
	if not instance or instance.Parent == hiddenFolder then
		return
	end

	instance:SetAttribute(SOURCE_ATTRIBUTE, "NativeCharacter")
	instance:SetAttribute(COMPATIBLE_ATTRIBUTE, false)
	instance:SetAttribute(REASON_ATTRIBUTE, reason)
	instance.Parent = hiddenFolder
end

local function inferRegionFromAccessoryType(accessory: Accessory): string?
	local success, accessoryType = pcall(function()
		return accessory.AccessoryType
	end)
	if not success or accessoryType == nil then
		return nil
	end

	local typeName = string.lower(tostring(accessoryType))
	if string.find(typeName, "hair", 1, true)
		or string.find(typeName, "hat", 1, true)
		or string.find(typeName, "face", 1, true)
		or string.find(typeName, "brow", 1, true)
		or string.find(typeName, "lash", 1, true)
	then
		return "Head"
	end

	if string.find(typeName, "neck", 1, true)
		or string.find(typeName, "front", 1, true)
		or string.find(typeName, "back", 1, true)
		or string.find(typeName, "waist", 1, true)
		or string.find(typeName, "shoulder", 1, true)
	then
		return "Torso"
	end

	return nil
end

local function resolveConflictRegion(accessory: Accessory, attachmentName: string?): string?
	if attachmentName and ATTACHMENT_REGION_LOOKUP[attachmentName] then
		return ATTACHMENT_REGION_LOOKUP[attachmentName]
	end

	return inferRegionFromAccessoryType(accessory)
end

local function getHandleAndSingleAttachment(accessory: Accessory): (BasePart?, Attachment?, string)
	local handle = accessory:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return nil, nil, "MissingHandle"
	end

	local foundAttachment = nil
	for _, child in ipairs(handle:GetChildren()) do
		if child:IsA("Attachment") then
			if foundAttachment then
				return handle, nil, "MultipleHandleAttachments"
			end
			foundAttachment = child
		end
	end

	if not foundAttachment then
		return handle, nil, "MissingHandleAttachment"
	end

	return handle, foundAttachment, "SingleHandleAttachment"
end

local function shouldHideAccessoryForEquippedRegion(
	accessory: Accessory,
	attachmentName: string?,
	equippedState: { [string]: any }?
): boolean
	local region = resolveConflictRegion(accessory, attachmentName)
	return region ~= nil and equippedState and equippedState[region] ~= nil
end

local function applyAccessories(
	character: Model,
	hiddenFolder: Folder,
	equippedState: { [string]: any }?
): (number, number)
	local accessories = {}
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") and not isManagedClone(child) then
			accessories[#accessories + 1] = child
		end
	end

	for _, accessory in ipairs(accessories) do
		local _, handleAttachment, attachmentReason = getHandleAndSingleAttachment(accessory)
		if handleAttachment then
			if shouldHideAccessoryForEquippedRegion(accessory, handleAttachment.Name, equippedState) then
				local region = resolveConflictRegion(accessory, handleAttachment.Name)
				hideNativeInstance(
					hiddenFolder,
					accessory,
					string.format("EquippedRegionOverride:%s:%s", tostring(region), handleAttachment.Name)
				)
			end
		elseif shouldHideAccessoryForEquippedRegion(accessory, nil, equippedState) then
			local region = resolveConflictRegion(accessory, nil)
			hideNativeInstance(hiddenFolder, accessory, string.format("EquippedRegionOverride:%s:%s", tostring(region), attachmentReason))
		end
	end

	return #accessories, 0
end

local function getSnapshotSourceInstances(character: Model): (Folder, Humanoid?)
	local snapshotSource = ensureSnapshotSourceFolder(character)
	return snapshotSource, snapshotSource:FindFirstChildOfClass("Humanoid")
end

local function clearSnapshotSource(character: Model)
	local snapshotSource = ensureSnapshotSourceFolder(character)
	for _, child in ipairs(snapshotSource:GetChildren()) do
		child:Destroy()
	end
	snapshotSource:SetAttribute("AppearanceSnapshotReady", false)
end

local function sanitizeHumanoidClone(humanoid: Humanoid): Humanoid
	local clone = humanoid:Clone()
	for _, child in ipairs(clone:GetChildren()) do
		child:Destroy()
	end

	pcall(function()
		clone.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end)
	pcall(function()
		clone.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end)
	pcall(function()
		clone.NameDisplayDistance = 0
	end)
	pcall(function()
		clone.HealthDisplayDistance = 0
	end)
	pcall(function()
		clone.BreakJointsOnDeath = false
	end)
	pcall(function()
		clone.RequiresNeck = false
	end)
	pcall(function()
		clone.AutoRotate = false
	end)
	pcall(function()
		clone.EvaluateStateMachine = false
	end)

	return clone
end

function CharacterAppearanceHostApplier.EnsureSnapshot(character: Model): (boolean, string?)
	local snapshotSource, snapshotHumanoid = getSnapshotSourceInstances(character)
	if snapshotHumanoid then
		snapshotSource:SetAttribute("AppearanceSnapshotReady", true)
		return true, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "Character appearance snapshot requires a Humanoid."
	end

	clearSnapshotSource(character)
	snapshotSource, _ = getSnapshotSourceInstances(character)

	local humanoidClone = sanitizeHumanoidClone(humanoid)
	setDebugAttributes(humanoidClone, "CharacterHumanoid", true, "AppearanceSnapshot")
	humanoidClone.Parent = snapshotSource

	local clothingCount = 0
	for _, child in ipairs(character:GetChildren()) do
		if CLOTHING_CLASS_NAMES[child.ClassName] and not isManagedClone(child) then
			local clone = child:Clone()
			setDebugAttributes(clone, child.Name, true, "AppearanceSnapshot")
			clone.Parent = snapshotSource
			clothingCount += 1
		end
	end

	snapshotSource:SetAttribute("AppearanceSnapshotReady", true)
	snapshotSource:SetAttribute("AppearanceSnapshotClothingCount", clothingCount)
	return true, nil
end

local function clearAppearanceState(character: Model)
	local appearanceFolder = character:FindFirstChild(APPEARANCE_FOLDER_NAME)
	if appearanceFolder and appearanceFolder:IsA("Folder") then
		local accessoriesFolder = appearanceFolder:FindFirstChild(APPLIED_ACCESSORIES_FOLDER_NAME)
		if accessoriesFolder and accessoriesFolder:IsA("Folder") then
			clearAppliedAccessories(accessoriesFolder)
		end

		appearanceFolder:SetAttribute("VisualPartCount", 0)
		appearanceFolder:SetAttribute("AccessoriesSeenCount", 0)
		appearanceFolder:SetAttribute("AccessoriesClonedCount", 0)
		appearanceFolder:SetAttribute("HiddenNativeCount", 0)
		appearanceFolder:SetAttribute("AppearanceHostCount", 0)
		appearanceFolder:SetAttribute("AppearanceHostHumanoidCount", 0)
		appearanceFolder:SetAttribute("ClothingHostCount", 0)
		appearanceFolder:SetAttribute("AppearanceSnapshotReady", false)
		appearanceFolder:SetAttribute(REASON_ATTRIBUTE, "NativeAppearanceActive")
	end

	clearManagedRegionHosts(character)
	clearManagedCharacterClothing(character)

	local hiddenRoot = ServerStorage:FindFirstChild(HIDDEN_NATIVE_ROOT_NAME)
	local hiddenKey = character:GetAttribute(HIDDEN_NATIVE_KEY_ATTRIBUTE)
	local hiddenFolder = hiddenRoot and type(hiddenKey) == "string" and hiddenRoot:FindFirstChild(hiddenKey) or nil
	if hiddenFolder and hiddenFolder:IsA("Folder") then
		restoreHiddenNative(hiddenFolder, character)
	end
end

local function cloneSnapshotClothing(regionFolder: Model, snapshotSource: Folder, region: string): (number, string)
	local relevantClasses = REGION_CLOTHING_CLASSES[region] or {}
	local classNames = {}
	local clothingCloneCount = 0

	for _, child in ipairs(snapshotSource:GetChildren()) do
		if CLOTHING_CLASS_NAMES[child.ClassName] and relevantClasses[child.ClassName] then
			local clone = child:Clone()
			setDebugAttributes(clone, child.Name, true, "RegionLocalClothingHost")
			clone.Parent = regionFolder
			clothingCloneCount += 1
			classNames[#classNames + 1] = child.ClassName
		end
	end

	table.sort(classNames)
	return clothingCloneCount, table.concat(classNames, ",")
end

local function applyRegionAppearanceHosts(
	character: Model,
	snapshotSource: Folder,
	equippedState: { [string]: any }?
): (number, number, number)
	local appliedFolder = character:FindFirstChild(APPLIED_FOLDER_NAME)
	if not appliedFolder then
		return 0, 0, 0
	end

	local snapshotHumanoid = snapshotSource:FindFirstChildOfClass("Humanoid")
	if not snapshotHumanoid then
		return 0, 0, 0
	end

	local hostCount = 0
	local humanoidCount = 0
	local clothingCount = 0

	for _, region in ipairs(BodyPartRegions.Order) do
		local regionFolder = appliedFolder:FindFirstChild(region)
		if equippedState and equippedState[region] and regionFolder and regionFolder:IsA("Model") then
			local humanoidClone = snapshotHumanoid:Clone()
			pcall(function()
				humanoidClone.EvaluateStateMachine = false
			end)
			setDebugAttributes(humanoidClone, "SnapshotHumanoid", true, "RegionLocalAppearanceHost")
			humanoidClone.Parent = regionFolder
			humanoidCount += 1

			local regionClothingCount, clothingClasses = cloneSnapshotClothing(regionFolder, snapshotSource, region)
			clothingCount += regionClothingCount
			hostCount += 1

			regionFolder:SetAttribute("HasAppearanceHost", true)
			regionFolder:SetAttribute("AppearanceHostClothingClasses", clothingClasses)
			regionFolder:SetAttribute("AppearanceSnapshotReady", true)
		end
	end

	return hostCount, humanoidCount, clothingCount
end

function CharacterAppearanceHostApplier.ClearCharacter(character: Model): boolean
	clearAppearanceState(character)
	return true
end

function CharacterAppearanceHostApplier.RestoreNativeCharacterAppearance(character: Model): (boolean, string?)
	clearAppearanceState(character)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return true, nil
	end

	local descriptionSuccess, description = pcall(function()
		return humanoid:GetAppliedDescription()
	end)
	if not descriptionSuccess or not description then
		return false, tostring(description)
	end

	local applySuccess, applyError = pcall(function()
		humanoid:ApplyDescriptionReset(description)
	end)
	if not applySuccess then
		return false, tostring(applyError)
	end

	return true, nil
end

function CharacterAppearanceHostApplier.ApplyCharacter(
	character: Model,
	equippedState: { [string]: any }?
): (boolean, string?)
	clearAppearanceState(character)

	local snapshotReady, snapshotError = CharacterAppearanceHostApplier.EnsureSnapshot(character)
	if not snapshotReady then
		return false, snapshotError
	end

	local snapshotSource = ensureSnapshotSourceFolder(character)
	local appearanceFolder, hiddenFolder, accessoriesFolder = ensureAppearanceFolders(character)
	local hostCount, humanoidCount, clothingCount = applyRegionAppearanceHosts(character, snapshotSource, equippedState)

	local visualPartsByName = buildVisualPartLookup(character)
	local accessoriesSeenCount, accessoriesClonedCount = applyAccessories(character, hiddenFolder, equippedState)

	local visualPartCount = 0
	for _ in pairs(visualPartsByName) do
		visualPartCount += 1
	end

	appearanceFolder:SetAttribute(MANAGED_ATTRIBUTE, true)
	appearanceFolder:SetAttribute(SOURCE_ATTRIBUTE, "PlayerCharacter")
	appearanceFolder:SetAttribute(COMPATIBLE_ATTRIBUTE, true)
	appearanceFolder:SetAttribute(REASON_ATTRIBUTE, "RegionLocalClothingHosts")
	appearanceFolder:SetAttribute("VisualPartCount", visualPartCount)
	appearanceFolder:SetAttribute("AccessoriesSeenCount", accessoriesSeenCount)
	appearanceFolder:SetAttribute("AccessoriesClonedCount", accessoriesClonedCount)
	appearanceFolder:SetAttribute("HiddenNativeCount", #hiddenFolder:GetChildren())
	appearanceFolder:SetAttribute("AppearanceHostCount", hostCount)
	appearanceFolder:SetAttribute("AppearanceHostHumanoidCount", humanoidCount)
	appearanceFolder:SetAttribute("ClothingHostCount", clothingCount)
	appearanceFolder:SetAttribute("AppearanceSnapshotReady", true)
	return true, nil
end

return CharacterAppearanceHostApplier
