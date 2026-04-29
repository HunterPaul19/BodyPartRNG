local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AccessoryConfig = require(ReplicatedStorage.Shared.Config.AccessoryConfig)
local BodyPartService = require(script.Parent.BodyPartService)
local DataService = require(script.Parent.DataService)
local RequestLimiter = require(script.Parent.Common.RequestLimiter)
local TutorialService = require(script.Parent.TutorialService)

local REMOTES_FOLDER_NAME = "Remotes"
local ACCESSORIES_REMOTES_FOLDER_NAME = "Accessories"
local GET_STATE_REMOTE_NAME = "GetAccessoryState"
local EQUIP_REMOTE_NAME = "EquipOwnedAccessory"
local UNEQUIP_REMOTE_NAME = "UnequipAccessorySlot"
local TOGGLE_FAVORITE_REMOTE_NAME = "ToggleFavoriteOwnedAccessory"
local SELL_OWNED_REMOTE_NAME = "SellOwnedAccessory"

local remotesFolder: Folder? = nil
local accessoriesRemotesFolder: Folder? = nil
local getStateRemote: RemoteFunction? = nil
local equipRemote: RemoteFunction? = nil
local unequipRemote: RemoteFunction? = nil
local toggleFavoriteRemote: RemoteFunction? = nil
local sellOwnedRemote: RemoteFunction? = nil

local AccessoryService = {}

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

local function ensureAccessoriesRemotesFolder(): Folder
	local rootFolder = ensureRemotesFolder()
	if accessoriesRemotesFolder and accessoriesRemotesFolder.Parent == rootFolder then
		return accessoriesRemotesFolder
	end

	local existing = rootFolder:FindFirstChild(ACCESSORIES_REMOTES_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		accessoriesRemotesFolder = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = ACCESSORIES_REMOTES_FOLDER_NAME
	folder.Parent = rootFolder
	accessoriesRemotesFolder = folder
	return folder
end

local function ensureRemoteFunction(cachedRemote: RemoteFunction?, remoteName: string): RemoteFunction
	local folder = ensureAccessoriesRemotesFolder()
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

local function waitForPlayerData(player: Player, timeoutSeconds: number?): boolean
	local timeoutAt = os.clock() + (timeoutSeconds or 20)
	while os.clock() < timeoutAt do
		if player.Parent ~= Players then
			return false
		end
		if DataService:Get(player) ~= nil then
			return true
		end
		task.wait(0.25)
	end
	return false
end

local function response(ok: boolean, message: string, state: any?)
	return {
		ok = ok,
		message = message,
		state = state,
	}
end

function AccessoryService:GetAccessoryState(player: Player, message: string?)
	return {
		ownedAccessories = DataService:GetOwnedAccessories(player),
		equippedAccessories = DataService:GetEquippedAccessories(player),
		message = message,
	}
end

local function rebuildAccessoryVisualIfNeeded(
	player: Player,
	slot: AccessoryConfig.AccessorySlot,
	previousOwnedId: string?
): (boolean, string?)
	if slot ~= "GearAccessory" and slot ~= "HeadAccessory" then
		return true, nil
	end

	local visualOk, visualMessage = BodyPartService:ApplySessionLoadout(player)
	if visualOk then
		return true, nil
	end

	DataService:SetEquippedAccessory(player, slot, previousOwnedId)
	BodyPartService:ApplySessionLoadout(player)
	return false, visualMessage or "Failed to apply the equipped accessory visual."
end

function AccessoryService:EquipOwnedAccessory(player: Player, ownedId: string): (boolean, string)
	if not waitForPlayerData(player, 10) then
		return false, "Player data is not ready yet."
	end
	if typeof(ownedId) ~= "string" or ownedId == "" then
		return false, "ownedId is required."
	end

	local ownedRecord = DataService:GetOwnedAccessories(player)[ownedId]
	if not ownedRecord then
		return false, "You do not own that accessory."
	end

	local config = AccessoryConfig.Get(ownedRecord.accessoryId)
	if not config then
		return false, "That accessory no longer exists."
	end

	local previousOwnedId = DataService:GetEquippedAccessories(player)[config.slot]
	local ok, message = DataService:SetEquippedAccessory(player, config.slot, ownedId)
	if not ok then
		return false, message or "Could not equip accessory."
	end

	local visualOk, visualMessage = rebuildAccessoryVisualIfNeeded(player, config.slot, previousOwnedId)
	if not visualOk then
		return false, visualMessage or "Could not equip accessory visual."
	end

	BodyPartService.LoadoutChanged:Fire(player)
	BodyPartService:NotifyClient(player, string.format('Equipped "%s".', config.label))
	TutorialService:RecordAccessoryEquipped(player, {
		ownedId = ownedId,
		accessoryId = config.id,
		slot = config.slot,
	})
	return true, string.format('Equipped "%s".', config.label)
end

function AccessoryService:UnequipAccessorySlot(player: Player, slot: string): (boolean, string)
	if not waitForPlayerData(player, 10) then
		return false, "Player data is not ready yet."
	end

	local normalizedSlot = AccessoryConfig.NormalizeSlot(slot)
	if not normalizedSlot then
		return false, "Accessory slot is invalid."
	end

	local equippedAccessories = DataService:GetEquippedAccessories(player)
	if equippedAccessories[normalizedSlot] == nil then
		return true, "Accessory slot is already empty."
	end

	local previousOwnedId = equippedAccessories[normalizedSlot]
	local ok, message = DataService:SetEquippedAccessory(player, normalizedSlot, nil)
	if not ok then
		return false, message or "Could not unequip accessory."
	end

	local visualOk, visualMessage = rebuildAccessoryVisualIfNeeded(player, normalizedSlot, previousOwnedId)
	if not visualOk then
		return false, visualMessage or "Could not unequip accessory visual."
	end

	BodyPartService.LoadoutChanged:Fire(player)
	BodyPartService:NotifyClient(player, "Unequipped accessory.")
	return true, "Unequipped accessory."
end

function AccessoryService:ToggleFavoriteOwnedAccessory(
	player: Player,
	ownedId: string,
	requestedFavoriteState: boolean?
): (boolean, string)
	if typeof(ownedId) ~= "string" or ownedId == "" then
		return false, "ownedId is required."
	end

	local ownedRecord = DataService:GetOwnedAccessories(player)[ownedId]
	if not ownedRecord then
		return false, "You do not own that accessory."
	end

	local nextFavoriteState = if typeof(requestedFavoriteState) == "boolean"
		then requestedFavoriteState
		else not (ownedRecord.isFavorite == true)
	local updatedRecord, updateError = DataService:SetOwnedAccessoryFavorite(player, ownedId, nextFavoriteState)
	if not updatedRecord then
		return false, updateError or "Failed to update favorite state."
	end

	local config = AccessoryConfig.Get(updatedRecord.accessoryId)
	local label = if config then config.label else "accessory"
	local message = if updatedRecord.isFavorite
		then string.format('Favorited "%s".', label)
		else string.format('Unfavorited "%s".', label)
	return true, message
end

function AccessoryService:SellOwnedAccessory(player: Player, ownedId: string): (boolean, string)
	if not waitForPlayerData(player, 10) then
		return false, "Player data is not ready yet."
	end
	if typeof(ownedId) ~= "string" or ownedId == "" then
		return false, "ownedId is required."
	end

	local ownedRecord = DataService:GetOwnedAccessories(player)[ownedId]
	if not ownedRecord then
		return false, "You do not own that accessory."
	end

	local config = AccessoryConfig.Get(ownedRecord.accessoryId)
	if not config then
		return false, "That accessory no longer exists."
	end

	local payout = AccessoryConfig.GetSellPrice(config.id)
	if payout <= 0 then
		return false, "That accessory cannot be sold."
	end

	local wasEquipped = DataService:GetEquippedAccessories(player)[config.slot] == ownedId
	if wasEquipped then
		local unequipped, unequipMessage = DataService:SetEquippedAccessory(player, config.slot, nil)
		if not unequipped then
			return false, unequipMessage or "Could not unequip accessory before selling."
		end

		local visualOk, visualMessage = rebuildAccessoryVisualIfNeeded(player, config.slot, ownedId)
		if not visualOk then
			return false, visualMessage or "Could not unequip accessory before selling."
		end
	end

	local removedRecord, removeError = DataService:RemoveOwnedAccessory(player, ownedId)
	if not removedRecord then
		if wasEquipped then
			DataService:SetEquippedAccessory(player, config.slot, ownedId)
			BodyPartService:ApplySessionLoadout(player)
		end
		return false, removeError or "Failed to remove the sold accessory."
	end

	DataService:AddMoney(player, payout, "accessory_sell")

	local message = string.format('Sold "%s" for $%s.', config.label, tostring(payout))
	if wasEquipped then
		BodyPartService.LoadoutChanged:Fire(player)
		BodyPartService:NotifyClient(player, message)
	end
	return true, message
end

local function handleGetAccessoryState(player: Player)
	return response(true, "Loaded accessory state.", AccessoryService:GetAccessoryState(player))
end

local function handleEquipOwnedAccessory(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Equip payload must be a table.", AccessoryService:GetAccessoryState(player))
	end

	local ok, message = AccessoryService:EquipOwnedAccessory(player, payload.ownedId)
	return response(ok, message, AccessoryService:GetAccessoryState(player))
end

local function handleUnequipAccessorySlot(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Unequip payload must be a table.", AccessoryService:GetAccessoryState(player))
	end

	local ok, message = AccessoryService:UnequipAccessorySlot(player, payload.slot)
	return response(ok, message, AccessoryService:GetAccessoryState(player))
end

local function handleToggleFavoriteOwnedAccessory(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Favorite payload must be a table.", AccessoryService:GetAccessoryState(player))
	end

	local ok, message = AccessoryService:ToggleFavoriteOwnedAccessory(player, payload.ownedId, payload.isFavorite)
	return response(ok, message, AccessoryService:GetAccessoryState(player))
end

local function handleSellOwnedAccessory(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Sell payload must be a table.", AccessoryService:GetAccessoryState(player))
	end

	local ok, message = AccessoryService:SellOwnedAccessory(player, payload.ownedId)
	return response(ok, message, AccessoryService:GetAccessoryState(player))
end

function AccessoryService:OnStart()
	getStateRemote = ensureRemoteFunction(getStateRemote, GET_STATE_REMOTE_NAME)
	equipRemote = ensureRemoteFunction(equipRemote, EQUIP_REMOTE_NAME)
	unequipRemote = ensureRemoteFunction(unequipRemote, UNEQUIP_REMOTE_NAME)
	toggleFavoriteRemote = ensureRemoteFunction(toggleFavoriteRemote, TOGGLE_FAVORITE_REMOTE_NAME)
	sellOwnedRemote = ensureRemoteFunction(sellOwnedRemote, SELL_OWNED_REMOTE_NAME)

	getStateRemote.OnServerInvoke = function(player: Player)
		if not RequestLimiter:Allow(player, "remote.accessories.get_state") then
			return response(false, "You're refreshing accessory state too quickly.", AccessoryService:GetAccessoryState(player))
		end
		return handleGetAccessoryState(player)
	end

	equipRemote.OnServerInvoke = function(player: Player, payload: any)
		if not RequestLimiter:Allow(player, "remote.accessories.equip") then
			return response(false, "You're equipping accessories too quickly.", AccessoryService:GetAccessoryState(player))
		end
		return handleEquipOwnedAccessory(player, payload)
	end

	unequipRemote.OnServerInvoke = function(player: Player, payload: any)
		if not RequestLimiter:Allow(player, "remote.accessories.unequip") then
			return response(false, "You're unequipping accessories too quickly.", AccessoryService:GetAccessoryState(player))
		end
		return handleUnequipAccessorySlot(player, payload)
	end

	toggleFavoriteRemote.OnServerInvoke = function(player: Player, payload: any)
		if not RequestLimiter:Allow(player, "remote.accessories.favorite") then
			return response(false, "You're changing accessory favorites too quickly.", AccessoryService:GetAccessoryState(player))
		end
		return handleToggleFavoriteOwnedAccessory(player, payload)
	end

	sellOwnedRemote.OnServerInvoke = function(player: Player, payload: any)
		if not RequestLimiter:Allow(player, "remote.accessories.sell") then
			return response(false, "You're selling accessories too quickly.", AccessoryService:GetAccessoryState(player))
		end
		return handleSellOwnedAccessory(player, payload)
	end
end

return AccessoryService
