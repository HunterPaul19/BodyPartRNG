local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameAssetResolver = require(ReplicatedStorage.Shared.Assets.GameAssetResolver)
local AccessoryScaleUtils = require(script.Parent.AccessoryScaleUtils)
local BodyPartVisuals = require(script.Parent.BodyPartVisuals)

local GearVisuals = {}

local GEAR_FOLDER_NAME = "CharacterGearVisuals"
local GEAR_MODELS_PATH = { "Models", "Gear" }
local DEFAULT_TARGET_PART_NAME = "RightHand"
local APPLIED_BODY_PARTS_FOLDER_NAME = "CharacterBodyParts"

local FORBIDDEN_CLASSES = table.freeze({
	Script = true,
	LocalScript = true,
	ModuleScript = true,
	RemoteEvent = true,
	RemoteFunction = true,
	BindableEvent = true,
	BindableFunction = true,
	Tool = true,
	HopperBin = true,
	ClickDetector = true,
	ProximityPrompt = true,
	TouchTransmitter = true,
	ScreenGui = true,
	BillboardGui = true,
	SurfaceGui = true,
})

local function ensureFolder(character: Model): Folder
	local folder = character:FindFirstChild(GEAR_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end
	if folder then
		folder:Destroy()
	end

	folder = Instance.new("Folder")
	folder.Name = GEAR_FOLDER_NAME
	folder.Parent = character
	return folder
end

function GearVisuals.Clear(character: Model?)
	if not (character and character:IsA("Model")) then
		return
	end

	local folder = character:FindFirstChild(GEAR_FOLDER_NAME)
	if folder then
		folder:Destroy()
	end
end

local function sanitizeClone(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if FORBIDDEN_CLASSES[descendant.ClassName] then
			descendant:Destroy()
		end
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.Massless = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		elseif descendant:IsA("Sound") then
			descendant.Playing = false
		end
	end
end

local function getManagedVisualTarget(character: Model, targetPartName: string): BasePart?
	local appliedFolder = character:FindFirstChild(APPLIED_BODY_PARTS_FOLDER_NAME)
	if not appliedFolder then
		return nil
	end

	for _, descendant in ipairs(appliedFolder:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == targetPartName then
			return descendant
		end
	end

	return nil
end

local function getNativeTargetPart(character: Model, targetPartName: string): BasePart?
	local nativeTarget = character:FindFirstChild(targetPartName)
	return if nativeTarget and nativeTarget:IsA("BasePart") then nativeTarget else nil
end

local function getTargetPart(character: Model, targetPartName: string): BasePart?
	local managedTarget = getManagedVisualTarget(character, targetPartName)
	if managedTarget then
		return managedTarget
	end

	return getNativeTargetPart(character, targetPartName)
end

local function getDirectAttachment(part: BasePart, attachmentName: string): Attachment?
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("Attachment") and child.Name == attachmentName then
			return child
		end
	end

	return nil
end

local function getTargetWorldCFrame(targetPart: BasePart): CFrame
	local rightGripAttachment = getDirectAttachment(targetPart, "RightGripAttachment")
	if rightGripAttachment then
		return rightGripAttachment.WorldCFrame
	end

	return targetPart.CFrame
end

local function scaleCFramePosition(cframe: CFrame, scaleFactor: number): CFrame
	if scaleFactor == 1 then
		return cframe
	end

	return CFrame.new(cframe.Position * scaleFactor) * cframe.Rotation
end

local function getPrimaryPart(model: Model): BasePart?
	if model.PrimaryPart then
		return model.PrimaryPart
	end

	local handle = model:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		model.PrimaryPart = handle
		return handle
	end

	local firstPart = model:FindFirstChildWhichIsA("BasePart", true)
	if firstPart then
		model.PrimaryPart = firstPart
	end
	return firstPart
end

local function weldModelToTarget(model: Model, targetPart: BasePart, primaryPart: BasePart)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= primaryPart then
			local weld = Instance.new("WeldConstraint")
			weld.Name = "GearVisualPartWeld"
			weld.Part0 = primaryPart
			weld.Part1 = descendant
			weld.Parent = descendant
		end
	end

	local gripWeld = Instance.new("WeldConstraint")
	gripWeld.Name = "GearVisualGripWeld"
	gripWeld.Part0 = targetPart
	gripWeld.Part1 = primaryPart
	gripWeld.Parent = primaryPart
end

local function getGearModel(config: any): Model?
	local assetModelName = if typeof(config) == "table" then config.assetModelName else nil
	if typeof(assetModelName) ~= "string" or assetModelName == "" then
		return nil
	end

	local model = GameAssetResolver.Find(GEAR_MODELS_PATH, assetModelName)
	return if model and model:IsA("Model") then model else nil
end

function GearVisuals.Apply(character: Model, config: any?): (boolean, string?)
	if not (character and character:IsA("Model")) then
		return false, "Character must be a Model."
	end

	GearVisuals.Clear(character)

	if typeof(config) ~= "table" then
		return true, nil
	end
	if typeof(config.assetModelName) ~= "string" or config.assetModelName == "" then
		return true, nil
	end

	local sourceModel = getGearModel(config)
	if not sourceModel then
		return false, string.format("Gear visual asset '%s' was not found.", tostring(config.assetModelName))
	end

	local targetPartName = sourceModel:GetAttribute("GearAttachmentPartName")
	if typeof(targetPartName) ~= "string" or targetPartName == "" then
		targetPartName = DEFAULT_TARGET_PART_NAME
	end

	local targetPart = getTargetPart(character, targetPartName)
	if not (targetPart and targetPart:IsA("BasePart")) then
		return false, string.format("Character is missing gear target part %s.", targetPartName)
	end

	local sourceReferencePart = getNativeTargetPart(character, targetPartName)
	if not sourceReferencePart then
		return false, string.format("Character is missing gear source part %s.", targetPartName)
	end

	local clone = sourceModel:Clone()
	clone.Name = "EquippedGearVisual"
	sanitizeClone(clone)

	local primaryPart = getPrimaryPart(clone)
	if not primaryPart then
		clone:Destroy()
		return false, string.format("Gear visual asset '%s' has no renderable parts.", sourceModel.Name)
	end

	local sourceReferenceSize = BodyPartVisuals.GetBaselinePartSize(character, targetPartName) or sourceReferencePart.Size
	local scaleFactor = AccessoryScaleUtils.ComputeUniformScaleFactor(sourceReferenceSize, targetPart.Size)
	local scaled, scaleError = AccessoryScaleUtils.ScaleModelToPartSize(clone, sourceReferenceSize, targetPart.Size)
	if not scaled then
		clone:Destroy()
		return false, scaleError
	end

	local grip = sourceModel:GetAttribute("GearGripCFrame")
	if typeof(grip) ~= "CFrame" then
		grip = CFrame.new()
	end
	grip = scaleCFramePosition(grip :: CFrame, scaleFactor)

	clone:PivotTo(getTargetWorldCFrame(targetPart) * (grip :: CFrame):Inverse())
	weldModelToTarget(clone, targetPart, primaryPart)

	local folder = ensureFolder(character)
	clone:SetAttribute("GearAccessoryId", tostring(config.id or ""))
	clone:SetAttribute("GearAssetModelName", sourceModel.Name)
	clone:SetAttribute("VisualOnlyGear", true)
	clone.Parent = folder

	return true, nil
end

return table.freeze(GearVisuals)
