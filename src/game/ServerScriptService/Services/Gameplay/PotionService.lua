local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Signal = require(ReplicatedStorage.Common.Signal)
local PotionRuntimeBonuses = require(ReplicatedStorage.Shared.Character.PotionRuntimeBonuses)
local PotionConfig = require(ReplicatedStorage.Shared.Config.PotionConfig)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)
local BossArenaArrivalService = require(script.Parent.BossArenaArrivalService)
local DataService = require(script.Parent.DataService)
local RequestLimiter = require(script.Parent.Common.RequestLimiter)

local REMOTES_FOLDER_NAME = "Remotes"
local POTIONS_FOLDER_NAME = "Potions"
local GET_STATE_REMOTE_NAME = "GetPotionState"
local USE_POTION_REMOTE_NAME = "UsePotion"
local TOGGLE_FAVORITE_REMOTE_NAME = "ToggleFavoriteOwnedPotion"
local SELL_POTION_REMOTE_NAME = "SellOwnedPotion"
local UPDATED_REMOTE_NAME = "PotionUpdated"
local EXPIRY_POLL_INTERVAL = 0.25
local BOSS_ARENA_PROFILE_ID = "boss_arena"

type ActivePotionEntry = {
	potionId: string,
	expiresAt: number,
}

local remotesFolder: Folder? = nil
local potionsFolder: Folder? = nil
local getStateRemote: RemoteFunction? = nil
local usePotionRemote: RemoteFunction? = nil
local toggleFavoriteRemote: RemoteFunction? = nil
local sellPotionRemote: RemoteFunction? = nil
local updatedRemote: RemoteEvent? = nil
local runtimeActiveByPlayer: { [Player]: { [string]: number } } = {}
local expiryLoopStarted = false

local PotionService = {}
PotionService.StateChanged = Signal.new()

local function response(ok: boolean, message: string, state: any?)
	return {
		ok = ok,
		message = message,
		state = state,
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

local function ensurePotionsFolder(): Folder
	local rootFolder = ensureRemotesFolder()
	if potionsFolder and potionsFolder.Parent == rootFolder then
		return potionsFolder
	end

	local existing = rootFolder:FindFirstChild(POTIONS_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		potionsFolder = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = POTIONS_FOLDER_NAME
	folder.Parent = rootFolder
	potionsFolder = folder
	return folder
end

local function ensureRemoteFunction(cachedRemote: RemoteFunction?, remoteName: string): RemoteFunction
	local folder = ensurePotionsFolder()
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
	local folder = ensurePotionsFolder()
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

local function getServerTimeNow(): number
	return Workspace:GetServerTimeNow()
end

local function getRuntimeState(player: Player): { [string]: number }
	local activeByPotionId = runtimeActiveByPlayer[player]
	if activeByPotionId then
		return activeByPotionId
	end

	activeByPotionId = {}
	runtimeActiveByPlayer[player] = activeByPotionId
	return activeByPotionId
end

local function buildNormalizedActiveByPotionId(activeByPotionId: { [string]: number }?, now: number): { [string]: number }
	local normalized = {}
	if typeof(activeByPotionId) ~= "table" then
		return normalized
	end

	for potionId, expiresAt in pairs(activeByPotionId) do
		local normalizedPotionId = PotionConfig.NormalizeId(potionId)
		local resolvedExpiresAt = tonumber(expiresAt)
		local config = PotionConfig.Get(normalizedPotionId)
		if normalizedPotionId and resolvedExpiresAt and config and resolvedExpiresAt > now then
			normalized[normalizedPotionId] = math.max(
				resolvedExpiresAt,
				tonumber(normalized[normalizedPotionId]) or 0
			)
		end
	end

	return normalized
end

local function areActiveMapsEqual(left: { [string]: number }?, right: { [string]: number }?): boolean
	local leftMap = if typeof(left) == "table" then left else {}
	local rightMap = if typeof(right) == "table" then right else {}

	for potionId, expiresAt in pairs(leftMap) do
		if rightMap[potionId] ~= expiresAt then
			return false
		end
	end

	for potionId, expiresAt in pairs(rightMap) do
		if leftMap[potionId] ~= expiresAt then
			return false
		end
	end

	return true
end

local function setRuntimeState(player: Player, activeByPotionId: { [string]: number })
	if next(activeByPotionId) == nil then
		runtimeActiveByPlayer[player] = nil
	else
		runtimeActiveByPlayer[player] = activeByPotionId
	end
end

local function buildActivePotionPayload(player: Player): { [string]: ActivePotionEntry }
	local payload = {}
	local now = getServerTimeNow()
	for potionId, expiresAt in pairs(buildNormalizedActiveByPotionId(runtimeActiveByPlayer[player], now)) do
		payload[potionId] = {
			potionId = potionId,
			expiresAt = expiresAt,
		}
	end
	return payload
end

local function persistRuntimeRemaining(player: Player, activeByPotionIdOverride: { [string]: number }?): boolean
	local activeByPotionId = activeByPotionIdOverride or runtimeActiveByPlayer[player]
	if typeof(activeByPotionId) ~= "table" then
		return false
	end

	local now = getServerTimeNow()
	local updates = {}
	for potionId, expiresAt in pairs(buildNormalizedActiveByPotionId(activeByPotionId, now)) do
		local remainingSeconds = math.max(0, math.ceil(expiresAt - now))
		if remainingSeconds > 0 then
			updates[potionId] = remainingSeconds
		end
	end
	DataService:SetPotionActiveRemainingMap(player, updates)
	return true
end

local function normalizeRuntimeStateForPlayer(player: Player): boolean
	local activeByPotionId = runtimeActiveByPlayer[player]
	if typeof(activeByPotionId) ~= "table" then
		return false
	end

	local normalized = buildNormalizedActiveByPotionId(activeByPotionId, getServerTimeNow())
	if areActiveMapsEqual(activeByPotionId, normalized) then
		if next(normalized) == nil then
			persistRuntimeRemaining(player, normalized)
			runtimeActiveByPlayer[player] = nil
			return true
		end
		return false
	end

	setRuntimeState(player, normalized)
	persistRuntimeRemaining(player, normalized)
	return true
end

local function clearExpiredPotionsForPlayer(player: Player): boolean
	return normalizeRuntimeStateForPlayer(player)
end

local function buildRemainingByPotionIdFromSnapshot(snapshot: any): { [string]: number }?
	if typeof(snapshot) ~= "table" then
		return nil
	end

	local capturedAtUnix = math.max(0, math.floor(tonumber(snapshot.capturedAtUnix) or 0))
	if capturedAtUnix <= 0 then
		return nil
	end

	local elapsedSeconds = math.max(0, os.time() - capturedAtUnix)
	local activeByPotionId = {}
	if typeof(snapshot.activeByPotionId) == "table" then
		for potionId, remainingSeconds in pairs(snapshot.activeByPotionId) do
			local normalizedPotionId = PotionConfig.NormalizeId(potionId)
			local config = PotionConfig.Get(normalizedPotionId)
			local resolvedRemainingSeconds = math.max(0, math.floor(tonumber(remainingSeconds) or 0) - elapsedSeconds)
			if normalizedPotionId and config and resolvedRemainingSeconds > 0 then
				activeByPotionId[normalizedPotionId] = math.max(
					resolvedRemainingSeconds,
					tonumber(activeByPotionId[normalizedPotionId]) or 0
				)
			end
		end
	end

	return if next(activeByPotionId) ~= nil then activeByPotionId else nil
end

local function getPotionSnapshotFromArrivalPayload(player: Player): any?
	if PlaceProfile.GetActiveProfile().id ~= BOSS_ARENA_PROFILE_ID then
		return nil
	end

	local payload = BossArenaArrivalService:GetArrivalPayload(player)
	local potionEffectsByUserId = if payload then payload.potionEffectsByUserId else nil
	if typeof(potionEffectsByUserId) ~= "table" then
		return nil
	end

	return potionEffectsByUserId[tostring(player.UserId)]
end

function PotionService:GetRuntimeBonuses(player: Player)
	local bonuses = PotionRuntimeBonuses.CreateEmpty()

	local now = getServerTimeNow()
	for potionId in pairs(buildNormalizedActiveByPotionId(runtimeActiveByPlayer[player], now)) do
		local config = PotionConfig.Get(potionId)
		if config then
			PotionRuntimeBonuses.ApplyConfigBonuses(bonuses, config)
		end
	end

	return bonuses
end

function PotionService:GetPotionState(player: Player, message: string?)
	return {
		ownedPotions = DataService:GetOwnedPotions(player),
		activePotions = buildActivePotionPayload(player),
		message = message,
	}
end

function PotionService:NotifyClient(player: Player, message: string?)
	ensureUpdatedRemote():FireClient(player, self:GetPotionState(player, message))
	self.StateChanged:Fire(player, self:GetRuntimeBonuses(player))
end

function PotionService:BuildTeleportSnapshot(player: Player): any?
	local activeByPotionId = {}
	local now = getServerTimeNow()

	for potionId, expiresAt in pairs(buildNormalizedActiveByPotionId(runtimeActiveByPlayer[player], now)) do
		local remainingSeconds = math.max(0, math.ceil(expiresAt - now))
		if remainingSeconds > 0 then
			activeByPotionId[potionId] = remainingSeconds
		end
	end

	if next(activeByPotionId) == nil then
		return nil
	end

	return {
		capturedAtUnix = os.time(),
		activeByPotionId = activeByPotionId,
	}
end

function PotionService:ApplyTeleportSnapshot(player: Player, snapshot: any): boolean
	local remainingByPotionId = buildRemainingByPotionIdFromSnapshot(snapshot)
	if remainingByPotionId == nil then
		return false
	end

	local now = getServerTimeNow()
	local activeByPotionId = {}
	for potionId, remainingSeconds in pairs(remainingByPotionId) do
		activeByPotionId[potionId] = now + remainingSeconds
	end

	setRuntimeState(player, buildNormalizedActiveByPotionId(activeByPotionId, now))
	DataService:SetPotionActiveRemainingMap(player, remainingByPotionId)
	self:NotifyClient(player)
	return true
end

function PotionService:GrantPotionUses(player: Player, potionId: string, amount: number): (boolean, string)
	local config = PotionConfig.Get(potionId)
	if not config then
		return false, "That potion does not exist."
	end

	local updatedRecord, err = DataService:AddOwnedPotionUses(player, config.id, amount)
	if not updatedRecord then
		return false, err or "Failed to grant potion uses."
	end

	self:NotifyClient(player, string.format('Granted %d %s use(s).', math.max(1, math.floor(amount)), config.label))
	return true, string.format('Granted %d %s use(s).', math.max(1, math.floor(amount)), config.label)
end

function PotionService:GrantAllPotionUses(player: Player, amountPerPotion: number?): (boolean, string, { [string]: any }?)
	local potionEntries = PotionConfig.GetAll()
	if #potionEntries == 0 then
		return false, "No potions are configured.", nil
	end

	local resolvedAmount = math.max(1, math.floor(tonumber(amountPerPotion) or 1))
	local grantedPotionIds = table.create(#potionEntries)

	for _, config in ipairs(potionEntries) do
		local updatedRecord, err = DataService:AddOwnedPotionUses(player, config.id, resolvedAmount)
		if not updatedRecord then
			return false, err or string.format("Failed to grant %s.", config.label), nil
		end

		table.insert(grantedPotionIds, config.id)
	end

	local message = string.format(
		"Granted %d use(s) for all %d configured potions.",
		resolvedAmount,
		#grantedPotionIds
	)
	self:NotifyClient(player, message)

	return true, message, {
		grantedPotionIds = grantedPotionIds,
		amountPerPotion = resolvedAmount,
		potionCount = #grantedPotionIds,
		state = self:GetPotionState(player, message),
	}
end

function PotionService:ClearActivePotions(player: Player): (boolean, string, { [string]: any }?)
	local activeByPotionId = buildNormalizedActiveByPotionId(runtimeActiveByPlayer[player], getServerTimeNow())
	local clearedPotionCount = 0
	for _ in pairs(activeByPotionId) do
		clearedPotionCount += 1
	end

	setRuntimeState(player, {})
	DataService:SetPotionActiveRemainingMap(player, {})

	local message = if clearedPotionCount > 0
		then string.format("Removed %d active potion effect(s).", clearedPotionCount)
		else "No potion effects were active."
	self:NotifyClient(player, message)

	return true, message, {
		clearedPotionCount = clearedPotionCount,
		state = self:GetPotionState(player, message),
	}
end

function PotionService:UsePotion(player: Player, potionId: string): (boolean, string)
	local config = PotionConfig.Get(potionId)
	if not config then
		return false, "That potion does not exist."
	end

	local ownedPotions = DataService:GetOwnedPotions(player)
	local ownedRecord = ownedPotions[config.id]
	if not ownedRecord or (tonumber(ownedRecord.amount) or 0) <= 0 then
		return false, string.format("You do not own any %s uses.", config.label)
	end

	local updatedRecord, consumeError = DataService:ConsumeOwnedPotionUses(player, config.id, 1)
	if consumeError ~= nil then
		return false, consumeError
	end

	local now = getServerTimeNow()
	local activeByPotionId = buildNormalizedActiveByPotionId(getRuntimeState(player), now)
	local currentExpiresAt = tonumber(activeByPotionId[config.id]) or 0
	local nextExpiresAt = math.max(currentExpiresAt, now) + config.durationSeconds
	activeByPotionId[config.id] = nextExpiresAt
	setRuntimeState(player, activeByPotionId)
	persistRuntimeRemaining(player)

	local remainingOwnedAmount = tonumber(updatedRecord and updatedRecord.amount) or 0
	local message = string.format('Used %s. %d use(s) left.', config.label, remainingOwnedAmount)
	self:NotifyClient(player, message)
	return true, message
end

function PotionService:ToggleFavoriteOwnedPotion(player: Player, potionId: string, requestedFavoriteState: boolean?): (boolean, string)
	local config = PotionConfig.Get(potionId)
	if not config then
		return false, "That potion does not exist."
	end

	local ownedRecord = DataService:GetOwnedPotions(player)[config.id]
	if not ownedRecord then
		return false, "You do not own that potion."
	end

	local nextFavoriteState = if typeof(requestedFavoriteState) == "boolean"
		then requestedFavoriteState
		else not (ownedRecord.isFavorite == true)
	local updatedRecord, err = DataService:SetOwnedPotionFavorite(player, config.id, nextFavoriteState)
	if not updatedRecord then
		return false, err or "Failed to update potion favorite state."
	end

	local message = if updatedRecord.isFavorite
		then string.format('Favorited %s.', config.label)
		else string.format('Unfavorited %s.', config.label)
	self:NotifyClient(player, message)
	return true, message
end

function PotionService:SellOwnedPotion(player: Player, potionId: string, quantity: number): (boolean, string)
	local config = PotionConfig.Get(potionId)
	if not config then
		return false, "That potion does not exist."
	end

	local sellQuantity = math.max(1, math.floor(tonumber(quantity) or 0))
	local ownedRecord = DataService:GetOwnedPotions(player)[config.id]
	local ownedAmount = tonumber(ownedRecord and ownedRecord.amount) or 0
	if ownedAmount <= 0 then
		return false, "You do not own that potion."
	end
	if sellQuantity > ownedAmount then
		return false, "You do not own that many potion uses."
	end

	local updatedRecord, err = DataService:ConsumeOwnedPotionUses(player, config.id, sellQuantity)
	if err ~= nil then
		return false, err
	end

	local payout = PotionConfig.GetSellPrice(config.id) * sellQuantity
	if payout > 0 then
		DataService:AddMoney(player, payout, "potion_sell")
	end

	local remainingOwnedAmount = tonumber(updatedRecord and updatedRecord.amount) or 0
	local message = string.format(
		'Sold %d %s use(s) for $%d. %d use(s) left.',
		sellQuantity,
		config.label,
		payout,
		remainingOwnedAmount
	)
	self:NotifyClient(player, message)
	return true, message
end

local function handleGetPotionState(player: Player)
	return response(true, "Loaded potion state.", PotionService:GetPotionState(player))
end

local function handleUsePotion(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Use potion payload must be a table.", PotionService:GetPotionState(player))
	end

	local ok, message = PotionService:UsePotion(player, payload.potionId)
	return response(ok, message, PotionService:GetPotionState(player))
end

local function handleToggleFavoriteOwnedPotion(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Favorite potion payload must be a table.", PotionService:GetPotionState(player))
	end

	local ok, message = PotionService:ToggleFavoriteOwnedPotion(player, payload.potionId, payload.isFavorite)
	return response(ok, message, PotionService:GetPotionState(player))
end

local function handleSellOwnedPotion(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Sell potion payload must be a table.", PotionService:GetPotionState(player))
	end

	local ok, message = PotionService:SellOwnedPotion(player, payload.potionId, payload.quantity)
	return response(ok, message, PotionService:GetPotionState(player))
end

function PotionService:OnStart()
	getStateRemote = ensureRemoteFunction(getStateRemote, GET_STATE_REMOTE_NAME)
	usePotionRemote = ensureRemoteFunction(usePotionRemote, USE_POTION_REMOTE_NAME)
	toggleFavoriteRemote = ensureRemoteFunction(toggleFavoriteRemote, TOGGLE_FAVORITE_REMOTE_NAME)
	sellPotionRemote = ensureRemoteFunction(sellPotionRemote, SELL_POTION_REMOTE_NAME)
	updatedRemote = ensureUpdatedRemote()

	getStateRemote.OnServerInvoke = function(player: Player)
		local allowed = RequestLimiter:Allow(player, "remote.potions.get_state")
		if not allowed then
			return response(false, "You're refreshing potion state too quickly.", PotionService:GetPotionState(player))
		end

		return handleGetPotionState(player)
	end
	usePotionRemote.OnServerInvoke = function(player: Player, payload: any)
		local allowed = RequestLimiter:Allow(player, "remote.potions.use")
		if not allowed then
			return response(false, "You're using potions too quickly.", PotionService:GetPotionState(player))
		end

		return handleUsePotion(player, payload)
	end
	toggleFavoriteRemote.OnServerInvoke = function(player: Player, payload: any)
		local allowed = RequestLimiter:Allow(player, "remote.potions.favorite")
		if not allowed then
			return response(false, "You're changing potion favorites too quickly.", PotionService:GetPotionState(player))
		end

		return handleToggleFavoriteOwnedPotion(player, payload)
	end
	sellPotionRemote.OnServerInvoke = function(player: Player, payload: any)
		local allowed = RequestLimiter:Allow(player, "remote.potions.sell")
		if not allowed then
			return response(false, "You're selling potions too quickly.", PotionService:GetPotionState(player))
		end

		return handleSellOwnedPotion(player, payload)
	end

	if not expiryLoopStarted then
		expiryLoopStarted = true
		task.spawn(function()
			while expiryLoopStarted do
				task.wait(EXPIRY_POLL_INTERVAL)
				for player in pairs(runtimeActiveByPlayer) do
					if clearExpiredPotionsForPlayer(player) then
						PotionService:NotifyClient(player, "Potion effect expired.")
					end
				end
			end
		end)
	end

	DataService.PlayerDataLoaded:Connect(function(player: Player)
		local persistedState = DataService:GetPotionsState(player)
		local activeByPotionId = {}
		local now = getServerTimeNow()
		for potionId, remainingSeconds in pairs(persistedState.activeByPotionId) do
			local config = PotionConfig.Get(potionId)
			local resolvedRemainingSeconds = math.max(0, math.floor(tonumber(remainingSeconds) or 0))
			if config and resolvedRemainingSeconds > 0 then
				activeByPotionId[potionId] = now + resolvedRemainingSeconds
			end
		end
		setRuntimeState(player, buildNormalizedActiveByPotionId(activeByPotionId, now))

		local appliedTeleportSnapshot = PotionService:ApplyTeleportSnapshot(player, getPotionSnapshotFromArrivalPayload(player))
		if not appliedTeleportSnapshot then
			PotionService:NotifyClient(player)
		end
	end)

	DataService.PlayerDataRemoving:Connect(function(player: Player)
		persistRuntimeRemaining(player)
	end)
end

function PotionService:OnPlayerRemoving(player: Player)
	persistRuntimeRemaining(player)
	runtimeActiveByPlayer[player] = nil
end

return PotionService
