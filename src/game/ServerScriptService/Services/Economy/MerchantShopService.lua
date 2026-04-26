local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local MerchantShopState = require(ReplicatedStorage.Shared.Character.MerchantShopState)
local Globals = require(ReplicatedStorage.Lists.Globals)
local PotionConfig = require(ReplicatedStorage.Shared.Config.PotionConfig)
local MerchantShopConfig = require(ReplicatedStorage.Shared.Config.MerchantShopConfig)
local Schema = require(ReplicatedStorage.Lists.Schema)
local DataService = require(script.Parent.DataService)
local PotionService = require(script.Parent.PotionService)
local PurchaseReceiptService = require(script.Parent.PurchaseReceiptService)
local RequestLimiter = require(script.Parent.Common.RequestLimiter)

local REMOTES_FOLDER_NAME = "Remotes"
local MERCHANT_SHOP_FOLDER_NAME = "MerchantShop"
local GET_SHOP_STATE_REMOTE_NAME = "GetShopState"
local PURCHASE_SHOP_ITEM_REMOTE_NAME = "PurchaseShopItem"
local AVAILABILITY_CHANGED_REMOTE_NAME = "AvailabilityChanged"
local TELEPORT_TO_MERCHANT_REMOTE_NAME = "TeleportToMerchant"
local MERCHANT_SHOP_KEY = Schema.MerchantShop and Schema.MerchantShop.key or nil
local WINDOW_INTERVAL_SECONDS = 900
local WINDOW_ACTIVE_DURATION_SECONDS = 300
local WINDOW_OFFSET_SECONDS = 600
local PARKING_FOLDER_NAME = "MerchantNpcParking"
local LEGACY_PARKING_FOLDER_NAME = "AppraisalNpcParking"
local MERCHANT_MODEL_NAME = "Merchant"
local MERCHANT_SPAWN_TAG_NAME = "MerchantSpawn"
local MERCHANT_OCCUPANT_ATTRIBUTE_NAME = "MerchantOccupantId"
local MERCHANT_OCCUPANT_ID = "Merchant"
local DIALOGUE_ID_ATTRIBUTE_NAME = "DialogueId"
local DIALOGUE_FRAME_ATTRIBUTE_NAME = "DialogueFrameName"
local MERCHANT_DIALOGUE_ID = "merchant_default"
local MERCHANT_DIALOGUE_FRAME_NAME = "ShopUI"
local MERCHANT_GROUND_RAYCAST_HEIGHT = 64
local MERCHANT_GROUND_RAYCAST_DISTANCE = 512
local MERCHANT_GROUND_CLEARANCE = 0.05
local MERCHANT_GROUND_REFERENCE_NAMES = {
	"GroundAttachment",
	"GroundMarker",
	"GroundPivot",
	"PIVOT",
}
local TELEPORT_OFFSET_DISTANCE = 8
local TELEPORT_RAYCAST_HEIGHT = 24
local TELEPORT_RAYCAST_DISTANCE = 96
local TELEPORT_CLEARANCE = 0.1
local MERCHANT_TELEPORTER_OFFER_KEY = "merchant_teleporter"

local remotesFolder: Folder? = nil
local merchantShopFolder: Folder? = nil
local getShopStateRemote: RemoteFunction? = nil
local purchaseShopItemRemote: RemoteFunction? = nil
local availabilityChangedRemote: RemoteEvent? = nil
local teleportToMerchantRemote: RemoteFunction? = nil

local MerchantShopService = {
	_started = false,
	_forcedActiveUntil = 0,
	_merchantModel = nil :: Model?,
	_workspaceParent = nil :: Instance?,
	_lastUsedSpawn = nil :: BasePart?,
	_reservedSpawn = nil :: BasePart?,
	_activeWindowToken = nil :: string?,
	_failedWindowToken = nil :: string?,
	_merchantGroundOffset = nil :: number?,
	_merchantGroundOffsetModel = nil :: Model?,
	_lastBroadcastIsActive = nil :: boolean?,
	_lastBroadcastWindowId = nil :: number?,
	_random = Random.new(),
}

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

local function ensureRemoteEvent(cachedRemote: RemoteEvent?, remoteName: string): RemoteEvent
	local folder = ensureMerchantShopFolder()
	if cachedRemote and cachedRemote.Parent == folder then
		return cachedRemote
	end

	local existing = folder:FindFirstChild(remoteName)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = remoteName
	remote.Parent = folder
	return remote
end

local function getUtcNowSeconds(): number
	return math.floor(DateTime.now().UnixTimestampMillis / 1000)
end

local function buildWindowState(now: number, forcedActiveUntil: number?): MerchantShopState.MerchantShopStateValue
	local windowId = math.floor((now - WINDOW_OFFSET_SECONDS) / WINDOW_INTERVAL_SECONDS)
	local appearsAt = WINDOW_OFFSET_SECONDS + (windowId * WINDOW_INTERVAL_SECONDS)
	local departsAt = appearsAt + WINDOW_ACTIVE_DURATION_SECONDS
	local nextAppearsAt = appearsAt + WINDOW_INTERVAL_SECONDS
	local forcedDeparture = math.max(0, math.floor(tonumber(forcedActiveUntil) or 0))
	local isForcedActive = forcedDeparture > now

	return MerchantShopState.CloneState({
		windowId = windowId,
		isActive = (now >= appearsAt and now < departsAt) or isForcedActive,
		appearsAt = appearsAt,
		departsAt = if isForcedActive then math.max(departsAt, forcedDeparture) else departsAt,
		nextAppearsAt = nextAppearsAt,
		stockByPotionId = {},
	})
end

local function createWindowRandom(windowId: number): Random
	local normalizedWindowId = math.floor(tonumber(windowId) or 0)
	if normalizedWindowId < 0 then
		normalizedWindowId = math.abs(normalizedWindowId) + 104729
	end

	local seed = ((normalizedWindowId % 1000000) * 7919) % 2147483647
	if seed <= 0 then
		seed = 1
	end

	return Random.new(seed)
end

local function createWindowStockMap(windowId: number): { [string]: number }
	local stockByPotionId = {}
	local cycleRandom = createWindowRandom(windowId)
	for _, entry in ipairs(MerchantShopConfig.GetAll()) do
		local appearanceChance = math.clamp(tonumber(entry.appearanceChance) or 0, 0, 1)
		local stockPerRefresh = MerchantShopConfig.GetMaxStockForPotionId(entry.potionId)
		local appears = appearanceChance >= 1 or cycleRandom:NextNumber() <= appearanceChance
		stockByPotionId[entry.potionId] = if appears then stockPerRefresh else 0
	end
	return stockByPotionId
end

local function normalizeQuantity(quantity: any): number
	return math.max(0, math.floor(tonumber(quantity) or 0))
end

local function isValidMerchantSpawn(instance: Instance?): boolean
	return instance ~= nil and instance:IsA("BasePart") and instance:IsDescendantOf(Workspace)
end

local function getMerchantOccupantId(spawn: BasePart): string?
	local occupantId = spawn:GetAttribute(MERCHANT_OCCUPANT_ATTRIBUTE_NAME)
	if typeof(occupantId) == "string" and occupantId ~= "" then
		return occupantId
	end

	return nil
end

local function findMerchantPrompt(model: Model): ProximityPrompt?
	local namedPrompt = model:FindFirstChild("MerchantPrompt", true)
	if namedPrompt and namedPrompt:IsA("ProximityPrompt") then
		return namedPrompt
	end

	local fallbackPrompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
	if fallbackPrompt then
		return fallbackPrompt
	end

	return nil
end

local function getActiveWindowToken(state: MerchantShopState.MerchantShopStateValue): string?
	if state.isActive ~= true then
		return nil
	end

	return string.format("%d:%d", state.windowId, state.departsAt)
end

local function buildAvailabilityPayload(state: MerchantShopState.MerchantShopStateValue)
	return {
		isActive = state.isActive == true,
		windowId = math.floor(tonumber(state.windowId) or -1),
		appearsAt = math.floor(tonumber(state.appearsAt) or 0),
		departsAt = math.floor(tonumber(state.departsAt) or 0),
		nextAppearsAt = math.floor(tonumber(state.nextAppearsAt) or 0),
	}
end

local function getBasePartBottomY(part: BasePart): number
	local halfHeight = math.abs(part.CFrame.RightVector.Y) * (part.Size.X * 0.5)
		+ math.abs(part.CFrame.UpVector.Y) * (part.Size.Y * 0.5)
		+ math.abs(part.CFrame.LookVector.Y) * (part.Size.Z * 0.5)
	return part.Position.Y - halfHeight
end

local function getMerchantGroundReference(model: Model): (Instance?, number?)
	for _, referenceName in ipairs(MERCHANT_GROUND_REFERENCE_NAMES) do
		local reference = model:FindFirstChild(referenceName, true)
		if reference and reference:IsA("Attachment") then
			return reference, reference.WorldPosition.Y
		end
		if reference and reference:IsA("BasePart") then
			return reference, reference.Position.Y
		end
	end

	return nil, nil
end

local function getYawLookVector(cframe: CFrame): Vector3
	local flattenedLook = Vector3.new(cframe.LookVector.X, 0, cframe.LookVector.Z)
	if flattenedLook.Magnitude > 1e-4 then
		return flattenedLook.Unit
	end

	local flattenedRight = Vector3.new(cframe.RightVector.X, 0, cframe.RightVector.Z)
	if flattenedRight.Magnitude > 1e-4 then
		return Vector3.new(-flattenedRight.Z, 0, flattenedRight.X).Unit
	end

	return Vector3.new(0, 0, -1)
end

local function ensureParkingFolder(): Folder
	local existing = ServerStorage:FindFirstChild(PARKING_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = PARKING_FOLDER_NAME
	folder.Parent = ServerStorage
	return folder
end

function MerchantShopService:_ensureNpcResolved()
	if self._merchantModel and self._merchantModel.Parent then
		return
	end

	local parkingFolder = ensureParkingFolder()
	local legacyParkingFolder = ServerStorage:FindFirstChild(LEGACY_PARKING_FOLDER_NAME)
	local workspaceModel = Workspace:FindFirstChild(MERCHANT_MODEL_NAME)
	local parkedModel = parkingFolder:FindFirstChild(MERCHANT_MODEL_NAME)
	local legacyParkedModel = if legacyParkingFolder and legacyParkingFolder:IsA("Folder")
		then legacyParkingFolder:FindFirstChild(MERCHANT_MODEL_NAME)
		else nil

	local model = nil

	if workspaceModel and workspaceModel:IsA("Model") then
		model = workspaceModel
		self._workspaceParent = workspaceModel.Parent
	elseif parkedModel and parkedModel:IsA("Model") then
		model = parkedModel
	elseif legacyParkedModel and legacyParkedModel:IsA("Model") then
		model = legacyParkedModel
	end

	if not self._workspaceParent then
		self._workspaceParent = Workspace
	end

	if self._merchantModel ~= model then
		self._merchantGroundOffset = nil
		self._merchantGroundOffsetModel = nil
	end

	self._merchantModel = model
end

function MerchantShopService:_getMerchantGroundOffset(): number?
	self:_ensureNpcResolved()

	local merchantModel = self._merchantModel
	if not merchantModel then
		return nil
	end

	if self._merchantGroundOffsetModel == merchantModel and self._merchantGroundOffset ~= nil then
		return self._merchantGroundOffset
	end

	local pivotY = merchantModel:GetPivot().Position.Y
	local _, groundReferenceY = getMerchantGroundReference(merchantModel)
	if groundReferenceY ~= nil then
		local groundOffset = math.max(0, pivotY - groundReferenceY)
		self._merchantGroundOffset = groundOffset
		self._merchantGroundOffsetModel = merchantModel
		return groundOffset
	end

	local lowestBottomY = math.huge

	for _, descendant in ipairs(merchantModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			lowestBottomY = math.min(lowestBottomY, getBasePartBottomY(descendant))
		end
	end

	if lowestBottomY == math.huge then
		Logger.Warn("[MerchantShopService] The merchant model has no BasePart descendants for grounded placement.")
		return nil
	end

	local groundOffset = math.max(0, pivotY - lowestBottomY)
	Logger.Warn(string.format(
		"[MerchantShopService] Merchant model %s has no named ground reference; falling back to BasePart bounds for grounded placement.",
		merchantModel:GetFullName()
	))
	self._merchantGroundOffset = groundOffset
	self._merchantGroundOffsetModel = merchantModel
	return groundOffset
end

function MerchantShopService:_applyMerchantDialogueAttributes()
	self:_ensureNpcResolved()

	local merchantModel = self._merchantModel
	if not merchantModel then
		return
	end

	merchantModel:SetAttribute(DIALOGUE_ID_ATTRIBUTE_NAME, MERCHANT_DIALOGUE_ID)
	merchantModel:SetAttribute(DIALOGUE_FRAME_ATTRIBUTE_NAME, MERCHANT_DIALOGUE_FRAME_NAME)

	-- The client resolves dialogue from the interacted prompt upward, so the prompt
	-- itself must match in case a renamed rig still carries stale attributes.
	local merchantPrompt = findMerchantPrompt(merchantModel)
	if merchantPrompt then
		merchantPrompt:SetAttribute(DIALOGUE_ID_ATTRIBUTE_NAME, MERCHANT_DIALOGUE_ID)
		merchantPrompt:SetAttribute(DIALOGUE_FRAME_ATTRIBUTE_NAME, MERCHANT_DIALOGUE_FRAME_NAME)
	end
end

function MerchantShopService:_clearReservedSpawn()
	local reservedSpawn = self._reservedSpawn
	self._reservedSpawn = nil

	if not isValidMerchantSpawn(reservedSpawn) then
		return
	end

	if getMerchantOccupantId(reservedSpawn :: BasePart) == MERCHANT_OCCUPANT_ID then
		(reservedSpawn :: BasePart):SetAttribute(MERCHANT_OCCUPANT_ATTRIBUTE_NAME, nil)
	end
end

function MerchantShopService:_moveNpcToParking()
	self:_ensureNpcResolved()

	local merchantModel = self._merchantModel
	if not (merchantModel and merchantModel.Parent) then
		return
	end

	local parkingFolder = ensureParkingFolder()
	if merchantModel.Parent ~= parkingFolder then
		merchantModel.Parent = parkingFolder
	end
end

function MerchantShopService:_getMerchantSpawnCandidates(): { BasePart }
	local candidates = {}

	for _, instance in ipairs(CollectionService:GetTagged(MERCHANT_SPAWN_TAG_NAME)) do
		if isValidMerchantSpawn(instance) then
			table.insert(candidates, instance :: BasePart)
		end
	end

	return candidates
end

function MerchantShopService:_chooseMerchantSpawn(): BasePart?
	local availableSpawns = {}
	for _, spawn in ipairs(self:_getMerchantSpawnCandidates()) do
		local occupantId = getMerchantOccupantId(spawn)
		if occupantId == nil or occupantId == MERCHANT_OCCUPANT_ID then
			table.insert(availableSpawns, spawn)
		end
	end

	if #availableSpawns == 0 then
		return nil
	end

	local preferredSpawns = availableSpawns
	if #availableSpawns > 1 and isValidMerchantSpawn(self._lastUsedSpawn) then
		local filteredSpawns = {}
		for _, spawn in ipairs(availableSpawns) do
			if spawn ~= self._lastUsedSpawn then
				table.insert(filteredSpawns, spawn)
			end
		end

		if #filteredSpawns > 0 then
			preferredSpawns = filteredSpawns
		end
	end

	return preferredSpawns[self._random:NextInteger(1, #preferredSpawns)]
end

function MerchantShopService:_reserveSpawn(spawn: BasePart)
	self:_clearReservedSpawn()
	spawn:SetAttribute(MERCHANT_OCCUPANT_ATTRIBUTE_NAME, MERCHANT_OCCUPANT_ID)
	self._reservedSpawn = spawn
	self._lastUsedSpawn = spawn
end

function MerchantShopService:_getGroundedPlacementCFrame(spawn: BasePart): CFrame?
	self:_ensureNpcResolved()

	local merchantModel = self._merchantModel
	local groundOffset = self:_getMerchantGroundOffset()
	if not merchantModel or groundOffset == nil then
		Logger.Warn("[MerchantShopService] Merchant placement failed because the merchant ground offset could not be resolved.")
		return nil
	end

	local excludedInstances = self:_getMerchantSpawnCandidates()
	table.insert(excludedInstances, merchantModel)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = excludedInstances

	local rayOrigin = spawn.Position + Vector3.new(0, MERCHANT_GROUND_RAYCAST_HEIGHT, 0)
	local rayDirection = Vector3.new(0, -(MERCHANT_GROUND_RAYCAST_HEIGHT + MERCHANT_GROUND_RAYCAST_DISTANCE), 0)
	local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	if raycastResult == nil then
		Logger.Warn(string.format(
			"[MerchantShopService] Merchant placement failed because no ground was hit below %s.",
			spawn:GetFullName()
		))
		return nil
	end

	local position = Vector3.new(
		spawn.Position.X,
		raycastResult.Position.Y + groundOffset + MERCHANT_GROUND_CLEARANCE,
		spawn.Position.Z
	)
	local lookVector = getYawLookVector(spawn.CFrame)
	return CFrame.lookAt(position, position + lookVector, Vector3.new(0, 1, 0))
end

function MerchantShopService:_placeNpcAtSpawn(spawn: BasePart): boolean
	self:_ensureNpcResolved()

	local merchantModel = self._merchantModel
	if not merchantModel then
		return false
	end

	self:_applyMerchantDialogueAttributes()

	local placementCFrame = self:_getGroundedPlacementCFrame(spawn)
	if not placementCFrame then
		return false
	end

	local targetParent = self._workspaceParent or Workspace
	if merchantModel.Parent ~= targetParent then
		merchantModel.Parent = targetParent
	end

	merchantModel:PivotTo(placementCFrame)
	return true
end

function MerchantShopService:_setNpcActive(isActive: boolean, activeWindowToken: string?): boolean
	if not isActive then
		self._activeWindowToken = nil
		self._failedWindowToken = nil
		self:_clearReservedSpawn()
		self:_moveNpcToParking()
		return false
	end

	local reservedSpawn = self._reservedSpawn
	if isValidMerchantSpawn(reservedSpawn) then
		local occupantId = getMerchantOccupantId(reservedSpawn :: BasePart)
		if occupantId == nil or occupantId == MERCHANT_OCCUPANT_ID then
			(reservedSpawn :: BasePart):SetAttribute(MERCHANT_OCCUPANT_ATTRIBUTE_NAME, MERCHANT_OCCUPANT_ID)
			self._activeWindowToken = activeWindowToken
			self._failedWindowToken = nil
			if self:_placeNpcAtSpawn(reservedSpawn :: BasePart) then
				return true
			end
		end
	end

	self:_clearReservedSpawn()

	if activeWindowToken ~= nil and self._failedWindowToken == activeWindowToken then
		self:_moveNpcToParking()
		return false
	end

	local spawn = self:_chooseMerchantSpawn()
	if not spawn then
		self._failedWindowToken = activeWindowToken
		self:_moveNpcToParking()
		Logger.Warn("[MerchantShopService] No valid MerchantSpawn-tagged parts are available for the active merchant window.")
		return false
	end

	self:_reserveSpawn(spawn)
	self._activeWindowToken = activeWindowToken
	self._failedWindowToken = nil
	if self:_placeNpcAtSpawn(spawn) then
		return true
	end

	self:_clearReservedSpawn()
	self._activeWindowToken = nil
	self._failedWindowToken = activeWindowToken
	self:_moveNpcToParking()
	Logger.Warn("[MerchantShopService] The merchant placeholder model could not be placed at the selected merchant spawn.")
	return false
end

function MerchantShopService:_broadcastAvailability(state: MerchantShopState.MerchantShopStateValue)
	if not availabilityChangedRemote then
		return
	end

	availabilityChangedRemote:FireAllClients(buildAvailabilityPayload(state))
end

function MerchantShopService:_broadcastAvailabilityIfChanged(state: MerchantShopState.MerchantShopStateValue)
	local isActive = state.isActive == true
	local windowId = if isActive then math.floor(tonumber(state.windowId) or -1) else nil

	if self._lastBroadcastIsActive == isActive then
		if not isActive then
			return
		end
		if self._lastBroadcastWindowId == windowId then
			return
		end
	end

	self._lastBroadcastIsActive = isActive
	self._lastBroadcastWindowId = windowId
	self:_broadcastAvailability(state)
end

function MerchantShopService:_reconcileWindowState(): MerchantShopState.MerchantShopStateValue
	local now = getUtcNowSeconds()
	if self._forcedActiveUntil > 0 and now >= self._forcedActiveUntil then
		self._forcedActiveUntil = 0
	end

	local state = buildWindowState(now, self._forcedActiveUntil)
	local activeWindowToken = getActiveWindowToken(state)
	local isPlacedActive = self:_setNpcActive(state.isActive, activeWindowToken)
	if state.isActive and not isPlacedActive then
		state.isActive = false
	end

	self:_broadcastAvailabilityIfChanged(state)

	return state
end

function MerchantShopService:_getRawState(player: Player): MerchantShopState.MerchantShopStateValue
	if not MERCHANT_SHOP_KEY then
		return MerchantShopState.CreateEmptyState()
	end

	return MerchantShopState.CloneState(DataService:Get(player, MERCHANT_SHOP_KEY))
end

function MerchantShopService:_saveState(player: Player, state: MerchantShopState.MerchantShopStateValue): MerchantShopState.MerchantShopStateValue
	local normalizedState = MerchantShopState.CloneState({
		windowId = state.windowId,
		stockByPotionId = state.stockByPotionId,
	})
	if MERCHANT_SHOP_KEY then
		DataService:Set(player, MERCHANT_SHOP_KEY, normalizedState)
	end
	return normalizedState
end

local function mergeSavedStockOverride(
	baseStockByPotionId: { [string]: number },
	savedState: MerchantShopState.MerchantShopStateValue,
	windowId: number
): { [string]: number }
	local mergedStockByPotionId = MerchantShopState.CloneStockByPotionId(baseStockByPotionId)
	if savedState.windowId ~= windowId then
		return mergedStockByPotionId
	end

	for potionId, stock in pairs(savedState.stockByPotionId) do
		mergedStockByPotionId[potionId] = math.clamp(
			normalizeQuantity(stock),
			0,
			MerchantShopConfig.GetMaxStockForPotionId(potionId)
		)
	end

	return mergedStockByPotionId
end

function MerchantShopService:_resolveCurrentState(player: Player): MerchantShopState.MerchantShopStateValue
	local scheduleState = self:_reconcileWindowState()
	if not scheduleState.isActive then
		return scheduleState
	end

	local rawState = self:_getRawState(player)
	local baseStockByPotionId = createWindowStockMap(scheduleState.windowId)
	local resolvedStockByPotionId = mergeSavedStockOverride(baseStockByPotionId, rawState, scheduleState.windowId)

	return MerchantShopState.CloneState({
		windowId = scheduleState.windowId,
		isActive = true,
		appearsAt = scheduleState.appearsAt,
		departsAt = scheduleState.departsAt,
		nextAppearsAt = scheduleState.nextAppearsAt,
		stockByPotionId = resolvedStockByPotionId,
	})
end

function MerchantShopService:_getAffordability(player: Player, totalPrice: number): boolean
	return DataService:GetTimeShardsBalance(player) >= totalPrice
end

function MerchantShopService:_getTeleportAnchorPart(): BasePart?
	self:_ensureNpcResolved()

	local merchantModel = self._merchantModel
	if not merchantModel then
		return nil
	end

	local merchantPrompt = findMerchantPrompt(merchantModel)
	if merchantPrompt then
		local current: Instance? = merchantPrompt
		while current do
			if current:IsA("BasePart") then
				return current
			end
			current = current.Parent
		end
	end

	local humanoidRootPart = merchantModel:FindFirstChild("HumanoidRootPart", true)
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	local primaryPart = merchantModel.PrimaryPart
	if primaryPart then
		return primaryPart
	end

	return merchantModel:FindFirstChildWhichIsA("BasePart", true)
end

function MerchantShopService:_buildTeleportTargetCFrame(character: Model): CFrame?
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not (rootPart and rootPart:IsA("BasePart")) then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	local anchorPart = self:_getTeleportAnchorPart()
	local anchorCFrame = if anchorPart then anchorPart.CFrame else nil
	if anchorCFrame == nil then
		self:_ensureNpcResolved()
		local merchantModel = self._merchantModel
		if merchantModel and merchantModel:IsDescendantOf(Workspace) then
			anchorCFrame = merchantModel:GetPivot()
		end
	end
	if anchorCFrame == nil then
		return nil
	end

	local lookVector = getYawLookVector(anchorCFrame)
	local flatTargetPosition = anchorCFrame.Position + (lookVector * TELEPORT_OFFSET_DISTANCE)

	local excludedInstances = { character }
	local merchantModel = self._merchantModel
	if merchantModel then
		table.insert(excludedInstances, merchantModel)
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = excludedInstances

	local rayOrigin = flatTargetPosition + Vector3.new(0, TELEPORT_RAYCAST_HEIGHT, 0)
	local rayDirection = Vector3.new(0, -(TELEPORT_RAYCAST_HEIGHT + TELEPORT_RAYCAST_DISTANCE), 0)
	local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	local groundY = if raycastResult then raycastResult.Position.Y else flatTargetPosition.Y
	local standingHeight = math.max((rootPart.Size.Y * 0.5) + humanoid.HipHeight, rootPart.Size.Y)
	local targetPosition = Vector3.new(
		flatTargetPosition.X,
		groundY + standingHeight + TELEPORT_CLEARANCE,
		flatTargetPosition.Z
	)
	local lookAtPosition = Vector3.new(anchorCFrame.Position.X, targetPosition.Y, anchorCFrame.Position.Z)

	if (lookAtPosition - targetPosition).Magnitude <= 1e-4 then
		lookAtPosition = targetPosition - lookVector
	end

	return CFrame.lookAt(targetPosition, lookAtPosition, Vector3.new(0, 1, 0))
end

function MerchantShopService:TeleportToMerchant(player: Player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return {
			ok = false,
			message = "A valid player is required.",
		}
	end

	local shopState = self:_resolveCurrentState(player)
	if shopState.isActive ~= true then
		return {
			ok = false,
			message = "The merchant isn't here right now.",
			shopState = shopState,
		}
	end

	if not PurchaseReceiptService:HasEntitlement(player, MERCHANT_TELEPORTER_OFFER_KEY) then
		return {
			ok = false,
			message = "Merchant Teleporter ownership is required.",
			shopState = shopState,
		}
	end

	local character = player.Character
	if not (character and character:IsA("Model")) then
		return {
			ok = false,
			message = "Your character is not ready yet.",
			shopState = shopState,
		}
	end

	self:_ensureNpcResolved()
	local merchantModel = self._merchantModel
	if not (merchantModel and merchantModel:IsDescendantOf(Workspace)) then
		return {
			ok = false,
			message = "The merchant could not be located.",
			shopState = shopState,
		}
	end

	local targetCFrame = self:_buildTeleportTargetCFrame(character)
	if not targetCFrame then
		return {
			ok = false,
			message = "A safe teleport position could not be found.",
			shopState = shopState,
		}
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local linearVelocity = if rootPart and rootPart:IsA("BasePart") then rootPart.AssemblyLinearVelocity else Vector3.zero
	character:PivotTo(targetCFrame)

	if rootPart and rootPart:IsA("BasePart") then
		rootPart.AssemblyLinearVelocity = linearVelocity
		rootPart.AssemblyAngularVelocity = Vector3.zero
	end

	return {
		ok = true,
		message = "Teleported to the merchant.",
		shopState = shopState,
	}
end

function MerchantShopService:GetShopState(player: Player)
	return response(true, "Loaded merchant shop state.", self:_resolveCurrentState(player))
end

function MerchantShopService:PurchaseShopItem(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Purchase payload must be a table.", self:_resolveCurrentState(player))
	end

	local entry = MerchantShopConfig.GetByPotionId(payload.potionId)
	if not entry then
		return response(false, "That item is not sold here.", self:_resolveCurrentState(player))
	end

	local potionConfig = PotionConfig.Get(entry.potionId)
	if not potionConfig then
		return response(false, "That potion is not configured.", self:_resolveCurrentState(player))
	end

	local resolvedState = self:_resolveCurrentState(player)
	if not resolvedState.isActive then
		return response(false, "The merchant isn't here right now.", resolvedState)
	end

	local maxStock = MerchantShopConfig.GetMaxStockForPotionId(entry.potionId)
	local availableStock = math.clamp(normalizeQuantity(resolvedState.stockByPotionId[entry.potionId]), 0, maxStock)
	if availableStock <= 0 then
		return response(false, string.format("%s is out of stock.", entry.shopLabel), resolvedState)
	end

	local quantity = normalizeQuantity(payload.quantity)
	if quantity <= 0 then
		return response(false, "Enter a valid purchase amount.", resolvedState)
	end
	if quantity > availableStock then
		return response(false, string.format("Only %d %s remain in stock.", availableStock, entry.shopLabel), resolvedState)
	end

	local totalPrice = MerchantShopConfig.GetPriceInTimeShards(entry.potionId) * quantity
	if not self:_getAffordability(player, totalPrice) then
		return response(
			false,
			string.format("You need %s Time Shards to buy that.", Globals.formatNumber(totalPrice)),
			resolvedState
		)
	end

	local previousBalance = DataService:GetTimeShardsBalance(player)
	local updatedBalance = DataService:AdjustTimeShardsBalance(player, -totalPrice, "merchant_shop_purchase")
	if updatedBalance > previousBalance then
		return response(false, "Could not process that purchase.", resolvedState)
	end

	local grantCallOk, potionGrantSucceeded, potionGrantMessage = pcall(function()
		return PotionService:GrantPotionUses(player, entry.potionId, quantity)
	end)
	if not grantCallOk then
		DataService:AdjustTimeShardsBalance(player, totalPrice, "merchant_shop_purchase_refund")
		return response(false, potionGrantSucceeded or "Could not grant those potion uses.", resolvedState)
	elseif not potionGrantSucceeded then
		DataService:AdjustTimeShardsBalance(player, totalPrice, "merchant_shop_purchase_refund")
		return response(false, potionGrantMessage or "Could not grant those potion uses.", resolvedState)
	end

	local nextState = {
		windowId = resolvedState.windowId,
		stockByPotionId = MerchantShopState.CloneStockByPotionId(resolvedState.stockByPotionId),
	}
	nextState.stockByPotionId[entry.potionId] = math.clamp(availableStock - quantity, 0, maxStock)
	nextState = self:_saveState(player, nextState)

	local successMessage = string.format(
		"Purchased %d %s for %s Time Shards.",
		quantity,
		entry.shopLabel,
		Globals.formatNumber(totalPrice)
	)
	return response(true, successMessage, MerchantShopState.CloneState({
		windowId = resolvedState.windowId,
		isActive = true,
		appearsAt = resolvedState.appearsAt,
		departsAt = resolvedState.departsAt,
		nextAppearsAt = resolvedState.nextAppearsAt,
		stockByPotionId = nextState.stockByPotionId,
	}))
end

function MerchantShopService:ForceAppear(durationSeconds: number?): MerchantShopState.MerchantShopStateValue
	local now = getUtcNowSeconds()
	local resolvedDuration = math.max(1, math.floor(tonumber(durationSeconds) or WINDOW_ACTIVE_DURATION_SECONDS))
	self._forcedActiveUntil = math.max(self._forcedActiveUntil or 0, now + resolvedDuration)
	return self:_reconcileWindowState()
end

function MerchantShopService:OnStart()
	if self._started then
		return
	end

	self._started = true
	getShopStateRemote = ensureRemoteFunction(getShopStateRemote, GET_SHOP_STATE_REMOTE_NAME)
	purchaseShopItemRemote = ensureRemoteFunction(purchaseShopItemRemote, PURCHASE_SHOP_ITEM_REMOTE_NAME)
	availabilityChangedRemote = ensureRemoteEvent(availabilityChangedRemote, AVAILABILITY_CHANGED_REMOTE_NAME)
	teleportToMerchantRemote = ensureRemoteFunction(teleportToMerchantRemote, TELEPORT_TO_MERCHANT_REMOTE_NAME)

	getShopStateRemote.OnServerInvoke = function(player: Player)
		local allowed = RequestLimiter:Allow(player, "remote.merchant.get_state")
		if not allowed then
			return response(false, "You're refreshing the merchant too quickly.", self:_resolveCurrentState(player))
		end

		return self:GetShopState(player)
	end

	purchaseShopItemRemote.OnServerInvoke = function(player: Player, payload: any)
		local allowed = RequestLimiter:Allow(player, "remote.merchant.purchase")
		if not allowed then
			return response(false, "You're buying from the merchant too quickly.", self:_resolveCurrentState(player))
		end

		return self:PurchaseShopItem(player, payload)
	end

	teleportToMerchantRemote.OnServerInvoke = function(player: Player)
		local allowed = RequestLimiter:Allow(player, "remote.merchant.teleport")
		if not allowed then
			return {
				ok = false,
				message = "You're teleporting to the merchant too quickly.",
				shopState = self:_resolveCurrentState(player),
			}
		end

		return self:TeleportToMerchant(player)
	end

	self:_reconcileWindowState()

	task.spawn(function()
		while true do
			self:_reconcileWindowState()
			task.wait(1)
		end
	end)
end

return MerchantShopService
