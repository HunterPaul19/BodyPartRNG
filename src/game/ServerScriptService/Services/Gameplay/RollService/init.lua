local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NumberFormatter = require(ReplicatedStorage.Shared.Formatting.NumberFormatter)
local RollTypes = require(ReplicatedStorage.Shared.Config.RollTypes)
local RollTargetRegions = require(ReplicatedStorage.Shared.Character.RollTargetRegions)
local BodyPartIcons = require(ReplicatedStorage.Shared.Config.BodyPartIcons)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local RollingConfig = require(ReplicatedStorage.Shared.Config.RollingConfig)
local SizeConfig = require(ReplicatedStorage.Shared.Config.SizeConfig)
local PerfStats = require(ReplicatedStorage.Shared.Diagnostics.PerfStats)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)
local RollMath = require(ReplicatedStorage.Shared.Rolling.RollMath)
local RollCutsceneConfig = require(ReplicatedStorage.Shared.UI.RollCutsceneConfig)
local OwnedBodyParts = require(ReplicatedStorage.Shared.Character.OwnedBodyParts)
local BodyPartEconomy = require(ReplicatedStorage.Shared.Character.BodyPartEconomy)
local BodyPartService = require(script.Parent.BodyPartService)
local ChatNotificationService = require(script.Parent.ChatNotificationService)
local CraftingService = require(script.Parent.CraftingService)
local DataService = require(script.Parent.DataService)
local PotionService = require(script.Parent.PotionService)
local PurchaseReceiptService = require(script.Parent.PurchaseReceiptService)
local RequestLimiter = require(script.Parent.Common.RequestLimiter)
local StatsService = require(script.Parent.StatsService)
local TutorialService = require(script.Parent.TutorialService)

local REMOTES_FOLDER_NAME = "Remotes"
local ROLLING_FOLDER_NAME = "Rolling"
local GET_STATE_REMOTE_NAME = "GetRollingState"
local SELECT_ROLL_TYPE_REMOTE_NAME = "SelectRollType"
local SELECT_ROLL_REGION_REMOTE_NAME = "SelectRollRegion"
local PERFORM_ROLL_REMOTE_NAME = "PerformRoll"
local TOGGLE_QUICK_ROLL_REMOTE_NAME = "ToggleQuickRoll"
local TOGGLE_AUTO_EQUIP_BEST_REMOTE_NAME = "ToggleAutoEquipBest"
local TOGGLE_AUTO_SELL_RARITY_REMOTE_NAME = "ToggleAutoSellRarity"
local TOGGLE_CUTSCENE_RARITY_REMOTE_NAME = "ToggleCutsceneRarity"
local FINALIZE_AUTO_SELL_ROLL_REMOTE_NAME = "FinalizeAutoSellRoll"
local PROMPT_QUICK_ROLL_PURCHASE_REMOTE_NAME = "PromptQuickRollPurchase"
local UPDATED_REMOTE_NAME = "RollingUpdated"
local BASE_ROLL_COOLDOWN = 1
local ROLLING_FEATURE_ID = "rolling"
local SIZE_LUCK_SOURCE_IDS = { "tiny", "small", "normal" }
local SIZE_LUCK_TARGET_IDS = { "large", "huge", "titanic" }

local remotesFolder: Folder? = nil
local rollingRemotesFolder: Folder? = nil
local getStateRemote: RemoteFunction? = nil
local selectRollTypeRemote: RemoteFunction? = nil
local selectRollRegionRemote: RemoteFunction? = nil
local performRollRemote: RemoteFunction? = nil
local toggleQuickRollRemote: RemoteFunction? = nil
local toggleAutoEquipBestRemote: RemoteFunction? = nil
local toggleAutoSellRarityRemote: RemoteFunction? = nil
local toggleCutsceneRarityRemote: RemoteFunction? = nil
local finalizeAutoSellRollRemote: RemoteFunction? = nil
local promptQuickRollPurchaseRemote: RemoteFunction? = nil
local updatedRemote: RemoteEvent? = nil
local rollLocks: { [Player]: boolean } = {}
local rollCooldownUntilByPlayer: { [Player]: number } = {}
local pendingAutoSellByPlayer: { [Player]: { [string]: any } } = {}
local nextPendingAutoSellToken = 0
local adminLuckOverridesByPlayer: { [Player]: number } = {}
local loadoutChangedConnection = nil
local potionStateChangedConnection = nil

local RollService = {}

local function isRollingEnabled(): boolean
	local activeProfile = PlaceProfile.GetActiveProfile()
	if activeProfile.id ~= "unknown" then
		return true
	end

	return PlaceProfile.IsFeatureEnabled(ROLLING_FEATURE_ID)
end

local function getRollingUnavailableMessage(): string
	return PlaceProfile.GetFeatureUnavailableMessage(ROLLING_FEATURE_ID)
end

local function buildUnavailableRollingState(message: string?): { [string]: any }
	return {
		unavailable = true,
		featureId = ROLLING_FEATURE_ID,
		placeProfileId = PlaceProfile.GetActiveProfile().id,
		rollTypes = {},
		rollRegions = {},
		quickRoll = {
			owned = false,
			enabled = false,
		},
		autoEquipBest = {
			enabled = false,
		},
		autoSellRarities = RollingConfig.CreateDefaultAutoSellState(),
		cutsceneRarities = RollingConfig.CreateDefaultCutsceneState(),
		message = message or getRollingUnavailableMessage(),
	}
end

local function destroyRollingRemotes()
	local existingRemotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if existingRemotesFolder and existingRemotesFolder:IsA("Folder") then
		local existingRollingFolder = existingRemotesFolder:FindFirstChild(ROLLING_FOLDER_NAME)
		if existingRollingFolder then
			existingRollingFolder:Destroy()
		end
	end

	rollingRemotesFolder = nil
	getStateRemote = nil
	selectRollTypeRemote = nil
	selectRollRegionRemote = nil
	performRollRemote = nil
	toggleQuickRollRemote = nil
	toggleAutoEquipBestRemote = nil
	toggleAutoSellRarityRemote = nil
	toggleCutsceneRarityRemote = nil
	finalizeAutoSellRollRemote = nil
	promptQuickRollPurchaseRemote = nil
	updatedRemote = nil
end

local function formatWholeNumber(value: any): string
	return NumberFormatter.Format(math.max(0, math.floor(tonumber(value) or 0)))
end

local function formatMoney(value: any): string
	return "$" .. NumberFormatter.Format(math.max(0, math.round(tonumber(value) or 0)))
end

local function getQuickRollPassConfig()
	return PurchaseReceiptService:GetOffer("quick_roll")
end

local function response(ok: boolean, message: string, state: any?, rollResult: any?)
	return {
		ok = ok,
		message = message,
		state = state,
		rollResult = rollResult,
	}
end

local function buildRateLimitResponse(message: string, state: any?)
	return response(false, message, state)
end

local function markDeltaState(state: { [string]: any })
	state._isDelta = true
	return state
end

local function ensureRemotesFolder(): Folder
	if remotesFolder and remotesFolder.Parent == ReplicatedStorage then
		return remotesFolder
	end

	local existing = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		remotesFolder = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = REMOTES_FOLDER_NAME
	folder.Parent = ReplicatedStorage
	remotesFolder = folder
	return folder
end

local function ensureRollingRemotesFolder(): Folder
	local rootFolder = ensureRemotesFolder()
	if rollingRemotesFolder and rollingRemotesFolder.Parent == rootFolder then
		return rollingRemotesFolder
	end

	local existing = rootFolder:FindFirstChild(ROLLING_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		rollingRemotesFolder = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = ROLLING_FOLDER_NAME
	folder.Parent = rootFolder
	rollingRemotesFolder = folder
	return folder
end

local function ensureRemoteFunction(cachedRemote: RemoteFunction?, remoteName: string): RemoteFunction
	local folder = ensureRollingRemotesFolder()
	if cachedRemote and cachedRemote.Parent == folder then
		return cachedRemote
	end

	local existing = folder:FindFirstChild(remoteName)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = remoteName
	remote.Parent = folder
	return remote
end

local function ensureUpdatedRemote(): RemoteEvent
	local folder = ensureRollingRemotesFolder()
	if updatedRemote and updatedRemote.Parent == folder then
		return updatedRemote
	end

	local existing = folder:FindFirstChild(UPDATED_REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		updatedRemote = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = UPDATED_REMOTE_NAME
	remote.Parent = folder
	updatedRemote = remote
	return remote
end

local function buildRollTypeState(player: Player)
	local selectedRollTypeId = DataService:GetSelectedRollType(player)
	local rollTypeEntries = {}

	for _, rollType in ipairs(RollTypes.GetOrdered()) do
		table.insert(rollTypeEntries, {
			id = rollType.id,
			displayName = rollType.displayName,
			moneyCost = rollType.moneyCost,
			luckMultiplier = rollType.luckMultiplier,
			bandLuckScalar = math.max(0, tonumber(rollType.bandLuckScalar) or 1),
			uiOrder = rollType.uiOrder,
			selected = selectedRollTypeId == rollType.id,
		})
	end

	return rollTypeEntries, selectedRollTypeId
end

local function buildRollRegionState(player: Player)
	local selectedRollRegion = DataService:GetSelectedRollRegion(player)
	local rollRegionEntries = {}

	for index, region in ipairs(RollTargetRegions.Order) do
		local iconEntry = BodyPartIcons[region]
		table.insert(rollRegionEntries, {
			id = region,
			displayName = iconEntry and iconEntry.buttonName or region,
			image = iconEntry and iconEntry.image or "",
			uiOrder = index,
			selected = selectedRollRegion == region,
		})
	end

	local selectedIcon = BodyPartIcons[selectedRollRegion]

	return rollRegionEntries, selectedRollRegion, (selectedIcon and selectedIcon.image or "")
end

local function buildQuickRollState(player: Player)
	local passConfig = getQuickRollPassConfig()
	local owned = false
	local enabled = false

	if passConfig and passConfig.offerKey then
		owned = PurchaseReceiptService:HasEntitlement(player, passConfig.offerKey)
		enabled = owned and DataService:GetQuickRollEnabled(player)
	end

	return {
		owned = owned,
		enabled = enabled,
		passId = passConfig and passConfig.selfPurchase and passConfig.selfPurchase.robloxId or nil,
	}
end

local function buildAutoEquipBestState(player: Player)
	return {
		enabled = DataService:GetAutoEquipBestEnabled(player),
	}
end

local function buildAutoSellState(player: Player)
	return DataService:GetAutoSellRarities(player)
end

local function buildCutsceneState(player: Player)
	return DataService:GetCutsceneRarities(player)
end

local function getEffectiveBonuses(player: Player)
	local loadoutBonuses = BodyPartService:GetComputedLoadoutBonuses(player)
	local potionBonuses = PotionService:GetRuntimeBonuses(player)

	return {
		passiveIncomePerSecond = tonumber(loadoutBonuses.passiveIncomePerSecond) or 0,
		luckBonus = (tonumber(loadoutBonuses.luckBonus) or 0) + (tonumber(potionBonuses.luckBonus) or 0),
		luckMultiplier = math.max(1, tonumber(loadoutBonuses.luckMultiplier) or 1)
			* math.max(1, tonumber(potionBonuses.luckMultiplier) or 1),
		rollSpeedBonus = (tonumber(loadoutBonuses.rollSpeedBonus) or 0) + (tonumber(potionBonuses.rollSpeedBonus) or 0),
		activeSetId = loadoutBonuses.activeSetId,
	}, potionBonuses, loadoutBonuses
end

local function getEffectiveRollCooldown(player: Player, bonuses: any, quickRollState: any?): number
	local totalRollSpeedBonus = math.max(0, tonumber(bonuses and bonuses.rollSpeedBonus) or 0)
	local cooldownDuration = BASE_ROLL_COOLDOWN / math.max(1, 1 + totalRollSpeedBonus)
	local resolvedQuickRollState = if typeof(quickRollState) == "table" then quickRollState else buildQuickRollState(player)
	if resolvedQuickRollState.enabled == true then
		cooldownDuration *= 0.5
	end
	return cooldownDuration
end

local function getPendingAutoSellState(player: Player): { [string]: any }
	local pendingState = pendingAutoSellByPlayer[player]
	if pendingState then
		return pendingState
	end

	pendingState = {}
	pendingAutoSellByPlayer[player] = pendingState
	return pendingState
end

local function createPendingAutoSellToken(player: Player): string
	nextPendingAutoSellToken += 1
	return string.format("%d_%d_%d", player.UserId, math.floor(os.clock() * 1000), nextPendingAutoSellToken)
end

local function clearPendingAutoSell(player: Player, pendingKey: string)
	local pendingState = pendingAutoSellByPlayer[player]
	if not pendingState then
		return
	end

	pendingState[pendingKey] = nil
	if next(pendingState) == nil then
		pendingAutoSellByPlayer[player] = nil
	end
end

local function cloneRollGrantPayload(payload: any): any
	if typeof(payload) ~= "table" then
		return nil
	end

	return table.clone(payload)
end

local function sellReservedBodyPartRecord(player: Player, ownedRecord: any): (boolean, string)
	if typeof(ownedRecord) ~= "table" then
		return false, "No rolled body part was available to sell."
	end

	local piece = BodyPartsCatalog.GetPiece(ownedRecord.pieceId)
	local pieceName = if piece then piece.displayName else "body part"
	local payout = BodyPartEconomy.GetSellValue(ownedRecord, piece)
	DataService:AddMoney(player, payout, "sell_single")
	StatsService:RecordBodyPartsSold(player, 1)
	StatsService:RecordTransientBodyPartAcquired(player)

	return true, string.format("Sold %s for $%s.", pieceName, tostring(payout))
end

local function isOwnedIdEquipped(player: Player, ownedId: string): boolean
	local equippedState = BodyPartService:GetSessionLoadout(player)

	for _, entry in pairs(equippedState) do
		if typeof(entry) == "table" and entry.ownedId == ownedId then
			return true
		end
	end

	return false
end

local function computeLuckState(player: Player, rollTypeConfig, successfulRollCount: number, suppressAdminOverride: boolean?)
	local bonuses, potionBonuses, loadoutBonuses = getEffectiveBonuses(player)
	local equippedLuckBonus = math.max(0, tonumber(loadoutBonuses and loadoutBonuses.luckBonus) or 0)
	local rollsSinceBonusRoll = RollMath.GetBonusChargeProgress(successfulRollCount, RollingConfig.BonusInterval)
	local useBonusRoll = RollMath.IsBonusRoll(successfulRollCount, RollingConfig.BonusInterval)
	local luckBoostReady = RollMath.IsBonusReady(successfulRollCount, RollingConfig.BonusInterval)
	local isVipOwned = DataService:GetVipOwned(player)
	local machineLuck = math.max(1, tonumber(rollTypeConfig.luckMultiplier) or 1)
	local equippedLuckMultiplier = math.max(1, 1 + equippedLuckBonus)
	local basicLuckBonus = math.max(0, machineLuck + equippedLuckBonus)
	local baseLuck = 1 + basicLuckBonus
	local bonusRollMultiplier = if useBonusRoll then RollingConfig.BonusMultiplier else 1
	local specialLuckBonus = math.max(0, tonumber(potionBonuses and potionBonuses.luckBonus) or 0)
	local loadoutLuckMultiplier = math.max(1, tonumber(loadoutBonuses and loadoutBonuses.luckMultiplier) or 1)
	local potionLuckMultiplier = math.max(1, tonumber(potionBonuses and potionBonuses.luckMultiplier) or 1)
	local vipMultiplier = if isVipOwned then RollingConfig.VipMultiplier else 1
	local bonusLuck = (baseLuck * bonusRollMultiplier) + specialLuckBonus
	local potionLuck = bonusLuck * loadoutLuckMultiplier * potionLuckMultiplier
	local vipLuck = potionLuck * vipMultiplier
	local rawLuck = vipLuck
	local bandLuckScalar = math.max(0, tonumber(rollTypeConfig and rollTypeConfig.bandLuckScalar) or 1)
	local adminOverrideLuck = adminLuckOverridesByPlayer[player]
	local hasAdminOverride = suppressAdminOverride ~= true and adminOverrideLuck ~= nil
	if hasAdminOverride then
		rawLuck = math.max(0, tonumber(adminOverrideLuck) or 0)
	end
	local bandLuckInput = rawLuck * bandLuckScalar

	return {
		machineLuck = machineLuck,
		basicLuckBonus = basicLuckBonus,
		baseLuck = baseLuck,
		bonusRollMultiplier = bonusRollMultiplier,
		specialLuckBonus = specialLuckBonus,
		loadoutLuckMultiplier = loadoutLuckMultiplier,
		potionLuckMultiplier = potionLuckMultiplier,
		potionLuck = potionLuck,
		vipMultiplier = vipMultiplier,
		bonusLuck = bonusLuck,
		vipLuck = vipLuck,
		equippedLuckMultiplier = equippedLuckMultiplier * loadoutLuckMultiplier,
		rawLuck = rawLuck,
		hasAdminLuckOverride = hasAdminOverride,
		adminOverrideLuck = adminOverrideLuck,
		bandLuckScalar = bandLuckScalar,
		bandLuckInput = bandLuckInput,
		useBonusRoll = useBonusRoll,
		luckBoostReady = luckBoostReady,
		isVipOwned = isVipOwned,
		successfulRollCount = successfulRollCount,
		nextRollNumber = successfulRollCount + 1,
		rollsSinceBonusRoll = rollsSinceBonusRoll,
		potionLuckBonus = specialLuckBonus,
	}, bonuses, potionBonuses
end

local function buildBandLuckSummary(finalLuck: number): { [string]: any }
	local summary = {
		finalLuck = tonumber(finalLuck) or 0,
		rarityBands = {},
	}

	for _, rarity in ipairs(RollingConfig.DisplayRarityOrder) do
		local displayRarity, bandMultiplier = RollingConfig.GetDisplayRarityBandMultiplier(rarity)
		summary.rarityBands[displayRarity] = {
			displayRarity = displayRarity,
			bandMultiplier = bandMultiplier,
			bandLuck = 1 + (summary.finalLuck * bandMultiplier),
		}
	end

	return summary
end

local function buildBandLuckInput(rawLuck: number, rollTypeConfig): number
	local resolvedRawLuck = math.max(0, tonumber(rawLuck) or 0)
	local bandLuckScalar = math.max(0, tonumber(rollTypeConfig and rollTypeConfig.bandLuckScalar) or 1)
	return resolvedRawLuck * bandLuckScalar
end

local function buildRollListEntries(finalLuck: number)
	local rollEntries = BodyPartsCatalog.GetRollEntries()
	local allEntries = table.create(#rollEntries)
	local resolvedFinalLuck = math.max(0, tonumber(finalLuck) or 0)

	for index = #rollEntries, 1, -1 do
		local rollEntry = rollEntries[index]
		local baseValue = rollEntry.displayedDenominator
		local displayRarity, bandMultiplier =
			RollingConfig.GetDisplayRarityBandMultiplier(rollEntry.rollDisplay.rarity)
		local bandLuck = 1 + (resolvedFinalLuck * bandMultiplier)
		local listValue = RollMath.GetListValue(baseValue, bandLuck)
		table.insert(allEntries, {
			setId = rollEntry.id,
			setConfig = rollEntry,
			baseValue = baseValue,
			displayedDenominator = baseValue,
			baseChance = rollEntry.baseChance,
			displayRarity = displayRarity,
			bandMultiplier = bandMultiplier,
			bandLuck = bandLuck,
			listValue = listValue,
			isPruned = listValue <= 1,
			rollSuccessChance = 0,
			probability = 0,
		})
	end

	local activeEntries = {}
	for _, entry in ipairs(allEntries) do
		if entry.isPruned ~= true then
			table.insert(activeEntries, entry)
		end
	end

	local remainingProbability = 1
	local lastIndex = #activeEntries
	for index, entry in ipairs(activeEntries) do
		entry.rollSuccessChance = 1 / entry.listValue
		entry.activeOrder = index
		if index == lastIndex then
			entry.probability = remainingProbability
		else
			entry.probability = remainingProbability * entry.rollSuccessChance
			remainingProbability *= 1 - entry.rollSuccessChance
		end
	end

	return allEntries, activeEntries, buildBandLuckSummary(resolvedFinalLuck)
end

local function chooseWeightedSet(randomSource: Random, activeEntries)
	local lastIndex = #activeEntries
	if lastIndex == 0 then
		return nil
	end

	for index, entry in ipairs(activeEntries) do
		if index == lastIndex then
			return entry
		end
		if RollMath.RollDenominator(randomSource, entry.listValue) then
			return entry
		end
	end

	return activeEntries[lastIndex]
end

local function findRollEntryBySetId(entries, setId: string)
	if typeof(setId) ~= "string" or setId == "" then
		return nil
	end

	for _, entry in ipairs(entries) do
		if entry.setId == setId then
			return entry
		end
	end

	return nil
end

local function findRollEntryForPiece(entries, piece)
	if typeof(piece) ~= "table" or typeof(piece.setId) ~= "string" then
		return nil
	end

	return findRollEntryBySetId(entries, piece.setId)
end

local function choosePieceFromSet(randomSource: Random, setId: string)
	local pieces = BodyPartsCatalog.GetPiecesForSet(setId)
	if not pieces or #pieces == 0 then
		return nil
	end

	return pieces[randomSource:NextInteger(1, #pieces)]
end

local function choosePieceFromSetForRegion(randomSource: Random, setId: string, rollRegion: string)
	if rollRegion == RollTargetRegions.FullBody then
		return choosePieceFromSet(randomSource, setId)
	end

	local pieces = BodyPartsCatalog.GetPiecesForSet(setId)
	if not pieces or #pieces == 0 then
		return nil
	end

	for _, piece in ipairs(pieces) do
		if piece.region == rollRegion then
			return piece
		end
	end

	return nil
end

local function resolveCutscenePlayback(player: Player, setId: string, displayRarity: string): (boolean, number)
	local normalizedRarity = RollCutsceneConfig.NormalizeDisplayRarity(displayRarity)
	local cutsceneTier = RollCutsceneConfig.ResolveTier(normalizedRarity)
	local hasSeenCutscene = DataService:HasSeenBundleCutscene(player, setId)
	local shouldPlayCutscene = RollCutsceneConfig.ShouldPlayForSet(normalizedRarity, setId, hasSeenCutscene)
	local isAlwaysPlaySet = RollCutsceneConfig.IsAlwaysPlaySetId(setId)
	local cutsceneEnabledForRarity = DataService:IsCutsceneEnabledForRarity(player, normalizedRarity)

	if not shouldPlayCutscene then
		return false, cutsceneTier
	end

	if not cutsceneEnabledForRarity then
		if not isAlwaysPlaySet then
			local didMarkSeen = DataService:MarkBundleCutsceneSeen(player, setId)
			if not didMarkSeen then
				Logger.Warn(string.format("[RollService] Failed to persist seen cutscene state for %s on set %s.", player.Name, setId))
			end
		end

		return false, cutsceneTier
	end

	if not isAlwaysPlaySet then
		local didMarkSeen = DataService:MarkBundleCutsceneSeen(player, setId)
		if not didMarkSeen then
			Logger.Warn(string.format("[RollService] Failed to persist seen cutscene state for %s on set %s.", player.Name, setId))
		end
	end

	return shouldPlayCutscene, cutsceneTier
end

local function chooseVariantEntry(randomSource: Random, orderedEntries)
	return RollMath.ChooseWeighted(randomSource, orderedEntries, function(entry)
		return entry.weight
	end)
end

local function getAdjustedMutationEntries(mutationChanceBonusById: any)
	if typeof(mutationChanceBonusById) ~= "table" or next(mutationChanceBonusById) == nil then
		return MutationConfig.GetOrdered()
	end

	return RollMath.ApplyFlatWeightBonuses(
		MutationConfig.GetOrdered(),
		mutationChanceBonusById,
		MutationConfig.GetDefault().id
	)
end

local function getAdjustedSizeEntries(sizeLuckBonus: any)
	local resolvedSizeLuckBonus = math.max(0, tonumber(sizeLuckBonus) or 0)
	if resolvedSizeLuckBonus <= 0 then
		return SizeConfig.GetOrdered()
	end

	return RollMath.ApplyDirectionalWeightShift(
		SizeConfig.GetOrdered(),
		SIZE_LUCK_SOURCE_IDS,
		SIZE_LUCK_TARGET_IDS,
		resolvedSizeLuckBonus
	)
end

local function rollMutation(randomSource: Random, mutationChanceBonusById: any)
	return chooseVariantEntry(randomSource, getAdjustedMutationEntries(mutationChanceBonusById)) or MutationConfig.GetDefault()
end

local function rollSize(randomSource: Random, sizeLuckBonus: any)
	local sizeData = chooseVariantEntry(randomSource, getAdjustedSizeEntries(sizeLuckBonus)) or SizeConfig.GetDefault()
	return sizeData, SizeConfig.RollScale(randomSource, sizeData)
end

local function createRollDisplayEntry(piece, resultData): (any?, string?)
	local setConfig = BodyPartsCatalog.GetSetForPiece(piece.id)
	if not setConfig then
		return nil, string.format("Missing set config for piece '%s'.", piece.id)
	end

	local rollDisplay = setConfig.rollDisplay
	local mutationData = resultData and resultData.mutationData or MutationConfig.GetDefault()
	local sizeData = resultData and resultData.sizeData or SizeConfig.GetDefault()
	local sizeScale = tonumber(resultData and resultData.sizeScale) or SizeConfig.GetRepresentativeScale(sizeData.id)
	local sizeMoneyMultiplier = tonumber(resultData and resultData.sizeMoneyMultiplier) or SizeConfig.GetMoneyMultiplier(sizeData.id)
	local finalPassiveIncomePerSecond = tonumber(resultData and resultData.finalPassiveIncomePerSecond) or piece.passiveIncomePerSecond

	return {
		Name = rollDisplay.displayName,
		BodyPart = piece.displayName,
		Region = piece.region,
		Chance = rollDisplay.chance,
		CashPerSec = finalPassiveIncomePerSecond,
		FinalCashPerSec = finalPassiveIncomePerSecond,
		Color = rollDisplay.color,
		Font = rollDisplay.fontFace,
		Weight = rollDisplay.fontWeight,
		Rarity = rollDisplay.rarity,
		PieceId = piece.id,
		PieceDisplayName = piece.displayName,
		SetId = setConfig.id,
		SetDisplayName = setConfig.displayName,
		DisplayOddsDenominator = rollDisplay.chance,
		SetBonusPassiveIncomePerSecond = setConfig.fullSetBonus.passiveIncomePerSecond,
		Mutation = mutationData.displayName,
		MutationId = mutationData.id,
		MutationMultiplier = mutationData.multiplier,
		Size = sizeData.displayName,
		SizeId = sizeData.id,
		SizeMultiplier = sizeScale,
		SizeMoneyMultiplier = sizeMoneyMultiplier,
		VariantMultiplier = tonumber(resultData and resultData.variantMultiplier) or 1,
		EffectiveRawLuck = tonumber(resultData and resultData.rawLuck) or nil,
		IsBonusRoll = resultData and resultData.useBonusRoll == true or false,
	}, nil
end

local function summarizeProbabilityTable(entries)
	local lines = {}
	local prunedCount = 0
	local previewCount = 0

	for _, entry in ipairs(entries) do
		if entry.isPruned == true then
			prunedCount += 1
		elseif previewCount < 5 then
			previewCount += 1
			local rollDisplay = entry.setConfig.rollDisplay
			table.insert(
				lines,
				string.format(
					"%s | 1/%s base | list %s | %.4f%% active",
					rollDisplay.displayName,
					formatWholeNumber(entry.baseValue),
					formatWholeNumber(entry.listValue),
					(entry.probability or 0) * 100
				)
			)
		end
	end

	if #lines == 0 then
		return string.format("No active sets remain after list pruning. %s pruned.", formatWholeNumber(prunedCount))
	end

	if prunedCount > 0 then
		table.insert(lines, string.format("%s pruned", formatWholeNumber(prunedCount)))
	end

	return table.concat(lines, " | ")
end

local function buildRarityShareSummary(activeEntries)
	local rarityShares = {}
	local byRarity = {}

	for _, rarity in ipairs(RollingConfig.DisplayRarityOrder) do
		local shareEntry = {
			displayRarity = rarity,
			probability = 0,
			entryCount = 0,
		}
		rarityShares[#rarityShares + 1] = shareEntry
		byRarity[rarity] = shareEntry
	end

	for _, entry in ipairs(activeEntries) do
		local displayRarity = entry.displayRarity or RollingConfig.NormalizeDisplayRarity(entry.setConfig.rollDisplay.rarity)
		local shareEntry = byRarity[displayRarity]
		if shareEntry then
			shareEntry.probability += tonumber(entry.probability) or 0
			shareEntry.entryCount += 1
		end
	end

	return rarityShares
end

local function formatRarityShareSummary(rarityShares): string
	local lines = {}

	for _, shareEntry in ipairs(rarityShares) do
		if shareEntry.entryCount > 0 or shareEntry.probability > 0 then
			lines[#lines + 1] = string.format(
				"%s %.4f%% (%s entries)",
				shareEntry.displayRarity,
				(tonumber(shareEntry.probability) or 0) * 100,
				formatWholeNumber(shareEntry.entryCount)
			)
		end
	end

	return table.concat(lines, " | ")
end

local function formatBandLuckSummary(bandLuckSummary): string
	local lines = {}
	local finalLuck = tonumber(bandLuckSummary and bandLuckSummary.finalLuck) or 0
	lines[#lines + 1] = string.format("Final luck %.2f", finalLuck)

	for _, rarity in ipairs(RollingConfig.DisplayRarityOrder) do
		local rarityBand = bandLuckSummary
			and typeof(bandLuckSummary.rarityBands) == "table"
			and bandLuckSummary.rarityBands[rarity]
		if rarityBand then
			lines[#lines + 1] = string.format(
				"%s x%.2f -> %.2f",
				rarity,
				tonumber(rarityBand.bandMultiplier) or 0,
				tonumber(rarityBand.bandLuck) or 0
			)
		end
	end

	return table.concat(lines, " | ")
end

function RollService:GetProbabilityDebug(player: Player, options: any?)
	if not isRollingEnabled() then
		local message = getRollingUnavailableMessage()
		return {
			unavailable = true,
			featureId = ROLLING_FEATURE_ID,
			placeProfileId = PlaceProfile.GetActiveProfile().id,
			summary = message,
			message = message,
			entries = {},
			rarityShares = {},
		}
	end

	local selectedRollTypeId = if typeof(options) == "table" and typeof(options.rollTypeId) == "string" then options.rollTypeId else DataService:GetSelectedRollType(player)
	local rollType = RollTypes.Get(selectedRollTypeId) or RollTypes.GetDefault()
	local successfulRollCount = DataService:GetSuccessfulRollCount(player)
	local luckState, bonuses = computeLuckState(player, rollType, successfulRollCount)

	if typeof(options) == "table" then
		if options.forceBonusRoll == true then
			luckState.useBonusRoll = true
			luckState.bonusRollMultiplier = RollingConfig.BonusMultiplier
			luckState.bonusLuck = (luckState.baseLuck * luckState.bonusRollMultiplier) + luckState.specialLuckBonus
			luckState.potionLuck =
				luckState.bonusLuck * luckState.loadoutLuckMultiplier * luckState.potionLuckMultiplier
			luckState.vipLuck = luckState.potionLuck * luckState.vipMultiplier
			luckState.rawLuck = luckState.vipLuck
			luckState.bandLuckInput = buildBandLuckInput(luckState.rawLuck, rollType)
		end
		if options.forceVipOwned ~= nil then
			luckState.isVipOwned = options.forceVipOwned == true
			luckState.vipMultiplier = if luckState.isVipOwned then RollingConfig.VipMultiplier else 1
			luckState.potionLuck =
				luckState.bonusLuck * luckState.loadoutLuckMultiplier * luckState.potionLuckMultiplier
			luckState.vipLuck = luckState.potionLuck * luckState.vipMultiplier
			luckState.rawLuck = luckState.vipLuck
			luckState.bandLuckInput = buildBandLuckInput(luckState.rawLuck, rollType)
		end
		if tonumber(options.totalLuck) ~= nil then
			luckState.rawLuck = math.max(0, tonumber(options.totalLuck) or 0)
			luckState.hasAdminLuckOverride = true
			luckState.adminOverrideLuck = luckState.rawLuck
			luckState.bandLuckInput = buildBandLuckInput(luckState.rawLuck, rollType)
		end
	end

	local entries, activeEntries, bandLuckSummary = buildRollListEntries(luckState.bandLuckInput)
	local rarityShares = buildRarityShareSummary(activeEntries)

	return {
		rollTypeId = rollType.id,
		rollTypeDisplayName = rollType.displayName,
		rawLuck = luckState.rawLuck,
		machineLuck = luckState.machineLuck,
		baseLuck = luckState.baseLuck,
		basicLuckBonus = luckState.basicLuckBonus,
		specialLuckBonus = luckState.specialLuckBonus,
		potionLuckBonus = luckState.potionLuckBonus,
		loadoutLuckMultiplier = luckState.loadoutLuckMultiplier,
		potionLuckMultiplier = luckState.potionLuckMultiplier,
		potionLuck = luckState.potionLuck,
		bonusLuck = luckState.bonusLuck,
		vipLuck = luckState.vipLuck,
		equippedLuckMultiplier = luckState.equippedLuckMultiplier,
		useBonusRoll = luckState.useBonusRoll,
		isVipOwned = luckState.isVipOwned,
		bonusInterval = RollingConfig.BonusInterval,
		bonusMultiplier = RollingConfig.BonusMultiplier,
		vipMultiplier = RollingConfig.VipMultiplier,
		bonuses = bonuses,
		finalLuck = luckState.rawLuck,
		bandLuckScalar = luckState.bandLuckScalar,
		bandLuckInput = luckState.bandLuckInput,
		bandLuckSummary = bandLuckSummary,
		rarityShares = rarityShares,
		entries = entries,
		activeEntryCount = #activeEntries,
		prunedEntryCount = #entries - #activeEntries,
		summary = table.concat({
			formatBandLuckSummary(bandLuckSummary),
			formatRarityShareSummary(rarityShares),
			summarizeProbabilityTable(entries),
		}, " | "),
	}
end

function RollService:GetAdminLuckOverrideState(player: Player): { [string]: any }
	local selectedRollTypeId = DataService:GetSelectedRollType(player)
	local rollType = RollTypes.Get(selectedRollTypeId) or RollTypes.GetDefault()
	local successfulRollCount = DataService:GetSuccessfulRollCount(player)
	local computedLuckState = computeLuckState(player, rollType, successfulRollCount, true)
	local overrideLuck = adminLuckOverridesByPlayer[player]
	local effectiveLuck = if overrideLuck ~= nil then overrideLuck else computedLuckState.rawLuck

	return {
		hasOverride = overrideLuck ~= nil,
		overrideLuck = overrideLuck,
		effectiveLuck = effectiveLuck,
		computedLuckWithoutOverride = computedLuckState.rawLuck,
		rollTypeId = rollType.id,
		rollTypeDisplayName = rollType.displayName,
		baseLuck = computedLuckState.baseLuck,
		bonusLuck = computedLuckState.bonusLuck,
		potionLuck = computedLuckState.potionLuck,
		vipLuck = computedLuckState.vipLuck,
		equippedLuckMultiplier = computedLuckState.equippedLuckMultiplier,
		potionLuckBonus = computedLuckState.potionLuckBonus,
		loadoutLuckMultiplier = computedLuckState.loadoutLuckMultiplier,
		potionLuckMultiplier = computedLuckState.potionLuckMultiplier,
		useBonusRoll = computedLuckState.useBonusRoll,
		isVipOwned = computedLuckState.isVipOwned,
	}
end

function RollService:SetAdminLuckOverride(player: Player, totalLuck: number): { [string]: any }
	adminLuckOverridesByPlayer[player] = math.max(0, tonumber(totalLuck) or 0)
	self:NotifyClient(player, "Admin luck override updated.")
	return self:GetAdminLuckOverrideState(player)
end

function RollService:ClearAdminLuckOverride(player: Player): { [string]: any }
	adminLuckOverridesByPlayer[player] = nil
	self:NotifyClient(player, "Admin luck override cleared.")
	return self:GetAdminLuckOverrideState(player)
end

function RollService:SimulateRolls(player: Player, options: any?): { [string]: any }
	local count = math.clamp(math.floor(tonumber(options and options.count) or 100), 1, 10000)
	local debugData = self:GetProbabilityDebug(player, options)
	local activeEntries = {}
	for _, entry in ipairs(debugData.entries or {}) do
		if entry.isPruned ~= true then
			table.insert(activeEntries, entry)
		end
	end

	local selectedRegion = if typeof(options) == "table" and typeof(options.rollRegion) == "string" and RollTargetRegions.IsValid(options.rollRegion)
		then options.rollRegion
		else DataService:GetSelectedRollRegion(player)
	local randomSource = Random.new(math.floor(tonumber(options and options.seed) or os.clock() * 1000000))
	local byRarity = {}
	local bySetId = {}
	local byPieceId = {}
	local missingPieceCount = 0

	for _ = 1, count do
		local chosenSet = chooseWeightedSet(randomSource, activeEntries)
		if chosenSet then
			local rarity = chosenSet.displayRarity or "Unknown"
			byRarity[rarity] = (byRarity[rarity] or 0) + 1
			bySetId[chosenSet.setId] = (bySetId[chosenSet.setId] or 0) + 1

			local piece = choosePieceFromSetForRegion(randomSource, chosenSet.setId, selectedRegion)
			if piece then
				byPieceId[piece.id] = (byPieceId[piece.id] or 0) + 1
			else
				missingPieceCount += 1
			end
		end
	end

	return {
		count = count,
		rollTypeId = debugData.rollTypeId,
		rollTypeDisplayName = debugData.rollTypeDisplayName,
		rollRegion = selectedRegion,
		finalLuck = debugData.finalLuck,
		bandLuckInput = debugData.bandLuckInput,
		byRarity = byRarity,
		bySetId = bySetId,
		byPieceId = byPieceId,
		missingPieceCount = missingPieceCount,
		probabilitySummary = debugData.summary,
	}
end

function RollService:PreviewChestRewards(player: Player, options: any?): { [string]: any }
	local count = math.clamp(math.floor(tonumber(options and options.count) or 5), 1, 10)
	local debugData = self:GetProbabilityDebug(player, options)
	local activeEntries = {}
	for _, entry in ipairs(debugData.entries or {}) do
		if entry.isPruned ~= true then
			table.insert(activeEntries, entry)
		end
	end

	local selectedRegion = if typeof(options) == "table" and typeof(options.rollRegion) == "string" and RollTargetRegions.IsValid(options.rollRegion)
		then options.rollRegion
		else DataService:GetSelectedRollRegion(player)
	local randomSource = Random.new(math.floor(tonumber(options and options.seed) or os.clock() * 1000000))
	local rollType = RollTypes.Get(debugData.rollTypeId) or RollTypes.GetDefault()
	local successfulRollCount = DataService:GetSuccessfulRollCount(player)
	local luckState, _, potionBonuses = computeLuckState(player, rollType, successfulRollCount)
	local rewards = {}
	local missingPieceCount = 0

	for index = 1, count do
		local chosenSet = chooseWeightedSet(randomSource, activeEntries)
		local finalPiece = chosenSet and choosePieceFromSetForRegion(randomSource, chosenSet.setId, selectedRegion) or nil
		if not (chosenSet and finalPiece) then
			missingPieceCount += 1
			continue
		end

		local mutationData = rollMutation(
			randomSource,
			if typeof(potionBonuses) == "table" then potionBonuses.mutationChanceBonusById else nil
		)
		local sizeData, sizeScale = rollSize(
			randomSource,
			if typeof(potionBonuses) == "table" then potionBonuses.sizeLuckBonus else nil
		)
		local sizeMoneyMultiplier = SizeConfig.GetMoneyMultiplier(sizeData.id)
		local variantMultiplier = RollMath.ComputeVariantMultiplier(mutationData.multiplier, sizeMoneyMultiplier)
		local finalPassiveIncomePerSecond = RollMath.ComputeFinalPassiveIncome(finalPiece.passiveIncomePerSecond, variantMultiplier)
		local finalResultData = {
			mutationData = mutationData,
			sizeData = sizeData,
			sizeScale = sizeScale,
			sizeMoneyMultiplier = sizeMoneyMultiplier,
			variantMultiplier = variantMultiplier,
			finalPassiveIncomePerSecond = finalPassiveIncomePerSecond,
			rawLuck = luckState.rawLuck,
			useBonusRoll = luckState.useBonusRoll,
		}
		local finalResult, finalResultError = createRollDisplayEntry(finalPiece, finalResultData)
		if not finalResult then
			return {
				ok = false,
				message = finalResultError or "Failed to build a chest preview reward.",
				rewards = {},
			}
		end

		local record = {
			ownedId = string.format("preview_%d_%d", player.UserId, index),
			pieceId = finalPiece.id,
			rarityDenominator = chosenSet.displayedDenominator,
			displayOddsDenominator = chosenSet.displayedDenominator,
			displayRarity = chosenSet.setConfig.rollDisplay.rarity,
			rolledSetId = chosenSet.setId,
			rolledSetDisplayName = chosenSet.setConfig.rollDisplay.displayName,
			mutationId = mutationData.id,
			mutation = mutationData.displayName,
			mutationMultiplier = mutationData.multiplier,
			sizeId = sizeData.id,
			sizeMultiplier = sizeScale,
			variantMultiplier = variantMultiplier,
			finalPassiveIncomePerSecond = finalPassiveIncomePerSecond,
			isFavorite = false,
		}

		table.insert(rewards, {
			record = record,
			finalResult = finalResult,
			rollTypeId = debugData.rollTypeId,
			rollRegion = selectedRegion,
		})
	end

	return {
		ok = #rewards > 0,
		message = if #rewards > 0 then string.format("Built %d chest preview reward(s).", #rewards) else "No preview rewards could be generated.",
		count = count,
		rewardCount = #rewards,
		missingPieceCount = missingPieceCount,
		rollTypeId = debugData.rollTypeId,
		rollTypeDisplayName = debugData.rollTypeDisplayName,
		rollRegion = selectedRegion,
		finalLuck = debugData.finalLuck,
		bandLuckInput = debugData.bandLuckInput,
		probabilitySummary = debugData.summary,
		rewards = rewards,
	}
end

function RollService:GetRollingState(player: Player, message: string?)
	if not isRollingEnabled() then
		return buildUnavailableRollingState(message)
	end

	local rollTypeEntries, selectedRollTypeId = buildRollTypeState(player)
	local rollRegionEntries, selectedRollRegion, selectedRollRegionIcon = buildRollRegionState(player)
	local selectedRollType = RollTypes.Get(selectedRollTypeId) or RollTypes.GetDefault()
	local successfulRollCount = DataService:GetSuccessfulRollCount(player)
	local quickRollState = buildQuickRollState(player)
	local autoEquipBestState = buildAutoEquipBestState(player)
	local luckState, bonuses, potionBonuses = computeLuckState(player, selectedRollType, successfulRollCount)
	local baseTotalLuck = luckState.baseLuck
	local effectiveRollCooldown = getEffectiveRollCooldown(player, bonuses, quickRollState)

	return {
		money = DataService:GetMoney(player),
		rollTypes = rollTypeEntries,
		rollRegions = rollRegionEntries,
		selectedRollTypeId = selectedRollType.id,
		selectedRollRegion = selectedRollRegion,
		selectedRollRegionIcon = selectedRollRegionIcon,
		selectedRollType = {
			id = selectedRollType.id,
			displayName = selectedRollType.displayName,
			moneyCost = selectedRollType.moneyCost,
			luckMultiplier = selectedRollType.luckMultiplier,
			bandLuckScalar = math.max(0, tonumber(selectedRollType.bandLuckScalar) or 1),
		},
		bonuses = bonuses,
		successfulRollCount = successfulRollCount,
		rollsSinceLuckyRoll = luckState.rollsSinceBonusRoll,
		luckyRollGoal = RollingConfig.BonusInterval,
		luckBoostReady = luckState.luckBoostReady,
		willUsePityBoost = luckState.useBonusRoll,
		willUseBonusRoll = luckState.useBonusRoll,
		baseTotalLuck = baseTotalLuck,
		totalLuck = luckState.rawLuck,
		baseRawLuck = luckState.baseLuck,
		rawLuck = luckState.rawLuck,
		bonusLuck = luckState.bonusLuck,
		potionLuck = luckState.potionLuck,
		potionLuckMultiplier = luckState.potionLuckMultiplier,
		loadoutLuckMultiplier = luckState.loadoutLuckMultiplier,
		vipLuck = luckState.vipLuck,
		equippedLuckMultiplier = luckState.equippedLuckMultiplier,
		isVipOwned = luckState.isVipOwned,
		bonusInterval = RollingConfig.BonusInterval,
		bonusMultiplier = RollingConfig.BonusMultiplier,
		vipMultiplier = RollingConfig.VipMultiplier,
		bandLuckScalar = luckState.bandLuckScalar,
		bandLuckInput = luckState.bandLuckInput,
		nextRollNumber = luckState.nextRollNumber,
		potionBonuses = potionBonuses,
		quickRoll = quickRollState,
		autoEquipBest = autoEquipBestState,
		effectiveRollCooldown = effectiveRollCooldown,
		autoSellRarities = buildAutoSellState(player),
		cutsceneRarities = buildCutsceneState(player),
		message = message,
	}
end

function RollService:GetRollingDeltaState(player: Player, message: string?)
	if not isRollingEnabled() then
		return markDeltaState(buildUnavailableRollingState(message))
	end

	local selectedRollTypeId = DataService:GetSelectedRollType(player)
	local selectedRollType = RollTypes.Get(selectedRollTypeId) or RollTypes.GetDefault()
	local successfulRollCount = DataService:GetSuccessfulRollCount(player)
	local quickRollState = buildQuickRollState(player)
	local autoEquipBestState = buildAutoEquipBestState(player)
	local luckState, bonuses, potionBonuses = computeLuckState(player, selectedRollType, successfulRollCount)
	local effectiveRollCooldown = getEffectiveRollCooldown(player, bonuses, quickRollState)
	local rollRegionEntries, selectedRollRegion, selectedRollRegionIcon = buildRollRegionState(player)

	return markDeltaState({
		money = DataService:GetMoney(player),
		rollRegions = rollRegionEntries,
		selectedRollTypeId = selectedRollType.id,
		selectedRollRegion = selectedRollRegion,
		selectedRollRegionIcon = selectedRollRegionIcon,
		selectedRollType = {
			id = selectedRollType.id,
			displayName = selectedRollType.displayName,
			moneyCost = selectedRollType.moneyCost,
			luckMultiplier = selectedRollType.luckMultiplier,
			bandLuckScalar = math.max(0, tonumber(selectedRollType.bandLuckScalar) or 1),
		},
		bonuses = bonuses,
		potionBonuses = potionBonuses,
		successfulRollCount = successfulRollCount,
		rollsSinceLuckyRoll = luckState.rollsSinceBonusRoll,
		luckyRollGoal = RollingConfig.BonusInterval,
		luckBoostReady = luckState.luckBoostReady,
		willUsePityBoost = luckState.useBonusRoll,
		willUseBonusRoll = luckState.useBonusRoll,
		baseTotalLuck = luckState.baseLuck,
		totalLuck = luckState.rawLuck,
		baseRawLuck = luckState.baseLuck,
		rawLuck = luckState.rawLuck,
		bonusLuck = luckState.bonusLuck,
		potionLuck = luckState.potionLuck,
		potionLuckMultiplier = luckState.potionLuckMultiplier,
		loadoutLuckMultiplier = luckState.loadoutLuckMultiplier,
		vipLuck = luckState.vipLuck,
		equippedLuckMultiplier = luckState.equippedLuckMultiplier,
		isVipOwned = luckState.isVipOwned,
		bonusInterval = RollingConfig.BonusInterval,
		bonusMultiplier = RollingConfig.BonusMultiplier,
		vipMultiplier = RollingConfig.VipMultiplier,
		bandLuckScalar = luckState.bandLuckScalar,
		bandLuckInput = luckState.bandLuckInput,
		nextRollNumber = luckState.nextRollNumber,
		quickRoll = quickRollState,
		autoEquipBest = autoEquipBestState,
		effectiveRollCooldown = effectiveRollCooldown,
		autoSellRarities = buildAutoSellState(player),
		cutsceneRarities = buildCutsceneState(player),
		message = message,
	})
end

function RollService:GetRollCompletionDeltaState(player: Player, message: string?)
	if not isRollingEnabled() then
		return markDeltaState(buildUnavailableRollingState(message))
	end

	local selectedRollTypeId = DataService:GetSelectedRollType(player)
	local selectedRollType = RollTypes.Get(selectedRollTypeId) or RollTypes.GetDefault()
	local successfulRollCount = DataService:GetSuccessfulRollCount(player)
	local quickRollState = buildQuickRollState(player)
	local autoEquipBestState = buildAutoEquipBestState(player)
	local luckState, bonuses, potionBonuses = computeLuckState(player, selectedRollType, successfulRollCount)
	local effectiveRollCooldown = getEffectiveRollCooldown(player, bonuses, quickRollState)
	local rollRegionEntries, selectedRollRegion, selectedRollRegionIcon = buildRollRegionState(player)

	return markDeltaState({
		money = DataService:GetMoney(player),
		rollRegions = rollRegionEntries,
		selectedRollTypeId = selectedRollType.id,
		selectedRollRegion = selectedRollRegion,
		selectedRollRegionIcon = selectedRollRegionIcon,
		selectedRollType = {
			id = selectedRollType.id,
			displayName = selectedRollType.displayName,
			moneyCost = selectedRollType.moneyCost,
			luckMultiplier = selectedRollType.luckMultiplier,
			bandLuckScalar = math.max(0, tonumber(selectedRollType.bandLuckScalar) or 1),
		},
		bonuses = bonuses,
		potionBonuses = potionBonuses,
		successfulRollCount = successfulRollCount,
		rollsSinceLuckyRoll = luckState.rollsSinceBonusRoll,
		luckyRollGoal = RollingConfig.BonusInterval,
		luckBoostReady = luckState.luckBoostReady,
		willUsePityBoost = luckState.useBonusRoll,
		willUseBonusRoll = luckState.useBonusRoll,
		baseTotalLuck = luckState.baseLuck,
		totalLuck = luckState.rawLuck,
		baseRawLuck = luckState.baseLuck,
		rawLuck = luckState.rawLuck,
		bonusLuck = luckState.bonusLuck,
		potionLuck = luckState.potionLuck,
		potionLuckMultiplier = luckState.potionLuckMultiplier,
		loadoutLuckMultiplier = luckState.loadoutLuckMultiplier,
		vipLuck = luckState.vipLuck,
		equippedLuckMultiplier = luckState.equippedLuckMultiplier,
		isVipOwned = luckState.isVipOwned,
		bonusInterval = RollingConfig.BonusInterval,
		bonusMultiplier = RollingConfig.BonusMultiplier,
		vipMultiplier = RollingConfig.VipMultiplier,
		bandLuckScalar = luckState.bandLuckScalar,
		bandLuckInput = luckState.bandLuckInput,
		nextRollNumber = luckState.nextRollNumber,
		quickRoll = quickRollState,
		autoEquipBest = autoEquipBestState,
		effectiveRollCooldown = effectiveRollCooldown,
		message = message,
	})
end

local function buildClientRollResult(rollResult: any): any
	if typeof(rollResult) ~= "table" or rollResult.skipPresentation ~= true then
		return rollResult
	end

	return {
		finalResult = if rollResult.shouldPlayCutscene == true then rollResult.finalResult else nil,
		skipPreview = rollResult.skipPreview,
		skipPresentation = rollResult.skipPresentation,
		autoSoldInstantly = rollResult.autoSoldInstantly,
		autoEquipped = rollResult.autoEquipped,
		autoCraftCommitted = rollResult.autoCraftCommitted,
		autoCrafted = rollResult.autoCrafted,
		autoCraftMessage = rollResult.autoCraftMessage,
		autoSellRarity = rollResult.autoSellRarity,
		moneySpent = rollResult.moneySpent,
		remainingMoney = rollResult.remainingMoney,
		successfulRollCount = rollResult.successfulRollCount,
		shouldPlayCutscene = rollResult.shouldPlayCutscene,
		cutsceneTier = rollResult.cutsceneTier,
		cutsceneSetId = rollResult.cutsceneSetId,
	}
end

function RollService:NotifyClient(player: Player, message: string?)
	if not isRollingEnabled() then
		return
	end

	local startedAt = PerfStats.Begin()
	local payload = self:GetRollingDeltaState(player, message)
	ensureUpdatedRemote():FireClient(player, payload)
	PerfStats.Measure("RollingUpdated", startedAt, {
		payload = payload,
		detail = player.Name,
	})
end

function RollService:SelectRollType(player: Player, rollTypeId: string): (boolean, string)
	if not isRollingEnabled() then
		return false, getRollingUnavailableMessage()
	end

	local rollType = RollTypes.Get(rollTypeId)
	if not rollType then
		return false, "That roll type does not exist."
	end

	local previousRollTypeId = DataService:GetSelectedRollType(player)
	local ok, message = DataService:SetSelectedRollType(player, rollTypeId)
	if not ok then
		return false, message or "Failed to select the roll type."
	end
	if previousRollTypeId ~= rollTypeId then
		StatsService:RecordSettingChange(player, "roll_type")
	end
	TutorialService:RecordRollTypeSelected(player, rollType.id)

	return true, string.format("Selected %s.", rollType.displayName)
end

function RollService:SelectRollRegion(player: Player, rollRegion: string): (boolean, string)
	if not isRollingEnabled() then
		return false, getRollingUnavailableMessage()
	end

	local previousRollRegion = DataService:GetSelectedRollRegion(player)
	local ok, message = DataService:SetSelectedRollRegion(player, rollRegion)
	if not ok then
		return false, message or "Failed to select the roll region."
	end
	if previousRollRegion ~= rollRegion then
		StatsService:RecordSettingChange(player, "roll_region")
	end

	local iconEntry = BodyPartIcons[rollRegion]
	return true, string.format("Selected %s.", if iconEntry then iconEntry.buttonName else rollRegion)
end

function RollService:ToggleQuickRoll(player: Player, enabled: boolean): (boolean, string)
	if not isRollingEnabled() then
		return false, getRollingUnavailableMessage()
	end

	local quickRollState = buildQuickRollState(player)
	if not quickRollState.owned then
		return false, "Quick Roll requires the gamepass."
	end

	local previousEnabled = quickRollState.enabled == true
	local ok, message = DataService:SetQuickRollEnabled(player, enabled == true)
	if not ok then
		return false, message or "Failed to update Quick Roll."
	end
	if previousEnabled ~= (enabled == true) then
		StatsService:RecordSettingChange(player, "quick_roll")
	end

	return true, if enabled then "Quick Roll enabled." else "Quick Roll disabled."
end

function RollService:ToggleAutoEquipBest(player: Player, enabled: boolean): (boolean, string)
	if not isRollingEnabled() then
		return false, getRollingUnavailableMessage()
	end

	local nextEnabled = enabled == true
	local wasEnabled = DataService:GetAutoEquipBestEnabled(player)
	local ok, message = DataService:SetAutoEquipBestEnabled(player, nextEnabled)
	if not ok then
		return false, message or "Failed to update Auto Equip Best."
	end
	if wasEnabled ~= nextEnabled then
		StatsService:RecordSettingChange(player, "auto_equip_best")
	end

	return true, if nextEnabled then "Auto Equip Best enabled." else "Auto Equip Best disabled."
end

function RollService:ToggleAutoSellRarity(player: Player, displayRarity: any, enabled: boolean): (boolean, string)
	if not isRollingEnabled() then
		return false, getRollingUnavailableMessage()
	end

	local normalizedRarity = RollingConfig.ResolveDisplayRarity(displayRarity)
	if not normalizedRarity then
		return false, "That auto-sell rarity does not exist."
	end

	local wasEnabled = DataService:IsAutoSellEnabledForRarity(player, normalizedRarity)
	local ok, message = DataService:SetAutoSellRarityEnabled(player, normalizedRarity, enabled == true)
	if not ok then
		return false, message or "Failed to update auto-sell."
	end
	if wasEnabled ~= (enabled == true) then
		StatsService:RecordSettingChange(player, "auto_sell")
	end

	return true, message or string.format(
		"%s auto-sell %s.",
		normalizedRarity,
		if enabled == true then "enabled" else "disabled"
	)
end

function RollService:ToggleCutsceneRarity(player: Player, displayRarity: any, enabled: boolean): (boolean, string)
	if not isRollingEnabled() then
		return false, getRollingUnavailableMessage()
	end

	local normalizedRarity = RollingConfig.ResolveDisplayRarity(displayRarity)
	if not normalizedRarity then
		return false, "That cutscene rarity does not exist."
	end

	local nextEnabled = enabled ~= false
	local wasEnabled = DataService:IsCutsceneEnabledForRarity(player, normalizedRarity)
	local ok, message = DataService:SetCutsceneRarityEnabled(player, normalizedRarity, nextEnabled)
	if not ok then
		return false, message or "Failed to update cutscenes."
	end
	if wasEnabled ~= nextEnabled then
		StatsService:RecordSettingChange(player, "cutscene")
	end

	return true, message or string.format(
		"%s cutscenes %s.",
		normalizedRarity,
		if nextEnabled then "enabled" else "disabled"
	)
end

function RollService:FinalizeAutoSellRoll(player: Player, payload: any): (boolean, string)
	if not isRollingEnabled() then
		return false, getRollingUnavailableMessage()
	end

	if typeof(payload) ~= "table" then
		return false, "Finalize auto-sell payload must be a table."
	end

	local token = payload.token
	if typeof(token) == "string" and token ~= "" then
		local pendingState = pendingAutoSellByPlayer[player]
		local pendingEntry = pendingState and pendingState[token]
		if not pendingEntry then
			return false, "That roll is no longer pending auto-sell."
		end

		if payload.keep == true then
			local ownedRecord, grantError = DataService:AddOwnedBodyPart(player, pendingEntry.grantPayload, pendingEntry.reservation)
			if not ownedRecord then
				return false, grantError or "Failed to keep the roll result."
			end

			clearPendingAutoSell(player, token)
			StatsService:RecordAutoSellOutcome(player, "kept")

			local message = string.format("Kept %s roll result.", pendingEntry.displayRarity)
			if payload.equip == true then
				local equipped, equipMessage = BodyPartService:EquipOwnedBodyPart(player, ownedRecord.ownedId, payload.scale, {
					applyVisuals = true,
				})
				if equipped then
					message = equipMessage or message
				elseif equipMessage then
					message = string.format("%s %s", message, equipMessage)
				end
			end

			return true, message
		end

		local sold, sellMessage = sellReservedBodyPartRecord(player, pendingEntry.ownedRecord)
		if not sold then
			return false, sellMessage or "Failed to auto-sell the roll result."
		end

		clearPendingAutoSell(player, token)
		StatsService:RecordAutoSellOutcome(player, "sold")
		return true, sellMessage or string.format("Auto-sold %s roll result.", pendingEntry.displayRarity)
	end

	local ownedId = payload.ownedId
	if typeof(ownedId) ~= "string" or ownedId == "" then
		return false, "ownedId is required."
	end

	local pendingState = pendingAutoSellByPlayer[player]
	local pendingEntry = pendingState and pendingState[ownedId]
	if not pendingEntry then
		return false, "That roll is no longer pending auto-sell."
	end

	if payload.keep == true or isOwnedIdEquipped(player, ownedId) then
		clearPendingAutoSell(player, ownedId)
		StatsService:RecordAutoSellOutcome(player, "kept")
		return true, string.format("Kept %s roll result.", pendingEntry.displayRarity)
	end

	local sold, sellMessage = BodyPartService:SellOwnedBodyPart(player, ownedId)
	if not sold then
		return false, sellMessage or "Failed to auto-sell the roll result."
	end
	clearPendingAutoSell(player, ownedId)
	StatsService:RecordAutoSellOutcome(player, "sold")

	return true, sellMessage or string.format("Auto-sold %s roll result.", pendingEntry.displayRarity)
end

function RollService:PromptQuickRollPurchase(player: Player): (boolean, string)
	if not isRollingEnabled() then
		return false, getRollingUnavailableMessage()
	end

	local passConfig = getQuickRollPassConfig()
	if not passConfig or not passConfig.offerKey then
		return false, "Quick Roll is not configured."
	end

	local ok, message = PurchaseReceiptService:PromptOfferPurchase(player, passConfig.offerKey)
	if not ok then
		return false, message or "Failed to open the Quick Roll purchase prompt."
	end

	return true, message or "Purchase prompt opened."
end

function RollService:PerformRoll(player: Player, payload: any?): (boolean, string, any?, any?)
	local startedAt = PerfStats.Begin()
	StatsService:RecordRollRequest(player)
	if not isRollingEnabled() then
		StatsService:RecordRollFailure(player, "unavailable")
		PerfStats.Measure("PerformRoll", startedAt, {
			detail = string.format("%s:unavailable", player.Name),
		})
		return false, getRollingUnavailableMessage(), nil
	end

	if rollLocks[player] then
		StatsService:RecordRollFailure(player, "locked")
		PerfStats.Measure("PerformRoll", startedAt, {
			detail = string.format("%s:locked", player.Name),
		})
		return false, "A roll is already in progress.", nil
	end

	rollLocks[player] = true

	local selectedRollTypeId = DataService:GetSelectedRollType(player)
	local selectedRollType = RollTypes.Get(selectedRollTypeId)
	local selectedRollRegion = DataService:GetSelectedRollRegion(player)
	if not selectedRollType then
		rollLocks[player] = nil
		StatsService:RecordRollFailure(player, "invalid_selection")
		PerfStats.Measure("PerformRoll", startedAt, {
			detail = string.format("%s:invalid_selection", player.Name),
		})
		return false, "No valid roll type is selected.", nil
	end

	local currentOwnedCount = OwnedBodyParts.CountOwned(DataService:GetBodyPartsState(player))
	if currentOwnedCount >= OwnedBodyParts.MAX_OWNED_COUNT then
		rollLocks[player] = nil
		StatsService:RecordRollFailure(player, "inventory_full")
		PerfStats.Measure("PerformRoll", startedAt, {
			detail = string.format("%s:inventory_full", player.Name),
		})
		return false, string.format(
			"Inventory is full (%d/%d). Sell body parts before rolling again.",
			currentOwnedCount,
			OwnedBodyParts.MAX_OWNED_COUNT
		), nil
	end

	local currentMoney = DataService:GetMoney(player)
	if currentMoney < selectedRollType.moneyCost then
		rollLocks[player] = nil
		StatsService:RecordRollFailure(player, "insufficient_money")
		PerfStats.Measure("PerformRoll", startedAt, {
			detail = string.format("%s:insufficient_money", player.Name),
		})
		return false, string.format(
			"You need %s more money to use %s.",
			formatMoney(selectedRollType.moneyCost - currentMoney),
			selectedRollType.displayName
		), nil
	end

	local successfulRollCount = DataService:GetSuccessfulRollCount(player)
	local luckState, bonuses, potionBonuses = computeLuckState(player, selectedRollType, successfulRollCount)
	local quickRollState = buildQuickRollState(player)
	local effectiveRollCooldown = getEffectiveRollCooldown(player, bonuses, quickRollState)
	local now = os.clock()
	local cooldownUntil = rollCooldownUntilByPlayer[player]
	if cooldownUntil and now < cooldownUntil then
		local retryAfterSeconds = cooldownUntil - now
		rollLocks[player] = nil
		StatsService:RecordRollFailure(player, "cooldown")
		PerfStats.Measure("PerformRoll", startedAt, {
			detail = string.format("%s:cooldown", player.Name),
		})
		return false, string.format("You're rolling too quickly. Try again in %.1fs.", retryAfterSeconds), nil
	end

	rollCooldownUntilByPlayer[player] = now + effectiveRollCooldown
	local tutorialRollOverride = TutorialService:GetRollOverride(player, {
		rollTypeId = selectedRollType.id,
		rollRegion = selectedRollRegion,
	})
	if typeof(tutorialRollOverride) == "table" then
		local rawLuckBonus = math.max(0, tonumber(tutorialRollOverride.rawLuckBonus) or 0)
		if rawLuckBonus > 0 then
			luckState.rawLuck += rawLuckBonus
			luckState.bandLuckInput = luckState.rawLuck * luckState.bandLuckScalar
		end
	end
	local quickRollApplied = quickRollState.enabled == true
	local triggerSource = if typeof(payload) == "table" and payload.triggerSource == "auto" then "auto" else "manual"
	local skipPresentation = quickRollApplied and triggerSource == "auto"
	local skipPreview = quickRollApplied and triggerSource ~= "auto"
	local allEntries, activeEntries = buildRollListEntries(luckState.bandLuckInput)
	local randomSource = Random.new()
	local finalSet = chooseWeightedSet(randomSource, activeEntries)
	local forcedPiece = nil
	local forcedSetApplied = false
	if typeof(tutorialRollOverride) == "table" then
		if typeof(tutorialRollOverride.forcedPieceId) == "string" then
			forcedPiece = BodyPartsCatalog.GetPiece(tutorialRollOverride.forcedPieceId)
			if forcedPiece then
				local forcedSet = findRollEntryForPiece(activeEntries, forcedPiece) or findRollEntryForPiece(allEntries, forcedPiece)
				if forcedSet then
					finalSet = forcedSet
					forcedSetApplied = true
				else
					forcedPiece = nil
				end
			end
		end
		if not forcedPiece and typeof(tutorialRollOverride.forcedSetId) == "string" then
			local forcedSet = findRollEntryBySetId(activeEntries, tutorialRollOverride.forcedSetId)
				or findRollEntryBySetId(allEntries, tutorialRollOverride.forcedSetId)
			if forcedSet then
				finalSet = forcedSet
				forcedSetApplied = true
			end
		end
	end
	if not finalSet then
		rollLocks[player] = nil
		StatsService:RecordRollFailure(player, "missing_config")
		PerfStats.Measure("PerformRoll", startedAt, {
			detail = string.format("%s:missing_set", player.Name),
		})
		return false, "No body part sets are configured for rolling.", nil
	end

	local finalPiece = forcedPiece
	if not finalPiece then
		if forcedSetApplied then
			finalPiece = choosePieceFromSet(randomSource, finalSet.setId)
		else
			finalPiece = choosePieceFromSetForRegion(randomSource, finalSet.setId, selectedRollRegion)
		end
	end
	if not finalPiece then
		rollLocks[player] = nil
		StatsService:RecordRollFailure(player, "missing_config")
		PerfStats.Measure("PerformRoll", startedAt, {
			detail = string.format("%s:missing_piece", player.Name),
		})
		return false, string.format("No body parts are configured for %s rolls.", selectedRollRegion), nil
	end
	local didDiscoverPieceFirstTime = not DataService:HasDiscoveredBodyPartPiece(player, finalPiece.id)

	local mutationData = rollMutation(
		randomSource,
		if typeof(potionBonuses) == "table" then potionBonuses.mutationChanceBonusById else nil
	)
	local sizeData, sizeScale = rollSize(
		randomSource,
		if typeof(potionBonuses) == "table" then potionBonuses.sizeLuckBonus else nil
	)
	local sizeMoneyMultiplier = SizeConfig.GetMoneyMultiplier(sizeData.id)
	local variantMultiplier = RollMath.ComputeVariantMultiplier(mutationData.multiplier, sizeMoneyMultiplier)
	local finalPassiveIncomePerSecond = RollMath.ComputeFinalPassiveIncome(finalPiece.passiveIncomePerSecond, variantMultiplier)
	local finalResultData = {
		mutationData = mutationData,
		sizeData = sizeData,
		sizeScale = sizeScale,
		sizeMoneyMultiplier = sizeMoneyMultiplier,
		variantMultiplier = variantMultiplier,
		finalPassiveIncomePerSecond = finalPassiveIncomePerSecond,
		rawLuck = luckState.rawLuck,
		useBonusRoll = luckState.useBonusRoll,
	}

	local finalResult, finalResultError = createRollDisplayEntry(finalPiece, finalResultData)
	if not finalResult then
		rollLocks[player] = nil
		StatsService:RecordRollFailure(player, "missing_config")
		PerfStats.Measure("PerformRoll", startedAt, {
			detail = string.format("%s:missing_result", player.Name),
		})
		return false, finalResultError or "Failed to build the final roll result.", nil
	end

	local remainingMoney = DataService:AdjustMoney(player, -selectedRollType.moneyCost, "roll_cost")
	local autoSellRarity = RollingConfig.NormalizeDisplayRarity(finalSet.setConfig.rollDisplay.rarity)
	local autoSellEnabledForRarity = DataService:IsAutoSellEnabledForRarity(player, autoSellRarity)
	local grantPayload = {
		pieceId = finalPiece.id,
		rarityDenominator = finalSet.displayedDenominator,
		rolledSetId = finalSet.setId,
		rolledSetDisplayName = finalSet.setConfig.rollDisplay.displayName,
		displayOddsDenominator = finalSet.displayedDenominator,
		displayRarity = finalSet.setConfig.rollDisplay.rarity,
		mutationId = mutationData.id,
		mutation = mutationData.displayName,
		mutationMultiplier = mutationData.multiplier,
		sizeId = sizeData.id,
		sizeMultiplier = sizeScale,
		variantMultiplier = variantMultiplier,
		finalPassiveIncomePerSecond = finalPassiveIncomePerSecond,
	}
	local tutorialCraftPriority = typeof(tutorialRollOverride) == "table"
		and typeof(tutorialRollOverride.forceAutoCraftRecipeId) == "string"
		and typeof(tutorialRollOverride.targetIngredientKey) == "string"
	local autoCraftCommitResult = nil
	if tutorialCraftPriority then
		autoCraftCommitResult = CraftingService:TryAutoCommitRolledBodyPart(player, grantPayload, {
			targetRecipeId = tutorialRollOverride.forceAutoCraftRecipeId,
			targetIngredientKey = tutorialRollOverride.targetIngredientKey,
			waiveCraftCost = tutorialRollOverride.waiveCraftCost == true,
		})
	end
	local autoCraftCommitted = typeof(autoCraftCommitResult) == "table" and autoCraftCommitResult.committed == true
	local shouldAutoEquipRoll = false
	if not tutorialCraftPriority and DataService:GetAutoEquipBestEnabled(player) then
		shouldAutoEquipRoll = BodyPartService:IsBodyPartGrantBetterThanEquipped(player, grantPayload)
	end

	if not tutorialCraftPriority and not shouldAutoEquipRoll then
		autoCraftCommitResult = CraftingService:TryAutoCommitRolledBodyPart(player, grantPayload)
	end
	autoCraftCommitted = typeof(autoCraftCommitResult) == "table" and autoCraftCommitResult.committed == true
	local pendingAutoSell = (not tutorialCraftPriority) and (not shouldAutoEquipRoll) and (not autoCraftCommitted) and (not skipPresentation) and autoSellEnabledForRarity
	local shouldUseTransientRecord = (not tutorialCraftPriority) and (not shouldAutoEquipRoll) and (not autoCraftCommitted) and autoSellEnabledForRarity

	local ownedRecord, grantError, reservedGrant
	if autoCraftCommitted then
		ownedRecord = table.clone(grantPayload)
		ownedRecord.ownedId = ""
		ownedRecord.serialNumber = 0
		ownedRecord.isFavorite = false
	elseif shouldUseTransientRecord then
		ownedRecord, reservedGrant, grantError = DataService:ReserveBodyPartRollRecord(player, grantPayload)
	else
		ownedRecord, grantError = DataService:AddOwnedBodyPart(player, grantPayload)
	end
	if not ownedRecord then
		StatsService:RecordRollFailure(player, "grant_failed")
		DataService:AddMoney(player, selectedRollType.moneyCost, "other")
		rollLocks[player] = nil
		PerfStats.Measure("PerformRoll", startedAt, {
			detail = string.format("%s:grant_failed", player.Name),
		})
		return false, grantError or "Failed to save the rolled body part.", nil
	end

	local autoEquipped = false
	local autoEquipMessage = nil
	if shouldAutoEquipRoll then
		local equipped, equipMessage = BodyPartService:EquipOwnedBodyPartIfBetter(player, ownedRecord.ownedId, sizeScale, {
			applyVisuals = true,
		})
		autoEquipped = equipped == true
		autoEquipMessage = equipMessage
		if not equipped and equipMessage then
			Logger.Warn(string.format(
				"[RollService] Auto Equip Best skipped for %s (%s): %s",
				player.Name,
				tostring(ownedRecord.ownedId),
				tostring(equipMessage)
			))
		end
	end

	local updatedSuccessfulRollCount = DataService:IncrementSuccessfulRollCount(player)
	local autoSoldInstantly = false
	local pendingAutoSellToken = nil
	local rollMessage = string.format("Rolled %s.", finalResult.Name)
	if autoEquipped then
		rollMessage = autoEquipMessage or string.format("Equipped %s.", finalResult.Name)
	elseif autoCraftCommitted then
		rollMessage = tostring(autoCraftCommitResult.message or string.format("Added %s to crafting.", finalResult.Name))
	end
	if pendingAutoSell then
		pendingAutoSellToken = createPendingAutoSellToken(player)
		getPendingAutoSellState(player)[pendingAutoSellToken] = {
			token = pendingAutoSellToken,
			displayRarity = autoSellRarity,
			ownedRecord = ownedRecord,
			grantPayload = cloneRollGrantPayload(grantPayload),
			reservation = reservedGrant,
		}
	elseif skipPresentation and autoSellEnabledForRarity then
		local sold, sellMessage = sellReservedBodyPartRecord(player, ownedRecord)
		if sold then
			autoSoldInstantly = true
			StatsService:RecordAutoSellOutcome(player, "sold")
			rollMessage = sellMessage or string.format("Auto-sold %s.", finalResult.Name)
		else
			Logger.Warn(string.format(
				"[RollService] Immediate auto-sell failed for %s (%s): %s",
				player.Name,
				tostring(ownedRecord.ownedId),
				tostring(sellMessage)
			))
			rollMessage = string.format("Auto-sell failed for %s; item kept.", finalResult.Name)
		end
	end
	StatsService:RecordRollSuccess(player, {
		rollTypeId = selectedRollType.id,
		rollRegion = selectedRollRegion,
		displayRarity = autoSellRarity,
		setId = finalSet.setId,
		mutationId = mutationData.id,
		sizeId = sizeData.id,
		displayedDenominator = finalSet.displayedDenominator,
		pieceId = finalPiece.id,
		variantMultiplier = variantMultiplier,
		serialNumber = ownedRecord.serialNumber,
		didDiscoverPieceFirstTime = didDiscoverPieceFirstTime,
		pendingAutoSell = pendingAutoSell,
	})
	local shouldPlayCutscene, cutsceneTier =
		resolveCutscenePlayback(player, finalSet.setId, finalSet.setConfig.rollDisplay.rarity)
	local rollResult = {
		finalResult = finalResult,
		ownedRecord = ownedRecord,
		ownedId = ownedRecord.ownedId,
		pendingAutoSellToken = pendingAutoSellToken,
		pendingAutoSell = pendingAutoSell,
		autoSoldInstantly = autoSoldInstantly,
		autoEquipped = autoEquipped,
		autoCraftCommitted = autoCraftCommitted,
		autoCrafted = typeof(autoCraftCommitResult) == "table" and autoCraftCommitResult.crafted == true,
		autoCraftMessage = if autoCraftCommitted then rollMessage else nil,
		skipPreview = skipPreview,
		skipPresentation = skipPresentation,
		autoSellRarity = if (pendingAutoSell or autoSoldInstantly) then autoSellRarity else nil,
		rollTypeId = selectedRollType.id,
		rollRegion = selectedRollRegion,
		moneySpent = selectedRollType.moneyCost,
		remainingMoney = remainingMoney,
		bonuses = bonuses,
		baseTotalLuck = luckState.baseLuck,
		totalLuck = luckState.rawLuck,
		baseRawLuck = luckState.baseLuck,
		rawLuck = luckState.rawLuck,
		bandLuckScalar = luckState.bandLuckScalar,
		bandLuckInput = luckState.bandLuckInput,
		bonusLuck = luckState.bonusLuck,
		potionLuck = luckState.potionLuck,
		potionLuckMultiplier = luckState.potionLuckMultiplier,
		loadoutLuckMultiplier = luckState.loadoutLuckMultiplier,
		vipLuck = luckState.vipLuck,
		equippedLuckMultiplier = luckState.equippedLuckMultiplier,
		usedPityBoost = luckState.useBonusRoll,
		usedBonusRoll = luckState.useBonusRoll,
		successfulRollCount = updatedSuccessfulRollCount,
		rollsSinceLuckyRoll = RollMath.GetBonusChargeProgress(updatedSuccessfulRollCount, RollingConfig.BonusInterval),
		luckyRollGoal = RollingConfig.BonusInterval,
		luckBoostReady = RollMath.IsBonusReady(updatedSuccessfulRollCount, RollingConfig.BonusInterval),
		nextRollWillUseBonus = RollMath.IsBonusRoll(updatedSuccessfulRollCount, RollingConfig.BonusInterval),
		setResult = {
			setId = finalSet.setId,
			displayName = finalSet.setConfig.rollDisplay.displayName,
			displayOddsDenominator = finalSet.displayedDenominator,
			displayRarity = finalSet.setConfig.rollDisplay.rarity,
		},
		shouldPlayCutscene = shouldPlayCutscene,
		cutsceneTier = cutsceneTier,
		cutsceneSetId = finalSet.setId,
		mutationResult = mutationData,
		sizeResult = {
			id = sizeData.id,
			displayName = sizeData.displayName,
			minScale = sizeData.minScale,
			maxScale = sizeData.maxScale,
			moneyMultiplier = sizeMoneyMultiplier,
			scale = sizeScale,
		},
		variantMultiplier = variantMultiplier,
		finalPassiveIncomePerSecond = finalPassiveIncomePerSecond,
	}
	TutorialService:RecordRollResult(player, rollResult)

	rollLocks[player] = nil
	local completionState = self:GetRollCompletionDeltaState(player, rollMessage)
	local clientRollResult = buildClientRollResult(rollResult)
	ChatNotificationService:AnnounceRareRoll(player, rollResult)
	PerfStats.Measure("PerformRoll", startedAt, {
		payload = clientRollResult,
		detail = string.format("%s:ok", player.Name),
	})
	return true, rollMessage, clientRollResult, completionState
end

local function handleGetState(player: Player)
	return response(true, "Loaded rolling state.", RollService:GetRollingState(player))
end

local function handleSelectRollType(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Select roll payload must be a table.", RollService:GetRollingState(player))
	end

	local ok, message = RollService:SelectRollType(player, payload.rollTypeId)
	return response(ok, message, RollService:GetRollingState(player))
end

local function handleSelectRollRegion(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Select roll region payload must be a table.", RollService:GetRollingState(player))
	end

	local ok, message = RollService:SelectRollRegion(player, payload.rollRegion)
	return response(ok, message, RollService:GetRollingState(player))
end

local function handleToggleQuickRoll(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Quick Roll payload must be a table.", RollService:GetRollingState(player))
	end

	local ok, message = RollService:ToggleQuickRoll(player, payload.enabled == true)
	return response(ok, message, RollService:GetRollingState(player))
end

local function handleToggleAutoEquipBest(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Auto Equip Best payload must be a table.", RollService:GetRollingState(player))
	end

	local ok, message = RollService:ToggleAutoEquipBest(player, payload.enabled == true)
	return response(ok, message, RollService:GetRollingState(player))
end

local function handleToggleAutoSellRarity(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Auto-sell payload must be a table.", RollService:GetRollingState(player))
	end

	local ok, message = RollService:ToggleAutoSellRarity(player, payload.rarity, payload.enabled == true)
	return response(ok, message, RollService:GetRollingState(player))
end

local function handleToggleCutsceneRarity(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Cutscene payload must be a table.", RollService:GetRollingState(player))
	end

	local ok, message = RollService:ToggleCutsceneRarity(player, payload.rarity, payload.enabled ~= false)
	return response(ok, message, RollService:GetRollingState(player))
end

local function handleFinalizeAutoSellRoll(player: Player, payload: any)
	local ok, message = RollService:FinalizeAutoSellRoll(player, payload)
	return response(ok, message, RollService:GetRollingDeltaState(player, message))
end

local function handlePromptQuickRollPurchase(player: Player)
	local ok, message = RollService:PromptQuickRollPurchase(player)
	return response(ok, message, RollService:GetRollingState(player))
end

local function handlePerformRoll(player: Player, payload: any)
	local ok, message, rollResult, completionState = RollService:PerformRoll(player, payload)
	return response(ok, message, completionState or RollService:GetRollingDeltaState(player, message), rollResult)
end

function RollService:OnStart()
	if not isRollingEnabled() then
		destroyRollingRemotes()
		return
	end

	getStateRemote = ensureRemoteFunction(getStateRemote, GET_STATE_REMOTE_NAME)
	selectRollTypeRemote = ensureRemoteFunction(selectRollTypeRemote, SELECT_ROLL_TYPE_REMOTE_NAME)
	selectRollRegionRemote = ensureRemoteFunction(selectRollRegionRemote, SELECT_ROLL_REGION_REMOTE_NAME)
	performRollRemote = ensureRemoteFunction(performRollRemote, PERFORM_ROLL_REMOTE_NAME)
	toggleQuickRollRemote = ensureRemoteFunction(toggleQuickRollRemote, TOGGLE_QUICK_ROLL_REMOTE_NAME)
	toggleAutoEquipBestRemote = ensureRemoteFunction(toggleAutoEquipBestRemote, TOGGLE_AUTO_EQUIP_BEST_REMOTE_NAME)
	toggleAutoSellRarityRemote = ensureRemoteFunction(toggleAutoSellRarityRemote, TOGGLE_AUTO_SELL_RARITY_REMOTE_NAME)
	toggleCutsceneRarityRemote = ensureRemoteFunction(toggleCutsceneRarityRemote, TOGGLE_CUTSCENE_RARITY_REMOTE_NAME)
	finalizeAutoSellRollRemote = ensureRemoteFunction(finalizeAutoSellRollRemote, FINALIZE_AUTO_SELL_ROLL_REMOTE_NAME)
	promptQuickRollPurchaseRemote = ensureRemoteFunction(promptQuickRollPurchaseRemote, PROMPT_QUICK_ROLL_PURCHASE_REMOTE_NAME)
	updatedRemote = ensureUpdatedRemote()

	getStateRemote.OnServerInvoke = function(player: Player)
		local allowed = RequestLimiter:Allow(player, "remote.roll.get_state")
		if not allowed then
			return buildRateLimitResponse("You're refreshing the rolling state too quickly.", self:GetRollingState(player))
		end

		local ok, result = pcall(function()
			return handleGetState(player)
		end)
		if ok then
			return result
		end

		Logger.Warn(string.format("[RollService] GetRollingState failed for %s: %s", player.Name, tostring(result)))
		return response(false, "Failed to load rolling state.", self:GetRollingState(player))
	end
	selectRollTypeRemote.OnServerInvoke = function(player: Player, payload: any)
		local allowed = RequestLimiter:Allow(player, "remote.roll.select_type")
		if not allowed then
			return buildRateLimitResponse("You're changing roll types too quickly.", self:GetRollingState(player))
		end

		local ok, result = pcall(function()
			return handleSelectRollType(player, payload)
		end)
		if ok then
			return result
		end

		Logger.Warn(string.format("[RollService] SelectRollType failed for %s: %s", player.Name, tostring(result)))
		return response(false, "Failed to select the roll type.", self:GetRollingState(player))
	end
	selectRollRegionRemote.OnServerInvoke = function(player: Player, payload: any)
		local allowed = RequestLimiter:Allow(player, "remote.roll.select_region")
		if not allowed then
			return buildRateLimitResponse("You're changing roll regions too quickly.", self:GetRollingState(player))
		end

		local ok, result = pcall(function()
			return handleSelectRollRegion(player, payload)
		end)
		if ok then
			return result
		end

		Logger.Warn(string.format("[RollService] SelectRollRegion failed for %s: %s", player.Name, tostring(result)))
		return response(false, "Failed to select the roll region.", self:GetRollingState(player))
	end
	toggleQuickRollRemote.OnServerInvoke = function(player: Player, payload: any)
		local allowed = RequestLimiter:Allow(player, "remote.roll.quick_roll")
		if not allowed then
			return buildRateLimitResponse("You're toggling Quick Roll too quickly.", self:GetRollingState(player))
		end

		local ok, result = pcall(function()
			return handleToggleQuickRoll(player, payload)
		end)
		if ok then
			return result
		end

		Logger.Warn(string.format("[RollService] ToggleQuickRoll failed for %s: %s", player.Name, tostring(result)))
		return response(false, "Failed to update Quick Roll.", self:GetRollingState(player))
	end
	toggleAutoEquipBestRemote.OnServerInvoke = function(player: Player, payload: any)
		local allowed = RequestLimiter:Allow(player, "remote.roll.auto_equip_best")
		if not allowed then
			return buildRateLimitResponse("You're toggling Auto Equip Best too quickly.", self:GetRollingState(player))
		end

		local ok, result = pcall(function()
			return handleToggleAutoEquipBest(player, payload)
		end)
		if ok then
			return result
		end

		Logger.Warn(string.format("[RollService] ToggleAutoEquipBest failed for %s: %s", player.Name, tostring(result)))
		return response(false, "Failed to update Auto Equip Best.", self:GetRollingState(player))
	end
	toggleAutoSellRarityRemote.OnServerInvoke = function(player: Player, payload: any)
		local allowed = RequestLimiter:Allow(player, "remote.roll.auto_sell")
		if not allowed then
			return buildRateLimitResponse("You're updating auto-sell too quickly.", self:GetRollingState(player))
		end

		local ok, result = pcall(function()
			return handleToggleAutoSellRarity(player, payload)
		end)
		if ok then
			return result
		end

		Logger.Warn(string.format("[RollService] ToggleAutoSellRarity failed for %s: %s", player.Name, tostring(result)))
		return response(false, "Failed to update auto-sell.", self:GetRollingState(player))
	end
	toggleCutsceneRarityRemote.OnServerInvoke = function(player: Player, payload: any)
		local allowed = RequestLimiter:Allow(player, "remote.roll.cutscene")
		if not allowed then
			return buildRateLimitResponse("You're updating cutscene settings too quickly.", self:GetRollingState(player))
		end

		local ok, result = pcall(function()
			return handleToggleCutsceneRarity(player, payload)
		end)
		if ok then
			return result
		end

		Logger.Warn(string.format("[RollService] ToggleCutsceneRarity failed for %s: %s", player.Name, tostring(result)))
		return response(false, "Failed to update cutscenes.", self:GetRollingState(player))
	end
	finalizeAutoSellRollRemote.OnServerInvoke = function(player: Player, payload: any)
		local allowed = RequestLimiter:Allow(player, "remote.roll.finalize_auto_sell")
		if not allowed then
			return buildRateLimitResponse("You're finalizing auto-sell too quickly.", self:GetRollingState(player))
		end

		local ok, result = pcall(function()
			return handleFinalizeAutoSellRoll(player, payload)
		end)
		if ok then
			return result
		end

		Logger.Warn(string.format("[RollService] FinalizeAutoSellRoll failed for %s: %s", player.Name, tostring(result)))
		return response(false, "Failed to finalize auto-sell.", self:GetRollingState(player))
	end
	promptQuickRollPurchaseRemote.OnServerInvoke = function(player: Player)
		local allowed = RequestLimiter:Allow(player, "remote.roll.prompt_quick_roll")
		if not allowed then
			return buildRateLimitResponse("You're opening the Quick Roll prompt too quickly.", self:GetRollingState(player))
		end

		local ok, result = pcall(function()
			return handlePromptQuickRollPurchase(player)
		end)
		if ok then
			return result
		end

		Logger.Warn(string.format("[RollService] PromptQuickRollPurchase failed for %s: %s", player.Name, tostring(result)))
		return response(false, "Failed to open the Quick Roll purchase prompt.", self:GetRollingState(player))
	end
	performRollRemote.OnServerInvoke = function(player: Player, payload: any)
		local allowed = RequestLimiter:Allow(player, "remote.roll.perform")
		if not allowed then
			return response(false, "You're rolling too quickly.", self:GetRollingState(player))
		end

		local ok, result = pcall(function()
			return handlePerformRoll(player, payload)
		end)
		if ok then
			return result
		end

		rollLocks[player] = nil
		StatsService:RecordRollFailure(player, "unexpected_error")
		Logger.Warn(string.format("[RollService] PerformRoll failed for %s: %s", player.Name, tostring(result)))
		return response(false, "The roll failed on the server.", self:GetRollingState(player))
	end

	PurchaseReceiptService.PurchaseProcessed:Connect(function(player: Player, key: string)
		if key == "quick_roll" then
			self:NotifyClient(player, "Quick Roll unlocked.")
		end
	end)

	PurchaseReceiptService.OwnedPassesReady:Connect(function(player: Player, ownedKeys)
		if ownedKeys["quick_roll"] then
			self:NotifyClient(player)
		end
	end)

	if BodyPartService.LoadoutChanged and not loadoutChangedConnection then
		loadoutChangedConnection = BodyPartService.LoadoutChanged:Connect(function(player: Player)
			self:NotifyClient(player)
		end)
	end

	if PotionService.StateChanged and not potionStateChangedConnection then
		potionStateChangedConnection = PotionService.StateChanged:Connect(function(player: Player)
			self:NotifyClient(player)
		end)
	end
end

function RollService:OnPlayerRemoving(player: Player)
	rollLocks[player] = nil
	rollCooldownUntilByPlayer[player] = nil
	adminLuckOverridesByPlayer[player] = nil

	local pendingState = pendingAutoSellByPlayer[player]
	if pendingState then
		for pendingKey, pendingEntry in pairs(pendingState) do
			if typeof(pendingEntry) == "table" and pendingEntry.ownedRecord ~= nil then
				local sold = sellReservedBodyPartRecord(player, pendingEntry.ownedRecord)
				if sold then
					StatsService:RecordAutoSellOutcome(player, "sold")
				end
			elseif not isOwnedIdEquipped(player, pendingKey) then
				BodyPartService:SellOwnedBodyPart(player, pendingKey)
			end
		end
	end

	pendingAutoSellByPlayer[player] = nil
end

return RollService
