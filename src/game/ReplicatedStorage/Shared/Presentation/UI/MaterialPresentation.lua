local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CraftingMaterialConfig = require(ReplicatedStorage.Shared.Config.CraftingMaterialConfig)
local NumberFormatter = require(ReplicatedStorage.Shared.Formatting.NumberFormatter)

local MaterialPresentation = {}

local placeholderModelsById: { [string]: Model } = {}

local function toRichTextColor(color: Color3): string
	return string.format(
		"rgb(%d,%d,%d)",
		math.round(color.R * 255),
		math.round(color.G * 255),
		math.round(color.B * 255)
	)
end

local function escapeRichText(text: any): string
	return tostring(text)
		:gsub("&", "&amp;")
		:gsub("<", "&lt;")
		:gsub(">", "&gt;")
		:gsub('"', "&quot;")
		:gsub("'", "&apos;")
end

local function formatWholeNumber(value: any): string
	return NumberFormatter.Format(math.max(0, math.floor(tonumber(value) or 0)))
end

local function createPlaceholderModel(config: CraftingMaterialConfig.CraftingMaterialConfigEntry): Model
	local model = Instance.new("Model")
	model.Name = config.label

	local core = Instance.new("Part")
	core.Name = "Material"
	core.Material = Enum.Material.Neon
	core.Color = config.displayColor
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(1.8, 1.8, 1.8)
	core.CFrame = CFrame.new(0, 1, 0)
	core.Parent = model

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Material = Enum.Material.SmoothPlastic
	base.Color = Color3.fromRGB(28, 30, 36)
	base.Size = Vector3.new(3.2, 0.25, 3.2)
	base.CFrame = CFrame.new(0, -0.15, 0)
	base.Parent = model

	return model
end

function MaterialPresentation.GetPlaceholderModel(configOrId: CraftingMaterialConfig.CraftingMaterialConfigEntry | string): Model?
	local config = if typeof(configOrId) == "string" then CraftingMaterialConfig.Get(configOrId) else configOrId
	if not config then
		return nil
	end

	local cached = placeholderModelsById[config.id]
	if cached then
		return cached
	end

	local placeholder = createPlaceholderModel(config)
	placeholderModelsById[config.id] = placeholder
	return placeholder
end

function MaterialPresentation.BuildPreviewPresentation(payload: any)
	local source = if typeof(payload) == "table" then payload else {}
	local record = if typeof(source.record) == "table" then source.record else nil
	local config = source.materialConfig
	if config == nil and source.materialId ~= nil then
		config = CraftingMaterialConfig.Get(source.materialId)
	end
	if config == nil and record and typeof(record.materialId) == "string" then
		config = CraftingMaterialConfig.Get(record.materialId)
	end
	if not config then
		return nil
	end

	local amount = math.max(0, math.floor(tonumber(record and record.amount) or 0))
	local displayColor = config.displayColor
	local labelText = escapeRichText(config.label)
	local iconTexture = CraftingMaterialConfig.ResolveIconTexture(config)
	local sellPrice = CraftingMaterialConfig.GetSellPrice(config.id)

	return {
		itemType = "material",
		materialId = config.id,
		materialConfig = config,
		cardNameText = string.format('<font color="%s">%s</font>', toRichTextColor(displayColor), labelText),
		cardUsageText = string.format("x%s", formatWholeNumber(amount)),
		bundleText = string.format("Material: <font color=\"%s\">%s</font>", toRichTextColor(displayColor), labelText),
		inventoryBundleText = string.format("Material: <font color=\"%s\">%s</font>", toRichTextColor(displayColor), labelText),
		partText = escapeRichText(config.description),
		rarityText = string.format("Owned: x%s", formatWholeNumber(amount)),
		mutationText = "Used for crafting",
		sizeText = string.format("Material ID: %s", escapeRichText(config.id)),
		cashText = string.format("Sell Each: $%s", formatWholeNumber(sellPrice)),
		chanceText = "",
		inventoryEverRolledText = nil,
		bundleModel = MaterialPresentation.GetPlaceholderModel(config),
		iconTexture = iconTexture,
		cardBackgroundTexture = iconTexture,
		cardAccentColor = displayColor,
		baseFillColor = displayColor,
		selectedFillColor = displayColor:Lerp(Color3.new(1, 1, 1), 0.3),
		preferIconOverViewport = iconTexture ~= nil,
	}
end

return table.freeze(MaterialPresentation)
