local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssetPaths = require(ReplicatedStorage.Shared.Assets.GameAssetPaths)
local GameAssetResolver = require(ReplicatedStorage.Shared.Assets.GameAssetResolver)

local NumberFormatter = require(ReplicatedStorage.Shared.Formatting.NumberFormatter)
local PreviewAppearanceRegistry = require(ReplicatedStorage.Shared.Character.PreviewAppearanceRegistry)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local MutationCovers = require(ReplicatedStorage.Shared.Config.MutationCovers)
local SizeConfig = require(ReplicatedStorage.Shared.Config.SizeConfig)
local SizeIcons = require(ReplicatedStorage.Shared.Config.SizeIcons)
local LocalizationKeys = require(ReplicatedStorage.Shared.Localization.Keys)
local TranslationHelper = require(ReplicatedStorage.Shared.Localization.TranslationHelper)
local ViewportModelRenderer = require(ReplicatedStorage.Shared.UI.ViewportModelRenderer)
local LOCAL_PLAYER = Players.LocalPlayer

local ITEM_COUNT_COLOR = Color3.fromRGB(205, 200, 0)
local DEFAULT_MUTATION_ID = MutationConfig.GetDefault().id
local FALLBACK_TEXT_COLOR = MutationConfig.GetColor(DEFAULT_MUTATION_ID)
local EQUIPPED_COLOR = Color3.fromRGB(113, 230, 139)

local REGION_TO_LABEL = {
	Head = "Head",
	Torso = "Torso",
	LeftArm = "Left Arm",
	RightArm = "Right Arm",
	LeftLeg = "Left Leg",
	RightLeg = "Right Leg",
}

local REGION_TO_PLURAL_LABEL = {
	Head = "Heads",
	Torso = "Torsos",
	LeftArm = "Left Arms",
	RightArm = "Right Arms",
	LeftLeg = "Left Legs",
	RightLeg = "Right Legs",
}

local BodyPartPresentation = {
	ItemCountColor = ITEM_COUNT_COLOR,
	MutationColor = FALLBACK_TEXT_COLOR,
	FallbackTextColor = FALLBACK_TEXT_COLOR,
	EquippedColor = EQUIPPED_COLOR,
	RegionToLabel = REGION_TO_LABEL,
	RegionToPluralLabel = REGION_TO_PLURAL_LABEL,
}

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

local function formatMoneyValue(value: number?): string
	local numericValue = math.max(0, tonumber(value) or 0)
	if numericValue >= 1000 then
		return NumberFormatter.Format(math.round(numericValue))
	end

	return string.format("%.2f", numericValue):gsub("0+$", ""):gsub("%.$", "")
end

local function formatMoneyPerSecond(value: number?): string
	return string.format("$%s/s", formatMoneyValue(value))
end

local function formatMultiplier(value: number?): string
	local numericValue = math.max(0, tonumber(value) or 0)
	local roundedTenths = math.round(numericValue * 10) / 10
	if math.abs(numericValue - roundedTenths) < 0.005 then
		return string.format("%.1f", roundedTenths)
	end

	return string.format("%.2f", numericValue):gsub("0+$", ""):gsub("%.$", "")
end

local function formatChance(value: number?): string
	local denominator = math.max(1, math.floor(tonumber(value) or 1))
	return string.format("1/%s", formatNumberish(denominator))
end

local function escapeRichText(text: any): string
	return tostring(text)
		:gsub("&", "&amp;")
		:gsub("<", "&lt;")
		:gsub(">", "&gt;")
		:gsub('"', "&quot;")
		:gsub("'", "&apos;")
end

local function getSizeEntry(scale: number?, sizeId: any)
	local entry = SizeConfig.GetByScale(scale)
	if entry then
		return entry
	end

	return SizeConfig.Get(SizeConfig.NormalizeId(sizeId)) or SizeConfig.GetDefault()
end

local function getSizeDescriptor(scale: number?, sizeId: any): string
	return getSizeEntry(scale, sizeId).displayName
end

local function getSizeTagStyle(scale: number?, sizeId: any)
	local sizeEntry = getSizeEntry(scale, sizeId)
	if not sizeEntry or sizeEntry.id == SizeConfig.GetDefault().id then
		return nil
	end

	local style = SizeIcons[sizeEntry.id]
	if typeof(style) == "table" and typeof(style.image) == "string" and style.image ~= "" then
		return style
	end

	return nil
end

local function getSizeTagTexture(scale: number?, sizeId: any): string?
	local style = getSizeTagStyle(scale, sizeId)
	return if style then style.image else nil
end

local function getRecordPassiveIncomePerSecond(record: any, piece: any): number
	return tonumber(record and record.finalPassiveIncomePerSecond) or tonumber(piece and piece.passiveIncomePerSecond) or 0
end

local function getFontWithWeight(fontFace: Font, fontWeight: Enum.FontWeight?): Font
	if typeof(fontWeight) == "EnumItem" then
		return Font.new(fontFace.Family, fontWeight, fontFace.Style)
	end

	return fontFace
end

local function getRarityTemplatesFolder(): Folder?
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	if not gameAssets then
		return nil
	end

	local indexFolder = GameAssetResolver.FindFirst({ GameAssetPaths.UI.Index, { "UI", "Index" } })
	if not (indexFolder and indexFolder:IsA("Folder")) then
		return nil
	end

	local rarityTemplates = indexFolder:FindFirstChild("RarityTemplates")
	if rarityTemplates and rarityTemplates:IsA("Folder") then
		return rarityTemplates
	end

	return nil
end

local function resolveRarityTemplateLabel(rarity: string): TextLabel?
	local rarityTemplates = getRarityTemplatesFolder()
	local rarityTemplate = rarityTemplates and rarityTemplates:FindFirstChild(rarity) or nil
	if rarityTemplate and rarityTemplate:IsA("TextLabel") then
		return rarityTemplate
	end

	return nil
end

local function replaceSupportedTextAdornments(targetLabel: TextLabel, sourceLabel: TextLabel)
	for _, child in ipairs(targetLabel:GetChildren()) do
		if child:IsA("UIGradient") or child:IsA("UIStroke") then
			child:Destroy()
		end
	end

	for _, child in ipairs(sourceLabel:GetChildren()) do
		if child:IsA("UIGradient") or child:IsA("UIStroke") then
			local clonedChild = child:Clone()
			clonedChild.Parent = targetLabel
		end
	end
end

local function resolveRarityTemplateStyle(
	rarity: string,
	setConfig: any
): {
	textColor: Color3,
	fontFace: Font?,
	textStrokeColor: Color3?,
	textStrokeTransparency: number?,
	richText: boolean?,
	templateLabel: TextLabel?,
}
	local rarityTemplate = resolveRarityTemplateLabel(rarity)
	if rarityTemplate then
		return {
			textColor = rarityTemplate.TextColor3,
			fontFace = rarityTemplate.FontFace,
			textStrokeColor = rarityTemplate.TextStrokeColor3,
			textStrokeTransparency = rarityTemplate.TextStrokeTransparency,
			richText = rarityTemplate.RichText,
			templateLabel = rarityTemplate,
		}
	end

	local rollDisplay = setConfig and setConfig.rollDisplay or nil
	local fallbackFontFace = nil
	if rollDisplay and typeof(rollDisplay.fontFace) == "Font" then
		fallbackFontFace = getFontWithWeight(rollDisplay.fontFace, rollDisplay.fontWeight)
	end

	return {
		textColor = if rollDisplay and typeof(rollDisplay.color) == "Color3" then rollDisplay.color else EQUIPPED_COLOR,
		fontFace = fallbackFontFace,
		templateLabel = nil,
	}
end

local function brightenCardFill(color: Color3, alpha: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), math.clamp(alpha, 0, 1))
end

local function findFirstGuiChild(root: Instance, names: { string }): GuiObject?
	for _, name in ipairs(names) do
		local child = root:FindFirstChild(name)
		if child and child:IsA("GuiObject") then
			return child
		end
	end

	return nil
end

local function resolveMutationInput(record: any): any
	if typeof(record) ~= "table" then
		return nil
	end

	for _, mutationId in ipairs({ record.mutationId, record.MutationId }) do
		if typeof(mutationId) == "string" and mutationId ~= "" then
			return mutationId
		end
	end

	for _, mutationName in ipairs({ record.mutation, record.Mutation }) do
		if typeof(mutationName) == "string" and mutationName ~= "" then
			return mutationName
		end
	end

	return nil
end

local function resolveMutationPresentation(record: any): (string, string, Color3)
	local mutationId = MutationConfig.NormalizeId(resolveMutationInput(record))
	return mutationId, MutationConfig.GetDisplayName(mutationId), MutationConfig.GetColor(mutationId)
end

local function resolveMutationCoverTexture(record: any): string?
	local mutationId = MutationConfig.NormalizeId(resolveMutationInput(record))
	local mutationCoverTexture = MutationCovers[mutationId]
	if typeof(mutationCoverTexture) == "string" and mutationCoverTexture ~= "" then
		return mutationCoverTexture
	end

	return nil
end

function BodyPartPresentation.GetRegionLabel(region: string): string
	return REGION_TO_LABEL[region] or tostring(region)
end

function BodyPartPresentation.GetRegionPluralLabel(region: string): string
	return REGION_TO_PLURAL_LABEL[region] or tostring(region)
end

function BodyPartPresentation.GetLocalizedRegionLabel(region: string): string
	return TranslationHelper.translate(BodyPartPresentation.GetRegionLabel(region))
end

function BodyPartPresentation.GetLocalizedRegionPluralLabel(region: string): string
	return TranslationHelper.translate(BodyPartPresentation.GetRegionPluralLabel(region))
end

function BodyPartPresentation.ToRichTextColor(color: Color3): string
	return toRichTextColor(color)
end

function BodyPartPresentation.FormatNumberish(value: number?): string
	return formatNumberish(value)
end

function BodyPartPresentation.FormatMoneyPerSecond(value: number?): string
	return formatMoneyPerSecond(value)
end

function BodyPartPresentation.FormatMultiplier(value: number?): string
	return formatMultiplier(value)
end

function BodyPartPresentation.FormatChance(value: number?): string
	return formatChance(value)
end

function BodyPartPresentation.FormatPlayerStatValue(value: number?): string
	return formatNumberish(value)
end

function BodyPartPresentation.GetSizeDescriptor(scale: number?, sizeId: any): string
	return getSizeDescriptor(scale, sizeId)
end

function BodyPartPresentation.GetSizeTagStyle(scale: number?, sizeId: any)
	return getSizeTagStyle(scale, sizeId)
end

function BodyPartPresentation.GetSizeTagTexture(scale: number?, sizeId: any): string?
	return getSizeTagTexture(scale, sizeId)
end

function BodyPartPresentation.GetRecordPassiveIncomePerSecond(record: any, piece: any): number
	return getRecordPassiveIncomePerSecond(record, piece)
end

function BodyPartPresentation.FormatTemplatedLabelText(templateText: any, value: any): string
	local formattedValue = string.match(tostring(value or ""), "^%s*(.-)%s*$") or ""
	local normalizedTemplate = if typeof(templateText) == "string"
		then string.match(templateText, "^%s*(.-)%s*$") or ""
		else ""

	if formattedValue == "" then
		return normalizedTemplate
	end

	if normalizedTemplate == "" then
		return formattedValue
	end

	if string.find(normalizedTemplate, "%%s", 1, true) then
		local ok, formattedText = pcall(string.format, normalizedTemplate, formattedValue)
		if ok and typeof(formattedText) == "string" then
			return formattedText
		end
	end

	for _, delimiter in ipairs({ ":", "-", "|" }) do
		local delimiterStart, delimiterEnd = string.find(normalizedTemplate, delimiter, 1, true)
		if delimiterStart and delimiterEnd then
			local prefixText = string.match(string.sub(normalizedTemplate, 1, delimiterEnd), "^%s*(.-)%s*$") or ""
			if prefixText ~= "" then
				return string.format("%s %s", prefixText, formattedValue)
			end
		end
	end

	local leadingText = string.match(normalizedTemplate, "^(.*%s)%S+$")
	if typeof(leadingText) == "string" and leadingText ~= "" then
		return leadingText .. formattedValue
	end

	return formattedValue
end

local function formatSignedNumberish(value: number?): string
	local numericValue = tonumber(value) or 0
	if math.abs(numericValue) < 0.005 then
		return "0"
	end

	local absoluteFormattedValue = formatNumberish(math.abs(numericValue))
	if numericValue > 0 then
		return "+" .. absoluteFormattedValue
	end

	return "-" .. absoluteFormattedValue
end

local function formatPreviewStatText(templateText: any, value: any): string
	local formattedValue = if typeof(value) == "string" then value else formatNumberish(value)
	local normalizedTemplate = if typeof(templateText) == "string"
		then string.match(templateText, "^%s*(.-)%s*$") or ""
		else ""
	if normalizedTemplate == "" then
		return formattedValue
	end

	local richTextPrefix = string.match(normalizedTemplate, "^(.-</font>%s*)[%d%.,%-]+%s*$")
	if typeof(richTextPrefix) == "string" and richTextPrefix ~= "" then
		return richTextPrefix .. formattedValue
	end

	local labelPrefix = string.match(normalizedTemplate, "^(.*:%s*)[%d%.,%-]+%s*$")
	if typeof(labelPrefix) == "string" and labelPrefix ~= "" then
		return labelPrefix .. formattedValue
	end

	return BodyPartPresentation.FormatTemplatedLabelText(normalizedTemplate, formattedValue)
end

function BodyPartPresentation.BuildPreviewStatTexts(
	bonuses: any,
	templates: { [string]: string }?
): { Strength: string, Speed: string, Health: string }
	local safeBonuses = if typeof(bonuses) == "table" then bonuses else {}
	local basePlayerStats = BodyPartsCatalog.GetBasePlayerStats()
	local statValues = {
		Strength = tonumber(safeBonuses.damage) or tonumber(basePlayerStats.damage) or 20,
		Speed = tonumber(safeBonuses.speed) or tonumber(basePlayerStats.speed) or 16,
		Health = tonumber(safeBonuses.health) or tonumber(basePlayerStats.health) or 100,
	}
	local defaultEntries = {
		Strength = LocalizationKeys.BodyPart.Stats.Strength,
		Speed = LocalizationKeys.BodyPart.Stats.Speed,
		Health = LocalizationKeys.BodyPart.Stats.Health,
	}
	local texts = {}

	for statName, value in pairs(statValues) do
		local template = if typeof(templates) == "table" and typeof(templates[statName]) == "string" then templates[statName] else nil
		if template ~= nil and template ~= "" and template ~= "Strength: %s" and template ~= "Speed: %s" and template ~= "Health: %s" then
			texts[statName] = formatPreviewStatText(template, value)
		else
			texts[statName] = TranslationHelper.formatByKey(defaultEntries[statName], {
				Value = formatNumberish(value),
			})
		end
	end

	return texts
end

function BodyPartPresentation.BuildBodyPartContributionStatTexts(
	piece: any,
	templates: { [string]: string }?
): { Strength: string, Speed: string, Health: string }
	local safePiece = if typeof(piece) == "table" then piece else {}
	local statValues = {
		Strength = tonumber(safePiece.damageBonus) or 0,
		Speed = tonumber(safePiece.speedBonus) or 0,
		Health = tonumber(safePiece.healthBonus) or 0,
	}
	local defaultEntries = {
		Strength = LocalizationKeys.BodyPart.Stats.Strength,
		Speed = LocalizationKeys.BodyPart.Stats.Speed,
		Health = LocalizationKeys.BodyPart.Stats.Health,
	}
	local texts = {}

	for statName, value in pairs(statValues) do
		local formattedValue = formatSignedNumberish(value)
		local template = if typeof(templates) == "table" and typeof(templates[statName]) == "string" then templates[statName] else nil
		if template ~= nil and template ~= "" and template ~= "Strength: %s" and template ~= "Speed: %s" and template ~= "Health: %s" then
			texts[statName] = formatPreviewStatText(template, formattedValue)
		else
			texts[statName] = TranslationHelper.formatByKey(defaultEntries[statName], {
				Value = formattedValue,
			})
		end
	end

	return texts
end

function BodyPartPresentation.FormatMutationLabelText(templateText: any, record: any): string
	local _, mutationDisplayName, mutationColor = resolveMutationPresentation(record)
	local formattedMutationName = string.format(
		'<font color="%s">%s</font>',
		toRichTextColor(mutationColor),
		escapeRichText(mutationDisplayName)
	)
	local formattedText = TranslationHelper.formatByKey(LocalizationKeys.BodyPart.Preview.Mutation, {
		MutationName = formattedMutationName,
	})
	local normalizedTemplate = if typeof(templateText) == "string"
		then string.match(templateText, "^%s*(.-)%s*$") or ""
		else ""

	if formattedText == formattedMutationName and normalizedTemplate ~= "" then
		return TranslationHelper.formatByKey(LocalizationKeys.BodyPart.Preview.Mutation, {
			MutationName = formattedMutationName,
		}, string.format("%s: {MutationName}", normalizedTemplate))
	end

	return formattedText
end

function BodyPartPresentation.ApplySetRarityTemplateToLabel(
	targetLabel: TextLabel,
	setConfig: any,
	displayRarity: string?,
	fallbackColor: Color3?
)
	local resolvedDisplayRarity = if typeof(displayRarity) == "string" and displayRarity ~= ""
		then displayRarity
		else tostring(setConfig and setConfig.rollDisplay and setConfig.rollDisplay.rarity or "Unknown")
	local style = resolveRarityTemplateStyle(resolvedDisplayRarity, setConfig)

	targetLabel.TextColor3 = style.textColor
	if typeof(style.fontFace) == "Font" then
		targetLabel.FontFace = style.fontFace
	end
	if typeof(style.textStrokeColor) == "Color3" then
		targetLabel.TextStrokeColor3 = style.textStrokeColor
	end
	if typeof(style.textStrokeTransparency) == "number" then
		targetLabel.TextStrokeTransparency = style.textStrokeTransparency
	end
	if typeof(style.richText) == "boolean" then
		targetLabel.RichText = style.richText
	end

	local templateLabel = style.templateLabel
	if templateLabel then
		replaceSupportedTextAdornments(targetLabel, templateLabel)
	elseif typeof(fallbackColor) == "Color3" then
		targetLabel.TextColor3 = fallbackColor
	end

	return style
end

function BodyPartPresentation.ResolveSetRarityStyle(
	setConfig: any,
	displayRarity: string?,
	fallbackColor: Color3?
)
	local resolvedDisplayRarity = if typeof(displayRarity) == "string" and displayRarity ~= ""
		then displayRarity
		else tostring(setConfig and setConfig.rollDisplay and setConfig.rollDisplay.rarity or "Unknown")
	local style = resolveRarityTemplateStyle(resolvedDisplayRarity, setConfig)
	local baseFillColor = style.textColor
	if typeof(baseFillColor) ~= "Color3" then
		baseFillColor = if typeof(fallbackColor) == "Color3" then fallbackColor else EQUIPPED_COLOR
	end

	return {
		displayRarity = resolvedDisplayRarity,
		textColor = style.textColor,
		fontFace = style.fontFace,
		accentColor = baseFillColor,
		baseFillColor = baseFillColor,
		selectedFillColor = brightenCardFill(baseFillColor, 0.3),
	}
end

function BodyPartPresentation.FormatInventoryNameText(pieceDisplayName: any, record: any): string
	local mutationId, _, mutationColor = resolveMutationPresentation(record)
	local safePieceDisplayName = escapeRichText(pieceDisplayName)
	if mutationId == DEFAULT_MUTATION_ID then
		return safePieceDisplayName
	end

	return string.format(
		'<font color="%s">%s</font>',
		toRichTextColor(mutationColor),
		safePieceDisplayName
	)
end

function BodyPartPresentation.ResolveBodyPartRarityStyle(payload: any)
	local source = if typeof(payload) == "table" then payload else {}
	local record = if typeof(source.record) == "table" then source.record else source
	local piece = source.piece
	if piece == nil then
		local pieceId = source.pieceId or (record and record.pieceId)
		if typeof(pieceId) == "string" then
			piece = BodyPartsCatalog.GetPiece(pieceId)
		end
	end

	if not piece then
		return nil
	end

	local setConfig = source.setConfig or BodyPartsCatalog.GetSetForPiece(piece.id)
	local displayRarity = if record and typeof(record.displayRarity) == "string" and record.displayRarity ~= ""
		then record.displayRarity
		else tostring(setConfig and setConfig.rollDisplay and setConfig.rollDisplay.rarity or "Unknown")
	local style = BodyPartPresentation.ResolveSetRarityStyle(setConfig, displayRarity)

	return {
		displayRarity = style.displayRarity,
		setConfig = setConfig,
		textColor = style.textColor,
		fontFace = style.fontFace,
		accentColor = style.accentColor,
		baseFillColor = style.baseFillColor,
		selectedFillColor = style.selectedFillColor,
	}
end

function BodyPartPresentation.BuildSummaryTexts(bonuses: any): { income: string, luck: string, rollSpeed: string }
	local safeBonuses = if typeof(bonuses) == "table" then bonuses else {}
	local passiveIncome = tonumber(safeBonuses.passiveIncomePerSecond) or 0
	local luckBonus = tonumber(safeBonuses.luckBonus) or 0
	local luckMultiplier = math.max(1, tonumber(safeBonuses.luckMultiplier) or 1)
	local rollSpeedBonus = tonumber(safeBonuses.rollSpeedBonus) or 0

	return {
		income = TranslationHelper.formatByKey(LocalizationKeys.BodyPart.Summary.Income, {
			IncomePerSecond = formatMoneyPerSecond(passiveIncome),
		}),
		luck = TranslationHelper.formatByKey(LocalizationKeys.BodyPart.Summary.Luck, {
			LuckMultiplier = formatMultiplier((1 + luckBonus) * luckMultiplier),
		}),
		rollSpeed = TranslationHelper.formatByKey(LocalizationKeys.BodyPart.Summary.RollSpeed, {
			RollSpeedMultiplier = formatMultiplier(1 + rollSpeedBonus),
		}),
	}
end

function BodyPartPresentation.BuildPreviewPresentation(payload: any)
	local source = if typeof(payload) == "table" then payload else {}
	local record = if typeof(source.record) == "table" then source.record else source
	local entry = if typeof(source.entry) == "table" then source.entry else nil
	local piece = source.piece
	if piece == nil then
		local pieceId = source.pieceId or (record and record.pieceId) or (entry and entry.pieceId)
		if typeof(pieceId) == "string" then
			piece = BodyPartsCatalog.GetPiece(pieceId)
		end
	end

	if not piece then
		return nil
	end

	local setConfig = BodyPartsCatalog.GetSetForPiece(piece.id)
	local applyPlayerClothing = setConfig == nil or setConfig.applyPlayerClothing ~= false
	local applyPlayerBodyColors = setConfig == nil or setConfig.applyPlayerBodyColors ~= false
	local previewScale = tonumber(source.visualScale)
		or tonumber(source.scale)
		or tonumber(entry and entry.scale)
		or tonumber(record and (record.sizeMultiplier or record.scale))
		or 1
	local displayScale = tonumber(source.displayScale)
		or tonumber(source.sizeMultiplier)
		or tonumber(record and (record.sizeMultiplier or record.scale))
		or tonumber(entry and entry.sizeMultiplier)
		or previewScale
	local sizeId = source.sizeId or (record and record.sizeId) or (entry and entry.sizeId)
	local rarityChance = tonumber(record and (record.displayOddsDenominator or record.rarityDenominator))
		or tonumber(setConfig and setConfig.rollDisplay and setConfig.rollDisplay.chance)
		or tonumber(piece.rarity)
		or 1
	local bundleName = if record and typeof(record.rolledSetDisplayName) == "string" and record.rolledSetDisplayName ~= ""
		then record.rolledSetDisplayName
		else if setConfig and setConfig.rollDisplay and setConfig.rollDisplay.displayName then setConfig.rollDisplay.displayName else piece.displayName
	local serialNumber = tonumber(record and record.serialNumber)
	local compactSerialNumber = if serialNumber
		then NumberFormatter.Format(math.max(1, math.floor(serialNumber)))
		else nil
	local passiveIncomePerSecond = getRecordPassiveIncomePerSecond(record, piece)
	local rarityStyle = BodyPartPresentation.ResolveBodyPartRarityStyle({
		record = record,
		piece = piece,
		setConfig = setConfig,
	})
	local rarityTextColor = if rarityStyle then rarityStyle.textColor else EQUIPPED_COLOR
	local displayRarity = if rarityStyle then rarityStyle.displayRarity else "Unknown"
	local rarityFontFace = if rarityStyle then rarityStyle.fontFace else nil

	return {
		itemType = "bodyPart",
		pieceId = piece.id,
		piece = piece,
		region = piece.region,
		setConfig = setConfig,
		applyPlayerClothing = applyPlayerClothing,
		applyPlayerBodyColors = applyPlayerBodyColors,
		passiveIncomePerSecond = passiveIncomePerSecond,
		previewScale = previewScale,
		displayScale = displayScale,
		appearanceUserId = tonumber(source.appearanceUserId)
			or tonumber(source.userId)
			or tonumber(record and record.userId)
			or tonumber(entry and entry.userId)
			or (LOCAL_PLAYER and LOCAL_PLAYER.UserId or nil),
		bundleText = TranslationHelper.formatByKey(LocalizationKeys.BodyPart.Preview.Bundle, {
			BundleName = string.format(
				'<font color="%s">%s</font>',
				toRichTextColor(rarityTextColor),
				tostring(bundleName)
			),
		}),
		inventoryBundleText = TranslationHelper.formatByKey(LocalizationKeys.BodyPart.Preview.Bundle, {
			BundleName = string.format(
				'<font color="%s">%s</font>',
				toRichTextColor(rarityTextColor),
				tostring(bundleName)
			),
		}),
		inventoryEverRolledText = if compactSerialNumber
			then string.format("#%s", compactSerialNumber)
			else TranslationHelper.formatByKey(LocalizationKeys.Common.NotAvailable),
		bundleFontFace = rarityFontFace,
		partText = TranslationHelper.formatByKey(LocalizationKeys.BodyPart.Preview.Part, {
			RegionLabel = BodyPartPresentation.GetLocalizedRegionLabel(piece.region),
		}),
		rarityText = TranslationHelper.formatByKey(LocalizationKeys.BodyPart.Preview.Rarity, {
			RarityName = string.format(
				'<font color="%s">%s</font>',
				toRichTextColor(rarityTextColor),
				displayRarity
			),
		}),
		rarityFontFace = rarityFontFace,
		mutationText = BodyPartPresentation.FormatMutationLabelText("Mutation", record),
		sizeText = TranslationHelper.formatByKey(LocalizationKeys.BodyPart.Preview.Size, {
			SizeDescriptor = getSizeDescriptor(displayScale, sizeId),
			SizeMultiplier = formatMultiplier(displayScale),
		}),
		cashText = TranslationHelper.formatByKey(LocalizationKeys.BodyPart.Preview.CashPerSec, {
			IncomePerSecond = string.format(
				'<font color="%s">%s</font>',
				toRichTextColor(ITEM_COUNT_COLOR),
				formatMoneyPerSecond(passiveIncomePerSecond)
			),
		}),
		chanceText = TranslationHelper.formatByKey(LocalizationKeys.BodyPart.Preview.Chance, {
			ChanceText = formatChance(rarityChance),
		}),
		bundleModel = BodyPartsCatalog.ResolveBundleModel(piece.id),
		sizeTagStyle = getSizeTagStyle(displayScale, sizeId),
		sizeTagTexture = getSizeTagTexture(displayScale, sizeId),
		cardNameText = BodyPartPresentation.FormatInventoryNameText(piece.displayName, record),
		cardUsageText = formatMoneyPerSecond(passiveIncomePerSecond),
		cardAccentColor = if rarityStyle then rarityStyle.accentColor else nil,
		baseFillColor = if rarityStyle then rarityStyle.baseFillColor else nil,
		selectedFillColor = if rarityStyle then rarityStyle.selectedFillColor else nil,
		mutationCoverTexture = resolveMutationCoverTexture(record),
		preferIconOverViewport = false,
	}
end

function BodyPartPresentation.BuildBundleCardPayload(previewPresentation: any, overrides: any?)
	if typeof(previewPresentation) ~= "table" then
		return nil
	end

	local payload = {
		nameText = previewPresentation.cardNameText,
		usageText = previewPresentation.cardUsageText,
		bundleModel = previewPresentation.bundleModel,
		region = previewPresentation.region,
		previewScale = previewPresentation.previewScale,
		appearanceUserId = previewPresentation.appearanceUserId,
		applyPlayerClothing = previewPresentation.applyPlayerClothing,
		applyPlayerBodyColors = previewPresentation.applyPlayerBodyColors,
		cardAccentColor = previewPresentation.cardAccentColor,
		baseFillColor = previewPresentation.baseFillColor,
		selectedFillColor = previewPresentation.selectedFillColor,
		mutationCoverTexture = previewPresentation.mutationCoverTexture,
		sizeTagStyle = previewPresentation.sizeTagStyle,
		iconTexture = previewPresentation.iconTexture,
		preferIconOverViewport = previewPresentation.preferIconOverViewport,
	}

	if typeof(overrides) == "table" then
		for key, value in pairs(overrides) do
		payload[key] = value
		end
	end

	return payload
end

local function getDefaultImageColor(instance: Instance): Color3?
	if not (instance:IsA("ImageButton") or instance:IsA("ImageLabel")) then
		return nil
	end

	local existing = instance:GetAttribute("BodyPartPresentation_DefaultImageColor")
	if typeof(existing) == "Color3" then
		return existing
	end

	instance:SetAttribute("BodyPartPresentation_DefaultImageColor", instance.ImageColor3)
	return instance.ImageColor3
end

local function getVisibleCardSurface(root: Instance): GuiObject?
	if root:IsA("ImageButton") or root:IsA("ImageLabel") then
		return root
	end

	for _, childName in ipairs({ "Base", "Temp" }) do
		local child = root:FindFirstChild(childName)
		if child and (child:IsA("ImageButton") or child:IsA("ImageLabel")) then
			return child
		end
	end

	return nil
end

local function findFirstGuiChildInCard(root: Instance, names: { string }): GuiObject?
	local child = findFirstGuiChild(root, names)
	if child then
		return child
	end

	local visibleSurface = getVisibleCardSurface(root)
	if visibleSurface and visibleSurface ~= root then
		return findFirstGuiChild(visibleSurface, names)
	end

	return nil
end

local function applyImageColor(target: Instance, color: Color3?)
	if not (target:IsA("ImageButton") or target:IsA("ImageLabel")) then
		return
	end

	local defaultColor = getDefaultImageColor(target)
	if defaultColor then
		target.ImageColor3 = if typeof(color) == "Color3" then color else defaultColor
	end
end

local function ensureGradient(target: Instance): UIGradient?
	local existing = target:FindFirstChildOfClass("UIGradient")
	if existing then
		return existing
	end

	if target:IsA("GuiObject") then
		local gradient = Instance.new("UIGradient")
		gradient.Name = "UIGradient"
		gradient.Parent = target
		return gradient
	end

	return nil
end

local function applySizeTagStyle(sizeTag: ImageLabel, style: any?)
	if typeof(style) ~= "table" or typeof(style.image) ~= "string" or style.image == "" then
		sizeTag.Visible = false
		sizeTag.Image = ""
		return
	end

	sizeTag.Visible = true
	sizeTag.Image = style.image

	local gradientConfig = style.gradient
	if typeof(gradientConfig) ~= "table" then
		return
	end

	local gradient = ensureGradient(sizeTag)
	if not gradient then
		return
	end

	if typeof(gradientConfig.rotation) == "number" then
		gradient.Rotation = gradientConfig.rotation
	end

	if typeof(gradientConfig.offset) == "Vector2" then
		gradient.Offset = gradientConfig.offset
	end

	if typeof(gradientConfig.color) == "ColorSequence" then
		gradient.Color = gradientConfig.color
	end

	if typeof(gradientConfig.transparency) == "NumberSequence" then
		gradient.Transparency = gradientConfig.transparency
	end
end

local function applyCardFill(root: Instance, baseFillColor: Color3?, selectedFillColor: Color3?, isSelected: boolean?)
	local visibleSurface = getVisibleCardSurface(root)
	local fillColor = if isSelected == true and typeof(selectedFillColor) == "Color3" then selectedFillColor else baseFillColor

	if visibleSurface then
		applyImageColor(visibleSurface, fillColor)
	end

	local decorationRoot = if visibleSurface then visibleSurface else root
	for _, childName in ipairs({ "Cover", "Cover2", "Rays" }) do
		local child = decorationRoot:FindFirstChild(childName)
		if child then
			applyImageColor(child, fillColor)
		end
	end
end

local function resolveCardFillColors(source: any): (Color3?, Color3?)
	local baseFillColor = source.baseFillColor
	local selectedFillColor = source.selectedFillColor

	if typeof(baseFillColor) ~= "Color3" then
		local rarityStyle = source.rarityStyle
		if typeof(rarityStyle) == "table" then
			if typeof(rarityStyle.baseFillColor) == "Color3" then
				baseFillColor = rarityStyle.baseFillColor
			elseif typeof(rarityStyle.accentColor) == "Color3" then
				baseFillColor = rarityStyle.accentColor
			end
		end
	end

	if typeof(selectedFillColor) ~= "Color3" then
		local rarityStyle = source.rarityStyle
		if typeof(rarityStyle) == "table" and typeof(rarityStyle.selectedFillColor) == "Color3" then
			selectedFillColor = rarityStyle.selectedFillColor
		end
	end

	if typeof(baseFillColor) ~= "Color3" and typeof(source.cardAccentColor) == "Color3" then
		baseFillColor = source.cardAccentColor
	end

	if typeof(baseFillColor) ~= "Color3" or typeof(selectedFillColor) ~= "Color3" then
		local resolvedStyle = BodyPartPresentation.ResolveBodyPartRarityStyle(source)
		if resolvedStyle then
			if typeof(baseFillColor) ~= "Color3" then
				baseFillColor = resolvedStyle.baseFillColor or resolvedStyle.accentColor
			end
			if typeof(selectedFillColor) ~= "Color3" then
				selectedFillColor = resolvedStyle.selectedFillColor
			end
		end
	end

	if typeof(selectedFillColor) ~= "Color3" and typeof(baseFillColor) == "Color3" then
		selectedFillColor = brightenCardFill(baseFillColor, 0.3)
	end

	return if typeof(baseFillColor) == "Color3" then baseFillColor else nil,
		if typeof(selectedFillColor) == "Color3" then selectedFillColor else nil
end

function BodyPartPresentation.PopulateBundleCard(cardRoot: Instance, payload: any)
	local source = if typeof(payload) == "table" then payload else {}
	local baseFillColor, selectedFillColor = resolveCardFillColors(source)
	applyCardFill(cardRoot, baseFillColor, selectedFillColor, source.isSelected == true)

	local cardNameLabel = findFirstGuiChildInCard(cardRoot, { "ItemName", "BodyPart" })
	if cardNameLabel and cardNameLabel:IsA("TextLabel") and typeof(source.nameText) == "string" then
		cardNameLabel.RichText = true
		cardNameLabel.Text = source.nameText
	end

	local usageLabel = findFirstGuiChildInCard(cardRoot, { "ItemCount", "Usage" })
	if usageLabel and usageLabel:IsA("TextLabel") then
		usageLabel.Text = if typeof(source.usageText) == "string"
			then source.usageText
			else formatMoneyPerSecond(source.passiveIncomePerSecond)
	end

	local viewport = findFirstGuiChildInCard(cardRoot, { "ItemViewport", "Viewport" })
	local icon = findFirstGuiChildInCard(cardRoot, { "ItemIcon", "Icon" })
	local iconTexture = if typeof(source.iconTexture) == "string" and source.iconTexture ~= "" then source.iconTexture else nil
	local shouldUseIcon = source.preferIconOverViewport == true and iconTexture ~= nil

	if viewport and viewport:IsA("ViewportFrame") then
		viewport.Visible = not shouldUseIcon
		if source.bundleModel and source.bundleModel:IsA("Model") then
			local appearanceSnapshot = PreviewAppearanceRegistry.GetSnapshotForUserId(source.appearanceUserId)
			if typeof(source.region) == "string" and source.region ~= "" and appearanceSnapshot ~= nil then
				ViewportModelRenderer.RenderBodyPartPreview(
					viewport,
					source.bundleModel,
					source.region,
					appearanceSnapshot,
					source.previewScale,
					{
						applyPlayerClothing = source.applyPlayerClothing,
						applyPlayerBodyColors = source.applyPlayerBodyColors,
					}
				)
			else
				ViewportModelRenderer.RenderBundle(viewport, source.bundleModel)
			end
		else
			ViewportModelRenderer.Clear(viewport)
		end
	end

	local favoriteIcon = findFirstGuiChildInCard(cardRoot, { "FavoriteIcon" })
	if favoriteIcon then
		favoriteIcon.Visible = source.favoriteVisible == true
	end

	local equippedBorder = findFirstGuiChildInCard(cardRoot, { "EquippedBorder" })
	if equippedBorder then
		equippedBorder.Visible = source.equippedVisible == true
	end

	local mutationCover = findFirstGuiChildInCard(cardRoot, { "MutationCover" })
	if mutationCover and mutationCover:IsA("ImageLabel") then
		local mutationCoverTexture = if typeof(source.mutationCoverTexture) == "string" and source.mutationCoverTexture ~= ""
			then source.mutationCoverTexture
			else nil
		mutationCover.Visible = mutationCoverTexture ~= nil
		mutationCover.Image = mutationCoverTexture or ""
	end

	local sizeTag = findFirstGuiChildInCard(cardRoot, { "SizeTag" })
	if sizeTag and sizeTag:IsA("ImageLabel") then
		local sizeTagStyle = if typeof(source.sizeTagStyle) == "table"
			then source.sizeTagStyle
			else if typeof(source.sizeTagTexture) == "string" and source.sizeTagTexture ~= ""
				then {
					image = source.sizeTagTexture,
				}
				else nil
		applySizeTagStyle(sizeTag, sizeTagStyle)
	end

	if icon and icon:IsA("ImageLabel") then
		if shouldUseIcon then
			icon.Image = iconTexture
		end

		icon.Visible = shouldUseIcon or source.iconVisible == true
	end
end

return table.freeze(BodyPartPresentation)
