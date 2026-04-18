local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NumberFormatter = require(ReplicatedStorage.Shared.Formatting.NumberFormatter)
local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local BodyPartPresentation = require(ReplicatedStorage.Shared.UI.BodyPartPresentation)

local AuraPresentation = {}

local placeholderModelsByAuraId: { [string]: Model } = {}

local function toRichTextColor(color: Color3): string
	return string.format(
		"rgb(%d,%d,%d)",
		math.round(color.R * 255),
		math.round(color.G * 255),
		math.round(color.B * 255)
	)
end

local function formatNumberish(value: number?): string
	local numericValue = tonumber(value) or 0
	if math.abs(numericValue - math.round(numericValue)) < 0.005 then
		return NumberFormatter.Format(math.round(numericValue))
	end

	return string.format("%.2f", numericValue):gsub("0+$", ""):gsub("%.$", "")
end

local function formatPercentDelta(value: number?): string
	local numericValue = math.max(0, tonumber(value) or 0) * 100
	return string.format("+%s%%", formatNumberish(numericValue))
end

local function formatMultiplier(value: number?): string
	local numericValue = math.max(0, tonumber(value) or 0)
	if math.abs(numericValue - math.round(numericValue * 10) / 10) < 0.005 then
		return string.format("%.1f", math.round(numericValue * 10) / 10)
	end

	return string.format("%.2f", numericValue):gsub("0+$", ""):gsub("%.$", "")
end

local function escapeRichText(text: any): string
	return tostring(text)
		:gsub("&", "&amp;")
		:gsub("<", "&lt;")
		:gsub(">", "&gt;")
		:gsub('"', "&quot;")
		:gsub("'", "&apos;")
end

local function getAurasFolder(): Folder?
	local gameAssets = ReplicatedStorage:WaitForChild("GameAssets", 10)
	if not (gameAssets and gameAssets:IsA("Folder")) then
		return nil
	end

	local auras = gameAssets:WaitForChild("Auras", 10)
	if auras and auras:IsA("Folder") then
		return auras
	end

	return nil
end

local function buildUnlockText(auraConfig: AuraConfig.AuraConfigEntry): string
	local setConfig = BodyPartsCatalog.GetSet(auraConfig.setId)
	local setName = if setConfig then setConfig.displayName else auraConfig.label
	return string.format("Unlock: %s 6/6", setName)
end

local function createPlaceholderModel(auraConfig: AuraConfig.AuraConfigEntry): Model
	local model = Instance.new("Model")
	model.Name = auraConfig.label

	local core = Instance.new("Part")
	core.Name = "Core"
	core.Shape = Enum.PartType.Ball
	core.Material = Enum.Material.Neon
	core.Color = auraConfig.displayColor
	core.Size = Vector3.new(2.2, 2.2, 2.2)
	core.CFrame = CFrame.new(0, 1.4, 0)
	core.Parent = model

	local shell = Instance.new("Part")
	shell.Name = "Shell"
	shell.Shape = Enum.PartType.Ball
	shell.Material = Enum.Material.ForceField
	shell.Color = auraConfig.displayColor
	shell.Transparency = 0.35
	shell.Size = Vector3.new(3.4, 3.4, 3.4)
	shell.CFrame = core.CFrame
	shell.Parent = model

	local pedestal = Instance.new("Part")
	pedestal.Name = "Pedestal"
	pedestal.Material = Enum.Material.SmoothPlastic
	pedestal.Color = Color3.fromRGB(28, 30, 36)
	pedestal.Size = Vector3.new(3.4, 0.35, 3.4)
	pedestal.CFrame = CFrame.new(0, 0, 0)
	pedestal.Parent = model

	return model
end

function AuraPresentation.GetPlaceholderModel(auraConfigOrId: AuraConfig.AuraConfigEntry | string): Model?
	local auraConfig = if typeof(auraConfigOrId) == "string"
		then AuraConfig.Get(auraConfigOrId)
		else auraConfigOrId
	if not auraConfig then
		return nil
	end

	local cached = placeholderModelsByAuraId[auraConfig.id]
	if cached then
		return cached
	end

	local placeholder = createPlaceholderModel(auraConfig)
	placeholderModelsByAuraId[auraConfig.id] = placeholder
	return placeholder
end

function AuraPresentation.GetBundleModel(auraConfigOrId: AuraConfig.AuraConfigEntry | string): Model?
	local auraConfig = if typeof(auraConfigOrId) == "string"
		then AuraConfig.Get(auraConfigOrId)
		else auraConfigOrId
	if not auraConfig then
		return nil
	end

	local aurasFolder = getAurasFolder()
	if not aurasFolder then
		return AuraPresentation.GetPlaceholderModel(auraConfig)
	end

	local model = aurasFolder:FindFirstChild(auraConfig.assetModelName)
	if model and model:IsA("Model") then
		return model
	end

	return AuraPresentation.GetPlaceholderModel(auraConfig)
end

function AuraPresentation.BuildPreviewPresentation(payload: any)
	local source = if typeof(payload) == "table" then payload else {}
	local record = if typeof(source.record) == "table" then source.record else source
	local auraConfig = source.auraConfig
	if auraConfig == nil and record and typeof(record.auraId) == "string" then
		auraConfig = AuraConfig.Get(record.auraId)
	end
	if not auraConfig then
		return nil
	end

	local setConfig = BodyPartsCatalog.GetSet(auraConfig.setId)
	local setRarityLabel = if setConfig and setConfig.rollDisplay and typeof(setConfig.rollDisplay.rarity) == "string"
		then setConfig.rollDisplay.rarity
		else auraConfig.tierLabel
	local tierLabel = if setConfig and setConfig.rollDisplay and typeof(setConfig.rollDisplay.rarity) == "string"
		then string.format("%s Aura", setConfig.rollDisplay.rarity)
		else auraConfig.tierLabel
	local rarityStyle = BodyPartPresentation.ResolveSetRarityStyle(setConfig, setRarityLabel, auraConfig.displayColor)
	local serialNumber = tonumber(record and record.serialNumber)
	local serialDisplay = if serialNumber
		then NumberFormatter.Format(math.max(1, math.floor(serialNumber)))
		else nil
	local displayColor = rarityStyle.textColor
	local labelText = escapeRichText(auraConfig.label)
	local tierText = escapeRichText(tierLabel)

	return {
		itemType = "aura",
		auraId = auraConfig.id,
		auraConfig = auraConfig,
		cardUsageText = "",
		cardNameText = labelText,
		bundleText = string.format(
			'Aura: <font color="%s">%s</font>',
			toRichTextColor(displayColor),
			labelText
		),
		inventoryBundleText = string.format(
			'Aura: <font color="%s">%s</font>',
			toRichTextColor(displayColor),
			labelText
		),
		partText = buildUnlockText(auraConfig),
		rarityText = string.format(
			'Tier: <font color="%s">%s</font>',
			toRichTextColor(displayColor),
			tierText
		),
		mutationText = string.format("Luck Bonus: %s", formatPercentDelta(auraConfig.bonuses.luckBonus)),
		sizeText = string.format("Roll Speed Bonus: %s", formatPercentDelta(auraConfig.bonuses.rollSpeedBonus)),
		cashText = string.format("Money Multiplier: x%s", formatMultiplier(auraConfig.bonuses.moneyMultiplier)),
		chanceText = string.format(
			"Passive Income Bonus: +%s/s",
			formatNumberish(math.max(0, tonumber(auraConfig.bonuses.passiveIncomePerSecondBonus) or 0))
		),
		inventoryEverRolledText = if serialDisplay then string.format("#%s", serialDisplay) else nil,
		bundleFontFace = rarityStyle.fontFace,
		rarityFontFace = rarityStyle.fontFace,
		cardAccentColor = rarityStyle.accentColor,
		baseFillColor = rarityStyle.baseFillColor,
		selectedFillColor = rarityStyle.selectedFillColor,
		bundleModel = AuraPresentation.GetBundleModel(auraConfig),
		iconTexture = AuraConfig.ResolveIconTexture(auraConfig),
	}
end

return table.freeze(AuraPresentation)
