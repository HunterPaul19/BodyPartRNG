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
local BodyPartService = require(script.Parent.BodyPartService)
local DataService = require(script.Parent.DataService)
local PotionService = require(script.Parent.PotionService)
local PurchaseReceiptService = require(script.Parent.PurchaseReceiptService)
local StatsService = require(script.Parent.StatsService)

local REMOTES_FOLDER_NAME = "Remotes"
local ROLLING_FOLDER_NAME = "Rolling"
local GET_STATE_REMOTE_NAME = "GetRollingState"
local SELECT_ROLL_TYPE_REMOTE_NAME = "SelectRollType"
local SELECT_ROLL_REGION_REMOTE_NAME = "SelectRollRegion"
local PERFORM_ROLL_REMOTE_NAME = "PerformRoll"
local TOGGLE_QUICK_ROLL_REMOTE_NAME = "ToggleQuickRoll"
local TOGGLE_AUTO_SELL_RARITY_REMOTE_NAME = "ToggleAutoSellRarity"
local FINALIZE_AUTO_SELL_ROLL_REMOTE_NAME = "FinalizeAutoSellRoll"
local PROMPT_QUICK_ROLL_PURCHASE_REMOTE_NAME = "PromptQuickRollPurchase"
local UPDATED_REMOTE_NAME = "RollingUpdated"
local BASE_ROLL_COOLDOWN = 1
local ROLLING_FEATURE_ID = "rolling"

local remotesFolder: Folder? = nil
local rollingRemotesFolder: Folder? = nil
local getStateRemote: RemoteFunction? = nil
local selectRollTypeRemote: RemoteFunction? = nil
local selectRollRegionRemote: RemoteFunction? = nil
local performRollRemote: RemoteFunction? = nil
local toggleQuickRollRemote: RemoteFunction? = nil
local toggleAutoSellRarityRemote: RemoteFunction? = nil
local finalizeAutoSellRollRemote: RemoteFunction? = nil
local promptQuickRollPurchaseRemote: RemoteFunction? = nil
local updatedRemote: RemoteEvent? = nil
local rollLocks: { [Player]: boolean } = {}
local pendingAutoSellByPlayer: { [Player]: { [string]: { displayRarity: string, ownedId: string } } } = {}
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
		autoSellRarities = RollingConfig.CreateDefaultAutoSellState(),
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
	toggleAutoSellRarityRemote = nil
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

local function buildAutoSellState(player: Player)
	return DataService:GetAutoSellRarities(player)
end

local function getEffectiveBonuses(player: Player)
	local loadoutBonuses = BodyPartService:GetComputedLoadoutBonuses(player)
	local potionBonuses = PotionService:GetRuntimeBonuses(player)

	return {
		passiveIncomePerSecond = tonumber(loadoutBonuses.passiveIncomePerSecond) or 0,
		luckBonus = (tonumber(loadoutBonuses.luckBonus) or 0) + (tonumber(potionBonuses.luckBonus) or 0),
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

local function getPendingAutoSellState(player: Player): { [string]: { displayRarity: string, ownedId: string } }
	local pendingState = pendingAutoSellByPlayer[player]
	if pendingState then
		return pendingState
	end

	pendingState = {}
	pendingAutoSellByPlayer[player] = pendingState
	return pendingState
end

local function clearPendingAutoSell(player: Player, ownedId: string)
	local pendingState = pendingAutoSellByPlayer[player]
	if not pendingState then
		return
	end

	pendingState[ownedId] = nil
	if next(pendingState) == nil then
		pendingAutoSellByPlayer[player] = nil
	end
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

local function computeLuckState(player: Player, rollTypeConfig, successfulRollCount: number)
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
	local vipMultiplier = if isVipOwned then RollingConfig.VipMultiplier else 1
	local bonusLuck = (baseLuck * bonusRollMultiplier) + specialLuckBonus
	local vipLuck = bonusLuck * vipMultiplier
	local rawLuck = vipLuck

	return {
		machineLuck = machineLuck,
		basicLuckBonus = basicLuckBonus,
		baseLuck = baseLuck,
		bonusRollMultiplier = bonusRollMultiplier,
		specialLuckBonus = specialLuckBonus,
		vipMultiplier = vipMultiplier,
		bonusLuck = bonusLuck,
		vipLuck = vipLuck,
		equippedLuckMultiplier = equippedLuckMultiplier,
		rawLuck = rawLuck,
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

	if shouldPlayCutscene and not RollCutsceneConfig.IsAlwaysPlaySetId(setId) then
		local didMarkSeen = DataService:MarkBundleCutsceneSeen(player, setId)
		if not didMarkSeen then
			warn(string.format("[RollService] Failed to persist seen cutscene state for %s on set %s.", player.Name, setId))
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

local function rollMutation(randomSource: Random, mutationChanceBonusById: any)
	return chooseVariantEntry(randomSource, getAdjustedMutationEntries(mutationChanceBonusById)) or MutationConfig.GetDefault()
end

local function rollSize(randomSource: Random)
	local sizeData = chooseVariantEntry(randomSource, SizeConfig.GetOrdered()) or SizeConfig.GetDefault()
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
			luckState.vipLuck = luckState.bonusLuck * luckState.vipMultiplier
			luckState.rawLuck = luckState.vipLuck
		end
		if options.forceVipOwned ~= nil then
			luckState.isVipOwned = options.forceVipOwned == true
			luckState.vipMultiplier = if luckState.isVipOwned then RollingConfig.VipMultiplier else 1
			luckState.vipLuck = luckState.bonusLuck * luckState.vipMultiplier
			luckState.rawLuck = luckState.vipLuck
		end
	end

	local entries, activeEntries, bandLuckSummary = buildRollListEntries(luckState.rawLuck)
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

function RollService:GetRollingState(player: Player, message: string?)
	if not isRollingEnabled() then
		return buildUnavailableRollingState(message)
	end

	local rollTypeEntries, selectedRollTypeId = buildRollTypeState(player)
	local rollRegionEntries, selectedRollRegion, selectedRollRegionIcon = buildRollRegionState(player)
	local selectedRollType = RollTypes.Get(selectedRollTypeId) or RollTypes.GetDefault()
	local successfulRollCount = DataService:GetSuccessfulRollCount(player)
	local quickRollState = buildQuickRollState(player)
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
		vipLuck = luckState.vipLuck,
		equippedLuckMultiplier = luckState.equippedLuckMultiplier,
		isVipOwned = luckState.isVipOwned,
		bonusInterval = RollingConfig.BonusInterval,
		bonusMultiplier = RollingConfig.BonusMultiplier,
		vipMultiplier = RollingConfig.VipMultiplier,
		nextRollNumber = luckState.nextRollNumber,
		potionBonuses = potionBonuses,
		quickRoll = quickRollState,
		effectiveRollCooldown = effectiveRollCooldown,
		autoSellRarities = buildAutoSellState(player),
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
		vipLuck = luckState.vipLuck,
		equippedLuckMultiplier = luckState.equippedLuckMultiplier,
		isVipOwned = luckState.isVipOwned,
		bonusInterval = RollingConfig.BonusInterval,
		bonusMultiplier = RollingConfig.BonusMultiplier,
		vipMultiplier = RollingConfig.VipMultiplier,
		nextRollNumber = luckState.nextRollNumber,
		quickRoll = quickRollState,
		effectiveRollCooldown = effectiveRollCooldown,
		autoSellRarities = buildAutoSellState(player),
		message = message,
	})
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

function RollService:FinalizeAutoSellRoll(player: Player, payload: any): (boolean, string)
	if not isRollingEnabled() then
		return false, getRollingUnavailableMessage()
	end

	if typeof(payload) ~= "table" then
		return false, "Finalize auto-sell payload must be a table."
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

	clearPendingAutoSell(player, ownedId)

	if payload.keep == true or isOwnedIdEquipped(player, ownedId) then
		StatsService:RecordAutoSellOutcome(player, "kept")
		return true, string.format("Kept %s roll result.", pendingEntry.displayRarity)
	end

	local sold, sellMessage = BodyPartService:SellOwnedBodyPart(player, ownedId)
	if not sold then
		return false, sellMessage or "Failed to auto-sell the roll result."
	end
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

function RollService:PerformRoll(player: Player, payload: any?): (boolean, string, any?)
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
	local quickRollApplied = buildQuickRollState(player).enabled == true
	local triggerSource = if typeof(payload) == "table" and payload.triggerSource == "auto" then "auto" else "manual"
	local skipPresentation = quickRollApplied and triggerSource == "auto"
	local skipPreview = quickRollApplied and triggerSource ~= "auto"
	local _, activeEntries = buildRollListEntries(luckState.rawLuck)
	local randomSource = Random.new()
	local finalSet = chooseWeightedSet(randomSource, activeEntries)
	if not finalSet then
		rollLocks[player] = nil
		StatsService:RecordRollFailure(player, "missing_config")
		PerfStats.Measure("PerformRoll", startedAt, {
			detail = string.format("%s:missing_set", player.Name),
		})
		return false, "No body part sets are configured for rolling.", nil
	end

	local finalPiece = choosePieceFromSetForRegion(randomSource, finalSet.setId, selectedRollRegion)
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
	local sizeData, sizeScale = rollSize(randomSource)
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

	local ownedRecord, grantError = DataService:AddOwnedBodyPart(player, {
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
	})
	if not ownedRecord then
		StatsService:RecordRollFailure(player, "grant_failed")
		DataService:AddMoney(player, selectedRollType.moneyCost, "other")
		rollLocks[player] = nil
		PerfStats.Measure("PerformRoll", startedAt, {
			detail = string.format("%s:grant_failed", player.Name),
		})
		return false, grantError or "Failed to save the rolled body part.", nil
	end

	local updatedSuccessfulRollCount = DataService:IncrementSuccessfulRollCount(player)
	local autoSellRarity = RollingConfig.NormalizeDisplayRarity(finalSet.setConfig.rollDisplay.rarity)
	local autoSellEnabledForRarity = DataService:IsAutoSellEnabledForRarity(player, autoSellRarity)
	local pendingAutoSell = (not skipPresentation) and autoSellEnabledForRarity
	local autoSoldInstantly = false
	local rollMessage = string.format("Rolled %s.", finalResult.Name)
	if pendingAutoSell then
		getPendingAutoSellState(player)[ownedRecord.ownedId] = {
			displayRarity = autoSellRarity,
			ownedId = ownedRecord.ownedId,
		}
	elseif skipPresentation and autoSellEnabledForRarity then
		local sold, sellMessage = BodyPartService:SellOwnedBodyPart(player, ownedRecord.ownedId)
		if sold then
			autoSoldInstantly = true
			StatsService:RecordAutoSellOutcome(player, "sold")
			rollMessage = sellMessage or string.format("Auto-sold %s.", finalResult.Name)
		else
			warn(string.format(
				"[RollService] Immediate auto-sell failed for %s (%s): %s",
				player.Name,
				ownedRecord.ownedId,
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
		pendingAutoSell = pendingAutoSell,
		autoSoldInstantly = autoSoldInstantly,
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
		bonusLuck = luckState.bonusLuck,
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

	rollLocks[player] = nil
	self:NotifyClient(player, rollMessage)
	PerfStats.Measure("PerformRoll", startedAt, {
		payload = rollResult,
		detail = string.format("%s:ok", player.Name),
	})
	return true, rollMessage, rollResult
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

local function handleToggleAutoSellRarity(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Auto-sell payload must be a table.", RollService:GetRollingState(player))
	end

	local ok, message = RollService:ToggleAutoSellRarity(player, payload.rarity, payload.enabled == true)
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
	local ok, message, rollResult = RollService:PerformRoll(player, payload)
	return response(ok, message, RollService:GetRollingDeltaState(player, message), rollResult)
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
	toggleAutoSellRarityRemote = ensureRemoteFunction(toggleAutoSellRarityRemote, TOGGLE_AUTO_SELL_RARITY_REMOTE_NAME)
	finalizeAutoSellRollRemote = ensureRemoteFunction(finalizeAutoSellRollRemote, FINALIZE_AUTO_SELL_ROLL_REMOTE_NAME)
	promptQuickRollPurchaseRemote = ensureRemoteFunction(promptQuickRollPurchaseRemote, PROMPT_QUICK_ROLL_PURCHASE_REMOTE_NAME)
	updatedRemote = ensureUpdatedRemote()

	getStateRemote.OnServerInvoke = function(player: Player)
		local ok, result = pcall(function()
			return handleGetState(player)
		end)
		if ok then
			return result
		end

		warn(string.format("[RollService] GetRollingState failed for %s: %s", player.Name, tostring(result)))
		return response(false, "Failed to load rolling state.", self:GetRollingState(player))
	end
	selectRollTypeRemote.OnServerInvoke = function(player: Player, payload: any)
		local ok, result = pcall(function()
			return handleSelectRollType(player, payload)
		end)
		if ok then
			return result
		end

		warn(string.format("[RollService] SelectRollType failed for %s: %s", player.Name, tostring(result)))
		return response(false, "Failed to select the roll type.", self:GetRollingState(player))
	end
	selectRollRegionRemote.OnServerInvoke = function(player: Player, payload: any)
		local ok, result = pcall(function()
			return handleSelectRollRegion(player, payload)
		end)
		if ok then
			return result
		end

		warn(string.format("[RollService] SelectRollRegion failed for %s: %s", player.Name, tostring(result)))
		return response(false, "Failed to select the roll region.", self:GetRollingState(player))
	end
	toggleQuickRollRemote.OnServerInvoke = function(player: Player, payload: any)
		local ok, result = pcall(function()
			return handleToggleQuickRoll(player, payload)
		end)
		if ok then
			return result
		end

		warn(string.format("[RollService] ToggleQuickRoll failed for %s: %s", player.Name, tostring(result)))
		return response(false, "Failed to update Quick Roll.", self:GetRollingState(player))
	end
	toggleAutoSellRarityRemote.OnServerInvoke = function(player: Player, payload: any)
		local ok, result = pcall(function()
			return handleToggleAutoSellRarity(player, payload)
		end)
		if ok then
			return result
		end

		warn(string.format("[RollService] ToggleAutoSellRarity failed for %s: %s", player.Name, tostring(result)))
		return response(false, "Failed to update auto-sell.", self:GetRollingState(player))
	end
	finalizeAutoSellRollRemote.OnServerInvoke = function(player: Player, payload: any)
		local ok, result = pcall(function()
			return handleFinalizeAutoSellRoll(player, payload)
		end)
		if ok then
			return result
		end

		warn(string.format("[RollService] FinalizeAutoSellRoll failed for %s: %s", player.Name, tostring(result)))
		return response(false, "Failed to finalize auto-sell.", self:GetRollingState(player))
	end
	promptQuickRollPurchaseRemote.OnServerInvoke = function(player: Player)
		local ok, result = pcall(function()
			return handlePromptQuickRollPurchase(player)
		end)
		if ok then
			return result
		end

		warn(string.format("[RollService] PromptQuickRollPurchase failed for %s: %s", player.Name, tostring(result)))
		return response(false, "Failed to open the Quick Roll purchase prompt.", self:GetRollingState(player))
	end
	performRollRemote.OnServerInvoke = function(player: Player, payload: any)
		local ok, result = pcall(function()
			return handlePerformRoll(player, payload)
		end)
		if ok then
			return result
		end

		rollLocks[player] = nil
		StatsService:RecordRollFailure(player, "unexpected_error")
		warn(string.format("[RollService] PerformRoll failed for %s: %s", player.Name, tostring(result)))
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

	local pendingState = pendingAutoSellByPlayer[player]
	if pendingState then
		for ownedId in pairs(pendingState) do
			if not isOwnedIdEquipped(player, ownedId) then
				BodyPartService:SellOwnedBodyPart(player, ownedId)
			end
		end
	end

	pendingAutoSellByPlayer[player] = nil
end

return RollService
