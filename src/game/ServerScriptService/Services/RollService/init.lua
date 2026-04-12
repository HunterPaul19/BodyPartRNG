local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Globals = require(ReplicatedStorage.Lists.Globals)
local RollTypes = require(ReplicatedStorage.Shared.Config.RollTypes)
local RollTargetRegions = require(ReplicatedStorage.Shared.Character.RollTargetRegions)
local BodyPartIcons = require(ReplicatedStorage.Shared.Config.BodyPartIcons)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local RollingConfig = require(ReplicatedStorage.Shared.Config.RollingConfig)
local SizeConfig = require(ReplicatedStorage.Shared.Config.SizeConfig)
local RollMath = require(ReplicatedStorage.Shared.Rolling.RollMath)
local BodyPartService = require(script.Parent.BodyPartService)
local DataService = require(script.Parent.DataService)
local PurchaseReceiptService = require(script.Parent.PurchaseReceiptService)

local REMOTES_FOLDER_NAME = "Remotes"
local ROLLING_FOLDER_NAME = "Rolling"
local GET_STATE_REMOTE_NAME = "GetRollingState"
local SELECT_ROLL_TYPE_REMOTE_NAME = "SelectRollType"
local SELECT_ROLL_REGION_REMOTE_NAME = "SelectRollRegion"
local PERFORM_ROLL_REMOTE_NAME = "PerformRoll"
local TOGGLE_QUICK_ROLL_REMOTE_NAME = "ToggleQuickRoll"
local PROMPT_QUICK_ROLL_PURCHASE_REMOTE_NAME = "PromptQuickRollPurchase"
local UPDATED_REMOTE_NAME = "RollingUpdated"
local PREVIEW_SEQUENCE_LENGTH = 10

local remotesFolder: Folder? = nil
local rollingRemotesFolder: Folder? = nil
local getStateRemote: RemoteFunction? = nil
local selectRollTypeRemote: RemoteFunction? = nil
local selectRollRegionRemote: RemoteFunction? = nil
local performRollRemote: RemoteFunction? = nil
local toggleQuickRollRemote: RemoteFunction? = nil
local promptQuickRollPurchaseRemote: RemoteFunction? = nil
local updatedRemote: RemoteEvent? = nil
local rollLocks: { [Player]: boolean } = {}

local RollService = {}

local function getQuickRollPassConfig()
	return PurchaseReceiptService.RobuxPurchases.Passes.quick_roll
end

local function response(ok: boolean, message: string, state: any?, rollResult: any?)
	return {
		ok = ok,
		message = message,
		state = state,
		rollResult = rollResult,
	}
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

	if passConfig and passConfig.id then
		owned = PurchaseReceiptService:HasPass(player, passConfig.key or passConfig.id)
		enabled = owned and DataService:GetQuickRollEnabled(player)
	end

	return {
		owned = owned,
		enabled = enabled,
		passId = passConfig and passConfig.id or nil,
	}
end

local function computeLuckState(player: Player, rollTypeConfig, successfulRollCount: number)
	local bonuses = BodyPartService:GetComputedLoadoutBonuses(player)
	local equippedLuckBonus = math.max(0, tonumber(bonuses.luckBonus) or 0)
	local useBonusRoll = RollMath.IsBonusRoll(successfulRollCount, RollingConfig.BonusInterval)
	local isVipOwned = DataService:GetVipOwned(player)
	local machineLuck = math.max(0.05, tonumber(rollTypeConfig.luckMultiplier) or 1)
	local bonusLuck = if useBonusRoll then machineLuck * RollingConfig.BonusMultiplier else machineLuck
	local vipLuck = bonusLuck * (if isVipOwned then RollingConfig.VipMultiplier else 1)
	local equippedLuckMultiplier = math.max(0.05, 1 + equippedLuckBonus)
	local rawLuck = vipLuck * equippedLuckMultiplier

	return {
		machineLuck = machineLuck,
		bonusLuck = bonusLuck,
		vipLuck = vipLuck,
		equippedLuckMultiplier = equippedLuckMultiplier,
		rawLuck = rawLuck,
		useBonusRoll = useBonusRoll,
		isVipOwned = isVipOwned,
		successfulRollCount = successfulRollCount,
		nextRollNumber = successfulRollCount + 1,
		rollsSinceBonusRoll = successfulRollCount % RollingConfig.BonusInterval,
	}, bonuses
end

local function buildAdjustedRollEntries(rawLuck: number)
	local adjustedEntries = table.create(#BodyPartsCatalog.GetRollEntries())

	for index, rollEntry in ipairs(BodyPartsCatalog.GetRollEntries()) do
		local rarityEffectiveness = RollingConfig.GetRarityEffectiveness(rollEntry.rollDisplay.rarity)
		local effectiveLuck = RollMath.GetEffectiveLuck(rawLuck, rarityEffectiveness)
		local adjustedWeight = RollMath.GetAdjustedWeight(rollEntry.baseChance, effectiveLuck)
		adjustedEntries[index] = {
			setId = rollEntry.id,
			setConfig = rollEntry,
			displayedDenominator = rollEntry.displayedDenominator,
			baseChance = rollEntry.baseChance,
			rarityEffectiveness = rarityEffectiveness,
			effectiveLuck = effectiveLuck,
			adjustedWeight = adjustedWeight,
		}
	end

	local normalizedEntries, totalWeight = RollMath.NormalizeWeights(adjustedEntries, function(entry)
		return entry.adjustedWeight
	end)

	return normalizedEntries, totalWeight
end

local function chooseWeightedSet(randomSource: Random, adjustedEntries)
	return RollMath.ChooseWeighted(randomSource, adjustedEntries, function(entry)
		return entry.adjustedWeight
	end)
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

local function chooseVariantEntry(randomSource: Random, orderedEntries)
	return RollMath.ChooseWeighted(randomSource, orderedEntries, function(entry)
		return entry.weight
	end)
end

local function rollMutation(randomSource: Random)
	return chooseVariantEntry(randomSource, MutationConfig.GetOrdered()) or MutationConfig.GetDefault()
end

local function rollSize(randomSource: Random)
	return chooseVariantEntry(randomSource, SizeConfig.GetOrdered()) or SizeConfig.GetDefault()
end

local function createRollDisplayEntry(piece, resultData): (any?, string?)
	local setConfig = BodyPartsCatalog.GetSetForPiece(piece.id)
	if not setConfig then
		return nil, string.format("Missing set config for piece '%s'.", piece.id)
	end

	local bundleModel = BodyPartsCatalog.ResolveBundleModel(piece.id)
	if not bundleModel then
		return nil, string.format("Missing bundle model for piece '%s'.", piece.id)
	end

	local rollDisplay = setConfig.rollDisplay
	local mutationData = resultData and resultData.mutationData or MutationConfig.GetDefault()
	local sizeData = resultData and resultData.sizeData or SizeConfig.GetDefault()
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
		Model = bundleModel,
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
		SizeMultiplier = sizeData.multiplier,
		VariantMultiplier = tonumber(resultData and resultData.variantMultiplier) or 1,
		EffectiveRawLuck = tonumber(resultData and resultData.rawLuck) or nil,
		IsBonusRoll = resultData and resultData.useBonusRoll == true or false,
	}, nil
end

local function buildPreviewSequence(randomSource: Random, adjustedEntries, rollRegion: string, finalPiece, finalResultData): (any?, string?)
	local previewSequence = table.create(PREVIEW_SEQUENCE_LENGTH)

	for index = 1, PREVIEW_SEQUENCE_LENGTH - 1 do
		local previewSet = chooseWeightedSet(randomSource, adjustedEntries)
		if not previewSet then
			return nil, "Preview roll failed because no body part sets were available."
		end

		local previewPiece = choosePieceFromSetForRegion(randomSource, previewSet.setId, rollRegion)
		if not previewPiece then
			return nil, string.format("Preview roll failed because set '%s' has no pieces for region '%s'.", previewSet.setId, rollRegion)
		end

		local previewEntry, previewError = createRollDisplayEntry(previewPiece, {
			rawLuck = finalResultData.rawLuck,
			useBonusRoll = finalResultData.useBonusRoll,
		})
		if not previewEntry then
			return nil, previewError
		end

		previewSequence[index] = previewEntry
	end

	local finalEntry, finalError = createRollDisplayEntry(finalPiece, finalResultData)
	if not finalEntry then
		return nil, finalError
	end

	previewSequence[PREVIEW_SEQUENCE_LENGTH] = finalEntry
	return previewSequence, nil
end

local function summarizeProbabilityTable(adjustedEntries)
	local lines = {}
	local maxLines = math.min(5, #adjustedEntries)

	for index = 1, maxLines do
		local entry = adjustedEntries[index]
		local rollDisplay = entry.setConfig.rollDisplay
		table.insert(
			lines,
			string.format(
				"%s | 1/%s shown | %.4f%% hidden",
				rollDisplay.displayName,
				Globals.formatNumber(entry.displayedDenominator, false, true),
				(entry.probability or 0) * 100
			)
		)
	end

	return table.concat(lines, " | ")
end

function RollService:GetProbabilityDebug(player: Player, options: any?)
	local selectedRollTypeId = if typeof(options) == "table" and typeof(options.rollTypeId) == "string" then options.rollTypeId else DataService:GetSelectedRollType(player)
	local rollType = RollTypes.Get(selectedRollTypeId) or RollTypes.GetDefault()
	local successfulRollCount = DataService:GetSuccessfulRollCount(player)
	local luckState, bonuses = computeLuckState(player, rollType, successfulRollCount)

	if typeof(options) == "table" then
		if options.forceBonusRoll == true then
			luckState.useBonusRoll = true
			luckState.bonusLuck = luckState.machineLuck * RollingConfig.BonusMultiplier
			luckState.vipLuck = luckState.bonusLuck * (if luckState.isVipOwned then RollingConfig.VipMultiplier else 1)
			luckState.rawLuck = luckState.vipLuck * luckState.equippedLuckMultiplier
		end
		if options.forceVipOwned ~= nil then
			luckState.isVipOwned = options.forceVipOwned == true
			luckState.vipLuck = luckState.bonusLuck * (if luckState.isVipOwned then RollingConfig.VipMultiplier else 1)
			luckState.rawLuck = luckState.vipLuck * luckState.equippedLuckMultiplier
		end
	end

	local adjustedEntries = buildAdjustedRollEntries(luckState.rawLuck)
	table.sort(adjustedEntries, function(a, b)
		if a.probability ~= b.probability then
			return a.probability > b.probability
		end
		return a.displayedDenominator < b.displayedDenominator
	end)

	return {
		rollTypeId = rollType.id,
		rollTypeDisplayName = rollType.displayName,
		rawLuck = luckState.rawLuck,
		machineLuck = luckState.machineLuck,
		bonusLuck = luckState.bonusLuck,
		vipLuck = luckState.vipLuck,
		equippedLuckMultiplier = luckState.equippedLuckMultiplier,
		useBonusRoll = luckState.useBonusRoll,
		isVipOwned = luckState.isVipOwned,
		bonusInterval = RollingConfig.BonusInterval,
		bonusMultiplier = RollingConfig.BonusMultiplier,
		vipMultiplier = RollingConfig.VipMultiplier,
		bonuses = bonuses,
		entries = adjustedEntries,
		summary = summarizeProbabilityTable(adjustedEntries),
	}
end

function RollService:GetRollingState(player: Player, message: string?)
	local rollTypeEntries, selectedRollTypeId = buildRollTypeState(player)
	local rollRegionEntries, selectedRollRegion, selectedRollRegionIcon = buildRollRegionState(player)
	local selectedRollType = RollTypes.Get(selectedRollTypeId) or RollTypes.GetDefault()
	local successfulRollCount = DataService:GetSuccessfulRollCount(player)
	local luckState, bonuses = computeLuckState(player, selectedRollType, successfulRollCount)
	local baseTotalLuck = luckState.machineLuck * luckState.equippedLuckMultiplier

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
		willUsePityBoost = luckState.useBonusRoll,
		willUseBonusRoll = luckState.useBonusRoll,
		baseTotalLuck = baseTotalLuck,
		totalLuck = luckState.rawLuck,
		baseRawLuck = luckState.machineLuck,
		rawLuck = luckState.rawLuck,
		bonusLuck = luckState.bonusLuck,
		vipLuck = luckState.vipLuck,
		equippedLuckMultiplier = luckState.equippedLuckMultiplier,
		isVipOwned = luckState.isVipOwned,
		bonusInterval = RollingConfig.BonusInterval,
		bonusMultiplier = RollingConfig.BonusMultiplier,
		vipMultiplier = RollingConfig.VipMultiplier,
		nextRollNumber = luckState.nextRollNumber,
		quickRoll = buildQuickRollState(player),
		message = message,
	}
end

function RollService:NotifyClient(player: Player, message: string?)
	ensureUpdatedRemote():FireClient(player, self:GetRollingState(player, message))
end

function RollService:SelectRollType(player: Player, rollTypeId: string): (boolean, string)
	local rollType = RollTypes.Get(rollTypeId)
	if not rollType then
		return false, "That roll type does not exist."
	end

	local ok, message = DataService:SetSelectedRollType(player, rollTypeId)
	if not ok then
		return false, message or "Failed to select the roll type."
	end

	return true, string.format("Selected %s.", rollType.displayName)
end

function RollService:SelectRollRegion(player: Player, rollRegion: string): (boolean, string)
	local ok, message = DataService:SetSelectedRollRegion(player, rollRegion)
	if not ok then
		return false, message or "Failed to select the roll region."
	end

	local iconEntry = BodyPartIcons[rollRegion]
	return true, string.format("Selected %s.", if iconEntry then iconEntry.buttonName else rollRegion)
end

function RollService:ToggleQuickRoll(player: Player, enabled: boolean): (boolean, string)
	local quickRollState = buildQuickRollState(player)
	if not quickRollState.owned then
		return false, "Quick Roll requires the gamepass."
	end

	local ok, message = DataService:SetQuickRollEnabled(player, enabled == true)
	if not ok then
		return false, message or "Failed to update Quick Roll."
	end

	return true, if enabled then "Quick Roll enabled." else "Quick Roll disabled."
end

function RollService:PromptQuickRollPurchase(player: Player): (boolean, string)
	local passConfig = getQuickRollPassConfig()
	if not passConfig or not passConfig.id then
		return false, "Quick Roll is not configured."
	end

	local ok, message = PurchaseReceiptService:PromptPassPurchase(player, passConfig.key or "quick_roll")
	if not ok then
		return false, message or "Failed to open the Quick Roll purchase prompt."
	end

	return true, message or "Purchase prompt opened."
end

function RollService:PerformRoll(player: Player): (boolean, string, any?)
	if rollLocks[player] then
		return false, "A roll is already in progress.", nil
	end

	rollLocks[player] = true

	local selectedRollTypeId = DataService:GetSelectedRollType(player)
	local selectedRollType = RollTypes.Get(selectedRollTypeId)
	local selectedRollRegion = DataService:GetSelectedRollRegion(player)
	if not selectedRollType then
		rollLocks[player] = nil
		return false, "No valid roll type is selected.", nil
	end

	local currentMoney = DataService:GetMoney(player)
	if currentMoney < selectedRollType.moneyCost then
		rollLocks[player] = nil
		return false, string.format("You need %s more money to use %s.", Globals.formatNumber(selectedRollType.moneyCost - currentMoney, false, true), selectedRollType.displayName), nil
	end

	local successfulRollCount = DataService:GetSuccessfulRollCount(player)
	local luckState, bonuses = computeLuckState(player, selectedRollType, successfulRollCount)
	local adjustedEntries = buildAdjustedRollEntries(luckState.rawLuck)
	local randomSource = Random.new()
	local finalSet = chooseWeightedSet(randomSource, adjustedEntries)
	if not finalSet then
		rollLocks[player] = nil
		return false, "No body part sets are configured for rolling.", nil
	end

	local finalPiece = choosePieceFromSetForRegion(randomSource, finalSet.setId, selectedRollRegion)
	if not finalPiece then
		rollLocks[player] = nil
		return false, string.format("No body parts are configured for %s rolls.", selectedRollRegion), nil
	end

	local mutationData = rollMutation(randomSource)
	local sizeData = rollSize(randomSource)
	local variantMultiplier = RollMath.ComputeVariantMultiplier(mutationData.multiplier, sizeData.multiplier)
	local finalPassiveIncomePerSecond = RollMath.ComputeFinalPassiveIncome(finalPiece.passiveIncomePerSecond, variantMultiplier)
	local finalResultData = {
		mutationData = mutationData,
		sizeData = sizeData,
		variantMultiplier = variantMultiplier,
		finalPassiveIncomePerSecond = finalPassiveIncomePerSecond,
		rawLuck = luckState.rawLuck,
		useBonusRoll = luckState.useBonusRoll,
	}

	local previewSequence, previewError = buildPreviewSequence(randomSource, adjustedEntries, selectedRollRegion, finalPiece, finalResultData)
	if not previewSequence then
		rollLocks[player] = nil
		return false, previewError or "Failed to build the roll preview sequence.", nil
	end

	local remainingMoney = currentMoney - selectedRollType.moneyCost
	DataService:Set(player, "money", remainingMoney)

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
		sizeMultiplier = sizeData.multiplier,
		variantMultiplier = variantMultiplier,
		finalPassiveIncomePerSecond = finalPassiveIncomePerSecond,
	})
	if not ownedRecord then
		DataService:Set(player, "money", currentMoney)
		rollLocks[player] = nil
		return false, grantError or "Failed to save the rolled body part.", nil
	end

	local updatedSuccessfulRollCount = DataService:IncrementSuccessfulRollCount(player)
	local finalResult = previewSequence[#previewSequence]
	local rollResult = {
		previewSequence = previewSequence,
		finalResult = finalResult,
		ownedRecord = ownedRecord,
		rollTypeId = selectedRollType.id,
		rollRegion = selectedRollRegion,
		moneySpent = selectedRollType.moneyCost,
		remainingMoney = remainingMoney,
		bonuses = bonuses,
		baseTotalLuck = luckState.machineLuck * luckState.equippedLuckMultiplier,
		totalLuck = luckState.rawLuck,
		baseRawLuck = luckState.machineLuck,
		rawLuck = luckState.rawLuck,
		bonusLuck = luckState.bonusLuck,
		vipLuck = luckState.vipLuck,
		equippedLuckMultiplier = luckState.equippedLuckMultiplier,
		usedPityBoost = luckState.useBonusRoll,
		usedBonusRoll = luckState.useBonusRoll,
		successfulRollCount = updatedSuccessfulRollCount,
		rollsSinceLuckyRoll = updatedSuccessfulRollCount % RollingConfig.BonusInterval,
		luckyRollGoal = RollingConfig.BonusInterval,
		nextRollWillUseBonus = RollMath.IsBonusRoll(updatedSuccessfulRollCount, RollingConfig.BonusInterval),
		setResult = {
			setId = finalSet.setId,
			displayName = finalSet.setConfig.rollDisplay.displayName,
			displayOddsDenominator = finalSet.displayedDenominator,
			displayRarity = finalSet.setConfig.rollDisplay.rarity,
		},
		mutationResult = mutationData,
		sizeResult = sizeData,
		variantMultiplier = variantMultiplier,
		finalPassiveIncomePerSecond = finalPassiveIncomePerSecond,
	}

	rollLocks[player] = nil
	self:NotifyClient(player, string.format("Rolled %s.", finalResult.Name))
	return true, string.format("Rolled %s.", finalResult.Name), rollResult
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

local function handlePromptQuickRollPurchase(player: Player)
	local ok, message = RollService:PromptQuickRollPurchase(player)
	return response(ok, message, RollService:GetRollingState(player))
end

local function handlePerformRoll(player: Player)
	local ok, message, rollResult = RollService:PerformRoll(player)
	return response(ok, message, RollService:GetRollingState(player), rollResult)
end

function RollService:OnStart()
	getStateRemote = ensureRemoteFunction(getStateRemote, GET_STATE_REMOTE_NAME)
	selectRollTypeRemote = ensureRemoteFunction(selectRollTypeRemote, SELECT_ROLL_TYPE_REMOTE_NAME)
	selectRollRegionRemote = ensureRemoteFunction(selectRollRegionRemote, SELECT_ROLL_REGION_REMOTE_NAME)
	performRollRemote = ensureRemoteFunction(performRollRemote, PERFORM_ROLL_REMOTE_NAME)
	toggleQuickRollRemote = ensureRemoteFunction(toggleQuickRollRemote, TOGGLE_QUICK_ROLL_REMOTE_NAME)
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
	performRollRemote.OnServerInvoke = function(player: Player)
		local ok, result = pcall(function()
			return handlePerformRoll(player)
		end)
		if ok then
			return result
		end

		rollLocks[player] = nil
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
end

function RollService:OnPlayerRemoving(player: Player)
	rollLocks[player] = nil
end

return RollService
