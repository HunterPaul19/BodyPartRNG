local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local BossRewards = require(ReplicatedStorage.Shared.BossArena.BossRewards)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local RollMath = require(ReplicatedStorage.Shared.Rolling.RollMath)
local SizeConfig = require(ReplicatedStorage.Shared.Config.SizeConfig)
local Notify = require(ReplicatedStorage.Shared.UI.Notify)
local DataService = require(script.Parent.DataService)

type RewardGrantEntry = {
	pieceId: string,
	displayName: string,
	setId: string,
	displayRarity: string,
	displayOddsDenominator: number,
	isBossPart: boolean,
}

export type RewardSummary = {
	player: Player?,
	bossId: string,
	grants: { RewardGrantEntry },
	grantedCount: number,
	skippedCount: number,
	stoppedReason: string?,
	message: string,
}

local BossArenaRewardService = {}

local DEFAULT_MUTATION = MutationConfig.GetDefault()
local DEFAULT_SIZE = SizeConfig.GetDefault()
local DEFAULT_SIZE_SCALE = SizeConfig.GetRepresentativeScale(DEFAULT_SIZE.id)
local INSUFFICIENT_DAMAGE_REWARD_MESSAGE = "Boss rewards require at least 15% damage contribution."
local warnedMissingPools = {}

local function warnWithPrefix(message: string)
	warn(string.format("[BossArenaRewardService] %s", message))
end

local function getPlayerByUserId(userId: number): Player?
	for _, player in ipairs(Players:GetPlayers()) do
		if player.UserId == userId then
			return player
		end
	end

	return nil
end

local function buildAllowedRaritySet(profile: BossRewards.BossRewardProfile): { [string]: boolean }
	local allowed = {}

	for _, rarity in ipairs(profile.allowedRarities) do
		allowed[rarity] = true
	end

	return allowed
end

local function buildNormalRewardPoolsByRarity(profile: BossRewards.BossRewardProfile): { [string]: { any } }
	local allowedRarities = buildAllowedRaritySet(profile)
	local poolsByRarity = {}

	for _, rollEntry in ipairs(BodyPartsCatalog.GetRollEntries()) do
		local setId = rollEntry.id
		local displayRarity = tostring(rollEntry.rollDisplay.rarity or "Basic")
		if setId ~= profile.bossSetId and allowedRarities[displayRarity] == true then
			local rarityPool = poolsByRarity[displayRarity]
			if rarityPool == nil then
				rarityPool = {}
				poolsByRarity[displayRarity] = rarityPool
			end
			table.insert(rarityPool, rollEntry)
		end
	end

	return poolsByRarity
end

local function chooseRandomPieceFromSet(randomSource: Random, setId: string): any?
	local pieces = BodyPartsCatalog.GetPiecesForSet(setId)
	if not pieces or #pieces <= 0 then
		return nil
	end

	return pieces[randomSource:NextInteger(1, #pieces)]
end

local function chooseWeightedSetFromPool(randomSource: Random, pool: { any }): any?
	return RollMath.ChooseWeighted(randomSource, pool, function(entry)
		return math.max(0, tonumber(entry.baseChance) or 0)
	end)
end

local function rollRewardRarity(
	randomSource: Random,
	floorPreset: BossRewards.LootFloorPreset,
	poolsByRarity: { [string]: { any } }
): string?
	local eligibleEntries = {}
	local totalProbability = 0

	for _, entry in ipairs(floorPreset.tierOddsOrdered) do
		local rarityPool = poolsByRarity[entry.displayRarity]
		local probability = math.max(0, tonumber(entry.probability) or 0)
		if rarityPool ~= nil and #rarityPool > 0 and probability > 0 then
			totalProbability += probability
			table.insert(eligibleEntries, {
				displayRarity = entry.displayRarity,
				probability = probability,
			})
		end
	end

	if totalProbability <= 0 then
		return nil
	end

	local threshold = randomSource:NextNumber() * totalProbability
	local cumulativeProbability = 0
	local lastEntry = nil

	for _, entry in ipairs(eligibleEntries) do
		lastEntry = entry
		cumulativeProbability += entry.probability
		if threshold <= cumulativeProbability then
			return entry.displayRarity
		end
	end

	if lastEntry ~= nil then
		return lastEntry.displayRarity
	end

	return nil
end

local function buildGrantPayload(entry: RewardGrantEntry): { [string]: any }
	local setConfig = BodyPartsCatalog.GetSet(entry.setId)
	local piece = BodyPartsCatalog.GetPiece(entry.pieceId)

	return {
		pieceId = entry.pieceId,
		rarityDenominator = tonumber(setConfig and setConfig.rollDisplay and setConfig.rollDisplay.chance) or 1,
		rolledSetId = entry.setId,
		rolledSetDisplayName = if setConfig then setConfig.rollDisplay.displayName else nil,
		displayOddsDenominator = tonumber(setConfig and setConfig.rollDisplay and setConfig.rollDisplay.chance) or 1,
		displayRarity = entry.displayRarity,
		mutationId = DEFAULT_MUTATION.id,
		mutation = DEFAULT_MUTATION.displayName,
		mutationMultiplier = DEFAULT_MUTATION.multiplier,
		sizeId = DEFAULT_SIZE.id,
		sizeMultiplier = DEFAULT_SIZE_SCALE,
		variantMultiplier = DEFAULT_MUTATION.multiplier + DEFAULT_SIZE.moneyMultiplier - 1,
		finalPassiveIncomePerSecond = tonumber(piece and piece.passiveIncomePerSecond) or 0,
	}
end

local function isInventoryFullError(message: string?): boolean
	return typeof(message) == "string" and string.find(string.lower(message), "inventory is full", 1, true) ~= nil
end

local function getPlayerBossDamage(encounter: any, userId: number): number
	local damageByUserId = if typeof(encounter) == "table" then encounter.damageByUserId else nil
	if typeof(damageByUserId) ~= "table" then
		return 0
	end

	return math.max(0, tonumber(damageByUserId[userId]) or 0)
end

local function getRewardEligibleDamageThreshold(encounter: any): number
	if typeof(encounter) ~= "table" then
		return 0
	end

	return math.max(0, tonumber(encounter.rewardEligibleDamageThreshold) or 0)
end

local function hasRewardEligibleDamage(encounter: any, userId: number): boolean
	return getPlayerBossDamage(encounter, userId) >= getRewardEligibleDamageThreshold(encounter)
end

local function formatRewardNames(grants: { RewardGrantEntry }): string
	local names = table.create(#grants)

	for _, grant in ipairs(grants) do
		table.insert(names, grant.displayName)
	end

	return table.concat(names, ", ")
end

local function buildSummaryMessage(summary: RewardSummary): string
	if summary.grantedCount <= 0 then
		if summary.stoppedReason == "insufficient_damage" then
			return INSUFFICIENT_DAMAGE_REWARD_MESSAGE
		end

		if summary.stoppedReason == "inventory_full" then
			return string.format("Boss rewards skipped: inventory full (%d slot(s)).", summary.skippedCount)
		end

		return string.format("Boss rewards could not be granted (%d skipped).", summary.skippedCount)
	end

	local baseMessage = string.format("Boss rewards: %s.", formatRewardNames(summary.grants))
	if summary.skippedCount <= 0 then
		return baseMessage
	end

	if summary.stoppedReason == "inventory_full" then
		return string.format("%s %d skipped (inventory full).", baseMessage, summary.skippedCount)
	end

	return string.format("%s %d skipped.", baseMessage, summary.skippedCount)
end

local function buildRewardEntryFromSetPiece(piece: any, setId: string, isBossPart: boolean): RewardGrantEntry?
	if piece == nil then
		return nil
	end

	local setConfig = BodyPartsCatalog.GetSet(setId)
	if setConfig == nil then
		return nil
	end

	return {
		pieceId = piece.id,
		displayName = tostring(piece.displayName or piece.id),
		setId = setId,
		displayRarity = tostring(setConfig.rollDisplay.rarity or "Basic"),
		displayOddsDenominator = math.max(1, math.floor(tonumber(setConfig.rollDisplay.chance) or 1)),
		isBossPart = isBossPart,
	}
end

local function rollRewardEntry(
	randomSource: Random,
	profile: BossRewards.BossRewardProfile,
	floorPreset: BossRewards.LootFloorPreset,
	poolsByRarity: { [string]: { any } }
): RewardGrantEntry?
	local bossPartChance = math.clamp(tonumber(profile.bossPartChance) or 0, 0, 1)
	if bossPartChance > 0 and randomSource:NextNumber() < bossPartChance then
		local bossPiece = chooseRandomPieceFromSet(randomSource, profile.bossSetId)
		return buildRewardEntryFromSetPiece(bossPiece, profile.bossSetId, true)
	end

	local selectedRarity = rollRewardRarity(randomSource, floorPreset, poolsByRarity)
	if selectedRarity == nil then
		local warnKey = string.format("%s:%s:no-eligible-rarity", profile.bossId, floorPreset.id)
		if warnedMissingPools[warnKey] ~= true then
			warnedMissingPools[warnKey] = true
			warnWithPrefix(string.format(
				"Boss '%s' has no eligible reward rarity pools for loot floor '%s' after filtering.",
				profile.bossId,
				floorPreset.id
			))
		end
		return nil
	end

	local rarityPool = poolsByRarity[selectedRarity]
	if rarityPool == nil or #rarityPool <= 0 then
		local warnKey = string.format("%s:%s", profile.bossId, selectedRarity)
		if warnedMissingPools[warnKey] ~= true then
			warnedMissingPools[warnKey] = true
			warnWithPrefix(string.format(
				"Boss '%s' rolled rarity '%s', but no eligible reward sets remain after filtering.",
				profile.bossId,
				selectedRarity
			))
		end
		return nil
	end

	local weightedSet = chooseWeightedSetFromPool(randomSource, rarityPool)
	if weightedSet == nil then
		return nil
	end

	local rewardPiece = chooseRandomPieceFromSet(randomSource, weightedSet.id)
	return buildRewardEntryFromSetPiece(rewardPiece, weightedSet.id, false)
end

local function buildRewardSummary(player: Player?, bossId: string): RewardSummary
	return {
		player = player,
		bossId = bossId,
		grants = {},
		grantedCount = 0,
		skippedCount = 0,
		stoppedReason = nil,
		message = "",
	}
end

local function grantRewardsToPlayer(
	player: Player,
	bossId: string,
	profile: BossRewards.BossRewardProfile,
	floorPreset: BossRewards.LootFloorPreset,
	poolsByRarity: { [string]: { any } }
): RewardSummary
	local summary = buildRewardSummary(player, bossId)
	local randomSource = Random.new()

	for slotIndex = 1, math.max(0, math.floor(tonumber(profile.slotCount) or 0)) do
		local rewardEntry = rollRewardEntry(randomSource, profile, floorPreset, poolsByRarity)
		if rewardEntry == nil then
			summary.skippedCount += 1
			continue
		end

		local grantedRecord, grantError = DataService:AddOwnedBodyPart(player, buildGrantPayload(rewardEntry))
		if grantedRecord == nil then
			local remainingSlots = math.max(0, profile.slotCount - slotIndex + 1)
			summary.skippedCount += remainingSlots
			summary.stoppedReason = if isInventoryFullError(grantError) then "inventory_full" else "grant_failed"
			if summary.stoppedReason ~= "inventory_full" then
				warnWithPrefix(string.format(
					"Failed to grant boss reward to %s for boss '%s': %s",
					player.Name,
					bossId,
					tostring(grantError)
				))
			end
			break
		end

		summary.grantedCount += 1
		table.insert(summary.grants, rewardEntry)
	end

	summary.message = buildSummaryMessage(summary)
	return summary
end

function BossArenaRewardService:GrantVictoryRewards(encounter: any): { [number]: RewardSummary }
	local results = {}
	if typeof(encounter) ~= "table" then
		return results
	end

	local bossId = encounter.bossId
	if typeof(bossId) ~= "string" or bossId == "" then
		return results
	end

	local profile = BossRewards.GetBossRewardProfile(bossId)
	if profile == nil then
		warnWithPrefix(string.format("No reward profile is configured for boss '%s'.", bossId))
		return results
	end

	local floorPreset = BossRewards.GetLootFloorPreset(profile.lootFloorId)
	if floorPreset == nil then
		warnWithPrefix(string.format("Boss '%s' references unknown reward floor '%s'.", bossId, tostring(profile.lootFloorId)))
		return results
	end

	local poolsByRarity = buildNormalRewardPoolsByRarity(profile)
	if next(poolsByRarity) == nil then
		warnWithPrefix(string.format("Boss '%s' reward pools are empty after filtering.", bossId))
		return results
	end

	for _, userId in ipairs(encounter.rosterOrder or {}) do
		local player = getPlayerByUserId(userId)
		if player == nil then
			continue
		end

		if not hasRewardEligibleDamage(encounter, userId) then
			local summary = buildRewardSummary(player, bossId)
			summary.stoppedReason = "insufficient_damage"
			summary.message = buildSummaryMessage(summary)
			results[player.UserId] = summary

			Notify.Send(player, summary.message, {
				title = "Boss Rewards",
				channel = "inventory",
				tone = "neutral",
			})
			continue
		end

		local summary = grantRewardsToPlayer(player, bossId, profile, floorPreset, poolsByRarity)
		results[player.UserId] = summary

		if summary.message ~= "" then
			Notify.Send(player, summary.message, {
				title = "Boss Rewards",
				channel = "inventory",
				tone = "good",
			})
		end
	end

	return results
end

return BossArenaRewardService
