local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Globals = require(ReplicatedStorage.Lists.Globals)
local Schema = require(ReplicatedStorage.Lists.Schema)
local Signal = require(ReplicatedStorage.Common.Signal)
local NumberFormatter = require(ReplicatedStorage.Shared.Formatting.NumberFormatter)
local BodyPartLoadout = require(ReplicatedStorage.Shared.Character.BodyPartLoadout)
local OwnedAccessories = require(ReplicatedStorage.Shared.Character.OwnedAccessories)
local OwnedAuras = require(ReplicatedStorage.Shared.Character.OwnedAuras)
local OwnedBodyParts = require(ReplicatedStorage.Shared.Character.OwnedBodyParts)
local OwnedCraftingMaterials = require(ReplicatedStorage.Shared.Character.OwnedCraftingMaterials)
local CraftingProgress = require(ReplicatedStorage.Shared.Character.CraftingProgress)
local OwnedPotions = require(ReplicatedStorage.Shared.Character.OwnedPotions)
local OwnedRollTypes = require(ReplicatedStorage.Shared.Character.OwnedRollTypes)
local RollTargetRegions = require(ReplicatedStorage.Shared.Character.RollTargetRegions)
local TimeShardState = require(ReplicatedStorage.Shared.Character.TimeShardState)
local DailyChestState = require(ReplicatedStorage.Shared.Character.DailyChestState)
local TutorialState = require(ReplicatedStorage.Shared.Character.TutorialState)
local PlayerStats = require(ReplicatedStorage.Shared.Stats.PlayerStats)
local AchievementState = require(ReplicatedStorage.Shared.Titles.AchievementState)
local AccessoryConfig = require(ReplicatedStorage.Shared.Config.AccessoryConfig)
local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local BodyPartLegacyIds = require(ReplicatedStorage.Shared.Config.BodyParts.LegacyIds)
local CraftingMaterialConfig = require(ReplicatedStorage.Shared.Config.CraftingMaterialConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local PotionConfig = require(ReplicatedStorage.Shared.Config.PotionConfig)
local RollingConfig = require(ReplicatedStorage.Shared.Config.RollingConfig)
local RollTypes = require(ReplicatedStorage.Shared.Config.RollTypes)
local SizeConfig = require(ReplicatedStorage.Shared.Config.SizeConfig)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)
local ProfileService = require(ServerScriptService.Packages.ProfileService)
local ReplicaService = require(ServerScriptService.Packages.ReplicaService)
local AuraSerialStore = require(script.AuraSerialStore)
local BodyPartSerialStore = require(script.BodyPartSerialStore)
local Leaderboards = require(script.Leaderboards)

local SCOPE = Globals.SCOPE
local DEBUG = false and RunService:IsStudio()
local USE_MOCK_DATA_IN_STUDIO = false
local PROFILE_CLASS_TOKEN = ReplicaService.NewClassToken(SCOPE)
local TIME_PLAYED_FLUSH_INTERVAL = 30
local LOBBY_ROLL_REGION_RESET_PROFILE_IDS = table.freeze({
	main = true,
	boss_lobby = true,
})

local LEGACY_CASH_KEY = "cash"
local LEGACY_OWNED_ROLL_TYPES_KEY = "ownedRollTypes"
local MONEY_KEY = Schema.Money and Schema.Money.key or nil
local TIME_PLAYED_KEY = Schema.TimePlayed and Schema.TimePlayed.key or nil
local TIME_SHARDS_KEY = Schema.TimeShards and Schema.TimeShards.key or nil
local DAILY_CHESTS_KEY = Schema.DailyChests and Schema.DailyChests.key or nil
local TUTORIAL_KEY = Schema.Tutorial and Schema.Tutorial.key or nil
local DIAGNOSTICS_KEY = Schema.Diagnostics and Schema.Diagnostics.key or nil
local STATS_KEY = Schema.Stats and Schema.Stats.key or nil
local BODY_PARTS_KEY = Schema.BodyParts and Schema.BodyParts.key or nil
local AURAS_KEY = Schema.Auras and Schema.Auras.key or nil
local ACCESSORIES_KEY = Schema.Accessories and Schema.Accessories.key or nil
local EQUIPPED_ACCESSORIES_KEY = Schema.EquippedAccessories and Schema.EquippedAccessories.key or nil
local CRAFTING_MATERIALS_KEY = Schema.CraftingMaterials and Schema.CraftingMaterials.key or nil
local CRAFTING_PROGRESS_KEY = Schema.CraftingProgress and Schema.CraftingProgress.key or nil
local POTIONS_KEY = Schema.Potions and Schema.Potions.key or nil
local EQUIPPED_LOADOUT_KEY = Schema.EquippedLoadout and Schema.EquippedLoadout.key or nil
local SUCCESSFUL_ROLL_COUNT_KEY = Schema.SuccessfulRollCount and Schema.SuccessfulRollCount.key or nil
local EQUIPPED_TITLE_ID_KEY = Schema.EquippedTitleId and Schema.EquippedTitleId.key or nil
local EQUIPPED_AURA_ID_KEY = Schema.EquippedAuraId and Schema.EquippedAuraId.key or nil
local ACHIEVEMENTS_KEY = Schema.Achievements and Schema.Achievements.key or nil
local VIP_OWNED_KEY = Schema.VipOwned and Schema.VipOwned.key or nil
local VIP_PLUS_OWNED_KEY = Schema.VipPlusOwned and Schema.VipPlusOwned.key or nil
local SELECTED_ROLL_TYPE_KEY = Schema.SelectedRollType and Schema.SelectedRollType.key or nil
local SELECTED_ROLL_REGION_KEY = Schema.SelectedRollRegion and Schema.SelectedRollRegion.key or nil
local QUICK_ROLL_ENABLED_KEY = Schema.QuickRollEnabled and Schema.QuickRollEnabled.key or nil
local AUTO_EQUIP_BEST_ENABLED_KEY = Schema.AutoEquipBestEnabled and Schema.AutoEquipBestEnabled.key or nil
local AUTO_SIZE_ENABLED_KEY = Schema.AutoSizeEnabled and Schema.AutoSizeEnabled.key or nil
local MUSIC_ENABLED_KEY = Schema.MusicEnabled and Schema.MusicEnabled.key or nil
local AUTO_SELL_RARITIES_KEY = Schema.AutoSellRarities and Schema.AutoSellRarities.key or nil
local CUTSCENE_RARITIES_KEY = Schema.CutsceneRarities and Schema.CutsceneRarities.key or nil

local ATTR_BY_KEY: { [string]: string } = {}
if MONEY_KEY then
	ATTR_BY_KEY[MONEY_KEY] = "Money"
end
if TIME_PLAYED_KEY then
	ATTR_BY_KEY[TIME_PLAYED_KEY] = "TimePlayed"
end
if EQUIPPED_TITLE_ID_KEY then
	ATTR_BY_KEY[EQUIPPED_TITLE_ID_KEY] = "EquippedTitleId"
end
if EQUIPPED_AURA_ID_KEY then
	ATTR_BY_KEY[EQUIPPED_AURA_ID_KEY] = "EquippedAuraId"
end

local PROFILES: { [Player]: any } = {}
local REPLICAS: { [Player]: any } = {}
local timePlayedSessionStartedAt: { [Player]: number } = {}
local timePlayedLastFlushAt: { [Player]: number } = {}
local timePlayedLoopStarted = false
local serialShutdownFlushBound = false

local GlobalUpdateProcessed = Signal.new()
local PlayerDataLoaded = Signal.new()
local PlayerDataRemoving = Signal.new()
local DataChanged = Signal.new()
local MoneyChanged = Signal.new()
local SuccessfulRollIncremented = Signal.new()
local TimePlayedFlushed = Signal.new()
local OwnedBodyPartAdded = Signal.new()
local BodyPartPieceDiscovered = Signal.new()
local OwnedAuraAdded = Signal.new()
local EquippedTitleChanged = Signal.new()
local EquippedAuraChanged = Signal.new()

local function toNonNegativeWhole(value: any): number
	return math.max(0, math.floor(tonumber(value) or 0))
end

local function formatMoneyLeaderstat(value: any): string
	return "$" .. NumberFormatter.Format(math.max(0, math.round(tonumber(value) or 0)))
end

local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, child in value do
		copy[key] = deepCopy(child)
	end
	return copy
end

local function getKey(userId: number): string
	return "Player_" .. userId
end

local function isSchemaEntry(value: any): boolean
	return typeof(value) == "table" and value.key ~= nil and value.value ~= nil
end

local function isSchemaContainer(value: any): boolean
	if typeof(value) ~= "table" then
		return false
	end

	local sawAny = false
	for _, child in pairs(value) do
		sawAny = true
		if not isSchemaEntry(child) then
			return false
		end
	end

	return sawAny
end

local function buildStructureFromSchema(schema: any): any
	if not isSchemaContainer(schema) then
		return deepCopy(schema)
	end

	local result = {}
	for _, entry in pairs(schema) do
		local key = entry.key
		local value = entry.value

		if isSchemaEntry(value) then
			result[key] = buildStructureFromSchema({ value })
		elseif isSchemaContainer(value) then
			result[key] = buildStructureFromSchema(value)
		else
			result[key] = deepCopy(value)
		end
	end

	return result
end

local function normalizeOptionalString(value: any): string
	if typeof(value) ~= "string" then
		return ""
	end

	local trimmed = string.match(value, "%S.*")
	if not trimmed or trimmed == "" then
		return ""
	end

	return trimmed
end

local function normalizeOptionalAuraId(value: any): string
	local normalized = normalizeOptionalString(value)
	if normalized == "" then
		return ""
	end

	return AuraConfig.NormalizeId(normalized) or ""
end

local function createLeaderstats(player: Player, profile: any)
	if not MONEY_KEY and not SUCCESSFUL_ROLL_COUNT_KEY then
		return
	end

	local existing = player:FindFirstChild("leaderstats")
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	folder.Parent = player

	if MONEY_KEY then
		local value = Instance.new("StringValue")
		value.Name = "money"
		value.Value = formatMoneyLeaderstat(profile.Data[MONEY_KEY])
		value.Parent = folder
	end

	if SUCCESSFUL_ROLL_COUNT_KEY then
		local rollsValue = Instance.new("IntValue")
		rollsValue.Name = "Rolls"
		rollsValue.Value = toNonNegativeWhole(profile.Data[SUCCESSFUL_ROLL_COUNT_KEY])
		rollsValue.Parent = folder
	end
end

local function updateLeaderstatsMoney(player: Player, moneyValue: number)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		return
	end

	local money = stats:FindFirstChild("money")
	if money and money:IsA("StringValue") then
		money.Value = formatMoneyLeaderstat(moneyValue)
	end
end

local function updateLeaderstatsRolls(player: Player, rollCount: number)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		return
	end

	local rolls = stats:FindFirstChild("Rolls")
	if rolls and rolls:IsA("IntValue") then
		rolls.Value = toNonNegativeWhole(rollCount)
	end
end

local function processGlobalUpdates(player: Player, profile: any)
	local globalUpdates = profile.GlobalUpdates

	local function handleLocked(id: number, data: any)
		GlobalUpdateProcessed:Fire(player, profile, data)
		globalUpdates:ClearLockedUpdate(id)
	end

	for _, update in globalUpdates:GetActiveUpdates() do
		globalUpdates:LockActiveUpdate(update[1])
	end

	for _, update in globalUpdates:GetLockedUpdates() do
		handleLocked(update[1], update[2])
	end

	globalUpdates:ListenToNewActiveUpdate(function(id: number)
		globalUpdates:LockActiveUpdate(id)
	end)

	globalUpdates:ListenToNewLockedUpdate(handleLocked)
end

local function createReplica(player: Player, profile: any)
	local replica = ReplicaService.NewReplica({
		ClassToken = PROFILE_CLASS_TOKEN,
		Tags = { Player = player },
		Data = profile.Data,
		Replication = player,
	})

	REPLICAS[player] = replica
end

local function getActiveProfile(player: Player)
	local profile = PROFILES[player]
	if profile and profile:IsActive() then
		return profile
	end
	return nil
end

local function getActiveReplica(player: Player)
	local replica = REPLICAS[player]
	if replica and replica:IsActive() then
		return replica
	end
	return nil
end

local function getReplicaValue(player: Player, key: string)
	local replica = getActiveReplica(player)
	if replica and typeof(replica.Data) == "table" then
		return replica.Data[key]
	end

	return nil
end

local function buildPathArray(key: string, path: { any }?): { any }
	local pathArray = table.create(1 + if typeof(path) == "table" then #path else 0)
	pathArray[1] = key

	if typeof(path) == "table" then
		for index, value in ipairs(path) do
			pathArray[index + 1] = value
		end
	end

	return pathArray
end

local cloneOwnedBodyPartsState

local function setReplicaPathValue(player: Player, key: string, path: { any }?, value: any): boolean
	local replica = getActiveReplica(player)
	if not replica then
		return false
	end

	replica:SetValue(buildPathArray(key, path), value)
	return true
end

local function setReplicaPathValues(player: Player, key: string, path: { any }?, values: { [any]: any }): boolean
	local replica = getActiveReplica(player)
	if not replica then
		return false
	end

	replica:SetValues(buildPathArray(key, path), values)
	return true
end

local function markBodyPartPieceDiscovered(player: Player, currentBodyPartsState: any, pieceId: string): boolean
	if not BODY_PARTS_KEY then
		return false
	end

	local discoveredPieceIds = if typeof(currentBodyPartsState) == "table"
		then currentBodyPartsState.discoveredPieceIds
		else nil
	if typeof(discoveredPieceIds) == "table" and discoveredPieceIds[pieceId] == true then
		return false
	end

	if not setReplicaPathValue(player, BODY_PARTS_KEY, { "discoveredPieceIds", pieceId }, true) then
		return false
	end

	BodyPartPieceDiscovered:Fire(player, pieceId, cloneOwnedBodyPartsState(getReplicaValue(player, BODY_PARTS_KEY)))
	return true
end

local function waitForActiveReplica(player: Player, timeoutSeconds: number?): any
	local replica = getActiveReplica(player)
	if replica then
		return replica
	end

	local timeoutAt = os.clock() + (timeoutSeconds or 15)
	while os.clock() < timeoutAt do
		if player.Parent ~= Players then
			return nil
		end

		replica = getActiveReplica(player)
		if replica then
			return replica
		end

		task.wait()
	end

	return nil
end

local function syncPlayerStateForKey(player: Player, key: string, value: any)
	local attributeName = ATTR_BY_KEY[key]
	if attributeName then
		if key == EQUIPPED_TITLE_ID_KEY or key == EQUIPPED_AURA_ID_KEY then
			local normalizedId = if key == EQUIPPED_AURA_ID_KEY
				then normalizeOptionalAuraId(value)
				else normalizeOptionalString(value)
			player:SetAttribute(attributeName, if normalizedId ~= "" then normalizedId else nil)
		else
			player:SetAttribute(attributeName, value)
		end
	end

	if MONEY_KEY and key == MONEY_KEY then
		updateLeaderstatsMoney(player, tonumber(value) or 0)
	elseif SUCCESSFUL_ROLL_COUNT_KEY and key == SUCCESSFUL_ROLL_COUNT_KEY then
		updateLeaderstatsRolls(player, tonumber(value) or 0)
	end
end

local DataService = {}
DataService.GlobalUpdateProcessed = GlobalUpdateProcessed
DataService.PlayerDataLoaded = PlayerDataLoaded
DataService.PlayerDataRemoving = PlayerDataRemoving
DataService.DataChanged = DataChanged
DataService.MoneyChanged = MoneyChanged
DataService.SuccessfulRollIncremented = SuccessfulRollIncremented
DataService.TimePlayedFlushed = TimePlayedFlushed
DataService.OwnedBodyPartAdded = OwnedBodyPartAdded
DataService.BodyPartPieceDiscovered = BodyPartPieceDiscovered
DataService.OwnedAuraAdded = OwnedAuraAdded
DataService.EquippedTitleChanged = EquippedTitleChanged
DataService.EquippedAuraChanged = EquippedAuraChanged

function DataService:IsPlayerDataLoaded(player: Player): boolean
	return getActiveProfile(player) ~= nil and getActiveReplica(player) ~= nil
end

local function isPositiveFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value > 0 and value == value and value < math.huge and value > -math.huge
end

local function clampWholeNumber(value: any, minimum: number?): number
	local floored = math.floor(tonumber(value) or 0)
	if minimum ~= nil then
		return math.max(minimum, floored)
	end

	return floored
end

local function normalizeMutationSnapshot(record: any): (string, string, number)
	local mutationId = MutationConfig.NormalizeId(record and (record.mutationId or record.mutation))
	local mutationDisplayName = MutationConfig.GetDisplayName(mutationId)
	local mutationMultiplier = MutationConfig.GetMultiplier(mutationId)

	return mutationId, mutationDisplayName, mutationMultiplier
end

local function normalizeSizeSnapshot(record: any): (string, number, number)
	local scale = tonumber(record and record.sizeMultiplier)
	if scale ~= nil and scale > 0 then
		local normalizedScale = SizeConfig.NormalizeScale(scale, record and record.sizeId)
		local entry = SizeConfig.GetByScale(normalizedScale) or SizeConfig.GetDefault()
		return entry.id, normalizedScale, entry.moneyMultiplier
	end

	local sizeId = SizeConfig.NormalizeId(record and record.sizeId)
	local sizeScale = SizeConfig.GetRepresentativeScale(sizeId)
	local sizeEntry = SizeConfig.Get(sizeId) or SizeConfig.GetDefault()
	return sizeEntry.id, sizeScale, sizeEntry.moneyMultiplier
end

local function normalizeOwnedBodyPartRecord(record: any, fallbackOwnedId: string?): OwnedBodyParts.OwnedBodyPartRecord?
	if typeof(record) ~= "table" then
		return nil
	end

	local originalPieceId = if typeof(record.pieceId) == "string" then record.pieceId else nil
	local pieceId = BodyPartLegacyIds.NormalizePieceId(record.pieceId)
	if pieceId == nil then
		return nil
	end

	local piece = BodyPartsCatalog.GetPiece(pieceId)
	if not piece then
		return nil
	end

	local setConfig = BodyPartsCatalog.GetSetForPiece(pieceId)
	local didMigratePieceId = originalPieceId ~= nil and pieceId ~= originalPieceId
	local legacyRolledSetId = if typeof(record.rolledSetId) == "string" and record.rolledSetId ~= ""
		then record.rolledSetId
		else nil
	local normalizedRolledSetId = BodyPartLegacyIds.NormalizeSetId(legacyRolledSetId)
	local refreshRolledSetMetadata = didMigratePieceId or normalizedRolledSetId ~= legacyRolledSetId
	local rolledSetDisplayName = if typeof(record.rolledSetDisplayName) == "string" and record.rolledSetDisplayName ~= ""
		then record.rolledSetDisplayName
		else nil
	local mutationId, mutationDisplayName, mutationMultiplier = normalizeMutationSnapshot(record)
	local sizeId, sizeMultiplier, sizeMoneyMultiplier = normalizeSizeSnapshot(record)
	local displayOddsDenominator = math.max(
		1,
		clampWholeNumber(record.displayOddsDenominator or record.rarityDenominator or (setConfig and setConfig.rollDisplay.chance) or piece.rarity, 1)
	)
	local variantMultiplier = tonumber(record.variantMultiplier)
	if variantMultiplier == nil or variantMultiplier <= 0 then
		variantMultiplier = mutationMultiplier + sizeMoneyMultiplier - 1
	end

	local finalPassiveIncomePerSecond = (tonumber(piece.passiveIncomePerSecond) or 0) * variantMultiplier

	return {
		ownedId = if typeof(record.ownedId) == "string" and record.ownedId ~= "" then record.ownedId else (fallbackOwnedId or ""),
		pieceId = pieceId,
		rarityDenominator = math.max(1, clampWholeNumber(record.rarityDenominator or displayOddsDenominator, 1)),
		rolledSetId = if refreshRolledSetMetadata and setConfig
			then setConfig.id
			else if normalizedRolledSetId ~= nil
				then normalizedRolledSetId
				else if setConfig then setConfig.id else nil,
		rolledSetDisplayName = if refreshRolledSetMetadata and setConfig
			then setConfig.rollDisplay.displayName
			else if rolledSetDisplayName ~= nil
				then rolledSetDisplayName
				else if setConfig then setConfig.rollDisplay.displayName else nil,
		displayOddsDenominator = displayOddsDenominator,
		displayRarity = if typeof(record.displayRarity) == "string" and record.displayRarity ~= ""
			then record.displayRarity
			else if setConfig then setConfig.rollDisplay.rarity else "Basic",
		mutationId = mutationId,
		mutation = mutationDisplayName,
		mutationMultiplier = mutationMultiplier,
		sizeId = sizeId,
		sizeMultiplier = sizeMultiplier,
		variantMultiplier = variantMultiplier,
		finalPassiveIncomePerSecond = finalPassiveIncomePerSecond,
		serialNumber = math.max(1, clampWholeNumber(record.serialNumber, 1)),
		isFavorite = record.isFavorite == true,
	}
end

local function normalizeOwnedAuraRecord(record: any, fallbackOwnedId: string?): OwnedAuras.OwnedAuraRecord?
	if typeof(record) ~= "table" then
		return nil
	end

	local auraId = AuraConfig.NormalizeId(record.auraId)
	if not auraId then
		return nil
	end

	return {
		ownedId = if typeof(record.ownedId) == "string" and record.ownedId ~= "" then record.ownedId else (fallbackOwnedId or ""),
		auraId = auraId,
		serialNumber = math.max(1, clampWholeNumber(record.serialNumber, 1)),
		isFavorite = record.isFavorite == true,
	}
end

local function normalizeOwnedAccessoryRecord(record: any, fallbackOwnedId: string?): OwnedAccessories.OwnedAccessoryRecord?
	if typeof(record) ~= "table" then
		return nil
	end

	local accessoryId = AccessoryConfig.NormalizeId(record.accessoryId)
	local config = accessoryId and AccessoryConfig.Get(accessoryId)
	if not config then
		return nil
	end

	local ownedId = if typeof(record.ownedId) == "string" and record.ownedId ~= "" then record.ownedId else fallbackOwnedId
	if typeof(ownedId) ~= "string" or ownedId == "" then
		return nil
	end

	return {
		ownedId = ownedId,
		accessoryId = config.id,
		slot = config.slot,
		isFavorite = record.isFavorite == true,
	}
end

cloneOwnedBodyPartsState = function(state: OwnedBodyParts.OwnedBodyPartsState?): OwnedBodyParts.OwnedBodyPartsState
	local ownedById = {}
	local discoveredPieceIds = {}
	local seenCutsceneSetIds = {}
	local nextOwnedId = 1

	if typeof(state) == "table" then
		if typeof(state.ownedById) == "table" then
			for ownedId, record in pairs(state.ownedById) do
				local normalizedRecord = normalizeOwnedBodyPartRecord(record, ownedId)
				if normalizedRecord then
					ownedById[ownedId] = normalizedRecord
					discoveredPieceIds[normalizedRecord.pieceId] = true
				end
			end
		end

		if typeof(state.discoveredPieceIds) == "table" then
			for pieceId, isDiscovered in pairs(state.discoveredPieceIds) do
				local normalizedPieceId = BodyPartLegacyIds.NormalizePieceId(pieceId)
				if isDiscovered == true and normalizedPieceId and BodyPartsCatalog.GetPiece(normalizedPieceId) then
					discoveredPieceIds[normalizedPieceId] = true
				end
			end
		end

		if typeof(state.seenCutsceneSetIds) == "table" then
			for setId, hasSeenCutscene in pairs(state.seenCutsceneSetIds) do
				local normalizedSetId = BodyPartLegacyIds.NormalizeSetId(setId)
				if hasSeenCutscene == true and normalizedSetId and BodyPartsCatalog.GetSet(normalizedSetId) then
					seenCutsceneSetIds[normalizedSetId] = true
				end
			end
		end

		if typeof(state.nextOwnedId) == "number" then
			nextOwnedId = math.max(1, math.floor(state.nextOwnedId))
		end
	end

	return {
		ownedById = ownedById,
		discoveredPieceIds = discoveredPieceIds,
		seenCutsceneSetIds = seenCutsceneSetIds,
		nextOwnedId = nextOwnedId,
	}
end

local function cloneOwnedAccessoriesState(state: OwnedAccessories.OwnedAccessoriesState?): OwnedAccessories.OwnedAccessoriesState
	local ownedById = {}
	local nextOwnedId = 1

	if typeof(state) == "table" then
		if typeof(state.ownedById) == "table" then
			for ownedId, record in pairs(state.ownedById) do
				local normalizedRecord = normalizeOwnedAccessoryRecord(record, ownedId)
				if normalizedRecord then
					ownedById[normalizedRecord.ownedId] = normalizedRecord
				end
			end
		end

		if typeof(state.nextOwnedId) == "number" then
			nextOwnedId = math.max(1, math.floor(state.nextOwnedId))
		end
	end

	return {
		ownedById = ownedById,
		nextOwnedId = nextOwnedId,
	}
end

local function cloneEquippedAccessoriesState(
	state: OwnedAccessories.EquippedAccessoriesState?,
	ownedAccessoriesState: OwnedAccessories.OwnedAccessoriesState?
): OwnedAccessories.EquippedAccessoriesState
	local equippedState = OwnedAccessories.CreateEmptyEquippedState()
	local ownedById = if typeof(ownedAccessoriesState) == "table" then ownedAccessoriesState.ownedById else nil

	if typeof(state) ~= "table" then
		return equippedState
	end

	for _, slot in ipairs(OwnedAccessories.SlotOrder) do
		local ownedId = state[slot]
		if typeof(ownedId) ~= "string" or ownedId == "" then
			continue
		end

		local ownedRecord = if typeof(ownedById) == "table" then ownedById[ownedId] else nil
		if ownedRecord and ownedRecord.slot == slot then
			equippedState[slot] = ownedId
		end
	end

	local legacyArmOwnedId = state.ArmAccessory
	if equippedState.GearAccessory == nil and typeof(legacyArmOwnedId) == "string" and legacyArmOwnedId ~= "" then
		local ownedRecord = if typeof(ownedById) == "table" then ownedById[legacyArmOwnedId] else nil
		if ownedRecord and ownedRecord.slot == "GearAccessory" then
			equippedState.GearAccessory = legacyArmOwnedId
		end
	end

	return equippedState
end

local function cloneCraftingMaterialsState(
	state: OwnedCraftingMaterials.CraftingMaterialsState?
): OwnedCraftingMaterials.CraftingMaterialsState
	local amountByMaterialId = {}

	if typeof(state) == "table" and typeof(state.amountByMaterialId) == "table" then
		for materialId, amount in pairs(state.amountByMaterialId) do
			local normalizedMaterialId = CraftingMaterialConfig.NormalizeId(materialId)
			local normalizedAmount = math.max(0, clampWholeNumber(amount, 0))
			if normalizedMaterialId and normalizedAmount > 0 then
				amountByMaterialId[normalizedMaterialId] = (amountByMaterialId[normalizedMaterialId] or 0) + normalizedAmount
			end
		end
	end

	return {
		amountByMaterialId = amountByMaterialId,
	}
end

local function cloneOwnedAurasState(state: OwnedAuras.OwnedAurasState?): OwnedAuras.OwnedAurasState
	local ownedById = {}
	local ownedAuraIdByAuraId = {}
	local nextOwnedId = 1

	if typeof(state) == "table" then
		if typeof(state.ownedById) == "table" then
			for ownedId, record in pairs(state.ownedById) do
				local normalizedRecord = normalizeOwnedAuraRecord(record, ownedId)
				if normalizedRecord and ownedAuraIdByAuraId[normalizedRecord.auraId] == nil then
					ownedById[normalizedRecord.ownedId] = normalizedRecord
					ownedAuraIdByAuraId[normalizedRecord.auraId] = normalizedRecord.ownedId
				end
			end
		end

		if typeof(state.nextOwnedId) == "number" then
			nextOwnedId = math.max(1, math.floor(state.nextOwnedId))
		end
	end

	return {
		ownedById = ownedById,
		ownedAuraIdByAuraId = ownedAuraIdByAuraId,
		nextOwnedId = nextOwnedId,
	}
end

local function normalizeOwnedPotionRecord(record: any, fallbackPotionId: string?): OwnedPotions.OwnedPotionRecord?
	if typeof(record) ~= "table" then
		return nil
	end

	local potionId = PotionConfig.NormalizeId(record.potionId or fallbackPotionId)
	if not potionId then
		return nil
	end

	local amount = math.max(0, clampWholeNumber(record.amount, 0))
	if amount <= 0 then
		return nil
	end

	return {
		potionId = potionId,
		amount = amount,
		isFavorite = record.isFavorite == true,
	}
end

local function cloneOwnedPotionsState(state: OwnedPotions.OwnedPotionsState?): OwnedPotions.OwnedPotionsState
	local ownedByPotionId = {}
	local activeByPotionId = {}

	if typeof(state) == "table" then
		if typeof(state.ownedByPotionId) == "table" then
			for potionId, record in pairs(state.ownedByPotionId) do
				local normalizedRecord = normalizeOwnedPotionRecord(record, potionId)
				if normalizedRecord then
					local existingRecord = ownedByPotionId[normalizedRecord.potionId]
					if existingRecord then
						existingRecord.amount += normalizedRecord.amount
						existingRecord.isFavorite = existingRecord.isFavorite or normalizedRecord.isFavorite
					else
						ownedByPotionId[normalizedRecord.potionId] = normalizedRecord
					end
				end
			end
		end

		if typeof(state.activeByPotionId) == "table" then
			for potionId, remainingSeconds in pairs(state.activeByPotionId) do
				local normalizedPotionId = PotionConfig.NormalizeId(potionId)
				local resolvedRemainingSeconds = math.max(0, clampWholeNumber(remainingSeconds, 0))
				if normalizedPotionId and resolvedRemainingSeconds > 0 then
					activeByPotionId[normalizedPotionId] = math.max(
						resolvedRemainingSeconds,
						tonumber(activeByPotionId[normalizedPotionId]) or 0
					)
				end
			end
		end
	end

	return {
		ownedByPotionId = ownedByPotionId,
		activeByPotionId = activeByPotionId,
	}
end

local function profileLooksPreTutorial(data: any): boolean
	if typeof(data) ~= "table" then
		return false
	end

	if SUCCESSFUL_ROLL_COUNT_KEY and (tonumber(data[SUCCESSFUL_ROLL_COUNT_KEY]) or 0) > 0 then
		return true
	end
	if MONEY_KEY and (tonumber(data[MONEY_KEY]) or 0) > (Schema.Money and Schema.Money.value or 200) then
		return true
	end
	if BODY_PARTS_KEY and OwnedBodyParts.CountOwned(data[BODY_PARTS_KEY]) > 0 then
		return true
	end
	if ACCESSORIES_KEY and OwnedAccessories.CountOwned(data[ACCESSORIES_KEY]) > 0 then
		return true
	end
	if CRAFTING_MATERIALS_KEY and OwnedCraftingMaterials.CountTotal(data[CRAFTING_MATERIALS_KEY]) > 0 then
		return true
	end
	if POTIONS_KEY
		and typeof(data[POTIONS_KEY]) == "table"
		and typeof(data[POTIONS_KEY].ownedByPotionId) == "table"
		and next(data[POTIONS_KEY].ownedByPotionId) ~= nil
	then
		return true
	end

	return false
end

local function normalizeProfileData(profile: any)
	if not profile or typeof(profile.Data) ~= "table" then
		return
	end

	local data = profile.Data

	if MONEY_KEY then
		local moneyValue = math.max(0, tonumber(data[MONEY_KEY]) or 0)
		local legacyCashValue = tonumber(data[LEGACY_CASH_KEY])
		if legacyCashValue ~= nil then
			moneyValue = math.max(moneyValue, math.max(0, legacyCashValue))
			data[LEGACY_CASH_KEY] = nil
		end
		data[MONEY_KEY] = moneyValue
	end
	if TIME_PLAYED_KEY then
		data[TIME_PLAYED_KEY] = math.max(0, clampWholeNumber(data[TIME_PLAYED_KEY], 0))
	end
	if TIME_SHARDS_KEY then
		data[TIME_SHARDS_KEY] = TimeShardState.Normalize(data[TIME_SHARDS_KEY])
	end
	if DAILY_CHESTS_KEY then
		data[DAILY_CHESTS_KEY] = DailyChestState.Normalize(data[DAILY_CHESTS_KEY])
	end

	data[LEGACY_OWNED_ROLL_TYPES_KEY] = nil
	if SELECTED_ROLL_TYPE_KEY then
		data[SELECTED_ROLL_TYPE_KEY] = OwnedRollTypes.NormalizeSelectedRollTypeId(data[SELECTED_ROLL_TYPE_KEY])
	end
	if SELECTED_ROLL_REGION_KEY then
		data[SELECTED_ROLL_REGION_KEY] = RollTargetRegions.Normalize(data[SELECTED_ROLL_REGION_KEY])
	end
	if SUCCESSFUL_ROLL_COUNT_KEY then
		data[SUCCESSFUL_ROLL_COUNT_KEY] = math.max(0, clampWholeNumber(data[SUCCESSFUL_ROLL_COUNT_KEY], 0))
	end
	if EQUIPPED_TITLE_ID_KEY then
		data[EQUIPPED_TITLE_ID_KEY] = normalizeOptionalString(data[EQUIPPED_TITLE_ID_KEY])
	end
	if EQUIPPED_AURA_ID_KEY then
		data[EQUIPPED_AURA_ID_KEY] = normalizeOptionalAuraId(data[EQUIPPED_AURA_ID_KEY])
	end
	if ACHIEVEMENTS_KEY then
		data[ACHIEVEMENTS_KEY] = AchievementState.Normalize(data[ACHIEVEMENTS_KEY])
	end
	if VIP_OWNED_KEY then
		data[VIP_OWNED_KEY] = data[VIP_OWNED_KEY] == true
	end
	if VIP_PLUS_OWNED_KEY then
		data[VIP_PLUS_OWNED_KEY] = data[VIP_PLUS_OWNED_KEY] == true
	end
	if QUICK_ROLL_ENABLED_KEY then
		data[QUICK_ROLL_ENABLED_KEY] = data[QUICK_ROLL_ENABLED_KEY] == true
	end
	if AUTO_EQUIP_BEST_ENABLED_KEY then
		data[AUTO_EQUIP_BEST_ENABLED_KEY] = data[AUTO_EQUIP_BEST_ENABLED_KEY] == true
	end
	if MUSIC_ENABLED_KEY then
		data[MUSIC_ENABLED_KEY] = data[MUSIC_ENABLED_KEY] ~= false
	end
	if AUTO_SELL_RARITIES_KEY then
		data[AUTO_SELL_RARITIES_KEY] = RollingConfig.NormalizeAutoSellState(data[AUTO_SELL_RARITIES_KEY])
	end
	if CUTSCENE_RARITIES_KEY then
		data[CUTSCENE_RARITIES_KEY] = RollingConfig.NormalizeCutsceneState(data[CUTSCENE_RARITIES_KEY])
	end
	if BODY_PARTS_KEY then
		data[BODY_PARTS_KEY] = cloneOwnedBodyPartsState(data[BODY_PARTS_KEY])
	end
	if AURAS_KEY then
		data[AURAS_KEY] = cloneOwnedAurasState(data[AURAS_KEY])
	end
	if ACCESSORIES_KEY then
		data[ACCESSORIES_KEY] = cloneOwnedAccessoriesState(data[ACCESSORIES_KEY])
	end
	if EQUIPPED_ACCESSORIES_KEY then
		data[EQUIPPED_ACCESSORIES_KEY] = cloneEquippedAccessoriesState(
			data[EQUIPPED_ACCESSORIES_KEY],
			if ACCESSORIES_KEY then data[ACCESSORIES_KEY] else nil
		)
	end
	if CRAFTING_MATERIALS_KEY then
		data[CRAFTING_MATERIALS_KEY] = cloneCraftingMaterialsState(data[CRAFTING_MATERIALS_KEY])
	end
	if CRAFTING_PROGRESS_KEY then
		data[CRAFTING_PROGRESS_KEY] = CraftingProgress.NormalizeState(data[CRAFTING_PROGRESS_KEY])
	end
	if POTIONS_KEY then
		data[POTIONS_KEY] = cloneOwnedPotionsState(data[POTIONS_KEY])
	end
	if EQUIPPED_LOADOUT_KEY then
		data[EQUIPPED_LOADOUT_KEY] = BodyPartLoadout.NormalizeEquippedState(data[EQUIPPED_LOADOUT_KEY])
	end
	if TUTORIAL_KEY then
		local tutorialState = TutorialState.Normalize(data[TUTORIAL_KEY])
		if tutorialState.completed ~= true and tutorialState.adminReplay ~= true and profileLooksPreTutorial(data) then
			tutorialState = TutorialState.CreateCompletedState()
		end
		data[TUTORIAL_KEY] = tutorialState
	end
	if STATS_KEY then
		data[STATS_KEY] = PlayerStats.Normalize(data[STATS_KEY], {
			bodyPartsState = if BODY_PARTS_KEY then data[BODY_PARTS_KEY] else nil,
			aurasState = if AURAS_KEY then data[AURAS_KEY] else nil,
			currentMoney = if MONEY_KEY then data[MONEY_KEY] else nil,
			diagnostics = if DIAGNOSTICS_KEY then data[DIAGNOSTICS_KEY] else nil,
			successfulRollCount = if SUCCESSFUL_ROLL_COUNT_KEY then data[SUCCESSFUL_ROLL_COUNT_KEY] else nil,
		})
	end
end

local function applyLobbyJoinDefaults(profile: any)
	if not SELECTED_ROLL_REGION_KEY or not profile or typeof(profile.Data) ~= "table" then
		return
	end

	local activeProfile = PlaceProfile.GetActiveProfile()
	if LOBBY_ROLL_REGION_RESET_PROFILE_IDS[activeProfile.id] ~= true then
		return
	end

	profile.Data[SELECTED_ROLL_REGION_KEY] = RollTargetRegions.FullBody
end

local function flushTimePlayedForPlayer(player: Player, force: boolean?)
	if not TIME_PLAYED_KEY then
		return
	end

	local lastFlushAt = timePlayedLastFlushAt[player]
	if not lastFlushAt then
		return
	end

	local elapsed = os.clock() - lastFlushAt
	local wholeSeconds = math.max(0, math.floor(elapsed))
	if wholeSeconds <= 0 then
		return
	end
	if not force and wholeSeconds < TIME_PLAYED_FLUSH_INTERVAL then
		return
	end

	timePlayedLastFlushAt[player] = lastFlushAt + wholeSeconds
	local previousValue = math.max(0, tonumber(DataService:Get(player, TIME_PLAYED_KEY)) or 0)
	local updatedValue = 0
	DataService:Set(player, TIME_PLAYED_KEY, function(currentValue)
		updatedValue = math.max(0, tonumber(currentValue) or 0) + wholeSeconds
		return updatedValue
	end)
	TimePlayedFlushed:Fire(player, wholeSeconds, previousValue, updatedValue)
end

local function syncProfileAttributes(player: Player, profile: any)
	if not profile or typeof(profile.Data) ~= "table" then
		return
	end

	for key in pairs(ATTR_BY_KEY) do
		syncPlayerStateForKey(player, key, profile.Data[key])
	end
end

local function startTimePlayedLoop()
	if timePlayedLoopStarted or not TIME_PLAYED_KEY then
		return
	end

	timePlayedLoopStarted = true
	task.spawn(function()
		while true do
			for _, player in ipairs(Players:GetPlayers()) do
				flushTimePlayedForPlayer(player, false)
			end
			task.wait(TIME_PLAYED_FLUSH_INTERVAL)
		end
	end)
end

local function bindSerialShutdownFlush()
	if serialShutdownFlushBound then
		return
	end

	serialShutdownFlushBound = true
	game:BindToClose(function()
		pcall(function()
			BodyPartSerialStore:FlushUnusedReservedSerials()
		end)
		pcall(function()
			AuraSerialStore:FlushUnusedReservedSerials()
		end)
	end)
end

local profileStoreName = if DEBUG then "studio" else SCOPE
local profileTemplate = buildStructureFromSchema(Schema)
local profileStore = ProfileService.GetProfileStore(profileStoreName, profileTemplate)
if RunService:IsStudio() and USE_MOCK_DATA_IN_STUDIO then
	profileStore = profileStore.Mock
end

DataService.ProfileStore = profileStore

function DataService:OnStart()
	Leaderboards.connect(self)
	task.spawn(function()
		local ok, err = pcall(function()
			Leaderboards.start(self)
		end)
		if not ok then
			Logger.Warn(string.format("[DataService] Leaderboards.start failed: %s", tostring(err)))
		end
	end)
	startTimePlayedLoop()
	bindSerialShutdownFlush()
	BodyPartSerialStore:StartExistenceRefreshLoop()
	AuraSerialStore:StartExistenceRefreshLoop()
end

function DataService:OnPlayerAdded(player: Player)
	local startedAt = os.clock()
	Logger.Print(string.format("[DataService] Loading profile for %s (%d).", player.Name, player.UserId))

	local profile = DataService.ProfileStore:LoadProfileAsync(getKey(player.UserId))
	if not profile then
		Logger.Warn(string.format("[DataService] Failed to load profile for %s (%d).", player.Name, player.UserId))
		player:Kick("Sorry! Your data did not load. Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	profile:ListenToRelease(function()
		PROFILES[player] = nil
		timePlayedSessionStartedAt[player] = nil
		timePlayedLastFlushAt[player] = nil

		local replica = REPLICAS[player]
		if replica then
			replica:Destroy()
			REPLICAS[player] = nil
		end

		if player.Parent == Players then
			player:Kick("Your data has been loaded in a different server.")
		end
	end)

	if DEBUG then
		profile.Data = buildStructureFromSchema(Schema)
	end

	normalizeProfileData(profile)
	applyLobbyJoinDefaults(profile)

	if not player:IsDescendantOf(Players) then
		profile:Release()
		return
	end

	PROFILES[player] = profile
	timePlayedSessionStartedAt[player] = os.clock()
	timePlayedLastFlushAt[player] = os.clock()

	syncProfileAttributes(player, profile)

	createReplica(player, profile)
	createLeaderstats(player, profile)
	processGlobalUpdates(player, profile)
	PlayerDataLoaded:Fire(player)
	Logger.Print(string.format(
		"[DataService] Profile ready for %s (%d) in %.2fs.",
		player.Name,
		player.UserId,
		os.clock() - startedAt
	))
	task.defer(function()
		Leaderboards.refresh(self)
	end)
end

function DataService:OnPlayerRemoving(player: Player)
	flushTimePlayedForPlayer(player, true)
	Leaderboards.flushPlayer(self, player)
	PlayerDataRemoving:Fire(player)

	local profile = PROFILES[player]
	if profile then
		profile:Release()
	end

	timePlayedSessionStartedAt[player] = nil
	timePlayedLastFlushAt[player] = nil

	task.defer(function()
		Leaderboards.refresh(self)
	end)
end

function DataService:Set(player: Player, key: string, mutator: any)
	local replica = getActiveReplica(player)
	if not replica then
		return
	end

	local currentValue = deepCopy(replica.Data[key])
	local newValue = if typeof(mutator) == "function" then mutator(currentValue) else mutator
	replica:SetValue({ key }, newValue)

	syncPlayerStateForKey(player, key, newValue)
	DataChanged:Fire(player, key, deepCopy(currentValue), deepCopy(newValue))
	if EQUIPPED_TITLE_ID_KEY and key == EQUIPPED_TITLE_ID_KEY then
		EquippedTitleChanged:Fire(
			player,
			if normalizeOptionalString(currentValue) ~= "" then normalizeOptionalString(currentValue) else nil,
			if normalizeOptionalString(newValue) ~= "" then normalizeOptionalString(newValue) else nil
		)
	end
	if EQUIPPED_AURA_ID_KEY and key == EQUIPPED_AURA_ID_KEY then
		EquippedAuraChanged:Fire(
			player,
			if normalizeOptionalAuraId(currentValue) ~= "" then normalizeOptionalAuraId(currentValue) else nil,
			if normalizeOptionalAuraId(newValue) ~= "" then normalizeOptionalAuraId(newValue) else nil
		)
	end
	return deepCopy(newValue), deepCopy(currentValue)
end

function DataService:SetNestedValue(player: Player, key: string, path: { any }, value: any): boolean
	return setReplicaPathValue(player, key, path, value)
end

function DataService:SetNestedValues(player: Player, key: string, path: { any }, values: { [any]: any }): boolean
	return setReplicaPathValues(player, key, path, values)
end

function DataService:GetOwnedBodyParts(player: Player): { [string]: OwnedBodyParts.OwnedBodyPartRecord }
	if not BODY_PARTS_KEY then
		return {}
	end

	local bodyPartsState = cloneOwnedBodyPartsState(self:Get(player, BODY_PARTS_KEY))
	return bodyPartsState.ownedById
end

function DataService:GetBodyPartsState(player: Player): OwnedBodyParts.OwnedBodyPartsState
	if not BODY_PARTS_KEY then
		return OwnedBodyParts.CreateEmptyState()
	end

	return cloneOwnedBodyPartsState(self:Get(player, BODY_PARTS_KEY))
end

function DataService:HasDiscoveredBodyPartPiece(player: Player, pieceId: string): boolean
	if not BODY_PARTS_KEY then
		return false
	end
	local normalizedPieceId = BodyPartLegacyIds.NormalizePieceId(pieceId)
	if normalizedPieceId == nil then
		return false
	end

	local bodyPartsState = getReplicaValue(player, BODY_PARTS_KEY)
	local discoveredPieceIds = if typeof(bodyPartsState) == "table" then bodyPartsState.discoveredPieceIds else nil
	return typeof(discoveredPieceIds) == "table" and discoveredPieceIds[normalizedPieceId] == true
end

function DataService:HasSeenBundleCutscene(player: Player, setId: string): boolean
	if not BODY_PARTS_KEY then
		return false
	end
	local normalizedSetId = BodyPartLegacyIds.NormalizeSetId(setId)
	if normalizedSetId == nil or BodyPartsCatalog.GetSet(normalizedSetId) == nil then
		return false
	end

	local bodyPartsState = getReplicaValue(player, BODY_PARTS_KEY)
	local seenCutsceneSetIds = if typeof(bodyPartsState) == "table" then bodyPartsState.seenCutsceneSetIds else nil
	return typeof(seenCutsceneSetIds) == "table" and seenCutsceneSetIds[normalizedSetId] == true
end

function DataService:MarkBundleCutsceneSeen(player: Player, setId: string): boolean
	if not BODY_PARTS_KEY then
		return false
	end
	if not getActiveReplica(player) then
		return false
	end

	local normalizedSetId = BodyPartLegacyIds.NormalizeSetId(setId)
	if normalizedSetId == nil or BodyPartsCatalog.GetSet(normalizedSetId) == nil then
		return false
	end

	if self:HasSeenBundleCutscene(player, normalizedSetId) then
		return true
	end

	return setReplicaPathValue(player, BODY_PARTS_KEY, { "seenCutsceneSetIds", normalizedSetId }, true)
end

function DataService:GetOwnedAuras(player: Player): { [string]: OwnedAuras.OwnedAuraRecord }
	if not AURAS_KEY then
		return {}
	end

	local aurasState = cloneOwnedAurasState(self:Get(player, AURAS_KEY))
	return aurasState.ownedById
end

function DataService:GetAurasState(player: Player): OwnedAuras.OwnedAurasState
	if not AURAS_KEY then
		return OwnedAuras.CreateEmptyState()
	end

	return cloneOwnedAurasState(self:Get(player, AURAS_KEY))
end

function DataService:GetOwnedAccessories(player: Player): { [string]: OwnedAccessories.OwnedAccessoryRecord }
	if not ACCESSORIES_KEY then
		return {}
	end

	local accessoriesState = cloneOwnedAccessoriesState(self:Get(player, ACCESSORIES_KEY))
	return accessoriesState.ownedById
end

function DataService:GetAccessoriesState(player: Player): OwnedAccessories.OwnedAccessoriesState
	if not ACCESSORIES_KEY then
		return OwnedAccessories.CreateEmptyState()
	end

	return cloneOwnedAccessoriesState(self:Get(player, ACCESSORIES_KEY))
end

function DataService:GetEquippedAccessories(player: Player): OwnedAccessories.EquippedAccessoriesState
	if not EQUIPPED_ACCESSORIES_KEY then
		return OwnedAccessories.CreateEmptyEquippedState()
	end

	return cloneEquippedAccessoriesState(self:Get(player, EQUIPPED_ACCESSORIES_KEY), self:GetAccessoriesState(player))
end

function DataService:GetCraftingMaterialsState(player: Player): OwnedCraftingMaterials.CraftingMaterialsState
	if not CRAFTING_MATERIALS_KEY then
		return OwnedCraftingMaterials.CreateEmptyState()
	end

	return cloneCraftingMaterialsState(self:Get(player, CRAFTING_MATERIALS_KEY))
end

function DataService:GetCraftingMaterialAmounts(player: Player): { [string]: number }
	return self:GetCraftingMaterialsState(player).amountByMaterialId
end

function DataService:GetCraftingProgress(player: Player): CraftingProgress.CraftingProgressState
	if not CRAFTING_PROGRESS_KEY then
		return CraftingProgress.CreateEmptyState()
	end

	return CraftingProgress.NormalizeState(self:Get(player, CRAFTING_PROGRESS_KEY))
end

function DataService:SetCraftingProgress(
	player: Player,
	state: CraftingProgress.CraftingProgressState
): (boolean, string?)
	if not CRAFTING_PROGRESS_KEY then
		return false, "Crafting progress persistence is not configured."
	end
	if not getActiveReplica(player) then
		return false, "Player data is not loaded."
	end

	self:Set(player, CRAFTING_PROGRESS_KEY, CraftingProgress.NormalizeState(state))
	return true, nil
end

function DataService:GetOwnedPotions(player: Player): { [string]: OwnedPotions.OwnedPotionRecord }
	if not POTIONS_KEY then
		return {}
	end

	local potionsState = cloneOwnedPotionsState(self:Get(player, POTIONS_KEY))
	return potionsState.ownedByPotionId
end

function DataService:GetPotionsState(player: Player): OwnedPotions.OwnedPotionsState
	if not POTIONS_KEY then
		return OwnedPotions.CreateEmptyState()
	end

	return cloneOwnedPotionsState(self:Get(player, POTIONS_KEY))
end

function DataService:GetOwnedAuraByAuraId(player: Player, auraId: string): OwnedAuras.OwnedAuraRecord?
	local normalizedAuraId = AuraConfig.NormalizeId(auraId)
	if not normalizedAuraId then
		return nil
	end

	local aurasState = self:GetAurasState(player)
	local ownedId = aurasState.ownedAuraIdByAuraId[normalizedAuraId]
	if not ownedId then
		return nil
	end

	return aurasState.ownedById[ownedId]
end

function DataService:GetEquippedLoadout(player: Player): BodyPartLoadout.EquippedState
	if not EQUIPPED_LOADOUT_KEY then
		return BodyPartLoadout.CreateEmptyEquippedState()
	end

	return BodyPartLoadout.NormalizeEquippedState(self:Get(player, EQUIPPED_LOADOUT_KEY))
end

function DataService:GetStats(player: Player): any
	if not STATS_KEY then
		return PlayerStats.CreateEmpty()
	end

	return PlayerStats.Normalize(self:Get(player, STATS_KEY), {
		bodyPartsState = self:GetBodyPartsState(player),
		aurasState = self:GetAurasState(player),
		currentMoney = self:GetMoney(player),
		diagnostics = if DIAGNOSTICS_KEY then self:Get(player, DIAGNOSTICS_KEY) else nil,
		successfulRollCount = self:GetSuccessfulRollCount(player),
	})
end

function DataService:GetTimePlayed(player: Player): number
	if not TIME_PLAYED_KEY then
		return 0
	end

	return math.max(0, clampWholeNumber(self:Get(player, TIME_PLAYED_KEY), 0))
end

function DataService:GetTimeShardsState(player: Player): TimeShardState.TimeShardStateValue
	if not TIME_SHARDS_KEY then
		return TimeShardState.CreateEmptyState()
	end

	return TimeShardState.Normalize(self:Get(player, TIME_SHARDS_KEY))
end

function DataService:GetTimeShardsBalance(player: Player): number
	return self:GetTimeShardsState(player).balance
end

function DataService:GetDailyChestState(player: Player): DailyChestState.DailyChestStateValue
	if not DAILY_CHESTS_KEY then
		return DailyChestState.CreateEmptyState()
	end

	return DailyChestState.Normalize(self:Get(player, DAILY_CHESTS_KEY))
end

function DataService:SetDailyChestState(player: Player, state: any): DailyChestState.DailyChestStateValue
	local normalizedState = DailyChestState.Normalize(state)
	if not DAILY_CHESTS_KEY then
		return normalizedState
	end
	if not getActiveReplica(player) then
		return normalizedState
	end

	self:Set(player, DAILY_CHESTS_KEY, normalizedState)
	return normalizedState
end

function DataService:GetTutorialState(player: Player): TutorialState.TutorialStateValue
	if not TUTORIAL_KEY then
		return TutorialState.CreateCompletedState()
	end

	return TutorialState.Normalize(self:Get(player, TUTORIAL_KEY))
end

function DataService:SetTutorialState(player: Player, state: any): TutorialState.TutorialStateValue
	local normalizedState = TutorialState.Normalize(state)
	if not TUTORIAL_KEY then
		return normalizedState
	end
	if not getActiveReplica(player) then
		return normalizedState
	end

	self:Set(player, TUTORIAL_KEY, normalizedState)
	return normalizedState
end

function DataService:AdjustTimeShardsBalance(player: Player, delta: number, _source: string?): number
	if not TIME_SHARDS_KEY then
		return 0
	end
	if not getActiveReplica(player) then
		return 0
	end

	local updatedBalance = 0
	self:Set(player, TIME_SHARDS_KEY, function(currentValue)
		local state = TimeShardState.Normalize(currentValue)
		updatedBalance = math.max(0, state.balance + (tonumber(delta) or 0))
		return {
			balance = updatedBalance,
			awardedMinutes = state.awardedMinutes,
		}
	end)

	return updatedBalance
end

function DataService:GetMoney(player: Player): number
	if not MONEY_KEY then
		return 0
	end

	return math.max(0, tonumber(self:Get(player, MONEY_KEY)) or 0)
end

function DataService:AdjustMoney(player: Player, delta: number, source: string?): number
	if not MONEY_KEY then
		return 0
	end
	if not getActiveReplica(player) then
		return 0
	end

	local previousValue = self:GetMoney(player)
	local updatedValue = math.max(0, previousValue + (tonumber(delta) or 0))
	setReplicaPathValue(player, MONEY_KEY, nil, updatedValue)
	syncPlayerStateForKey(player, MONEY_KEY, updatedValue)
	MoneyChanged:Fire(player, previousValue, updatedValue, tonumber(delta) or 0, source)

	return updatedValue
end

function DataService:AddMoney(player: Player, amount: number, source: string?): number
	return self:AdjustMoney(player, amount, source)
end

function DataService:GetSuccessfulRollCount(player: Player): number
	if not SUCCESSFUL_ROLL_COUNT_KEY then
		return 0
	end

	return math.max(0, clampWholeNumber(self:Get(player, SUCCESSFUL_ROLL_COUNT_KEY), 0))
end

function DataService:GetEquippedTitleId(player: Player): string?
	if not EQUIPPED_TITLE_ID_KEY then
		return nil
	end

	local normalizedEquippedTitleId = normalizeOptionalString(self:Get(player, EQUIPPED_TITLE_ID_KEY))
	if normalizedEquippedTitleId == "" then
		return nil
	end

	return normalizedEquippedTitleId
end

function DataService:GetEquippedAuraId(player: Player): string?
	if not EQUIPPED_AURA_ID_KEY then
		return nil
	end

	local normalizedEquippedAuraId = normalizeOptionalAuraId(self:Get(player, EQUIPPED_AURA_ID_KEY))
	if normalizedEquippedAuraId == "" then
		return nil
	end

	return normalizedEquippedAuraId
end

function DataService:SetEquippedTitleId(player: Player, equippedTitleId: string?): (boolean, string?)
	if not EQUIPPED_TITLE_ID_KEY then
		return false, "Equipped title persistence is not configured."
	end
	if not getActiveReplica(player) then
		return false, "Player data is not loaded."
	end

	self:Set(player, EQUIPPED_TITLE_ID_KEY, normalizeOptionalString(equippedTitleId))
	return true, "Equipped title updated."
end

function DataService:SetEquippedAuraId(player: Player, equippedAuraId: string?): (boolean, string?)
	if not EQUIPPED_AURA_ID_KEY then
		return false, "Equipped aura persistence is not configured."
	end
	if not getActiveReplica(player) then
		return false, "Player data is not loaded."
	end

	self:Set(player, EQUIPPED_AURA_ID_KEY, normalizeOptionalAuraId(equippedAuraId))
	return true, "Equipped aura updated."
end

function DataService:GetAchievementsState(player: Player): AchievementState.AchievementsState
	if not ACHIEVEMENTS_KEY then
		return AchievementState.CreateEmptyState()
	end

	return AchievementState.Normalize(self:Get(player, ACHIEVEMENTS_KEY))
end

function DataService:IncrementSuccessfulRollCount(player: Player): number
	if not SUCCESSFUL_ROLL_COUNT_KEY then
		return 0
	end

	local previousValue = self:GetSuccessfulRollCount(player)
	local updatedValue = math.max(0, previousValue) + 1
	setReplicaPathValue(player, SUCCESSFUL_ROLL_COUNT_KEY, nil, updatedValue)
	syncPlayerStateForKey(player, SUCCESSFUL_ROLL_COUNT_KEY, updatedValue)
	SuccessfulRollIncremented:Fire(player, previousValue, updatedValue)

	return updatedValue
end

function DataService:GetVipOwned(player: Player): boolean
	if not VIP_OWNED_KEY then
		return false
	end

	return self:Get(player, VIP_OWNED_KEY) == true
end

function DataService:SetVipOwned(player: Player, isOwned: boolean): (boolean, string?)
	if not VIP_OWNED_KEY then
		return false, "VIP persistence is not configured."
	end
	if not getActiveReplica(player) then
		return false, "Player data is not loaded."
	end

	self:Set(player, VIP_OWNED_KEY, isOwned == true)
	return true, "VIP ownership updated."
end

function DataService:GetVipPlusOwned(player: Player): boolean
	if not VIP_PLUS_OWNED_KEY then
		return false
	end

	return self:Get(player, VIP_PLUS_OWNED_KEY) == true
end

function DataService:SetVipPlusOwned(player: Player, isOwned: boolean): (boolean, string?)
	if not VIP_PLUS_OWNED_KEY then
		return false, "VIP+ persistence is not configured."
	end
	if not getActiveReplica(player) then
		return false, "Player data is not loaded."
	end

	self:Set(player, VIP_PLUS_OWNED_KEY, isOwned == true)
	return true, "VIP+ ownership updated."
end

function DataService:GetSelectedRollType(player: Player): string
	if not SELECTED_ROLL_TYPE_KEY then
		return OwnedRollTypes.GetDefaultSelectedRollTypeId()
	end

	return OwnedRollTypes.NormalizeSelectedRollTypeId(self:Get(player, SELECTED_ROLL_TYPE_KEY))
end

function DataService:SetSelectedRollType(player: Player, rollTypeId: string): (boolean, string?)
	if not SELECTED_ROLL_TYPE_KEY then
		return false, "Selected roll type persistence is not configured."
	end
	if not getActiveReplica(player) then
		return false, "Player data is not loaded."
	end
	if typeof(rollTypeId) ~= "string" or rollTypeId == "" then
		return false, "rollTypeId is required."
	end
	if not RollTypes.Get(rollTypeId) then
		return false, "That roll type does not exist."
	end

	self:Set(player, SELECTED_ROLL_TYPE_KEY, rollTypeId)
	return true, "Selected roll type updated."
end

function DataService:GetSelectedRollRegion(player: Player): string
	if not SELECTED_ROLL_REGION_KEY then
		return RollTargetRegions.Default
	end

	return RollTargetRegions.Normalize(self:Get(player, SELECTED_ROLL_REGION_KEY))
end

function DataService:SetSelectedRollRegion(player: Player, rollRegion: string): (boolean, string?)
	if not SELECTED_ROLL_REGION_KEY then
		return false, "Selected roll region persistence is not configured."
	end
	if not getActiveReplica(player) then
		return false, "Player data is not loaded."
	end
	if typeof(rollRegion) ~= "string" or rollRegion == "" then
		return false, "rollRegion is required."
	end
	if not RollTargetRegions.IsValid(rollRegion) then
		return false, "That roll region does not exist."
	end

	self:Set(player, SELECTED_ROLL_REGION_KEY, rollRegion)
	return true, "Selected roll region updated."
end

function DataService:GetQuickRollEnabled(player: Player): boolean
	if not QUICK_ROLL_ENABLED_KEY then
		return false
	end

	return self:Get(player, QUICK_ROLL_ENABLED_KEY) == true
end

function DataService:SetQuickRollEnabled(player: Player, enabled: boolean): (boolean, string?)
	if not QUICK_ROLL_ENABLED_KEY then
		return false, "Quick roll persistence is not configured."
	end
	if not getActiveReplica(player) then
		return false, "Player data is not loaded."
	end

	self:Set(player, QUICK_ROLL_ENABLED_KEY, enabled == true)
	return true, "Quick roll updated."
end

function DataService:GetAutoEquipBestEnabled(player: Player): boolean
	if not AUTO_EQUIP_BEST_ENABLED_KEY then
		return false
	end

	return self:Get(player, AUTO_EQUIP_BEST_ENABLED_KEY) == true
end

function DataService:SetAutoEquipBestEnabled(player: Player, enabled: boolean): (boolean, string?)
	if not AUTO_EQUIP_BEST_ENABLED_KEY then
		return false, "Auto equip best persistence is not configured."
	end
	if not getActiveReplica(player) then
		return false, "Player data is not loaded."
	end

	self:Set(player, AUTO_EQUIP_BEST_ENABLED_KEY, enabled == true)
	return true, "Auto equip best updated."
end

function DataService:GetAutoSizeEnabled(player: Player): boolean
	if not AUTO_SIZE_ENABLED_KEY then
		return false
	end

	return self:Get(player, AUTO_SIZE_ENABLED_KEY) == true
end

function DataService:SetAutoSizeEnabled(player: Player, enabled: boolean): (boolean, string?)
	if not AUTO_SIZE_ENABLED_KEY then
		return false, "Regular scale persistence is not configured."
	end
	if not getActiveReplica(player) then
		return false, "Player data is not loaded."
	end

	self:Set(player, AUTO_SIZE_ENABLED_KEY, enabled == true)
	return true, "Regular scale updated."
end

function DataService:GetMusicEnabled(player: Player): boolean
	if not MUSIC_ENABLED_KEY then
		return true
	end

	return self:Get(player, MUSIC_ENABLED_KEY) ~= false
end

function DataService:SetMusicEnabled(player: Player, enabled: boolean): (boolean, string?)
	if not MUSIC_ENABLED_KEY then
		return false, "Music preference persistence is not configured."
	end
	if not getActiveReplica(player) then
		return false, "Player data is not loaded."
	end

	self:Set(player, MUSIC_ENABLED_KEY, enabled ~= false)
	return true, "Music preference updated."
end

function DataService:GetAutoSellRarities(player: Player): { [string]: boolean }
	if not AUTO_SELL_RARITIES_KEY then
		return RollingConfig.CreateDefaultAutoSellState()
	end

	return RollingConfig.NormalizeAutoSellState(self:Get(player, AUTO_SELL_RARITIES_KEY))
end

function DataService:IsAutoSellEnabledForRarity(player: Player, displayRarity: any): boolean
	local normalizedRarity = RollingConfig.NormalizeDisplayRarity(displayRarity)
	return self:GetAutoSellRarities(player)[normalizedRarity] == true
end

function DataService:SetAutoSellRarityEnabled(player: Player, displayRarity: any, enabled: boolean): (boolean, string?)
	if not AUTO_SELL_RARITIES_KEY then
		return false, "Auto-sell persistence is not configured."
	end
	if not getActiveReplica(player) then
		return false, "Player data is not loaded."
	end

	local normalizedRarity = RollingConfig.ResolveDisplayRarity(displayRarity)
	if not RollingConfig.IsValidDisplayRarity(normalizedRarity) then
		return false, "That auto-sell rarity does not exist."
	end

	self:Set(player, AUTO_SELL_RARITIES_KEY, function(currentValue)
		local autoSellState = RollingConfig.NormalizeAutoSellState(currentValue)
		autoSellState[normalizedRarity] = enabled == true
		return autoSellState
	end)

	return true, string.format(
		"%s auto-sell %s.",
		normalizedRarity,
		if enabled == true then "enabled" else "disabled"
	)
end

function DataService:GetCutsceneRarities(player: Player): { [string]: boolean }
	if not CUTSCENE_RARITIES_KEY then
		return RollingConfig.CreateDefaultCutsceneState()
	end

	return RollingConfig.NormalizeCutsceneState(self:Get(player, CUTSCENE_RARITIES_KEY))
end

function DataService:IsCutsceneEnabledForRarity(player: Player, displayRarity: any): boolean
	local normalizedRarity = RollingConfig.NormalizeDisplayRarity(displayRarity)
	return self:GetCutsceneRarities(player)[normalizedRarity] ~= false
end

function DataService:SetCutsceneRarityEnabled(player: Player, displayRarity: any, enabled: boolean): (boolean, string?)
	if not CUTSCENE_RARITIES_KEY then
		return false, "Cutscene persistence is not configured."
	end
	if not getActiveReplica(player) then
		return false, "Player data is not loaded."
	end

	local normalizedRarity = RollingConfig.ResolveDisplayRarity(displayRarity)
	if not RollingConfig.IsValidDisplayRarity(normalizedRarity) then
		return false, "That cutscene rarity does not exist."
	end

	self:Set(player, CUTSCENE_RARITIES_KEY, function(currentValue)
		local cutsceneState = RollingConfig.NormalizeCutsceneState(currentValue)
		cutsceneState[normalizedRarity] = enabled ~= false
		return cutsceneState
	end)

	return true, string.format(
		"%s cutscenes %s.",
		normalizedRarity,
		if enabled ~= false then "enabled" else "disabled"
	)
end

function DataService:SetEquippedLoadout(player: Player, equippedState: BodyPartLoadout.EquippedState): (boolean, string?)
	if not EQUIPPED_LOADOUT_KEY then
		return false, "Equipped loadout persistence is not configured."
	end
	if not waitForActiveReplica(player, 15) then
		return false, "Player data is not loaded."
	end

	self:Set(player, EQUIPPED_LOADOUT_KEY, BodyPartLoadout.NormalizeEquippedState(equippedState))
	return true, "Equipped loadout updated."
end

function DataService:SetEquippedAccessories(
	player: Player,
	equippedState: OwnedAccessories.EquippedAccessoriesState
): (boolean, string?)
	if not EQUIPPED_ACCESSORIES_KEY then
		return false, "Accessory equipment persistence is not configured."
	end
	if not waitForActiveReplica(player, 15) then
		return false, "Player data is not loaded."
	end

	self:Set(player, EQUIPPED_ACCESSORIES_KEY, cloneEquippedAccessoriesState(equippedState, self:GetAccessoriesState(player)))
	return true, "Equipped accessories updated."
end

function DataService:SetEquippedAccessory(player: Player, slot: string, ownedId: string?): (boolean, string?)
	local normalizedSlot = OwnedAccessories.NormalizeSlot(slot)
	if not normalizedSlot then
		return false, "Accessory slot is invalid."
	end

	local equippedState = self:GetEquippedAccessories(player)
	if ownedId == nil or ownedId == "" then
		equippedState[normalizedSlot] = nil
		return self:SetEquippedAccessories(player, equippedState)
	end

	local ownedRecord = self:GetOwnedAccessories(player)[ownedId]
	if not ownedRecord then
		return false, "You do not own that accessory."
	end
	if ownedRecord.slot ~= normalizedSlot then
		return false, "That accessory cannot be equipped in this slot."
	end

	equippedState[normalizedSlot] = ownedId
	return self:SetEquippedAccessories(player, equippedState)
end

function DataService:UpdateOwnedBodyPartVariant(player: Player, ownedId: string, payload: {
	mutationId: string,
	mutation: string?,
	mutationMultiplier: number,
	sizeId: string,
	sizeMultiplier: number,
	variantMultiplier: number,
	finalPassiveIncomePerSecond: number,
}): (OwnedBodyParts.OwnedBodyPartRecord?, string?)
	if not BODY_PARTS_KEY then
		return nil, "Body parts persistence is not configured."
	end
	if not getActiveReplica(player) then
		return nil, "Player data is not loaded."
	end
	if typeof(ownedId) ~= "string" or ownedId == "" then
		return nil, "ownedId is required."
	end
	if typeof(payload) ~= "table" then
		return nil, "Variant payload must be a table."
	end

	local bodyPartsState = getReplicaValue(player, BODY_PARTS_KEY)
	local ownedById = if typeof(bodyPartsState) == "table" then bodyPartsState.ownedById else nil
	local existingRecord = normalizeOwnedBodyPartRecord(
		typeof(ownedById) == "table" and ownedById[ownedId] or nil,
		ownedId
	)
	if not existingRecord then
		return nil, string.format("Owned body part '%s' was not found.", ownedId)
	end

	local updatedRecord = normalizeOwnedBodyPartRecord({
		ownedId = existingRecord.ownedId,
		pieceId = existingRecord.pieceId,
		rarityDenominator = existingRecord.rarityDenominator,
		rolledSetId = existingRecord.rolledSetId,
		rolledSetDisplayName = existingRecord.rolledSetDisplayName,
		displayOddsDenominator = existingRecord.displayOddsDenominator,
		displayRarity = existingRecord.displayRarity,
		serialNumber = existingRecord.serialNumber,
		isFavorite = existingRecord.isFavorite == true,
		mutationId = payload.mutationId,
		mutation = payload.mutation,
		mutationMultiplier = payload.mutationMultiplier,
		sizeId = payload.sizeId,
		sizeMultiplier = payload.sizeMultiplier,
		variantMultiplier = payload.variantMultiplier,
		finalPassiveIncomePerSecond = payload.finalPassiveIncomePerSecond,
	}, ownedId)

	if not updatedRecord then
		return nil, "Failed to store the updated body part variant."
	end

	local didUpdate = setReplicaPathValues(player, BODY_PARTS_KEY, { "ownedById", ownedId }, {
		mutationId = updatedRecord.mutationId,
		mutation = updatedRecord.mutation,
		mutationMultiplier = updatedRecord.mutationMultiplier,
		sizeId = updatedRecord.sizeId,
		sizeMultiplier = updatedRecord.sizeMultiplier,
		variantMultiplier = updatedRecord.variantMultiplier,
		finalPassiveIncomePerSecond = updatedRecord.finalPassiveIncomePerSecond,
	})
	if not didUpdate then
		return nil, "Failed to update the owned body part variant."
	end

	return deepCopy(updatedRecord), nil
end

function DataService:GetNextSerialForPiece(pieceId: string): (number?, string?)
	local normalizedPieceId = BodyPartLegacyIds.NormalizePieceId(pieceId)
	if normalizedPieceId == nil then
		return nil, "pieceId is required."
	end

	return BodyPartSerialStore:GetNextSerialForPiece(normalizedPieceId)
end

function DataService:ReleaseBodyPartSerial(pieceId: string, serialNumber: number): (boolean, string?)
	local normalizedPieceId = BodyPartLegacyIds.NormalizePieceId(pieceId)
	if normalizedPieceId == nil then
		return false, "pieceId is required."
	end

	return BodyPartSerialStore:ReleaseSerialForPiece(normalizedPieceId, serialNumber)
end

function DataService:ReleaseBodyPartSerials(serialReservations: { any }): (boolean, string?)
	if typeof(serialReservations) ~= "table" then
		return false, "serialReservations must be a table."
	end

	local serialsByPieceId = {}
	for _, reservation in ipairs(serialReservations) do
		if typeof(reservation) ~= "table" then
			continue
		end

		local normalizedPieceId = BodyPartLegacyIds.NormalizePieceId(reservation.pieceId)
		local serialNumber = math.floor(tonumber(reservation.serialNumber) or 0)
		if normalizedPieceId ~= nil and serialNumber > 0 then
			local serials = serialsByPieceId[normalizedPieceId]
			if serials == nil then
				serials = {}
				serialsByPieceId[normalizedPieceId] = serials
			end
			table.insert(serials, serialNumber)
		end
	end

	local didReleaseAll = true
	local lastError = nil
	for pieceId, serialNumbers in pairs(serialsByPieceId) do
		local didRelease, releaseError = BodyPartSerialStore:ReleaseSerialsForPiece(pieceId, serialNumbers)
		if not didRelease then
			didReleaseAll = false
			lastError = releaseError
		end
	end

	return didReleaseAll, lastError
end

function DataService:GetTotalInExistenceForPiece(pieceId: string): (number?, string?)
	local normalizedPieceId = BodyPartLegacyIds.NormalizePieceId(pieceId)
	if normalizedPieceId == nil then
		return nil, "pieceId is required."
	end

	return BodyPartSerialStore:GetTotalInExistenceForPiece(normalizedPieceId)
end

function DataService:GetTotalInExistenceForPieces(pieceIds: { string }): ({ [string]: number }?, string?)
	if typeof(pieceIds) ~= "table" then
		return nil, "pieceIds must be a table."
	end

	local normalizedPieceIds = {}
	local seenPieceIds = {}
	for _, pieceId in ipairs(pieceIds) do
		local normalizedPieceId = BodyPartLegacyIds.NormalizePieceId(pieceId)
		if normalizedPieceId == nil then
			return nil, "pieceId is required."
		end
		if seenPieceIds[normalizedPieceId] ~= true then
			seenPieceIds[normalizedPieceId] = true
			table.insert(normalizedPieceIds, normalizedPieceId)
		end
	end

	return BodyPartSerialStore:GetTotalInExistenceForPieces(normalizedPieceIds)
end

function DataService:GetNextSerialForAura(auraId: string): (number?, string?)
	return AuraSerialStore:GetNextSerialForAura(auraId)
end

function DataService:GetTotalInExistenceForAura(auraId: string): (number?, string?)
	return AuraSerialStore:GetTotalInExistenceForAura(auraId)
end

local function validateBodyPartGrantPayload(payload: any): ({ [string]: any }?, string?)
	if typeof(payload) ~= "table" then
		return nil, "Owned body part payload must be a table."
	end

	local pieceId = BodyPartLegacyIds.NormalizePieceId(payload.pieceId)
	if typeof(pieceId) ~= "string" or pieceId == "" then
		return nil, "pieceId is required."
	end

	if not BodyPartsCatalog.GetPiece(pieceId) then
		return nil, string.format("Unknown body part pieceId '%s'.", pieceId)
	end

	local rarityDenominator = payload.rarityDenominator
	if not isPositiveFiniteNumber(rarityDenominator) then
		return nil, "rarityDenominator must be a positive number."
	end
	rarityDenominator = math.max(1, math.floor(rarityDenominator))

	local mutation = payload.mutation
	if mutation ~= nil and typeof(mutation) ~= "string" then
		return nil, "mutation must be a string when provided."
	end

	local mutationId = payload.mutationId
	if mutationId ~= nil and typeof(mutationId) ~= "string" then
		return nil, "mutationId must be a string when provided."
	end

	local sizeMultiplier = payload.sizeMultiplier
	if sizeMultiplier == nil then
		sizeMultiplier = SizeConfig.GetRepresentativeScale(payload.sizeId)
	elseif not isPositiveFiniteNumber(sizeMultiplier) then
		return nil, "sizeMultiplier must be a positive number when provided."
	else
		sizeMultiplier = SizeConfig.NormalizeScale(sizeMultiplier, payload.sizeId)
	end

	local mutationMultiplier = payload.mutationMultiplier
	if mutationMultiplier ~= nil and not isPositiveFiniteNumber(mutationMultiplier) then
		return nil, "mutationMultiplier must be a positive number when provided."
	end

	local variantMultiplier = payload.variantMultiplier
	if variantMultiplier ~= nil and not isPositiveFiniteNumber(variantMultiplier) then
		return nil, "variantMultiplier must be a positive number when provided."
	end

	local finalPassiveIncomePerSecond = payload.finalPassiveIncomePerSecond
	if finalPassiveIncomePerSecond ~= nil and (typeof(finalPassiveIncomePerSecond) ~= "number" or finalPassiveIncomePerSecond < 0) then
		return nil, "finalPassiveIncomePerSecond must be zero or greater when provided."
	end

	return {
		pieceId = pieceId,
		rarityDenominator = rarityDenominator,
		rolledSetId = payload.rolledSetId,
		rolledSetDisplayName = payload.rolledSetDisplayName,
		displayOddsDenominator = payload.displayOddsDenominator,
		displayRarity = payload.displayRarity,
		mutationId = mutationId,
		mutation = mutation,
		mutationMultiplier = mutationMultiplier,
		sizeId = payload.sizeId,
		sizeMultiplier = sizeMultiplier,
		variantMultiplier = variantMultiplier,
		finalPassiveIncomePerSecond = finalPassiveIncomePerSecond,
	}, nil
end

local function buildGrantedBodyPartRecord(
	grantData: { [string]: any },
	ownedId: string?,
	serialNumber: number
): OwnedBodyParts.OwnedBodyPartRecord?
	return normalizeOwnedBodyPartRecord({
		ownedId = ownedId,
		pieceId = grantData.pieceId,
		rarityDenominator = grantData.rarityDenominator,
		rolledSetId = grantData.rolledSetId,
		rolledSetDisplayName = grantData.rolledSetDisplayName,
		displayOddsDenominator = grantData.displayOddsDenominator,
		displayRarity = grantData.displayRarity,
		mutationId = grantData.mutationId,
		mutation = grantData.mutation,
		mutationMultiplier = grantData.mutationMultiplier,
		sizeId = grantData.sizeId,
		sizeMultiplier = grantData.sizeMultiplier,
		variantMultiplier = grantData.variantMultiplier,
		finalPassiveIncomePerSecond = grantData.finalPassiveIncomePerSecond,
		serialNumber = serialNumber,
	}, ownedId)
end

function DataService:ReserveBodyPartRollRecord(player: Player, payload: OwnedBodyParts.OwnedBodyPartGrantPayload): (OwnedBodyParts.OwnedBodyPartRecord?, any?, string?)
	if not BODY_PARTS_KEY then
		return nil, nil, "Body parts persistence is not configured."
	end
	local replica = getActiveReplica(player)
	if not replica then
		return nil, nil, "Player data is not loaded."
	end

	local grantData, grantError = validateBodyPartGrantPayload(payload)
	if not grantData then
		return nil, nil, grantError
	end

	local serialNumber, serialError = self:GetNextSerialForPiece(grantData.pieceId)
	if not serialNumber then
		return nil, nil, serialError or "Failed to allocate body part serial number."
	end

	local reservedRecord = buildGrantedBodyPartRecord(grantData, nil, serialNumber)
	if not reservedRecord then
		return nil, nil, "Failed to reserve rolled body part."
	end

	local currentBodyPartsState = if typeof(replica.Data[BODY_PARTS_KEY]) == "table"
		then replica.Data[BODY_PARTS_KEY]
		else OwnedBodyParts.CreateEmptyState()
	markBodyPartPieceDiscovered(player, currentBodyPartsState, grantData.pieceId)

	return deepCopy(reservedRecord), {
		serialNumber = serialNumber,
		pieceId = grantData.pieceId,
	}, nil
end

function DataService:AddOwnedBodyPart(
	player: Player,
	payload: OwnedBodyParts.OwnedBodyPartGrantPayload,
	reservation: any?
): (OwnedBodyParts.OwnedBodyPartRecord?, string?)
	if not BODY_PARTS_KEY then
		return nil, "Body parts persistence is not configured."
	end
	local replica = getActiveReplica(player)
	if not replica then
		return nil, "Player data is not loaded."
	end

	local grantData, grantError = validateBodyPartGrantPayload(payload)
	if not grantData then
		return nil, grantError
	end

	local currentBodyPartsState = if typeof(replica.Data[BODY_PARTS_KEY]) == "table"
		then replica.Data[BODY_PARTS_KEY]
		else OwnedBodyParts.CreateEmptyState()
	local currentOwnedCount = OwnedBodyParts.CountOwned(currentBodyPartsState)
	local ignoreInventoryLimit = typeof(reservation) == "table" and reservation.ignoreInventoryLimit == true
	if currentOwnedCount >= OwnedBodyParts.MAX_OWNED_COUNT and not ignoreInventoryLimit then
		return nil, string.format(
			"Inventory is full (%d/%d). Sell body parts to make room.",
			currentOwnedCount,
			OwnedBodyParts.MAX_OWNED_COUNT
		)
	end

	local serialNumber = if typeof(reservation) == "table" then tonumber(reservation.serialNumber) else nil
	if serialNumber == nil or serialNumber <= 0 then
		local serialError
		serialNumber, serialError = self:GetNextSerialForPiece(grantData.pieceId)
		if not serialNumber then
			return nil, serialError or "Failed to allocate body part serial number."
		end
	end

	local nextOwnedId = math.max(1, math.floor(tonumber(currentBodyPartsState.nextOwnedId) or 1))
	local ownedId = OwnedBodyParts.CreateOwnedId(nextOwnedId)
	local createdRecord = buildGrantedBodyPartRecord(grantData, ownedId, serialNumber)

	if not createdRecord then
		return nil, "Failed to store owned body part."
	end

	setReplicaPathValue(player, BODY_PARTS_KEY, { "ownedById", ownedId }, createdRecord)
	markBodyPartPieceDiscovered(player, currentBodyPartsState, grantData.pieceId)
	setReplicaPathValue(player, BODY_PARTS_KEY, { "nextOwnedId" }, nextOwnedId + 1)

	local updatedBodyPartsState = self:GetBodyPartsState(player)

	OwnedBodyPartAdded:Fire(player, deepCopy(createdRecord), cloneOwnedBodyPartsState(updatedBodyPartsState))

	return deepCopy(createdRecord), nil
end

function DataService:AddOwnedAura(player: Player, payload: OwnedAuras.OwnedAuraGrantPayload): (OwnedAuras.OwnedAuraRecord?, string?)
	if not AURAS_KEY then
		return nil, "Aura persistence is not configured."
	end
	if not getActiveReplica(player) then
		return nil, "Player data is not loaded."
	end
	if typeof(payload) ~= "table" then
		return nil, "Owned aura payload must be a table."
	end

	local auraId = AuraConfig.NormalizeId(payload.auraId)
	if not auraId then
		return nil, "auraId is required."
	end

	local existingRecord = self:GetOwnedAuraByAuraId(player, auraId)
	if existingRecord then
		return deepCopy(existingRecord), nil
	end

	local serialNumber, serialError = self:GetNextSerialForAura(auraId)
	if not serialNumber then
		return nil, serialError or "Failed to allocate aura serial number."
	end

	local createdRecord: OwnedAuras.OwnedAuraRecord? = nil
	local updatedAurasState: OwnedAuras.OwnedAurasState? = nil

	self:Set(player, AURAS_KEY, function(currentAurasState)
		local aurasState = cloneOwnedAurasState(currentAurasState)
		local ownedAuraId = aurasState.ownedAuraIdByAuraId[auraId]
		if ownedAuraId and aurasState.ownedById[ownedAuraId] then
			createdRecord = aurasState.ownedById[ownedAuraId]
			return aurasState
		end

		local ownedId = OwnedAuras.CreateOwnedId(aurasState.nextOwnedId)
		createdRecord = {
			ownedId = ownedId,
			auraId = auraId,
			serialNumber = math.max(1, clampWholeNumber(serialNumber, 1)),
			isFavorite = false,
		}

		aurasState.ownedById[ownedId] = createdRecord
		aurasState.ownedAuraIdByAuraId[auraId] = ownedId
		aurasState.nextOwnedId += 1
		updatedAurasState = cloneOwnedAurasState(aurasState)
		return aurasState
	end)

	if not createdRecord then
		return nil, "Failed to store owned aura."
	end

	if updatedAurasState and existingRecord == nil then
		OwnedAuraAdded:Fire(player, deepCopy(createdRecord), cloneOwnedAurasState(updatedAurasState))
	end

	return deepCopy(createdRecord), nil
end

function DataService:AddOwnedAccessory(
	player: Player,
	payload: OwnedAccessories.OwnedAccessoryGrantPayload
): (OwnedAccessories.OwnedAccessoryRecord?, string?)
	if not ACCESSORIES_KEY then
		return nil, "Accessory persistence is not configured."
	end
	if not getActiveReplica(player) then
		return nil, "Player data is not loaded."
	end
	if typeof(payload) ~= "table" then
		return nil, "Owned accessory payload must be a table."
	end

	local accessoryId = AccessoryConfig.NormalizeId(payload.accessoryId)
	local config = accessoryId and AccessoryConfig.Get(accessoryId)
	if not config then
		return nil, "accessoryId is required."
	end

	local currentAccessoriesState = if typeof(getReplicaValue(player, ACCESSORIES_KEY)) == "table"
		then getReplicaValue(player, ACCESSORIES_KEY)
		else OwnedAccessories.CreateEmptyState()
	local currentOwnedCount = OwnedAccessories.CountOwned(currentAccessoriesState)
	if currentOwnedCount >= OwnedAccessories.MAX_OWNED_COUNT then
		return nil, string.format(
			"Accessory inventory is full (%d/%d).",
			currentOwnedCount,
			OwnedAccessories.MAX_OWNED_COUNT
		)
	end

	local nextOwnedId = math.max(1, math.floor(tonumber(currentAccessoriesState.nextOwnedId) or 1))
	local ownedId = OwnedAccessories.CreateOwnedId(nextOwnedId)
	local createdRecord = {
		ownedId = ownedId,
		accessoryId = config.id,
		slot = config.slot,
		isFavorite = false,
	}

	setReplicaPathValue(player, ACCESSORIES_KEY, { "ownedById", ownedId }, createdRecord)
	setReplicaPathValue(player, ACCESSORIES_KEY, { "nextOwnedId" }, nextOwnedId + 1)

	return deepCopy(createdRecord), nil
end

function DataService:RemoveOwnedAccessory(player: Player, ownedId: string): (OwnedAccessories.OwnedAccessoryRecord?, string?)
	if not ACCESSORIES_KEY then
		return nil, "Accessory persistence is not configured."
	end
	if not getActiveReplica(player) then
		return nil, "Player data is not loaded."
	end
	if typeof(ownedId) ~= "string" or ownedId == "" then
		return nil, "ownedId is required."
	end

	local accessoriesState = getReplicaValue(player, ACCESSORIES_KEY)
	local ownedById = if typeof(accessoriesState) == "table" then accessoriesState.ownedById else nil
	local removedRecord = normalizeOwnedAccessoryRecord(
		typeof(ownedById) == "table" and ownedById[ownedId] or nil,
		ownedId
	)
	if not removedRecord then
		return nil, string.format("Owned accessory '%s' was not found.", ownedId)
	end

	setReplicaPathValue(player, ACCESSORIES_KEY, { "ownedById", ownedId }, nil)

	return deepCopy(removedRecord), nil
end

function DataService:AddOwnedPotionUses(player: Player, potionId: string, amount: number): (OwnedPotions.OwnedPotionRecord?, string?)
	if not POTIONS_KEY then
		return nil, "Potion persistence is not configured."
	end
	if not getActiveReplica(player) then
		return nil, "Player data is not loaded."
	end

	local normalizedPotionId = PotionConfig.NormalizeId(potionId)
	if not normalizedPotionId then
		return nil, "potionId is required."
	end

	local resolvedAmount = math.max(1, math.floor(tonumber(amount) or 0))
	local updatedRecord: OwnedPotions.OwnedPotionRecord? = nil

	self:Set(player, POTIONS_KEY, function(currentPotionsState)
		local potionsState = cloneOwnedPotionsState(currentPotionsState)
		local existingRecord = potionsState.ownedByPotionId[normalizedPotionId]
		local nextAmount = resolvedAmount
		local isFavorite = false
		if existingRecord then
			nextAmount += existingRecord.amount
			isFavorite = existingRecord.isFavorite == true
		end

		updatedRecord = {
			potionId = normalizedPotionId,
			amount = nextAmount,
			isFavorite = isFavorite,
		}
		potionsState.ownedByPotionId[normalizedPotionId] = updatedRecord
		return potionsState
	end)

	if not updatedRecord then
		return nil, "Failed to store owned potion."
	end

	return deepCopy(updatedRecord), nil
end

function DataService:ConsumeOwnedPotionUses(player: Player, potionId: string, amount: number): (OwnedPotions.OwnedPotionRecord?, string?)
	if not POTIONS_KEY then
		return nil, "Potion persistence is not configured."
	end
	if not getActiveReplica(player) then
		return nil, "Player data is not loaded."
	end

	local normalizedPotionId = PotionConfig.NormalizeId(potionId)
	if not normalizedPotionId then
		return nil, "potionId is required."
	end

	local resolvedAmount = math.max(1, math.floor(tonumber(amount) or 0))
	local updatedRecord: OwnedPotions.OwnedPotionRecord? = nil
	local failureMessage = nil

	self:Set(player, POTIONS_KEY, function(currentPotionsState)
		local potionsState = cloneOwnedPotionsState(currentPotionsState)
		local existingRecord = potionsState.ownedByPotionId[normalizedPotionId]
		if not existingRecord then
			failureMessage = "You do not own that potion."
			return potionsState
		end
		if existingRecord.amount < resolvedAmount then
			failureMessage = "You do not own that many potion uses."
			return potionsState
		end

		local remainingAmount = existingRecord.amount - resolvedAmount
		if remainingAmount > 0 then
			existingRecord.amount = remainingAmount
			updatedRecord = existingRecord
			potionsState.ownedByPotionId[normalizedPotionId] = existingRecord
		else
			potionsState.ownedByPotionId[normalizedPotionId] = nil
			updatedRecord = nil
		end
		return potionsState
	end)

	if failureMessage then
		return nil, failureMessage
	end

	return deepCopy(updatedRecord), nil
end

function DataService:RemoveOwnedBodyPart(player: Player, ownedId: string): (OwnedBodyParts.OwnedBodyPartRecord?, string?)
	if not BODY_PARTS_KEY then
		return nil, "Body parts persistence is not configured."
	end
	local bodyPartsState = getReplicaValue(player, BODY_PARTS_KEY)
	if not getActiveReplica(player) then
		return nil, "Player data is not loaded."
	end

	if typeof(ownedId) ~= "string" or ownedId == "" then
		return nil, "ownedId is required."
	end

	local ownedById = if typeof(bodyPartsState) == "table" then bodyPartsState.ownedById else nil
	local removedRecord = normalizeOwnedBodyPartRecord(
		typeof(ownedById) == "table" and ownedById[ownedId] or nil,
		ownedId
	)

	if not removedRecord then
		return nil, string.format("Owned body part '%s' was not found.", ownedId)
	end

	setReplicaPathValue(player, BODY_PARTS_KEY, { "ownedById", ownedId }, nil)

	return deepCopy(removedRecord), nil
end

function DataService:RemoveOwnedBodyParts(player: Player, ownedIds: { string }): ({ OwnedBodyParts.OwnedBodyPartRecord }?, string?)
	if not BODY_PARTS_KEY then
		return nil, "Body parts persistence is not configured."
	end
	if not getActiveReplica(player) then
		return nil, "Player data is not loaded."
	end
	if typeof(ownedIds) ~= "table" then
		return nil, "ownedIds must be a table."
	end

	local bodyPartsState = cloneOwnedBodyPartsState(getReplicaValue(player, BODY_PARTS_KEY))
	local uniqueOwnedIds = {}
	local seenOwnedIds = {}
	for _, ownedId in ipairs(ownedIds) do
		if typeof(ownedId) ~= "string" or ownedId == "" then
			return nil, "ownedId is required."
		end
		if seenOwnedIds[ownedId] ~= true then
			seenOwnedIds[ownedId] = true
			table.insert(uniqueOwnedIds, ownedId)
		end
	end

	table.sort(uniqueOwnedIds)

	local removedRecords = table.create(#uniqueOwnedIds)
	for _, ownedId in ipairs(uniqueOwnedIds) do
		local removedRecord = normalizeOwnedBodyPartRecord(bodyPartsState.ownedById[ownedId], ownedId)
		if not removedRecord then
			return nil, string.format("Owned body part '%s' was not found.", ownedId)
		end

		table.insert(removedRecords, removedRecord)
		bodyPartsState.ownedById[ownedId] = nil
	end

	if #removedRecords > 0 then
		setReplicaPathValue(player, BODY_PARTS_KEY, nil, bodyPartsState)
	end

	return deepCopy(removedRecords), nil
end

function DataService:AddCraftingMaterial(player: Player, materialId: string, amount: number): (number?, string?)
	if not CRAFTING_MATERIALS_KEY then
		return nil, "Crafting material persistence is not configured."
	end
	if not getActiveReplica(player) then
		return nil, "Player data is not loaded."
	end

	local normalizedMaterialId = CraftingMaterialConfig.NormalizeId(materialId)
	if not normalizedMaterialId then
		return nil, "materialId is required."
	end

	local normalizedAmount = math.max(1, clampWholeNumber(amount, 1))
	local state = self:GetCraftingMaterialsState(player)
	state.amountByMaterialId[normalizedMaterialId] = math.max(
		0,
		tonumber(state.amountByMaterialId[normalizedMaterialId]) or 0
	) + normalizedAmount
	self:Set(player, CRAFTING_MATERIALS_KEY, state)

	return state.amountByMaterialId[normalizedMaterialId], nil
end

function DataService:SetCraftingMaterialAmounts(
	player: Player,
	amountByMaterialId: { [string]: number }
): (boolean, string?)
	if not CRAFTING_MATERIALS_KEY then
		return false, "Crafting material persistence is not configured."
	end
	if not getActiveReplica(player) then
		return false, "Player data is not loaded."
	end

	self:Set(player, CRAFTING_MATERIALS_KEY, cloneCraftingMaterialsState({
		amountByMaterialId = amountByMaterialId,
	}))
	return true, "Crafting materials updated."
end

function DataService:RemoveCraftingMaterialStack(player: Player, materialId: string): (number?, string?)
	if not CRAFTING_MATERIALS_KEY then
		return nil, "Crafting material persistence is not configured."
	end
	if not getActiveReplica(player) then
		return nil, "Player data is not loaded."
	end

	local normalizedMaterialId = CraftingMaterialConfig.NormalizeId(materialId)
	if not normalizedMaterialId then
		return nil, "materialId is required."
	end

	local state = self:GetCraftingMaterialsState(player)
	local removedAmount = math.max(0, math.floor(tonumber(state.amountByMaterialId[normalizedMaterialId]) or 0))
	if removedAmount <= 0 then
		return nil, "You do not own that crafting material."
	end

	state.amountByMaterialId[normalizedMaterialId] = nil
	self:Set(player, CRAFTING_MATERIALS_KEY, state)

	return removedAmount, nil
end

function DataService:SetOwnedBodyPartFavorite(player: Player, ownedId: string, isFavorite: boolean): (OwnedBodyParts.OwnedBodyPartRecord?, string?)
	if not BODY_PARTS_KEY then
		return nil, "Body parts persistence is not configured."
	end
	local bodyPartsState = getReplicaValue(player, BODY_PARTS_KEY)
	if not getActiveReplica(player) then
		return nil, "Player data is not loaded."
	end
	if typeof(ownedId) ~= "string" or ownedId == "" then
		return nil, "ownedId is required."
	end

	local ownedById = if typeof(bodyPartsState) == "table" then bodyPartsState.ownedById else nil
	local updatedRecord = normalizeOwnedBodyPartRecord(
		typeof(ownedById) == "table" and ownedById[ownedId] or nil,
		ownedId
	)

	if not updatedRecord then
		return nil, string.format("Owned body part '%s' was not found.", ownedId)
	end

	updatedRecord.isFavorite = isFavorite == true
	setReplicaPathValue(player, BODY_PARTS_KEY, { "ownedById", ownedId, "isFavorite" }, updatedRecord.isFavorite)

	return deepCopy(updatedRecord), nil
end

function DataService:SetOwnedAuraFavorite(player: Player, ownedId: string, isFavorite: boolean): (OwnedAuras.OwnedAuraRecord?, string?)
	if not AURAS_KEY then
		return nil, "Aura persistence is not configured."
	end
	if not getActiveReplica(player) then
		return nil, "Player data is not loaded."
	end
	if typeof(ownedId) ~= "string" or ownedId == "" then
		return nil, "ownedId is required."
	end

	local updatedRecord: OwnedAuras.OwnedAuraRecord? = nil

	self:Set(player, AURAS_KEY, function(currentAurasState)
		local aurasState = cloneOwnedAurasState(currentAurasState)
		local existingRecord = aurasState.ownedById[ownedId]
		if not existingRecord then
			return aurasState
		end

		existingRecord.isFavorite = isFavorite == true
		updatedRecord = existingRecord
		aurasState.ownedById[ownedId] = existingRecord
		if existingRecord.auraId ~= "" then
			aurasState.ownedAuraIdByAuraId[existingRecord.auraId] = existingRecord.ownedId
		end
		return aurasState
	end)

	if not updatedRecord then
		return nil, string.format("Owned aura '%s' was not found.", ownedId)
	end

	return deepCopy(updatedRecord), nil
end

function DataService:SetOwnedAccessoryFavorite(
	player: Player,
	ownedId: string,
	isFavorite: boolean
): (OwnedAccessories.OwnedAccessoryRecord?, string?)
	if not ACCESSORIES_KEY then
		return nil, "Accessory persistence is not configured."
	end
	if not getActiveReplica(player) then
		return nil, "Player data is not loaded."
	end
	if typeof(ownedId) ~= "string" or ownedId == "" then
		return nil, "ownedId is required."
	end

	local accessoriesState = getReplicaValue(player, ACCESSORIES_KEY)
	local ownedById = if typeof(accessoriesState) == "table" then accessoriesState.ownedById else nil
	local updatedRecord = normalizeOwnedAccessoryRecord(
		typeof(ownedById) == "table" and ownedById[ownedId] or nil,
		ownedId
	)

	if not updatedRecord then
		return nil, string.format("Owned accessory '%s' was not found.", ownedId)
	end

	updatedRecord.isFavorite = isFavorite == true
	setReplicaPathValue(player, ACCESSORIES_KEY, { "ownedById", ownedId, "isFavorite" }, updatedRecord.isFavorite)

	return deepCopy(updatedRecord), nil
end

function DataService:SetOwnedPotionFavorite(player: Player, potionId: string, isFavorite: boolean): (OwnedPotions.OwnedPotionRecord?, string?)
	if not POTIONS_KEY then
		return nil, "Potion persistence is not configured."
	end
	if not getActiveReplica(player) then
		return nil, "Player data is not loaded."
	end

	local normalizedPotionId = PotionConfig.NormalizeId(potionId)
	if not normalizedPotionId then
		return nil, "potionId is required."
	end

	local updatedRecord: OwnedPotions.OwnedPotionRecord? = nil
	self:Set(player, POTIONS_KEY, function(currentPotionsState)
		local potionsState = cloneOwnedPotionsState(currentPotionsState)
		local existingRecord = potionsState.ownedByPotionId[normalizedPotionId]
		if not existingRecord then
			return potionsState
		end

		existingRecord.isFavorite = isFavorite == true
		updatedRecord = existingRecord
		potionsState.ownedByPotionId[normalizedPotionId] = existingRecord
		return potionsState
	end)

	if not updatedRecord then
		return nil, string.format("Owned potion '%s' was not found.", normalizedPotionId)
	end

	return deepCopy(updatedRecord), nil
end

function DataService:SetPotionActiveRemaining(player: Player, potionId: string, remainingSeconds: number?): (boolean, string?)
	if not POTIONS_KEY then
		return false, "Potion persistence is not configured."
	end
	if not getActiveReplica(player) then
		return false, "Player data is not loaded."
	end

	local normalizedPotionId = PotionConfig.NormalizeId(potionId)
	if not normalizedPotionId then
		return false, "potionId is required."
	end

	self:Set(player, POTIONS_KEY, function(currentPotionsState)
		local potionsState = cloneOwnedPotionsState(currentPotionsState)
		local resolvedRemainingSeconds = math.max(0, math.floor(tonumber(remainingSeconds) or 0))
		if resolvedRemainingSeconds > 0 then
			potionsState.activeByPotionId[normalizedPotionId] = resolvedRemainingSeconds
		else
			potionsState.activeByPotionId[normalizedPotionId] = nil
		end
		return potionsState
	end)

	return true, "Potion active state updated."
end

function DataService:SetPotionActiveRemainingMap(player: Player, activeByPotionId: { [string]: number }): (boolean, string?)
	if not POTIONS_KEY then
		return false, "Potion persistence is not configured."
	end
	if not getActiveReplica(player) then
		return false, "Player data is not loaded."
	end

	self:Set(player, POTIONS_KEY, function(currentPotionsState)
		local potionsState = cloneOwnedPotionsState(currentPotionsState)
		potionsState.activeByPotionId = {}
		if typeof(activeByPotionId) == "table" then
			for potionId, remainingSeconds in pairs(activeByPotionId) do
				local normalizedPotionId = PotionConfig.NormalizeId(potionId)
				local resolvedRemainingSeconds = math.max(0, math.floor(tonumber(remainingSeconds) or 0))
				if normalizedPotionId and resolvedRemainingSeconds > 0 then
					potionsState.activeByPotionId[normalizedPotionId] = resolvedRemainingSeconds
				end
			end
		end
		return potionsState
	end)

	return true, "Potion active state updated."
end

function DataService:Get(player: Player, key: string?)
	local profile = getActiveProfile(player)
	if profile and profile.Data then
		if key ~= nil then
			return deepCopy(profile.Data[key])
		end
		return deepCopy(profile.Data)
	end

	local timeoutAt = os.clock() + 15
	while os.clock() < timeoutAt do
		if player.Parent ~= Players then
			return nil
		end

		profile = getActiveProfile(player)
		if profile and profile.Data then
			if key ~= nil then
				return deepCopy(profile.Data[key])
			end
			return deepCopy(profile.Data)
		end

		task.wait()
	end

	return nil
end

function DataService:SendGlobalUpdate(sender: Player, targetId: number, updateType: string, payload: any)
	if not sender or not targetId or payload == nil then
		return
	end

	DataService.ProfileStore:GlobalUpdateProfileAsync(getKey(targetId), function(globalUpdates)
		globalUpdates:AddActiveUpdate({
			updateType = updateType,
			senderId = sender.UserId,
			sendTime = os.time(),
			data = payload,
		})
	end)
end

local function findLoadedPlayerByUserId(userId: number): Player?
	for player, profile in pairs(PROFILES) do
		if player.UserId == userId and profile and profile:IsActive() then
			return player
		end
	end
	return nil
end

local function waitForProfileRelease(userId: number, timeoutSeconds: number?): (boolean, string?)
	local timeoutAt = os.clock() + (timeoutSeconds or 15)

	while os.clock() < timeoutAt do
		if not findLoadedPlayerByUserId(userId) then
			return true, nil
		end
		task.wait(0.1)
	end

	return false, "Timed out waiting for the player's profile to release"
end

local function wipeProfileByUserId(userId: number): (boolean, string?)
	local resolvedUserId = tonumber(userId)
	if not resolvedUserId then
		return false, "UserId is required"
	end
	resolvedUserId = math.floor(resolvedUserId)

	local loadedPlayer = findLoadedPlayerByUserId(resolvedUserId)
	if loadedPlayer then
		loadedPlayer:Kick("Your data was reset. Please rejoin.")

		local released, releaseError = waitForProfileRelease(resolvedUserId, 15)
		if not released then
			return false, releaseError
		end
	end

	local profileKey = getKey(resolvedUserId)
	local ok, result = pcall(function()
		return DataService.ProfileStore:WipeProfileAsync(profileKey)
	end)
	if not ok then
		return false, tostring(result)
	end
	if result ~= true then
		return false, "WipeProfileAsync returned false"
	end

	return true, nil
end

function DataService:OfflineWipe(target: any): (boolean, string?)
	if typeof(target) == "number" then
		local resolvedUserId = math.floor(target)
		if findLoadedPlayerByUserId(resolvedUserId) then
			return false, "Cannot offline wipe a player whose profile is currently loaded in this server"
		end
		return wipeProfileByUserId(resolvedUserId)
	end

	if typeof(target) == "string" then
		local username = string.match(target, "%S+")
		if not username then
			return false, "Username is required"
		end

		local ok, resolvedUserId = pcall(function()
			return Players:GetUserIdFromNameAsync(username)
		end)
		if not ok then
			return false, tostring(resolvedUserId)
		end

		if findLoadedPlayerByUserId(resolvedUserId) then
			return false, "Cannot offline wipe a player whose profile is currently loaded in this server"
		end
		return wipeProfileByUserId(resolvedUserId)
	end

	return false, "Target must be a userId or username"
end

function DataService:WipeByUserId(userId: number): (boolean, string?)
	return wipeProfileByUserId(userId)
end

function DataService:WipeByUsername(username: string): (boolean, string?)
	local ok, resolvedUserId = pcall(function()
		return Players:GetUserIdFromNameAsync(username)
	end)
	if not ok then
		return false, tostring(resolvedUserId)
	end
	return wipeProfileByUserId(resolvedUserId)
end

return DataService
