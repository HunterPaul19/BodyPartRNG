local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Common.Signal)
local BodyPartLoadout = require(ReplicatedStorage.Shared.Character.BodyPartLoadout)
local BodyPartCollection = require(ReplicatedStorage.Shared.Character.BodyPartCollection)
local BodyPartEconomy = require(ReplicatedStorage.Shared.Character.BodyPartEconomy)
local OwnedBodyParts = require(ReplicatedStorage.Shared.Character.OwnedBodyParts)
local BodyPartRegions = require(ReplicatedStorage.Shared.Character.BodyPartRegions)
local BodyPartVisuals = require(ReplicatedStorage.Shared.Character.BodyPartVisuals)
local GearVisuals = require(ReplicatedStorage.Shared.Character.GearVisuals)
local HeadAccessoryVisuals = require(ReplicatedStorage.Shared.Character.HeadAccessoryVisuals)
local AccessoryConfig = require(ReplicatedStorage.Shared.Config.AccessoryConfig)
local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local BodyPartRuntimeConfig = require(ReplicatedStorage.Shared.Config.BodyParts.Runtime)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local CombatPower = require(ReplicatedStorage.Shared.Combat.CombatPower)
local PotionRuntimeBonuses = require(ReplicatedStorage.Shared.Character.PotionRuntimeBonuses)
local PerfStats = require(ReplicatedStorage.Shared.Diagnostics.PerfStats)
local DataService = require(script.Parent.DataService)
local PotionService = require(script.Parent.PotionService)
local RequestLimiter = require(script.Parent.Common.RequestLimiter)
local StatsService = require(script.Parent.StatsService)
local TutorialService = require(script.Parent.TutorialService)
local SessionStore = require(script.SessionStore)

local REMOTES_FOLDER_NAME = "Remotes"
local BODY_PARTS_FOLDER_NAME = "BodyParts"
local GET_STATE_REMOTE_NAME = "GetSessionLoadout"
local GET_EXISTENCE_REMOTE_NAME = "GetTotalInExistenceForPiece"
local GET_EXISTENCES_REMOTE_NAME = "GetTotalInExistenceForPieces"
local GET_PLAYER_INSPECT_SUMMARY_REMOTE_NAME = "GetPlayerInspectSummary"
local EQUIP_REMOTE_NAME = "EquipOwnedBodyPart"
local EQUIP_BEST_REMOTE_NAME = "EquipBestLoadout"
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
local AURA_VISUAL_VERIFY_RETRY_SECONDS = 0.35
local AURA_VISUAL_VERIFY_RETRY_LIMIT = 5
local APPEARANCE_TRANSFER_MANAGED_ATTRIBUTE = "AppearanceTransferApplied"
local VISUAL_ONLY_HEAD_ACCESSORY_ATTRIBUTE = "VisualOnlyHeadAccessory"
local APPEARANCE_REFRESH_DEBOUNCE_SECONDS = 0.15
local CHARACTER_ACTIVATION_RETRY_SECONDS = 0.5
local CHARACTER_ACTIVATION_RETRY_LIMIT = 4
local CHARACTER_READY_TIMEOUT_SECONDS = 5
local CHARACTER_READY_POLL_INTERVAL_SECONDS = 0.1
local PLAYER_DATA_READY_TIMEOUT_SECONDS = 15

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
local getExistencesRemote: RemoteFunction? = nil
local getPlayerInspectSummaryRemote: RemoteFunction? = nil
local equipRemote: RemoteFunction? = nil
local equipBestRemote: RemoteFunction? = nil
local unequipRemote: RemoteFunction? = nil
local setAutoSizeEnabledRemote: RemoteFunction? = nil
local clearRemote: RemoteFunction? = nil
local toggleFavoriteRemote: RemoteFunction? = nil
local sellOwnedRemote: RemoteFunction? = nil
local sellAllRemote: RemoteFunction? = nil
local updatedRemote: RemoteEvent? = nil
local characterAddedConnections: { [Player]: RBXScriptConnection } = {}
local characterAppearanceLoadedConnections: { [Player]: RBXScriptConnection } = {}
local lastBodyPartScaleOverrideByPlayer: { [Player]: number? } = {}
local playerDataReadyByPlayer: { [Player]: boolean } = {}
local characterLifecycleStates: {
	[Player]: {
		currentCharacter: Model?,
		appearanceLoadedCharacter: Model?,
		activeRuntimeCharacter: Model?,
		pendingRuntimeApply: boolean,
		fallbackGeneration: number,
		activationRetryAttempt: number,
		auraVisualVerifyGeneration: number,
		lastActivationSource: string?,
	},
} = {}
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
		appearanceRefreshInFlight: boolean,
		appearanceRefreshScheduled: boolean,
		appearanceRefreshDirty: boolean,
		appearanceRefreshReason: string?,
	},
} = {}

local BodyPartService = {}
BodyPartService.LoadoutChanged = Signal.new()
local getCharacter
local waitForCharacterReady
local rollbackVisualState
local restoreSessionState
local rollbackMutationState
local persistSessionLoadout

export type EquipOptions = {
	applyVisuals: boolean?,
	persistLoadout: boolean?,
	recordStats: boolean?,
	notifyClient: boolean?,
	notifyLoadoutChanged: boolean?,
	autoSizeEnabled: boolean?,
}

local function response(ok: boolean, message: string, state: any?)
	return {
		ok = ok,
		message = message,
		state = state,
	}
end

local function buildRateLimitResponse(message: string, state: any?)
	return response(false, message, state)
end

local rebuildCurrentVisualStateNow: ((Player, string?, boolean?) -> (boolean, string?))
local refreshCurrentAuraNow: ((Player, string?) -> (boolean, string?))
local refreshCurrentAppearanceNow: ((Player, string?) -> (boolean, string?))
local computeLoadoutBonuses

local function markDeltaState(state: { [string]: any })
	state._isDelta = true
	return state
end

local function notifyLoadoutChanged(player: Player)
	BodyPartService.LoadoutChanged:Fire(player)
end

local function getCharacterLifecycleState(player: Player)
	local state = characterLifecycleStates[player]
	if state then
		return state
	end

	state = {
		currentCharacter = nil,
		appearanceLoadedCharacter = nil,
		activeRuntimeCharacter = nil,
		pendingRuntimeApply = false,
		fallbackGeneration = 0,
		activationRetryAttempt = 0,
		auraVisualVerifyGeneration = 0,
		lastActivationSource = nil,
	}
	characterLifecycleStates[player] = state
	return state
end

local function isPlayerDataReady(player: Player): boolean
	if playerDataReadyByPlayer[player] == true then
		return true
	end

	if DataService:IsPlayerDataLoaded(player) then
		playerDataReadyByPlayer[player] = true
		return true
	end

	return false
end

local function waitForPlayerDataReady(player: Player, timeoutSeconds: number?): boolean
	if isPlayerDataReady(player) then
		return true
	end

	local timeoutAt = os.clock() + (timeoutSeconds or PLAYER_DATA_READY_TIMEOUT_SECONDS)
	while os.clock() < timeoutAt do
		if player.Parent ~= Players then
			return false
		end

		if isPlayerDataReady(player) then
			return true
		end

		task.wait()
	end

	return isPlayerDataReady(player)
end

local function setCharacterBuildLock(character: Model?, isLocked: boolean)
	if character and character.Parent then
		character:SetAttribute(BUILD_LOCK_ATTRIBUTE, isLocked)
	end
end

local function ensureLiveHumanoidAutoRotateEnabled(character: Model?)
	if not (character and character:IsA("Model") and character.Parent) then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Parent then
		humanoid.AutoRotate = true
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

local function shouldRefreshCharacterAppearance(player: Player, character: Model?): boolean
	if character == nil or character:GetAttribute(BUILD_LOCK_ATTRIBUTE) == true then
		return false
	end

	if not BodyPartLoadout.HasAnyEquipped(SessionStore.GetEquipped(player)) then
		return false
	end

	return getRuntimeFolder(character) ~= nil
end

local function shouldProcessCharacterAccessoryMutation(player: Player, character: Model, instance: Instance?): boolean
	local state = getCharacterRuntimeWatcherState(player)
	if state == nil or state.character ~= character then
		return false
	end

	if character:GetAttribute(BUILD_LOCK_ATTRIBUTE) == true then
		return false
	end

	if not (instance and instance:IsA("Accessory")) then
		return false
	end

	if instance:GetAttribute(APPEARANCE_TRANSFER_MANAGED_ATTRIBUTE) == true then
		return false
	end

	if instance:GetAttribute(VISUAL_ONLY_HEAD_ACCESSORY_ATTRIBUTE) == true then
		return false
	end

	return shouldRefreshCharacterAppearance(player, character)
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

			local success, applyMessage = refreshCurrentAuraNow(player, reason)
			if not success and applyMessage then
				BodyPartService:NotifyClient(player, applyMessage)
				Logger.Warn(string.format("[BodyPartService] Failed to reapply aura after %s for %s: %s", reason, player.Name, applyMessage))
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

		local success, applyMessage = refreshCurrentAuraNow(player, applyReason)
		if not success and applyMessage then
			BodyPartService:NotifyClient(player, applyMessage)
			Logger.Warn(string.format("[BodyPartService] Failed to reapply aura after %s for %s: %s", applyReason, player.Name, applyMessage))
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

local function requestAppearanceRefresh(player: Player, reason: string)
	local state = getCharacterRuntimeWatcherState(player)
	if state == nil then
		return
	end

	local character = getCharacter(player)
	if character == nil or character ~= state.character then
		return
	end

	if not shouldRefreshCharacterAppearance(player, character) then
		return
	end

	if not waitForCharacterReady(character) then
		return
	end

	if state.appearanceRefreshInFlight then
		state.appearanceRefreshDirty = true
		state.appearanceRefreshReason = reason
		return
	end

	if state.appearanceRefreshScheduled then
		state.appearanceRefreshDirty = true
		state.appearanceRefreshReason = reason
		return
	end

	state.appearanceRefreshScheduled = true
	state.appearanceRefreshReason = reason
	task.delay(APPEARANCE_REFRESH_DEBOUNCE_SECONDS, function()
		local activeState = getCharacterRuntimeWatcherState(player)
		if activeState == nil or activeState ~= state then
			return
		end

		activeState.appearanceRefreshScheduled = false

		local activeCharacter = getCharacter(player)
		if activeCharacter == nil or activeCharacter ~= activeState.character then
			activeState.appearanceRefreshDirty = false
			activeState.appearanceRefreshInFlight = false
			activeState.appearanceRefreshReason = nil
			return
		end

		if not waitForCharacterReady(activeCharacter) or not shouldRefreshCharacterAppearance(player, activeCharacter) then
			activeState.appearanceRefreshDirty = false
			activeState.appearanceRefreshInFlight = false
			activeState.appearanceRefreshReason = nil
			return
		end

		activeState.appearanceRefreshInFlight = true
		activeState.appearanceRefreshDirty = false
		local refreshReason = activeState.appearanceRefreshReason or reason

		local success, refreshMessage = refreshCurrentAppearanceNow(player, refreshReason)
		if not success then
			Logger.Warn(string.format(
				"[BodyPartService] Failed to refresh appearance after %s for %s: %s",
				refreshReason,
				player.Name,
				tostring(refreshMessage)
			))
		end

		activeState.appearanceRefreshInFlight = false
		activeState.appearanceRefreshReason = nil

		if activeState.appearanceRefreshDirty == true then
			activeState.appearanceRefreshDirty = false
			requestAppearanceRefresh(player, refreshReason)
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
		appearanceRefreshInFlight = false,
		appearanceRefreshScheduled = false,
		appearanceRefreshDirty = false,
		appearanceRefreshReason = nil,
	}
	characterRuntimeWatcherStates[player] = state

	table.insert(state.characterConnections, character.ChildAdded:Connect(function(child)
		if child.Name ~= APPLIED_FOLDER_NAME then
			if shouldProcessCharacterAccessoryMutation(player, character, child) then
				requestAppearanceRefresh(player, "native_accessory_added")
			end
			return
		end

		attachRuntimeFolderWatcher(player, character, child)
		if shouldProcessRuntimeMutation(player, character, child) then
			requestAuraReapply(player, "body_part_runtime_container_added")
		end
	end))
	table.insert(state.characterConnections, character.ChildRemoved:Connect(function(child)
		if child.Name ~= APPLIED_FOLDER_NAME then
			if shouldProcessCharacterAccessoryMutation(player, character, child) then
				requestAppearanceRefresh(player, "native_accessory_removed")
			end
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

local function getCharacterRigNotReadyMessage(reason: string?, reasonKind: string?): string
	if reasonKind == "placeholder_character" then
		return "Body part runtime is waiting for the finalized avatar appearance to load."
	end

	if typeof(reason) == "string" and reason ~= "" then
		return string.format("Body part runtime is waiting for the character rig to finish assembling. %s", reason)
	end

	return "Body part runtime is waiting for the character rig to finish assembling."
end

local function validateCharacterReadyNow(character: Model): (boolean, string?, string?)
	if not (character and character:IsA("Model") and character.Parent) then
		return false, "Character is not available.", "missing_character"
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return false, "Character is missing a Humanoid.", "missing_humanoid"
	end

	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return false, "Character is not using an R15 rig.", "non_r15_rig"
	end

	local missingPartNames = {}
	for _, partName in ipairs(REQUIRED_R15_PARTS) do
		local bodyPart = character:FindFirstChild(partName)
		if not (bodyPart and bodyPart:IsA("BasePart")) then
			table.insert(missingPartNames, partName)
		end
	end

	if #missingPartNames > 0 then
		return false, string.format(
			"Character is missing required R15 body parts: %s.",
			table.concat(missingPartNames, ", ")
		), "missing_required_parts"
	end

	local canBuildReferencePose, referencePoseError, referencePoseErrorKind = BodyPartVisuals.ValidateReferencePose(character)
	if not canBuildReferencePose then
		return false, referencePoseError or "Character rig joints are not fully assembled yet.", referencePoseErrorKind
	end

	return true, nil, nil
end

waitForCharacterReady = function(character: Model, timeoutSeconds: number?): (boolean, string?, string?)
	local timeoutAt = os.clock() + math.max(0, tonumber(timeoutSeconds) or 0)
	local lastError = nil
	local lastErrorKind = nil

	while true do
		local isReady, readyError, readyErrorKind = validateCharacterReadyNow(character)
		if isReady then
			return true, nil, nil
		end

		lastError = readyError
		lastErrorKind = readyErrorKind
		if os.clock() >= timeoutAt then
			break
		end

		task.wait(CHARACTER_READY_POLL_INTERVAL_SECONDS)
	end

	return false, lastError, lastErrorKind
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
			'Missing mutation VFX model "ReplicatedStorage.GameAssets.Effects.Mutations.%s" for mutation "%s".',
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
	ownedBodyPartsById: { [string]: OwnedBodyParts.OwnedBodyPartRecord }?,
	bodyPartScaleOverride: number?
): (BodyPartVisuals.ApplyRequest?, string?)
	local baseRig = getBaseRig()
	if not baseRig then
		return nil, "ReplicatedStorage.GameAssets.Models.BodyParts.BaseRigs.DefaultR15 is missing."
	end

	local regions = {}
	local auraRequest, auraError = buildAuraApplyRequest(equippedAuraId)
	if auraError then
		return nil, auraError
	end
	local hasAnyEquippedRegions = BodyPartLoadout.HasAnyEquipped(equippedState)
	local visualScaleOverride = tonumber(bodyPartScaleOverride)
	local hasVisualScaleOverride = visualScaleOverride ~= nil and visualScaleOverride > 0

	for _, region in ipairs(BodyPartRegions.Order) do
		local entry = equippedState[region]
		if entry then
			local bundleModel = BodyPartsCatalog.ResolveBundleModel(entry.pieceId)
			if not bundleModel then
				return nil, string.format("Missing bundle model for piece '%s'.", entry.pieceId)
			end
			local setConfig = BodyPartsCatalog.GetSetForPiece(entry.pieceId)

			local ownedRecord = if ownedBodyPartsById then ownedBodyPartsById[entry.ownedId] else nil
			local mutationRequest, mutationError = buildMutationApplyRequest(ownedRecord)
			if mutationError then
				return nil, string.format("%s mutation error: %s", region, mutationError)
			end

			regions[region] = {
				bundle = bundleModel,
				scale = visualScaleOverride or entry.scale,
				attachRules = BodyPartsCatalog.ResolveAttachRules(entry.pieceId),
				mutation = mutationRequest,
				applyPlayerClothing = setConfig == nil or setConfig.applyPlayerClothing ~= false,
				applyPlayerBodyColors = setConfig == nil or setConfig.applyPlayerBodyColors ~= false,
			}
		elseif hasAnyEquippedRegions or hasVisualScaleOverride then
			regions[region] = {
				bundle = nil,
				scale = visualScaleOverride or 1,
				attachRules = nil,
				mutation = nil,
				isNativeFallback = true,
			}
		end
	end

	return {
		baseRig = baseRig,
		regions = regions,
		aura = auraRequest,
	}, nil
end

local function getBodyPartScaleOverride(player: Player, overrideAutoSizeEnabled: boolean?): number?
	local regularScaleEnabled = if overrideAutoSizeEnabled ~= nil
		then overrideAutoSizeEnabled == true
		else DataService:GetAutoSizeEnabled(player)
	if regularScaleEnabled then
		return nil
	end

	local bonuses = PotionService:GetRuntimeBonuses(player)
	if typeof(bonuses) ~= "table" then
		return nil
	end

	local bodyPartScaleOverride = tonumber((bonuses :: PotionRuntimeBonuses.RuntimeBonuses).bodyPartScaleOverride)
	if bodyPartScaleOverride == nil or bodyPartScaleOverride <= 0 then
		return nil
	end

	return bodyPartScaleOverride
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
	return BodyPartEconomy.GetSellValue(record, piece)
end

local function resolveAutoSizeEnabled(player: Player, overrideEnabled: boolean?): boolean
	if overrideEnabled ~= nil then
		return overrideEnabled == true
	end

	return DataService:GetAutoSizeEnabled(player)
end

local function resolveEffectiveScale(
	player: Player,
	pieceId: string,
	ownedRecord: OwnedBodyParts.OwnedBodyPartRecord,
	requestedScale: number?,
	overrideAutoSizeEnabled: boolean?
): number
	local regularScaleEnabled = resolveAutoSizeEnabled(player, overrideAutoSizeEnabled)
	local fallbackScale = tonumber(ownedRecord.sizeMultiplier) or 1
	local targetScale = if regularScaleEnabled then 1 else tonumber(requestedScale) or fallbackScale
	return BodyPartRuntimeConfig.ClampScale(pieceId, targetScale)
end

local function resolveEquippedStateScales(
	player: Player,
	equippedState: BodyPartLoadout.EquippedState,
	overrideAutoSizeEnabled: boolean?
): (BodyPartLoadout.EquippedState?, string?)
	local ownedBodyParts = DataService:GetOwnedBodyParts(player)
	local resolvedState = BodyPartLoadout.CreateEmptyEquippedState()

	for _, region in ipairs(BodyPartRegions.Order) do
		local entry = equippedState[region]
		if entry then
			local ownedRecord = ownedBodyParts[entry.ownedId]
			if not ownedRecord then
				return nil, string.format("You do not own the equipped body part '%s'.", tostring(entry.ownedId))
			end

			local piece = BodyPartsCatalog.GetPiece(ownedRecord.pieceId)
			if not piece then
				return nil, string.format("Unknown piece '%s'.", tostring(ownedRecord.pieceId))
			end

			resolvedState[region] = {
				ownedId = entry.ownedId,
				pieceId = piece.id,
				region = piece.region,
				scale = resolveEffectiveScale(player, piece.id, ownedRecord, entry.scale, overrideAutoSizeEnabled),
			}
		end
	end

	return resolvedState, nil
end

local function resolveCanonicalEquippedStateScales(
	player: Player,
	equippedState: BodyPartLoadout.EquippedState
): (BodyPartLoadout.EquippedState?, string?)
	local ownedBodyParts = DataService:GetOwnedBodyParts(player)
	local normalizedState = BodyPartLoadout.NormalizeEquippedState(equippedState, ownedBodyParts)
	local resolvedState = BodyPartLoadout.CreateEmptyEquippedState()

	for _, region in ipairs(BodyPartRegions.Order) do
		local entry = normalizedState[region]
		if entry then
			local ownedRecord = ownedBodyParts[entry.ownedId]
			if not ownedRecord then
				return nil, string.format("You do not own the equipped body part '%s'.", tostring(entry.ownedId))
			end

			local piece = BodyPartsCatalog.GetPiece(ownedRecord.pieceId)
			if not piece then
				return nil, string.format("Unknown piece '%s'.", tostring(ownedRecord.pieceId))
			end

			resolvedState[region] = {
				ownedId = entry.ownedId,
				pieceId = piece.id,
				region = piece.region,
				scale = BodyPartRuntimeConfig.ClampScale(piece.id, tonumber(ownedRecord.sizeMultiplier) or entry.scale),
			}
		end
	end

	return resolvedState, nil
end

local function buildOwnedBodyPartCandidate(ownedId: string, ownedRecord: OwnedBodyParts.OwnedBodyPartRecord)
	local piece = BodyPartsCatalog.GetPiece(ownedRecord.pieceId)
	if not piece then
		return nil
	end
	local combatStats = CombatPower.GetBodyPartContributionStats(piece, ownedRecord)

	return {
		ownedId = ownedId,
		pieceId = piece.id,
		region = piece.region,
		scale = BodyPartRuntimeConfig.ClampScale(piece.id, tonumber(ownedRecord.sizeMultiplier) or 1),
		passiveIncomePerSecond = tonumber(ownedRecord.finalPassiveIncomePerSecond) or piece.passiveIncomePerSecond,
		luckBonus = tonumber(piece.luckBonus) or 0,
		rollSpeedBonus = tonumber(piece.rollSpeedBonus) or 0,
		speedBonus = tonumber(combatStats.speed) or 0,
		damageBonus = tonumber(combatStats.damage) or 0,
		healthBonus = tonumber(combatStats.health) or 0,
	}
end

local function buildGrantPayloadBodyPartCandidate(grantPayload: any)
	if typeof(grantPayload) ~= "table" then
		return nil
	end

	local piece = BodyPartsCatalog.GetPiece(grantPayload.pieceId)
	if not piece then
		return nil
	end
	local combatStats = CombatPower.GetBodyPartContributionStats(piece, grantPayload)

	return {
		ownedId = "",
		pieceId = piece.id,
		region = piece.region,
		scale = BodyPartRuntimeConfig.ClampScale(piece.id, tonumber(grantPayload.sizeMultiplier) or 1),
		passiveIncomePerSecond = tonumber(grantPayload.finalPassiveIncomePerSecond) or piece.passiveIncomePerSecond,
		luckBonus = tonumber(piece.luckBonus) or 0,
		rollSpeedBonus = tonumber(piece.rollSpeedBonus) or 0,
		speedBonus = tonumber(combatStats.speed) or 0,
		damageBonus = tonumber(combatStats.damage) or 0,
		healthBonus = tonumber(combatStats.health) or 0,
	}
end

local function compareOwnedBodyPartCandidateStats(leftCandidate, rightCandidate): number
	if leftCandidate == rightCandidate then
		return 0
	end
	if leftCandidate == nil then
		return -1
	end
	if rightCandidate == nil then
		return 1
	end

	if leftCandidate.passiveIncomePerSecond ~= rightCandidate.passiveIncomePerSecond then
		return if leftCandidate.passiveIncomePerSecond > rightCandidate.passiveIncomePerSecond then 1 else -1
	end
	if leftCandidate.luckBonus ~= rightCandidate.luckBonus then
		return if leftCandidate.luckBonus > rightCandidate.luckBonus then 1 else -1
	end
	if leftCandidate.rollSpeedBonus ~= rightCandidate.rollSpeedBonus then
		return if leftCandidate.rollSpeedBonus > rightCandidate.rollSpeedBonus then 1 else -1
	end
	if leftCandidate.damageBonus ~= rightCandidate.damageBonus then
		return if leftCandidate.damageBonus > rightCandidate.damageBonus then 1 else -1
	end
	if leftCandidate.healthBonus ~= rightCandidate.healthBonus then
		return if leftCandidate.healthBonus > rightCandidate.healthBonus then 1 else -1
	end
	if leftCandidate.speedBonus ~= rightCandidate.speedBonus then
		return if leftCandidate.speedBonus > rightCandidate.speedBonus then 1 else -1
	end

	return 0
end

local function compareOwnedBodyPartCandidates(leftCandidate, rightCandidate, preferredOwnedId: string?): number
	if leftCandidate == rightCandidate then
		return 0
	end
	if leftCandidate == nil then
		return -1
	end
	if rightCandidate == nil then
		return 1
	end

	local statComparison = compareOwnedBodyPartCandidateStats(leftCandidate, rightCandidate)
	if statComparison ~= 0 then
		return statComparison
	end

	local prefersLeft = preferredOwnedId ~= nil and leftCandidate.ownedId == preferredOwnedId
	local prefersRight = preferredOwnedId ~= nil and rightCandidate.ownedId == preferredOwnedId
	if prefersLeft ~= prefersRight then
		return if prefersLeft then 1 else -1
	end

	if leftCandidate.ownedId ~= rightCandidate.ownedId then
		return if leftCandidate.ownedId < rightCandidate.ownedId then 1 else -1
	end

	return 0
end

local function isBodyPartCandidateBetterThanEquipped(player: Player, candidate): boolean
	if candidate == nil then
		return false
	end

	local equippedState = SessionStore.GetEquipped(player)
	local equippedEntry = equippedState[candidate.region]
	if equippedEntry == nil then
		return true
	end

	local equippedOwnedId = equippedEntry.ownedId
	if typeof(equippedOwnedId) ~= "string" or equippedOwnedId == "" then
		return true
	end

	local equippedRecord = DataService:GetOwnedBodyParts(player)[equippedOwnedId]
	if not equippedRecord then
		return true
	end

	local equippedCandidate = buildOwnedBodyPartCandidate(equippedOwnedId, equippedRecord)
	if equippedCandidate == nil or equippedCandidate.region ~= candidate.region then
		return true
	end

	return compareOwnedBodyPartCandidateStats(candidate, equippedCandidate) > 0
end

local function chooseBestOwnedBodyPartCandidate(candidates, preferredOwnedId: string?)
	local bestCandidate = nil

	for _, candidate in ipairs(candidates) do
		if compareOwnedBodyPartCandidates(candidate, bestCandidate, preferredOwnedId) > 0 then
			bestCandidate = candidate
		end
	end

	return bestCandidate
end

local function buildOwnedBodyPartCandidateIndexes(ownedBodyParts: { [string]: OwnedBodyParts.OwnedBodyPartRecord })
	local candidatesByRegion = {}
	local candidatesByPieceId = {}

	for ownedId, ownedRecord in pairs(ownedBodyParts) do
		local candidate = buildOwnedBodyPartCandidate(ownedId, ownedRecord)
		if candidate ~= nil then
			local regionCandidates = candidatesByRegion[candidate.region]
			if regionCandidates == nil then
				regionCandidates = {}
				candidatesByRegion[candidate.region] = regionCandidates
			end
			table.insert(regionCandidates, candidate)

			local pieceCandidates = candidatesByPieceId[candidate.pieceId]
			if pieceCandidates == nil then
				pieceCandidates = {}
				candidatesByPieceId[candidate.pieceId] = pieceCandidates
			end
			table.insert(pieceCandidates, candidate)
		end
	end

	return candidatesByRegion, candidatesByPieceId
end

local function buildLoadoutCandidate(selectedCandidatesByRegion, setBonus: BodyPartsCatalog.SetBonus?)
	local equippedState = BodyPartLoadout.CreateEmptyEquippedState()
	local totals = {
		passiveIncomePerSecond = 0,
		luckBonus = 0,
		rollSpeedBonus = 0,
		speedBonus = 0,
		damageBonus = 0,
		healthBonus = 0,
	}

	for _, region in ipairs(BodyPartRegions.Order) do
		local candidate = selectedCandidatesByRegion[region]
		if candidate ~= nil then
			equippedState[region] = {
				ownedId = candidate.ownedId,
				pieceId = candidate.pieceId,
				region = region,
				scale = candidate.scale,
			}
			totals.passiveIncomePerSecond += candidate.passiveIncomePerSecond
			totals.luckBonus += candidate.luckBonus
			totals.rollSpeedBonus += candidate.rollSpeedBonus
			totals.speedBonus += candidate.speedBonus
			totals.damageBonus += candidate.damageBonus
			totals.healthBonus += candidate.healthBonus
		end
	end

	if setBonus ~= nil then
		totals.passiveIncomePerSecond += tonumber(setBonus.passiveIncomePerSecond) or 0
		totals.luckBonus += tonumber(setBonus.luckBonus) or 0
		totals.rollSpeedBonus += tonumber(setBonus.rollSpeedBonus) or 0
		totals.speedBonus += tonumber(setBonus.speedBonus) or 0
		totals.damageBonus += tonumber(setBonus.damageBonus) or 0
		totals.healthBonus += tonumber(setBonus.healthBonus) or 0
	end

	return {
		equippedState = equippedState,
		passiveIncomePerSecond = totals.passiveIncomePerSecond,
		luckBonus = totals.luckBonus,
		rollSpeedBonus = totals.rollSpeedBonus,
		speedBonus = totals.speedBonus,
		damageBonus = totals.damageBonus,
		healthBonus = totals.healthBonus,
	}
end

local function buildBodyLoadoutCandidates(player: Player)
	local currentEquippedState = SessionStore.GetEquipped(player)
	local ownedBodyParts = DataService:GetOwnedBodyParts(player)
	local candidatesByRegion, candidatesByPieceId = buildOwnedBodyPartCandidateIndexes(ownedBodyParts)
	local loadoutCandidates = {}

	local independentCandidatesByRegion = {}
	for _, region in ipairs(BodyPartRegions.Order) do
		local currentEntry = currentEquippedState[region]
		local preferredOwnedId = if currentEntry ~= nil then currentEntry.ownedId else nil
		local regionCandidates = candidatesByRegion[region]
		if regionCandidates ~= nil then
			independentCandidatesByRegion[region] = chooseBestOwnedBodyPartCandidate(regionCandidates, preferredOwnedId)
		end
	end

	table.insert(loadoutCandidates, buildLoadoutCandidate(independentCandidatesByRegion, nil))

	for _, setConfig in ipairs(BodyPartsCatalog.GetAllSets()) do
		local setCandidatesByRegion = {}
		local canAssembleFullSet = true

		for _, region in ipairs(BodyPartRegions.Order) do
			local pieceId = setConfig.piecesByRegion[region]
			local pieceCandidates = pieceId and candidatesByPieceId[pieceId] or nil
			if pieceCandidates == nil then
				canAssembleFullSet = false
				break
			end

			local currentEntry = currentEquippedState[region]
			local preferredOwnedId = if currentEntry ~= nil and currentEntry.pieceId == pieceId then currentEntry.ownedId else nil
			local bestCandidate = chooseBestOwnedBodyPartCandidate(pieceCandidates, preferredOwnedId)
			if bestCandidate == nil then
				canAssembleFullSet = false
				break
			end

			setCandidatesByRegion[region] = bestCandidate
		end

		if canAssembleFullSet then
			local setLoadoutCandidate = buildLoadoutCandidate(setCandidatesByRegion, setConfig.fullSetBonus)
			table.insert(loadoutCandidates, setLoadoutCandidate)
		end
	end

	return loadoutCandidates
end

local function getOwnedAuraCandidates(ownedAuras: { [string]: any }, currentEquippedAuraId: string?)
	local auraCandidates = {}

	for ownedId, ownedRecord in pairs(ownedAuras) do
		local auraConfig = typeof(ownedRecord) == "table" and AuraConfig.Get(ownedRecord.auraId) or nil
		if auraConfig then
			table.insert(auraCandidates, {
				ownedId = ownedId,
				auraId = auraConfig.id,
				preferred = currentEquippedAuraId == auraConfig.id,
			})
		end
	end

	if #auraCandidates == 0 then
		table.insert(auraCandidates, {
			ownedId = "",
			auraId = nil,
			preferred = currentEquippedAuraId == nil,
		})
	end

	return auraCandidates
end

local function getOwnedAccessoryCandidatesBySlot(
	ownedAccessories: { [string]: any },
	currentEquippedAccessories: { [string]: string? }
)
	local candidatesBySlot = {}
	for _, slot in ipairs(AccessoryConfig.SlotOrder) do
		candidatesBySlot[slot] = {}
	end

	for ownedId, ownedRecord in pairs(ownedAccessories) do
		if typeof(ownedRecord) ~= "table" then
			continue
		end

		local accessoryConfig = AccessoryConfig.Get(ownedRecord.accessoryId)
		if not accessoryConfig or accessoryConfig.slot ~= ownedRecord.slot then
			continue
		end

		local slotCandidates = candidatesBySlot[accessoryConfig.slot]
		if slotCandidates then
			table.insert(slotCandidates, {
				ownedId = ownedId,
				accessoryId = accessoryConfig.id,
				slot = accessoryConfig.slot,
				preferred = currentEquippedAccessories[accessoryConfig.slot] == ownedId,
			})
		end
	end

	for _, slot in ipairs(AccessoryConfig.SlotOrder) do
		if #candidatesBySlot[slot] == 0 then
			table.insert(candidatesBySlot[slot], {
				ownedId = "",
				accessoryId = nil,
				slot = slot,
				preferred = currentEquippedAccessories[slot] == nil,
			})
		end
	end

	return candidatesBySlot
end

local function buildAccessoryStateForCandidates(headCandidate, gearCandidate, ownedAccessories)
	local equippedAccessories = {
		HeadAccessory = nil,
		GearAccessory = nil,
		_ownedAccessories = ownedAccessories,
	}

	if headCandidate and typeof(headCandidate.ownedId) == "string" and headCandidate.ownedId ~= "" then
		equippedAccessories.HeadAccessory = headCandidate.ownedId
	end
	if gearCandidate and typeof(gearCandidate.ownedId) == "string" and gearCandidate.ownedId ~= "" then
		equippedAccessories.GearAccessory = gearCandidate.ownedId
	end

	return equippedAccessories
end

local function buildPersistedAccessoryState(equippedAccessories)
	local persistedState = {
		HeadAccessory = nil,
		GearAccessory = nil,
	}

	for _, slot in ipairs(AccessoryConfig.SlotOrder) do
		local ownedId = equippedAccessories and equippedAccessories[slot] or nil
		if typeof(ownedId) == "string" and ownedId ~= "" then
			persistedState[slot] = ownedId
		end
	end

	return persistedState
end

local function buildSetupScore(equippedState, ownedBodyParts, equippedAuraId, equippedAccessories)
	local bonuses = computeLoadoutBonuses(equippedState, ownedBodyParts, equippedAuraId, equippedAccessories)
	local passiveIncomePerSecond = math.max(0, tonumber(bonuses.passiveIncomePerSecond) or 0)
		* math.max(1, tonumber(bonuses.passiveIncomeMultiplier) or 1)
	local luckBonus = ((1 + math.max(0, tonumber(bonuses.luckBonus) or 0))
		* math.max(1, tonumber(bonuses.luckMultiplier) or 1))
		- 1

	return {
		passiveIncomePerSecond = passiveIncomePerSecond,
		luckBonus = luckBonus,
		rollSpeedBonus = math.max(0, tonumber(bonuses.rollSpeedBonus) or 0),
		damage = math.max(0, tonumber(bonuses.damage) or 0),
		health = math.max(0, tonumber(bonuses.health) or 0),
		speed = math.max(0, tonumber(bonuses.speed) or 0),
	}
end

local function compareSetupScores(leftScore, rightScore): number
	if leftScore == rightScore then
		return 0
	end
	if leftScore == nil then
		return -1
	end
	if rightScore == nil then
		return 1
	end

	for _, key in ipairs({ "passiveIncomePerSecond", "luckBonus", "rollSpeedBonus", "damage", "health", "speed" }) do
		if leftScore[key] ~= rightScore[key] then
			return if leftScore[key] > rightScore[key] then 1 else -1
		end
	end

	return 0
end

local function countPreferredMatches(candidate): number
	local total = 0

	if candidate.bodyLoadoutCandidate and candidate.bodyLoadoutCandidate.preferredMatchCount then
		total += candidate.bodyLoadoutCandidate.preferredMatchCount
	end
	if candidate.auraCandidate and candidate.auraCandidate.preferred == true then
		total += 1
	end
	if candidate.headCandidate and candidate.headCandidate.preferred == true then
		total += 1
	end
	if candidate.gearCandidate and candidate.gearCandidate.preferred == true then
		total += 1
	end

	return total
end

local function compareOptionalIds(leftId: string?, rightId: string?): number
	local left = if typeof(leftId) == "string" then leftId else ""
	local right = if typeof(rightId) == "string" then rightId else ""
	if left == right then
		return 0
	end
	return if left < right then 1 else -1
end

local function compareFullSetupCandidates(leftCandidate, rightCandidate): number
	if leftCandidate == rightCandidate then
		return 0
	end
	if leftCandidate == nil then
		return -1
	end
	if rightCandidate == nil then
		return 1
	end

	local scoreComparison = compareSetupScores(leftCandidate.score, rightCandidate.score)
	if scoreComparison ~= 0 then
		return scoreComparison
	end

	local leftPreferredMatches = countPreferredMatches(leftCandidate)
	local rightPreferredMatches = countPreferredMatches(rightCandidate)
	if leftPreferredMatches ~= rightPreferredMatches then
		return if leftPreferredMatches > rightPreferredMatches then 1 else -1
	end

	for _, region in ipairs(BodyPartRegions.Order) do
		local leftEntry = leftCandidate.equippedState[region]
		local rightEntry = rightCandidate.equippedState[region]
		local idComparison = compareOptionalIds(
			if leftEntry ~= nil then leftEntry.ownedId else nil,
			if rightEntry ~= nil then rightEntry.ownedId else nil
		)
		if idComparison ~= 0 then
			return idComparison
		end
	end

	local auraComparison = compareOptionalIds(leftCandidate.equippedAuraId, rightCandidate.equippedAuraId)
	if auraComparison ~= 0 then
		return auraComparison
	end

	for _, slot in ipairs(AccessoryConfig.SlotOrder) do
		local accessoryComparison = compareOptionalIds(
			leftCandidate.equippedAccessories[slot],
			rightCandidate.equippedAccessories[slot]
		)
		if accessoryComparison ~= 0 then
			return accessoryComparison
		end
	end

	return 0
end

local function getBodyLoadoutPreferredMatchCount(bodyLoadoutCandidate, currentEquippedState)
	local total = 0

	for _, region in ipairs(BodyPartRegions.Order) do
		local candidateEntry = bodyLoadoutCandidate.equippedState[region]
		local currentEntry = currentEquippedState[region]
		if candidateEntry == nil and currentEntry == nil then
			total += 1
		elseif candidateEntry ~= nil and currentEntry ~= nil and candidateEntry.ownedId == currentEntry.ownedId then
			total += 1
		end
	end

	return total
end

local function getBestLoadoutCandidate(player: Player)
	local currentEquippedState = SessionStore.GetEquipped(player)
	local currentEquippedAuraId = DataService:GetEquippedAuraId(player)
	local currentEquippedAccessories = DataService:GetEquippedAccessories(player)
	local ownedBodyParts = DataService:GetOwnedBodyParts(player)
	local ownedAuras = DataService:GetOwnedAuras(player)
	local ownedAccessories = DataService:GetOwnedAccessories(player)
	local bodyLoadoutCandidates = buildBodyLoadoutCandidates(player)
	local auraCandidates = getOwnedAuraCandidates(ownedAuras, currentEquippedAuraId)
	local accessoryCandidatesBySlot = getOwnedAccessoryCandidatesBySlot(ownedAccessories, currentEquippedAccessories)
	local bestSetupCandidate = nil

	for _, bodyLoadoutCandidate in ipairs(bodyLoadoutCandidates) do
		bodyLoadoutCandidate.preferredMatchCount =
			getBodyLoadoutPreferredMatchCount(bodyLoadoutCandidate, currentEquippedState)

		for _, auraCandidate in ipairs(auraCandidates) do
			for _, headCandidate in ipairs(accessoryCandidatesBySlot.HeadAccessory) do
				for _, gearCandidate in ipairs(accessoryCandidatesBySlot.GearAccessory) do
					local equippedAccessories = buildAccessoryStateForCandidates(
						headCandidate,
						gearCandidate,
						ownedAccessories
					)
					local setupCandidate = {
						bodyLoadoutCandidate = bodyLoadoutCandidate,
						auraCandidate = auraCandidate,
						headCandidate = headCandidate,
						gearCandidate = gearCandidate,
						equippedState = bodyLoadoutCandidate.equippedState,
						equippedAuraId = auraCandidate.auraId,
						equippedAccessories = buildPersistedAccessoryState(equippedAccessories),
						score = buildSetupScore(
							bodyLoadoutCandidate.equippedState,
							ownedBodyParts,
							auraCandidate.auraId,
							equippedAccessories
						),
					}

					if compareFullSetupCandidates(setupCandidate, bestSetupCandidate) > 0 then
						bestSetupCandidate = setupCandidate
					end
				end
			end
		end
	end

	return bestSetupCandidate
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
		sizeId = if ownedRecord then ownedRecord.sizeId else nil,
		sizeMultiplier = if ownedRecord then ownedRecord.sizeMultiplier else nil,
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

local function serializeInspectAccessoryEntry(ownedRecord: any, accessoryConfig: AccessoryConfig.AccessoryConfigEntry)
	return {
		ownedId = ownedRecord.ownedId,
		accessoryId = accessoryConfig.id,
		slot = accessoryConfig.slot,
		label = accessoryConfig.label,
		description = accessoryConfig.description,
		tierLabel = accessoryConfig.tierLabel,
		displayColor = accessoryConfig.displayColor,
		iconTexture = accessoryConfig.iconTexture,
		bonuses = accessoryConfig.bonuses,
	}
end

local function countOwnedRecords(recordsById: { [string]: any }): number
	local total = 0
	for _ in pairs(recordsById) do
		total += 1
	end
	return total
end

computeLoadoutBonuses = function(
	equippedState: BodyPartLoadout.EquippedState,
	ownedBodyParts: { [string]: OwnedBodyParts.OwnedBodyPartRecord }?,
	equippedAuraId: string?,
	equippedAccessories: any?
)
	local normalizedEquippedState = BodyPartLoadout.NormalizeEquippedState(equippedState, ownedBodyParts)
	local basePlayerStats = BodyPartsCatalog.GetBasePlayerStats()
	local bonuses = {
		passiveIncomePerSecond = 0,
		luckBonus = 0,
		rollSpeedBonus = 0,
		speedBonus = 0,
		damageBonus = 0,
		healthBonus = 0,
		luckMultiplier = 1,
		passiveIncomeMultiplier = 1,
		speedMultiplier = 1,
		damageMultiplier = 1,
		healthMultiplier = 1,
		speed = tonumber(basePlayerStats.speed) or 16,
		damage = tonumber(basePlayerStats.damage) or 20,
		health = tonumber(basePlayerStats.health) or 100,
		activeSetId = nil,
	}

	for _, region in ipairs(BodyPartRegions.Order) do
		local entry = normalizedEquippedState[region]
		if entry then
			local piece = BodyPartsCatalog.GetPiece(entry.pieceId)
			if piece then
				local ownedRecord = if ownedBodyParts then ownedBodyParts[entry.ownedId] else nil
				local combatStats = CombatPower.GetBodyPartContributionStats(piece, ownedRecord)
				bonuses.passiveIncomePerSecond += tonumber(ownedRecord and ownedRecord.finalPassiveIncomePerSecond)
					or tonumber(piece.passiveIncomePerSecond)
					or 0
				bonuses.luckBonus += tonumber(piece.luckBonus) or 0
				bonuses.rollSpeedBonus += tonumber(piece.rollSpeedBonus) or 0
				bonuses.speedBonus += tonumber(combatStats.speed) or 0
				bonuses.damageBonus += tonumber(combatStats.damage) or 0
				bonuses.healthBonus += tonumber(combatStats.health) or 0
			end
		end
	end

	local pieceIdsByRegion = buildEquippedPieceIdsByRegion(normalizedEquippedState)
	local setBonus = BodyPartsCatalog.GetFullSetBonus(pieceIdsByRegion)
	if setBonus then
		bonuses.passiveIncomePerSecond += tonumber(setBonus.passiveIncomePerSecond) or 0
		bonuses.luckBonus += tonumber(setBonus.luckBonus) or 0
		bonuses.rollSpeedBonus += tonumber(setBonus.rollSpeedBonus) or 0
		bonuses.speedBonus += tonumber(setBonus.speedBonus) or 0
		bonuses.damageBonus += tonumber(setBonus.damageBonus) or 0
		bonuses.healthBonus += tonumber(setBonus.healthBonus) or 0

		local samplePieceId = pieceIdsByRegion[BodyPartRegions.Order[1]]
		local setConfig = samplePieceId and BodyPartsCatalog.GetSetForPiece(samplePieceId) or nil
		bonuses.activeSetId = if setConfig then setConfig.id else nil
	end

	local auraConfig = AuraConfig.Get(equippedAuraId)
	if auraConfig and typeof(auraConfig.bonuses) == "table" then
		bonuses.passiveIncomePerSecond += tonumber(auraConfig.bonuses.passiveIncomePerSecondBonus) or 0
		bonuses.luckBonus += tonumber(auraConfig.bonuses.luckBonus) or 0
		bonuses.rollSpeedBonus += tonumber(auraConfig.bonuses.rollSpeedBonus) or 0
		bonuses.passiveIncomeMultiplier *= math.max(1, tonumber(auraConfig.bonuses.moneyMultiplier) or 1)
	end

	if typeof(equippedAccessories) == "table" then
		for _, slot in ipairs(AccessoryConfig.SlotOrder) do
			local ownedId = equippedAccessories[slot]
			if typeof(ownedId) ~= "string" or ownedId == "" then
				continue
			end

			local accessoryId = nil
			local ownedAccessories = equippedAccessories._ownedAccessories
			if typeof(ownedAccessories) == "table" and typeof(ownedAccessories[ownedId]) == "table" then
				accessoryId = ownedAccessories[ownedId].accessoryId
			end

			local accessoryConfig = AccessoryConfig.Get(accessoryId)
			if accessoryConfig and accessoryConfig.slot == slot and typeof(accessoryConfig.bonuses) == "table" then
				local accessoryBonuses = accessoryConfig.bonuses
				bonuses.passiveIncomePerSecond += tonumber(accessoryBonuses.passiveIncomePerSecondBonus) or 0
				bonuses.luckBonus += tonumber(accessoryBonuses.luckBonus) or 0
				bonuses.rollSpeedBonus += tonumber(accessoryBonuses.rollSpeedBonus) or 0
				bonuses.speedBonus += tonumber(accessoryBonuses.speedBonus) or 0
				bonuses.damageBonus += tonumber(accessoryBonuses.damageBonus) or 0
				bonuses.healthBonus += tonumber(accessoryBonuses.healthBonus) or 0
				bonuses.luckMultiplier *= math.max(1, tonumber(accessoryBonuses.luckMultiplier) or 1)
				bonuses.passiveIncomeMultiplier *= math.max(1, tonumber(accessoryBonuses.passiveIncomeMultiplier) or 1)
				bonuses.speedMultiplier *= math.max(1, tonumber(accessoryBonuses.speedMultiplier) or 1)
				bonuses.damageMultiplier *= math.max(1, tonumber(accessoryBonuses.damageMultiplier) or 1)
				bonuses.healthMultiplier *= math.max(1, tonumber(accessoryBonuses.healthMultiplier) or 1)
			end
		end
	end

	bonuses.speed = (bonuses.speed + bonuses.speedBonus) * bonuses.speedMultiplier
	bonuses.damage = (bonuses.damage + bonuses.damageBonus) * bonuses.damageMultiplier
	bonuses.health = (bonuses.health + bonuses.healthBonus) * bonuses.healthMultiplier

	return bonuses
end

function BodyPartService:GetComputedLoadoutBonuses(player: Player)
	local ownedBodyParts = DataService:GetOwnedBodyParts(player)
	local ownedAccessories = DataService:GetOwnedAccessories(player)
	local equippedAccessories = DataService:GetEquippedAccessories(player)
	equippedAccessories._ownedAccessories = ownedAccessories
	local equippedAuraId = DataService:GetEquippedAuraId(player)
	if equippedAuraId and not DataService:GetOwnedAuraByAuraId(player, equippedAuraId) then
		equippedAuraId = nil
	end

	return computeLoadoutBonuses(SessionStore.GetEquipped(player), ownedBodyParts, equippedAuraId, equippedAccessories)
end

function BodyPartService:GetPersistedLoadoutBonuses(player: Player)
	local ownedBodyParts = DataService:GetOwnedBodyParts(player)
	local ownedAccessories = DataService:GetOwnedAccessories(player)
	local equippedAccessories = DataService:GetEquippedAccessories(player)
	equippedAccessories._ownedAccessories = ownedAccessories
	local equippedAuraId = DataService:GetEquippedAuraId(player)
	if equippedAuraId and not DataService:GetOwnedAuraByAuraId(player, equippedAuraId) then
		equippedAuraId = nil
	end

	return computeLoadoutBonuses(DataService:GetEquippedLoadout(player), ownedBodyParts, equippedAuraId, equippedAccessories)
end

function BodyPartService:GetSessionLoadout(player: Player): BodyPartLoadout.EquippedState
	return SessionStore.GetEquipped(player)
end

function BodyPartService:RefreshEquippedOwnedBodyPartVariant(
	player: Player,
	ownedId: string,
	newScale: number
): (boolean, string)
	if typeof(ownedId) ~= "string" or ownedId == "" then
		return false, "ownedId is required."
	end

	local previousState = SessionStore.GetEquipped(player)
	local equippedRegion, equippedEntry = findEquippedEntryForOwnedId(previousState, ownedId)
	if not equippedRegion or not equippedEntry then
		return true, "Owned body part variant refreshed."
	end

	local piece = BodyPartsCatalog.GetPiece(equippedEntry.pieceId)
	if not piece then
		return false, string.format("Unknown piece '%s'.", tostring(equippedEntry.pieceId))
	end

	local ownedRecord = DataService:GetOwnedBodyParts(player)[ownedId]
	if not ownedRecord then
		return false, "You do not own that body part."
	end

	SessionStore.SetEquipped(player, {
		ownedId = equippedEntry.ownedId,
		pieceId = equippedEntry.pieceId,
		region = equippedEntry.region,
		scale = resolveEffectiveScale(player, piece.id, ownedRecord, newScale, nil),
	})

	local success, applyMessage = rebuildCurrentVisualStateNow(player, "refresh_equipped_variant")
	if not success then
		rollbackVisualState(player, previousState)
		return false, applyMessage or "Failed to refresh the equipped body part variant."
	end

	local persisted, persistMessage = persistSessionLoadout(player, previousState, true)
	if not persisted then
		return false, persistMessage or "Failed to save the equipped body part loadout."
	end

	notifyLoadoutChanged(player)
	return true, "Owned body part variant refreshed."
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
	local ownedAccessories = DataService:GetOwnedAccessories(targetPlayer)
	local equippedAccessoryIds = DataService:GetEquippedAccessories(targetPlayer)
	local equippedAuraId = DataService:GetEquippedAuraId(targetPlayer)
	local equipped = {}
	local equippedAura = nil
	local equippedAccessories = {}

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

	for _, slot in ipairs(AccessoryConfig.SlotOrder) do
		local ownedId = equippedAccessoryIds[slot]
		local ownedRecord = if typeof(ownedId) == "string" then ownedAccessories[ownedId] else nil
		local accessoryConfig = ownedRecord and AccessoryConfig.Get(ownedRecord.accessoryId) or nil
		if ownedRecord and accessoryConfig and accessoryConfig.slot == slot then
			equippedAccessories[slot] = serializeInspectAccessoryEntry(ownedRecord, accessoryConfig)
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
		currentOwnedAccessories = countOwnedRecords(ownedAccessories),
		stats = StatsService:GetStats(targetPlayer),
		equipped = equipped,
		equippedAura = equippedAura,
		equippedAccessories = equippedAccessories,
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
		DataService:GetOwnedBodyParts(player),
		getBodyPartScaleOverride(player)
	)
end

local function resolveEquippedGearConfig(player: Player): AccessoryConfig.AccessoryConfigEntry?
	local equippedAccessories = DataService:GetEquippedAccessories(player)
	local equippedOwnedId = equippedAccessories.GearAccessory
	if typeof(equippedOwnedId) ~= "string" or equippedOwnedId == "" then
		return nil
	end

	local ownedRecord = DataService:GetOwnedAccessories(player)[equippedOwnedId]
	if not ownedRecord then
		return nil
	end

	local config = AccessoryConfig.Get(ownedRecord.accessoryId)
	if not config or config.slot ~= "GearAccessory" then
		return nil
	end

	return config
end

local function resolveEquippedHeadAccessoryConfig(player: Player): AccessoryConfig.AccessoryConfigEntry?
	local equippedAccessories = DataService:GetEquippedAccessories(player)
	local equippedOwnedId = equippedAccessories.HeadAccessory
	if typeof(equippedOwnedId) ~= "string" or equippedOwnedId == "" then
		return nil
	end

	local ownedRecord = DataService:GetOwnedAccessories(player)[equippedOwnedId]
	if not ownedRecord then
		return nil
	end

	local config = AccessoryConfig.Get(ownedRecord.accessoryId)
	if not config or config.slot ~= "HeadAccessory" then
		return nil
	end

	return config
end

local function applyCurrentGearVisual(player: Player, character: Model): (boolean, string?)
	return GearVisuals.Apply(character, resolveEquippedGearConfig(player))
end

local function applyCurrentHeadAccessoryVisual(player: Player, character: Model): (boolean, string?)
	return HeadAccessoryVisuals.Apply(character, resolveEquippedHeadAccessoryConfig(player))
end

function BodyPartService:CanApplyCurrentVisualState(player: Player, equippedAuraIdOverride: string?): (boolean, string?)
	local character = getCharacter(player)
	if not character then
		return true, nil
	end
	local isCharacterReady, characterReadyError, characterReadyErrorKind = waitForCharacterReady(character)
	if not isCharacterReady then
		return false, getCharacterRigNotReadyMessage(characterReadyError, characterReadyErrorKind)
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

function BodyPartService:ApplySessionLoadout(player: Player, overrideAutoSizeEnabled: boolean?): (boolean, string?)
	local startedAt = PerfStats.Begin()
	local character = getCharacter(player)
	if not character then
		PerfStats.Measure("BodyPartVisualsApply", startedAt, {
			detail = string.format("%s:no_character", player.Name),
		})
		return true, nil
	end

	local isCharacterReady, characterReadyError, characterReadyErrorKind =
		waitForCharacterReady(character, CHARACTER_READY_TIMEOUT_SECONDS)
	if not isCharacterReady then
		local failureMessage = getCharacterRigNotReadyMessage(characterReadyError, characterReadyErrorKind)
		PerfStats.Measure("BodyPartVisualsApply", startedAt, {
			detail = string.format("%s:not_ready", player.Name),
		})
		return false, failureMessage
	end

	beginRuntimeMutationSuppression(player, character)
	setCharacterBuildLock(character, true)

	local callSucceeded, applySuccessOrTrace, applyMessage = xpcall(function()
		local equippedState = SessionStore.GetEquipped(player)
		local equippedAuraId = DataService:GetEquippedAuraId(player)
		local bodyPartScaleOverride = getBodyPartScaleOverride(player, overrideAutoSizeEnabled)

		if not BodyPartLoadout.HasAnyEquipped(equippedState) and equippedAuraId == nil and bodyPartScaleOverride == nil then
			local resetResult = BodyPartVisuals.Reset(character, getBaseRig())
			if not resetResult.success then
				return false, table.concat(resetResult.errors, " | ")
			end
		else
			local request, requestError = buildVisualApplyRequest(
				equippedState,
				equippedAuraId,
				DataService:GetOwnedBodyParts(player),
				bodyPartScaleOverride
			)
			if not request then
				return false, requestError or "Failed to build body part apply request."
			end

			local applyResult = BodyPartVisuals.Apply(character, request)
			if not applyResult.success then
				return false, table.concat(applyResult.errors, " | ")
			end
		end

		local headAccessorySuccess, headAccessoryMessage = applyCurrentHeadAccessoryVisual(player, character)
		if not headAccessorySuccess then
			return false, headAccessoryMessage or "Failed to apply the equipped head accessory visual."
		end

		local gearSuccess, gearMessage = applyCurrentGearVisual(player, character)
		if not gearSuccess then
			return false, gearMessage or "Failed to apply the equipped gear visual."
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
	ensureLiveHumanoidAutoRotateEnabled(character)
	PerfStats.Measure("BodyPartVisualsApply", startedAt, {
		detail = string.format("%s:%s", player.Name, if success then "ok" else "failed"),
	})
	return success, message
end

-- Any explicit server action that changes the effective equipped scale, or changes
-- how effective scale is resolved, must trigger a full visual rebuild before success
-- is returned. Persistence-only writes that do not change the active equipped scale
-- do not need to call this helper.
rebuildCurrentVisualStateNow = function(player: Player, reason: string?, overrideAutoSizeEnabled: boolean?): (boolean, string?)
	local success, applyMessage = BodyPartService:ApplySessionLoadout(player, overrideAutoSizeEnabled)
	if success then
		return true, nil
	end

	local detail = tostring(reason or "visual_rebuild")
	if applyMessage and applyMessage ~= "" then
		return false, string.format("Failed to rebuild visuals after %s: %s", detail, applyMessage)
	end
	return false, string.format("Failed to rebuild visuals after %s.", detail)
end

refreshCurrentAuraNow = function(player: Player, reason: string?): (boolean, string?)
	local character = getCharacter(player)
	if not character or not waitForCharacterReady(character) then
		return true, nil
	end

	if not shouldRefreshAuraRuntime(player, character) then
		return true, nil
	end

	local auraRequest, auraError = buildAuraApplyRequest(DataService:GetEquippedAuraId(player))
	if auraError then
		return false, auraError
	end

	beginRuntimeMutationSuppression(player, character)
	setCharacterBuildLock(character, true)

	local callSucceeded, refreshSuccessOrTrace, refreshMessage = xpcall(function()
		return BodyPartVisuals.RefreshAura(character, auraRequest)
	end, debug.traceback)

	setCharacterBuildLock(character, false)
	endRuntimeMutationSuppression(player, character)
	ensureLiveHumanoidAutoRotateEnabled(character)

	local success = refreshSuccessOrTrace
	local message = refreshMessage
	if not callSucceeded then
		success = false
		message = tostring(refreshSuccessOrTrace)
	end

	if success == nil then
		success = false
	end

	if not success then
		local detail = tostring(reason or "aura_refresh")
		return false, message or string.format("Failed to refresh aura runtime after %s.", detail)
	end

	local status = BodyPartVisuals.GetAuraRuntimeStatus(character, auraRequest)
	if not status.isComplete then
		local detail = tostring(reason or "aura_refresh")
		local statusMessage = status.message or "Aura runtime verification failed."
		if #status.missingTargetPartNames > 0 then
			statusMessage = string.format("%s Missing: %s.", statusMessage, table.concat(status.missingTargetPartNames, ", "))
		end
		return false, string.format("Failed to verify aura runtime after %s: %s", detail, statusMessage)
	end

	return true, nil
end

refreshCurrentAppearanceNow = function(player: Player, reason: string?): (boolean, string?)
	local character = getCharacter(player)
	if not character or not waitForCharacterReady(character) then
		return true, nil
	end

	if not shouldRefreshCharacterAppearance(player, character) then
		return true, nil
	end

	local request, requestError = BodyPartService:BuildCurrentVisualApplyRequest(player)
	if not request then
		return false, requestError or "Failed to build the current appearance refresh request."
	end

	beginRuntimeMutationSuppression(player, character)
	setCharacterBuildLock(character, true)

	local callSucceeded, refreshSuccessOrTrace, refreshMessage = xpcall(function()
		local appearanceSuccess, appearanceMessage = BodyPartVisuals.RefreshAppearance(character, request)
		if not appearanceSuccess then
			return false, appearanceMessage
		end

		return applyCurrentGearVisual(player, character)
	end, debug.traceback)

	setCharacterBuildLock(character, false)
	endRuntimeMutationSuppression(player, character)
	ensureLiveHumanoidAutoRotateEnabled(character)

	local success = refreshSuccessOrTrace
	local message = refreshMessage
	if not callSucceeded then
		success = false
		message = tostring(refreshSuccessOrTrace)
	end

	if success == nil then
		success = false
	end

	if success == false and message == nil then
		local detail = tostring(reason or "appearance_refresh")
		message = string.format("Failed to refresh character appearance after %s.", detail)
	end

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

	local success, applyMessage = refreshCurrentAuraNow(player, reason or "aura_cleanup")
	if not success then
		return false, applyMessage or "Failed to clear aura runtime."
	end

	if BodyPartVisuals.HasAuraRuntimeInstances(character) then
		local message = string.format("Aura runtime remained after %s.", tostring(reason or "cleanup"))
		Logger.Warn(string.format("[BodyPartService] %s", message))
		return false, message
	end

	return true, nil
end

rollbackVisualState = function(player: Player, previousState: BodyPartLoadout.EquippedState)
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
				DataService:GetOwnedBodyParts(player),
				getBodyPartScaleOverride(player)
			)
			if request then
				BodyPartVisuals.Apply(character, request)
			end
		else
			BodyPartVisuals.Reset(character, getBaseRig())
		end
	end, debug.traceback)

	setCharacterBuildLock(character, false)
	ensureLiveHumanoidAutoRotateEnabled(character)

	if not rollbackSucceeded then
		Logger.Warn(string.format("[BodyPartService] Failed to rollback visual state for %s: %s", player.Name, tostring(rollbackError)))
	end
end

restoreSessionState = function(player: Player, previousState: BodyPartLoadout.EquippedState)
	SessionStore.Restore(player, previousState)
end

rollbackMutationState = function(player: Player, previousState: BodyPartLoadout.EquippedState, applyVisuals: boolean)
	if applyVisuals then
		rollbackVisualState(player, previousState)
	else
		restoreSessionState(player, previousState)
	end
end

persistSessionLoadout = function(player: Player, previousState: BodyPartLoadout.EquippedState, applyVisuals: boolean): (boolean, string?)
	local canonicalState, canonicalError = resolveCanonicalEquippedStateScales(player, SessionStore.GetEquipped(player))
	if not canonicalState then
		rollbackMutationState(player, previousState, applyVisuals)
		return false, canonicalError or "Failed to resolve the equipped body part loadout."
	end

	local ok, message = DataService:SetEquippedLoadout(player, canonicalState)
	if ok then
		return true, nil
	end

	rollbackMutationState(player, previousState, applyVisuals)
	return false, message or "Failed to save the equipped body part loadout."
end

local function getSanitizedPersistedLoadout(player: Player): (BodyPartLoadout.EquippedState, boolean, string?)
	local persistedState = DataService:GetEquippedLoadout(player)
	local sanitizedState = BodyPartLoadout.NormalizeEquippedState(persistedState, DataService:GetOwnedBodyParts(player))
	local canonicalState, canonicalError = resolveCanonicalEquippedStateScales(player, sanitizedState)
	if canonicalState then
		sanitizedState = canonicalState
	elseif canonicalError then
		Logger.Warn(string.format("[BodyPartService] Failed to canonicalize persisted loadout for %s: %s", player.Name, canonicalError))
	end
	local didChange = not BodyPartLoadout.AreEquippedStatesEqual(persistedState, sanitizedState)
	if not didChange then
		return sanitizedState, false, nil
	end

	local ok, message = DataService:SetEquippedLoadout(player, sanitizedState)
	return sanitizedState, ok, message
end

local function syncSessionLoadoutFromPersistedData(player: Player): (boolean, BodyPartLoadout.EquippedState)
	local previousState = SessionStore.GetEquipped(player)
	local restoredState, savedCleanedState, savedCleanedStateMessage = getSanitizedPersistedLoadout(player)
	local visualState, visualStateError = resolveEquippedStateScales(player, restoredState, nil)
	if not visualState then
		Logger.Warn(string.format(
			"[BodyPartService] Failed to resolve visual loadout for %s: %s",
			player.Name,
			tostring(visualStateError)
		))
		visualState = BodyPartLoadout.CreateEmptyEquippedState()
	end
	SessionStore.LoadPlayer(player, visualState)

	if savedCleanedState == false and savedCleanedStateMessage then
		Logger.Warn(string.format("[BodyPartService] Failed to clean persisted loadout for %s: %s", player.Name, savedCleanedStateMessage))
	end

	return not BodyPartLoadout.AreEquippedStatesEqual(previousState, visualState), visualState
end

local function isCharacterCurrentForPlayer(player: Player, character: Model?): boolean
	if not (character and character:IsA("Model") and character.Parent) then
		return false
	end

	local state = getCharacterLifecycleState(player)
	return player.Parent == Players and player.Character == character and state.currentCharacter == character
end

local function markCurrentCharacter(player: Player, character: Model)
	local state = getCharacterLifecycleState(player)
	local didChange = state.currentCharacter ~= character

	if didChange then
		state.currentCharacter = character
		state.appearanceLoadedCharacter = nil
		state.activeRuntimeCharacter = nil
		state.lastActivationSource = nil
		state.fallbackGeneration += 1
		state.activationRetryAttempt = 0
		state.auraVisualVerifyGeneration += 1
		clearCharacterRuntimeWatcherState(player)
	end

	state.pendingRuntimeApply = true
	return state, didChange
end

local function logDeferredCharacterActivation(player: Player, source: string, reason: string)
	Logger.Print(string.format(
		"[BodyPartService] Delaying body part runtime activation for %s after %s: %s",
		player.Name,
		source,
		reason
	))
end

local function getCurrentAuraRuntimeStatus(
	player: Player,
	character: Model
): (BodyPartVisuals.AuraRuntimeStatus?, string?)
	local auraRequest, auraError = buildAuraApplyRequest(DataService:GetEquippedAuraId(player))
	if auraError then
		return nil, auraError
	end

	return BodyPartVisuals.GetAuraRuntimeStatus(character, auraRequest), nil
end

local function shouldCancelAuraVisualVerification(
	player: Player,
	character: Model,
	auraId: string,
	verifyGeneration: number
): boolean
	local state = characterLifecycleStates[player]
	if state == nil or state.auraVisualVerifyGeneration ~= verifyGeneration then
		return true
	end

	if not isCharacterCurrentForPlayer(player, character) or state.activeRuntimeCharacter ~= character then
		return true
	end

	return DataService:GetEquippedAuraId(player) ~= auraId
end

local function runAuraVisualVerificationRetry(
	player: Player,
	character: Model,
	auraId: string,
	source: string,
	verifyGeneration: number,
	attempt: number
)
	task.delay(AURA_VISUAL_VERIFY_RETRY_SECONDS, function()
		if shouldCancelAuraVisualVerification(player, character, auraId, verifyGeneration) then
			return
		end

		local status, statusError = getCurrentAuraRuntimeStatus(player, character)
		if status and status.isComplete then
			return
		end

		local isCharacterReady = waitForCharacterReady(character, CHARACTER_READY_TIMEOUT_SECONDS)
		if isCharacterReady and not shouldCancelAuraVisualVerification(player, character, auraId, verifyGeneration) then
			local success, applyMessage = refreshCurrentAuraNow(player, source)
			if not success and applyMessage then
				Logger.Warn(string.format(
					"[BodyPartService] Failed aura visual verification retry %d after %s for %s: %s",
					attempt,
					source,
					player.Name,
					applyMessage
				))
			end
		end

		status, statusError = getCurrentAuraRuntimeStatus(player, character)
		if shouldCancelAuraVisualVerification(player, character, auraId, verifyGeneration)
			or (status and status.isComplete)
		then
			return
		end

		if attempt < AURA_VISUAL_VERIFY_RETRY_LIMIT then
			runAuraVisualVerificationRetry(player, character, auraId, source, verifyGeneration, attempt + 1)
			return
		end

		Logger.Warn(string.format(
			"[BodyPartService] Equipped aura '%s' still has incomplete managed visual runtime for %s after %s: %s",
			auraId,
			player.Name,
			source,
			tostring(statusError or (status and status.message) or "unknown status")
		))
	end)
end

local function scheduleAuraVisualVerification(player: Player, character: Model, source: string)
	local equippedAuraId = DataService:GetEquippedAuraId(player)
	if equippedAuraId == nil or equippedAuraId == "" then
		return
	end

	local status, statusError = getCurrentAuraRuntimeStatus(player, character)
	if status and status.isComplete then
		return
	end
	if statusError then
		Logger.Warn(string.format(
			"[BodyPartService] Failed to inspect aura runtime after %s for %s: %s",
			source,
			player.Name,
			statusError
		))
	end

	local state = getCharacterLifecycleState(player)
	state.auraVisualVerifyGeneration += 1
	runAuraVisualVerificationRetry(player, character, equippedAuraId, source, state.auraVisualVerifyGeneration, 1)
end

local function tryActivateCharacterRuntime(
	player: Player,
	character: Model,
	source: string,
	options: { forceReapply: boolean? }?
): (boolean, string?)
	if not isCharacterCurrentForPlayer(player, character) then
		return false, "not_current_character"
	end

	local state = getCharacterLifecycleState(player)
	if not isPlayerDataReady(player) then
		state.pendingRuntimeApply = true
		return false, "player_data_not_ready"
	end

	local forceReapply = if typeof(options) == "table" then options.forceReapply == true else false
	local didChange = false
	didChange = syncSessionLoadoutFromPersistedData(player)

	local shouldApply = forceReapply
		or didChange
		or state.pendingRuntimeApply
		or state.activeRuntimeCharacter ~= character
	if not shouldApply then
		return true, nil
	end

	local isCharacterReady, characterReadyError, characterReadyErrorKind =
		waitForCharacterReady(character, CHARACTER_READY_TIMEOUT_SECONDS)
	if not isCharacterReady then
		if characterReadyErrorKind == "placeholder_character" then
			state.pendingRuntimeApply = true
			logDeferredCharacterActivation(
				player,
				source,
				tostring(characterReadyError or "Character appearance has not finished loading.")
			)
			return false, characterReadyErrorKind
		end

		state.pendingRuntimeApply = true
		Logger.Warn(string.format(
			"[BodyPartService] Character rig readiness failed during %s for %s: %s",
			source,
			player.Name,
			tostring(characterReadyError)
		))
		BodyPartService:NotifyClient(player, getCharacterRigNotReadyMessage(characterReadyError, characterReadyErrorKind))
		return false, characterReadyErrorKind or "character_not_ready"
	end

	attachCharacterRuntimeWatcher(player, character)

	local success, applyMessage = BodyPartService:ApplySessionLoadout(player)
	if not success then
		state.pendingRuntimeApply = true
		if applyMessage then
			BodyPartService:NotifyClient(player, applyMessage)
			Logger.Warn(string.format("[BodyPartService] %s", applyMessage))
		end
		return false, "apply_failed"
	end

	state.activeRuntimeCharacter = character
	state.activationRetryAttempt = 0
	state.pendingRuntimeApply = false
	state.lastActivationSource = source
	Logger.Print(string.format("[BodyPartService] Activated body part runtime for %s via %s.", player.Name, source))
	notifyLoadoutChanged(player)
	scheduleAuraVisualVerification(player, character, source)
	return true, nil
end

local function scheduleCharacterActivationRetry(
	player: Player,
	character: Model,
	source: string,
	retryAttempt: number,
	options: { forceReapply: boolean? }?
)
	if retryAttempt > CHARACTER_ACTIVATION_RETRY_LIMIT then
		return
	end

	local state = getCharacterLifecycleState(player)
	local fallbackGeneration = state.fallbackGeneration
	if state.activationRetryAttempt >= retryAttempt then
		return
	end

	state.activationRetryAttempt = retryAttempt

	task.delay(CHARACTER_ACTIVATION_RETRY_SECONDS, function()
		local activeState = characterLifecycleStates[player]
		if activeState == nil or activeState.fallbackGeneration ~= fallbackGeneration then
			return
		end

		if activeState.currentCharacter ~= character or activeState.activeRuntimeCharacter == character then
			return
		end

		local _, failureKind = tryActivateCharacterRuntime(player, character, source, options)
		if failureKind == "placeholder_character" or failureKind == "player_data_not_ready" then
			scheduleCharacterActivationRetry(player, character, source, retryAttempt + 1, options)
			return
		end

		if activeState.activationRetryAttempt == retryAttempt then
			activeState.activationRetryAttempt = 0
		end
	end)
end

local function queueCharacterActivation(
	player: Player,
	character: Model,
	source: string,
	options: { forceReapply: boolean? }?
)
	task.defer(function()
		local _, failureKind = tryActivateCharacterRuntime(player, character, source, options)
		if failureKind == "placeholder_character" or failureKind == "player_data_not_ready" then
			scheduleCharacterActivationRetry(player, character, source, 1, options)
		end
	end)
end

local function equipOwnedBodyPartInternal(
	player: Player,
	ownedId: string,
	requestedScale: number?,
	options: EquipOptions?
): (boolean, string)
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

	local shouldApplyVisuals = if typeof(options) == "table" then options.applyVisuals ~= false else true
	local shouldPersistLoadout = if typeof(options) == "table" then options.persistLoadout ~= false else true
	local shouldRecordStats = if typeof(options) == "table" then options.recordStats ~= false else true
	local shouldNotifyClient = if typeof(options) == "table" then options.notifyClient ~= false else true
	local shouldNotifyLoadoutChanged = if typeof(options) == "table" then options.notifyLoadoutChanged ~= false else true
	local scale = resolveEffectiveScale(player, piece.id, ownedRecord, requestedScale, if typeof(options) == "table" then options.autoSizeEnabled else nil)
	local previousState = SessionStore.GetEquipped(player)

	SessionStore.SetEquipped(player, {
		ownedId = ownedId,
		pieceId = piece.id,
		region = piece.region,
		scale = scale,
	})

	if shouldApplyVisuals then
		local success, applyMessage = rebuildCurrentVisualStateNow(player, "equip_owned_body_part")
		if not success then
			rollbackVisualState(player, previousState)
			return false, applyMessage or "Failed to apply the body part."
		end
	else
		local bonuses = BodyPartService:GetComputedLoadoutBonuses(player)
		if bonuses == nil then
			restoreSessionState(player, previousState)
			return false, "Failed to compute the equipped body part bonuses."
		end
	end

	if shouldPersistLoadout then
		local persisted, persistMessage = persistSessionLoadout(player, previousState, shouldApplyVisuals)
		if not persisted then
			return false, persistMessage or "Failed to save the equipped body part loadout."
		end
	end

	if shouldRecordStats then
		StatsService:RecordLoadoutAction(player, "equip")
	end
	if shouldNotifyClient then
		BodyPartService:NotifyClient(player, string.format("Equipped %s at %.2fx.", piece.displayName, scale))
	end
	if shouldNotifyLoadoutChanged then
		notifyLoadoutChanged(player)
	end
	TutorialService:RecordBodyPartEquipped(player, {
		ownedId = ownedId,
		pieceId = piece.id,
		region = piece.region,
	})

	return true, string.format("Equipped %s.", piece.displayName)
end

function BodyPartService:EquipOwnedBodyPart(player: Player, ownedId: string, requestedScale: number?, options: EquipOptions?): (boolean, string)
	return equipOwnedBodyPartInternal(player, ownedId, requestedScale, options)
end

function BodyPartService:IsBodyPartGrantBetterThanEquipped(player: Player, grantPayload: any): boolean
	return isBodyPartCandidateBetterThanEquipped(player, buildGrantPayloadBodyPartCandidate(grantPayload))
end

function BodyPartService:EquipOwnedBodyPartIfBetter(
	player: Player,
	ownedId: string,
	requestedScale: number?,
	options: EquipOptions?
): (boolean, string)
	if typeof(ownedId) ~= "string" or ownedId == "" then
		return false, "ownedId is required."
	end

	local ownedRecord = DataService:GetOwnedBodyParts(player)[ownedId]
	if not ownedRecord then
		return false, "You do not own that body part."
	end

	local candidate = buildOwnedBodyPartCandidate(ownedId, ownedRecord)
	if not isBodyPartCandidateBetterThanEquipped(player, candidate) then
		return false, "Rolled body part is not better than the equipped slot."
	end

	return equipOwnedBodyPartInternal(player, ownedId, requestedScale, options)
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

function BodyPartService:EquipBestLoadout(player: Player): (boolean, string)
	local previousState = SessionStore.GetEquipped(player)
	local previousAuraId = DataService:GetEquippedAuraId(player)
	local previousAccessories = DataService:GetEquippedAccessories(player)
	local bestLoadoutCandidate = getBestLoadoutCandidate(player)
	if bestLoadoutCandidate == nil then
		local message = "No owned body parts, auras, or accessories are available to equip."
		self:NotifyClient(player, message)
		return true, message
	end

	local resolvedBestEquippedState, resolveError = resolveEquippedStateScales(player, bestLoadoutCandidate.equippedState, nil)
	if not resolvedBestEquippedState then
		return false, resolveError or "Failed to resolve the best loadout scales."
	end

	local bestEquippedAccessories = buildPersistedAccessoryState(bestLoadoutCandidate.equippedAccessories)
	local function areAccessoriesEqual(left, right): boolean
		for _, slot in ipairs(AccessoryConfig.SlotOrder) do
			if left[slot] ~= right[slot] then
				return false
			end
		end
		return true
	end

	local hasAnyEquipped = BodyPartLoadout.HasAnyEquipped(resolvedBestEquippedState)
		or bestLoadoutCandidate.equippedAuraId ~= nil
		or bestEquippedAccessories.HeadAccessory ~= nil
		or bestEquippedAccessories.GearAccessory ~= nil
	local isAlreadyEquipped = BodyPartLoadout.AreEquippedStatesEqual(previousState, resolvedBestEquippedState)
		and previousAuraId == bestLoadoutCandidate.equippedAuraId
		and areAccessoriesEqual(previousAccessories, bestEquippedAccessories)

	if isAlreadyEquipped then
		local message = if hasAnyEquipped
			then "Best loadout is already equipped."
			else "No owned body parts, auras, or accessories are available to equip."
		self:NotifyClient(player, message)
		return true, message
	end

	local function restorePreviousEquipment()
		SessionStore.Restore(player, previousState)

		local auraRestored, auraRestoreMessage = DataService:SetEquippedAuraId(player, previousAuraId)
		if not auraRestored then
			Logger.Warn(string.format(
				"[BodyPartService] Failed to restore previous aura for %s after Equip Best rollback: %s",
				player.Name,
				tostring(auraRestoreMessage)
			))
		end

		local accessoriesRestored, accessoriesRestoreMessage =
			DataService:SetEquippedAccessories(player, previousAccessories)
		if not accessoriesRestored then
			Logger.Warn(string.format(
				"[BodyPartService] Failed to restore previous accessories for %s after Equip Best rollback: %s",
				player.Name,
				tostring(accessoriesRestoreMessage)
			))
		end

		rollbackVisualState(player, previousState)
		self:ApplySessionLoadout(player)
	end

	SessionStore.Restore(player, resolvedBestEquippedState)

	local auraPersisted, auraPersistMessage = DataService:SetEquippedAuraId(player, bestLoadoutCandidate.equippedAuraId)
	if not auraPersisted then
		restorePreviousEquipment()
		return false, auraPersistMessage or "Failed to save the equipped aura."
	end

	local accessoriesPersisted, accessoriesPersistMessage =
		DataService:SetEquippedAccessories(player, bestEquippedAccessories)
	if not accessoriesPersisted then
		restorePreviousEquipment()
		return false, accessoriesPersistMessage or "Failed to save the equipped accessories."
	end

	local success, applyMessage = self:ApplySessionLoadout(player)
	if not success then
		restorePreviousEquipment()
		return false, applyMessage or "Failed to equip the best loadout."
	end

	local persisted, persistMessage = persistSessionLoadout(player, previousState, true)
	if not persisted then
		restorePreviousEquipment()
		return false, persistMessage or "Failed to save the equipped body part loadout."
	end

	local successMessage = if hasAnyEquipped
		then "Equipped best loadout."
		else "No owned body parts, auras, or accessories are available to equip."
	if hasAnyEquipped then
		StatsService:RecordLoadoutAction(player, "equip")
	end
	self:NotifyClient(player, successMessage)
	notifyLoadoutChanged(player)
	return true, successMessage
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

local function handleGetTotalInExistences(_player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return {
			ok = false,
			message = "Existence payload must be a table.",
		}
	end

	local pieceIds = payload.pieceIds
	if typeof(pieceIds) ~= "table" then
		return {
			ok = false,
			message = "pieceIds must be a table.",
		}
	end

	local normalizedPieceIds = {}
	local seenPieceIds = {}
	for _, pieceId in ipairs(pieceIds) do
		if typeof(pieceId) ~= "string" or pieceId == "" then
			return {
				ok = false,
				message = "pieceId is required.",
			}
		end
		if seenPieceIds[pieceId] ~= true then
			seenPieceIds[pieceId] = true
			table.insert(normalizedPieceIds, pieceId)
		end
	end

	local countsByPieceId, message = DataService:GetTotalInExistenceForPieces(normalizedPieceIds)
	if countsByPieceId == nil then
		return {
			ok = false,
			message = message or "Failed to load body part existence counts.",
		}
	end

	return {
		ok = true,
		countsByPieceId = countsByPieceId,
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

	if targetUserId == player.UserId then
		return {
			ok = false,
			message = "You cannot inspect yourself.",
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

local function handleEquipBest(player: Player)
	local ok, message = BodyPartService:EquipBestLoadout(player)
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
		return response(false, "Regular scale payload must be a table.", BodyPartService:GetClientState(player))
	end

	local nextAutoSizeEnabled = payload.enabled == true
	local previousAutoSizeEnabled = DataService:GetAutoSizeEnabled(player)
	local previousState = SessionStore.GetEquipped(player)

	if previousAutoSizeEnabled ~= nextAutoSizeEnabled then
		local canonicalState, canonicalError = resolveCanonicalEquippedStateScales(player, previousState)
		if not canonicalState then
			return response(false, canonicalError or "Failed to resolve the equipped body part loadout.", BodyPartService:GetClientState(player))
		end

		local visualState, visualStateError = resolveEquippedStateScales(player, canonicalState, nextAutoSizeEnabled)
		if not visualState then
			return response(false, visualStateError or "Failed to resolve regular scale visuals.", BodyPartService:GetClientState(player))
		end
		SessionStore.Restore(player, visualState)

		local success, applyMessage = rebuildCurrentVisualStateNow(player, "set_auto_size_enabled", nextAutoSizeEnabled)
		if not success then
			rollbackVisualState(player, previousState)
			return response(false, applyMessage or "Failed to apply regular scale.", BodyPartService:GetClientState(player))
		end
	end

	local ok, message = DataService:SetAutoSizeEnabled(player, nextAutoSizeEnabled)
	if not ok then
		rollbackVisualState(player, previousState)
		return response(false, message or "Failed to update regular scale.", BodyPartService:GetClientState(player))
	end

	notifyLoadoutChanged(player)
	return response(true, message or "Regular scale updated.", BodyPartService:GetClientDeltaState(player, message))
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
	getExistencesRemote = ensureRemoteFunction(getExistencesRemote, GET_EXISTENCES_REMOTE_NAME)
	getPlayerInspectSummaryRemote = ensureRemoteFunction(getPlayerInspectSummaryRemote, GET_PLAYER_INSPECT_SUMMARY_REMOTE_NAME)
	equipRemote = ensureRemoteFunction(equipRemote, EQUIP_REMOTE_NAME)
	equipBestRemote = ensureRemoteFunction(equipBestRemote, EQUIP_BEST_REMOTE_NAME)
	unequipRemote = ensureRemoteFunction(unequipRemote, UNEQUIP_REMOTE_NAME)
	setAutoSizeEnabledRemote = ensureRemoteFunction(setAutoSizeEnabledRemote, SET_AUTO_SIZE_ENABLED_REMOTE_NAME)
	clearRemote = ensureRemoteFunction(clearRemote, CLEAR_REMOTE_NAME)
	toggleFavoriteRemote = ensureRemoteFunction(toggleFavoriteRemote, TOGGLE_FAVORITE_REMOTE_NAME)
	sellOwnedRemote = ensureRemoteFunction(sellOwnedRemote, SELL_OWNED_REMOTE_NAME)
	sellAllRemote = ensureRemoteFunction(sellAllRemote, SELL_ALL_REMOTE_NAME)
	updatedRemote = ensureUpdatedRemote()

	getStateRemote.OnServerInvoke = function(player: Player)
		local allowed = RequestLimiter:Allow(player, "remote.body_parts.get_state")
		if not allowed then
			return buildRateLimitResponse("You're refreshing your inventory too quickly.", BodyPartService:GetClientState(player))
		end

		return handleGetState(player)
	end
	getExistenceRemote.OnServerInvoke = function(player: Player, payload: any)
		local allowed = RequestLimiter:Allow(player, "remote.body_parts.existence")
		if not allowed then
			return {
				ok = false,
				message = "You're checking existence counts too quickly.",
			}
		end

		return handleGetTotalInExistence(player, payload)
	end
	getExistencesRemote.OnServerInvoke = function(player: Player, payload: any)
		local allowed = RequestLimiter:Allow(player, "remote.body_parts.existence")
		if not allowed then
			return {
				ok = false,
				message = "You're checking existence counts too quickly.",
			}
		end

		return handleGetTotalInExistences(player, payload)
	end
	getPlayerInspectSummaryRemote.OnServerInvoke = function(player: Player, payload: any)
		local allowed = RequestLimiter:Allow(player, "remote.body_parts.inspect")
		if not allowed then
			return {
				ok = false,
				message = "You're inspecting players too quickly.",
			}
		end

		return handleGetPlayerInspectSummary(player, payload)
	end
	equipRemote.OnServerInvoke = function(player: Player, payload: any)
		local allowed = RequestLimiter:Allow(player, "remote.body_parts.equip")
		if not allowed then
			return buildRateLimitResponse("You're equipping body parts too quickly.", BodyPartService:GetClientState(player))
		end

		return handleEquip(player, payload)
	end
	equipBestRemote.OnServerInvoke = function(player: Player)
		local allowed = RequestLimiter:Allow(player, "remote.body_parts.equip_best")
		if not allowed then
			return buildRateLimitResponse("You're equipping loadouts too quickly.", BodyPartService:GetClientState(player))
		end

		return handleEquipBest(player)
	end
	unequipRemote.OnServerInvoke = function(player: Player, payload: any)
		local allowed = RequestLimiter:Allow(player, "remote.body_parts.unequip")
		if not allowed then
			return buildRateLimitResponse("You're unequipping body parts too quickly.", BodyPartService:GetClientState(player))
		end

		return handleUnequip(player, payload)
	end
	setAutoSizeEnabledRemote.OnServerInvoke = function(player: Player, payload: any)
		local allowed = RequestLimiter:Allow(player, "remote.body_parts.auto_size")
		if not allowed then
			return buildRateLimitResponse("You're toggling regular scale too quickly.", BodyPartService:GetClientState(player))
		end

		return handleSetAutoSizeEnabled(player, payload)
	end
	clearRemote.OnServerInvoke = function(player: Player)
		local allowed = RequestLimiter:Allow(player, "remote.body_parts.clear")
		if not allowed then
			return buildRateLimitResponse("You're clearing loadouts too quickly.", BodyPartService:GetClientState(player))
		end

		return handleClear(player)
	end
	toggleFavoriteRemote.OnServerInvoke = function(player: Player, payload: any)
		local allowed = RequestLimiter:Allow(player, "remote.body_parts.favorite")
		if not allowed then
			return buildRateLimitResponse("You're changing favorites too quickly.", BodyPartService:GetClientState(player))
		end

		return handleToggleFavorite(player, payload)
	end
	sellOwnedRemote.OnServerInvoke = function(player: Player, payload: any)
		local allowed = RequestLimiter:Allow(player, "remote.body_parts.sell_one")
		if not allowed then
			return buildRateLimitResponse("You're selling body parts too quickly.", BodyPartService:GetClientState(player))
		end

		return handleSellOwned(player, payload)
	end
	sellAllRemote.OnServerInvoke = function(player: Player)
		local allowed = RequestLimiter:Allow(player, "remote.body_parts.sell_all")
		if not allowed then
			return buildRateLimitResponse("You're bulk selling too quickly.", BodyPartService:GetClientState(player))
		end

		return handleSellAll(player)
	end

	DataService.EquippedAuraChanged:Connect(function(player: Player)
		BodyPartService:NotifyClient(player)
		notifyLoadoutChanged(player)
		requestAuraReapply(player, "equipped_aura_changed")
	end)
	PotionService.StateChanged:Connect(function(player: Player, _bonuses: PotionRuntimeBonuses.RuntimeBonuses?)
		local nextScaleOverride = getBodyPartScaleOverride(player)
		local previousScaleOverride = lastBodyPartScaleOverrideByPlayer[player]
		lastBodyPartScaleOverrideByPlayer[player] = nextScaleOverride

		if previousScaleOverride == nextScaleOverride then
			return
		end

		local success, applyMessage = rebuildCurrentVisualStateNow(player, "potion_scale_override_changed")
		if not success then
			if applyMessage then
				BodyPartService:NotifyClient(player, applyMessage)
			end
			Logger.Warn(string.format("[BodyPartService] Failed to rebuild visuals after potion scale override change for %s: %s", player.Name, tostring(applyMessage)))
			return
		end

		notifyLoadoutChanged(player)
	end)

	DataService.PlayerDataLoaded:Connect(function(player: Player)
		playerDataReadyByPlayer[player] = true

		if player.Parent ~= Players then
			return
		end

		local didChange = syncSessionLoadoutFromPersistedData(player)
		local state = getCharacterLifecycleState(player)
		local character = state.currentCharacter or getCharacter(player)
		if not character then
			if didChange then
				notifyLoadoutChanged(player)
			end
			return
		end

		if state.currentCharacter ~= character then
			markCurrentCharacter(player, character)
			state = getCharacterLifecycleState(player)
		end

		state.pendingRuntimeApply = true
		queueCharacterActivation(player, character, "PlayerDataLoaded", {
			forceReapply = didChange or state.activeRuntimeCharacter ~= character,
		})
		if didChange and state.activeRuntimeCharacter ~= character then
			notifyLoadoutChanged(player)
		end
	end)
end

function BodyPartService:OnPlayerAdded(player: Player)
	lastBodyPartScaleOverrideByPlayer[player] = getBodyPartScaleOverride(player)
	waitForPlayerDataReady(player, PLAYER_DATA_READY_TIMEOUT_SECONDS)
	syncSessionLoadoutFromPersistedData(player)

	local state = getCharacterLifecycleState(player)

	if characterAddedConnections[player] then
		characterAddedConnections[player]:Disconnect()
	end
	if characterAppearanceLoadedConnections[player] then
		characterAppearanceLoadedConnections[player]:Disconnect()
	end

	characterAddedConnections[player] = player.CharacterAdded:Connect(function(character)
		markCurrentCharacter(player, character)
		queueCharacterActivation(player, character, "CharacterAdded")
	end)

	characterAppearanceLoadedConnections[player] = player.CharacterAppearanceLoaded:Connect(function(character)
		if player.Character ~= character then
			return
		end

		local activeState = getCharacterLifecycleState(player)
		if activeState.currentCharacter ~= character then
			markCurrentCharacter(player, character)
			activeState = getCharacterLifecycleState(player)
		end

		activeState.appearanceLoadedCharacter = character
		activeState.pendingRuntimeApply = true
		queueCharacterActivation(player, character, "CharacterAppearanceLoaded")
	end)

	if player.Character then
		local character = player.Character
		if character and character:IsA("Model") then
			markCurrentCharacter(player, character)
			state.pendingRuntimeApply = true
			queueCharacterActivation(player, character, "ExistingCharacter")
		end
	end
end

function BodyPartService:OnPlayerRemoving(player: Player)
	lastBodyPartScaleOverrideByPlayer[player] = nil
	playerDataReadyByPlayer[player] = nil
	if characterAddedConnections[player] then
		characterAddedConnections[player]:Disconnect()
		characterAddedConnections[player] = nil
	end
	if characterAppearanceLoadedConnections[player] then
		characterAppearanceLoadedConnections[player]:Disconnect()
		characterAppearanceLoadedConnections[player] = nil
	end
	characterLifecycleStates[player] = nil

	clearCharacterRuntimeWatcherState(player)

	local character = getCharacter(player)
	if character then
		BodyPartVisuals.Reset(character, getBaseRig())
	end

	SessionStore.CleanupPlayer(player)
end

return BodyPartService
