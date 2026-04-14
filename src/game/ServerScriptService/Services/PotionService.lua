local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Signal = require(ReplicatedStorage.Common.Signal)
local PotionConfig = require(ReplicatedStorage.Shared.Config.PotionConfig)
local DataService = require(script.Parent.DataService)

local REMOTES_FOLDER_NAME = "Remotes"
local POTIONS_FOLDER_NAME = "Potions"
local GET_STATE_REMOTE_NAME = "GetPotionState"
local USE_POTION_REMOTE_NAME = "UsePotion"
local TOGGLE_FAVORITE_REMOTE_NAME = "ToggleFavoriteOwnedPotion"
local SELL_POTION_REMOTE_NAME = "SellOwnedPotion"
local UPDATED_REMOTE_NAME = "PotionUpdated"
local EXPIRY_POLL_INTERVAL = 0.25

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

local function buildActivePotionPayload(player: Player): { [string]: ActivePotionEntry }
	local payload = {}
	local now = getServerTimeNow()
	local activeByPotionId = runtimeActiveByPlayer[player]
	if typeof(activeByPotionId) ~= "table" then
		return payload
	end

	for potionId, expiresAt in pairs(activeByPotionId) do
		local remainingSeconds = expiresAt - now
		if remainingSeconds > 0 then
			payload[potionId] = {
				potionId = potionId,
				expiresAt = expiresAt,
			}
		end
	end

	return payload
end

local function persistRuntimeRemaining(player: Player)
	local now = getServerTimeNow()
	local updates = {}
	local activeByPotionId = runtimeActiveByPlayer[player]
	if typeof(activeByPotionId) == "table" then
		for potionId, expiresAt in pairs(activeByPotionId) do
			local remainingSeconds = math.max(0, math.ceil(expiresAt - now))
			if remainingSeconds > 0 then
				updates[potionId] = remainingSeconds
			end
		end
	end
	DataService:SetPotionActiveRemainingMap(player, updates)
end

local function clearExpiredPotionsForPlayer(player: Player): boolean
	local activeByPotionId = runtimeActiveByPlayer[player]
	if typeof(activeByPotionId) ~= "table" then
		return false
	end

	local now = getServerTimeNow()
	local didChange = false
	for potionId, expiresAt in pairs(activeByPotionId) do
		if expiresAt <= now then
			activeByPotionId[potionId] = nil
			DataService:SetPotionActiveRemaining(player, potionId, nil)
			didChange = true
		end
	end

	if next(activeByPotionId) == nil then
		runtimeActiveByPlayer[player] = nil
	end

	return didChange
end

function PotionService:GetRuntimeBonuses(player: Player)
	local bonuses = {
		passiveIncomeMultiplier = 1,
		luckBonus = 0,
		rollSpeedBonus = 0,
	}

	local activeByPotionId = runtimeActiveByPlayer[player]
	if typeof(activeByPotionId) ~= "table" then
		return bonuses
	end

	local now = getServerTimeNow()
	for potionId, expiresAt in pairs(activeByPotionId) do
		if expiresAt > now then
			local config = PotionConfig.Get(potionId)
			if config then
				if tonumber(config.passiveIncomeMultiplier) and config.passiveIncomeMultiplier > 1 then
					bonuses.passiveIncomeMultiplier *= config.passiveIncomeMultiplier
				end
				bonuses.luckBonus += tonumber(config.luckBonus) or 0
				bonuses.rollSpeedBonus += tonumber(config.rollSpeedBonus) or 0
			end
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
	local activeByPotionId = getRuntimeState(player)
	local nextExpiresAt = math.max(now, tonumber(activeByPotionId[config.id]) or 0) + config.durationSeconds
	activeByPotionId[config.id] = nextExpiresAt
	DataService:SetPotionActiveRemaining(player, config.id, math.ceil(nextExpiresAt - now))

	local remainingOwnedAmount = tonumber(updatedRecord and updatedRecord.amount) or 0
	local message = if nextExpiresAt - now > config.durationSeconds
		then string.format('Extended %s. %d use(s) left.', config.label, remainingOwnedAmount)
		else string.format('Used %s. %d use(s) left.', config.label, remainingOwnedAmount)
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

	getStateRemote.OnServerInvoke = handleGetPotionState
	usePotionRemote.OnServerInvoke = handleUsePotion
	toggleFavoriteRemote.OnServerInvoke = handleToggleFavoriteOwnedPotion
	sellPotionRemote.OnServerInvoke = handleSellOwnedPotion

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
		if next(activeByPotionId) ~= nil then
			runtimeActiveByPlayer[player] = activeByPotionId
		end
		PotionService:NotifyClient(player)
	end)

	DataService.PlayerDataRemoving:Connect(function(player: Player)
		persistRuntimeRemaining(player)
	end)
end

function PotionService:OnPlayerRemoving(player: Player)
	runtimeActiveByPlayer[player] = nil
end

return PotionService
