local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NumberFormatter = require(ReplicatedStorage.Shared.Formatting.NumberFormatter)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local SizeConfig = require(ReplicatedStorage.Shared.Config.SizeConfig)

local PlayerStatsPresentation = {}

local EARNED_SOURCE_ORDER = {
	"passive_income",
	"offline_income",
	"sell_single",
	"sell_bulk",
	"purchase_reward",
	"admin",
	"other",
}

local SPENT_SOURCE_ORDER = {
	"roll_cost",
	"admin",
	"other",
}

local FAILURE_REASON_ORDER = {
	"locked",
	"insufficient_money",
	"invalid_selection",
	"missing_config",
	"grant_failed",
	"unexpected_error",
}

local function formatNumberish(value: number?): string
	return NumberFormatter.Format(math.max(0, math.floor(tonumber(value) or 0)))
end

local function formatWholeWithSeparators(value: number?): string
	local wholeNumber = math.max(0, math.floor(tonumber(value) or 0))
	if wholeNumber >= 1e15 then
		return NumberFormatter.Format(wholeNumber)
	end

	local text = string.format("%.0f", wholeNumber)
	local reversedText = string.reverse(text)
	local formattedText = string.reverse((string.gsub(reversedText, "(%d%d%d)", "%1,")))
	if string.sub(formattedText, 1, 1) == "," then
		formattedText = string.sub(formattedText, 2)
	end

	return formattedText
end

local function formatDuration(totalSeconds: number?): string
	local seconds = math.max(0, math.floor(tonumber(totalSeconds) or 0))
	local days = math.floor(seconds / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	local minutes = math.floor((seconds % 3600) / 60)

	if days > 0 then
		return string.format("%dd %dh", days, hours)
	end
	if hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	end

	return string.format("%dm", minutes)
end

local function formatTimestamp(unixTimestamp: number?): string
	local timestamp = math.max(0, math.floor(tonumber(unixTimestamp) or 0))
	if timestamp <= 0 then
		return "Never"
	end

	local ok, dateTime = pcall(DateTime.fromUnixTimestamp, timestamp)
	if not ok or not dateTime then
		return tostring(timestamp)
	end

	return dateTime:FormatLocalTime("MMM D, YYYY h:mm A", "en-us")
end

local function formatLabel(key: string): string
	local label = tostring(key or ""):gsub("_", " ")
	return (label:gsub("(%a)([%w']*)", function(first, rest)
		return string.upper(first) .. string.lower(rest)
	end))
end

local function formatSizeId(key: any): string
	if typeof(key) ~= "string" or key == "" then
		return "Unknown"
	end

	local entry = SizeConfig.Get(key)
	if entry then
		return entry.displayName
	end

	if key == "compact" or key == "massive" then
		return SizeConfig.GetDisplayName(key)
	end

	return formatLabel(key)
end

local function formatBreakdown(map: any, orderedKeys: { string }?): string
	if typeof(map) ~= "table" then
		return "None"
	end

	local lines = {}
	local seen = {}

	if orderedKeys then
		for _, key in ipairs(orderedKeys) do
			seen[key] = true
			local value = tonumber(map[key]) or 0
			if value > 0 then
				table.insert(lines, string.format("%s: %s", formatLabel(key), formatNumberish(value)))
			end
		end
	end

	local remainingKeys = {}
	for key, value in pairs(map) do
		if not seen[key] and (tonumber(value) or 0) > 0 then
			table.insert(remainingKeys, tostring(key))
		end
	end
	table.sort(remainingKeys)

	for _, key in ipairs(remainingKeys) do
		table.insert(lines, string.format("%s: %s", tostring(key), formatNumberish(map[key])))
	end

	if #lines == 0 then
		return "None"
	end

	return table.concat(lines, "\n")
end

local function formatBestEver(bestEver: any): string
	if typeof(bestEver) ~= "table" or math.max(0, math.floor(tonumber(bestEver.displayedDenominator) or 0)) <= 0 then
		return "None recorded"
	end

	local piece = if typeof(bestEver.pieceId) == "string" then BodyPartsCatalog.GetPiece(bestEver.pieceId) else nil
	local pieceLabel = if piece then piece.displayName else tostring(bestEver.pieceId or "Unknown")
	local mutationId = tostring(bestEver.mutationId or "")
	local sizeId = tostring(bestEver.sizeId or "")
	local extras = {}

	if mutationId ~= "" and mutationId ~= "normal" then
		table.insert(extras, mutationId)
	end
	if sizeId ~= "" and sizeId ~= "normal" then
		table.insert(extras, formatSizeId(sizeId))
	end

	local detail = ""
	if #extras > 0 then
		detail = " | " .. table.concat(extras, " / ")
	end

	return string.format(
		"%s | 1/%s%s",
		pieceLabel,
		formatNumberish(bestEver.displayedDenominator),
		detail
	)
end

local function formatSizeBreakdown(map: any): string
	if typeof(map) ~= "table" then
		return "None"
	end

	local lines = {}
	local keys = {}
	for key, value in pairs(map) do
		if (tonumber(value) or 0) > 0 then
			table.insert(keys, tostring(key))
		end
	end
	table.sort(keys)

	for _, key in ipairs(keys) do
		table.insert(lines, string.format("%s: %s", formatSizeId(key), formatNumberish(map[key])))
	end

	if #lines == 0 then
		return "None"
	end

	return table.concat(lines, "\n")
end

function PlayerStatsPresentation.FormatBoardWholeNumber(value: number?): string
	return formatWholeWithSeparators(value)
end

function PlayerStatsPresentation.FormatBoardClockDuration(totalSeconds: number?): string
	local seconds = math.max(0, math.floor(tonumber(totalSeconds) or 0))
	local days = math.floor(seconds / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local remainingSeconds = seconds % 60

	return string.format("%02dd %02dh %02dm %02ds", days, hours, minutes, remainingSeconds)
end

function PlayerStatsPresentation.FormatBoardLuckMultiplier(value: number?): string
	local luckMultiplier = math.max(0, tonumber(value) or 1)
	local roundedValue = math.floor((luckMultiplier * 10) + 0.5) / 10

	return string.format("%.1fx", roundedValue)
end

function PlayerStatsPresentation.FormatBoardRarestRng(bestEver: any): string
	local denominator = if typeof(bestEver) == "table" then tonumber(bestEver.displayedDenominator) else nil
	denominator = math.max(0, math.floor(denominator or 0))
	if denominator <= 0 then
		return "None"
	end

	return "1/" .. formatWholeWithSeparators(denominator)
end

function PlayerStatsPresentation.FormatBoardRarestPart(bestEver: any): string
	local denominator = if typeof(bestEver) == "table" then tonumber(bestEver.displayedDenominator) else nil
	if math.max(0, math.floor(denominator or 0)) <= 0 then
		return "None"
	end

	local pieceId = if typeof(bestEver.pieceId) == "string" then bestEver.pieceId else ""
	local piece = if pieceId ~= "" then BodyPartsCatalog.GetPiece(pieceId) else nil
	return if piece then piece.displayName else if pieceId ~= "" then pieceId else "Unknown"
end

function PlayerStatsPresentation.BuildInspectStatusText(baseText: string, summary: any): string
	if typeof(summary) ~= "table" then
		return baseText
	end

	local lines = {
		baseText,
		string.format(
			"$%s | %s rolls | %s played",
			formatNumberish(summary.currentMoney),
			formatNumberish(summary.currentSuccessfulRollCount),
			formatDuration(summary.currentTimePlayed)
		),
		string.format(
			"Best: %s",
			formatBestEver(summary.stats and summary.stats.rolls and summary.stats.rolls.bestEver or nil)
		),
	}

	return table.concat(lines, "\n")
end

function PlayerStatsPresentation.BuildAdminSections(summary: any): { [string]: string }
	if typeof(summary) ~= "table" then
		return {
			overview = "No player summary loaded.",
			economy = "No economy data loaded.",
			rolls = "No roll data loaded.",
			collection = "No collection data loaded.",
			monetization = "No monetization data loaded.",
			settings = "No settings data loaded.",
		}
	end

	local stats = summary.stats or {}
	local lifecycle = stats.lifecycle or {}
	local economy = stats.economy or {}
	local rolls = stats.rolls or {}
	local collection = stats.collection or {}
	local monetization = stats.monetization or {}
	local settings = stats.settings or {}

	return {
		overview = table.concat({
			string.format("Player: %s (@%s)", tostring(summary.displayName or summary.name or "Unknown"), tostring(summary.name or "unknown")),
			string.format("Money: $%s", formatNumberish(summary.currentMoney)),
			string.format("Rolls: %s", formatNumberish(summary.currentSuccessfulRollCount)),
			string.format("Time Played: %s", formatDuration(summary.currentTimePlayed)),
			string.format("Sessions: %s", formatNumberish(lifecycle.joinCount)),
			string.format("First Seen: %s", formatTimestamp(lifecycle.firstSeenAt)),
			string.format("Last Join: %s", formatTimestamp(lifecycle.lastJoinAt)),
			string.format("Last Leave: %s", formatTimestamp(lifecycle.lastLeaveAt)),
			string.format("Longest Session: %s", formatDuration(lifecycle.longestSessionSeconds)),
			string.format("Current Owned Parts: %s", formatNumberish(summary.currentOwnedBodyParts)),
			string.format("Current Owned Auras: %s", formatNumberish(summary.currentOwnedAuras)),
			string.format("Best Ever: %s", formatBestEver(rolls.bestEver)),
		}, "\n"),
		economy = table.concat({
			string.format("Lifetime Earned: $%s", formatNumberish(economy.lifetimeEarned)),
			string.format("Lifetime Spent: $%s", formatNumberish(economy.lifetimeSpent)),
			string.format("Highest Money Held: $%s", formatNumberish(economy.highestMoneyHeld)),
			"Earned By Source:",
			formatBreakdown(economy.earnedBySource, EARNED_SOURCE_ORDER),
			"Spent By Source:",
			formatBreakdown(economy.spentBySource, SPENT_SOURCE_ORDER),
		}, "\n"),
		rolls = table.concat({
			string.format("Requests: %s", formatNumberish(rolls.totalRequests)),
			string.format("First-Time Discoveries: %s", formatNumberish(rolls.firstTimeDiscoveries)),
			string.format("Auto-Sell Queued: %s", formatNumberish(rolls.autoSellQueued)),
			string.format("Auto-Sold: %s", formatNumberish(rolls.autoSold)),
			string.format("Auto-Sell Kept: %s", formatNumberish(rolls.autoSellKept)),
			"Failures:",
			formatBreakdown(rolls.failedByReason, FAILURE_REASON_ORDER),
			"Roll Types:",
			formatBreakdown(rolls.byRollType),
			"Regions:",
			formatBreakdown(rolls.byRegion),
			"Display Rarities:",
			formatBreakdown(rolls.byRarity),
			"Set IDs:",
			formatBreakdown(rolls.bySetId),
			"Mutations:",
			formatBreakdown(rolls.byMutationId),
			"Sizes:",
			formatSizeBreakdown(rolls.bySizeId),
		}, "\n"),
		collection = table.concat({
			string.format("Body Parts Acquired: %s", formatNumberish(collection.totalBodyPartsAcquired)),
			string.format("Body Parts Sold: %s", formatNumberish(collection.totalBodyPartsSold)),
			string.format("Auras Acquired: %s", formatNumberish(collection.totalAurasAcquired)),
			string.format("Sets Completed First Time: %s", formatNumberish(collection.setsCompletedFirstTime)),
			string.format("Peak Owned Parts: %s", formatNumberish(collection.peakOwnedBodyParts)),
			string.format("Completed Set IDs Tracked: %s", formatNumberish(collection.seenCompletedSetIds and #collection.seenCompletedSetIds or 0)),
			string.format("Active Set: %s", tostring(summary.bonuses and summary.bonuses.activeSetId or "None")),
			string.format("Current Income / s: %s", formatNumberish(summary.bonuses and summary.bonuses.passiveIncomePerSecond)),
		}, "\n"),
		monetization = table.concat({
			string.format("First Purchase Key: %s", tostring(monetization.firstPurchaseKey ~= "" and monetization.firstPurchaseKey or "None")),
			string.format("First Purchase Seen At: %s", formatTimestamp(monetization.firstPurchaseAt)),
			"Prompts:",
			formatBreakdown(monetization.promptShownByKey),
			"Purchases Granted:",
			formatBreakdown(monetization.purchaseGrantedByKey),
			"Self Purchases:",
			formatBreakdown(monetization.selfPurchaseByKey),
			"Gift Purchases:",
			formatBreakdown(monetization.giftPurchaseByKey),
			"Gifts Sent:",
			formatBreakdown(monetization.giftsSentByKey),
			"Gifts Delivered:",
			formatBreakdown(monetization.giftsDeliveredByKey),
			"Gifts Received:",
			formatBreakdown(monetization.giftsReceivedByKey),
			"Duplicate Gifts Blocked:",
			formatBreakdown(monetization.duplicateGiftBlockedByKey),
		}, "\n"),
		settings = table.concat({
			string.format("Roll Type Changes: %s", formatNumberish(settings.rollTypeChanges)),
			string.format("Roll Region Changes: %s", formatNumberish(settings.rollRegionChanges)),
			string.format("Quick Roll Toggles: %s", formatNumberish(settings.quickRollToggleCount)),
			string.format("Auto Equip Best Toggles: %s", formatNumberish(settings.autoEquipBestToggleCount)),
			string.format("Auto-Sell Toggles: %s", formatNumberish(settings.autoSellToggleCount)),
			string.format("Cutscene Toggles: %s", formatNumberish(settings.cutsceneToggleCount)),
			string.format("Music Toggles: %s", formatNumberish(settings.musicToggleCount)),
		}, "\n"),
	}
end

return PlayerStatsPresentation
