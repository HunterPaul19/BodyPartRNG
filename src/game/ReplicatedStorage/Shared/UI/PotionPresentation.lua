local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NumberFormatter = require(ReplicatedStorage.Shared.Formatting.NumberFormatter)
local PotionConfig = require(ReplicatedStorage.Shared.Config.PotionConfig)
local LocalizationKeys = require(ReplicatedStorage.Shared.Localization.Keys)
local TranslationHelper = require(ReplicatedStorage.Shared.Localization.TranslationHelper)

local PotionPresentation = {}

local convertedModelsByPotionId: { [string]: Model } = {}

local function formatWholeNumber(value: number?): string
	return NumberFormatter.Format(math.max(0, math.floor(tonumber(value) or 0)))
end

local function formatMoney(value: number?): string
	return "$" .. formatWholeNumber(value)
end

local function formatDecimal(value: number?, minimumDecimals: number?): string
	local resolvedValue = tonumber(value) or 0
	local decimals = math.max(0, math.floor(tonumber(minimumDecimals) or 0))
	local formatted = string.format("%." .. tostring(math.max(decimals, 2)) .. "f", resolvedValue)
	formatted = string.gsub(formatted, "0+$", "")
	formatted = string.gsub(formatted, "%.$", "")
	return formatted
end

local function formatDuration(seconds: number?): string
	local totalSeconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local minutes = math.floor(totalSeconds / 60)
	local remainingSeconds = totalSeconds % 60
	return string.format("%02d:%02d", minutes, remainingSeconds)
end

local function escapeRichText(value: string): string
	local escaped = string.gsub(value, "&", "&amp;")
	escaped = string.gsub(escaped, "<", "&lt;")
	escaped = string.gsub(escaped, ">", "&gt;")
	return escaped
end

local function getPotionsFolder(): Folder?
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	if not (gameAssets and gameAssets:IsA("Folder")) then
		return nil
	end

	local potionsFolder = gameAssets:FindFirstChild("Potions")
	if potionsFolder and potionsFolder:IsA("Folder") then
		return potionsFolder
	end

	return nil
end

local function convertPotionToolToModel(tool: Tool, displayName: string): Model
	local model = Instance.new("Model")
	model.Name = displayName

	for _, child in ipairs(tool:GetChildren()) do
		child:Clone().Parent = model
	end

	return model
end

local function createFallbackModel(config: PotionConfig.PotionConfigEntry): Model
	local model = Instance.new("Model")
	model.Name = config.label

	local bottle = Instance.new("Part")
	bottle.Name = "Bottle"
	bottle.Shape = Enum.PartType.Cylinder
	bottle.Size = Vector3.new(1.2, 2.4, 1.2)
	bottle.Material = Enum.Material.Glass
	bottle.Color = Color3.fromRGB(82, 195, 255)
	bottle.CFrame = CFrame.new(0, 1.1, 0) * CFrame.Angles(0, 0, math.rad(90))
	bottle.Parent = model

	local cap = Instance.new("Part")
	cap.Name = "Cap"
	cap.Size = Vector3.new(0.7, 0.45, 0.7)
	cap.Material = Enum.Material.SmoothPlastic
	cap.Color = Color3.fromRGB(41, 45, 51)
	cap.CFrame = CFrame.new(0, 2.35, 0)
	cap.Parent = model

	return model
end

local function buildEffectText(config: PotionConfig.PotionConfigEntry): string
	if typeof(config.effectDescription) == "string" and config.effectDescription ~= "" then
		return config.effectDescription
	end
	if tonumber(config.passiveIncomeMultiplier) and config.passiveIncomeMultiplier > 1 then
		return string.format("Effect: x%s Passive Income", formatDecimal(config.passiveIncomeMultiplier))
	end
	if tonumber(config.luckBonus) and config.luckBonus > 0 then
		return string.format("Effect: +%s Luck", formatDecimal(config.luckBonus))
	end
	if tonumber(config.rollSpeedBonus) and config.rollSpeedBonus > 0 then
		return string.format("Effect: +%s Roll Speed", formatDecimal(config.rollSpeedBonus))
	end
	return "Effect: None"
end

function PotionPresentation.GetBundleModel(configOrId: PotionConfig.PotionConfigEntry | string): Model?
	local config = if typeof(configOrId) == "string" then PotionConfig.Get(configOrId) else configOrId
	if not config then
		return nil
	end

	local cachedModel = convertedModelsByPotionId[config.id]
	if cachedModel then
		return cachedModel
	end

	local potionsFolder = getPotionsFolder()
	local potionAsset = potionsFolder and potionsFolder:FindFirstChild(config.assetModelName) or nil
	local model = nil
	if potionAsset and potionAsset:IsA("Tool") then
		model = convertPotionToolToModel(potionAsset, config.label)
	else
		model = createFallbackModel(config)
	end

	convertedModelsByPotionId[config.id] = model
	return model
end

function PotionPresentation.BuildPreviewPresentation(payload: any)
	local source = if typeof(payload) == "table" then payload else {}
	local record = if typeof(source.record) == "table" then source.record else nil
	local config = source.config
	if config == nil and source.potionId ~= nil then
		config = PotionConfig.Get(source.potionId)
	end
	if config == nil and record then
		config = PotionConfig.Get(record.potionId)
	end
	if not config then
		return nil
	end

	local ownedAmount = math.max(0, math.floor(tonumber(record and record.amount) or 0))
	local remainingSeconds = math.max(0, math.floor(tonumber(source.remainingSeconds) or 0))
	local isActive = remainingSeconds > 0

	return {
		itemType = "potion",
		potionId = config.id,
		bundleText = TranslationHelper.formatByKey(LocalizationKeys.Potion.Preview.Bundle, {
			PotionName = config.label,
		}),
		partText = buildEffectText(config),
		rarityText = TranslationHelper.formatByKey(LocalizationKeys.Potion.Preview.Duration, {
			Duration = formatDuration(config.durationSeconds),
		}),
		mutationText = TranslationHelper.formatByKey(LocalizationKeys.Potion.Preview.Owned, {
			OwnedAmount = formatWholeNumber(ownedAmount),
		}),
		sizeText = if isActive
			then TranslationHelper.formatByKey(LocalizationKeys.Potion.Preview.UseAddTime, {
				Duration = formatDuration(config.durationSeconds),
			})
			else TranslationHelper.formatByKey(LocalizationKeys.Potion.Preview.UseStart, {
				Duration = formatDuration(config.durationSeconds),
			}),
		existingText = if isActive
			then TranslationHelper.formatByKey(LocalizationKeys.Potion.Preview.ActiveRemaining, {
				Remaining = formatDuration(remainingSeconds),
			})
			else TranslationHelper.formatByKey(LocalizationKeys.Potion.Preview.ActiveInactive),
		cashText = TranslationHelper.formatByKey(LocalizationKeys.Potion.Preview.SellEach, {
			Price = formatMoney(PotionConfig.GetSellPrice(config.id)),
		}),
		chanceText = TranslationHelper.formatByKey(LocalizationKeys.Potion.Preview.BuyEach, {
			Price = formatMoney(config.buyPrice),
		}),
		cardUsageText = string.format("x%s", formatWholeNumber(ownedAmount)),
		bundleModel = PotionPresentation.GetBundleModel(config),
	}
end

function PotionPresentation.GetEffectDescription(configOrId: PotionConfig.PotionConfigEntry | string): string
	local config = if typeof(configOrId) == "string" then PotionConfig.Get(configOrId) else configOrId
	if not config then
		return "Effect: None"
	end

	return buildEffectText(config)
end

function PotionPresentation.BuildStatusHoverPresentation(payload: any)
	local source = if typeof(payload) == "table" then payload else {}
	local config = source.config
	if config == nil and source.potionId ~= nil then
		config = PotionConfig.Get(source.potionId)
	end
	if not config then
		return nil
	end

	local remainingSeconds = math.max(0, math.floor(tonumber(source.remainingSeconds) or 0))
	local descriptionText = PotionPresentation.GetEffectDescription(config)
	local durationText = TranslationHelper.formatByKey(LocalizationKeys.Potion.Status.Duration, {
		Duration = formatDuration(config.durationSeconds),
	})
	local remainingText = TranslationHelper.formatByKey(LocalizationKeys.Potion.Status.Remaining, {
		Remaining = formatDuration(remainingSeconds),
	})

	return {
		titleText = config.label,
		descriptionText = descriptionText,
		durationText = durationText,
		remainingText = remainingText,
		bodyText = table.concat({
			escapeRichText(descriptionText),
			escapeRichText(durationText),
			escapeRichText(remainingText),
		}, "\n"),
	}
end

function PotionPresentation.FormatDuration(seconds: number?): string
	return formatDuration(seconds)
end

return table.freeze(PotionPresentation)
