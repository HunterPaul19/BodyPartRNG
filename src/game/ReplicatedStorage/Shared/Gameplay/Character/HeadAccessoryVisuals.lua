local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameAssetResolver = require(ReplicatedStorage.Shared.Assets.GameAssetResolver)
local AccessoryScaleUtils = require(script.Parent.AccessoryScaleUtils)

local HeadAccessoryVisuals = {}

local HEAD_ACCESSORY_MODELS_PATH = { "Models", "HeadAccessories" }
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

function HeadAccessoryVisuals.Clear(character: Model?)
	if not (character and character:IsA("Model")) then
		return
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") and child:GetAttribute("VisualOnlyHeadAccessory") == true then
			child:Destroy()
		end
	end
end

local function sanitizeClone(accessory: Accessory)
	for _, descendant in ipairs(accessory:GetDescendants()) do
		if FORBIDDEN_CLASSES[descendant.ClassName] then
			descendant:Destroy()
		end
	end

	for _, descendant in ipairs(accessory:GetDescendants()) do
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

local function getNativePart(character: Model, partName: string): BasePart?
	local part = character:FindFirstChild(partName)
	return if part and part:IsA("BasePart") then part else nil
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

local function getTargetPart(character: Model, targetPartName: string): BasePart?
	local managedTarget = getManagedVisualTarget(character, targetPartName)
	if managedTarget then
		return managedTarget
	end

	return getNativePart(character, targetPartName)
end

local function getHeadAccessory(config: any): Accessory?
	local assetModelName = if typeof(config) == "table" then config.assetModelName else nil
	if typeof(assetModelName) ~= "string" or assetModelName == "" then
		return nil
	end

	local accessory = GameAssetResolver.Find(HEAD_ACCESSORY_MODELS_PATH, assetModelName)
	return if accessory and accessory:IsA("Accessory") then accessory else nil
end

function HeadAccessoryVisuals.Apply(character: Model, config: any?): (boolean, string?)
	if not (character and character:IsA("Model")) then
		return false, "Character must be a Model."
	end

	HeadAccessoryVisuals.Clear(character)

	if typeof(config) ~= "table" then
		return true, nil
	end
	if typeof(config.assetModelName) ~= "string" or config.assetModelName == "" then
		return true, nil
	end

	local sourceAccessory = getHeadAccessory(config)
	if not sourceAccessory then
		return false, string.format("Head accessory visual asset '%s' was not found.", tostring(config.assetModelName))
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "Character is missing a Humanoid."
	end

	local sourceHead = getNativePart(character, "Head")
	if not sourceHead then
		return false, "Character is missing a source Head part."
	end

	local targetHead = getTargetPart(character, "Head")
	if not targetHead then
		return false, "Character is missing a head accessory target part."
	end

	local clone = sourceAccessory:Clone()
	clone.Name = "EquippedHeadAccessoryVisual"
	clone:SetAttribute("HeadAccessoryId", tostring(config.id or ""))
	clone:SetAttribute("HeadAccessoryAssetModelName", sourceAccessory.Name)
	clone:SetAttribute("VisualOnlyHeadAccessory", true)
	sanitizeClone(clone)

	local handle = clone:FindFirstChild("Handle")
	if not (handle and handle:IsA("BasePart")) then
		clone:Destroy()
		return false, string.format("Head accessory visual asset '%s' has no Handle part.", sourceAccessory.Name)
	end

	local scaled, scaleError = AccessoryScaleUtils.ScaleAccessoryToPartSize(clone, sourceHead.Size, targetHead.Size)
	if not scaled then
		clone:Destroy()
		return false, scaleError
	end

	local addOk, addError = pcall(function()
		humanoid:AddAccessory(clone)
	end)
	if not addOk then
		clone:Destroy()
		return false, string.format("Failed to attach head accessory visual '%s': %s", sourceAccessory.Name, tostring(addError))
	end

	return true, nil
end

return table.freeze(HeadAccessoryVisuals)
