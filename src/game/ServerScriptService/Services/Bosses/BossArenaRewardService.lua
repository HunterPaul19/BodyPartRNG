local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local BossRewards = require(ReplicatedStorage.Shared.BossArena.BossRewards)
local CraftingMaterialConfig = require(ReplicatedStorage.Shared.Config.CraftingMaterialConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local RollMath = require(ReplicatedStorage.Shared.Rolling.RollMath)
local SizeConfig = require(ReplicatedStorage.Shared.Config.SizeConfig)
local Notify = require(ReplicatedStorage.Shared.UI.Notify)
local DataService = require(script.Parent.DataService)

type BodyPartRewardGrantEntry = {
	kind: "bodyPart",
	pieceId: string,
	displayName: string,
	setId: string,
	displayRarity: string,
	displayOddsDenominator: number,
	isBossPart: boolean,
}

type MaterialRewardGrantEntry = {
	kind: "material",
	materialId: string,
	displayName: string,
	amount: number,
	dropTier: BossRewards.MaterialDropTier,
	chance: number,
	displayColor: Color3,
}

type RewardGrantEntry = BodyPartRewardGrantEntry | MaterialRewardGrantEntry

export type RewardSummary = {
	player: Player?,
	bossId: string,
	grants: { RewardGrantEntry },
	grantedCount: number,
	skippedCount: number,
	stoppedReason: string?,
	message: string,
}

type PreparedBodyPartReward = {
	kind: "bodyPart",
	grant: BodyPartRewardGrantEntry,
	payload: { [string]: any },
	reservation: { pieceId: string, serialNumber: number },
	committed: boolean?,
	released: boolean?,
}

type PreparedMaterialReward = {
	kind: "material",
	grant: MaterialRewardGrantEntry,
	committed: boolean?,
	released: boolean?,
}

type PreparedReward = PreparedBodyPartReward | PreparedMaterialReward

type PreparedPlayerRewards = {
	userId: number,
	rewards: { PreparedReward },
	skippedCount: number,
	status: string,
	error: string?,
	committed: boolean?,
	released: boolean?,
}

type PreparedEncounterRewards = {
	bossId: string,
	status: string,
	byUserId: { [number]: PreparedPlayerRewards },
	releaseRequested: boolean?,
	error: string?,
}

local BossArenaRewardService = {}

local DEFAULT_MUTATION = MutationConfig.GetDefault()
local DEFAULT_SIZE = SizeConfig.GetDefault()
local DEFAULT_SIZE_SCALE = SizeConfig.GetRepresentativeScale(DEFAULT_SIZE.id)
local INSUFFICIENT_DAMAGE_REWARD_MESSAGE = "Boss rewards require at least 15% damage contribution."
local warnedMissingPools = {}

local function warnWithPrefix(message: string)
	Logger.Warn(string.format("[BossArenaRewardService] %s", message))
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

local function buildGrantPayload(entry: BodyPartRewardGrantEntry): { [string]: any }
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
		if grant.kind == "material" then
			table.insert(names, string.format("%s x%d", grant.displayName, grant.amount))
		else
			table.insert(names, grant.displayName)
		end
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

local function buildRewardEntryFromSetPiece(piece: any, setId: string, isBossPart: boolean): BodyPartRewardGrantEntry?
	if piece == nil then
		return nil
	end

	local setConfig = BodyPartsCatalog.GetSet(setId)
	if setConfig == nil then
		return nil
	end

	return {
		kind = "bodyPart",
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
): BodyPartRewardGrantEntry?
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

local function buildMaterialRewardEntry(
	drop: BossRewards.BossMaterialDropEntry,
	amount: number
): MaterialRewardGrantEntry?
	local config = CraftingMaterialConfig.Get(drop.materialId)
	if not config then
		return nil
	end

	return {
		kind = "material",
		materialId = config.id,
		displayName = config.label,
		amount = math.max(1, math.floor(tonumber(amount) or 1)),
		dropTier = drop.dropTier,
		chance = math.clamp(tonumber(drop.chance) or 0, 0, 1),
		displayColor = config.displayColor,
	}
end

local function rollMaterialRewardEntries(randomSource: Random, bossId: string): { MaterialRewardGrantEntry }
	local entries = {}

	for _, drop in ipairs(BossRewards.GetBossMaterialDrops(bossId)) do
		local chance = math.clamp(tonumber(drop.chance) or 0, 0, 1)
		if chance >= 1 or randomSource:NextNumber() < chance then
			local amountMin = math.max(1, math.floor(tonumber(drop.amountMin) or 1))
			local amountMax = math.max(amountMin, math.floor(tonumber(drop.amountMax) or amountMin))
			local entry = buildMaterialRewardEntry(drop, randomSource:NextInteger(amountMin, amountMax))
			if entry then
				table.insert(entries, entry)
			end
		end
	end

	return entries
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

local function getPreparedRewardsState(encounter: any): PreparedEncounterRewards?
	if typeof(encounter) ~= "table" then
		return nil
	end

	local state = encounter.preparedBossRewards
	if typeof(state) ~= "table" then
		return nil
	end

	return state
end

local function releaseSerialReservationsAsync(serialReservations: { any }, reason: string?)
	if #serialReservations <= 0 then
		return
	end

	task.spawn(function()
		local didRelease, releaseError = DataService:ReleaseBodyPartSerials(serialReservations)
		if not didRelease then
			warnWithPrefix(string.format(
				"Failed to release %d prepared boss reward serial(s)%s: %s",
				#serialReservations,
				if typeof(reason) == "string" and reason ~= "" then " for " .. reason else "",
				tostring(releaseError)
			))
		end
	end)
end

local function collectPreparedRewardRelease(
	preparedReward: PreparedReward,
	serialReservations: { any }
)
	if preparedReward.released == true or preparedReward.committed == true then
		return
	end

	preparedReward.released = true
	if preparedReward.kind ~= "bodyPart" then
		return
	end

	local reservation = preparedReward.reservation
	local pieceId = if typeof(reservation) == "table" then reservation.pieceId else nil
	local serialNumber = if typeof(reservation) == "table" then tonumber(reservation.serialNumber) else nil
	if typeof(pieceId) == "string" and pieceId ~= "" and serialNumber ~= nil and serialNumber > 0 then
		table.insert(serialReservations, {
			pieceId = pieceId,
			serialNumber = serialNumber,
		})
	end
end

local function collectPreparedPlayerRelease(
	preparedPlayerRewards: PreparedPlayerRewards?,
	serialReservations: { any }
)
	if preparedPlayerRewards == nil or preparedPlayerRewards.released == true then
		return
	end

	for _, preparedReward in ipairs(preparedPlayerRewards.rewards) do
		collectPreparedRewardRelease(preparedReward, serialReservations)
	end

	preparedPlayerRewards.released = true
	if preparedPlayerRewards.committed ~= true then
		preparedPlayerRewards.status = "released"
	end
end

local function collectPreparedEncounterRelease(
	state: PreparedEncounterRewards?,
	serialReservations: { any }
)
	if state == nil then
		return
	end

	state.releaseRequested = true
	for _, preparedPlayerRewards in pairs(state.byUserId) do
		collectPreparedPlayerRelease(preparedPlayerRewards, serialReservations)
	end
	if state.status ~= "committed" then
		state.status = "released"
	end
end

local function failPreparedEncounter(state: PreparedEncounterRewards, message: string): (boolean, string)
	local serialReservations = {}
	collectPreparedEncounterRelease(state, serialReservations)
	state.status = "failed"
	state.error = message
	releaseSerialReservationsAsync(serialReservations, "failed boss reward preparation")
	return false, message
end

local function prepareBodyPartReward(
	entry: BodyPartRewardGrantEntry
): (PreparedBodyPartReward?, string?)
	local serialNumber, serialError = DataService:GetNextSerialForPiece(entry.pieceId)
	if not serialNumber then
		return nil, serialError or "Failed to allocate body part serial number."
	end

	return {
		kind = "bodyPart",
		grant = entry,
		payload = buildGrantPayload(entry),
		reservation = {
			pieceId = entry.pieceId,
			serialNumber = serialNumber,
		},
		committed = false,
		released = false,
	}, nil
end

local function prepareRewardsForPlayer(
	state: PreparedEncounterRewards,
	userId: number,
	profile: BossRewards.BossRewardProfile,
	floorPreset: BossRewards.LootFloorPreset,
	poolsByRarity: { [string]: { any } },
	randomSource: Random
): (PreparedPlayerRewards?, string?)
	local preparedPlayerRewards: PreparedPlayerRewards = {
		userId = userId,
		rewards = {},
		skippedCount = 0,
		status = "ready",
		error = nil,
		committed = false,
		released = false,
	}

	for _ = 1, math.max(0, math.floor(tonumber(profile.slotCount) or 0)) do
		if state.releaseRequested == true then
			local serialReservations = {}
			collectPreparedPlayerRelease(preparedPlayerRewards, serialReservations)
			releaseSerialReservationsAsync(serialReservations, "cancelled boss reward preparation")
			return nil, "Boss reward preparation was cancelled."
		end

		local rewardEntry = rollRewardEntry(randomSource, profile, floorPreset, poolsByRarity)
		if rewardEntry == nil then
			preparedPlayerRewards.skippedCount += 1
			continue
		end

		local preparedReward, prepareError = prepareBodyPartReward(rewardEntry)
		if preparedReward == nil then
			preparedPlayerRewards.status = "failed"
			preparedPlayerRewards.error = prepareError
			return preparedPlayerRewards, prepareError
		end

		if state.releaseRequested == true then
			local serialReservations = {}
			collectPreparedRewardRelease(preparedReward, serialReservations)
			releaseSerialReservationsAsync(serialReservations, "cancelled boss reward preparation")
			return nil, "Boss reward preparation was cancelled."
		end

		table.insert(preparedPlayerRewards.rewards, preparedReward)
	end

	for _, materialEntry in ipairs(rollMaterialRewardEntries(randomSource, profile.bossId)) do
		table.insert(preparedPlayerRewards.rewards, {
			kind = "material",
			grant = materialEntry,
			committed = false,
			released = false,
		})
	end

	return preparedPlayerRewards, nil
end

local function commitPreparedPlayerRewards(
	player: Player,
	bossId: string,
	preparedPlayerRewards: PreparedPlayerRewards
): RewardSummary
	local summary = buildRewardSummary(player, bossId)
	summary.skippedCount += preparedPlayerRewards.skippedCount

	local releaseSerials = {}
	local stopBodyPartGrants = false

	for _, preparedReward in ipairs(preparedPlayerRewards.rewards) do
		if preparedReward.kind ~= "bodyPart" then
			continue
		end
		if preparedReward.released == true then
			summary.skippedCount += 1
			continue
		end

		if stopBodyPartGrants then
			summary.skippedCount += 1
			collectPreparedRewardRelease(preparedReward, releaseSerials)
			continue
		end

		local grantedRecord, grantError = DataService:AddOwnedBodyPart(
			player,
			preparedReward.payload,
			preparedReward.reservation
		)
		if grantedRecord == nil then
			summary.skippedCount += 1
			summary.stoppedReason = if isInventoryFullError(grantError) then "inventory_full" else "grant_failed"
			collectPreparedRewardRelease(preparedReward, releaseSerials)
			stopBodyPartGrants = true
			if summary.stoppedReason ~= "inventory_full" then
				warnWithPrefix(string.format(
					"Failed to commit prepared boss reward to %s for boss '%s': %s",
					player.Name,
					bossId,
					tostring(grantError)
				))
			end
			continue
		end

		preparedReward.committed = true
		summary.grantedCount += 1
		table.insert(summary.grants, preparedReward.grant)
	end

	for _, preparedReward in ipairs(preparedPlayerRewards.rewards) do
		if preparedReward.kind ~= "material" then
			continue
		end
		if preparedReward.released == true then
			continue
		end

		local materialEntry = preparedReward.grant
		local _, grantError = DataService:AddCraftingMaterial(player, materialEntry.materialId, materialEntry.amount)
		if grantError then
			summary.skippedCount += 1
			warnWithPrefix(string.format(
				"Failed to grant prepared boss material reward to %s for boss '%s': %s",
				player.Name,
				bossId,
				tostring(grantError)
			))
			continue
		end

		preparedReward.committed = true
		summary.grantedCount += 1
		table.insert(summary.grants, materialEntry)
	end

	if #releaseSerials > 0 then
		releaseSerialReservationsAsync(releaseSerials, "uncommitted prepared boss rewards")
	end

	preparedPlayerRewards.committed = true
	preparedPlayerRewards.status = "committed"
	summary.message = buildSummaryMessage(summary)
	return summary
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

	for _, materialEntry in ipairs(rollMaterialRewardEntries(randomSource, bossId)) do
		local _, grantError = DataService:AddCraftingMaterial(player, materialEntry.materialId, materialEntry.amount)
		if grantError then
			summary.skippedCount += 1
			warnWithPrefix(string.format(
				"Failed to grant boss material reward to %s for boss '%s': %s",
				player.Name,
				bossId,
				tostring(grantError)
			))
			continue
		end

		summary.grantedCount += 1
		table.insert(summary.grants, materialEntry)
	end

	summary.message = buildSummaryMessage(summary)
	return summary
end

function BossArenaRewardService:GetPreparedRewardStatus(encounter: any): string
	local state = getPreparedRewardsState(encounter)
	if state == nil then
		return "none"
	end

	return tostring(state.status or "none")
end

function BossArenaRewardService:GetPreparedResultRewards(encounter: any): { [number]: { RewardGrantEntry } }
	local resultRewardsByUserId = {}
	local state = getPreparedRewardsState(encounter)
	if state == nil or state.status ~= "ready" then
		return resultRewardsByUserId
	end

	for userId, preparedPlayerRewards in pairs(state.byUserId) do
		if hasRewardEligibleDamage(encounter, userId) and getPlayerByUserId(userId) ~= nil then
			local entries = {}
			for _, preparedReward in ipairs(preparedPlayerRewards.rewards) do
				if preparedReward.released ~= true then
					table.insert(entries, preparedReward.grant)
				end
			end
			resultRewardsByUserId[userId] = entries
		end
	end

	return resultRewardsByUserId
end

function BossArenaRewardService:PrepareEncounterRewards(encounter: any): (boolean, string?)
	if typeof(encounter) ~= "table" then
		return false, "Encounter is required."
	end

	local existingState = getPreparedRewardsState(encounter)
	if existingState ~= nil then
		return existingState.status == "ready" or existingState.status == "committed", existingState.error
	end

	local bossId = encounter.bossId
	if typeof(bossId) ~= "string" or bossId == "" then
		return false, "Encounter bossId is required."
	end

	local state: PreparedEncounterRewards = {
		bossId = bossId,
		status = "pending",
		byUserId = {},
		releaseRequested = false,
		error = nil,
	}
	encounter.preparedBossRewards = state

	local profile = BossRewards.GetBossRewardProfile(bossId)
	if profile == nil then
		return failPreparedEncounter(state, string.format("No reward profile is configured for boss '%s'.", bossId))
	end

	local floorPreset = BossRewards.GetLootFloorPreset(profile.lootFloorId)
	if floorPreset == nil then
		return failPreparedEncounter(
			state,
			string.format("Boss '%s' references unknown reward floor '%s'.", bossId, tostring(profile.lootFloorId))
		)
	end

	local poolsByRarity = buildNormalRewardPoolsByRarity(profile)
	if next(poolsByRarity) == nil then
		warnWithPrefix(string.format("Boss '%s' reward pools are empty after filtering.", bossId))
	end

	local randomSource = Random.new()
	local seenUserIds = {}
	for _, rawUserId in ipairs(encounter.rosterOrder or {}) do
		local userId = math.floor(tonumber(rawUserId) or 0)
		if userId <= 0 or seenUserIds[userId] == true then
			continue
		end
		seenUserIds[userId] = true

		if state.releaseRequested == true then
			local serialReservations = {}
			collectPreparedEncounterRelease(state, serialReservations)
			releaseSerialReservationsAsync(serialReservations, "cancelled boss reward preparation")
			return false, "Boss reward preparation was cancelled."
		end

		local preparedPlayerRewards, prepareError = prepareRewardsForPlayer(
			state,
			userId,
			profile,
			floorPreset,
			poolsByRarity,
			randomSource
		)
		if preparedPlayerRewards ~= nil then
			state.byUserId[userId] = preparedPlayerRewards
		end
		if prepareError ~= nil then
			return failPreparedEncounter(state, prepareError)
		end
	end

	if state.releaseRequested == true then
		local serialReservations = {}
		collectPreparedEncounterRelease(state, serialReservations)
		releaseSerialReservationsAsync(serialReservations, "cancelled boss reward preparation")
		return false, "Boss reward preparation was cancelled."
	end

	state.status = "ready"
	return true, nil
end

function BossArenaRewardService:CommitPreparedRewards(encounter: any): { [number]: RewardSummary }
	local results = {}
	local state = getPreparedRewardsState(encounter)
	if state == nil or state.status ~= "ready" then
		return results
	end

	state.status = "committing"
	local processedUserIds = {}
	local bossId = state.bossId

	for _, rawUserId in ipairs(encounter.rosterOrder or {}) do
		local userId = math.floor(tonumber(rawUserId) or 0)
		if userId <= 0 or processedUserIds[userId] == true then
			continue
		end
		processedUserIds[userId] = true

		local preparedPlayerRewards = state.byUserId[userId]
		if preparedPlayerRewards == nil then
			continue
		end
		if preparedPlayerRewards.released == true then
			continue
		end

		local player = getPlayerByUserId(userId)
		if player == nil then
			local serialReservations = {}
			collectPreparedPlayerRelease(preparedPlayerRewards, serialReservations)
			releaseSerialReservationsAsync(serialReservations, "offline boss reward recipient")
			continue
		end

		if not hasRewardEligibleDamage(encounter, userId) then
			local summary = buildRewardSummary(player, bossId)
			summary.stoppedReason = "insufficient_damage"
			summary.message = buildSummaryMessage(summary)
			results[player.UserId] = summary

			local serialReservations = {}
			collectPreparedPlayerRelease(preparedPlayerRewards, serialReservations)
			releaseSerialReservationsAsync(serialReservations, "damage-ineligible boss reward recipient")
			Notify.Send(player, summary.message, {
				title = "Boss Rewards",
				channel = "inventory",
				tone = "neutral",
			})
			continue
		end

		local summary = commitPreparedPlayerRewards(player, bossId, preparedPlayerRewards)
		results[player.UserId] = summary

		if summary.message ~= "" then
			Notify.Send(player, summary.message, {
				title = "Boss Rewards",
				channel = "inventory",
				tone = "good",
			})
		end
	end

	for userId, preparedPlayerRewards in pairs(state.byUserId) do
		if processedUserIds[userId] ~= true and preparedPlayerRewards.committed ~= true then
			local serialReservations = {}
			collectPreparedPlayerRelease(preparedPlayerRewards, serialReservations)
			releaseSerialReservationsAsync(serialReservations, "unprocessed boss reward recipient")
		end
	end

	state.status = "committed"
	return results
end

function BossArenaRewardService:ReleasePreparedRewardsForUserId(encounter: any, userId: number, reason: string?)
	local state = getPreparedRewardsState(encounter)
	if state == nil then
		return
	end

	local resolvedUserId = math.floor(tonumber(userId) or 0)
	local preparedPlayerRewards = state.byUserId[resolvedUserId]
	if preparedPlayerRewards == nil then
		return
	end

	local serialReservations = {}
	collectPreparedPlayerRelease(preparedPlayerRewards, serialReservations)
	releaseSerialReservationsAsync(serialReservations, reason or "released prepared boss reward recipient")
end

function BossArenaRewardService:ReleasePreparedRewards(encounter: any, reason: string?)
	local state = getPreparedRewardsState(encounter)
	if state == nil then
		return
	end

	local serialReservations = {}
	collectPreparedEncounterRelease(state, serialReservations)
	releaseSerialReservationsAsync(serialReservations, reason or "released prepared boss rewards")
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
