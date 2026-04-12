local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BodyPartLoadout = require(ReplicatedStorage.Shared.Character.BodyPartLoadout)
local BodyPartCollection = require(ReplicatedStorage.Shared.Character.BodyPartCollection)
local BodyPartRegions = require(ReplicatedStorage.Shared.Character.BodyPartRegions)
local BodyPartVisuals = require(ReplicatedStorage.Shared.Character.BodyPartVisuals)
local BodyPartRuntimeConfig = require(ReplicatedStorage.Shared.Config.BodyParts.Runtime)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local DataService = require(script.Parent.DataService)
local SessionStore = require(script.SessionStore)

local REMOTES_FOLDER_NAME = "Remotes"
local BODY_PARTS_FOLDER_NAME = "BodyParts"
local GET_STATE_REMOTE_NAME = "GetSessionLoadout"
local EQUIP_REMOTE_NAME = "EquipOwnedBodyPart"
local UNEQUIP_REMOTE_NAME = "UnequipRegion"
local CLEAR_REMOTE_NAME = "ClearLoadout"
local UPDATED_REMOTE_NAME = "LoadoutUpdated"

local REQUIRED_R15_PARTS = {
	"Head",
	"UpperTorso",
	"LowerTorso",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
}

local remotesFolder: Folder? = nil
local bodyPartsRemotesFolder: Folder? = nil
local getStateRemote: RemoteFunction? = nil
local equipRemote: RemoteFunction? = nil
local unequipRemote: RemoteFunction? = nil
local clearRemote: RemoteFunction? = nil
local updatedRemote: RemoteEvent? = nil
local characterAddedConnections: { [Player]: RBXScriptConnection } = {}

local BodyPartService = {}

export type EquipOptions = {
	applyVisuals: boolean?,
}

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

local function ensureBodyPartsRemotesFolder(): Folder
	local rootFolder = ensureRemotesFolder()
	if bodyPartsRemotesFolder and bodyPartsRemotesFolder.Parent == rootFolder then
		return bodyPartsRemotesFolder
	end

	local existing = rootFolder:FindFirstChild(BODY_PARTS_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		bodyPartsRemotesFolder = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = BODY_PARTS_FOLDER_NAME
	folder.Parent = rootFolder
	bodyPartsRemotesFolder = folder
	return folder
end

local function ensureRemoteFunction(cachedRemote: RemoteFunction?, remoteName: string): RemoteFunction
	local folder = ensureBodyPartsRemotesFolder()
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
	local folder = ensureBodyPartsRemotesFolder()
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

local function getCharacter(player: Player): Model?
	local character = player.Character
	if character and character:IsA("Model") and character.Parent then
		return character
	end
	return nil
end

local function waitForCharacterReady(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if not (humanoid and humanoid:IsA("Humanoid") and humanoid.RigType == Enum.HumanoidRigType.R15) then
		return false
	end

	for _, partName in ipairs(REQUIRED_R15_PARTS) do
		local bodyPart = character:FindFirstChild(partName) or character:WaitForChild(partName, 5)
		if not bodyPart then
			return false
		end
	end

	return true
end

local function getBaseRig(): Model?
	return BodyPartsCatalog.GetDefaultBaseRig()
end

local function buildVisualApplyRequest(equippedState: BodyPartLoadout.EquippedState): (BodyPartVisuals.ApplyRequest?, string?)
	local baseRig = getBaseRig()
	if not baseRig then
		return nil, "ReplicatedStorage.GameAssets.BodyParts.BaseRigs.DefaultR15 is missing."
	end

	local regions = {}

	for _, region in ipairs(BodyPartRegions.Order) do
		local entry = equippedState[region]
		if entry then
			local bundleModel = BodyPartsCatalog.ResolveBundleModel(entry.pieceId)
			if not bundleModel then
				return nil, string.format("Missing bundle model for piece '%s'.", entry.pieceId)
			end

			regions[region] = {
				bundle = bundleModel,
				scale = entry.scale,
				aura = nil,
			}
		end
	end

	return {
		baseRig = baseRig,
		regions = regions,
	}, nil
end

local function buildEquippedPieceIdsByRegion(equippedState: BodyPartLoadout.EquippedState): { [string]: string }
	local pieceIdsByRegion = {}

	for _, region in ipairs(BodyPartRegions.Order) do
		local entry = equippedState[region]
		if entry then
			pieceIdsByRegion[region] = entry.pieceId
		end
	end

	return pieceIdsByRegion
end

function BodyPartService:GetComputedLoadoutBonuses(player: Player)
	local equippedState = SessionStore.GetEquipped(player)
	local ownedBodyParts = DataService:GetOwnedBodyParts(player)
	local bonuses = {
		passiveIncomePerSecond = 0,
		luckBonus = 0,
		rollSpeedBonus = 0,
		activeSetId = nil,
	}

	for _, region in ipairs(BodyPartRegions.Order) do
		local entry = equippedState[region]
		if entry then
			local piece = BodyPartsCatalog.GetPiece(entry.pieceId)
			if piece then
				local ownedRecord = ownedBodyParts[entry.ownedId]
				bonuses.passiveIncomePerSecond += tonumber(ownedRecord and ownedRecord.finalPassiveIncomePerSecond) or piece.passiveIncomePerSecond
				bonuses.luckBonus += piece.luckBonus
				bonuses.rollSpeedBonus += piece.rollSpeedBonus
			end
		end
	end

	local pieceIdsByRegion = buildEquippedPieceIdsByRegion(equippedState)
	local setBonus = BodyPartsCatalog.GetFullSetBonus(pieceIdsByRegion)
	if setBonus then
		bonuses.passiveIncomePerSecond += setBonus.passiveIncomePerSecond
		bonuses.luckBonus += setBonus.luckBonus
		bonuses.rollSpeedBonus += setBonus.rollSpeedBonus

		local samplePieceId = pieceIdsByRegion[BodyPartRegions.Order[1]]
		local setConfig = samplePieceId and BodyPartsCatalog.GetSetForPiece(samplePieceId) or nil
		bonuses.activeSetId = if setConfig then setConfig.id else nil
	end

	return bonuses
end

function BodyPartService:GetSessionLoadout(player: Player): BodyPartLoadout.EquippedState
	return SessionStore.GetEquipped(player)
end

function BodyPartService:OwnsFullSet(player: Player, setId: string): boolean
	if typeof(setId) ~= "string" or setId == "" then
		return false
	end

	return BodyPartCollection.OwnsFullSet(DataService:GetBodyPartsState(player), setId)
end

function BodyPartService:GetClientState(player: Player, message: string?)
	return {
		equipped = SessionStore.GetEquipped(player),
		ownedBodyParts = DataService:GetOwnedBodyParts(player),
		bonuses = self:GetComputedLoadoutBonuses(player),
		message = message,
	}
end

function BodyPartService:NotifyClient(player: Player, message: string?)
	ensureUpdatedRemote():FireClient(player, self:GetClientState(player, message))
end

function BodyPartService:ApplySessionLoadout(player: Player): (boolean, string?)
	local character = getCharacter(player)
	if not character then
		return true, nil
	end

	local equippedState = SessionStore.GetEquipped(player)
	if not BodyPartLoadout.HasAnyEquipped(equippedState) then
		local resetResult = BodyPartVisuals.Reset(character, getBaseRig())
		if not resetResult.success then
			return false, table.concat(resetResult.errors, " | ")
		end
		return true, nil
	end

	local request, requestError = buildVisualApplyRequest(equippedState)
	if not request then
		return false, requestError or "Failed to build body part apply request."
	end

	local applyResult = BodyPartVisuals.Apply(character, request)
	if not applyResult.success then
		return false, table.concat(applyResult.errors, " | ")
	end

	return true, nil
end

local function rollbackVisualState(player: Player, previousState: BodyPartLoadout.EquippedState)
	SessionStore.Restore(player, previousState)

	local character = getCharacter(player)
	if not character then
		return
	end

	if BodyPartLoadout.HasAnyEquipped(previousState) then
		local request = buildVisualApplyRequest(previousState)
		if request then
			BodyPartVisuals.Apply(character, request)
		end
	else
		BodyPartVisuals.Reset(character, getBaseRig())
	end
end

local function restoreSessionState(player: Player, previousState: BodyPartLoadout.EquippedState)
	SessionStore.Restore(player, previousState)
end

function BodyPartService:EquipOwnedBodyPart(player: Player, ownedId: string, requestedScale: number?, options: EquipOptions?): (boolean, string)
	if typeof(ownedId) ~= "string" or ownedId == "" then
		return false, "ownedId is required."
	end

	local ownedBodyParts = DataService:GetOwnedBodyParts(player)
	local ownedRecord = ownedBodyParts[ownedId]
	if not ownedRecord then
		return false, "You do not own that body part."
	end

	local piece = BodyPartsCatalog.GetPiece(ownedRecord.pieceId)
	if not piece then
		return false, string.format("Unknown piece '%s'.", tostring(ownedRecord.pieceId))
	end

	local scale = BodyPartRuntimeConfig.ClampScale(piece.id, requestedScale)
	local previousState = SessionStore.GetEquipped(player)
	local shouldApplyVisuals = if typeof(options) == "table" then options.applyVisuals ~= false else true

	SessionStore.SetEquipped(player, {
		ownedId = ownedId,
		pieceId = piece.id,
		region = piece.region,
		scale = scale,
	})

	if shouldApplyVisuals then
		local success, applyMessage = self:ApplySessionLoadout(player)
		if not success then
			rollbackVisualState(player, previousState)
			return false, applyMessage or "Failed to apply the body part."
		end
	else
		local bonuses = self:GetComputedLoadoutBonuses(player)
		if bonuses == nil then
			restoreSessionState(player, previousState)
			return false, "Failed to compute the equipped body part bonuses."
		end
	end

	self:NotifyClient(player, string.format("Equipped %s at %.2fx.", piece.displayName, scale))
	return true, string.format("Equipped %s.", piece.displayName)
end

function BodyPartService:UnequipRegion(player: Player, region: string): (boolean, string)
	if typeof(region) ~= "string" or not BodyPartRegions.IsValid(region) then
		return false, "A valid region is required."
	end

	local previousState = SessionStore.GetEquipped(player)
	if previousState[region] == nil then
		self:NotifyClient(player, string.format("%s is already empty.", region))
		return true, string.format("%s is already empty.", region)
	end

	SessionStore.ClearRegion(player, region)

	local success, applyMessage = self:ApplySessionLoadout(player)
	if not success then
		rollbackVisualState(player, previousState)
		return false, applyMessage or "Failed to remove the equipped body part."
	end

	self:NotifyClient(player, string.format("Unequipped %s.", region))
	return true, string.format("Unequipped %s.", region)
end

function BodyPartService:ClearLoadout(player: Player): (boolean, string)
	local previousState = SessionStore.GetEquipped(player)
	if not BodyPartLoadout.HasAnyEquipped(previousState) then
		self:NotifyClient(player, "Loadout is already empty.")
		return true, "Loadout is already empty."
	end

	SessionStore.ClearAll(player)

	local success, applyMessage = self:ApplySessionLoadout(player)
	if not success then
		rollbackVisualState(player, previousState)
		return false, applyMessage or "Failed to clear the loadout."
	end

	self:NotifyClient(player, "Cleared the equipped body part loadout.")
	return true, "Cleared the equipped body part loadout."
end

local function handleGetState(player: Player)
	return response(true, "Loaded body part state.", BodyPartService:GetClientState(player))
end

local function handleEquip(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Equip payload must be a table.", BodyPartService:GetClientState(player))
	end

	local ok, message = BodyPartService:EquipOwnedBodyPart(player, payload.ownedId, payload.scale, {
		applyVisuals = payload.applyVisuals,
	})
	return response(ok, message, BodyPartService:GetClientState(player))
end

local function handleUnequip(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Unequip payload must be a table.", BodyPartService:GetClientState(player))
	end

	local ok, message = BodyPartService:UnequipRegion(player, payload.region)
	return response(ok, message, BodyPartService:GetClientState(player))
end

local function handleClear(player: Player)
	local ok, message = BodyPartService:ClearLoadout(player)
	return response(ok, message, BodyPartService:GetClientState(player))
end

function BodyPartService:OnStart()
	getStateRemote = ensureRemoteFunction(getStateRemote, GET_STATE_REMOTE_NAME)
	equipRemote = ensureRemoteFunction(equipRemote, EQUIP_REMOTE_NAME)
	unequipRemote = ensureRemoteFunction(unequipRemote, UNEQUIP_REMOTE_NAME)
	clearRemote = ensureRemoteFunction(clearRemote, CLEAR_REMOTE_NAME)
	updatedRemote = ensureUpdatedRemote()

	getStateRemote.OnServerInvoke = function(player: Player)
		return handleGetState(player)
	end
	equipRemote.OnServerInvoke = function(player: Player, payload: any)
		return handleEquip(player, payload)
	end
	unequipRemote.OnServerInvoke = function(player: Player, payload: any)
		return handleUnequip(player, payload)
	end
	clearRemote.OnServerInvoke = function(player: Player)
		return handleClear(player)
	end
end

function BodyPartService:OnPlayerAdded(player: Player)
	SessionStore.LoadPlayer(player)

	if characterAddedConnections[player] then
		characterAddedConnections[player]:Disconnect()
	end

	characterAddedConnections[player] = player.CharacterAdded:Connect(function(character)
		task.defer(function()
			if not waitForCharacterReady(character) then
				self:NotifyClient(player, "Character did not finish loading the required R15 body parts.")
				return
			end

			local success, applyMessage = self:ApplySessionLoadout(player)
			if not success and applyMessage then
				self:NotifyClient(player, applyMessage)
				warn(string.format("[BodyPartService] %s", applyMessage))
				return
			end

			self:NotifyClient(player, "Body part runtime is ready on the live rig.")
		end)
	end)

	if player.Character then
		task.defer(function()
			local character = player.Character
			if character and waitForCharacterReady(character) then
				local success, applyMessage = self:ApplySessionLoadout(player)
				if not success and applyMessage then
					self:NotifyClient(player, applyMessage)
				end
			end
		end)
	end
end

function BodyPartService:OnPlayerRemoving(player: Player)
	if characterAddedConnections[player] then
		characterAddedConnections[player]:Disconnect()
		characterAddedConnections[player] = nil
	end

	local character = getCharacter(player)
	if character then
		BodyPartVisuals.Reset(character, getBaseRig())
	end

	SessionStore.CleanupPlayer(player)
end

return BodyPartService
