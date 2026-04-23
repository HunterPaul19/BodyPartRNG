local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BossArenaRuntimeService = require(script.Parent.BossArenaRuntimeService)
local BossAnimationController = require(script.Parent.Common.BossAnimationController)
local BossArenaMovePresentationRelay = require(script.Parent.Common.BossArenaMovePresentationRelay)
local RequestLimiter = require(script.Parent.Common.RequestLimiter)
local BossEncounterScaling = require(ReplicatedStorage.Shared.BossArena.EncounterScaling)
local Bosses = require(ReplicatedStorage.Shared.Bosses)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local ACTIVE_PROFILE_ID = "boss_arena"
local REMOTES_FOLDER_NAME = "Remotes"
local BOSS_ARENA_FOLDER_NAME = "BossArena"
local START_REMOTE_NAME = "StartStudioTestSuite"
local GET_STATE_REMOTE_NAME = "GetStudioTestSuiteState"
local RUN_MOVE_REMOTE_NAME = "RunStudioTestSuiteMove"
local RESET_REMOTE_NAME = "ResetStudioTestSuite"
local TELEPORT_REMOTE_NAME = "TeleportStudioTestSuitePlayer"
local STATE_CHANGED_REMOTE_NAME = "StudioTestSuiteStateChanged"
local GAME_ASSETS_FOLDER_NAME = "GameAssets"
local BOSSES_FOLDER_NAME = "Bosses"
local SUITE_FOLDER_NAME = "BossArenaTestSuite"
local BOSSES_CONTAINER_NAME = "Bosses"
local BASEPLATE_NAME = "Baseplate"
local PLAYER_WALK_SPEED = 80
local RESET_PLAYER_WALK_SPEED = 16
local BASEPLATE_SIZE = Vector3.new(700, 2, 700)
local GRID_SPACING = 145
local TELEPORT_DISTANCE_FROM_BOSS = 38
local TELEPORT_HEIGHT_OFFSET = 8
local BOSS_ID_ATTRIBUTE_NAME = "StudioTestSuiteBossId"
local HOME_CFRAME_ATTRIBUTE_NAME = "StudioTestSuiteHomeCFrame"
local GET_STATE_RATE_LIMIT_KEY = "remote.boss_arena_test_suite.get_state"
local START_RATE_LIMIT_KEY = "remote.boss_arena_test_suite.start"
local RUN_MOVE_RATE_LIMIT_KEY = "remote.boss_arena_test_suite.run_move"
local RESET_RATE_LIMIT_KEY = "remote.boss_arena_test_suite.reset"
local TELEPORT_RATE_LIMIT_KEY = "remote.boss_arena_test_suite.teleport"

type TestSuiteMoveEntry = {
	id: string,
	displayName: string,
	moduleId: string,
	tags: { string },
}

type TestSuiteBossState = {
	id: string,
	displayName: string,
	castingMoveId: string?,
	moves: { TestSuiteMoveEntry },
}

type TestSuiteState = {
	enabled: boolean,
	active: boolean,
	message: string?,
	bosses: { TestSuiteBossState },
}

type ActiveCast = {
	castId: string,
	move: any,
	lifecycleHandle: any?,
	startedAt: number,
	recoveryEndsAt: number,
	completedAt: number?,
}

type BossRecord = {
	bossId: string,
	definition: any,
	bossModel: Model,
	bossHumanoid: Humanoid,
	bossRootPart: BasePart,
	homeCFrame: CFrame,
	floorRaycastRoots: { Instance },
	animationController: any?,
	activeCast: ActiveCast?,
}

local remotesFolder: Folder? = nil
local bossArenaFolder: Folder? = nil
local startRemote: RemoteFunction? = nil
local getStateRemote: RemoteFunction? = nil
local runMoveRemote: RemoteFunction? = nil
local resetRemote: RemoteFunction? = nil
local teleportRemote: RemoteFunction? = nil
local stateChangedRemote: RemoteEvent? = nil

local BossArenaStudioTestSuiteService = {
	_started = false,
	_heartbeatConnection = nil :: RBXScriptConnection?,
	_rootFolder = nil :: Folder?,
	_bossRecords = {} :: { [string]: BossRecord },
	_bossOrder = {} :: { string },
	_movePresentationListeners = {} :: { [(any) -> ()]: boolean },
	_characterConnections = {} :: { [Player]: RBXScriptConnection },
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID and RunService:IsStudio()
end

local function warnWithPrefix(message: string)
	warn(string.format("[BossArenaStudioTestSuiteService] %s", message))
end

local function response(ok: boolean, code: string, message: string, state: TestSuiteState?): { [string]: any }
	return {
		ok = ok,
		code = code,
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

local function ensureBossArenaFolder(): Folder
	local folder = ensureRemotesFolder()
	if bossArenaFolder and bossArenaFolder.Parent == folder then
		return bossArenaFolder
	end

	local existing = folder:FindFirstChild(BOSS_ARENA_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		bossArenaFolder = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local created = Instance.new("Folder")
	created.Name = BOSS_ARENA_FOLDER_NAME
	created.Parent = folder
	bossArenaFolder = created
	return created
end

local function ensureRemoteFunction(remoteName: string, cachedRemote: RemoteFunction?): RemoteFunction
	local folder = ensureBossArenaFolder()
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

local function ensureStateChangedRemote(): RemoteEvent
	local folder = ensureBossArenaFolder()
	if stateChangedRemote and stateChangedRemote.Parent == folder then
		return stateChangedRemote
	end

	local existing = folder:FindFirstChild(STATE_CHANGED_REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		stateChangedRemote = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = STATE_CHANGED_REMOTE_NAME
	remote.Parent = folder
	stateChangedRemote = remote
	return remote
end

local function normalizeString(value: any): string
	if typeof(value) ~= "string" then
		return ""
	end

	local trimmed = string.match(value, "%S.*")
	return trimmed or ""
end

local function getCharacterHumanoid(character: Model?): Humanoid?
	if character == nil then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end

	return nil
end

local function getModelRootPart(model: Model?): BasePart?
	if model == nil then
		return nil
	end

	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	local primaryPart = model.PrimaryPart
	if primaryPart then
		return primaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function getStandingHeight(humanoid: Humanoid, rootPart: BasePart): number
	return math.max((rootPart.Size.Y * 0.5) + humanoid.HipHeight, rootPart.Size.Y)
end

local function setServerNetworkOwnership(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Anchored == false then
			pcall(function()
				descendant:SetNetworkOwner(nil)
			end)
		end
	end
end

local function invokeLifecycleCancel(moveId: string, lifecycleHandle: any?)
	if typeof(lifecycleHandle) ~= "table" or typeof(lifecycleHandle.Cancel) ~= "function" then
		return
	end

	local ok, err = pcall(lifecycleHandle.Cancel)
	if not ok then
		warnWithPrefix(string.format("Boss move '%s' cancel failed: %s", moveId, tostring(err)))
	end
end

local function invokeLifecycleIsComplete(moveId: string, lifecycleHandle: any?): boolean
	if typeof(lifecycleHandle) ~= "table" or typeof(lifecycleHandle.IsComplete) ~= "function" then
		return true
	end

	local ok, isComplete = pcall(lifecycleHandle.IsComplete)
	if not ok then
		warnWithPrefix(string.format("Boss move '%s' IsComplete failed: %s", moveId, tostring(isComplete)))
		return true
	end

	return isComplete == true
end

local function invokeLifecycleRecoveryEndsAt(moveId: string, lifecycleHandle: any?): number?
	if typeof(lifecycleHandle) ~= "table" or typeof(lifecycleHandle.GetRecoveryEndsAt) ~= "function" then
		return nil
	end

	local ok, recoveryEndsAt = pcall(lifecycleHandle.GetRecoveryEndsAt)
	if not ok then
		warnWithPrefix(string.format("Boss move '%s' GetRecoveryEndsAt failed: %s", moveId, tostring(recoveryEndsAt)))
		return nil
	end

	local resolvedRecoveryEndsAt = tonumber(recoveryEndsAt)
	if resolvedRecoveryEndsAt == nil then
		return nil
	end

	return resolvedRecoveryEndsAt
end

local function getBossesFolder(): Folder
	local gameAssets = ReplicatedStorage:FindFirstChild(GAME_ASSETS_FOLDER_NAME)
	if not (gameAssets and gameAssets:IsA("Folder")) then
		error(string.format("[BossArenaStudioTestSuiteService] Missing ReplicatedStorage.%s.", GAME_ASSETS_FOLDER_NAME), 0)
	end

	local bossesFolder = gameAssets:FindFirstChild(BOSSES_FOLDER_NAME)
	if not (bossesFolder and bossesFolder:IsA("Folder")) then
		error(string.format(
			"[BossArenaStudioTestSuiteService] Missing ReplicatedStorage.%s.%s.",
			GAME_ASSETS_FOLDER_NAME,
			BOSSES_FOLDER_NAME
		), 0)
	end

	return bossesFolder
end

local function collectMoveEntries(definition: any): { TestSuiteMoveEntry }
	local moves = {}

	for _, move in ipairs(definition.moves or {}) do
		table.insert(moves, {
			id = move.id,
			displayName = move.displayName or move.id,
			moduleId = move.moduleId,
			tags = table.clone(move.tags or {}),
		})
	end

	return moves
end

local function findMove(definition: any, moveId: string): any?
	for _, move in ipairs(definition.moves or {}) do
		if move.id == moveId then
			return move
		end
	end

	return nil
end

local function collectSortedBossDefinitions(): { any }
	local definitions = Bosses.GetAll()
	table.sort(definitions, function(left, right)
		if left.displayName == right.displayName then
			return left.bossId < right.bossId
		end

		return left.displayName < right.displayName
	end)

	return definitions
end

local function computeGridPosition(index: number, count: number): Vector3
	local columns = math.max(1, math.ceil(math.sqrt(count)))
	local rows = math.max(1, math.ceil(count / columns))
	local column = (index - 1) % columns
	local row = math.floor((index - 1) / columns)
	local x = (column - ((columns - 1) * 0.5)) * GRID_SPACING
	local z = (row - ((rows - 1) * 0.5)) * GRID_SPACING

	return Vector3.new(x, 0, z)
end

local function buildMoveStubLog(record: BossRecord, move: any, context: any, debugPayload: any, targetingData: any)
	local serializedPayload = HttpService:JSONEncode({
		bossId = record.bossId,
		arenaId = "studio_test_suite",
		moveId = move.id,
		moduleId = move.moduleId,
		tags = move.tags,
		timestampUnix = os.time(),
		state = "StudioTestSuite",
		distanceToTarget = context.distanceToTarget,
		target = targetingData,
		debug = debugPayload,
	})

	print(string.format("[BossArenaStudioTestSuiteService] MoveStub %s", serializedPayload))
end

function BossArenaStudioTestSuiteService:_isActive(): boolean
	if self._rootFolder ~= nil and self._rootFolder.Parent == Workspace then
		if #self._bossOrder <= 0 then
			self:_rehydrateSuiteFromWorkspace()
		end
		return true
	end

	local existingRoot = Workspace:FindFirstChild(SUITE_FOLDER_NAME)
	if existingRoot and existingRoot:IsA("Folder") then
		self._rootFolder = existingRoot
		self:_rehydrateSuiteFromWorkspace()
		return true
	end

	return false
end

function BossArenaStudioTestSuiteService:_applyFastMovement(player: Player)
	if self:_isActive() ~= true then
		return
	end

	local humanoid = getCharacterHumanoid(player.Character)
	if humanoid == nil then
		return
	end

	humanoid.WalkSpeed = PLAYER_WALK_SPEED
end

function BossArenaStudioTestSuiteService:_restoreDefaultMovement(player: Player)
	local humanoid = getCharacterHumanoid(player.Character)
	if humanoid == nil then
		return
	end

	humanoid.WalkSpeed = RESET_PLAYER_WALK_SPEED
end

function BossArenaStudioTestSuiteService:_teleportPlayerToCFrame(player: Player, targetCFrame: CFrame): boolean
	local character = player.Character
	local humanoid = getCharacterHumanoid(character)
	local rootPart = getModelRootPart(character)
	if character == nil or humanoid == nil or rootPart == nil then
		return false
	end

	character:PivotTo(targetCFrame)
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
	self:_applyFastMovement(player)
	return true
end

function BossArenaStudioTestSuiteService:_teleportPlayerToCenter(player: Player)
	self:_teleportPlayerToCFrame(player, CFrame.new(0, 8, 0))
end

function BossArenaStudioTestSuiteService:_getTeleportCFrameForBoss(record: BossRecord): CFrame
	local bossPosition = record.homeCFrame.Position
	local forward = record.homeCFrame.LookVector
	local planarForward = Vector3.new(forward.X, 0, forward.Z)
	if planarForward.Magnitude <= 0.001 then
		planarForward = Vector3.new(0, 0, -1)
	else
		planarForward = planarForward.Unit
	end

	local targetPosition = bossPosition
		+ (planarForward * TELEPORT_DISTANCE_FROM_BOSS)
		+ Vector3.new(0, TELEPORT_HEIGHT_OFFSET, 0)
	local lookTarget = Vector3.new(bossPosition.X, targetPosition.Y, bossPosition.Z)
	if (lookTarget - targetPosition).Magnitude <= 0.001 then
		lookTarget = targetPosition + Vector3.new(0, 0, -1)
	end

	return CFrame.lookAt(targetPosition, lookTarget)
end

function BossArenaStudioTestSuiteService:_ensureRecordAnimationController(record: BossRecord)
	if record.animationController ~= nil then
		return
	end

	record.animationController = BossAnimationController.Attach(record.bossModel, record.bossHumanoid, {
		scaleMultiplier = record.definition.scaleMultiplier,
	})
end

function BossArenaStudioTestSuiteService:_rehydrateSuiteFromWorkspace()
	local rootFolder = self._rootFolder
	if rootFolder == nil or rootFolder.Parent ~= Workspace then
		local existingRoot = Workspace:FindFirstChild(SUITE_FOLDER_NAME)
		if not (existingRoot and existingRoot:IsA("Folder")) then
			return
		end

		rootFolder = existingRoot
		self._rootFolder = existingRoot
	end

	local bossesContainer = rootFolder:FindFirstChild(BOSSES_CONTAINER_NAME)
	if not (bossesContainer and bossesContainer:IsA("Folder")) then
		return
	end

	table.clear(self._bossRecords)
	table.clear(self._bossOrder)

	local definitionsById = {}
	for _, definition in ipairs(Bosses.GetAll()) do
		definitionsById[definition.bossId] = definition
	end

	local rehydratedRecords = {}
	for _, child in ipairs(bossesContainer:GetChildren()) do
		if not child:IsA("Model") then
			continue
		end

		local bossId = normalizeString(child:GetAttribute(BOSS_ID_ATTRIBUTE_NAME))
		if bossId == "" then
			bossId = child.Name
		end

		local definition = definitionsById[bossId]
		local humanoid = child:FindFirstChildOfClass("Humanoid")
		local rootPart = getModelRootPart(child)
		local homeCFrame = child:GetAttribute(HOME_CFRAME_ATTRIBUTE_NAME)
		if definition == nil or humanoid == nil or rootPart == nil or typeof(homeCFrame) ~= "CFrame" then
			continue
		end

		humanoid.WalkSpeed = 0
		humanoid.AutoRotate = false
		setServerNetworkOwnership(child)

		table.insert(rehydratedRecords, {
			bossId = definition.bossId,
			definition = definition,
			bossModel = child,
			bossHumanoid = humanoid,
			bossRootPart = rootPart,
			homeCFrame = homeCFrame,
			animationController = nil,
			activeCast = nil,
		})
	end

	table.sort(rehydratedRecords, function(left, right)
		if left.definition.displayName == right.definition.displayName then
			return left.bossId < right.bossId
		end

		return left.definition.displayName < right.definition.displayName
	end)

	for _, record in ipairs(rehydratedRecords) do
		self._bossRecords[record.bossId] = record
		table.insert(self._bossOrder, record.bossId)
	end
end

function BossArenaStudioTestSuiteService:_buildState(message: string?): TestSuiteState
	local bosses = {}

	for _, bossId in ipairs(self._bossOrder) do
		local record = self._bossRecords[bossId]
		if record == nil then
			continue
		end

		table.insert(bosses, {
			id = record.bossId,
			displayName = record.definition.displayName,
			castingMoveId = if record.activeCast then record.activeCast.move.id else nil,
			moves = collectMoveEntries(record.definition),
		})
	end

	return {
		enabled = isEnabledForPlace(),
		active = self:_isActive(),
		message = message,
		bosses = bosses,
	}
end

function BossArenaStudioTestSuiteService:_broadcastStateChanged(message: string?)
	local state = self:_buildState(message)
	local remote = ensureStateChangedRemote()

	for _, player in ipairs(Players:GetPlayers()) do
		remote:FireClient(player, state)
	end
end

function BossArenaStudioTestSuiteService:_notifyMovePresentation(payload: any)
	if typeof(payload) == "table" then
		payload.source = "studio_test_suite"
	end

	BossArenaMovePresentationRelay.FireAllClients(payload)

	for callback in pairs(self._movePresentationListeners) do
		local ok, err = pcall(callback, payload)
		if not ok then
			warnWithPrefix(string.format("Move presentation callback failed: %s", tostring(err)))
		end
	end
end

function BossArenaStudioTestSuiteService:_cancelRecordCast(record: BossRecord)
	local activeCast = record.activeCast
	if activeCast == nil then
		return
	end

	record.activeCast = nil
	invokeLifecycleCancel(activeCast.move.id, activeCast.lifecycleHandle)
	if record.animationController then
		record.animationController:SetLocomotionSuppressed(false)
	end
end

function BossArenaStudioTestSuiteService:_clearSuite()
	for _, record in pairs(self._bossRecords) do
		self:_cancelRecordCast(record)
		if record.animationController then
			record.animationController:Destroy()
		end
	end

	table.clear(self._bossRecords)
	table.clear(self._bossOrder)

	local rootFolder = self._rootFolder
	self._rootFolder = nil

	if rootFolder and rootFolder.Parent ~= nil then
		rootFolder:Destroy()
	end

	local lingering = Workspace:FindFirstChild(SUITE_FOLDER_NAME)
	if lingering then
		lingering:Destroy()
	end
end

function BossArenaStudioTestSuiteService:_spawnBaseplate(rootFolder: Folder)
	local baseplate = Instance.new("Part")
	baseplate.Name = BASEPLATE_NAME
	baseplate.Anchored = true
	baseplate.CanCollide = true
	baseplate.Size = BASEPLATE_SIZE
	baseplate.CFrame = CFrame.new(0, -BASEPLATE_SIZE.Y * 0.5, 0)
	baseplate.Material = Enum.Material.SmoothPlastic
	baseplate.Color = Color3.fromRGB(88, 93, 102)
	baseplate.TopSurface = Enum.SurfaceType.Smooth
	baseplate.BottomSurface = Enum.SurfaceType.Smooth
	baseplate.Parent = rootFolder
end

function BossArenaStudioTestSuiteService:_spawnBossGrid(rootFolder: Folder)
	local bossesContainer = Instance.new("Folder")
	bossesContainer.Name = BOSSES_CONTAINER_NAME
	bossesContainer.Parent = rootFolder

	local sourceBossesFolder = getBossesFolder()
	local definitions = collectSortedBossDefinitions()

	for index, definition in ipairs(definitions) do
		local sourceBossModel = sourceBossesFolder:FindFirstChild(definition.bossId)
		if not (sourceBossModel and sourceBossModel:IsA("Model")) then
			warnWithPrefix(string.format("Missing boss model '%s' under ReplicatedStorage.GameAssets.Bosses.", definition.bossId))
			continue
		end

		local bossModel = sourceBossModel:Clone()
		bossModel.Name = definition.bossId

		if definition.scaleMultiplier ~= 1 then
			local scaleOk, scaleError = pcall(function()
				bossModel:ScaleTo(definition.scaleMultiplier)
			end)
			if not scaleOk then
				warnWithPrefix(string.format(
					"Failed to scale boss '%s' to %.2fx: %s",
					definition.bossId,
					definition.scaleMultiplier,
					tostring(scaleError)
				))
			end
		end

		local bossHumanoid = bossModel:FindFirstChildOfClass("Humanoid")
		local bossRootPart = getModelRootPart(bossModel)
		if bossHumanoid == nil or bossRootPart == nil then
			warnWithPrefix(string.format("Boss model '%s' must contain a Humanoid and root BasePart.", definition.bossId))
			bossModel:Destroy()
			continue
		end

		local gridPosition = computeGridPosition(index, #definitions)
		local standingHeight = getStandingHeight(bossHumanoid, bossRootPart)
		local homePosition = gridPosition + Vector3.new(0, standingHeight, 0)
		local lookTarget = Vector3.new(0, homePosition.Y, 0)
		if (lookTarget - homePosition).Magnitude <= 0.001 then
			lookTarget = homePosition + Vector3.new(0, 0, 1)
		end
		local homeCFrame = CFrame.lookAt(homePosition, lookTarget)

		bossHumanoid.MaxHealth = definition.baseHealth
		bossHumanoid.Health = definition.baseHealth
		bossHumanoid.WalkSpeed = 0
		bossHumanoid.AutoRotate = false
		bossModel:PivotTo(homeCFrame)
		bossModel:SetAttribute(BOSS_ID_ATTRIBUTE_NAME, definition.bossId)
		bossModel:SetAttribute(HOME_CFRAME_ATTRIBUTE_NAME, homeCFrame)
		bossModel.Parent = bossesContainer
		setServerNetworkOwnership(bossModel)

		local animationController = BossAnimationController.Attach(bossModel, bossHumanoid, {
			scaleMultiplier = definition.scaleMultiplier,
		})

		self._bossRecords[definition.bossId] = {
			bossId = definition.bossId,
			definition = definition,
			bossModel = bossModel,
			bossHumanoid = bossHumanoid,
			bossRootPart = bossRootPart,
			homeCFrame = homeCFrame,
			floorRaycastRoots = { rootFolder:WaitForChild(BASEPLATE_NAME) },
			animationController = animationController,
			activeCast = nil,
		}
		table.insert(self._bossOrder, definition.bossId)
	end
end

function BossArenaStudioTestSuiteService:_collectAliveTargets(record: BossRecord)
	local aliveTargets = {}

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = getCharacterHumanoid(character)
		local rootPart = getModelRootPart(character)
		if character == nil or humanoid == nil or rootPart == nil then
			continue
		end

		table.insert(aliveTargets, {
			player = player,
			character = character,
			humanoid = humanoid,
			rootPart = rootPart,
			distanceToBoss = (rootPart.Position - record.bossRootPart.Position).Magnitude,
			distanceToHome = (rootPart.Position - record.homeCFrame.Position).Magnitude,
		})
	end

	table.sort(aliveTargets, function(left, right)
		if left.distanceToBoss == right.distanceToBoss then
			return left.player.UserId < right.player.UserId
		end

		return left.distanceToBoss < right.distanceToBoss
	end)

	return aliveTargets
end

function BossArenaStudioTestSuiteService:_resolveTarget(player: Player, aliveTargets: { any })
	for _, target in ipairs(aliveTargets) do
		if target.player == player then
			return target
		end
	end

	return aliveTargets[1]
end

function BossArenaStudioTestSuiteService:_buildMoveContext(record: BossRecord, move: any, target: any?, aliveTargets: { any }, castId: string)
	local function emitPresentation(action: string, payload: { [string]: any }?)
		self:_notifyMovePresentation({
			castId = castId,
			bossModel = record.bossModel,
			bossId = record.bossId,
			moveId = move.id,
			moduleId = move.moduleId,
			action = action,
			payload = payload,
			serverTime = Workspace:GetServerTimeNow(),
		})
	end

	return {
		now = os.clock(),
		castId = castId,
		bossDefinition = record.definition,
		encounterScaling = BossEncounterScaling.GetForPartySize(1),
		move = move,
		bossModel = record.bossModel,
		bossHumanoid = record.bossHumanoid,
		bossRootPart = record.bossRootPart,
		bossState = "StudioTestSuite",
		homePosition = record.homeCFrame.Position,
		floorRaycastRoots = record.floorRaycastRoots,
		targetPlayer = if target then target.player else nil,
		targetCharacter = if target then target.character else nil,
		targetHumanoid = if target then target.humanoid else nil,
		targetRootPart = if target then target.rootPart else nil,
		distanceToTarget = if target then target.distanceToBoss else nil,
		aliveTargets = aliveTargets,
		EmitPresentation = emitPresentation,
	}
end

function BossArenaStudioTestSuiteService:_faceTarget(record: BossRecord, target: any?)
	if target == nil or target.rootPart == nil or target.rootPart.Parent == nil then
		record.bossModel:PivotTo(record.homeCFrame)
		return
	end

	local position = record.homeCFrame.Position
	local targetPosition = target.rootPart.Position
	local lookTarget = Vector3.new(targetPosition.X, position.Y, targetPosition.Z)
	if (lookTarget - position).Magnitude <= 0.001 then
		record.bossModel:PivotTo(record.homeCFrame)
		return
	end

	record.bossModel:PivotTo(CFrame.lookAt(position, lookTarget))
	record.bossRootPart.AssemblyLinearVelocity = Vector3.zero
	record.bossRootPart.AssemblyAngularVelocity = Vector3.zero
end

function BossArenaStudioTestSuiteService:_finishCast(record: BossRecord)
	record.activeCast = nil
	record.bossHumanoid.WalkSpeed = 0
	record.bossHumanoid.AutoRotate = false
	record.bossModel:PivotTo(record.homeCFrame)
	record.bossRootPart.AssemblyLinearVelocity = Vector3.zero
	record.bossRootPart.AssemblyAngularVelocity = Vector3.zero

	if record.animationController then
		record.animationController:SetLocomotionSuppressed(false)
	end

	self:_broadcastStateChanged(nil)
end

function BossArenaStudioTestSuiteService:_executeMoveStub(record: BossRecord, move: any, context: any)
	local targetingOk, targetingData = pcall(function()
		return move.module.GetTargeting(context)
	end)
	if not targetingOk then
		warnWithPrefix(string.format("Boss move '%s' GetTargeting failed: %s", move.id, tostring(targetingData)))
		targetingData = {
			mode = "unknown",
			summary = "targeting error",
		}
	end

	local executeOk, debugPayload = pcall(function()
		return move.module.ExecuteStub(context)
	end)
	if not executeOk then
		warnWithPrefix(string.format("Boss move '%s' ExecuteStub failed: %s", move.id, tostring(debugPayload)))
		debugPayload = {
			error = tostring(debugPayload),
		}
	end

	buildMoveStubLog(record, move, context, debugPayload, targetingData)
end

function BossArenaStudioTestSuiteService:_runMove(player: Player, bossId: string, moveId: string): (boolean, string?)
	if self:_isActive() ~= true then
		return false, "The Studio test suite is not active."
	end

	local record = self._bossRecords[bossId]
	if record == nil then
		return false, string.format("Unknown test suite boss '%s'.", bossId)
	end
	if record.activeCast ~= nil then
		return false, string.format("Boss '%s' is already casting.", record.definition.displayName)
	end

	local move = findMove(record.definition, moveId)
	if move == nil then
		return false, string.format("Unknown move '%s' for boss '%s'.", moveId, bossId)
	end
	if record.bossModel.Parent == nil or record.bossRootPart.Parent == nil or record.bossHumanoid.Parent == nil then
		return false, string.format("Boss '%s' is no longer available.", bossId)
	end
	if record.bossHumanoid.Health <= 0 then
		record.bossHumanoid.Health = math.max(1, record.bossHumanoid.MaxHealth)
	end
	self:_ensureRecordAnimationController(record)

	local aliveTargets = self:_collectAliveTargets(record)
	local target = self:_resolveTarget(player, aliveTargets)
	self:_faceTarget(record, target)

	local castId = HttpService:GenerateGUID(false)
	local context = self:_buildMoveContext(record, move, target, aliveTargets, castId)
	local startCast = move.module.StartCast

	if typeof(startCast) ~= "function" then
		self:_executeMoveStub(record, move, context)
		return true, nil
	end

	if record.animationController then
		record.animationController:SetLocomotionSuppressed(true)
	end

	local startOk, lifecycleHandleOrError = pcall(startCast, context)
	if not startOk then
		if record.animationController then
			record.animationController:SetLocomotionSuppressed(false)
		end
		return false, string.format("Boss move '%s' StartCast failed: %s", move.id, tostring(lifecycleHandleOrError))
	end

	record.activeCast = {
		castId = castId,
		move = move,
		lifecycleHandle = if typeof(lifecycleHandleOrError) == "table" then lifecycleHandleOrError else nil,
		startedAt = os.clock(),
		recoveryEndsAt = os.clock() + math.max(0, tonumber(move.castTimeSeconds) or 0) + math.max(0, tonumber(move.recoverySeconds) or 0),
		completedAt = nil,
	}

	self:_broadcastStateChanged(nil)
	return true, nil
end

function BossArenaStudioTestSuiteService:_updateCast(record: BossRecord)
	local activeCast = record.activeCast
	if activeCast == nil then
		return
	end

	local now = os.clock()
	local lifecycleHandle = activeCast.lifecycleHandle

	if lifecycleHandle ~= nil then
		if activeCast.completedAt == nil then
			if not invokeLifecycleIsComplete(activeCast.move.id, lifecycleHandle) then
				return
			end

			activeCast.completedAt = now
			local recoveryEndsAt = invokeLifecycleRecoveryEndsAt(activeCast.move.id, lifecycleHandle)
			activeCast.recoveryEndsAt = recoveryEndsAt or (now + math.max(0, tonumber(activeCast.move.recoverySeconds) or 0))
		end

		if now >= activeCast.recoveryEndsAt then
			self:_finishCast(record)
		end
		return
	end

	if now >= activeCast.recoveryEndsAt then
		self:_finishCast(record)
	end
end

function BossArenaStudioTestSuiteService:_heartbeat()
	if self:_isActive() ~= true then
		return
	end

	for _, bossId in ipairs(self._bossOrder) do
		local record = self._bossRecords[bossId]
		if record == nil then
			continue
		end
		if record.bossModel.Parent == nil or record.bossHumanoid.Parent == nil or record.bossRootPart.Parent == nil then
			continue
		end

		self:_ensureRecordAnimationController(record)
		record.bossHumanoid.WalkSpeed = 0
		if record.activeCast == nil then
			record.bossRootPart.AssemblyLinearVelocity = Vector3.zero
			record.bossRootPart.AssemblyAngularVelocity = Vector3.zero
		end
		self:_updateCast(record)
	end
end

function BossArenaStudioTestSuiteService:StartStudioTestSuiteFromPlayer(player: Player?): (boolean, string?)
	if not isEnabledForPlace() then
		return false, "Boss arena test suite is only available in Studio boss arena places."
	end
	if BossArenaRuntimeService:HasActiveEncounter() then
		return false, "A normal boss encounter is already active."
	end
	if self:_isActive() then
		if player then
			self:_teleportPlayerToCenter(player)
		end
		return true, nil
	end

	local spawnOk, spawnError = xpcall(function()
		self:_clearSuite()

		local rootFolder = Instance.new("Folder")
		rootFolder.Name = SUITE_FOLDER_NAME
		rootFolder.Parent = Workspace
		self._rootFolder = rootFolder

		self:_spawnBaseplate(rootFolder)
		self:_spawnBossGrid(rootFolder)

		for _, existingPlayer in ipairs(Players:GetPlayers()) do
			self:_applyFastMovement(existingPlayer)
			self:_teleportPlayerToCenter(existingPlayer)
		end
	end, debug.traceback)

	if not spawnOk then
		self:_clearSuite()
		return false, tostring(spawnError)
	end

	self:_broadcastStateChanged("Studio boss test suite started.")
	print("[BossArenaStudioTestSuiteService] Started Studio boss test suite.")
	return true, nil
end

function BossArenaStudioTestSuiteService:ResetStudioTestSuite(player: Player?): (boolean, string?)
	if not isEnabledForPlace() then
		return false, "Boss arena test suite is unavailable here."
	end

	self:_clearSuite()
	local ok, err = self:StartStudioTestSuiteFromPlayer(player)
	if ok then
		self:_broadcastStateChanged("Studio boss test suite reset.")
	end
	return ok, err
end

function BossArenaStudioTestSuiteService:IsActive(): boolean
	return self:_isActive()
end

function BossArenaStudioTestSuiteService:GetState(message: string?): TestSuiteState
	return self:_buildState(message)
end

function BossArenaStudioTestSuiteService:ConnectMovePresentation(callback: (any) -> ()): () -> ()
	assert(type(callback) == "function", "Move presentation callback must be a function.")
	self._movePresentationListeners[callback] = true

	return function()
		self._movePresentationListeners[callback] = nil
	end
end

function BossArenaStudioTestSuiteService:OnStart()
	if self._started then
		return
	end
	self._started = true

	if not isEnabledForPlace() then
		return
	end

	startRemote = ensureRemoteFunction(START_REMOTE_NAME, startRemote)
	getStateRemote = ensureRemoteFunction(GET_STATE_REMOTE_NAME, getStateRemote)
	runMoveRemote = ensureRemoteFunction(RUN_MOVE_REMOTE_NAME, runMoveRemote)
	resetRemote = ensureRemoteFunction(RESET_REMOTE_NAME, resetRemote)
	teleportRemote = ensureRemoteFunction(TELEPORT_REMOTE_NAME, teleportRemote)
	ensureStateChangedRemote()
	BossArenaMovePresentationRelay.EnsureRemote()

	getStateRemote.OnServerInvoke = function(player: Player)
		if not RequestLimiter:Allow(player, GET_STATE_RATE_LIMIT_KEY) then
			return self:_buildState("Studio test suite state is being requested too quickly.")
		end

		return self:_buildState(nil)
	end

	startRemote.OnServerInvoke = function(player: Player)
		if not RequestLimiter:Allow(player, START_RATE_LIMIT_KEY) then
			return response(false, "RATE_LIMITED", "Test suite start is being requested too quickly.", self:_buildState(nil))
		end

		local ok, err = self:StartStudioTestSuiteFromPlayer(player)
		return response(ok, if ok then "OK" else "START_FAILED", err or "Started test suite.", self:_buildState(err))
	end

	runMoveRemote.OnServerInvoke = function(player: Player, request: any)
		if not RequestLimiter:Allow(player, RUN_MOVE_RATE_LIMIT_KEY) then
			return response(false, "RATE_LIMITED", "Move requests are being sent too quickly.", self:_buildState(nil))
		end
		if typeof(request) ~= "table" then
			return response(false, "BAD_REQUEST", "Move requests must be tables.", self:_buildState(nil))
		end

		local bossId = normalizeString(request.bossId)
		local moveId = normalizeString(request.moveId)
		if bossId == "" or moveId == "" then
			return response(false, "BAD_REQUEST", "A valid bossId and moveId are required.", self:_buildState(nil))
		end

		local ok, err = self:_runMove(player, bossId, moveId)
		return response(ok, if ok then "OK" else "MOVE_FAILED", err or "Move started.", self:_buildState(err))
	end

	resetRemote.OnServerInvoke = function(player: Player)
		if not RequestLimiter:Allow(player, RESET_RATE_LIMIT_KEY) then
			return response(false, "RATE_LIMITED", "Test suite reset is being requested too quickly.", self:_buildState(nil))
		end

		local ok, err = self:ResetStudioTestSuite(player)
		return response(ok, if ok then "OK" else "RESET_FAILED", err or "Test suite reset.", self:_buildState(err))
	end

	teleportRemote.OnServerInvoke = function(player: Player, request: any)
		if not RequestLimiter:Allow(player, TELEPORT_RATE_LIMIT_KEY) then
			return response(false, "RATE_LIMITED", "Teleport requests are being sent too quickly.", self:_buildState(nil))
		end
		if typeof(request) ~= "table" then
			return response(false, "BAD_REQUEST", "Teleport requests must be tables.", self:_buildState(nil))
		end

		local ok, result = xpcall(function()
			if self:_isActive() ~= true then
				local started, startError = self:StartStudioTestSuiteFromPlayer(player)
				if not started then
					return response(
						false,
						"START_FAILED",
						startError or "Could not restart the Studio test suite.",
						self:_buildState(startError)
					)
				end
			end

			local bossId = normalizeString(request.bossId)
			local record = self._bossRecords[bossId]
			if record == nil then
				self:_rehydrateSuiteFromWorkspace()
				record = self._bossRecords[bossId]
			end
			if record == nil then
				return response(false, "UNKNOWN_BOSS", string.format("Unknown test suite boss '%s'.", bossId), self:_buildState(nil))
			end
			if record.bossModel.Parent == nil or record.bossRootPart.Parent == nil then
				return response(false, "BOSS_UNAVAILABLE", string.format("Boss '%s' is no longer available.", record.definition.displayName), self:_buildState(nil))
			end

			local targetCFrame = self:_getTeleportCFrameForBoss(record)
			local teleported = self:_teleportPlayerToCFrame(player, targetCFrame)
			if not teleported then
				return response(false, "TELEPORT_FAILED", "Could not teleport your character. Respawn and try again.", self:_buildState(nil))
			end

			return response(true, "OK", "Teleported.", self:_buildState(nil))
		end, debug.traceback)

		if ok then
			return result
		end

		warnWithPrefix(string.format("Teleport request failed: %s", tostring(result)))
		return response(false, "TELEPORT_ERROR", "Teleport failed; see server output for details.", self:_buildState(nil))
	end

	self._heartbeatConnection = RunService.Heartbeat:Connect(function()
		self:_heartbeat()
	end)

	print("[BossArenaStudioTestSuiteService] Ready for Studio boss test suite.")
end

function BossArenaStudioTestSuiteService:OnPlayerAdded(player: Player)
	if not isEnabledForPlace() then
		return
	end

	local existingConnection = self._characterConnections[player]
	if existingConnection then
		existingConnection:Disconnect()
	end

	self._characterConnections[player] = player.CharacterAdded:Connect(function()
		task.defer(function()
			self:_applyFastMovement(player)
		end)
	end)

	task.defer(function()
		if player.Parent == Players then
			self:_applyFastMovement(player)
			ensureStateChangedRemote():FireClient(player, self:_buildState(nil))
		end
	end)
end

function BossArenaStudioTestSuiteService:OnPlayerRemoving(player: Player)
	local connection = self._characterConnections[player]
	if connection then
		connection:Disconnect()
		self._characterConnections[player] = nil
	end
end

return BossArenaStudioTestSuiteService
