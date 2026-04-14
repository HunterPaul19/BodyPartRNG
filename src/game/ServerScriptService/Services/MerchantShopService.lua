local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MerchantShopState = require(ReplicatedStorage.Shared.Character.MerchantShopState)
local Globals = require(ReplicatedStorage.Lists.Globals)
local PotionConfig = require(ReplicatedStorage.Shared.Config.PotionConfig)
local MerchantShopConfig = require(ReplicatedStorage.Shared.Config.MerchantShopConfig)
local Schema = require(ReplicatedStorage.Lists.Schema)
local DataService = require(script.Parent.DataService)
local PotionService = require(script.Parent.PotionService)

local REMOTES_FOLDER_NAME = "Remotes"
local MERCHANT_SHOP_FOLDER_NAME = "MerchantShop"
local GET_SHOP_STATE_REMOTE_NAME = "GetShopState"
local PURCHASE_SHOP_ITEM_REMOTE_NAME = "PurchaseShopItem"
local REFRESH_INTERVAL_SECONDS = 300
local MAX_STOCK_PER_ITEM = 10
local MERCHANT_SHOP_KEY = Schema.MerchantShop and Schema.MerchantShop.key or nil
local MONEY_KEY = Schema.Money and Schema.Money.key or nil

local remotesFolder: Folder? = nil
local merchantShopFolder: Folder? = nil
local getShopStateRemote: RemoteFunction? = nil
local purchaseShopItemRemote: RemoteFunction? = nil

local MerchantShopService = {}

local function response(ok: boolean, message: string, shopState: any?)
	return {
		ok = ok,
		message = message,
		shopState = shopState,
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

local function ensureMerchantShopFolder(): Folder
	local rootFolder = ensureRemotesFolder()
	if merchantShopFolder and merchantShopFolder.Parent == rootFolder then
		return merchantShopFolder
	end

	local existing = rootFolder:FindFirstChild(MERCHANT_SHOP_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		merchantShopFolder = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = MERCHANT_SHOP_FOLDER_NAME
	folder.Parent = rootFolder
	merchantShopFolder = folder
	return folder
end

local function ensureRemoteFunction(cachedRemote: RemoteFunction?, remoteName: string): RemoteFunction
	local folder = ensureMerchantShopFolder()
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

local function getCurrentCycleId(): number
	return math.floor(Workspace:GetServerTimeNow() / REFRESH_INTERVAL_SECONDS)
end

local function getRefreshesAt(cycleId: number): number
	return (cycleId + 1) * REFRESH_INTERVAL_SECONDS
end

local function createFullStockMap(): { [string]: number }
	local stockByPotionId = {}
	for _, entry in ipairs(MerchantShopConfig.GetAll()) do
		stockByPotionId[entry.potionId] = MAX_STOCK_PER_ITEM
	end
	return stockByPotionId
end

local function normalizeQuantity(quantity: any): number
	return math.max(0, math.floor(tonumber(quantity) or 0))
end

function MerchantShopService:_getRawState(player: Player): MerchantShopState.MerchantShopStateValue
	if not MERCHANT_SHOP_KEY then
		return MerchantShopState.CreateEmptyState()
	end

	return MerchantShopState.CloneState(DataService:Get(player, MERCHANT_SHOP_KEY))
end

function MerchantShopService:_saveState(player: Player, state: MerchantShopState.MerchantShopStateValue): MerchantShopState.MerchantShopStateValue
	local normalizedState = MerchantShopState.CloneState(state)
	if MERCHANT_SHOP_KEY then
		DataService:Set(player, MERCHANT_SHOP_KEY, normalizedState)
	end
	return normalizedState
end

function MerchantShopService:_resolveCurrentState(player: Player): MerchantShopState.MerchantShopStateValue
	local cycleId = getCurrentCycleId()
	local rawState = self:_getRawState(player)

	if rawState.cycleId ~= cycleId then
		return self:_saveState(player, {
			cycleId = cycleId,
			stockByPotionId = createFullStockMap(),
		})
	end

	local stockByPotionId = createFullStockMap()
	for potionId, stock in pairs(rawState.stockByPotionId) do
		stockByPotionId[potionId] = math.clamp(normalizeQuantity(stock), 0, MAX_STOCK_PER_ITEM)
	end

	local normalizedState = {
		cycleId = cycleId,
		stockByPotionId = stockByPotionId,
	}

	if rawState.cycleId ~= normalizedState.cycleId or rawState.stockByPotionId == nil then
		return self:_saveState(player, normalizedState)
	end

	for potionId, stock in pairs(stockByPotionId) do
		if rawState.stockByPotionId[potionId] ~= stock then
			return self:_saveState(player, normalizedState)
		end
	end

	return normalizedState
end

function MerchantShopService:_buildShopStatePayload(player: Player, resolvedState: MerchantShopState.MerchantShopStateValue?)
	local state = resolvedState or self:_resolveCurrentState(player)
	return {
		cycleId = state.cycleId,
		refreshesAt = getRefreshesAt(state.cycleId),
		stockByPotionId = MerchantShopState.CloneStockByPotionId(state.stockByPotionId),
	}
end

function MerchantShopService:_getAffordability(player: Player, totalPrice: number): boolean
	if not MONEY_KEY then
		return false
	end

	return DataService:GetMoney(player) >= totalPrice
end

function MerchantShopService:GetShopState(player: Player)
	return response(true, "Loaded merchant shop state.", self:_buildShopStatePayload(player))
end

function MerchantShopService:PurchaseShopItem(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Purchase payload must be a table.", self:_buildShopStatePayload(player))
	end

	local entry = MerchantShopConfig.GetByPotionId(payload.potionId)
	if not entry then
		return response(false, "That item is not sold here.", self:_buildShopStatePayload(player))
	end

	local potionConfig = PotionConfig.Get(entry.potionId)
	if not potionConfig then
		return response(false, "That potion is not configured.", self:_buildShopStatePayload(player))
	end

	local resolvedState = self:_resolveCurrentState(player)
	local availableStock = math.clamp(normalizeQuantity(resolvedState.stockByPotionId[entry.potionId]), 0, MAX_STOCK_PER_ITEM)
	if availableStock <= 0 then
		return response(false, string.format("%s is out of stock.", entry.shopLabel), self:_buildShopStatePayload(player, resolvedState))
	end

	local quantity = normalizeQuantity(payload.quantity)
	if quantity <= 0 then
		return response(false, "Enter a valid purchase amount.", self:_buildShopStatePayload(player, resolvedState))
	end
	if quantity > availableStock then
		return response(false, string.format("Only %d %s remain in stock.", availableStock, entry.shopLabel), self:_buildShopStatePayload(player, resolvedState))
	end

	local totalPrice = math.max(0, potionConfig.buyPrice) * quantity
	if not self:_getAffordability(player, totalPrice) then
		return response(false, string.format("You need %s$ to buy that.", Globals.formatNumber(totalPrice)), self:_buildShopStatePayload(player, resolvedState))
	end

	local previousMoney = DataService:GetMoney(player)
	local updatedMoney = DataService:AddMoney(player, -totalPrice, "merchant_shop_purchase")
	if updatedMoney > previousMoney then
		return response(false, "Could not process that purchase.", self:_buildShopStatePayload(player, resolvedState))
	end

	local grantCallOk, potionGrantSucceeded, potionGrantMessage = pcall(function()
		return PotionService:GrantPotionUses(player, entry.potionId, quantity)
	end)
	if not grantCallOk then
		DataService:AddMoney(player, totalPrice, "merchant_shop_purchase_refund")
		return response(false, potionGrantSucceeded or "Could not grant those potion uses.", self:_buildShopStatePayload(player, resolvedState))
	elseif not potionGrantSucceeded then
		DataService:AddMoney(player, totalPrice, "merchant_shop_purchase_refund")
		return response(false, potionGrantMessage or "Could not grant those potion uses.", self:_buildShopStatePayload(player, resolvedState))
	end

	local nextState = {
		cycleId = resolvedState.cycleId,
		stockByPotionId = MerchantShopState.CloneStockByPotionId(resolvedState.stockByPotionId),
	}
	nextState.stockByPotionId[entry.potionId] = math.clamp(availableStock - quantity, 0, MAX_STOCK_PER_ITEM)
	nextState = self:_saveState(player, nextState)

	local successMessage = string.format(
		"Purchased %d %s for %s$.",
		quantity,
		entry.shopLabel,
		Globals.formatNumber(totalPrice)
	)
	return response(true, successMessage, self:_buildShopStatePayload(player, nextState))
end

function MerchantShopService:OnStart()
	getShopStateRemote = ensureRemoteFunction(getShopStateRemote, GET_SHOP_STATE_REMOTE_NAME)
	purchaseShopItemRemote = ensureRemoteFunction(purchaseShopItemRemote, PURCHASE_SHOP_ITEM_REMOTE_NAME)

	getShopStateRemote.OnServerInvoke = function(player: Player)
		return self:GetShopState(player)
	end

	purchaseShopItemRemote.OnServerInvoke = function(player: Player, payload: any)
		return self:PurchaseShopItem(player, payload)
	end
end

return MerchantShopService
