local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameAssetResolver = require(ReplicatedStorage.Shared.Assets.GameAssetResolver)
local AccessoryConfig = require(ReplicatedStorage.Shared.Config.AccessoryConfig)
local NumberFormatter = require(ReplicatedStorage.Shared.Formatting.NumberFormatter)

local AccessoryPresentation = {}

local placeholderModelsById: { [string]: Model } = {}
local assetPreviewModelsById: { [string]: Model } = {}
local GEAR_MODELS_PATH = { "Models", "Gear" }
local HEAD_ACCESSORY_MODELS_PATH = { "Models", "HeadAccessories" }

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

local STAT_LINE_DEFINITIONS = table.freeze({
	{
		key = "luckBonus",
		label = "Luck",
		kind = "percentDelta",
		color = Color3.fromRGB(113, 230, 139),
	},
	{
		key = "luckMultiplier",
		label = "Luck",
		kind = "percentMultiplier",
		color = Color3.fromRGB(113, 230, 139),
	},
	{
		key = "rollSpeedBonus",
		label = "Roll Speed",
		kind = "percentDelta",
		color = Color3.fromRGB(255, 221, 95),
	},
	{
		key = "passiveIncomePerSecondBonus",
		label = "Income",
		kind = "moneyPerSecond",
		color = Color3.fromRGB(94, 239, 151),
	},
	{
		key = "passiveIncomeMultiplier",
		label = "Income",
		kind = "percentMultiplier",
		color = Color3.fromRGB(94, 239, 151),
	},
	{
		key = "damageBonus",
		label = "Damage",
		kind = "flat",
		color = Color3.fromRGB(255, 128, 77),
	},
	{
		key = "damageMultiplier",
		label = "Damage",
		kind = "percentMultiplier",
		color = Color3.fromRGB(255, 128, 77),
	},
	{
		key = "healthBonus",
		label = "Health",
		kind = "flat",
		color = Color3.fromRGB(255, 97, 128),
	},
	{
		key = "healthMultiplier",
		label = "Health",
		kind = "percentMultiplier",
		color = Color3.fromRGB(255, 97, 128),
	},
	{
		key = "speedBonus",
		label = "Speed",
		kind = "flat",
		color = Color3.fromRGB(91, 218, 255),
	},
	{
		key = "speedMultiplier",
		label = "Speed",
		kind = "percentMultiplier",
		color = Color3.fromRGB(91, 218, 255),
	},
})

local function buildStatRowData(definition: any, rawValue: any): any?
	if rawValue == nil then
		return nil
	end

	local value = tonumber(rawValue) or 0
	local amountText = nil
	local signValue = value

	if definition.kind == "percentDelta" then
		if value == 0 then
			return nil
		end
		amountText = string.format("%s%%", formatNumberish(math.abs(value) * 100))
	elseif definition.kind == "percentMultiplier" then
		if value <= 0 or value == 1 then
			return nil
		end
		local percentGain = (value - 1) * 100
		if percentGain == 0 then
			return nil
		end
		signValue = percentGain
		amountText = string.format("%s%%", formatNumberish(math.abs(percentGain)))
	elseif definition.kind == "moneyPerSecond" then
		if value == 0 then
			return nil
		end
		amountText = string.format("$%s/s", formatNumberish(math.abs(value)))
	elseif definition.kind == "flat" then
		if value == 0 then
			return nil
		end
		amountText = formatNumberish(math.abs(value))
	else
		return nil
	end

	local sign = if signValue < 0 then "-" else "+"
	return {
		valueText = string.format("%s %s", sign, amountText),
		labelText = definition.label,
		color = definition.color,
	}
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
	if tonumber(bonuses.damageMultiplier) and bonuses.damageMultiplier > 1 then
		return `STR {formatPercentDelta(bonuses.damageMultiplier - 1)}`
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
	core.Size = if config.slot == "HeadAccessory"
		then Vector3.new(2, 2, 2)
		else Vector3.new(1, 4, 1)
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

local function getAssetSource(config: AccessoryConfig.AccessoryConfigEntry): Instance?
	local assetModelName = config.assetModelName
	if typeof(assetModelName) ~= "string" or assetModelName == "" then
		return nil
	end

	if config.slot == "GearAccessory" then
		local model = GameAssetResolver.Find(GEAR_MODELS_PATH, assetModelName)
		return if model and model:IsA("Model") then model else nil
	end

	if config.slot == "HeadAccessory" then
		local accessory = GameAssetResolver.Find(HEAD_ACCESSORY_MODELS_PATH, assetModelName)
		return if accessory and accessory:IsA("Accessory") then accessory else nil
	end

	return nil
end

local function sanitizePreviewClone(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if FORBIDDEN_CLASSES[descendant.ClassName] then
			descendant:Destroy()
		end
	end
end

local function wrapAccessoryForPreview(config: AccessoryConfig.AccessoryConfigEntry, accessory: Accessory): Model?
	local cached = assetPreviewModelsById[config.id]
	if cached then
		return cached
	end

	local wrapper = Instance.new("Model")
	wrapper.Name = config.label

	local clone = accessory:Clone()
	sanitizePreviewClone(clone)
	clone.Parent = wrapper

	assetPreviewModelsById[config.id] = wrapper
	return wrapper
end

local function getAssetModel(config: AccessoryConfig.AccessoryConfigEntry): Model?
	local source = getAssetSource(config)
	if source and source:IsA("Model") then
		return source
	end
	if source and source:IsA("Accessory") then
		return wrapAccessoryForPreview(config, source)
	end
	return nil
end

function AccessoryPresentation.BuildStatRows(configOrId: AccessoryConfig.AccessoryConfigEntry | string): { any }
	local config = if typeof(configOrId) == "string" then AccessoryConfig.Get(configOrId) else configOrId
	local bonuses = if config and typeof(config.bonuses) == "table" then config.bonuses else nil
	if not bonuses then
		return {}
	end

	local rows = {}
	for _, definition in ipairs(STAT_LINE_DEFINITIONS) do
		local rowData = buildStatRowData(definition, bonuses[definition.key])
		if rowData then
			table.insert(rows, rowData)
		end
	end
	return rows
end

function AccessoryPresentation.GetPlaceholderModel(configOrId: AccessoryConfig.AccessoryConfigEntry | string): Model?
	local config = if typeof(configOrId) == "string" then AccessoryConfig.Get(configOrId) else configOrId
	if not config then
		return nil
	end

	local assetModel = getAssetModel(config)
	if assetModel then
		return assetModel
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
	local damageBonusText = "+" .. formatNumberish(tonumber(bonuses.damageBonus) or 0)
	local speedBonusText = "+" .. formatNumberish(tonumber(bonuses.speedBonus) or 0)
	local healthBonusText = "+" .. formatNumberish(tonumber(bonuses.healthBonus) or 0)
	local damageMultiplier = math.max(1, tonumber(bonuses.damageMultiplier) or 1)
	local speedMultiplier = math.max(1, tonumber(bonuses.speedMultiplier) or 1)
	local healthMultiplier = math.max(1, tonumber(bonuses.healthMultiplier) or 1)
	if damageMultiplier > 1 then
		damageBonusText = formatPercentDelta(damageMultiplier - 1)
	end
	if speedMultiplier > 1 then
		speedBonusText = formatPercentDelta(speedMultiplier - 1)
	end
	if healthMultiplier > 1 then
		healthBonusText = formatPercentDelta(healthMultiplier - 1)
	end

	return {
		itemType = "accessory",
		accessoryId = config.id,
		accessoryConfig = config,
		cardNameText = string.format('<font color="%s">%s</font>', toRichTextColor(displayColor), label),
		cardUsageText = getPrimaryUsageText(config),
		bundleText = string.format("Accessory: <font color=\"%s\">%s</font>", toRichTextColor(displayColor), label),
		inventoryBundleText = string.format("Accessory: <font color=\"%s\">%s</font>", toRichTextColor(displayColor), label),
		partText = if config.slot == "HeadAccessory"
			then "Slot: Head Accessory"
			else "Slot: Gear",
		rarityText = string.format("Tier: <font color=\"%s\">%s</font>", toRichTextColor(displayColor), escapeRichText(config.tierLabel)),
		mutationText = string.format("Luck: %s %s", formatPercentDelta(luckValue), formatMultiplier(luckMultiplier)),
		sizeText = string.format("Roll Speed: %s", formatPercentDelta(tonumber(bonuses.rollSpeedBonus) or 0)),
		cashText = string.format("Income: +$%s/s %s", formatNumberish(incomeBonus), formatMultiplier(incomeMultiplier)),
		chanceText = string.format(
			"Stats: STR %s SPD %s HP %s",
			damageBonusText,
			speedBonusText,
			healthBonusText
		),
		statRows = AccessoryPresentation.BuildStatRows(config),
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
