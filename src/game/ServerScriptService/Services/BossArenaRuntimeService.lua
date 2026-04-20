local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BossArenaArrivalService = require(script.Parent.BossArenaArrivalService)
local BossAnimationController = require(script.Parent.Common.BossAnimationController)
local BossArenas = require(ReplicatedStorage.Shared.BossArenas)
local BossQueueTeleportPayload = require(ReplicatedStorage.Shared.BossQueue.TeleportPayload)
local Bosses = require(ReplicatedStorage.Shared.Bosses)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local ACTIVE_PROFILE_ID = "boss_arena"
local GAME_ASSETS_FOLDER_NAME = "GameAssets"
local BOSSES_FOLDER_NAME = "Bosses"
local BOSS_ARENAS_FOLDER_NAME = "BossArenas"
local ARENA_LIGHTING_FOLDER_NAME = "ArenaLighting"
local ACTIVE_BOSS_MODEL_NAME = "ActiveBoss"
local ACTIVE_ARENA_MODEL_NAME = "ActiveBossArena"
local AGGRO_RADIUS_ATTRIBUTE_NAME = "BossAggroRadius"
local LEASH_RADIUS_ATTRIBUTE_NAME = "BossLeashRadius"
local PLAYER_SPAWN_VERTICAL_OFFSET = 4
local PLAYER_SPAWN_RING_SIZE = 6
local PLAYER_SPAWN_RING_RADIUS = 8

type CastState = {
	move: any,
	startedAt: number,
	executeAt: number,
	recoveryEndsAt: number,
	rootDuringCast: boolean,
	executed: boolean,
	targetUserId: number?,
}

type BossHealthState = {
	bossId: string,
	currentHealth: number,
	maxHealth: number,
}

type EncounterState = {
	payload: any,
	bossId: string,
	arenaId: string,
	bossDefinition: any,
	arenaDefinition: any,
	arenaModel: Model,
	bossModel: Model,
	bossHumanoid: Humanoid,
	bossRootPart: BasePart,
	animationController: any,
	bossSpawn: BasePart,
	playerSpawns: { BasePart },
	appliedLightingInstances: { Instance },
	homePosition: Vector3,
	aggroRadius: number,
	leashRadius: number,
	rosterUserIds: { [number]: boolean },
	rosterOrder: { number },
	placedCharacters: { [number]: Model? },
	state: string,
	currentTargetUserId: number?,
	lastRetargetAt: number,
	lastMoveCommandAt: number,
	lastAbilityStartedAt: number,
	cooldowns: { [string]: number },
	rng: Random,
	spawnedAt: number,
	activeCast: CastState?,
	bossHealthConnections: { RBXScriptConnection },
}

type AliveTargetContext = {
	player: Player,
	character: Model,
	humanoid: Humanoid,
	rootPart: BasePart,
	distanceToBoss: number,
	distanceToHome: number,
}

local BossArenaRuntimeService = {
	_started = false,
	_heartbeatConnection = nil :: RBXScriptConnection?,
	_encounter = nil :: EncounterState?,
	_encounterStateListeners = {} :: { [(string?) -> ()]: boolean },
	_bossHealthStateListeners = {} :: { [(BossHealthState?) -> ()]: boolean },
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
end

local function warnWithPrefix(message: string)
	warn(string.format("[BossArenaRuntimeService] %s", message))
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

local function getModelRootPart(model: Model): BasePart?
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

local function readPositiveAttribute(instance: Instance?, attributeName: string): number?
	if instance == nil then
		return nil
	end

	local value = tonumber(instance:GetAttribute(attributeName))
	if value == nil or value <= 0 then
		return nil
	end

	return value
end

local function disconnectConnections(connections: { RBXScriptConnection })
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	table.clear(connections)
end

local function buildRosterUserIdSet(payload: any): { [number]: boolean }
	local rosterUserIds = {}

	if typeof(payload) ~= "table" or typeof(payload.queuedUserIds) ~= "table" then
		return rosterUserIds
	end

	for _, userId in ipairs(payload.queuedUserIds) do
		local resolvedUserId = math.floor(tonumber(userId) or 0)
		if resolvedUserId > 0 then
			rosterUserIds[resolvedUserId] = true
		end
	end

	return rosterUserIds
end

local function chooseWeightedMove(validMoves: { { move: any, context: any } }, rng: Random)
	local totalWeight = 0
	for _, entry in ipairs(validMoves) do
		totalWeight += math.max(0, tonumber(entry.move.weight) or 0)
	end

	if totalWeight <= 0 then
		return validMoves[1]
	end

	local threshold = rng:NextNumber(0, totalWeight)
	local accumulatedWeight = 0

	for _, entry in ipairs(validMoves) do
		accumulatedWeight += math.max(0, tonumber(entry.move.weight) or 0)
		if threshold <= accumulatedWeight then
			return entry
		end
	end

	return validMoves[#validMoves]
end

local function getPlayerByUserId(userId: number?): Player?
	if userId == nil then
		return nil
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if player.UserId == userId then
			return player
		end
	end

	return nil
end

local function buildSyntheticQueuedUserIds(requestingPlayer: Player?): { number }
	local queuedUserIds = {}
	local seenUserIds = {}

	for _, player in ipairs(Players:GetPlayers()) do
		if seenUserIds[player.UserId] ~= true then
			seenUserIds[player.UserId] = true
			table.insert(queuedUserIds, player.UserId)
		end
	end

	if requestingPlayer and seenUserIds[requestingPlayer.UserId] ~= true then
		table.insert(queuedUserIds, requestingPlayer.UserId)
	end

	return queuedUserIds
end

local function getGameAssetsFolder(): Folder
	local gameAssetsFolder = ReplicatedStorage:FindFirstChild(GAME_ASSETS_FOLDER_NAME)
	if gameAssetsFolder == nil or not gameAssetsFolder:IsA("Folder") then
		error(string.format(
			"[BossArenaRuntimeService] Missing ReplicatedStorage.%s in the boss arena place.",
			GAME_ASSETS_FOLDER_NAME
		), 0)
	end

	return gameAssetsFolder
end

local function getBossesFolder(): Folder
	local bossesFolder = getGameAssetsFolder():FindFirstChild(BOSSES_FOLDER_NAME)
	if bossesFolder == nil or not bossesFolder:IsA("Folder") then
		error(string.format(
			"[BossArenaRuntimeService] Missing ReplicatedStorage.%s.%s in the boss arena place.",
			GAME_ASSETS_FOLDER_NAME,
			BOSSES_FOLDER_NAME
		), 0)
	end

	return bossesFolder
end

local function getBossArenasFolder(): Folder
	local bossArenasFolder = getGameAssetsFolder():FindFirstChild(BOSS_ARENAS_FOLDER_NAME)
	if bossArenasFolder == nil or not bossArenasFolder:IsA("Folder") then
		error(string.format(
			"[BossArenaRuntimeService] Missing ReplicatedStorage.%s.%s in the boss arena place.",
			GAME_ASSETS_FOLDER_NAME,
			BOSS_ARENAS_FOLDER_NAME
		), 0)
	end

	return bossArenasFolder
end

local function collectNamedBaseParts(root: Instance, targetName: string): { BasePart }
	local matches = {}

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == targetName then
			table.insert(matches, descendant)
		end
	end

	table.sort(matches, function(left, right)
		return left:GetFullName() < right:GetFullName()
	end)

	return matches
end

local function resolveSingleNamedBasePart(root: Instance, targetName: string): (BasePart?, string?)
	local matches = collectNamedBaseParts(root, targetName)
	if #matches <= 0 then
		return nil, string.format("missing a BasePart named '%s'", targetName)
	end
	if #matches > 1 then
		return nil, string.format(
			"must contain exactly one BasePart named '%s', but found %d",
			targetName,
			#matches
		)
	end

	return matches[1], nil
end

local function computeOverflowOffset(reuseIndex: number): Vector3
	if reuseIndex <= 0 then
		return Vector3.zero
	end

	local pointIndex = (reuseIndex - 1) % PLAYER_SPAWN_RING_SIZE
	local ringIndex = math.floor((reuseIndex - 1) / PLAYER_SPAWN_RING_SIZE) + 1
	local radius = PLAYER_SPAWN_RING_RADIUS * ringIndex
	local angle = (2 * math.pi * pointIndex) / PLAYER_SPAWN_RING_SIZE

	return Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

local function withPosition(baseCFrame: CFrame, position: Vector3): CFrame
	return CFrame.new(position) * (baseCFrame - baseCFrame.Position)
end

local function getBossStandingHeight(humanoid: Humanoid, rootPart: BasePart): number
	return math.max((rootPart.Size.Y * 0.5) + humanoid.HipHeight, rootPart.Size.Y)
end

local function getFeetAlignedBossSpawnCFrame(spawnCFrame: CFrame, humanoid: Humanoid, rootPart: BasePart): CFrame
	local standingHeight = getBossStandingHeight(humanoid, rootPart)
	return withPosition(spawnCFrame, spawnCFrame.Position + Vector3.new(0, standingHeight, 0))
end

function BossArenaRuntimeService:_setState(encounter: EncounterState, nextState: string)
	if encounter.state == nextState then
		return
	end

	encounter.state = nextState
end

function BossArenaRuntimeService:_notifyEncounterStateChanged()
	local activeBossId = self:GetActiveBossId()
	local callbacks = {}

	for callback in pairs(self._encounterStateListeners) do
		table.insert(callbacks, callback)
	end

	for _, callback in ipairs(callbacks) do
		local ok, err = pcall(callback, activeBossId)
		if not ok then
			warnWithPrefix(string.format("Encounter state callback failed: %s", tostring(err)))
		end
	end
end

function BossArenaRuntimeService:_buildBossHealthState(encounter: EncounterState?): BossHealthState?
	if encounter == nil then
		return nil
	end

	local bossModel = encounter.bossModel
	local bossHumanoid = encounter.bossHumanoid
	if bossModel.Parent == nil or bossHumanoid.Parent == nil then
		return nil
	end

	local currentHealth = math.max(0, bossHumanoid.Health)
	if currentHealth <= 0 then
		return nil
	end

	local maxHealth = math.max(currentHealth, bossHumanoid.MaxHealth)
	if maxHealth <= 0 then
		return nil
	end

	return {
		bossId = encounter.bossId,
		currentHealth = currentHealth,
		maxHealth = maxHealth,
	}
end

function BossArenaRuntimeService:_notifyBossHealthStateChanged()
	local healthState = self:GetBossHealthState()
	local callbacks = {}

	for callback in pairs(self._bossHealthStateListeners) do
		table.insert(callbacks, callback)
	end

	for _, callback in ipairs(callbacks) do
		local ok, err = pcall(callback, healthState)
		if not ok then
			warnWithPrefix(string.format("Boss health callback failed: %s", tostring(err)))
		end
	end
end

function BossArenaRuntimeService:_bindBossHealthSignals(encounter: EncounterState)
	disconnectConnections(encounter.bossHealthConnections)

	table.insert(encounter.bossHealthConnections, encounter.bossHumanoid.HealthChanged:Connect(function()
		self:_notifyBossHealthStateChanged()
	end))
	table.insert(encounter.bossHealthConnections, encounter.bossHumanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		self:_notifyBossHealthStateChanged()
	end))
	table.insert(encounter.bossHealthConnections, encounter.bossModel.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			self:_notifyBossHealthStateChanged()
		end
	end))
	table.insert(encounter.bossHealthConnections, encounter.bossHumanoid.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			self:_notifyBossHealthStateChanged()
		end
	end))
end

function BossArenaRuntimeService:_destroyLingeringArtifacts()
	local lingeringBoss = Workspace:FindFirstChild(ACTIVE_BOSS_MODEL_NAME)
	if lingeringBoss then
		lingeringBoss:Destroy()
	end

	local lingeringArena = Workspace:FindFirstChild(ACTIVE_ARENA_MODEL_NAME)
	if lingeringArena then
		lingeringArena:Destroy()
	end
end

function BossArenaRuntimeService:_cleanupEncounterAssets(encounter: EncounterState)
	disconnectConnections(encounter.bossHealthConnections)

	if encounter.animationController then
		encounter.animationController:Destroy()
	end

	for _, instance in ipairs(encounter.appliedLightingInstances) do
		if instance.Parent ~= nil then
			instance:Destroy()
		end
	end

	if encounter.bossModel.Parent ~= nil then
		encounter.bossModel:Destroy()
	end

	if encounter.arenaModel.Parent ~= nil then
		encounter.arenaModel:Destroy()
	end
end

function BossArenaRuntimeService:_clearEncounter(reason: string?)
	local encounter = self._encounter
	if encounter == nil then
		self:_destroyLingeringArtifacts()
		return
	end

	self._encounter = nil
	self:_cleanupEncounterAssets(encounter)

	if typeof(reason) == "string" and reason ~= "" then
		warnWithPrefix(reason)
	end

	self:_notifyBossHealthStateChanged()
	self:_notifyEncounterStateChanged()
end

function BossArenaRuntimeService:_resolveBossSourceModel(bossId: string): Model
	local bossModel = getBossesFolder():FindFirstChild(bossId)
	if bossModel == nil then
		error(string.format(
			"[BossArenaRuntimeService] Missing boss model '%s' under ReplicatedStorage.%s.%s.",
			bossId,
			GAME_ASSETS_FOLDER_NAME,
			BOSSES_FOLDER_NAME
		), 0)
	end
	if not bossModel:IsA("Model") then
		error(string.format(
			"[BossArenaRuntimeService] ReplicatedStorage.%s.%s.%s must be a Model.",
			GAME_ASSETS_FOLDER_NAME,
			BOSSES_FOLDER_NAME,
			bossId
		), 0)
	end

	return bossModel
end

function BossArenaRuntimeService:_resolveArenaSourceModel(arenaDefinition: any): Model
	local arenaModel = getBossArenasFolder():FindFirstChild(arenaDefinition.assetName)
	if arenaModel == nil then
		error(string.format(
			"[BossArenaRuntimeService] Missing arena model '%s' under ReplicatedStorage.%s.%s.",
			arenaDefinition.assetName,
			GAME_ASSETS_FOLDER_NAME,
			BOSS_ARENAS_FOLDER_NAME
		), 0)
	end
	if not arenaModel:IsA("Model") then
		error(string.format(
			"[BossArenaRuntimeService] ReplicatedStorage.%s.%s.%s must be a Model.",
			GAME_ASSETS_FOLDER_NAME,
			BOSS_ARENAS_FOLDER_NAME,
			arenaDefinition.assetName
		), 0)
	end

	return arenaModel
end

function BossArenaRuntimeService:_cloneArenaLighting(): { Instance }
	local appliedInstances = {}
	local lightingFolder = getBossArenasFolder():FindFirstChild(ARENA_LIGHTING_FOLDER_NAME)

	if lightingFolder == nil then
		return appliedInstances
	end
	if not lightingFolder:IsA("Folder") then
		error(string.format(
			"[BossArenaRuntimeService] ReplicatedStorage.%s.%s.%s must be a Folder.",
			GAME_ASSETS_FOLDER_NAME,
			BOSS_ARENAS_FOLDER_NAME,
			ARENA_LIGHTING_FOLDER_NAME
		), 0)
	end

	for _, child in ipairs(lightingFolder:GetChildren()) do
		local clone = child:Clone()
		clone.Parent = Lighting
		table.insert(appliedInstances, clone)
	end

	return appliedInstances
end

function BossArenaRuntimeService:_resolveArenaRadii(bossDefinition: any, bossSpawn: BasePart, arenaModel: Model): (number, number)
	local aggroRadius = readPositiveAttribute(bossSpawn, AGGRO_RADIUS_ATTRIBUTE_NAME)
		or readPositiveAttribute(arenaModel, AGGRO_RADIUS_ATTRIBUTE_NAME)
		or bossDefinition.aggroRadius

	local leashRadius = readPositiveAttribute(bossSpawn, LEASH_RADIUS_ATTRIBUTE_NAME)
		or readPositiveAttribute(arenaModel, LEASH_RADIUS_ATTRIBUTE_NAME)
		or bossDefinition.leashRadius

	return aggroRadius, math.max(aggroRadius, leashRadius)
end

function BossArenaRuntimeService:_setServerNetworkOwnership(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Anchored == false then
			pcall(function()
				descendant:SetNetworkOwner(nil)
			end)
		end
	end
end

function BossArenaRuntimeService:_getRosterIndex(encounter: EncounterState, userId: number): number?
	for index, rosterUserId in ipairs(encounter.rosterOrder) do
		if rosterUserId == userId then
			return index
		end
	end

	return nil
end

function BossArenaRuntimeService:_getAssignedPlayerSpawnCFrame(encounter: EncounterState, userId: number): CFrame?
	local playerSpawnCount = #encounter.playerSpawns
	if playerSpawnCount <= 0 then
		return nil
	end

	local rosterIndex = self:_getRosterIndex(encounter, userId)
	if rosterIndex == nil then
		rosterIndex = #encounter.rosterOrder + 1
		table.insert(encounter.rosterOrder, userId)
	end

	local baseSpawnIndex = ((rosterIndex - 1) % playerSpawnCount) + 1
	local reuseIndex = math.floor((rosterIndex - 1) / playerSpawnCount)
	local baseSpawn = encounter.playerSpawns[baseSpawnIndex]
	local baseCFrame = baseSpawn.CFrame
	local overflowOffset = computeOverflowOffset(reuseIndex)
	local worldOffset = (baseCFrame.RightVector * overflowOffset.X) + (baseCFrame.LookVector * overflowOffset.Z)

	return withPosition(baseCFrame, baseCFrame.Position + worldOffset)
end

function BossArenaRuntimeService:_positionPlayerInArena(encounter: EncounterState, player: Player): boolean
	local character = player.Character
	local humanoid = getCharacterHumanoid(character)
	if character == nil or humanoid == nil then
		return false
	end

	local rootPart = getModelRootPart(character)
	local assignedSpawn = self:_getAssignedPlayerSpawnCFrame(encounter, player.UserId)
	if rootPart == nil or assignedSpawn == nil then
		return false
	end

	local targetPosition = assignedSpawn.Position + Vector3.new(0, PLAYER_SPAWN_VERTICAL_OFFSET, 0)
	local targetCFrame = withPosition(assignedSpawn, targetPosition)

	character:PivotTo(targetCFrame)
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
	encounter.placedCharacters[player.UserId] = character

	return true
end

function BossArenaRuntimeService:_positionQueuedPlayersIfNeeded(encounter: EncounterState)
	for _, userId in ipairs(encounter.rosterOrder) do
		local player = getPlayerByUserId(userId)
		if player == nil then
			continue
		end

		local currentCharacter = player.Character
		if currentCharacter == nil then
			continue
		end
		if encounter.placedCharacters[userId] == currentCharacter then
			continue
		end

		self:_positionPlayerInArena(encounter, player)
	end
end

function BossArenaRuntimeService:_spawnBossEncounter(payload: any)
	self:_clearEncounter(nil)

	local bossId = payload.bossName
	local bossDefinition = Bosses.GetDefinition(bossId)
	if bossDefinition == nil then
		error(string.format(
			"[BossArenaRuntimeService] No local boss definition exists for '%s'.",
			bossId
		), 0)
	end

	local arenaId = payload.arenaId
	if arenaId ~= bossDefinition.arenaId then
		error(string.format(
			"[BossArenaRuntimeService] Payload arena '%s' does not match boss '%s' arena '%s'.",
			tostring(arenaId),
			bossId,
			bossDefinition.arenaId
		), 0)
	end

	local arenaDefinition = BossArenas.GetDefinition(arenaId)
	if arenaDefinition == nil then
		error(string.format(
			"[BossArenaRuntimeService] No local arena definition exists for '%s'.",
			arenaId
		), 0)
	end

	local sourceArenaModel = self:_resolveArenaSourceModel(arenaDefinition)
	local sourceBossModel = self:_resolveBossSourceModel(bossId)

	local arenaModel = sourceArenaModel:Clone()
	arenaModel.Name = ACTIVE_ARENA_MODEL_NAME
	arenaModel.Parent = Workspace

	-- Boss placement is intentionally singular: one authoritative BossSpawn drives both initial
	-- spawn placement and the boss's home/return anchor for the encounter.
	local bossSpawn, bossSpawnError = resolveSingleNamedBasePart(arenaModel, arenaDefinition.bossSpawnName)
	if bossSpawn == nil then
		arenaModel:Destroy()
		error(string.format(
			"[BossArenaRuntimeService] Arena '%s' %s.",
			arenaId,
			tostring(bossSpawnError)
		), 0)
	end

	-- Player placement is intentionally plural and separate from boss placement.
	local playerSpawns = collectNamedBaseParts(arenaModel, arenaDefinition.playerSpawnName)
	if #playerSpawns <= 0 then
		arenaModel:Destroy()
		error(string.format(
			"[BossArenaRuntimeService] Arena '%s' is missing BaseParts named '%s'.",
			arenaId,
			arenaDefinition.playerSpawnName
		), 0)
	end

	local appliedLightingInstances = self:_cloneArenaLighting()
	local aggroRadius, leashRadius = self:_resolveArenaRadii(bossDefinition, bossSpawn, arenaModel)

	local bossModel = sourceBossModel:Clone()
	bossModel.Name = ACTIVE_BOSS_MODEL_NAME

	if bossDefinition.scaleMultiplier ~= 1 then
		local scaleOk, scaleError = pcall(function()
			bossModel:ScaleTo(bossDefinition.scaleMultiplier)
		end)
		if not scaleOk then
			warnWithPrefix(string.format(
				"Failed to scale boss '%s' to %.2fx: %s",
				bossId,
				bossDefinition.scaleMultiplier,
				tostring(scaleError)
			))
		end
	end

	bossModel.Parent = Workspace

	local bossHumanoid = bossModel:FindFirstChildOfClass("Humanoid")
	if bossHumanoid == nil then
		bossModel:Destroy()
		arenaModel:Destroy()
		for _, instance in ipairs(appliedLightingInstances) do
			instance:Destroy()
		end
		error(string.format(
			"[BossArenaRuntimeService] Boss model '%s' must contain a Humanoid.",
			bossId
		), 0)
	end

	local bossRootPart = getModelRootPart(bossModel)
	if bossRootPart == nil then
		bossModel:Destroy()
		arenaModel:Destroy()
		for _, instance in ipairs(appliedLightingInstances) do
			instance:Destroy()
		end
		error(string.format(
			"[BossArenaRuntimeService] Boss model '%s' must contain a root BasePart.",
			bossId
		), 0)
	end

	local bossSpawnCFrame = getFeetAlignedBossSpawnCFrame(bossSpawn.CFrame, bossHumanoid, bossRootPart)
	bossModel:PivotTo(bossSpawnCFrame)

	bossHumanoid.WalkSpeed = bossDefinition.walkSpeed
	bossHumanoid.AutoRotate = true
	self:_setServerNetworkOwnership(bossModel)

	local animationController = BossAnimationController.Attach(bossModel, bossHumanoid, {
		scaleMultiplier = bossDefinition.scaleMultiplier,
	})

	self._encounter = {
		payload = payload,
		bossId = bossId,
		arenaId = arenaId,
		bossDefinition = bossDefinition,
		arenaDefinition = arenaDefinition,
		arenaModel = arenaModel,
		bossModel = bossModel,
		bossHumanoid = bossHumanoid,
		bossRootPart = bossRootPart,
		animationController = animationController,
		bossSpawn = bossSpawn,
		playerSpawns = playerSpawns,
		appliedLightingInstances = appliedLightingInstances,
		homePosition = bossSpawnCFrame.Position,
		aggroRadius = aggroRadius,
		leashRadius = leashRadius,
		rosterUserIds = buildRosterUserIdSet(payload),
		rosterOrder = table.clone(payload.queuedUserIds),
		placedCharacters = {},
		state = "Spawning",
		currentTargetUserId = nil,
		lastRetargetAt = 0,
		lastMoveCommandAt = 0,
		lastAbilityStartedAt = 0,
		cooldowns = {},
		rng = Random.new(),
		spawnedAt = os.clock(),
		activeCast = nil,
		bossHealthConnections = {},
	}
	self:_bindBossHealthSignals(self._encounter)

	self:_positionQueuedPlayersIfNeeded(self._encounter)
	self:_setState(self._encounter, "Idle")

	print(string.format(
		"[BossArenaRuntimeService] Spawned boss '%s' in arena '%s' from BossSpawn '%s' at %.2fx with aggro %.1f and leash %.1f.",
		bossId,
		arenaId,
		bossSpawn:GetFullName(),
		bossDefinition.scaleMultiplier,
		aggroRadius,
		leashRadius
	))

	self:_notifyBossHealthStateChanged()
	self:_notifyEncounterStateChanged()
end

function BossArenaRuntimeService:_validatePlayerPayload(player: Player)
	local payload = BossArenaArrivalService:GetArrivalPayload(player)
	if payload == nil then
		return nil
	end

	local encounter = self._encounter
	if encounter == nil then
		return payload
	end

	if payload.bossName ~= encounter.bossId or payload.arenaId ~= encounter.arenaId then
		warnWithPrefix(string.format(
			"Player %s arrived with boss '%s' in arena '%s' but the active encounter is '%s' in '%s'.",
			player.Name,
			payload.bossName,
			payload.arenaId,
			encounter.bossId,
			encounter.arenaId
		))
		return nil
	end

	encounter.rosterUserIds[player.UserId] = true
	self:_positionPlayerInArena(encounter, player)
	return payload
end

function BossArenaRuntimeService:_tryInitializeEncounterFromPlayer(player: Player)
	if self._encounter ~= nil then
		self:_validatePlayerPayload(player)
		return
	end

	local payload = self:_validatePlayerPayload(player)
	if payload == nil then
		return
	end

	local spawnOk, spawnError = xpcall(function()
		self:_spawnBossEncounter(payload)
	end, debug.traceback)
	if not spawnOk then
		warnWithPrefix(string.format("Failed to initialize boss encounter: %s", tostring(spawnError)))
	end
end

function BossArenaRuntimeService:_tryInitializeEncounterFromExistingPlayers()
	if self._encounter ~= nil then
		return
	end

	for _, player in ipairs(Players:GetPlayers()) do
		self:_tryInitializeEncounterFromPlayer(player)
		if self._encounter ~= nil then
			return
		end
	end
end

function BossArenaRuntimeService:_refreshRosterFromPlayers()
	local encounter = self._encounter
	if encounter == nil then
		return
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if encounter.rosterUserIds[player.UserId] ~= true then
			self:_validatePlayerPayload(player)
		end
	end
end

function BossArenaRuntimeService:_collectAliveTargets(encounter: EncounterState): { AliveTargetContext }
	local aliveTargets = {}
	local restrictToRoster = next(encounter.rosterUserIds) ~= nil

	for _, player in ipairs(Players:GetPlayers()) do
		if restrictToRoster and encounter.rosterUserIds[player.UserId] ~= true then
			continue
		end

		local character = player.Character
		local humanoid = getCharacterHumanoid(character)
		if character == nil or humanoid == nil then
			continue
		end

		local rootPart = getModelRootPart(character)
		if rootPart == nil then
			continue
		end

		table.insert(aliveTargets, {
			player = player,
			character = character,
			humanoid = humanoid,
			rootPart = rootPart,
			distanceToBoss = (rootPart.Position - encounter.bossRootPart.Position).Magnitude,
			distanceToHome = (rootPart.Position - encounter.homePosition).Magnitude,
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

function BossArenaRuntimeService:_resolveTargetContext(
	encounter: EncounterState,
	aliveTargets: { AliveTargetContext }
): AliveTargetContext?
	local currentTargetContext = nil

	if encounter.currentTargetUserId ~= nil then
		for _, aliveTarget in ipairs(aliveTargets) do
			if aliveTarget.player.UserId == encounter.currentTargetUserId then
				currentTargetContext = aliveTarget
				break
			end
		end
	end

	if currentTargetContext ~= nil and currentTargetContext.distanceToHome > encounter.leashRadius then
		currentTargetContext = nil
		encounter.currentTargetUserId = nil
	end

	local now = os.clock()
	if currentTargetContext ~= nil and now - encounter.lastRetargetAt < encounter.bossDefinition.retargetCadenceSeconds then
		return currentTargetContext
	end

	local nearestTarget = nil
	for _, aliveTarget in ipairs(aliveTargets) do
		if aliveTarget.distanceToHome <= encounter.aggroRadius then
			nearestTarget = aliveTarget
			break
		end
	end

	if nearestTarget == nil then
		encounter.currentTargetUserId = nil
		encounter.lastRetargetAt = now
		return nil
	end

	if currentTargetContext ~= nil then
		local distanceDelta = currentTargetContext.distanceToBoss - nearestTarget.distanceToBoss
		if currentTargetContext.distanceToHome <= encounter.leashRadius and distanceDelta < encounter.bossDefinition.retargetSwapBuffer then
			return currentTargetContext
		end
	end

	encounter.currentTargetUserId = nearestTarget.player.UserId
	encounter.lastRetargetAt = now
	return nearestTarget
end

function BossArenaRuntimeService:_buildMoveContext(
	encounter: EncounterState,
	moveDefinition: any,
	aliveTargets: { AliveTargetContext },
	targetUserId: number?
)
	local targetPlayer = getPlayerByUserId(targetUserId)
	local targetCharacter = if targetPlayer then targetPlayer.Character else nil
	local targetHumanoid = getCharacterHumanoid(targetCharacter)
	local targetRootPart = if targetCharacter then getModelRootPart(targetCharacter) else nil

	return {
		now = os.clock(),
		bossDefinition = encounter.bossDefinition,
		move = moveDefinition,
		bossModel = encounter.bossModel,
		bossHumanoid = encounter.bossHumanoid,
		bossRootPart = encounter.bossRootPart,
		bossState = encounter.state,
		homePosition = encounter.homePosition,
		targetPlayer = targetPlayer,
		targetCharacter = targetCharacter,
		targetHumanoid = targetHumanoid,
		targetRootPart = targetRootPart,
		distanceToTarget = if targetRootPart then (targetRootPart.Position - encounter.bossRootPart.Position).Magnitude else nil,
		aliveTargets = aliveTargets,
	}
end

function BossArenaRuntimeService:_canUseMove(moveDefinition: any, context: any): boolean
	if context.distanceToTarget ~= nil then
		if context.distanceToTarget < moveDefinition.minRange or context.distanceToTarget > moveDefinition.maxRange then
			return false
		end
	end

	local canUseOk, canUse, reason = pcall(function()
		return moveDefinition.module.CanUse(context)
	end)
	if not canUseOk then
		warnWithPrefix(string.format(
			"Boss move '%s' CanUse failed: %s",
			moveDefinition.id,
			tostring(canUse)
		))
		return false
	end
	if canUse ~= true then
		if typeof(reason) == "string" and reason ~= "" then
			return false
		end
		return false
	end

	return true
end

function BossArenaRuntimeService:_startCast(
	encounter: EncounterState,
	moveDefinition: any,
	targetContext: AliveTargetContext?,
	aliveTargets: { AliveTargetContext }
)
	local now = os.clock()
	local castState: CastState = {
		move = moveDefinition,
		startedAt = now,
		executeAt = now + moveDefinition.castTimeSeconds,
		recoveryEndsAt = now + moveDefinition.castTimeSeconds + moveDefinition.recoverySeconds,
		rootDuringCast = moveDefinition.rootDuringCast == true,
		executed = false,
		targetUserId = if targetContext then targetContext.player.UserId else nil,
	}

	encounter.activeCast = castState
	encounter.lastAbilityStartedAt = now
	encounter.cooldowns[moveDefinition.id] = now + moveDefinition.cooldownSeconds
	self:_setState(encounter, "Casting")

	local previewContext = self:_buildMoveContext(encounter, moveDefinition, aliveTargets, castState.targetUserId)
	print(string.format(
		"[BossArenaRuntimeService] Boss '%s' in arena '%s' started cast '%s' targeting %s.",
		encounter.bossId,
		encounter.arenaId,
		moveDefinition.id,
		if previewContext.targetPlayer then previewContext.targetPlayer.Name else "arena"
	))
end

function BossArenaRuntimeService:_emitMoveStub(
	encounter: EncounterState,
	moveDefinition: any,
	aliveTargets: { AliveTargetContext },
	targetUserId: number?
)
	local context = self:_buildMoveContext(encounter, moveDefinition, aliveTargets, targetUserId)
	local targetingOk, targetingData = pcall(function()
		return moveDefinition.module.GetTargeting(context)
	end)
	if not targetingOk then
		warnWithPrefix(string.format(
			"Boss move '%s' GetTargeting failed: %s",
			moveDefinition.id,
			tostring(targetingData)
		))
		targetingData = {
			mode = "unknown",
			summary = "targeting error",
		}
	end

	local executeOk, debugPayload = pcall(function()
		return moveDefinition.module.ExecuteStub(context)
	end)
	if not executeOk then
		warnWithPrefix(string.format(
			"Boss move '%s' ExecuteStub failed: %s",
			moveDefinition.id,
			tostring(debugPayload)
		))
		debugPayload = {
			error = tostring(debugPayload),
		}
	end

	local serializedPayload = HttpService:JSONEncode({
		bossId = encounter.bossId,
		arenaId = encounter.arenaId,
		moveId = moveDefinition.id,
		moduleId = moveDefinition.moduleId,
		tags = moveDefinition.tags,
		timestampUnix = os.time(),
		state = encounter.state,
		distanceToTarget = context.distanceToTarget,
		target = targetingData,
		debug = debugPayload,
	})

	print(string.format("[BossArenaRuntimeService] MoveStub %s", serializedPayload))
end

function BossArenaRuntimeService:_updateCast(encounter: EncounterState, aliveTargets: { AliveTargetContext })
	local activeCast = encounter.activeCast
	if activeCast == nil then
		return
	end

	local now = os.clock()

	if not activeCast.executed and now >= activeCast.executeAt then
		self:_emitMoveStub(encounter, activeCast.move, aliveTargets, activeCast.targetUserId)
		activeCast.executed = true
	end

	if now >= activeCast.recoveryEndsAt then
		encounter.activeCast = nil
	end
end

function BossArenaRuntimeService:_moveBossTo(encounter: EncounterState, worldPosition: Vector3)
	if os.clock() - encounter.lastMoveCommandAt < encounter.bossDefinition.moveToRefreshSeconds then
		return
	end

	encounter.lastMoveCommandAt = os.clock()
	encounter.bossHumanoid:MoveTo(worldPosition)
end

function BossArenaRuntimeService:_updateMovement(encounter: EncounterState, targetContext: AliveTargetContext?)
	local activeCast = encounter.activeCast

	if activeCast ~= nil and activeCast.rootDuringCast then
		self:_setState(encounter, "Casting")
		self:_moveBossTo(encounter, encounter.bossRootPart.Position)
		return
	end

	if targetContext ~= nil and targetContext.distanceToHome <= encounter.leashRadius then
		if activeCast == nil then
			self:_setState(encounter, "Chasing")
		end
		self:_moveBossTo(encounter, targetContext.rootPart.Position)
		return
	end

	local distanceFromHome = (encounter.bossRootPart.Position - encounter.homePosition).Magnitude
	if distanceFromHome > 4 then
		if activeCast == nil then
			self:_setState(encounter, "Returning")
		end
		self:_moveBossTo(encounter, encounter.homePosition)
		return
	end

	if activeCast == nil then
		self:_setState(encounter, "Idle")
	end
end

function BossArenaRuntimeService:_tryStartAbility(
	encounter: EncounterState,
	aliveTargets: { AliveTargetContext },
	targetContext: AliveTargetContext?
)
	if encounter.activeCast ~= nil then
		return
	end
	if os.clock() - encounter.lastAbilityStartedAt < encounter.bossDefinition.abilityCadenceSeconds then
		return
	end

	local validMoves = {}

	for _, moveDefinition in ipairs(encounter.bossDefinition.moves) do
		local cooldownEndsAt = encounter.cooldowns[moveDefinition.id] or 0
		if cooldownEndsAt > os.clock() then
			continue
		end

		local context = self:_buildMoveContext(
			encounter,
			moveDefinition,
			aliveTargets,
			if targetContext then targetContext.player.UserId else nil
		)
		if self:_canUseMove(moveDefinition, context) then
			table.insert(validMoves, {
				move = moveDefinition,
				context = context,
			})
		end
	end

	if #validMoves <= 0 then
		return
	end

	local selectedMove = chooseWeightedMove(validMoves, encounter.rng)
	self:_startCast(encounter, selectedMove.move, targetContext, aliveTargets)
end

function BossArenaRuntimeService:_heartbeat()
	if self._encounter == nil then
		self:_tryInitializeEncounterFromExistingPlayers()
		return
	end

	self:_refreshRosterFromPlayers()

	local encounter = self._encounter
	if encounter == nil then
		return
	end

	self:_positionQueuedPlayersIfNeeded(encounter)

	if encounter.arenaModel.Parent == nil then
		self:_clearEncounter("Active arena model was removed from Workspace.")
		return
	end
	if encounter.bossModel.Parent == nil then
		self:_clearEncounter("Active boss model was removed from Workspace.")
		return
	end
	if encounter.bossHumanoid.Health <= 0 then
		self:_setState(encounter, "Idle")
		return
	end

	local aliveTargets = self:_collectAliveTargets(encounter)
	local targetContext = self:_resolveTargetContext(encounter, aliveTargets)
	self:_updateCast(encounter, aliveTargets)
	encounter.animationController:SetLocomotionSuppressed(encounter.activeCast ~= nil)
	self:_updateMovement(encounter, targetContext)
	self:_tryStartAbility(encounter, aliveTargets, targetContext)
end

function BossArenaRuntimeService:OnStart()
	if self._started then
		return
	end
	self._started = true

	if not isEnabledForPlace() then
		return
	end

	self._heartbeatConnection = RunService.Heartbeat:Connect(function()
		self:_heartbeat()
	end)

	print("[BossArenaRuntimeService] Ready for boss arena encounter initialization.")
end

function BossArenaRuntimeService:OnPlayerAdded(player: Player)
	if not isEnabledForPlace() then
		return
	end

	self:_tryInitializeEncounterFromPlayer(player)
end

function BossArenaRuntimeService:OnPlayerRemoving(player: Player)
	local encounter = self._encounter
	if encounter == nil then
		return
	end

	encounter.rosterUserIds[player.UserId] = nil
	encounter.placedCharacters[player.UserId] = nil
	if encounter.currentTargetUserId == player.UserId then
		encounter.currentTargetUserId = nil
	end
end

function BossArenaRuntimeService:HasActiveEncounter(): boolean
	return self._encounter ~= nil
end

function BossArenaRuntimeService:GetActiveBossId(): string?
	local encounter = self._encounter
	if encounter == nil then
		return nil
	end

	return encounter.bossId
end

function BossArenaRuntimeService:GetBossHealthState(): BossHealthState?
	return self:_buildBossHealthState(self._encounter)
end

function BossArenaRuntimeService:GetAssignedPlayerSpawnCFrame(player: Player): CFrame?
	local encounter = self._encounter
	if encounter == nil then
		return nil
	end
	if encounter.rosterUserIds[player.UserId] ~= true then
		return nil
	end

	return self:_getAssignedPlayerSpawnCFrame(encounter, player.UserId)
end

function BossArenaRuntimeService:StartStudioEncounterFromBossId(
	requestingPlayer: Player?,
	bossId: string
): (boolean, string?)
	if not isEnabledForPlace() then
		return false, "Boss arena runtime is not enabled for this place."
	end
	if RunService:IsStudio() ~= true then
		return false, "Manual boss selection is only available in Studio."
	end
	if self._encounter ~= nil then
		return false, "A boss encounter is already active."
	end

	local normalizedBossId = normalizeString(bossId)
	if normalizedBossId == "" then
		return false, "A valid boss id is required."
	end

	local bossDefinition = Bosses.GetDefinition(normalizedBossId)
	if bossDefinition == nil then
		return false, string.format("Unknown boss '%s'.", normalizedBossId)
	end
	if BossArenas.HasDefinition(bossDefinition.arenaId) ~= true then
		return false, string.format(
			"Boss '%s' is mapped to unknown arena '%s'.",
			normalizedBossId,
			tostring(bossDefinition.arenaId)
		)
	end

	local payload, payloadError = BossQueueTeleportPayload.Build(
		normalizedBossId,
		bossDefinition.arenaId,
		"studio_picker",
		buildSyntheticQueuedUserIds(requestingPlayer),
		os.time()
	)
	if payload == nil then
		return false, payloadError or "Failed to build the Studio boss selection payload."
	end

	local spawnOk, spawnError = xpcall(function()
		self:_spawnBossEncounter(payload)
	end, debug.traceback)
	if not spawnOk then
		return false, tostring(spawnError)
	end

	return true, nil
end

function BossArenaRuntimeService:ConnectEncounterStateChanged(callback: (string?) -> ()): () -> ()
	assert(type(callback) == "function", "Encounter state callback must be a function.")
	self._encounterStateListeners[callback] = true

	return function()
		self._encounterStateListeners[callback] = nil
	end
end

function BossArenaRuntimeService:ConnectBossHealthStateChanged(callback: (BossHealthState?) -> ()): () -> ()
	assert(type(callback) == "function", "Boss health callback must be a function.")
	self._bossHealthStateListeners[callback] = true

	return function()
		self._bossHealthStateListeners[callback] = nil
	end
end

return BossArenaRuntimeService
