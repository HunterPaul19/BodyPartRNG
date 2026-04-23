local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BodyPartCollection = require(ReplicatedStorage.Shared.Character.BodyPartCollection)
local BodyPartRegions = require(ReplicatedStorage.Shared.Character.BodyPartRegions)
local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local Notify = require(ReplicatedStorage.Shared.UI.Notify)
local BodyPartService = require(script.Parent.BodyPartService)
local DataService = require(script.Parent.DataService)
local RequestLimiter = require(script.Parent.Common.RequestLimiter)

local REMOTES_FOLDER_NAME = "Remotes"
local AURAS_REMOTES_FOLDER_NAME = "Auras"
local GET_STATE_REMOTE_NAME = "GetAuraState"
local EQUIP_REMOTE_NAME = "EquipOwnedAura"
local TOGGLE_FAVORITE_REMOTE_NAME = "ToggleFavoriteOwnedAura"
local GET_EXISTENCE_REMOTE_NAME = "GetTotalInExistenceForAura"

local remotesFolder: Folder? = nil
local aurasRemotesFolder: Folder? = nil
local getStateRemote: RemoteFunction? = nil
local equipRemote: RemoteFunction? = nil
local toggleFavoriteRemote: RemoteFunction? = nil
local getExistenceRemote: RemoteFunction? = nil
local activeGrantLocks: { [Player]: { [string]: boolean } } = {}

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

local function ensureAurasRemotesFolder(): Folder
	local rootFolder = ensureRemotesFolder()
	if aurasRemotesFolder and aurasRemotesFolder.Parent == rootFolder then
		return aurasRemotesFolder
	end

	local existing = rootFolder:FindFirstChild(AURAS_REMOTES_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		aurasRemotesFolder = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = AURAS_REMOTES_FOLDER_NAME
	folder.Parent = rootFolder
	aurasRemotesFolder = folder
	return folder
end

local function ensureRemoteFunction(cachedRemote: RemoteFunction?, remoteName: string): RemoteFunction
	local folder = ensureAurasRemotesFolder()
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

local function acquireGrantLock(player: Player, auraId: string, timeoutSeconds: number?): boolean
	local playerLocks = activeGrantLocks[player]
	if not playerLocks then
		playerLocks = {}
		activeGrantLocks[player] = playerLocks
	end

	local timeoutAt = os.clock() + (timeoutSeconds or 10)
	while playerLocks[auraId] == true do
		if player.Parent ~= Players then
			return false
		end

		task.wait()
		if os.clock() >= timeoutAt then
			return false
		end
	end

	playerLocks[auraId] = true
	return true
end

local function releaseGrantLock(player: Player, auraId: string)
	local playerLocks = activeGrantLocks[player]
	if not playerLocks then
		return
	end

	playerLocks[auraId] = nil
	if next(playerLocks) == nil then
		activeGrantLocks[player] = nil
	end
end

local function getUnlockableCompletedSetIds(bodyPartsState: any): { [string]: boolean }
	local completedSetIds = {}
	for _, summary in ipairs(BodyPartCollection.GetAllSetSummaries(bodyPartsState)) do
		if summary.discoveredCount >= #BodyPartRegions.Order then
			completedSetIds[summary.setId] = true
		end
	end

	return completedSetIds
end

local AuraService = {}

function AuraService:GetAuraState(player: Player, message: string?)
	return {
		ownedAuras = DataService:GetOwnedAuras(player),
		equippedAuraId = DataService:GetEquippedAuraId(player),
		message = message,
	}
end

function AuraService:IsAuraUnlocked(player: Player, auraId: string): boolean
	return DataService:GetOwnedAuraByAuraId(player, auraId) ~= nil
end

function AuraService:GrantAuraUnlock(player: Player, auraId: string): (boolean, string, boolean)
	local auraConfig = AuraConfig.Get(auraId)
	if not auraConfig then
		return false, "That aura does not exist.", false
	end

	if not acquireGrantLock(player, auraConfig.id, 10) then
		local existingDuringWait = DataService:GetOwnedAuraByAuraId(player, auraConfig.id)
		if existingDuringWait then
			return true, string.format('"%s" is already unlocked.', auraConfig.label), false
		end
		return false, "That aura unlock is still processing.", false
	end

	local existingRecord = DataService:GetOwnedAuraByAuraId(player, auraConfig.id)
	if existingRecord then
		releaseGrantLock(player, auraConfig.id)
		return true, string.format('"%s" is already unlocked.', auraConfig.label), false
	end

	local ownedRecord, grantError = DataService:AddOwnedAura(player, {
		auraId = auraConfig.id,
	})
	if not ownedRecord then
		releaseGrantLock(player, auraConfig.id)
		return false, grantError or "Failed to unlock the aura.", false
	end

	releaseGrantLock(player, auraConfig.id)

	Notify.Send(player, string.format('Unlocked aura "%s".', auraConfig.label), {
		channel = "auras",
		duration = 5,
		tone = "good",
	})

	return true, string.format('Unlocked "%s".', auraConfig.label), true
end

function AuraService:GrantSetIndexCompletionAuras(player: Player, setId: string): boolean
	local auraConfig = AuraConfig.GetBySetId(setId)
	if not auraConfig then
		return false
	end

	local _, _, didGrant = self:GrantAuraUnlock(player, auraConfig.id)
	return didGrant
end

function AuraService:EquipOwnedAura(player: Player, action: string, ownedId: string?): (boolean, string)
	if not waitForPlayerData(player, 10) then
		return false, "Player data is not ready yet."
	end

	if action == "unequip" then
		local currentlyEquippedAuraId = DataService:GetEquippedAuraId(player)
		if currentlyEquippedAuraId == nil or currentlyEquippedAuraId == "" then
			return true, "Aura is already unequipped."
		end

		local canApplyUnequip, unequipApplyError = BodyPartService:CanApplyCurrentVisualState(player, "")
		if not canApplyUnequip then
			return false, unequipApplyError or "Could not validate the aura unequip."
		end

		local currentAuraConfig = AuraConfig.Get(currentlyEquippedAuraId)
		local ok, message = DataService:SetEquippedAuraId(player, nil)
		if not ok then
			return false, message or "Could not unequip aura."
		end

		local cleanupOk, cleanupMessage = BodyPartService:EnsureAuraRuntimeCleared(player, "explicit_aura_unequip")
		if not cleanupOk and cleanupMessage then
			warn(string.format("[AuraService] Failed to verify aura cleanup for %s: %s", player.Name, cleanupMessage))
		end

		if currentAuraConfig then
			return true, string.format('Unequipped "%s".', currentAuraConfig.label)
		end

		return true, "Unequipped aura."
	end

	if action ~= "equip" then
		return false, "Aura action must be either equip or unequip."
	end

	if ownedId == nil or ownedId == "" then
		return false, "ownedId is required to equip an aura."
	end

	local ownedRecord = DataService:GetOwnedAuras(player)[ownedId]
	if not ownedRecord then
		return false, "You do not own that aura."
	end

	local auraConfig = AuraConfig.Get(ownedRecord.auraId)
	if not auraConfig then
		return false, "That aura no longer exists."
	end

	local currentlyEquippedAuraId = DataService:GetEquippedAuraId(player)
	if currentlyEquippedAuraId == auraConfig.id then
		return true, string.format('"%s" is already equipped.', auraConfig.label)
	end

	local canApply, applyError = BodyPartService:CanApplyCurrentVisualState(player, auraConfig.id)
	if not canApply then
		return false, applyError or "Could not validate the equipped aura."
	end

	local ok, message = DataService:SetEquippedAuraId(player, auraConfig.id)
	return ok, if ok then string.format('Equipped "%s".', auraConfig.label) else (message or "Could not equip aura.")
end

function AuraService:ToggleFavoriteOwnedAura(player: Player, ownedId: string, requestedFavoriteState: boolean?): (boolean, string)
	if typeof(ownedId) ~= "string" or ownedId == "" then
		return false, "ownedId is required."
	end

	local ownedRecord = DataService:GetOwnedAuras(player)[ownedId]
	if not ownedRecord then
		return false, "You do not own that aura."
	end

	local nextFavoriteState = if typeof(requestedFavoriteState) == "boolean"
		then requestedFavoriteState
		else not (ownedRecord.isFavorite == true)
	local updatedRecord, updateError = DataService:SetOwnedAuraFavorite(player, ownedId, nextFavoriteState)
	if not updatedRecord then
		return false, updateError or "Failed to update favorite state."
	end

	local auraConfig = AuraConfig.Get(updatedRecord.auraId)
	local auraLabel = if auraConfig then auraConfig.label else "aura"
	local message = if updatedRecord.isFavorite
		then string.format('Favorited "%s".', auraLabel)
		else string.format('Unfavorited "%s".', auraLabel)

	return true, message
end

function AuraService:GetTotalInExistenceForAura(auraId: string): (number?, string?)
	return DataService:GetTotalInExistenceForAura(auraId)
end

function AuraService:_sanitizeEquippedAura(player: Player)
	if not waitForPlayerData(player, 20) then
		return
	end

	local equippedAuraId = DataService:GetEquippedAuraId(player)
	if not equippedAuraId then
		return
	end

	if not self:IsAuraUnlocked(player, equippedAuraId) then
		DataService:SetEquippedAuraId(player, nil)
	end
end

function AuraService:_grantSetCompletionAurasFromBodyPartsState(player: Player, bodyPartsState: any)
	for setId in pairs(getUnlockableCompletedSetIds(bodyPartsState)) do
		self:GrantSetIndexCompletionAuras(player, setId)
	end
end

function AuraService:_seedPlayerUnlocks(player: Player)
	if not waitForPlayerData(player, 20) then
		return
	end

	self:_grantSetCompletionAurasFromBodyPartsState(player, DataService:GetBodyPartsState(player))
	self:_sanitizeEquippedAura(player)
end

local function handleGetAuraState(player: Player)
	return response(true, "Loaded aura state.", AuraService:GetAuraState(player))
end

local function handleEquipOwnedAura(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Equip payload must be a table.", AuraService:GetAuraState(player))
	end

	local ok, message = AuraService:EquipOwnedAura(player, payload.action, payload.ownedId)
	return response(ok, message, AuraService:GetAuraState(player))
end

local function handleToggleFavoriteOwnedAura(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Favorite payload must be a table.", AuraService:GetAuraState(player))
	end

	local ok, message = AuraService:ToggleFavoriteOwnedAura(player, payload.ownedId, payload.isFavorite)
	return response(ok, message, AuraService:GetAuraState(player))
end

local function handleGetTotalInExistenceForAura(_player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return {
			ok = false,
			message = "Aura existence payload must be a table.",
		}
	end

	local auraId = payload.auraId
	if typeof(auraId) ~= "string" or auraId == "" then
		return {
			ok = false,
			message = "auraId is required.",
		}
	end

	local count, message = AuraService:GetTotalInExistenceForAura(auraId)
	if count == nil then
		return {
			ok = false,
			message = message or "Failed to load aura existence count.",
		}
	end

	return {
		ok = true,
		count = count,
	}
end

function AuraService:OnStart()
	getStateRemote = ensureRemoteFunction(getStateRemote, GET_STATE_REMOTE_NAME)
	equipRemote = ensureRemoteFunction(equipRemote, EQUIP_REMOTE_NAME)
	toggleFavoriteRemote = ensureRemoteFunction(toggleFavoriteRemote, TOGGLE_FAVORITE_REMOTE_NAME)
	getExistenceRemote = ensureRemoteFunction(getExistenceRemote, GET_EXISTENCE_REMOTE_NAME)

	getStateRemote.OnServerInvoke = function(player: Player)
		local allowed = RequestLimiter:Allow(player, "remote.aura.get_state")
		if not allowed then
			return response(false, "You're refreshing your aura state too quickly.", AuraService:GetAuraState(player))
		end

		return handleGetAuraState(player)
	end
	equipRemote.OnServerInvoke = function(player: Player, payload: any)
		local allowed = RequestLimiter:Allow(player, "remote.aura.equip")
		if not allowed then
			return response(false, "You're equipping auras too quickly.", AuraService:GetAuraState(player))
		end

		return handleEquipOwnedAura(player, payload)
	end
	toggleFavoriteRemote.OnServerInvoke = function(player: Player, payload: any)
		local allowed = RequestLimiter:Allow(player, "remote.aura.favorite")
		if not allowed then
			return response(false, "You're changing aura favorites too quickly.", AuraService:GetAuraState(player))
		end

		return handleToggleFavoriteOwnedAura(player, payload)
	end
	getExistenceRemote.OnServerInvoke = function(player: Player, payload: any)
		local allowed = RequestLimiter:Allow(player, "remote.aura.existence")
		if not allowed then
			return {
				ok = false,
				message = "You're checking aura counts too quickly.",
			}
		end

		return handleGetTotalInExistenceForAura(player, payload)
	end

	DataService.PlayerDataLoaded:Connect(function(player: Player)
		self:_seedPlayerUnlocks(player)
	end)

	DataService.OwnedBodyPartAdded:Connect(function(player: Player, _record: any, bodyPartsState: any)
		self:_grantSetCompletionAurasFromBodyPartsState(player, bodyPartsState)
	end)
end

function AuraService:OnPlayerAdded(_player: Player)
end

function AuraService:OnPlayerRemoving(player: Player)
	activeGrantLocks[player] = nil
end

return AuraService
