local AchievementState = require(script.Parent.AchievementState)
local TitleConfig = require(script.Parent.Parent.Config.TitleConfig)
local PremiumBenefits = require(script.Parent.Parent.Premium.PremiumBenefits)

local TitleUtil = {}

local DEVELOPER_TAG_TEXT = "[DEVELOPER]"
local DEVELOPER_TAG_COLOR_HEX = "#ffd166"

local function normalizeOptionalString(value: any): string?
	if typeof(value) ~= "string" then
		return nil
	end

	local trimmed = string.match(value, "%S.*")
	if not trimmed or trimmed == "" then
		return nil
	end

	return trimmed
end

function TitleUtil.NormalizeEquippedTitleId(value: any): string?
	return normalizeOptionalString(value)
end

function TitleUtil.Color3ToHex(color: Color3?): string
	if typeof(color) ~= "Color3" then
		return "#ffffff"
	end

	return string.format("#%02x%02x%02x", math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255))
end

function TitleUtil.EscapeRichText(text: any): string
	local escaped = tostring(text or "")
	escaped = string.gsub(escaped, "&", "&amp;")
	escaped = string.gsub(escaped, "<", "&lt;")
	escaped = string.gsub(escaped, ">", "&gt;")
	return escaped
end

function TitleUtil.GetUnlockedTitles(achievementState: any): { TitleConfig.TitleConfigEntry }
	local normalizedState = AchievementState.Normalize(achievementState)
	local unlocked = {}

	for _, title in ipairs(TitleConfig.GetOrdered()) do
		if normalizedState.completedIds[title.achievementId] == true then
			table.insert(unlocked, title)
		end
	end

	return unlocked
end

function TitleUtil.IsTitleUnlocked(titleId: any, achievementState: any): boolean
	local normalizedTitleId = normalizeOptionalString(titleId)
	local title = normalizedTitleId and TitleConfig.Get(normalizedTitleId) or nil
	if not title then
		return false
	end

	local normalizedState = AchievementState.Normalize(achievementState)
	return normalizedState.completedIds[title.achievementId] == true
end

function TitleUtil.GetPrefixSegments(
	premiumTier: any,
	equippedTitleId: any,
	hasDeveloperTag: boolean?
): { { text: string, colorHex: string } }
	local segments = {}
	local normalizedTier = PremiumBenefits.NormalizeTier(premiumTier)

	if hasDeveloperTag == true then
		table.insert(segments, {
			text = DEVELOPER_TAG_TEXT,
			colorHex = DEVELOPER_TAG_COLOR_HEX,
		})
	end

	if normalizedTier ~= PremiumBenefits.Tiers.none then
		table.insert(segments, {
			text = PremiumBenefits.Tags[normalizedTier],
			colorHex = PremiumBenefits.Colors[normalizedTier],
		})
	end

	local normalizedTitleId = normalizeOptionalString(equippedTitleId)
	local title = normalizedTitleId and TitleConfig.Get(normalizedTitleId) or nil
	if title then
		table.insert(segments, {
			text = "[" .. title.label .. "]",
			colorHex = TitleUtil.Color3ToHex(title.displayColor),
		})
	end

	return segments
end

function TitleUtil.BuildRichTextPrefix(premiumTier: any, equippedTitleId: any, hasDeveloperTag: boolean?): string
	local segments = TitleUtil.GetPrefixSegments(premiumTier, equippedTitleId, hasDeveloperTag)
	local richSegments = {}

	for _, segment in ipairs(segments) do
		table.insert(
			richSegments,
			string.format('<font color="%s"><b>%s</b></font>', segment.colorHex, TitleUtil.EscapeRichText(segment.text))
		)
	end

	return table.concat(richSegments, " ")
end

function TitleUtil.BuildRichTextDisplayName(premiumTier: any, equippedTitleId: any, displayName: any): string
	local prefix = TitleUtil.BuildRichTextPrefix(premiumTier, equippedTitleId)
	local safeDisplayName = TitleUtil.EscapeRichText(displayName)
	if prefix == "" then
		return safeDisplayName
	end

	return prefix .. " " .. safeDisplayName
end

function TitleUtil.BuildLeaderboardRichTextPrefix(premiumTier: any): string
	local normalizedTier = PremiumBenefits.NormalizeTier(premiumTier)
	if normalizedTier == PremiumBenefits.Tiers.none then
		return ""
	end

	return string.format(
		'<font color="%s"><b>%s</b></font>',
		PremiumBenefits.Colors[normalizedTier],
		TitleUtil.EscapeRichText(PremiumBenefits.Tags[normalizedTier])
	)
end

function TitleUtil.BuildLeaderboardRichTextDisplayName(premiumTier: any, displayName: any): string
	local prefix = TitleUtil.BuildLeaderboardRichTextPrefix(premiumTier)
	local safeDisplayName = TitleUtil.EscapeRichText(displayName)
	if prefix == "" then
		return safeDisplayName
	end

	return prefix .. " " .. safeDisplayName
end

return table.freeze(TitleUtil)
