local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Schema = require(ReplicatedStorage.Lists.Schema)
local PlayerStats = require(ReplicatedStorage.Shared.Stats.PlayerStats)
local DataService = require(script.Parent.DataService)

local STATS_KEY = Schema.Stats and Schema.Stats.key or "stats"

local sessionStartedAtByPlayer: { [Player]: number } = {}

local StatsService = {}

local function incrementCounter(counterMap: { [string]: number }, key: string?, amount: number?)
	if key == nil or key == "" then
		return
	end

	counterMap[key] = math.max(0, math.floor(tonumber(counterMap[key]) or 0)) + math.max(0, math.floor(tonumber(amount) or 0))
end

local function mutateStats(player: Player, options: any?, mutator: (any) -> ())
	if DataService:Get(player) == nil then
		return false
	end

	DataService:Set(player, STATS_KEY, function(currentValue)
		local stats = PlayerStats.Normalize(currentValue, {
			bodyPartsState = if typeof(options) == "table" then options.bodyPartsState else nil,
			aurasState = if typeof(options) == "table" then options.aurasState else nil,
			currentMoney = if typeof(options) == "table" then options.currentMoney else nil,
			diagnostics = if typeof(options) == "table" then options.diagnostics else nil,
			successfulRollCount = if typeof(options) == "table" then options.successfulRollCount else nil,
		})
		mutator(stats)
		return stats
	end)

	return true
end

local function setStatsValue(player: Player, path: { any }, value: any): boolean
	return DataService:SetNestedValue(player, STATS_KEY, path, value)
end

local function setStatsValues(player: Player, path: { any }, values: { [any]: any }): boolean
	return DataService:SetNestedValues(player, STATS_KEY, path, values)
end

local function handleMoneyChanged(player: Player, previousValue: number, newValue: number, _delta: number, source: string?)
	local actualDelta = math.floor((tonumber(newValue) or 0) - (tonumber(previousValue) or 0))
	local stats = DataService:GetStats(player)
	if not stats then
		return
	end

	local economy = stats.economy
	economy.highestMoneyHeld = math.max(
		math.max(0, math.floor(tonumber(economy.highestMoneyHeld) or 0)),
		math.max(0, math.floor(tonumber(newValue) or 0))
	)

	if actualDelta > 0 then
		economy.lifetimeEarned += actualDelta
		incrementCounter(economy.earnedBySource, PlayerStats.NormalizeEarnedMoneySource(source), actualDelta)
	elseif actualDelta < 0 then
		local spentAmount = math.abs(actualDelta)
		economy.lifetimeSpent += spentAmount
		incrementCounter(economy.spentBySource, PlayerStats.NormalizeSpentMoneySource(source), spentAmount)
	end

	setStatsValues(player, {
		"economy",
	}, {
		highestMoneyHeld = economy.highestMoneyHeld,
		lifetimeEarned = economy.lifetimeEarned,
		lifetimeSpent = economy.lifetimeSpent,
		earnedBySource = economy.earnedBySource,
		spentBySource = economy.spentBySource,
	})
end

local function handleOwnedBodyPartAdded(player: Player, _record: any, bodyPartsState: any)
	local completedSetIds = PlayerStats.GetCompletedSetIds(bodyPartsState)
	local ownedCount = PlayerStats.CountOwnedBodyParts(bodyPartsState)
	local stats = DataService:GetStats(player)
	if not stats then
		return
	end

	local collection = stats.collection
	collection.totalBodyPartsAcquired += 1
	collection.peakOwnedBodyParts = math.max(collection.peakOwnedBodyParts, ownedCount)

	for setId in pairs(completedSetIds) do
		if collection.seenCompletedSetIds[setId] ~= true then
			collection.seenCompletedSetIds[setId] = true
			collection.setsCompletedFirstTime += 1
		end
	end

	setStatsValues(player, {
		"collection",
	}, {
		totalBodyPartsAcquired = collection.totalBodyPartsAcquired,
		peakOwnedBodyParts = collection.peakOwnedBodyParts,
		seenCompletedSetIds = collection.seenCompletedSetIds,
		setsCompletedFirstTime = collection.setsCompletedFirstTime,
	})
end

local function handleOwnedAuraAdded(player: Player, _record: any, aurasState: any)
	local stats = DataService:GetStats(player)
	if not stats then
		return
	end

	local totalAurasAcquired = math.max(
		stats.collection.totalAurasAcquired + 1,
		PlayerStats.CountOwnedAuras(aurasState)
	)
	setStatsValue(player, { "collection", "totalAurasAcquired" }, totalAurasAcquired)
end

function StatsService:GetStats(player: Player): any
	return DataService:GetStats(player)
end

function StatsService:RecordSessionJoin(player: Player)
	local now = os.time()
	sessionStartedAtByPlayer[player] = now

	mutateStats(player, {
		currentMoney = DataService:GetMoney(player),
		successfulRollCount = DataService:GetSuccessfulRollCount(player),
		bodyPartsState = DataService:GetBodyPartsState(player),
		aurasState = DataService:GetAurasState(player),
	}, function(stats)
		stats.lifecycle.joinCount += 1
		if stats.lifecycle.firstSeenAt <= 0 then
			stats.lifecycle.firstSeenAt = now
		end
		stats.lifecycle.lastJoinAt = now
	end)
end

function StatsService:RecordSessionLeave(player: Player)
	local now = os.time()
	local sessionStartedAt = sessionStartedAtByPlayer[player]
	sessionStartedAtByPlayer[player] = nil

	local sessionLengthSeconds = 0
	if sessionStartedAt ~= nil then
		sessionLengthSeconds = math.max(0, now - sessionStartedAt)
	end

	mutateStats(player, nil, function(stats)
		stats.lifecycle.lastLeaveAt = now
		stats.lifecycle.lastSessionLengthSeconds = sessionLengthSeconds
		stats.lifecycle.longestSessionSeconds = math.max(stats.lifecycle.longestSessionSeconds, sessionLengthSeconds)
	end)
end

function StatsService:RecordRollRequest(player: Player)
	local stats = DataService:GetStats(player)
	if not stats then
		return
	end

	setStatsValue(player, { "rolls", "totalRequests" }, stats.rolls.totalRequests + 1)
end

function StatsService:RecordRollFailure(player: Player, reason: string)
	local stats = DataService:GetStats(player)
	if not stats then
		return
	end

	incrementCounter(
		stats.rolls.failedByReason,
		PlayerStats.NormalizeRollFailureReason(reason),
		1
	)
	setStatsValue(player, { "rolls", "failedByReason" }, stats.rolls.failedByReason)
end

function StatsService:RecordRollSuccess(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return
	end

	local stats = DataService:GetStats(player)
	if not stats then
		return
	end

	local rolls = stats.rolls
	incrementCounter(rolls.byRollType, payload.rollTypeId, 1)
	incrementCounter(rolls.byRegion, payload.rollRegion, 1)
	incrementCounter(rolls.byRarity, payload.displayRarity, 1)
	incrementCounter(rolls.bySetId, payload.setId, 1)
	incrementCounter(rolls.byMutationId, payload.mutationId, 1)
	incrementCounter(rolls.bySizeId, payload.sizeId, 1)

	if payload.didDiscoverPieceFirstTime == true then
		rolls.firstTimeDiscoveries += 1
	end
	if payload.pendingAutoSell == true then
		rolls.autoSellQueued += 1
	end

	local candidateBestEver = {
		displayedDenominator = math.max(0, math.floor(tonumber(payload.displayedDenominator) or 0)),
		pieceId = payload.pieceId,
		setId = payload.setId,
		displayRarity = payload.displayRarity,
		mutationId = payload.mutationId,
		sizeId = payload.sizeId,
		variantMultiplier = tonumber(payload.variantMultiplier) or 1,
		serialNumber = math.max(0, math.floor(tonumber(payload.serialNumber) or 0)),
		achievedAt = os.time(),
	}

	if PlayerStats.ShouldReplaceBestEver(rolls.bestEver, candidateBestEver) then
		rolls.bestEver = candidateBestEver
	end

	setStatsValues(player, { "rolls" }, {
		byRollType = rolls.byRollType,
		byRegion = rolls.byRegion,
		byRarity = rolls.byRarity,
		bySetId = rolls.bySetId,
		byMutationId = rolls.byMutationId,
		bySizeId = rolls.bySizeId,
		autoSellQueued = rolls.autoSellQueued,
		firstTimeDiscoveries = rolls.firstTimeDiscoveries,
		bestEver = rolls.bestEver,
	})
end

function StatsService:RecordAutoSellOutcome(player: Player, outcome: string)
	local stats = DataService:GetStats(player)
	if not stats then
		return
	end

	if outcome == "sold" then
		setStatsValue(player, { "rolls", "autoSold" }, stats.rolls.autoSold + 1)
	elseif outcome == "kept" then
		setStatsValue(player, { "rolls", "autoSellKept" }, stats.rolls.autoSellKept + 1)
	end
end

function StatsService:RecordLoadoutAction(player: Player, action: string)
	local key = PlayerStats.NormalizeLoadoutAction(action)
	if not key then
		return
	end

	mutateStats(player, nil, function(stats)
		stats.loadout[key] += 1
	end)
end

function StatsService:RecordSettingChange(player: Player, kind: string)
	local key = PlayerStats.NormalizeSettingChangeKind(kind)
	if not key then
		return
	end

	local stats = DataService:GetStats(player)
	if not stats then
		return
	end

	setStatsValue(player, { "settings", key }, stats.settings[key] + 1)
end

function StatsService:RecordBodyPartsSold(player: Player, amount: number)
	local soldCount = math.max(0, math.floor(tonumber(amount) or 0))
	if soldCount <= 0 then
		return
	end

	local stats = DataService:GetStats(player)
	if not stats then
		return
	end

	setStatsValue(player, { "collection", "totalBodyPartsSold" }, stats.collection.totalBodyPartsSold + soldCount)
end

function StatsService:RecordTransientBodyPartAcquired(player: Player)
	local stats = DataService:GetStats(player)
	if not stats then
		return
	end

	setStatsValue(player, { "collection", "totalBodyPartsAcquired" }, stats.collection.totalBodyPartsAcquired + 1)
end

function StatsService:RecordPurchasePrompt(player: Player, key: string)
	if typeof(key) ~= "string" or key == "" then
		return
	end

	mutateStats(player, nil, function(stats)
		incrementCounter(stats.monetization.promptShownByKey, key, 1)
	end)
end

function StatsService:RecordPurchaseProcessed(player: Player, context: any)
	if typeof(context) ~= "table" or context.isNew ~= true then
		return
	end

	local key = if typeof(context.key) == "string" and context.key ~= "" then context.key else tostring(context.id or "")
	if key == "" then
		return
	end

	local now = os.time()
	mutateStats(player, nil, function(stats)
		if stats.monetization.firstPurchaseAt <= 0 then
			stats.monetization.firstPurchaseAt = now
			stats.monetization.firstPurchaseKey = key
		end

		incrementCounter(stats.monetization.purchaseGrantedByKey, key, 1)
		if context.purchaseKind == "gift" then
			incrementCounter(stats.monetization.giftPurchaseByKey, key, 1)
		else
			incrementCounter(stats.monetization.selfPurchaseByKey, key, 1)
		end
	end)
end

function StatsService:RecordGiftSent(player: Player, key: string)
	if typeof(key) ~= "string" or key == "" then
		return
	end

	mutateStats(player, nil, function(stats)
		incrementCounter(stats.monetization.giftsSentByKey, key, 1)
	end)
end

function StatsService:RecordGiftDelivered(player: Player, key: string)
	if typeof(key) ~= "string" or key == "" then
		return
	end

	mutateStats(player, nil, function(stats)
		incrementCounter(stats.monetization.giftsDeliveredByKey, key, 1)
		incrementCounter(stats.monetization.giftsReceivedByKey, key, 1)
	end)
end

function StatsService:RecordDuplicateGiftBlocked(player: Player, key: string)
	if typeof(key) ~= "string" or key == "" then
		return
	end

	mutateStats(player, nil, function(stats)
		incrementCounter(stats.monetization.duplicateGiftBlockedByKey, key, 1)
	end)
end

function StatsService:OnStart()
	DataService.PlayerDataLoaded:Connect(function(player: Player)
		self:RecordSessionJoin(player)
	end)

	DataService.PlayerDataRemoving:Connect(function(player: Player)
		self:RecordSessionLeave(player)
	end)

	DataService.MoneyChanged:Connect(handleMoneyChanged)
	DataService.OwnedBodyPartAdded:Connect(handleOwnedBodyPartAdded)
	DataService.OwnedAuraAdded:Connect(handleOwnedAuraAdded)
end

function StatsService:OnPlayerRemoving(player: Player)
	sessionStartedAtByPlayer[player] = nil
end

return StatsService
