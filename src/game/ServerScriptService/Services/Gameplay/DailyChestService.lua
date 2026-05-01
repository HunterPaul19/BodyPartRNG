local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local BossRewards = require(ReplicatedStorage.Shared.BossArena.BossRewards)
local DailyChestConfig = require(ReplicatedStorage.Shared.Config.DailyChestConfig)
local DailyChestState = require(ReplicatedStorage.Shared.Character.DailyChestState)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local NumberFormatter = require(ReplicatedStorage.Shared.Formatting.NumberFormatter)
local PotionConfig = require(ReplicatedStorage.Shared.Config.PotionConfig)
local RollMath = require(ReplicatedStorage.Shared.Rolling.RollMath)
local SizeConfig = require(ReplicatedStorage.Shared.Config.SizeConfig)
local DataService = require(script.Parent.DataService)
local PassiveIncomeService = require(script.Parent.PassiveIncomeService)
local PotionService = require(script.Parent.PotionService)

local CHESTS_REMOTE_FOLDER_NAME = "Chests"
local CLAIM_DAILY_CHESTS_REMOTE_NAME = "ClaimDailyChests"
local NORMAL_TIERED_POTION_FAMILIES = table.freeze({
	"money",
	"luck",
	"size",
	"rollSpeed",
})

type ChestPackage = {
	chestId: string,
	visualChestId: string,
	displayName: string,
	sourceBossId: string?,
	rewards: { any },
}

local DailyChestService = {}

local DEFAULT_MUTATION = MutationConfig.GetDefault()
local DEFAULT_SIZE = SizeConfig.GetDefault()
local DEFAULT_SIZE_SCALE = SizeConfig.GetRepresentativeScale(DEFAULT_SIZE.id)
local activeClaimsByPlayer: { [Player]: boolean } = {}
local potionIdsByTier: { [number]: { string } } = {}
local warnedMissingBossRewardPools: { [string]: boolean } = {}

type BodyPartRewardGrantEntry = {
	kind: "bodyPart",
	pieceId: string,
	displayName: string,
	setId: string,
	displayRarity: string,
	displayOddsDenominator: number,
	isBossPart: boolean,
}

local function createOrGetFolder(parent: Instance, name: string): Folder
	local folder = parent:FindFirstChild(name)
	if folder and folder:IsA("Folder") then
		return folder
	end

	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = parent
	return created
end

local function createOrGetRemoteFunction(parent: Instance, name: string): RemoteFunction
	local remote = parent:FindFirstChild(name)
	if remote and remote:IsA("RemoteFunction") then
		return remote
	end

	local created = Instance.new("RemoteFunction")
	created.Name = name
	created.Parent = parent
	return created
end

local function rollInteger(random: Random, range: { min: number, max: number }): number
	local minValue = math.floor(tonumber(range and range.min) or 0)
	local maxValue = math.floor(tonumber(range and range.max) or minValue)
	if maxValue < minValue then
		minValue, maxValue = maxValue, minValue
	end
	return random:NextInteger(minValue, maxValue)
end

local function chooseWeighted(random: Random, entries: { any }, valueKey: string): any?
	local totalWeight = 0
	for _, entry in ipairs(entries) do
		totalWeight += math.max(0, tonumber(entry.chance) or 0)
	end
	if totalWeight <= 0 then
		return nil
	end

	local roll = random:NextNumber(0, totalWeight)
	local running = 0
	for _, entry in ipairs(entries) do
		running += math.max(0, tonumber(entry.chance) or 0)
		if roll <= running then
			return entry[valueKey]
		end
	end

	local lastEntry = entries[#entries]
	return if lastEntry then lastEntry[valueKey] else nil
end

local function chooseRandom(random: Random, values: { any }): any?
	if #values <= 0 then
		return nil
	end
	return values[random:NextInteger(1, #values)]
end

local function buildPotionTierCache()
	local byTier = {}
	for _, familyId in ipairs(NORMAL_TIERED_POTION_FAMILIES) do
		for _, potionConfig in ipairs(PotionConfig.GetFamilyEntries(familyId)) do
			local tier = math.floor(tonumber(potionConfig.tier) or 0)
			if tier > 0 then
				local tierList = byTier[tier]
				if tierList == nil then
					tierList = {}
					byTier[tier] = tierList
				end
				table.insert(tierList, potionConfig.id)
			end
		end
	end
	potionIdsByTier = byTier
end

local function choosePotionIdForTier(random: Random, tier: number): string?
	local potionIds = potionIdsByTier[math.floor(tonumber(tier) or 0)] or {}
	return chooseRandom(random, potionIds)
end

local function getAllBossIds(): { string }
	local bossIds = {}
	for _, profile in ipairs(BossRewards.GetAllBossRewardProfiles()) do
		table.insert(bossIds, profile.bossId)
	end
	return bossIds
end

local function chooseBossIdForChest(random: Random, config: DailyChestConfig.ChestConfig): string?
	local bossPool = config.bossPool
	if typeof(bossPool) == "table" and #bossPool > 0 then
		return chooseRandom(random, bossPool)
	end

	return chooseRandom(random, getAllBossIds())
end

local function chooseMaterialDrop(
	random: Random,
	bossId: string,
	materialTier: BossRewards.MaterialDropTier
): BossRewards.BossMaterialDropEntry?
	local candidates = {}
	for _, drop in ipairs(BossRewards.GetBossMaterialDrops(bossId)) do
		if drop.dropTier == materialTier then
			table.insert(candidates, drop)
		end
	end
	return chooseRandom(random, candidates)
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

local function chooseRandomPieceFromSet(random: Random, setId: string): any?
	local pieces = BodyPartsCatalog.GetPiecesForSet(setId)
	if not pieces or #pieces <= 0 then
		return nil
	end

	return pieces[random:NextInteger(1, #pieces)]
end

local function chooseWeightedSetFromPool(random: Random, pool: { any }): any?
	return RollMath.ChooseWeighted(random, pool, function(entry)
		return math.max(0, tonumber(entry.baseChance) or 0)
	end)
end

local function rollRewardRarity(
	random: Random,
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

	local threshold = random:NextNumber() * totalProbability
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

local function warnMissingBossRewardPoolOnce(key: string, message: string)
	if warnedMissingBossRewardPools[key] == true then
		return
	end

	warnedMissingBossRewardPools[key] = true
	Logger.Warn(string.format("[DailyChestService] %s", message))
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

local function rollBossBodyPartRewardEntry(
	random: Random,
	profile: BossRewards.BossRewardProfile,
	floorPreset: BossRewards.LootFloorPreset,
	poolsByRarity: { [string]: { any } }
): BodyPartRewardGrantEntry?
	local bossPartChance = math.clamp(tonumber(profile.bossPartChance) or 0, 0, 1)
	if bossPartChance > 0 and random:NextNumber() < bossPartChance then
		local bossPiece = chooseRandomPieceFromSet(random, profile.bossSetId)
		return buildRewardEntryFromSetPiece(bossPiece, profile.bossSetId, true)
	end

	local selectedRarity = rollRewardRarity(random, floorPreset, poolsByRarity)
	if selectedRarity == nil then
		warnMissingBossRewardPoolOnce(
			string.format("%s:%s:no-eligible-rarity", profile.bossId, floorPreset.id),
			string.format(
				"Boss '%s' has no eligible chest body-part rarity pools for loot floor '%s' after filtering.",
				profile.bossId,
				floorPreset.id
			)
		)
		return nil
	end

	local rarityPool = poolsByRarity[selectedRarity]
	if rarityPool == nil or #rarityPool <= 0 then
		warnMissingBossRewardPoolOnce(
			string.format("%s:%s", profile.bossId, selectedRarity),
			string.format(
				"Boss '%s' rolled chest body-part rarity '%s', but no eligible reward sets remain after filtering.",
				profile.bossId,
				selectedRarity
			)
		)
		return nil
	end

	local weightedSet = chooseWeightedSetFromPool(random, rarityPool)
	if weightedSet == nil then
		return nil
	end

	local rewardPiece = chooseRandomPieceFromSet(random, weightedSet.id)
	return buildRewardEntryFromSetPiece(rewardPiece, weightedSet.id, false)
end

local function buildBodyPartGrantPayload(entry: BodyPartRewardGrantEntry): { [string]: any }
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

local function grantBossBodyPartReward(player: Player, random: Random, sourceBossId: string): any?
	local profile = BossRewards.GetBossRewardProfile(sourceBossId)
	if profile == nil then
		Logger.Warn(string.format(
			"[DailyChestService] No boss body-part reward profile is configured for boss '%s'.",
			tostring(sourceBossId)
		))
		return nil
	end

	local floorPreset = BossRewards.GetLootFloorPreset(profile.lootFloorId)
	if floorPreset == nil then
		Logger.Warn(string.format(
			"[DailyChestService] Boss '%s' references unknown chest body-part reward floor '%s'.",
			profile.bossId,
			tostring(profile.lootFloorId)
		))
		return nil
	end

	local poolsByRarity = buildNormalRewardPoolsByRarity(profile)
	if next(poolsByRarity) == nil then
		warnMissingBossRewardPoolOnce(
			string.format("%s:no-pools", profile.bossId),
			string.format("Boss '%s' chest body-part reward pools are empty after filtering.", profile.bossId)
		)
	end

	local rewardEntry = rollBossBodyPartRewardEntry(random, profile, floorPreset, poolsByRarity)
	if rewardEntry == nil then
		return nil
	end

	local grantedRecord, grantError = DataService:AddOwnedBodyPart(
		player,
		buildBodyPartGrantPayload(rewardEntry),
		{ ignoreInventoryLimit = true }
	)
	if grantedRecord == nil then
		Logger.Warn(string.format(
			"[DailyChestService] Failed to grant chest body-part reward '%s' to %s for boss '%s': %s",
			tostring(rewardEntry.pieceId),
			player.Name,
			profile.bossId,
			tostring(grantError)
		))
		return nil
	end

	return {
		kind = "bodyPart",
		record = grantedRecord,
		sourceBossId = sourceBossId,
		isBossPart = rewardEntry.isBossPart,
	}
end

local function buildMoneyDescriptor(amount: number, minutes: number): any
	return {
		kind = "money",
		displayName = "Money",
		amount = amount,
		minutes = minutes,
	}
end

local function grantChestRewards(
	player: Player,
	config: DailyChestConfig.ChestConfig,
	random: Random,
	sourcePrefix: string?
): ChestPackage
	local rewards = {}
	local chestSource = (sourcePrefix or "daily_chest_") .. config.id
	local sourceBossId = chooseBossIdForChest(random, config)

	local timeShardAmount = rollInteger(random, config.timeShardRange)
	if timeShardAmount > 0 then
		DataService:AdjustTimeShardsBalance(player, timeShardAmount, chestSource)
		table.insert(rewards, {
			kind = "timeShard",
			displayName = "Time Shards",
			amount = timeShardAmount,
			iconTexture = DailyChestConfig.TimeShardIconTexture,
		})
	end

	local incomeMinutes = rollInteger(random, config.incomeMinutesRange)
	local passiveIncomePerSecond = PassiveIncomeService:GetPassiveIncomePerSecond(player)
	local moneyAmount = math.max(0, math.floor(passiveIncomePerSecond * incomeMinutes * 60))
	if moneyAmount > 0 then
		DataService:AddMoney(player, moneyAmount, chestSource)
		table.insert(rewards, buildMoneyDescriptor(moneyAmount, incomeMinutes))
	end

	for _, potionChance in ipairs(config.potionChances) do
		local chance = math.clamp(tonumber(potionChance.chance) or 0, 0, 1)
		if chance >= 1 or random:NextNumber() <= chance then
			local potionId = choosePotionIdForTier(random, potionChance.tier)
			local potionConfig = if potionId then PotionConfig.Get(potionId) else nil
			if potionConfig then
				local ok, message = PotionService:GrantPotionUses(player, potionConfig.id, 1)
				if ok then
					table.insert(rewards, {
						kind = "potion",
						displayName = potionConfig.label,
						amount = 1,
						potionId = potionConfig.id,
						tier = potionConfig.tier,
					})
				else
					Logger.Warn(string.format(
						"[DailyChestService] Failed to grant potion '%s' to %s: %s",
						potionConfig.id,
						player.Name,
						tostring(message)
					))
				end
			end
		end
	end

	if sourceBossId then
		local bossDropSlotCount = math.max(0, math.floor(tonumber(config.materialSlotCount) or 0))

		if bossDropSlotCount > 0 then
			local materialTier = chooseWeighted(random, config.materialTierOdds, "tier")
			local drop = if materialTier then chooseMaterialDrop(random, sourceBossId, materialTier) else nil
			if drop then
				local materialAmount = random:NextInteger(drop.amountMin, drop.amountMax)
				local _, err = DataService:AddCraftingMaterial(player, drop.materialId, materialAmount)
				if err == nil then
					table.insert(rewards, {
						kind = "material",
						displayName = drop.materialId,
						amount = materialAmount,
						materialId = drop.materialId,
						materialTier = drop.dropTier,
						sourceBossId = sourceBossId,
					})
				else
					Logger.Warn(string.format(
						"[DailyChestService] Failed to grant material '%s' to %s: %s",
						drop.materialId,
						player.Name,
						tostring(err)
					))
				end
			end
		end

		for _ = 1, math.max(0, bossDropSlotCount - 1) do
			local bodyPartReward = grantBossBodyPartReward(player, random, sourceBossId)
			if bodyPartReward ~= nil then
				table.insert(rewards, bodyPartReward)
			end
		end
	end

	if #rewards == 0 then
		Logger.Warn(string.format("[DailyChestService] Chest '%s' produced no rewards for %s.", config.id, player.Name))
		table.insert(rewards, {
			kind = "money",
			displayName = "Money",
			amount = 0,
			cardUsageText = "$0",
		})
	end

	return {
		chestId = config.id,
		visualChestId = config.visualChestId,
		displayName = config.displayName,
		sourceBossId = sourceBossId,
		rewards = rewards,
	}
end

local function response(ok: boolean, message: string?, chests: { ChestPackage }?)
	return {
		ok = ok,
		message = message,
		chests = chests or {},
	}
end

function DailyChestService:_claimEligibleChests(player: Player, payload: any)
	if activeClaimsByPlayer[player] == true then
		return response(false, "A chest claim is already running.")
	end
	if not DataService:IsPlayerDataLoaded(player) then
		return response(false, "Player data is not loaded.")
	end
	local TutorialService = require(script.Parent.TutorialService)
	if TutorialService:IsTutorialIncomplete(player) then
		return response(true, "Daily chest is deferred until the tutorial is complete.", {})
	end

	activeClaimsByPlayer[player] = true
	local ok, result = pcall(function()
		local state = DataService:GetDailyChestState(player)
		if state.localUtcOffsetMinutes == nil then
			local submittedOffset = if typeof(payload) == "table" then payload.localUtcOffsetMinutes else nil
			state.localUtcOffsetMinutes = DailyChestState.NormalizeOffsetMinutes(submittedOffset)
			if state.localUtcOffsetMinutes == nil then
				return response(false, "A valid local UTC offset is required for first-time chest setup.")
			end
			DataService:SetDailyChestState(player, state)
		end

		local localDay = DailyChestState.GetLocalDay(os.time(), state.localUtcOffsetMinutes)
		local hasVip = DataService:GetVipOwned(player)
		local hasVipPlus = DataService:GetVipPlusOwned(player)
		local eligibleChestIds = DailyChestConfig.GetEligibleChestIds(hasVip, hasVipPlus)
		local random = Random.new()
		local packages = {}

		for _, chestId in ipairs(eligibleChestIds) do
			state = DataService:GetDailyChestState(player)
			if DailyChestState.IsClaimedForLocalDay(state, chestId, localDay) then
				continue
			end

			local config = DailyChestConfig.Get(chestId)
			if config == nil then
				Logger.Warn(string.format("[DailyChestService] Missing config for chest '%s'.", tostring(chestId)))
				continue
			end

			local package = grantChestRewards(player, config, random)
			state = DailyChestState.MarkClaimedForLocalDay(state, chestId, localDay)
			DataService:SetDailyChestState(player, state)
			table.insert(packages, package)
		end

		if #packages <= 0 then
			return response(true, "No daily chests are claimable right now.", packages)
		end

		return response(true, string.format("Claimed %s chest(s).", NumberFormatter.Format(#packages)), packages)
	end)

	activeClaimsByPlayer[player] = nil

	if not ok then
		Logger.Warn(string.format("[DailyChestService] Claim failed for %s: %s", player.Name, tostring(result)))
		return response(false, "Failed to claim daily chests.")
	end

	return result
end

function DailyChestService:GrantChestPackageForAdmin(player: Player, chestId: string): (boolean, string, ChestPackage?)
	if not DataService:IsPlayerDataLoaded(player) then
		return false, "Player data is not loaded.", nil
	end

	local config = DailyChestConfig.Get(chestId)
	if config == nil then
		return false, string.format("Unknown chest id '%s'.", tostring(chestId)), nil
	end

	local package = grantChestRewards(player, config, Random.new(), "admin_chest_")
	return true, string.format("Granted %s to %s.", config.displayName, player.Name), package
end

function DailyChestService:OnStart()
	buildPotionTierCache()

	local remotesFolder = createOrGetFolder(ReplicatedStorage, "Remotes")
	local chestsFolder = createOrGetFolder(remotesFolder, CHESTS_REMOTE_FOLDER_NAME)
	local claimRemote = createOrGetRemoteFunction(chestsFolder, CLAIM_DAILY_CHESTS_REMOTE_NAME)
	claimRemote.OnServerInvoke = function(player: Player, payload: any)
		return self:_claimEligibleChests(player, payload)
	end
end

function DailyChestService:OnPlayerRemoving(player: Player)
	activeClaimsByPlayer[player] = nil
end

return DailyChestService
