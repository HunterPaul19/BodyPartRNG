local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Common.Signal)
local BodyPartLoadout = require(ReplicatedStorage.Shared.Character.BodyPartLoadout)
local BodyPartCollection = require(ReplicatedStorage.Shared.Character.BodyPartCollection)
local OwnedBodyParts = require(ReplicatedStorage.Shared.Character.OwnedBodyParts)
local BodyPartRegions = require(ReplicatedStorage.Shared.Character.BodyPartRegions)
local BodyPartVisuals = require(ReplicatedStorage.Shared.Character.BodyPartVisuals)
local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local BodyPartRuntimeConfig = require(ReplicatedStorage.Shared.Config.BodyParts.Runtime)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local PerfStats = require(ReplicatedStorage.Shared.Diagnostics.PerfStats)
local DataService = require(script.Parent.DataService)
local StatsService = require(script.Parent.StatsService)
local SessionStore = require(script.SessionStore)

local REMOTES_FOLDER_NAME = "Remotes"
local BODY_PARTS_FOLDER_NAME = "BodyParts"
local GET_STATE_REMOTE_NAME = "GetSessionLoadout"
local GET_EXISTENCE_REMOTE_NAME = "GetTotalInExistenceForPiece"
local GET_PLAYER_INSPECT_SUMMARY_REMOTE_NAME = "GetPlayerInspectSummary"
local EQUIP_REMOTE_NAME = "EquipOwnedBodyPart"
local UNEQUIP_REMOTE_NAME = "UnequipRegion"
local SET_AUTO_SIZE_ENABLED_REMOTE_NAME = "SetAutoSizeEnabled"
local CLEAR_REMOTE_NAME = "ClearLoadout"
local TOGGLE_FAVORITE_REMOTE_NAME = "ToggleFavoriteOwnedBodyPart"
local SELL_OWNED_REMOTE_NAME = "SellOwnedBodyPart"
local SELL_ALL_REMOTE_NAME = "SellAllUnfavoritedBodyParts"
local UPDATED_REMOTE_NAME = "LoadoutUpdated"
local BUILD_LOCK_ATTRIBUTE = "BodyPartBuildLocked"
local APPLIED_FOLDER_NAME = "CharacterBodyParts"
local AURA_RUNTIME_ATTRIBUTE = "BodyPartAuraManaged"
local AURA_REAPPLY_DEBOUNCE_SECONDS = 0.15

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
local getExistenceRemote: RemoteFunction? = nil
local getPlayerInspectSummaryRemote: RemoteFunction? = nil
local equipRemote: RemoteFunction? = nil
local unequipRemote: RemoteFunction? = nil
local setAutoSizeEnabledRemote: RemoteFunction? = nil
local clearRemote: RemoteFunction? = nil
local toggleFavoriteRemote: RemoteFunction? = nil
local sellOwnedRemote: RemoteFunction? = nil
local sellAllRemote: RemoteFunction? = nil
local updatedRemote: RemoteEvent? = nil
local characterAddedConnections: { [Player]: RBXScriptConnection } = {}
local characterRuntimeWatcherStates: {
	[Player]: {
		character: Model,
		characterConnections: { RBXScriptConnection },
		runtimeConnections: { RBXScriptConnection },
		runtimeFolder: Instance?,
		runtimeMutationSuppressionDepth: number,
		auraReapplyInFlight: boolean,
		auraReapplyScheduled: boolean,
		auraReapplyDirty: boolean,
		auraReapplyReason: string?,
	},
} = {}

local BodyPartService = {}
BodyPartService.LoadoutChanged = Signal.new()
local getCharacter
local waitForCharacterReady

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

local function markDeltaState(state: { [string]: any })
	state._isDelta = true
	return state
end

local function notifyLoadoutChanged(player: Player)
	BodyPartService.LoadoutChanged:Fire(player)
end

local function setCharacterBuildLock(character: Model?, isLocked: boolean)
	if character and character.Parent then
		character:SetAttribute(BUILD_LOCK_ATTRIBUTE, isLocked)
	end
end

local function disconnectConnections(connections: { RBXScriptConnection }?)
	if not connections then
		return
	end

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	table.clear(connections)
end

local function getCharacterRuntimeWatcherState(player: Player)
	return characterRuntimeWatcherStates[player]
end

local function clearCharacterRuntimeWatcherState(player: Player)
	local state = characterRuntimeWatcherStates[player]
	if not state then
		return
	end

	disconnectConnections(state.runtimeConnections)
	disconnectConnections(state.characterConnections)
	characterRuntimeWatcherStates[player] = nil
end

local function isAuraManagedRuntimeInstance(instance: Instance?): boolean
	local current = instance
	while current do
		if current:GetAttribute(AURA_RUNTIME_ATTRIBUTE) == true then
			return true
		end
		current = current.Parent
	end

	return false
end

local function getRuntimeFolder(character: Model): Instance?
	return character:FindFirstChild(APPLIED_FOLDER_NAME)
end

local function isBodyPartRuntimeMutation(character: Model, instance: Instance?): boolean
	if not instance then
		return false
	end

	local runtimeFolder = getRuntimeFolder(character)
	if runtimeFolder == nil then
		return instance.Name == APPLIED_FOLDER_NAME
	end

	return instance == runtimeFolder or instance:IsDescendantOf(runtimeFolder)
end

local function beginRuntimeMutationSuppression(player: Player, character: Model)
	local state = getCharacterRuntimeWatcherState(player)
	if state == nil or state.character ~= character then
		return
	end

	state.runtimeMutationSuppressionDepth += 1
end

local function endRuntimeMutationSuppression(player: Player, character: Model)
	local state = getCharacterRuntimeWatcherState(player)
	if state == nil or state.character ~= character then
		return
	end

	state.runtimeMutationSuppressionDepth = math.max(0, state.runtimeMutationSuppressionDepth - 1)
end

local function shouldProcessRuntimeMutation(player: Player, character: Model, instance: Instance?): boolean
	local state = getCharacterRuntimeWatcherState(player)
	if state == nil or state.character ~= character then
		return false
	end

	if state.runtimeMutationSuppressionDepth > 0 then
		return false
	end

	if isAuraManagedRuntimeInstance(instance) then
		return false
	end

	return isBodyPartRuntimeMutation(character, instance)
end

local function shouldRefreshAuraRuntime(player: Player, character: Model?): boolean
	local equippedAuraId = DataService:GetEquippedAuraId(player)
	if typeof(equippedAuraId) == "string" and equippedAuraId ~= "" then
		return true
	end

	return character ~= nil and BodyPartVisuals.HasAuraRuntimeInstances(character)
end

local function requestAuraReapply(player: Player, reason: string)
	local state = getCharacterRuntimeWatcherState(player)
	if state == nil then
		local character = getCharacter(player)
		if character == nil or not shouldRefreshAuraRuntime(player, character) then
			return
		end

		task.defer(function()
			if player.Character ~= character or not waitForCharacterReady(character) then
				return
			end

			if not shouldRefreshAuraRuntime(player, character) then
				return
			end

			local success, applyMessage = BodyPartService:ApplySessionLoadout(player)
			if not success and applyMessage then
				BodyPartService:NotifyClient(player, applyMessage)
				warn(string.format("[BodyPartService] Failed to reapply aura after %s for %s: %s", reason, player.Name, applyMessage))
				return
			end

			notifyLoadoutChanged(player)
		end)
		return
	end

	local character = getCharacter(player)
	if character == nil or character ~= state.character then
		return
	end

	if not shouldRefreshAuraRuntime(player, character) then
		return
	end

	if not waitForCharacterReady(character) then
		return
	end

	if state.auraReapplyInFlight then
		state.auraReapplyDirty = true
		state.auraReapplyReason = reason
		return
	end

	if state.auraReapplyScheduled then
		state.auraReapplyDirty = true
		state.auraReapplyReason = reason
		return
	end

	state.auraReapplyScheduled = true
	state.auraReapplyReason = reason
	task.delay(AURA_REAPPLY_DEBOUNCE_SECONDS, function()
		local activeState = getCharacterRuntimeWatcherState(player)
		if activeState == nil or activeState ~= state then
			return
		end

		activeState.auraReapplyScheduled = false

		local activeCharacter = getCharacter(player)
		if activeCharacter == nil or activeCharacter ~= activeState.character then
			activeState.auraReapplyDirty = false
			activeState.auraReapplyInFlight = false
			activeState.auraReapplyReason = nil
			return
		end

		if not waitForCharacterReady(activeCharacter) then
			activeState.auraReapplyDirty = false
			activeState.auraReapplyInFlight = false
			activeState.auraReapplyReason = nil
			return
		end

		if not shouldRefreshAuraRuntime(player, activeCharacter) then
			activeState.auraReapplyDirty = false
			activeState.auraReapplyInFlight = false
			activeState.auraReapplyReason = nil
			return
		end

		activeState.auraReapplyInFlight = true
		activeState.auraReapplyDirty = false
		local applyReason = activeState.auraReapplyReason or reason

		local success, applyMessage = BodyPartService:ApplySessionLoadout(player)
		if not success and applyMessage then
			BodyPartService:NotifyClient(player, applyMessage)
			warn(string.format("[BodyPartService] Failed to reapply aura after %s for %s: %s", applyReason, player.Name, applyMessage))
		else
			notifyLoadoutChanged(player)
		end

		activeState.auraReapplyInFlight = false
		activeState.auraReapplyReason = nil

		if activeState.auraReapplyDirty == true then
			activeState.auraReapplyDirty = false
			requestAuraReapply(player, applyReason)
		end
	end)
end

local function attachRuntimeFolderWatcher(player: Player, character: Model, runtimeFolder: Instance?)
	local state = getCharacterRuntimeWatcherState(player)
	if state == nil or state.character ~= character then
		return
	end

	if state.runtimeFolder == runtimeFolder then
		return
	end

	disconnectConnections(state.runtimeConnections)
	state.runtimeFolder = runtimeFolder

	if runtimeFolder == nil then
		return
	end

	table.insert(state.runtimeConnections, runtimeFolder.DescendantAdded:Connect(function(descendant)
		if shouldProcessRuntimeMutation(player, character, descendant) then
			requestAuraReapply(player, "body_part_runtime_descendant_added")
		end
	end))
	table.insert(state.runtimeConnections, runtimeFolder.DescendantRemoving:Connect(function(descendant)
		if shouldProcessRuntimeMutation(player, character, descendant) then
			requestAuraReapply(player, "body_part_runtime_descendant_removed")
		end
	end))
end

local function attachCharacterRuntimeWatcher(player: Player, character: Model)
	clearCharacterRuntimeWatcherState(player)

	local state = {
		character = character,
		characterConnections = {},
		runtimeConnections = {},
		runtimeFolder = nil,
		runtimeMutationSuppressionDepth = 0,
		auraReapplyInFlight = false,
		auraReapplyScheduled = false,
		auraReapplyDirty = false,
		auraReapplyReason = nil,
	}
	characterRuntimeWatcherStates[player] = state

	table.insert(state.characterConnections, character.ChildAdded:Connect(function(child)
		if child.Name ~= APPLIED_FOLDER_NAME then
			return
		end

		attachRuntimeFolderWatcher(player, character, child)
		if shouldProcessRuntimeMutation(player, character, child) then
			requestAuraReapply(player, "body_part_runtime_container_added")
		end
	end))
	table.insert(state.characterConnections, character.ChildRemoved:Connect(function(child)
		if child.Name ~= APPLIED_FOLDER_NAME then
			return
		end

		attachRuntimeFolderWatcher(player, character, nil)
		if shouldProcessRuntimeMutation(player, character, child) then
			requestAuraReapply(player, "body_part_runtime_container_removed")
		end
	end))
	table.insert(state.characterConnections, character.Destroying:Connect(function()
		clearCharacterRuntimeWatcherState(player)
	end))

	attachRuntimeFolderWatcher(player, character, getRuntimeFolder(character))
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

getCharacter = function(player: Player): Model?
	local character = player.Character
	if character and character:IsA("Model") and character.Parent then
		return character
	end
	return nil
end

waitForCharacterReady = function(character: Model): boolean
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

local function buildAuraApplyRequest(equippedAuraId: string?): (BodyPartVisuals.ApplyAuraRequest?, string?)
	if equippedAuraId == nil or equippedAuraId == "" then
		return nil, nil
	end

	local auraConfig = AuraConfig.Get(equippedAuraId)
	if not auraConfig then
		return nil, string.format("Missing aura config for '%s'.", tostring(equippedAuraId))
	end

	local auraModel = AuraConfig.ResolveModel(auraConfig)
	if not auraModel then
		return nil, string.format("Missing aura model for '%s'.", auraConfig.label)
	end

	return {
		id = auraConfig.id,
		model = auraModel,
	}, nil
end

local function buildMutationApplyRequest(
	ownedRecord: OwnedBodyParts.OwnedBodyPartRecord?
): (BodyPartVisuals.ApplyMutationRequest?, string?)
	if typeof(ownedRecord) ~= "table" then
		return nil, nil
	end

	local mutationValue = ownedRecord.mutationId
	if typeof(mutationValue) ~= "string" or mutationValue == "" then
		mutationValue = ownedRecord.mutation
	end

	local mutationId = MutationConfig.NormalizeId(mutationValue)
	if mutationId == MutationConfig.GetDefault().id then
		return nil, nil
	end

	local mutationModel = MutationConfig.ResolveModel(mutationId)
	if mutationModel == nil then
		return nil, string.format(
			'Missing mutation VFX model "ReplicatedStorage.GameAssets.MutationVFX.%s" for mutation "%s".',
			MutationConfig.GetDisplayName(mutationId),
			mutationId
		)
	end

	return {
		id = mutationId,
		model = mutationModel,
	}, nil
end

local function buildVisualApplyRequest(
	equippedState: BodyPartLoadout.EquippedState,
	equippedAuraId: string?,
	forceDefaultScale: boolean?,
	ownedBodyPartsById: { [string]: OwnedBodyParts.OwnedBodyPartRecord }?
): (BodyPartVisuals.ApplyRequest?, string?)
	local baseRig = getBaseRig()
	if not baseRig then
		return nil, "ReplicatedStorage.GameAssets.BodyParts.BaseRigs.DefaultR15 is missing."
	end

	local regions = {}
	local auraRequest, auraError = buildAuraApplyRequest(equippedAuraId)
	if auraError then
		return nil, auraError
	end

	for _, region in ipairs(BodyPartRegions.Order) do
		local entry = equippedState[region]
		if entry then
			local bundleModel = BodyPartsCatalog.ResolveBundleModel(entry.pieceId)
			if not bundleModel then
				return nil, string.format("Missing bundle model for piece '%s'.", entry.pieceId)
			end

			local ownedRecord = if ownedBodyPartsById then ownedBodyPartsById[entry.ownedId] else nil
			local mutationRequest, mutationError = buildMutationApplyRequest(ownedRecord)
			if mutationError then
				return nil, string.format("%s mutation error: %s", region, mutationError)
			end

			regions[region] = {
				bundle = bundleModel,
				scale = if forceDefaultScale == true then 1 else entry.scale,
				attachRules = BodyPartsCatalog.ResolveAttachRules(entry.pieceId),
				mutation = mutationRequest,
			}
		end
	end

	return {
		baseRig = baseRig,
		regions = regions,
		aura = auraRequest,
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

local function findEquippedEntryForOwnedId(
	equippedState: BodyPartLoadout.EquippedState,
	ownedId: string
): (string?, BodyPartLoadout.LoadoutEntry?)
	for _, region in ipairs(BodyPartRegions.Order) do
		local entry = equippedState[region]
		if entry and entry.ownedId == ownedId then
			return region, entry
		end
	end

	return nil, nil
end

local function getSellValueForRecord(record: OwnedBodyParts.OwnedBodyPartRecord): number
	local piece = BodyPartsCatalog.GetPiece(record.pieceId)
	local passiveIncomePerSecond = tonumber(record.finalPassiveIncomePerSecond)
		or tonumber(piece and piece.passiveIncomePerSecond)
		or 0
	return math.max(1, math.floor(passiveIncomePerSecond * 60))
end

local function serializeInspectEntry(entry: BodyPartLoadout.LoadoutEntry, ownedRecord: OwnedBodyParts.OwnedBodyPartRecord?)
	return {
		ownedId = entry.ownedId,
		pieceId = entry.pieceId,
		region = entry.region,
		scale = entry.scale,
		serialNumber = if ownedRecord then ownedRecord.serialNumber else nil,
		rolledSetDisplayName = if ownedRecord then ownedRecord.rolledSetDisplayName else nil,
		displayRarity = if ownedRecord then ownedRecord.displayRarity else nil,
		displayOddsDenominator = if ownedRecord then ownedRecord.displayOddsDenominator else nil,
		rarityDenominator = if ownedRecord then ownedRecord.rarityDenominator else nil,
		mutation = if ownedRecord then ownedRecord.mutation else nil,
		finalPassiveIncomePerSecond = if ownedRecord then ownedRecord.finalPassiveIncomePerSecond else nil,
	}
end

local function serializeInspectAuraEntry(
	ownedRecord: { ownedId: string, auraId: string, serialNumber: number?, isFavorite: boolean? },
	auraConfig: AuraConfig.AuraConfigEntry
)
	return {
		ownedId = ownedRecord.ownedId,
		auraId = auraConfig.id,
		serialNumber = ownedRecord.serialNumber,
		label = auraConfig.label,
		description = auraConfig.description,
		tierLabel = auraConfig.tierLabel,
		displayColor = auraConfig.displayColor,
		bonuses = {
			luckBonus = auraConfig.bonuses.luckBonus,
			rollSpeedBonus = auraConfig.bonuses.rollSpeedBonus,
			moneyMultiplier = auraConfig.bonuses.moneyMultiplier,
			passiveIncomePerSecondBonus = auraConfig.bonuses.passiveIncomePerSecondBonus,
		},
	}
end

local function countOwnedRecords(recordsById: { [string]: any }): number
	local total = 0
	for _ in pairs(recordsById) do
		total += 1
	end
	return total
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
		autoSizeEnabled = DataService:GetAutoSizeEnabled(player),
		message = message,
	}
end

function BodyPartService:GetClientDeltaState(player: Player, message: string?)
	return markDeltaState({
		equipped = SessionStore.GetEquipped(player),
		bonuses = self:GetComputedLoadoutBonuses(player),
		autoSizeEnabled = DataService:GetAutoSizeEnabled(player),
		message = message,
	})
end

function BodyPartService:GetPlayerInspectSummary(targetPlayer: Player)
	local equippedState = SessionStore.GetEquipped(targetPlayer)
	local ownedBodyParts = DataService:GetOwnedBodyParts(targetPlayer)
	local ownedAuras = DataService:GetOwnedAuras(targetPlayer)
	local equippedAuraId = DataService:GetEquippedAuraId(targetPlayer)
	local equipped = {}
	local equippedAura = nil

	for _, region in ipairs(BodyPartRegions.Order) do
		local entry = equippedState[region]
		if entry then
			equipped[region] = serializeInspectEntry(entry, ownedBodyParts[entry.ownedId])
		end
	end

	if equippedAuraId then
		local ownedAuraRecord = DataService:GetOwnedAuraByAuraId(targetPlayer, equippedAuraId)
		local auraConfig = AuraConfig.Get(equippedAuraId)
		if ownedAuraRecord and auraConfig then
			equippedAura = serializeInspectAuraEntry(ownedAuraRecord, auraConfig)
		end
	end

	return {
		userId = targetPlayer.UserId,
		name = targetPlayer.Name,
		displayName = targetPlayer.DisplayName,
		currentMoney = DataService:GetMoney(targetPlayer),
		currentTimePlayed = DataService:GetTimePlayed(targetPlayer),
		currentSuccessfulRollCount = DataService:GetSuccessfulRollCount(targetPlayer),
		currentOwnedBodyParts = countOwnedRecords(ownedBodyParts),
		currentOwnedAuras = countOwnedRecords(ownedAuras),
		stats = StatsService:GetStats(targetPlayer),
		equipped = equipped,
		equippedAura = equippedAura,
		bonuses = self:GetComputedLoadoutBonuses(targetPlayer),
	}
end

function BodyPartService:NotifyClient(player: Player, message: string?)
	local startedAt = PerfStats.Begin()
	local payload = self:GetClientDeltaState(player, message)
	ensureUpdatedRemote():FireClient(player, payload)
	PerfStats.Measure("LoadoutUpdated", startedAt, {
		payload = payload,
		detail = player.Name,
	})
end

function BodyPartService:BuildCurrentVisualApplyRequest(player: Player, equippedAuraIdOverride: string?): (BodyPartVisuals.ApplyRequest?, string?)
	local equippedState = SessionStore.GetEquipped(player)
	local auraId = equippedAuraIdOverride
	if auraId == nil then
		auraId = DataService:GetEquippedAuraId(player)
	end

	return buildVisualApplyRequest(
		equippedState,
		auraId,
		DataService:GetAutoSizeEnabled(player),
		DataService:GetOwnedBodyParts(player)
	)
end

function BodyPartService:CanApplyCurrentVisualState(player: Player, equippedAuraIdOverride: string?): (boolean, string?)
	local character = getCharacter(player)
	if not character then
		return true, nil
	end
	if not waitForCharacterReady(character) then
		return true, nil
	end

	local request, requestError = self:BuildCurrentVisualApplyRequest(player, equippedAuraIdOverride)
	if not request then
		return false, requestError or "Failed to build the current visual request."
	end

	for _, region in ipairs(BodyPartRegions.Order) do
		local regionRequest = request.regions and request.regions[region] or nil
		local mutationRequest = regionRequest and regionRequest.mutation or nil
		if mutationRequest ~= nil then
			local canApplyMutation, mutationError = BodyPartVisuals.CanApplyMutation(character, region, mutationRequest)
			if not canApplyMutation then
				return false, mutationError
			end
		end
	end

	local auraRequest = request.aura
	if auraRequest == nil then
		return true, nil
	end

	return BodyPartVisuals.CanApplyAura(character, auraRequest)
end

function BodyPartService:ApplySessionLoadout(player: Player): (boolean, string?)
	local startedAt = PerfStats.Begin()
	local character = getCharacter(player)
	if not character then
		PerfStats.Measure("BodyPartVisualsApply", startedAt, {
			detail = string.format("%s:no_character", player.Name),
		})
		return true, nil
	end

	beginRuntimeMutationSuppression(player, character)
	setCharacterBuildLock(character, true)

	local callSucceeded, applySuccessOrTrace, applyMessage = xpcall(function()
		local equippedState = SessionStore.GetEquipped(player)
		local equippedAuraId = DataService:GetEquippedAuraId(player)

		if not BodyPartLoadout.HasAnyEquipped(equippedState) and equippedAuraId == nil then
			local resetResult = BodyPartVisuals.Reset(character, getBaseRig())
			if not resetResult.success then
				return false, table.concat(resetResult.errors, " | ")
			end
		else
			local request, requestError = buildVisualApplyRequest(
				equippedState,
				equippedAuraId,
				DataService:GetAutoSizeEnabled(player),
				DataService:GetOwnedBodyParts(player)
			)
			if not request then
				return false, requestError or "Failed to build body part apply request."
			end

			local applyResult = BodyPartVisuals.Apply(character, request)
			if not applyResult.success then
				return false, table.concat(applyResult.errors, " | ")
			end
		end

		return true, nil
	end, debug.traceback)

	local success = applySuccessOrTrace
	local message = applyMessage

	if not callSucceeded then
		success = false
		message = tostring(applySuccessOrTrace)
	end

	if success == nil then
		success = false
	end

	if success == false and message == nil then
		message = "Failed to apply the current body part loadout."
	end

	setCharacterBuildLock(character, false)
	endRuntimeMutationSuppression(player, character)
	PerfStats.Measure("BodyPartVisualsApply", startedAt, {
		detail = string.format("%s:%s", player.Name, if success then "ok" else "failed"),
	})
	return success, message
end

function BodyPartService:EnsureAuraRuntimeCleared(player: Player, reason: string?): (boolean, string?)
	local character = getCharacter(player)
	if not character or not waitForCharacterReady(character) then
		return true, nil
	end

	if not BodyPartVisuals.HasAuraRuntimeInstances(character) then
		return true, nil
	end

	local success, applyMessage = self:ApplySessionLoadout(player)
	if not success then
		return false, applyMessage or "Failed to clear aura runtime."
	end

	if BodyPartVisuals.HasAuraRuntimeInstances(character) then
		local message = string.format("Aura runtime remained after %s.", tostring(reason or "cleanup"))
		warn(string.format("[BodyPartService] %s", message))
		return false, message
	end

	return true, nil
end

local function rollbackVisualState(player: Player, previousState: BodyPartLoadout.EquippedState)
	SessionStore.Restore(player, previousState)

	local character = getCharacter(player)
	if not character then
		return
	end

	setCharacterBuildLock(character, true)

	local rollbackSucceeded, rollbackError = xpcall(function()
		local equippedAuraId = DataService:GetEquippedAuraId(player)
		if BodyPartLoadout.HasAnyEquipped(previousState) or equippedAuraId ~= nil then
			local request = buildVisualApplyRequest(
				previousState,
				equippedAuraId,
				DataService:GetAutoSizeEnabled(player),
				DataService:GetOwnedBodyParts(player)
			)
			if request then
				BodyPartVisuals.Apply(character, request)
			end
		else
			BodyPartVisuals.Reset(character, getBaseRig())
		end
	end, debug.traceback)

	setCharacterBuildLock(character, false)

	if not rollbackSucceeded then
		warn(string.format("[BodyPartService] Failed to rollback visual state for %s: %s", player.Name, tostring(rollbackError)))
	end
end

local function restoreSessionState(player: Player, previousState: BodyPartLoadout.EquippedState)
	SessionStore.Restore(player, previousState)
end

local function rollbackMutationState(player: Player, previousState: BodyPartLoadout.EquippedState, applyVisuals: boolean)
	if applyVisuals then
		rollbackVisualState(player, previousState)
	else
		restoreSessionState(player, previousState)
	end
end

local function persistSessionLoadout(player: Player, previousState: BodyPartLoadout.EquippedState, applyVisuals: boolean): (boolean, string?)
	local ok, message = DataService:SetEquippedLoadout(player, SessionStore.GetEquipped(player))
	if ok then
		return true, nil
	end

	rollbackMutationState(player, previousState, applyVisuals)
	return false, message or "Failed to save the equipped body part loadout."
end

local function getSanitizedPersistedLoadout(player: Player): (BodyPartLoadout.EquippedState, boolean, string?)
	local persistedState = DataService:GetEquippedLoadout(player)
	local sanitizedState = BodyPartLoadout.NormalizeEquippedState(persistedState, DataService:GetOwnedBodyParts(player))
	local didChange = not BodyPartLoadout.AreEquippedStatesEqual(persistedState, sanitizedState)
	if not didChange then
		return sanitizedState, false, nil
	end

	local ok, message = DataService:SetEquippedLoadout(player, sanitizedState)
	return sanitizedState, ok, message
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

	local persisted, persistMessage = persistSessionLoadout(player, previousState, shouldApplyVisuals)
	if not persisted then
		return false, persistMessage or "Failed to save the equipped body part loadout."
	end

	StatsService:RecordLoadoutAction(player, "equip")
	self:NotifyClient(player, string.format("Equipped %s at %.2fx.", piece.displayName, scale))
	notifyLoadoutChanged(player)
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

	local persisted, persistMessage = persistSessionLoadout(player, previousState, true)
	if not persisted then
		return false, persistMessage or "Failed to save the equipped body part loadout."
	end

	StatsService:RecordLoadoutAction(player, "unequip")
	self:NotifyClient(player, string.format("Unequipped %s.", region))
	notifyLoadoutChanged(player)
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

	local persisted, persistMessage = persistSessionLoadout(player, previousState, true)
	if not persisted then
		return false, persistMessage or "Failed to save the equipped body part loadout."
	end

	StatsService:RecordLoadoutAction(player, "clear")
	self:NotifyClient(player, "Cleared the equipped body part loadout.")
	notifyLoadoutChanged(player)
	return true, "Cleared the equipped body part loadout."
end

function BodyPartService:ToggleFavoriteOwnedBodyPart(player: Player, ownedId: string, requestedFavoriteState: boolean?): (boolean, string)
	if typeof(ownedId) ~= "string" or ownedId == "" then
		return false, "ownedId is required."
	end

	local ownedRecord = DataService:GetOwnedBodyParts(player)[ownedId]
	if not ownedRecord then
		return false, "You do not own that body part."
	end

	local nextFavoriteState = if typeof(requestedFavoriteState) == "boolean"
		then requestedFavoriteState
		else not (ownedRecord.isFavorite == true)
	local updatedRecord, updateError = DataService:SetOwnedBodyPartFavorite(player, ownedId, nextFavoriteState)
	if not updatedRecord then
		return false, updateError or "Failed to update favorite state."
	end

	local piece = BodyPartsCatalog.GetPiece(updatedRecord.pieceId)
	local pieceName = if piece then piece.displayName else "body part"
	local message = if updatedRecord.isFavorite
		then string.format("Favorited %s.", pieceName)
		else string.format("Unfavorited %s.", pieceName)

	self:NotifyClient(player, message)
	return true, message
end

function BodyPartService:SellOwnedBodyPart(player: Player, ownedId: string): (boolean, string)
	if typeof(ownedId) ~= "string" or ownedId == "" then
		return false, "ownedId is required."
	end

	local ownedRecord = DataService:GetOwnedBodyParts(player)[ownedId]
	if not ownedRecord then
		return false, "You do not own that body part."
	end

	local piece = BodyPartsCatalog.GetPiece(ownedRecord.pieceId)
	local pieceName = if piece then piece.displayName else "body part"
	local previousLoadoutState = SessionStore.GetEquipped(player)
	local equippedRegion = findEquippedEntryForOwnedId(previousLoadoutState, ownedId)
	if equippedRegion then
		SessionStore.ClearRegion(player, equippedRegion)

		local success, applyMessage = self:ApplySessionLoadout(player)
		if not success then
			rollbackVisualState(player, previousLoadoutState)
			return false, applyMessage or "Failed to unequip the sold body part."
		end

		local persisted, persistMessage = persistSessionLoadout(player, previousLoadoutState, true)
		if not persisted then
			return false, persistMessage or "Failed to save the equipped body part loadout."
		end
	end

	local removedRecord, removeError = DataService:RemoveOwnedBodyPart(player, ownedId)
	if not removedRecord then
		return false, removeError or "Failed to remove the sold body part."
	end

	local payout = getSellValueForRecord(removedRecord)
	DataService:AddMoney(player, payout, "sell_single")
	StatsService:RecordBodyPartsSold(player, 1)

	local message = string.format("Sold %s for $%s.", pieceName, tostring(payout))
	self:NotifyClient(player, message)
	if equippedRegion then
		notifyLoadoutChanged(player)
	end
	return true, message
end

function BodyPartService:SellAllUnfavoritedBodyParts(player: Player): (boolean, string)
	local startedAt = PerfStats.Begin()
	local ownedBodyParts = DataService:GetOwnedBodyParts(player)
	local equippedState = SessionStore.GetEquipped(player)
	local equippedOwnedIds = {}

	for _, region in ipairs(BodyPartRegions.Order) do
		local entry = equippedState[region]
		if entry and typeof(entry.ownedId) == "string" and entry.ownedId ~= "" then
			equippedOwnedIds[entry.ownedId] = true
		end
	end

	local ownedIdsToSell = {}
	for ownedId, record in pairs(ownedBodyParts) do
		if record.isFavorite ~= true and equippedOwnedIds[ownedId] ~= true then
			table.insert(ownedIdsToSell, ownedId)
		end
	end

	if #ownedIdsToSell == 0 then
		local message = "No unfavorited unequipped body parts were available to sell."
		self:NotifyClient(player, message)
		PerfStats.Measure("BodyPartSellAll", startedAt, {
			detail = string.format("%s sold=0 requested=0", player.Name),
		})
		return true, message
	end

	local removedRecords, removeError = DataService:RemoveOwnedBodyParts(player, ownedIdsToSell)
	if not removedRecords then
		PerfStats.Measure("BodyPartSellAll", startedAt, {
			detail = string.format("%s sold=0 requested=%d", player.Name, #ownedIdsToSell),
		})
		return false, removeError or "Failed to sell the selected body parts."
	end

	local soldCount = #removedRecords
	local totalPayout = 0
	for _, removedRecord in ipairs(removedRecords) do
		totalPayout += getSellValueForRecord(removedRecord)
	end

	if soldCount <= 0 then
		PerfStats.Measure("BodyPartSellAll", startedAt, {
			detail = string.format("%s sold=0 requested=%d", player.Name, #ownedIdsToSell),
		})
		return false, "Failed to sell the selected body parts."
	end

	DataService:AddMoney(player, totalPayout, "sell_bulk")
	StatsService:RecordBodyPartsSold(player, soldCount)

	local message = string.format("Sold %d body parts for $%s.", soldCount, tostring(totalPayout))
	self:NotifyClient(player, message)
	PerfStats.Measure("BodyPartSellAll", startedAt, {
		detail = string.format("%s sold=%d requested=%d", player.Name, soldCount, #ownedIdsToSell),
	})
	return true, message
end

local function handleGetState(player: Player)
	return response(true, "Loaded body part state.", BodyPartService:GetClientState(player))
end

local function handleGetTotalInExistence(_player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return {
			ok = false,
			message = "Existence payload must be a table.",
		}
	end

	local pieceId = payload.pieceId
	if typeof(pieceId) ~= "string" or pieceId == "" then
		return {
			ok = false,
			message = "pieceId is required.",
		}
	end

	local count, message = DataService:GetTotalInExistenceForPiece(pieceId)
	if count == nil then
		return {
			ok = false,
			message = message or "Failed to load body part existence count.",
		}
	end

	return {
		ok = true,
		count = count,
	}
end

local function handleGetPlayerInspectSummary(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return {
			ok = false,
			message = "Inspect payload must be a table.",
		}
	end

	local targetUserId = math.floor(tonumber(payload.userId) or 0)
	if targetUserId <= 0 then
		return {
			ok = false,
			message = "A valid target userId is required.",
		}
	end

	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if not targetPlayer then
		return {
			ok = false,
			message = "That player is no longer in this server.",
		}
	end

	return {
		ok = true,
		summary = BodyPartService:GetPlayerInspectSummary(targetPlayer),
	}
end

local function handleEquip(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Equip payload must be a table.", BodyPartService:GetClientState(player))
	end

	local ok, message = BodyPartService:EquipOwnedBodyPart(player, payload.ownedId, payload.scale, {
		applyVisuals = payload.applyVisuals,
	})
	return response(ok, message, BodyPartService:GetClientDeltaState(player, message))
end

local function handleUnequip(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Unequip payload must be a table.", BodyPartService:GetClientState(player))
	end

	local ok, message = BodyPartService:UnequipRegion(player, payload.region)
	return response(ok, message, BodyPartService:GetClientDeltaState(player, message))
end

local function handleClear(player: Player)
	local ok, message = BodyPartService:ClearLoadout(player)
	return response(ok, message, BodyPartService:GetClientDeltaState(player, message))
end

local function handleSetAutoSizeEnabled(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Auto size payload must be a table.", BodyPartService:GetClientState(player))
	end

	local ok, message = DataService:SetAutoSizeEnabled(player, payload.enabled == true)
	if not ok then
		return response(false, message or "Failed to update auto size.", BodyPartService:GetClientState(player))
	end

	local success, applyMessage = BodyPartService:ApplySessionLoadout(player)
	if not success then
		return response(false, applyMessage or "Failed to apply auto size.", BodyPartService:GetClientState(player))
	end

	notifyLoadoutChanged(player)
	return response(true, message or "Auto size updated.", BodyPartService:GetClientDeltaState(player, message))
end

local function handleToggleFavorite(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Favorite payload must be a table.", BodyPartService:GetClientState(player))
	end

	local ok, message = BodyPartService:ToggleFavoriteOwnedBodyPart(player, payload.ownedId, payload.isFavorite)
	return response(ok, message, BodyPartService:GetClientDeltaState(player, message))
end

local function handleSellOwned(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Sell payload must be a table.", BodyPartService:GetClientState(player))
	end

	local ok, message = BodyPartService:SellOwnedBodyPart(player, payload.ownedId)
	return response(ok, message, BodyPartService:GetClientDeltaState(player, message))
end

local function handleSellAll(player: Player)
	local ok, message = BodyPartService:SellAllUnfavoritedBodyParts(player)
	return response(ok, message, BodyPartService:GetClientDeltaState(player, message))
end

function BodyPartService:OnStart()
	getStateRemote = ensureRemoteFunction(getStateRemote, GET_STATE_REMOTE_NAME)
	getExistenceRemote = ensureRemoteFunction(getExistenceRemote, GET_EXISTENCE_REMOTE_NAME)
	getPlayerInspectSummaryRemote = ensureRemoteFunction(getPlayerInspectSummaryRemote, GET_PLAYER_INSPECT_SUMMARY_REMOTE_NAME)
	equipRemote = ensureRemoteFunction(equipRemote, EQUIP_REMOTE_NAME)
	unequipRemote = ensureRemoteFunction(unequipRemote, UNEQUIP_REMOTE_NAME)
	setAutoSizeEnabledRemote = ensureRemoteFunction(setAutoSizeEnabledRemote, SET_AUTO_SIZE_ENABLED_REMOTE_NAME)
	clearRemote = ensureRemoteFunction(clearRemote, CLEAR_REMOTE_NAME)
	toggleFavoriteRemote = ensureRemoteFunction(toggleFavoriteRemote, TOGGLE_FAVORITE_REMOTE_NAME)
	sellOwnedRemote = ensureRemoteFunction(sellOwnedRemote, SELL_OWNED_REMOTE_NAME)
	sellAllRemote = ensureRemoteFunction(sellAllRemote, SELL_ALL_REMOTE_NAME)
	updatedRemote = ensureUpdatedRemote()

	getStateRemote.OnServerInvoke = function(player: Player)
		return handleGetState(player)
	end
	getExistenceRemote.OnServerInvoke = function(player: Player, payload: any)
		return handleGetTotalInExistence(player, payload)
	end
	getPlayerInspectSummaryRemote.OnServerInvoke = function(player: Player, payload: any)
		return handleGetPlayerInspectSummary(player, payload)
	end
	equipRemote.OnServerInvoke = function(player: Player, payload: any)
		return handleEquip(player, payload)
	end
	unequipRemote.OnServerInvoke = function(player: Player, payload: any)
		return handleUnequip(player, payload)
	end
	setAutoSizeEnabledRemote.OnServerInvoke = function(player: Player, payload: any)
		return handleSetAutoSizeEnabled(player, payload)
	end
	clearRemote.OnServerInvoke = function(player: Player)
		return handleClear(player)
	end
	toggleFavoriteRemote.OnServerInvoke = function(player: Player, payload: any)
		return handleToggleFavorite(player, payload)
	end
	sellOwnedRemote.OnServerInvoke = function(player: Player, payload: any)
		return handleSellOwned(player, payload)
	end
	sellAllRemote.OnServerInvoke = function(player: Player)
		return handleSellAll(player)
	end

	DataService.EquippedAuraChanged:Connect(function(player: Player)
		requestAuraReapply(player, "equipped_aura_changed")
	end)
end

function BodyPartService:OnPlayerAdded(player: Player)
	local restoredState, savedCleanedState, savedCleanedStateMessage = getSanitizedPersistedLoadout(player)
	SessionStore.LoadPlayer(player, restoredState)
	if savedCleanedState == false and savedCleanedStateMessage then
		warn(string.format("[BodyPartService] Failed to clean persisted loadout for %s: %s", player.Name, savedCleanedStateMessage))
	end

	if characterAddedConnections[player] then
		characterAddedConnections[player]:Disconnect()
	end

	characterAddedConnections[player] = player.CharacterAdded:Connect(function(character)
		clearCharacterRuntimeWatcherState(player)
		task.defer(function()
			if not waitForCharacterReady(character) then
				self:NotifyClient(player, "Character did not finish loading the required R15 body parts.")
				return
			end

			attachCharacterRuntimeWatcher(player, character)
			local success, applyMessage = self:ApplySessionLoadout(player)
			if not success and applyMessage then
				self:NotifyClient(player, applyMessage)
				warn(string.format("[BodyPartService] %s", applyMessage))
				return
			end

			self:NotifyClient(player, "Body part runtime is ready on the live rig.")
			notifyLoadoutChanged(player)
		end)
	end)

	if player.Character then
		task.defer(function()
			local character = player.Character
			if character and waitForCharacterReady(character) then
				attachCharacterRuntimeWatcher(player, character)
				local success, applyMessage = self:ApplySessionLoadout(player)
				if not success and applyMessage then
					self:NotifyClient(player, applyMessage)
				else
					notifyLoadoutChanged(player)
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

	clearCharacterRuntimeWatcherState(player)

	local character = getCharacter(player)
	if character then
		BodyPartVisuals.Reset(character, getBaseRig())
	end

	SessionStore.CleanupPlayer(player)
end

return BodyPartService
