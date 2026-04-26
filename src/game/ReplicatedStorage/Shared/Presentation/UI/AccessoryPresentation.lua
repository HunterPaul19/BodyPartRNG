local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AccessoryConfig = require(ReplicatedStorage.Shared.Config.AccessoryConfig)
local NumberFormatter = require(ReplicatedStorage.Shared.Formatting.NumberFormatter)

local AccessoryPresentation = {}

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

local function formatNumberish(value: any): string
	local numericValue = tonumber(value) or 0
	if math.abs(numericValue - math.round(numericValue)) < 0.005 then
		return NumberFormatter.Format(math.round(numericValue))
	end

	return string.format("%.2f", numericValue):gsub("0+$", ""):gsub("%.$", "")
end

local function formatPercentDelta(value: any): string
	return string.format("+%s%%", formatNumberish((tonumber(value) or 0) * 100))
end

local function formatMultiplier(value: any): string
	return string.format("x%s", formatNumberish(tonumber(value) or 1))
end

local function getPrimaryUsageText(config: AccessoryConfig.AccessoryConfigEntry): string
	local bonuses = config.bonuses or {}
	if tonumber(bonuses.luckMultiplier) and bonuses.luckMultiplier > 1 then
		return `Luck {formatMultiplier(bonuses.luckMultiplier)}`
	end
	if tonumber(bonuses.passiveIncomeMultiplier) and bonuses.passiveIncomeMultiplier > 1 then
		return `Income {formatMultiplier(bonuses.passiveIncomeMultiplier)}`
	end
	if tonumber(bonuses.luckBonus) and bonuses.luckBonus ~= 0 then
		return `Luck {formatPercentDelta(bonuses.luckBonus)}`
	end
	if tonumber(bonuses.damageBonus) and bonuses.damageBonus ~= 0 then
		return `STR +{formatNumberish(bonuses.damageBonus)}`
	end
	return config.tierLabel
end

local function createPlaceholderModel(config: AccessoryConfig.AccessoryConfigEntry): Model
	local model = Instance.new("Model")
	model.Name = config.label

	local core = Instance.new("Part")
	core.Name = "Accessory"
	core.Material = Enum.Material.Neon
	core.Color = config.displayColor
	core.Shape = if config.slot == "HeadAccessory" then Enum.PartType.Ball else Enum.PartType.Block
	core.Size = if config.slot == "HeadAccessory" then Vector3.new(2, 2, 2) else Vector3.new(3, 1, 1.5)
	core.CFrame = CFrame.new(0, 1, 0)
	core.Parent = model

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Material = Enum.Material.SmoothPlastic
	base.Color = Color3.fromRGB(28, 30, 36)
	base.Size = Vector3.new(3.4, 0.25, 3.4)
	base.CFrame = CFrame.new(0, -0.2, 0)
	base.Parent = model

	return model
end

function AccessoryPresentation.GetPlaceholderModel(configOrId: AccessoryConfig.AccessoryConfigEntry | string): Model?
	local config = if typeof(configOrId) == "string" then AccessoryConfig.Get(configOrId) else configOrId
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

function AccessoryPresentation.BuildPreviewPresentation(payload: any)
	local source = if typeof(payload) == "table" then payload else {}
	local record = if typeof(source.record) == "table" then source.record else source
	local config = source.accessoryConfig
	if config == nil and record and typeof(record.accessoryId) == "string" then
		config = AccessoryConfig.Get(record.accessoryId)
	end
	if not config then
		return nil
	end

	local label = escapeRichText(config.label)
	local displayColor = config.displayColor
	local bonuses = config.bonuses or {}
	local luckValue = (tonumber(bonuses.luckBonus) or 0)
	local luckMultiplier = math.max(1, tonumber(bonuses.luckMultiplier) or 1)
	local incomeBonus = tonumber(bonuses.passiveIncomePerSecondBonus) or 0
	local incomeMultiplier = math.max(1, tonumber(bonuses.passiveIncomeMultiplier) or 1)

	return {
		itemType = "accessory",
		accessoryId = config.id,
		accessoryConfig = config,
		cardNameText = string.format('<font color="%s">%s</font>', toRichTextColor(displayColor), label),
		cardUsageText = getPrimaryUsageText(config),
		bundleText = string.format("Accessory: <font color=\"%s\">%s</font>", toRichTextColor(displayColor), label),
		inventoryBundleText = string.format("Accessory: <font color=\"%s\">%s</font>", toRichTextColor(displayColor), label),
		partText = if config.slot == "HeadAccessory" then "Slot: Head Accessory" else "Slot: Arm Accessory",
		rarityText = string.format("Tier: <font color=\"%s\">%s</font>", toRichTextColor(displayColor), escapeRichText(config.tierLabel)),
		mutationText = string.format("Luck: %s %s", formatPercentDelta(luckValue), formatMultiplier(luckMultiplier)),
		sizeText = string.format("Roll Speed: %s", formatPercentDelta(tonumber(bonuses.rollSpeedBonus) or 0)),
		cashText = string.format("Income: +$%s/s %s", formatNumberish(incomeBonus), formatMultiplier(incomeMultiplier)),
		chanceText = string.format(
			"Stats: STR +%s SPD +%s HP +%s",
			formatNumberish(tonumber(bonuses.damageBonus) or 0),
			formatNumberish(tonumber(bonuses.speedBonus) or 0),
			formatNumberish(tonumber(bonuses.healthBonus) or 0)
		),
		inventoryEverRolledText = nil,
		bundleModel = AccessoryPresentation.GetPlaceholderModel(config),
		iconTexture = if typeof(config.iconTexture) == "string" and config.iconTexture ~= "" then config.iconTexture else nil,
		cardAccentColor = displayColor,
		baseFillColor = displayColor,
		selectedFillColor = displayColor:Lerp(Color3.new(1, 1, 1), 0.3),
		preferIconOverViewport = false,
	}
end

return table.freeze(AccessoryPresentation)
