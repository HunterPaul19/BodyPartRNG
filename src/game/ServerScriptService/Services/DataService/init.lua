local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Globals = require(ReplicatedStorage.Lists.Globals)
local Schema = require(ReplicatedStorage.Lists.Schema)
local Signal = require(ReplicatedStorage.Common.Signal)
local BodyPartLoadout = require(ReplicatedStorage.Shared.Character.BodyPartLoadout)
local OwnedBodyParts = require(ReplicatedStorage.Shared.Character.OwnedBodyParts)
local OwnedRollTypes = require(ReplicatedStorage.Shared.Character.OwnedRollTypes)
local RollTargetRegions = require(ReplicatedStorage.Shared.Character.RollTargetRegions)
local AchievementState = require(ReplicatedStorage.Shared.Titles.AchievementState)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local RollingConfig = require(ReplicatedStorage.Shared.Config.RollingConfig)
local RollTypes = require(ReplicatedStorage.Shared.Config.RollTypes)
local SizeConfig = require(ReplicatedStorage.Shared.Config.SizeConfig)
local ProfileService = require(ServerScriptService.Packages.ProfileService)
local ReplicaService = require(ServerScriptService.Packages.ReplicaService)
local BodyPartSerialStore = require(script.BodyPartSerialStore)
local Leaderboards = require(script.Leaderboards)

local SCOPE = Globals.SCOPE
local DEBUG = false and RunService:IsStudio()
local USE_MOCK_DATA_IN_STUDIO = false
local PROFILE_CLASS_TOKEN = ReplicaService.NewClassToken(SCOPE)
local TIME_PLAYED_FLUSH_INTERVAL = 30

local LEGACY_CASH_KEY = "cash"
local LEGACY_OWNED_ROLL_TYPES_KEY = "ownedRollTypes"
local MONEY_KEY = Schema.Money and Schema.Money.key or nil
local TIME_PLAYED_KEY = Schema.TimePlayed and Schema.TimePlayed.key or nil
local BODY_PARTS_KEY = Schema.BodyParts and Schema.BodyParts.key or nil
local EQUIPPED_LOADOUT_KEY = Schema.EquippedLoadout and Schema.EquippedLoadout.key or nil
local SUCCESSFUL_ROLL_COUNT_KEY = Schema.SuccessfulRollCount and Schema.SuccessfulRollCount.key or nil
local EQUIPPED_TITLE_ID_KEY = Schema.EquippedTitleId and Schema.EquippedTitleId.key or nil
local ACHIEVEMENTS_KEY = Schema.Achievements and Schema.Achievements.key or nil
local VIP_OWNED_KEY = Schema.VipOwned and Schema.VipOwned.key or nil
local SELECTED_ROLL_TYPE_KEY = Schema.SelectedRollType and Schema.SelectedRollType.key or nil
local SELECTED_ROLL_REGION_KEY = Schema.SelectedRollRegion and Schema.SelectedRollRegion.key or nil
local QUICK_ROLL_ENABLED_KEY = Schema.QuickRollEnabled and Schema.QuickRollEnabled.key or nil
local AUTO_SELL_RARITIES_KEY = Schema.AutoSellRarities and Schema.AutoSellRarities.key or nil

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

local PROFILES: { [Player]: any } = {}
local REPLICAS: { [Player]: any } = {}
local timePlayedSessionStartedAt: { [Player]: number } = {}
local timePlayedLastFlushAt: { [Player]: number } = {}
local timePlayedLoopStarted = false

local GlobalUpdateProcessed = Signal.new()
local PlayerDataLoaded = Signal.new()
local DataChanged = Signal.new()
local MoneyChanged = Signal.new()
local SuccessfulRollIncremented = Signal.new()
local TimePlayedFlushed = Signal.new()
local OwnedBodyPartAdded = Signal.new()
local EquippedTitleChanged = Signal.new()

local function toNonNegativeWhole(value: any): number
	return math.max(0, math.floor(tonumber(value) or 0))
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
		value.Value = Globals.formatNumber(tonumber(profile.Data[MONEY_KEY]) or 0, true)
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
		money.Value = Globals.formatNumber(tonumber(moneyValue) or 0, true)
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
		if key == EQUIPPED_TITLE_ID_KEY then
			local normalizedEquippedTitleId = normalizeOptionalString(value)
			player:SetAttribute(attributeName, if normalizedEquippedTitleId ~= "" then normalizedEquippedTitleId else nil)
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
DataService.DataChanged = DataChanged
DataService.MoneyChanged = MoneyChanged
DataService.SuccessfulRollIncremented = SuccessfulRollIncremented
DataService.TimePlayedFlushed = TimePlayedFlushed
DataService.OwnedBodyPartAdded = OwnedBodyPartAdded
DataService.EquippedTitleChanged = EquippedTitleChanged

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
	local mutationMultiplier = tonumber(record and record.mutationMultiplier)
	if mutationMultiplier == nil or mutationMultiplier <= 0 then
		mutationMultiplier = MutationConfig.GetMultiplier(mutationId)
	end

	return mutationId, mutationDisplayName, mutationMultiplier
end

local function normalizeSizeSnapshot(record: any): (string, number)
	local sizeId = SizeConfig.NormalizeId(record and record.sizeId)
	local sizeMultiplier = tonumber(record and record.sizeMultiplier)
	if sizeMultiplier == nil or sizeMultiplier <= 0 then
		sizeMultiplier = SizeConfig.GetMultiplier(sizeId)
	end

	return sizeId, sizeMultiplier
end

local function normalizeOwnedBodyPartRecord(record: any, fallbackOwnedId: string?): OwnedBodyParts.OwnedBodyPartRecord?
	if typeof(record) ~= "table" then
		return nil
	end

	local pieceId = record.pieceId
	if typeof(pieceId) ~= "string" or pieceId == "" then
		return nil
	end

	local piece = BodyPartsCatalog.GetPiece(pieceId)
	if not piece then
		return nil
	end

	local setConfig = BodyPartsCatalog.GetSetForPiece(pieceId)
	local mutationId, mutationDisplayName, mutationMultiplier = normalizeMutationSnapshot(record)
	local sizeId, sizeMultiplier = normalizeSizeSnapshot(record)
	local displayOddsDenominator = math.max(
		1,
		clampWholeNumber(record.displayOddsDenominator or record.rarityDenominator or (setConfig and setConfig.rollDisplay.chance) or piece.rarity, 1)
	)
	local variantMultiplier = tonumber(record.variantMultiplier)
	if variantMultiplier == nil or variantMultiplier <= 0 then
		variantMultiplier = mutationMultiplier + sizeMultiplier - 1
	end

	local finalPassiveIncomePerSecond = tonumber(record.finalPassiveIncomePerSecond)
	if finalPassiveIncomePerSecond == nil or finalPassiveIncomePerSecond < 0 then
		finalPassiveIncomePerSecond = (tonumber(piece.passiveIncomePerSecond) or 0) * variantMultiplier
	end

	return {
		ownedId = if typeof(record.ownedId) == "string" and record.ownedId ~= "" then record.ownedId else (fallbackOwnedId or ""),
		pieceId = pieceId,
		rarityDenominator = math.max(1, clampWholeNumber(record.rarityDenominator or displayOddsDenominator, 1)),
		rolledSetId = if typeof(record.rolledSetId) == "string" and record.rolledSetId ~= ""
			then record.rolledSetId
			else if setConfig then setConfig.id else nil,
		rolledSetDisplayName = if typeof(record.rolledSetDisplayName) == "string" and record.rolledSetDisplayName ~= ""
			then record.rolledSetDisplayName
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

local function cloneOwnedBodyPartsState(state: OwnedBodyParts.OwnedBodyPartsState?): OwnedBodyParts.OwnedBodyPartsState
	local ownedById = {}
	local discoveredPieceIds = {}
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
				if isDiscovered == true and typeof(pieceId) == "string" and BodyPartsCatalog.GetPiece(pieceId) then
					discoveredPieceIds[pieceId] = true
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
		nextOwnedId = nextOwnedId,
	}
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
	if ACHIEVEMENTS_KEY then
		data[ACHIEVEMENTS_KEY] = AchievementState.Normalize(data[ACHIEVEMENTS_KEY])
	end
	if VIP_OWNED_KEY then
		data[VIP_OWNED_KEY] = data[VIP_OWNED_KEY] == true
	end
	if QUICK_ROLL_ENABLED_KEY then
		data[QUICK_ROLL_ENABLED_KEY] = data[QUICK_ROLL_ENABLED_KEY] == true
	end
	if AUTO_SELL_RARITIES_KEY then
		data[AUTO_SELL_RARITIES_KEY] = RollingConfig.NormalizeAutoSellState(data[AUTO_SELL_RARITIES_KEY])
	end
	if BODY_PARTS_KEY then
		data[BODY_PARTS_KEY] = cloneOwnedBodyPartsState(data[BODY_PARTS_KEY])
	end
	if EQUIPPED_LOADOUT_KEY then
		data[EQUIPPED_LOADOUT_KEY] = BodyPartLoadout.NormalizeEquippedState(data[EQUIPPED_LOADOUT_KEY])
	end
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

local profileStoreName = if DEBUG then "studio" else SCOPE
local profileTemplate = buildStructureFromSchema(Schema)
local profileStore = ProfileService.GetProfileStore(profileStoreName, profileTemplate)
if RunService:IsStudio() and USE_MOCK_DATA_IN_STUDIO then
	profileStore = profileStore.Mock
end

DataService.ProfileStore = profileStore

function DataService:OnStart()
	Leaderboards.start(self)
	startTimePlayedLoop()
end

function DataService:OnPlayerAdded(player: Player)
	local profile = DataService.ProfileStore:LoadProfileAsync(getKey(player.UserId))
	if not profile then
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
	task.defer(function()
		Leaderboards.refresh(self)
	end)
end

function DataService:OnPlayerRemoving(player: Player)
	flushTimePlayedForPlayer(player, true)
	Leaderboards.flushPlayer(self, player)

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
	return deepCopy(newValue), deepCopy(currentValue)
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

function DataService:GetEquippedLoadout(player: Player): BodyPartLoadout.EquippedState
	if not EQUIPPED_LOADOUT_KEY then
		return BodyPartLoadout.CreateEmptyEquippedState()
	end

	return BodyPartLoadout.NormalizeEquippedState(self:Get(player, EQUIPPED_LOADOUT_KEY))
end

function DataService:GetMoney(player: Player): number
	if not MONEY_KEY then
		return 0
	end

	return math.max(0, tonumber(self:Get(player, MONEY_KEY)) or 0)
end

function DataService:AdjustMoney(player: Player, delta: number): number
	if not MONEY_KEY then
		return 0
	end
	if not getActiveReplica(player) then
		return 0
	end

	local previousValue = self:GetMoney(player)
	local updatedValue = previousValue
	self:Set(player, MONEY_KEY, function(currentValue)
		updatedValue = math.max(0, (tonumber(currentValue) or 0) + (tonumber(delta) or 0))
		return updatedValue
	end)
	MoneyChanged:Fire(player, previousValue, updatedValue, tonumber(delta) or 0)

	return updatedValue
end

function DataService:AddMoney(player: Player, amount: number): number
	return self:AdjustMoney(player, amount)
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
	local updatedValue = 0
	self:Set(player, SUCCESSFUL_ROLL_COUNT_KEY, function(currentValue)
		updatedValue = math.max(0, clampWholeNumber(currentValue, 0)) + 1
		return updatedValue
	end)
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

function DataService:GetNextSerialForPiece(pieceId: string): (number?, string?)
	return BodyPartSerialStore:GetNextSerialForPiece(pieceId)
end

function DataService:GetTotalInExistenceForPiece(pieceId: string): (number?, string?)
	return BodyPartSerialStore:GetTotalInExistenceForPiece(pieceId)
end

function DataService:AddOwnedBodyPart(player: Player, payload: OwnedBodyParts.OwnedBodyPartGrantPayload): (OwnedBodyParts.OwnedBodyPartRecord?, string?)
	if not BODY_PARTS_KEY then
		return nil, "Body parts persistence is not configured."
	end
	if not getActiveReplica(player) then
		return nil, "Player data is not loaded."
	end

	if typeof(payload) ~= "table" then
		return nil, "Owned body part payload must be a table."
	end

	local pieceId = payload.pieceId
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
		sizeMultiplier = SizeConfig.GetMultiplier(payload.sizeId)
	elseif not isPositiveFiniteNumber(sizeMultiplier) then
		return nil, "sizeMultiplier must be a positive number when provided."
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

	local serialNumber, serialError = self:GetNextSerialForPiece(pieceId)
	if not serialNumber then
		return nil, serialError or "Failed to allocate body part serial number."
	end

	local createdRecord: OwnedBodyParts.OwnedBodyPartRecord? = nil
	local updatedBodyPartsState: OwnedBodyParts.OwnedBodyPartsState? = nil

	self:Set(player, BODY_PARTS_KEY, function(currentBodyPartsState)
		local bodyPartsState = cloneOwnedBodyPartsState(currentBodyPartsState)
		local ownedId = OwnedBodyParts.CreateOwnedId(bodyPartsState.nextOwnedId)

		local normalizedRecord = normalizeOwnedBodyPartRecord({
			ownedId = ownedId,
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
			serialNumber = serialNumber,
		}, ownedId)
		if not normalizedRecord then
			return bodyPartsState
		end

		createdRecord = normalizedRecord

		bodyPartsState.ownedById[ownedId] = createdRecord
		bodyPartsState.discoveredPieceIds[pieceId] = true
		bodyPartsState.nextOwnedId += 1
		updatedBodyPartsState = cloneOwnedBodyPartsState(bodyPartsState)
		return bodyPartsState
	end)

	if not createdRecord then
		return nil, "Failed to store owned body part."
	end

	if updatedBodyPartsState then
		OwnedBodyPartAdded:Fire(player, deepCopy(createdRecord), cloneOwnedBodyPartsState(updatedBodyPartsState))
	end

	return deepCopy(createdRecord), nil
end

function DataService:RemoveOwnedBodyPart(player: Player, ownedId: string): (OwnedBodyParts.OwnedBodyPartRecord?, string?)
	if not BODY_PARTS_KEY then
		return nil, "Body parts persistence is not configured."
	end
	if not getActiveReplica(player) then
		return nil, "Player data is not loaded."
	end

	if typeof(ownedId) ~= "string" or ownedId == "" then
		return nil, "ownedId is required."
	end

	local removedRecord: OwnedBodyParts.OwnedBodyPartRecord? = nil

	self:Set(player, BODY_PARTS_KEY, function(currentBodyPartsState)
		local bodyPartsState = cloneOwnedBodyPartsState(currentBodyPartsState)
		removedRecord = bodyPartsState.ownedById[ownedId]
		if removedRecord then
			bodyPartsState.ownedById[ownedId] = nil
		end
		return bodyPartsState
	end)

	if not removedRecord then
		return nil, string.format("Owned body part '%s' was not found.", ownedId)
	end

	return deepCopy(removedRecord), nil
end

function DataService:SetOwnedBodyPartFavorite(player: Player, ownedId: string, isFavorite: boolean): (OwnedBodyParts.OwnedBodyPartRecord?, string?)
	if not BODY_PARTS_KEY then
		return nil, "Body parts persistence is not configured."
	end
	if not getActiveReplica(player) then
		return nil, "Player data is not loaded."
	end
	if typeof(ownedId) ~= "string" or ownedId == "" then
		return nil, "ownedId is required."
	end

	local updatedRecord: OwnedBodyParts.OwnedBodyPartRecord? = nil

	self:Set(player, BODY_PARTS_KEY, function(currentBodyPartsState)
		local bodyPartsState = cloneOwnedBodyPartsState(currentBodyPartsState)
		local existingRecord = bodyPartsState.ownedById[ownedId]
		if not existingRecord then
			return bodyPartsState
		end

		existingRecord.isFavorite = isFavorite == true
		updatedRecord = existingRecord
		bodyPartsState.ownedById[ownedId] = existingRecord
		return bodyPartsState
	end)

	if not updatedRecord then
		return nil, string.format("Owned body part '%s' was not found.", ownedId)
	end

	return deepCopy(updatedRecord), nil
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
