local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local AccessoryScaleUtils = require(script.Parent.AccessoryScaleUtils)
local AppearanceRegionRules = require(script.Parent.AppearanceRegionRules)
local BodyPartRegions = require(script.Parent.BodyPartRegions)

local CharacterAppearanceHostApplier = {}

local APPLIED_FOLDER_NAME = "CharacterBodyParts"
local APPEARANCE_FOLDER_NAME = "CharacterBodyPartAppearance"
local HIDDEN_NATIVE_ROOT_NAME = "CharacterAppearanceHiddenStorage"
local SNAPSHOT_ROOT_NAME = "CharacterAppearanceSnapshotStorage"
local HIDDEN_NATIVE_KEY_ATTRIBUTE = "AppearanceTransferHiddenKey"
local APPLIED_ACCESSORIES_FOLDER_NAME = "AppliedAccessories"
local SNAPSHOT_SOURCE_FOLDER_NAME = "AppearanceSource"
local SNAPSHOT_RIG_REFERENCE_FOLDER_NAME = "RigReference"
local SNAPSHOT_ACCESSORIES_FOLDER_NAME = "SnapshotAccessories"
local ACCESSORY_ATTACHMENT_ATTRIBUTE = "AccessoryBindingAttachmentName"
local ACCESSORY_MATCH_KEY_ATTRIBUTE = "AccessoryBindingMatchKey"
local ACCESSORY_REGION_ATTRIBUTE = "AccessoryBindingRegion"
local ACCESSORY_TARGET_PART_ATTRIBUTE = "AccessoryBindingTargetPartName"

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

local CLOTHING_CLASS_NAMES = AppearanceRegionRules.ClothingClassNames
local REGION_CLOTHING_CLASSES = AppearanceRegionRules.RegionClothingClasses

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

local REGION_VISUAL_PART_ORDER = {
	Head = { "Head" },
	Torso = { "UpperTorso", "LowerTorso" },
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

local function ensureSnapshotRigReferenceFolder(character: Model): Folder
	local snapshotFolder = ensureSnapshotFolder(character)
	return ensureFolder(snapshotFolder, SNAPSHOT_RIG_REFERENCE_FOLDER_NAME)
end

local function ensureSnapshotAccessoriesFolder(character: Model): Folder
	local snapshotFolder = ensureSnapshotFolder(character)
	return ensureFolder(snapshotFolder, SNAPSHOT_ACCESSORIES_FOLDER_NAME)
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

local function findDirectAttachment(part: BasePart, attachmentName: string): Attachment?
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("Attachment") and child.Name == attachmentName then
			return child
		end
	end

	return nil
end

local function findNativeCharacterPartForAttachment(character: Model, attachmentName: string): BasePart?
	for _, partName in ipairs(ALL_RIG_PARTS) do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") and findDirectAttachment(part, attachmentName) then
			return part
		end
	end

	return nil
end

local function findSnapshotReferencePartForAttachment(rigReferenceFolder: Folder, attachmentName: string): BasePart?
	for _, partName in ipairs(ALL_RIG_PARTS) do
		local part = rigReferenceFolder:FindFirstChild(partName)
		if part and part:IsA("BasePart") and findDirectAttachment(part, attachmentName) then
			return part
		end
	end

	return nil
end

local function resolveNativeScaledAttachmentWorldCFrame(
	referencePart: BasePart,
	attachmentName: string,
	targetPart: BasePart
): CFrame?
	local referenceAttachment = findDirectAttachment(referencePart, attachmentName)
	if not referenceAttachment then
		return nil
	end

	local scaledAttachmentLocalCFrame =
		AccessoryScaleUtils.ScaleAttachmentLocalCFrame(referenceAttachment.CFrame, referencePart.Size, targetPart.Size)
	return targetPart.CFrame * scaledAttachmentLocalCFrame
end

local function findCompatibleVisualAttachment(
	visualPartsByName: { [string]: BasePart },
	attachmentName: string,
	region: string?
): (BasePart?, Attachment?)
	local preferredPartNames = if region then REGION_VISUAL_PART_ORDER[region] else nil
	if preferredPartNames ~= nil then
		for _, partName in ipairs(preferredPartNames) do
			local visualPart = visualPartsByName[partName]
			if visualPart then
				local attachment = findDirectAttachment(visualPart, attachmentName)
				if attachment then
					return visualPart, attachment
				end
			end
		end
	end

	for _, partName in ipairs(ALL_RIG_PARTS) do
		local visualPart = visualPartsByName[partName]
		if visualPart then
			local attachment = findDirectAttachment(visualPart, attachmentName)
			if attachment then
				return visualPart, attachment
			end
		end
	end

	return nil, nil
end

local function configureAccessoryHandle(handle: BasePart)
	handle.Anchored = false
	handle.Massless = true
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
end

local function clearAccessoryHandleWelds(handle: BasePart)
	for _, child in ipairs(handle:GetChildren()) do
		if (child:IsA("Weld") or child:IsA("WeldConstraint")) and child.Name == "AccessoryWeld" then
			child:Destroy()
		end
	end
end

local function alignAccessoryClone(
	accessory: Accessory,
	targetPart: BasePart,
	targetAttachmentWorldCFrame: CFrame
): (boolean, string?)
	local handle = accessory:FindFirstChild("Handle")
	if not (handle and handle:IsA("BasePart")) then
		return false, string.format("Accessory %s is missing a Handle.", accessory.Name)
	end

	local accessoryAttachment = nil
	for _, child in ipairs(handle:GetChildren()) do
		if child:IsA("Attachment") then
			if accessoryAttachment ~= nil then
				return false, string.format("Accessory %s must have exactly one handle attachment.", accessory.Name)
			end
			accessoryAttachment = child
		end
	end

	if accessoryAttachment == nil then
		return false, string.format("Accessory %s is missing a handle attachment.", accessory.Name)
	end

	clearAccessoryHandleWelds(handle)
	configureAccessoryHandle(handle)
	handle.CFrame = targetAttachmentWorldCFrame * accessoryAttachment.CFrame:Inverse()

	local weld = Instance.new("WeldConstraint")
	weld.Name = "AccessoryWeld"
	weld.Part0 = targetPart
	weld.Part1 = handle
	weld.Parent = handle

	return true, nil
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

local function buildAccessoryMatchKey(accessoryName: string, attachmentName: string): string
	return string.format("%s\0%s", accessoryName, attachmentName)
end

local function getManagedAccessoryBinding(accessory: Accessory): (string?, string?, string?)
	local attachmentName = accessory:GetAttribute(ACCESSORY_ATTACHMENT_ATTRIBUTE)
	local matchKey = accessory:GetAttribute(ACCESSORY_MATCH_KEY_ATTRIBUTE)
	local region = accessory:GetAttribute(ACCESSORY_REGION_ATTRIBUTE)
	return
		if type(attachmentName) == "string" and attachmentName ~= "" then attachmentName else nil,
		if type(matchKey) == "string" and matchKey ~= "" then matchKey else nil,
		if type(region) == "string" and region ~= "" then region else nil
end

local function getManagedAccessoryTargetPartName(accessory: Accessory): string?
	local targetPartName = accessory:GetAttribute(ACCESSORY_TARGET_PART_ATTRIBUTE)
	return if type(targetPartName) == "string" and targetPartName ~= "" then targetPartName else nil
end

local function setManagedAccessoryBinding(
	accessory: Accessory,
	attachmentName: string,
	matchKey: string,
	region: string?,
	targetPartName: string?
)
	accessory:SetAttribute(ACCESSORY_ATTACHMENT_ATTRIBUTE, attachmentName)
	accessory:SetAttribute(ACCESSORY_MATCH_KEY_ATTRIBUTE, matchKey)
	accessory:SetAttribute(ACCESSORY_REGION_ATTRIBUTE, region)
	accessory:SetAttribute(ACCESSORY_TARGET_PART_ATTRIBUTE, targetPartName)
end

local function getAppliedRegionPart(character: Model, region: string, partName: string): BasePart?
	local appliedFolder = character:FindFirstChild(APPLIED_FOLDER_NAME)
	if not appliedFolder then
		return nil
	end

	local regionFolder = appliedFolder:FindFirstChild(region)
	if not (regionFolder and regionFolder:IsA("Model")) then
		return nil
	end

	local part = regionFolder:FindFirstChild(partName, true)
	if part and part:IsA("BasePart") then
		return part
	end

	return nil
end

local function findBoundVisualAttachment(
	character: Model,
	region: string?,
	targetPartName: string?,
	attachmentName: string
): (BasePart?, Attachment?)
	if region and targetPartName then
		local boundPart = getAppliedRegionPart(character, region, targetPartName)
		if boundPart then
			local attachment = findDirectAttachment(boundPart, attachmentName)
			if attachment then
				return boundPart, attachment
			end
		end
	end

	local visualPartsByName = buildVisualPartLookup(character)
	return findCompatibleVisualAttachment(visualPartsByName, attachmentName, region)
end

local function resolveManagedAccessoryTarget(
	character: Model,
	rigReferenceFolder: Folder,
	region: string?,
	targetPartName: string?,
	attachmentName: string
): (BasePart?, CFrame?)
	local targetPart, fallbackTargetAttachment =
		findBoundVisualAttachment(character, region, targetPartName, attachmentName)
	if not targetPart then
		return nil, nil
	end

	local referencePart = findSnapshotReferencePartForAttachment(rigReferenceFolder, attachmentName)
	if referencePart then
		local derivedWorldCFrame = resolveNativeScaledAttachmentWorldCFrame(referencePart, attachmentName, targetPart)
		if derivedWorldCFrame then
			return targetPart, derivedWorldCFrame
		end
	end

	return targetPart, fallbackTargetAttachment and fallbackTargetAttachment.WorldCFrame or nil
end

local function buildAccessoryQueue(character: Model): ({ [string]: { Accessory } }, number)
	local queueByKey = {}
	local seenCount = 0

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") and not isManagedClone(child) then
			seenCount += 1

			local _, handleAttachment = getHandleAndSingleAttachment(child)
			if handleAttachment then
				local matchKey = buildAccessoryMatchKey(child.Name, handleAttachment.Name)
				local queue = queueByKey[matchKey]
				if queue == nil then
					queue = {}
					queueByKey[matchKey] = queue
				end

				queue[#queue + 1] = child
			end
		end
	end

	return queueByKey, seenCount
end

local function popQueuedAccessory(queueByKey: { [string]: { Accessory } }, matchKey: string): Accessory?
	local queue = queueByKey[matchKey]
	if queue == nil or #queue == 0 then
		return nil
	end

	local accessory = queue[1]
	table.remove(queue, 1)
	if #queue == 0 then
		queueByKey[matchKey] = nil
	end

	return accessory
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
	accessoriesFolder: Folder,
	hiddenFolder: Folder,
	equippedState: { [string]: any }?,
	visualPartsByName: { [string]: BasePart },
	rigReferenceFolder: Folder,
	snapshotAccessoriesFolder: Folder
): (number, number)
	local snapshotAccessories = {}
	local accessoriesClonedCount = 0

	for _, child in ipairs(snapshotAccessoriesFolder:GetChildren()) do
		if child:IsA("Accessory") then
			snapshotAccessories[#snapshotAccessories + 1] = child
		end
	end

	local liveAccessoryQueue, liveAccessoriesSeenCount = buildAccessoryQueue(character)

	for _, snapshotAccessory in ipairs(snapshotAccessories) do
		local _, handleAttachment = getHandleAndSingleAttachment(snapshotAccessory)
		if handleAttachment ~= nil then
			local region = resolveConflictRegion(snapshotAccessory, handleAttachment.Name)
			local isEquippedRegion = region ~= nil and equippedState and equippedState[region] ~= nil
			if isEquippedRegion then
				local targetPart, _ = findCompatibleVisualAttachment(visualPartsByName, handleAttachment.Name, region)
				local sourcePart = findSnapshotReferencePartForAttachment(rigReferenceFolder, handleAttachment.Name)
				local matchKey = buildAccessoryMatchKey(snapshotAccessory.Name, handleAttachment.Name)
				local liveAccessory = popQueuedAccessory(liveAccessoryQueue, matchKey)
				local targetAttachmentWorldCFrame =
					(targetPart and sourcePart)
						and resolveNativeScaledAttachmentWorldCFrame(sourcePart, handleAttachment.Name, targetPart)
					or nil
				if targetPart and targetAttachmentWorldCFrame and sourcePart and liveAccessory then
					local accessoryClone = snapshotAccessory:Clone()
					setDebugAttributes(
						accessoryClone,
						snapshotAccessory.Name,
						true,
						string.format("AppliedAccessoryClone:%s", handleAttachment.Name)
					)
					setManagedAccessoryBinding(accessoryClone, handleAttachment.Name, matchKey, region, targetPart.Name)
					accessoryClone.Parent = accessoriesFolder

					local scaleSuccess =
						select(1, AccessoryScaleUtils.ScaleAccessoryToPartSize(accessoryClone, sourcePart.Size, targetPart.Size))
					local alignSuccess =
						scaleSuccess and alignAccessoryClone(accessoryClone, targetPart, targetAttachmentWorldCFrame)
					if alignSuccess then
						hideNativeInstance(
							hiddenFolder,
							liveAccessory,
							string.format("EquippedRegionOverride:%s:%s", tostring(region), handleAttachment.Name)
						)
						accessoriesClonedCount += 1
					else
						accessoryClone:Destroy()
					end
				end
			end
		end
	end

	return liveAccessoriesSeenCount, accessoriesClonedCount
end

local function refreshManagedAccessoryAlignmentInternal(
	character: Model,
	equippedState: { [string]: any }?,
	accessoriesFolder: Folder,
	rigReferenceFolder: Folder
): (number, string?)
	local alignedCount = 0

	for _, child in ipairs(accessoriesFolder:GetChildren()) do
		if child:IsA("Accessory") and isManagedClone(child) then
			local attachmentName, _, boundRegion = getManagedAccessoryBinding(child)
			local boundTargetPartName = getManagedAccessoryTargetPartName(child)
			if attachmentName == nil then
				local _, handleAttachment = getHandleAndSingleAttachment(child)
				attachmentName = handleAttachment and handleAttachment.Name or nil
			end

			local region = boundRegion
			if region ~= nil and (not equippedState or equippedState[region] == nil) then
				continue
			end

			if attachmentName ~= nil then
				local targetPart, targetAttachmentWorldCFrame =
					resolveManagedAccessoryTarget(character, rigReferenceFolder, region, boundTargetPartName, attachmentName)
				if not (targetPart and targetAttachmentWorldCFrame) then
					return alignedCount, string.format(
						"Managed accessory %s could not resolve final attachment %s on %s.",
						child.Name,
						attachmentName,
						tostring(boundTargetPartName or "heuristic target")
					)
				end

				local success, alignError = alignAccessoryClone(child, targetPart, targetAttachmentWorldCFrame)
				if not success then
					return alignedCount, alignError
				end

				alignedCount += 1
			end
		end
	end

	return alignedCount, nil
end

local function getSnapshotSourceInstances(character: Model): (Folder, Humanoid?)
	local snapshotSource = ensureSnapshotSourceFolder(character)
	return snapshotSource, snapshotSource:FindFirstChildOfClass("Humanoid")
end

local function clearSnapshotAccessories(character: Model)
	local snapshotAccessoriesFolder = ensureSnapshotAccessoriesFolder(character)
	for _, child in ipairs(snapshotAccessoriesFolder:GetChildren()) do
		child:Destroy()
	end
end

local function hasSnapshotRigReference(character: Model): boolean
	local rigReferenceFolder = ensureSnapshotRigReferenceFolder(character)
	for _, partName in ipairs(ALL_RIG_PARTS) do
		local part = rigReferenceFolder:FindFirstChild(partName)
		if not (part and part:IsA("BasePart")) then
			return false
		end
	end

	return true
end

local function cloneReferencePart(part: BasePart): BasePart
	local clone = part:Clone()
	for _, child in ipairs(clone:GetChildren()) do
		if not child:IsA("Attachment") then
			child:Destroy()
		end
	end

	return clone
end

local function captureSnapshotRigReference(character: Model): (boolean, string?)
	local rigReferenceFolder = ensureSnapshotRigReferenceFolder(character)
	for _, child in ipairs(rigReferenceFolder:GetChildren()) do
		child:Destroy()
	end

	for _, partName in ipairs(ALL_RIG_PARTS) do
		local part = character:FindFirstChild(partName)
		if not (part and part:IsA("BasePart")) then
			return false, string.format("Character appearance snapshot requires body part %s.", partName)
		end

		local clone = cloneReferencePart(part)
		setDebugAttributes(clone, partName, true, "AppearanceRigReference")
		clone.Parent = rigReferenceFolder
	end

	return true, nil
end

local function iterSnapshotAccessorySources(character: Model): { Accessory }
	local accessories = {}
	local hiddenFolder = ensureHiddenNativeFolder(character)

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") and not isManagedClone(child) then
			accessories[#accessories + 1] = child
		end
	end

	for _, child in ipairs(hiddenFolder:GetChildren()) do
		if child:IsA("Accessory") and not isManagedClone(child) then
			accessories[#accessories + 1] = child
		end
	end

	return accessories
end

local function refreshSnapshotAccessories(character: Model): number
	local snapshotAccessoriesFolder = ensureSnapshotAccessoriesFolder(character)
	clearSnapshotAccessories(character)

	local accessoryCount = 0
	for _, accessory in ipairs(iterSnapshotAccessorySources(character)) do
		local clone = accessory:Clone()
		setDebugAttributes(clone, accessory.Name, true, "AppearanceAccessorySnapshot")
		clone.Parent = snapshotAccessoriesFolder
		accessoryCount += 1
	end

	snapshotAccessoriesFolder:SetAttribute("AppearanceSnapshotAccessoryCount", accessoryCount)
	return accessoryCount
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
	local rigReferenceReady = hasSnapshotRigReference(character)
	if not rigReferenceReady then
		local rigReferenceSuccess, rigReferenceError = captureSnapshotRigReference(character)
		if not rigReferenceSuccess then
			return false, rigReferenceError
		end
	end

	refreshSnapshotAccessories(character)

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
	local rigReferenceFolder = ensureSnapshotRigReferenceFolder(character)
	local snapshotAccessoriesFolder = ensureSnapshotAccessoriesFolder(character)

	local visualPartsByName = buildVisualPartLookup(character)
	local accessoriesSeenCount, accessoriesClonedCount = applyAccessories(
		character,
		accessoriesFolder,
		hiddenFolder,
		equippedState,
		visualPartsByName,
		rigReferenceFolder,
		snapshotAccessoriesFolder
	)
	local alignedCount, alignmentError =
		refreshManagedAccessoryAlignmentInternal(character, equippedState, accessoriesFolder, rigReferenceFolder)
	if alignmentError then
		return false, alignmentError
	end

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
	appearanceFolder:SetAttribute("AccessoriesAlignedCount", alignedCount)
	appearanceFolder:SetAttribute("HiddenNativeCount", #hiddenFolder:GetChildren())
	appearanceFolder:SetAttribute("AppearanceHostCount", hostCount)
	appearanceFolder:SetAttribute("AppearanceHostHumanoidCount", humanoidCount)
	appearanceFolder:SetAttribute("ClothingHostCount", clothingCount)
	appearanceFolder:SetAttribute("AppearanceSnapshotReady", true)
	return true, nil
end

function CharacterAppearanceHostApplier.RefreshManagedAccessoryAlignment(
	character: Model,
	equippedState: { [string]: any }?
): (boolean, string?)
	if not (character and character:IsA("Model")) then
		return false, "Character must be a Model."
	end

	local appearanceFolder = character:FindFirstChild(APPEARANCE_FOLDER_NAME)
	if not (appearanceFolder and appearanceFolder:IsA("Folder")) then
		return true, nil
	end

	local accessoriesFolder = appearanceFolder:FindFirstChild(APPLIED_ACCESSORIES_FOLDER_NAME)
	if not (accessoriesFolder and accessoriesFolder:IsA("Folder")) then
		return true, nil
	end

	local rigReferenceFolder = ensureSnapshotRigReferenceFolder(character)
	local alignedCount, alignmentError =
		refreshManagedAccessoryAlignmentInternal(character, equippedState, accessoriesFolder, rigReferenceFolder)
	if alignmentError then
		return false, alignmentError
	end

	appearanceFolder:SetAttribute("AccessoriesAlignedCount", alignedCount)
	return true, nil
end

return CharacterAppearanceHostApplier
