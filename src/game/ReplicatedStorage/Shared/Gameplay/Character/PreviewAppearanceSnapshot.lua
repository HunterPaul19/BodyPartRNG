local HttpService = game:GetService("HttpService")

local PreviewAppearanceSnapshot = {}

export type EncodedColor = {
	r: number,
	g: number,
	b: number,
}

export type Snapshot = {
	version: number,
	sourceUserId: number,
	cacheKey: string,
	shirtTemplate: string?,
	pantsTemplate: string?,
	shirtGraphic: string?,
	bodyColors: {
		Head: EncodedColor,
		Torso: EncodedColor,
		LeftArm: EncodedColor,
		RightArm: EncodedColor,
		LeftLeg: EncodedColor,
		RightLeg: EncodedColor,
	},
}

local VERSION = 1
local FOLDER_NAME = "PreviewAppearanceSnapshots"

PreviewAppearanceSnapshot.FolderName = FOLDER_NAME

local COLOR_REGIONS = {
	"Head",
	"Torso",
	"LeftArm",
	"RightArm",
	"LeftLeg",
	"RightLeg",
}

local DEFAULT_COLOR = {
	r = 0.917647,
	g = 0.721569,
	b = 0.572549,
}

local function clampChannel(value: any): number
	return math.clamp(tonumber(value) or 0, 0, 1)
end

local function encodeColor(color: any): EncodedColor
	if typeof(color) == "Color3" then
		return {
			r = color.R,
			g = color.G,
			b = color.B,
		}
	end

	if typeof(color) == "table" then
		return {
			r = clampChannel(color.r),
			g = clampChannel(color.g),
			b = clampChannel(color.b),
		}
	end

	return table.clone(DEFAULT_COLOR)
end

local function decodeColor(color: EncodedColor?): Color3
	if typeof(color) ~= "table" then
		return Color3.new(DEFAULT_COLOR.r, DEFAULT_COLOR.g, DEFAULT_COLOR.b)
	end

	return Color3.new(
		clampChannel(color.r),
		clampChannel(color.g),
		clampChannel(color.b)
	)
end

local function normalizeTemplateString(value: any): string?
	if typeof(value) ~= "string" then
		return nil
	end

	local trimmed = string.gsub(value, "^%s+", "")
	trimmed = string.gsub(trimmed, "%s+$", "")
	if trimmed == "" then
		return nil
	end

	return trimmed
end

local function buildBodyColors(value: any)
	local source = if typeof(value) == "table" then value else {}
	local bodyColors = {}

	for _, region in ipairs(COLOR_REGIONS) do
		bodyColors[region] = encodeColor(source[region])
	end

	return bodyColors
end

local function buildCacheKey(
	sourceUserId: number,
	shirtTemplate: string?,
	pantsTemplate: string?,
	shirtGraphic: string?,
	bodyColors
): string
	local colorParts = table.create(#COLOR_REGIONS)
	for index, region in ipairs(COLOR_REGIONS) do
		local color = bodyColors[region]
		colorParts[index] = string.format(
			"%s:%03d%03d%03d",
			region,
			math.round(clampChannel(color.r) * 255),
			math.round(clampChannel(color.g) * 255),
			math.round(clampChannel(color.b) * 255)
		)
	end

	return table.concat({
		"v" .. tostring(VERSION),
		"u" .. tostring(math.max(0, math.floor(tonumber(sourceUserId) or 0))),
		"s" .. tostring(shirtTemplate or ""),
		"p" .. tostring(pantsTemplate or ""),
		"g" .. tostring(shirtGraphic or ""),
		table.concat(colorParts, "|"),
	}, "|")
end

function PreviewAppearanceSnapshot.CreateEmpty(sourceUserId: number?): Snapshot
	local resolvedUserId = math.max(0, math.floor(tonumber(sourceUserId) or 0))
	local bodyColors = buildBodyColors(nil)

	return {
		version = VERSION,
		sourceUserId = resolvedUserId,
		cacheKey = buildCacheKey(resolvedUserId, nil, nil, nil, bodyColors),
		shirtTemplate = nil,
		pantsTemplate = nil,
		shirtGraphic = nil,
		bodyColors = bodyColors,
	}
end

function PreviewAppearanceSnapshot.Normalize(value: any, sourceUserId: number?): Snapshot
	if typeof(value) ~= "table" then
		return PreviewAppearanceSnapshot.CreateEmpty(sourceUserId)
	end

	local resolvedUserId = math.max(0, math.floor(tonumber(value.sourceUserId or sourceUserId) or 0))
	local shirtTemplate = normalizeTemplateString(value.shirtTemplate)
	local pantsTemplate = normalizeTemplateString(value.pantsTemplate)
	local shirtGraphic = normalizeTemplateString(value.shirtGraphic)
	local bodyColors = buildBodyColors(value.bodyColors)

	return {
		version = VERSION,
		sourceUserId = resolvedUserId,
		cacheKey = buildCacheKey(resolvedUserId, shirtTemplate, pantsTemplate, shirtGraphic, bodyColors),
		shirtTemplate = shirtTemplate,
		pantsTemplate = pantsTemplate,
		shirtGraphic = shirtGraphic,
		bodyColors = bodyColors,
	}
end

function PreviewAppearanceSnapshot.FromCharacterAppearance(character: Model?, sourceUserId: number?): Snapshot
	if not (character and character:IsA("Model")) then
		return PreviewAppearanceSnapshot.CreateEmpty(sourceUserId)
	end

	local bodyColorsInstance = character:FindFirstChildOfClass("BodyColors")
	local shirt = character:FindFirstChildOfClass("Shirt")
	local pants = character:FindFirstChildOfClass("Pants")
	local shirtGraphic = character:FindFirstChildOfClass("ShirtGraphic")

	return PreviewAppearanceSnapshot.Normalize({
		sourceUserId = sourceUserId,
		shirtTemplate = if shirt then shirt.ShirtTemplate else nil,
		pantsTemplate = if pants then pants.PantsTemplate else nil,
		shirtGraphic = if shirtGraphic then shirtGraphic.Graphic else nil,
		bodyColors = {
			Head = if bodyColorsInstance then bodyColorsInstance.HeadColor3 else nil,
			Torso = if bodyColorsInstance then bodyColorsInstance.TorsoColor3 else nil,
			LeftArm = if bodyColorsInstance then bodyColorsInstance.LeftArmColor3 else nil,
			RightArm = if bodyColorsInstance then bodyColorsInstance.RightArmColor3 else nil,
			LeftLeg = if bodyColorsInstance then bodyColorsInstance.LeftLegColor3 else nil,
			RightLeg = if bodyColorsInstance then bodyColorsInstance.RightLegColor3 else nil,
		},
	}, sourceUserId)
end

function PreviewAppearanceSnapshot.DecodeColor(bodyColors: any, region: string): Color3
	if typeof(bodyColors) ~= "table" then
		return decodeColor(nil)
	end

	return decodeColor(bodyColors[region])
end

function PreviewAppearanceSnapshot.Encode(snapshot: Snapshot?): string
	local normalized = PreviewAppearanceSnapshot.Normalize(snapshot)
	return HttpService:JSONEncode(normalized)
end

function PreviewAppearanceSnapshot.Decode(payload: any, sourceUserId: number?): Snapshot
	if typeof(payload) == "string" and payload ~= "" then
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(payload)
		end)
		if ok then
			return PreviewAppearanceSnapshot.Normalize(decoded, sourceUserId)
		end
	end

	return PreviewAppearanceSnapshot.Normalize(payload, sourceUserId)
end

return table.freeze(PreviewAppearanceSnapshot)
