local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local BossArenaArrivalService = require(script.Parent.BossArenaArrivalService)
local BossAnimationController = require(script.Parent.Common.BossAnimationController)
local BossArenaRewardService = require(script.Parent.BossArenaRewardService)
local BossPhysicsStabilizer = require(script.Parent.Common.BossPhysicsStabilizer)
local BossArenas = require(ReplicatedStorage.Shared.BossArenas)
local BossEncounterScaling = require(ReplicatedStorage.Shared.BossArena.EncounterScaling)
local BossQueueTeleportPayload = require(ReplicatedStorage.Shared.BossQueue.TeleportPayload)
local BossFacing = require(ReplicatedStorage.Shared.Bosses.BossFacing)
local BossMoveTags = require(ReplicatedStorage.Shared.Bosses.MoveTags)
local Bosses = require(ReplicatedStorage.Shared.Bosses)
local CombatConstants = require(ReplicatedStorage.Shared.Combat.Constants)
local GameAssetPaths = require(ReplicatedStorage.Shared.Assets.GameAssetPaths)
local GameAssetResolver = require(ReplicatedStorage.Shared.Assets.GameAssetResolver)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local ACTIVE_PROFILE_ID = "boss_arena"
local GAME_ASSETS_FOLDER_NAME = "GameAssets"
local ARENA_LIGHTING_FOLDER_NAME = "ArenaLighting"
local ACTIVE_BOSS_MODEL_NAME = "ActiveBoss"
local ACTIVE_ARENA_MODEL_NAME = "ActiveBossArena"
local AGGRO_RADIUS_ATTRIBUTE_NAME = "BossAggroRadius"
local LEASH_RADIUS_ATTRIBUTE_NAME = "BossLeashRadius"
local PLAYER_SPAWN_VERTICAL_OFFSET = 4
local PLAYER_SPAWN_RING_SIZE = 6
local PLAYER_SPAWN_RING_RADIUS = 8
local BOSS_INTRO_COUNTDOWN_SECONDS = 10
local BOSS_INTRO_RISE_SECONDS = 2
local BOSS_INTRO_UNDERGROUND_PADDING = 1
local BOSS_ATTACK_SPAWN_DELAY_SECONDS = 5
local BOSS_ENCOUNTER_DURATION_SECONDS = 180
local BOSS_TIMEOUT_RETURN_ROUTE_ID = "return_to_boss_lobby"
local BOSS_RESULTS_DURATION_SECONDS = 15
local CHARACTER_PLACEMENT_RETRY_COUNT = 20
local CHARACTER_PLACEMENT_RETRY_INTERVAL_SECONDS = 0.1
local BOSS_REWARD_DAMAGE_CONTRIBUTION_RATIO = 0.15
local DAMAGE_LEADERSTAT_NAME = "Damage"
local BOSS_INVULNERABLE_ATTRIBUTE = "BossM1Invulnerable"
local BOSS_HITBOX_COLLIDER_NAME = "BossHitboxCollider"
local BOSS_FOLDER_PATHS = { GameAssetPaths.Models.Bosses, GameAssetPaths.Legacy.Bosses }
local BOSS_ARENA_FOLDER_PATHS = { GameAssetPaths.Models.Worlds.BossArenas, GameAssetPaths.Legacy.BossArenas }

type CastState = {
	castId: string,
	move: any,
	startedAt: number,
	executeAt: number,
	recoveryEndsAt: number,
	rootDuringCast: boolean,
	executed: boolean,
	targetUserId: number?,
	lifecycleHandle: any?,
	completedAt: number?,
}

type BossHealthState = {
	bossId: string,
	currentHealth: number,
	maxHealth: number,
}

type BossTimerState = {
	phase: string,
	startsAtServerTime: number,
	endsAtServerTime: number,
	durationSeconds: number,
}

type BossHitConfirmedPayload = {
	bossId: string,
	damage: number,
	attackerUserId: number,
	serverTime: number,
}

type BossResultRewardEntry = {
	pieceId: string,
	displayName: string,
	setId: string,
	displayRarity: string,
	displayOddsDenominator: number,
	isBossPart: boolean,
}

type BossResultsState = {
	outcome: string,
	bossId: string,
	damagePercent: number,
	startsAtServerTime: number,
	endsAtServerTime: number,
	durationSeconds: number,
	rewards: { BossResultRewardEntry },
	readyCount: number,
	capacity: number,
	isReplayReady: boolean,
}

type EncounterState = {
	payload: any,
	bossId: string,
	arenaId: string,
	bossDefinition: any,
	encounterScaling: BossEncounterScaling.EncounterScaling,
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
	damageByUserId: { [number]: number },
	rewardEligibleDamageThreshold: number,
	state: string,
	currentTargetUserId: number?,
	lastRetargetAt: number,
	lastMoveCommandAt: number,
	nextAbilityAvailableAt: number,
	cooldowns: { [string]: number },
	rng: Random,
	spawnedAt: number,
	timerStartedAt: number,
	timerEndsAt: number,
	timerStartedAtServerTime: number,
	timerEndsAtServerTime: number,
	timerPhase: string,
	introFinalCFrame: CFrame?,
	introRiseTween: Tween?,
	introRiseCFrameValue: CFrameValue?,
	introRiseCFrameConnection: RBXScriptConnection?,
	introRiseCompletedConnection: RBXScriptConnection?,
	introRiseAnchorStates: { [BasePart]: boolean }?,
	rewardsGranted: boolean,
	returnCountdownEndsAt: number?,
	returnCountdownStartedAtServerTime: number?,
	returnCountdownEndsAtServerTime: number?,
	resultsOutcome: string?,
	resultsStartedAt: number?,
	resultsEndsAt: number?,
	resultsStartedAtServerTime: number?,
	resultsEndsAtServerTime: number?,
	resultRewardsByUserId: { [number]: { BossResultRewardEntry } },
	replayReadyUserIds: { [number]: boolean },
	resultsCompleted: boolean,
	timedOut: boolean,
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
	_playerCharacterConnections = {} :: { [Player]: RBXScriptConnection },
	_characterPlacementTokens = {} :: { [Player]: number },
	_encounterStateListeners = {} :: { [(string?) -> ()]: boolean },
	_rosterStateListeners = {} :: { [() -> ()]: boolean },
	_bossHealthStateListeners = {} :: { [(BossHealthState?) -> ()]: boolean },
	_bossTimerStateListeners = {} :: { [(BossTimerState?) -> ()]: boolean },
	_bossResultsStateListeners = {} :: { [() -> ()]: boolean },
	_bossHitConfirmedListeners = {} :: { [(BossHitConfirmedPayload) -> ()]: boolean },
	_movePresentationListeners = {} :: { [(any) -> ()]: boolean },
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
end

local function warnWithPrefix(message: string)
	Logger.Warn(string.format("[BossArenaRuntimeService] %s", message))
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

local function resolveEncounterPartySize(payload: BossQueueTeleportPayload.BossQueueTeleportPayload?): number
	if typeof(payload) ~= "table" then
		return 1
	end

	local queueSize = math.floor(tonumber(payload.queueSize) or 0)
	if queueSize > 0 then
		return queueSize
	end

	if typeof(payload.queuedUserIds) == "table" then
		return #payload.queuedUserIds
	end

	return 1
end

local function applyBossHealthScaling(bossHumanoid: Humanoid, healthMultiplier: number)
	local resolvedHealthMultiplier = math.max(0, tonumber(healthMultiplier) or 1)
	local previousMaxHealth = math.max(1, tonumber(bossHumanoid.MaxHealth) or 1)
	local previousHealth = math.max(0, tonumber(bossHumanoid.Health) or previousMaxHealth)
	local healthRatio = math.clamp(previousHealth / previousMaxHealth, 0, 1)
	local scaledMaxHealth = math.max(1, math.round(previousMaxHealth * resolvedHealthMultiplier))
	local scaledHealth = math.round(scaledMaxHealth * healthRatio)

	bossHumanoid.MaxHealth = scaledMaxHealth
	bossHumanoid.Health = math.clamp(scaledHealth, 0, scaledMaxHealth)
end

local function applyBossHealthRatio(bossHumanoid: Humanoid, ratio: number)
	local resolvedRatio = math.max(0, tonumber(ratio) or 1)
	local previousMaxHealth = math.max(1, tonumber(bossHumanoid.MaxHealth) or 1)
	local previousHealth = math.max(0, tonumber(bossHumanoid.Health) or previousMaxHealth)
	local scaledMaxHealth = math.max(1, math.round(previousMaxHealth * resolvedRatio))
	local scaledHealth = math.clamp(math.round(previousHealth * resolvedRatio), 0, scaledMaxHealth)

	bossHumanoid.MaxHealth = scaledMaxHealth
	bossHumanoid.Health = scaledHealth
end

local function applyBossBaseHealth(bossHumanoid: Humanoid, baseHealth: number)
	local resolvedBaseHealth = math.max(1, math.round(tonumber(baseHealth) or 1))
	local previousMaxHealth = math.max(1, tonumber(bossHumanoid.MaxHealth) or 1)
	local previousHealth = math.max(0, tonumber(bossHumanoid.Health) or previousMaxHealth)
	local healthRatio = math.clamp(previousHealth / previousMaxHealth, 0, 1)
	local resolvedHealth = math.clamp(math.round(resolvedBaseHealth * healthRatio), 0, resolvedBaseHealth)

	bossHumanoid.MaxHealth = resolvedBaseHealth
	bossHumanoid.Health = resolvedHealth
end

local function applyBossBodyCollisionGroup(bossModel: Model)
	local bossBodyGroup = CombatConstants.COLLISION_GROUPS.BossBody
	for _, descendant in ipairs(bossModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = bossBodyGroup
		end
	end
end

local function createBossHitboxCollider(bossModel: Model, bossRootPart: BasePart): BasePart
	local existingCollider = bossModel:FindFirstChild(BOSS_HITBOX_COLLIDER_NAME)
	if existingCollider then
		existingCollider:Destroy()
	end

	local boundingCFrame, boundingSize = bossModel:GetBoundingBox()
	local collider = Instance.new("Part")
	collider.Name = BOSS_HITBOX_COLLIDER_NAME
	collider.Size = Vector3.new(
		math.max(0.1, boundingSize.X),
		math.max(0.1, boundingSize.Y),
		math.max(0.1, boundingSize.Z)
	)
	collider.CFrame = boundingCFrame
	collider.Transparency = 1
	collider.Anchored = false
	collider.CanCollide = false
	collider.CanTouch = false
	collider.CanQuery = true
	collider.Massless = true
	collider.CollisionGroup = CombatConstants.COLLISION_GROUPS.BossBody
	collider.Parent = bossModel

	local weld = Instance.new("WeldConstraint")
	weld.Name = "BossHitboxColliderWeld"
	weld.Part0 = bossRootPart
	weld.Part1 = collider
	weld.Parent = collider

	return collider
end

local function chooseWeightedMove(validMoves: { { move: any, context: any, effectiveWeight: number } }, rng: Random)
	local totalWeight = 0
	for _, entry in ipairs(validMoves) do
		totalWeight += math.max(0, tonumber(entry.effectiveWeight) or 0)
	end

	if totalWeight <= 0 then
		return validMoves[1]
	end

	local threshold = rng:NextNumber(0, totalWeight)
	local accumulatedWeight = 0

	for _, entry in ipairs(validMoves) do
		accumulatedWeight += math.max(0, tonumber(entry.effectiveWeight) or 0)
		if threshold <= accumulatedWeight then
			return entry
		end
	end

	return validMoves[#validMoves]
end

local function moveHasTag(moveDefinition: any, targetTag: string): boolean
	if typeof(moveDefinition) ~= "table" or typeof(moveDefinition.tags) ~= "table" then
		return false
	end

	for _, tag in ipairs(moveDefinition.tags) do
		if tag == targetTag then
			return true
		end
	end

	return false
end

local function shouldFaceTargetOnCast(moveDefinition: any): boolean
	return moveDefinition.faceTargetOnCast == true or moveHasTag(moveDefinition, BossMoveTags.RangedSingle)
end

local function resolveCastTargetRootPart(targetContext: AliveTargetContext?): BasePart?
	if targetContext == nil then
		return nil
	end

	local rootPart = targetContext.rootPart
	if rootPart == nil or rootPart.Parent == nil then
		return nil
	end

	return rootPart
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

local function countRosterMembers(encounter: EncounterState): number
	local count = 0
	for userId in pairs(encounter.rosterUserIds) do
		if math.floor(tonumber(userId) or 0) > 0 then
			count += 1
		end
	end

	return count
end

local function getOrCreateLeaderstats(player: Player): Folder
	local existing = player:FindFirstChild("leaderstats")
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	folder.Parent = player
	return folder
end

local function getOrCreateDamageLeaderstat(player: Player): IntValue
	local leaderstats = getOrCreateLeaderstats(player)
	local existing = leaderstats:FindFirstChild(DAMAGE_LEADERSTAT_NAME)
	if existing and existing:IsA("IntValue") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local value = Instance.new("IntValue")
	value.Name = DAMAGE_LEADERSTAT_NAME
	value.Value = 0
	value.Parent = leaderstats
	return value
end

local function setDamageLeaderstat(player: Player, damageAmount: number)
	local damageValue = getOrCreateDamageLeaderstat(player)
	local resolvedDamage = math.max(0, math.floor(tonumber(damageAmount) or 0))
	if damageValue.Value ~= resolvedDamage then
		damageValue.Value = resolvedDamage
	end
end

function BossArenaRuntimeService:_syncDamageLeaderstats(encounter: EncounterState?)
	if encounter == nil then
		return
	end

	for userId in pairs(encounter.rosterUserIds) do
		local player = getPlayerByUserId(userId)
		if player then
			setDamageLeaderstat(player, encounter.damageByUserId[userId] or 0)
		end
	end
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
		Logger.Error(string.format(
			"[BossArenaRuntimeService] Missing ReplicatedStorage.%s in the boss arena place.",
			GAME_ASSETS_FOLDER_NAME
		), 0)
	end

	return gameAssetsFolder
end

local function formatAssetPaths(paths: { any }): string
	local formattedPaths = {}
	for _, path in ipairs(paths) do
		table.insert(formattedPaths, GameAssetResolver.Format(path))
	end

	return table.concat(formattedPaths, " or ")
end

local function getRequiredGameAssetFolder(label: string, paths: { any }): Folder
	getGameAssetsFolder()

	local folder = GameAssetResolver.FindFirst(paths)
	if folder == nil or not folder:IsA("Folder") then
		Logger.Error(string.format(
			"[BossArenaRuntimeService] Missing %s assets folder in the boss arena place. Expected %s.",
			label,
			formatAssetPaths(paths)
		), 0)
	end

	return folder
end

local function getBossesFolder(): Folder
	return getRequiredGameAssetFolder("boss", BOSS_FOLDER_PATHS)
end

local function getBossArenasFolder(): Folder
	return getRequiredGameAssetFolder("arena", BOSS_ARENA_FOLDER_PATHS)
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

local function getUndergroundBossIntroCFrame(bossModel: Model, finalCFrame: CFrame): CFrame
	local _, boundingSize = bossModel:GetBoundingBox()
	local undergroundOffset = math.max(1, boundingSize.Y + BOSS_INTRO_UNDERGROUND_PADDING)
	return withPosition(finalCFrame, finalCFrame.Position - Vector3.new(0, undergroundOffset, 0))
end

local function anchorBossModelForIntro(bossModel: Model): { [BasePart]: boolean }
	local anchorStates = {}

	for _, descendant in ipairs(bossModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			anchorStates[descendant] = descendant.Anchored
			descendant.Anchored = true
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end

	return anchorStates
end

local function restoreBossAnchorStates(anchorStates: { [BasePart]: boolean }?)
	if anchorStates == nil then
		return
	end

	for part, wasAnchored in pairs(anchorStates) do
		if part.Parent ~= nil then
			part.Anchored = wasAnchored
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function collectArenaFloorRaycastRoots(arenaModel: Model): { Instance }
	local roots = {}
	for _, childName in ipairs({ "Visuals", "Map", "Floor", "Floors", "Ground" }) do
		local child = arenaModel:FindFirstChild(childName)
		if child then
			table.insert(roots, child)
		end
	end

	if #roots <= 0 then
		table.insert(roots, arenaModel)
	end

	return roots
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

function BossArenaRuntimeService:_notifyRosterStateChanged()
	local callbacks = {}

	for callback in pairs(self._rosterStateListeners) do
		table.insert(callbacks, callback)
	end

	for _, callback in ipairs(callbacks) do
		local ok, err = pcall(callback)
		if not ok then
			warnWithPrefix(string.format("Roster state callback failed: %s", tostring(err)))
		end
	end
end

function BossArenaRuntimeService:_buildBossHealthState(encounter: EncounterState?): BossHealthState?
	if encounter == nil then
		return nil
	end
	if encounter.timerPhase ~= "fight" and encounter.timerPhase ~= "return" then
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

function BossArenaRuntimeService:_buildBossTimerState(encounter: EncounterState?): BossTimerState?
	if encounter == nil then
		return nil
	end
	if encounter.timedOut == true then
		return nil
	end
	if encounter.timerPhase == "intro" then
		return {
			phase = "intro",
			startsAtServerTime = encounter.timerStartedAtServerTime,
			endsAtServerTime = encounter.timerEndsAtServerTime,
			durationSeconds = BOSS_INTRO_COUNTDOWN_SECONDS,
		}
	end
	if encounter.timerPhase == "intro_rise" then
		return nil
	end
	if encounter.timerPhase == "return" then
		local startsAtServerTime = encounter.returnCountdownStartedAtServerTime
		local endsAtServerTime = encounter.returnCountdownEndsAtServerTime
		if startsAtServerTime == nil or endsAtServerTime == nil then
			return nil
		end

		return {
			phase = "return",
			startsAtServerTime = startsAtServerTime,
			endsAtServerTime = endsAtServerTime,
			durationSeconds = BOSS_RESULTS_DURATION_SECONDS,
		}
	end
	if encounter.bossModel.Parent == nil or encounter.bossHumanoid.Parent == nil then
		return nil
	end
	if encounter.bossHumanoid.Health <= 0 then
		return nil
	end

	return {
		phase = "fight",
		startsAtServerTime = encounter.timerStartedAtServerTime,
		endsAtServerTime = encounter.timerEndsAtServerTime,
		durationSeconds = BOSS_ENCOUNTER_DURATION_SECONDS,
	}
end

local function copyRewardEntry(entry: any): BossResultRewardEntry?
	if typeof(entry) ~= "table" then
		return nil
	end

	local pieceId = if typeof(entry.pieceId) == "string" then entry.pieceId else ""
	local displayName = if typeof(entry.displayName) == "string" then entry.displayName else pieceId
	local setId = if typeof(entry.setId) == "string" then entry.setId else ""
	local displayRarity = if typeof(entry.displayRarity) == "string" then entry.displayRarity else "Basic"
	local displayOddsDenominator = math.max(1, math.floor(tonumber(entry.displayOddsDenominator) or 1))

	if pieceId == "" or displayName == "" then
		return nil
	end

	return {
		pieceId = pieceId,
		displayName = displayName,
		setId = setId,
		displayRarity = displayRarity,
		displayOddsDenominator = displayOddsDenominator,
		isBossPart = entry.isBossPart == true,
	}
end

local function copyRewardEntries(entries: any): { BossResultRewardEntry }
	local copiedEntries = {}
	if typeof(entries) ~= "table" then
		return copiedEntries
	end

	for _, entry in ipairs(entries) do
		local copiedEntry = copyRewardEntry(entry)
		if copiedEntry ~= nil then
			table.insert(copiedEntries, copiedEntry)
		end
	end

	return copiedEntries
end

local function countReplayReadyPlayers(encounter: EncounterState): number
	local count = 0
	for userId in pairs(encounter.replayReadyUserIds) do
		local resolvedUserId = math.floor(tonumber(userId) or 0)
		if resolvedUserId > 0 and encounter.rosterUserIds[resolvedUserId] == true and getPlayerByUserId(resolvedUserId) ~= nil then
			count += 1
		end
	end
	return count
end

function BossArenaRuntimeService:_beginResults(encounter: EncounterState, outcome: string)
	if encounter.timerPhase == "results" or encounter.resultsCompleted == true then
		return
	end

	local normalizedOutcome = if outcome == "victory" then "victory" else "defeat"
	local resultsStartedAt = os.clock()
	local resultsStartedAtServerTime = Workspace:GetServerTimeNow()

	encounter.timerPhase = "results"
	encounter.resultsOutcome = normalizedOutcome
	encounter.resultsStartedAt = resultsStartedAt
	encounter.resultsEndsAt = resultsStartedAt + BOSS_RESULTS_DURATION_SECONDS
	encounter.resultsStartedAtServerTime = resultsStartedAtServerTime
	encounter.resultsEndsAtServerTime = resultsStartedAtServerTime + BOSS_RESULTS_DURATION_SECONDS
	encounter.replayReadyUserIds = {}
	encounter.resultRewardsByUserId = {}

	self:_cancelActiveCast(encounter)
	encounter.currentTargetUserId = nil
	self:_setState(encounter, "Results")
	if normalizedOutcome == "victory" and encounter.rewardsGranted ~= true then
		encounter.rewardsGranted = true
		local rewardResults = BossArenaRewardService:GrantVictoryRewards(encounter)
		if next(rewardResults) == nil then
			warnWithPrefix(string.format("Boss '%s' victory granted no rewards.", encounter.bossId))
		end
		for userId, summary in pairs(rewardResults) do
			encounter.resultRewardsByUserId[userId] = copyRewardEntries(summary.grants)
		end
	end

	self:_notifyBossHealthStateChanged()
	self:_notifyBossTimerStateChanged()
	self:_notifyEncounterStateChanged()
	self:_notifyBossResultsStateChanged()
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

function BossArenaRuntimeService:_notifyBossTimerStateChanged()
	local timerState = self:GetBossTimerState()
	local callbacks = {}

	for callback in pairs(self._bossTimerStateListeners) do
		table.insert(callbacks, callback)
	end

	for _, callback in ipairs(callbacks) do
		local ok, err = pcall(callback, timerState)
		if not ok then
			warnWithPrefix(string.format("Boss timer callback failed: %s", tostring(err)))
		end
	end
end

function BossArenaRuntimeService:_notifyBossResultsStateChanged()
	local callbacks = {}

	for callback in pairs(self._bossResultsStateListeners) do
		table.insert(callbacks, callback)
	end

	for _, callback in ipairs(callbacks) do
		local ok, err = pcall(callback)
		if not ok then
			warnWithPrefix(string.format("Boss results callback failed: %s", tostring(err)))
		end
	end
end

function BossArenaRuntimeService:_notifyBossHitConfirmed(hitPayload: BossHitConfirmedPayload)
	local callbacks = {}

	for callback in pairs(self._bossHitConfirmedListeners) do
		table.insert(callbacks, callback)
	end

	for _, callback in ipairs(callbacks) do
		local ok, err = pcall(callback, hitPayload)
		if not ok then
			warnWithPrefix(string.format("Boss hit callback failed: %s", tostring(err)))
		end
	end
end

function BossArenaRuntimeService:_bindBossHealthSignals(encounter: EncounterState)
	disconnectConnections(encounter.bossHealthConnections)

	table.insert(encounter.bossHealthConnections, encounter.bossHumanoid.HealthChanged:Connect(function()
		if encounter.bossHumanoid.Health <= 0 then
			self:_beginResults(encounter, "victory")
		end
		self:_notifyBossHealthStateChanged()
		self:_notifyBossTimerStateChanged()
	end))
	table.insert(encounter.bossHealthConnections, encounter.bossHumanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		self:_notifyBossHealthStateChanged()
	end))
	table.insert(encounter.bossHealthConnections, encounter.bossModel.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			self:_notifyBossHealthStateChanged()
			self:_notifyBossTimerStateChanged()
		end
	end))
	table.insert(encounter.bossHealthConnections, encounter.bossHumanoid.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			self:_notifyBossHealthStateChanged()
			self:_notifyBossTimerStateChanged()
		end
	end))
end

function BossArenaRuntimeService:_cleanupBossIntroRiseMotion(encounter: EncounterState, restoreAnchors: boolean)
	if encounter.introRiseTween ~= nil then
		encounter.introRiseTween:Cancel()
		encounter.introRiseTween = nil
	end
	if encounter.introRiseCFrameConnection ~= nil then
		encounter.introRiseCFrameConnection:Disconnect()
		encounter.introRiseCFrameConnection = nil
	end
	if encounter.introRiseCompletedConnection ~= nil then
		encounter.introRiseCompletedConnection:Disconnect()
		encounter.introRiseCompletedConnection = nil
	end
	if encounter.introRiseCFrameValue ~= nil then
		encounter.introRiseCFrameValue:Destroy()
		encounter.introRiseCFrameValue = nil
	end
	if restoreAnchors then
		restoreBossAnchorStates(encounter.introRiseAnchorStates)
		encounter.introRiseAnchorStates = nil
	end
end

function BossArenaRuntimeService:_activateBossFight(encounter: EncounterState)
	if self._encounter ~= encounter then
		return
	end
	if encounter.timerPhase ~= "intro_rise" then
		return
	end

	self:_cleanupBossIntroRiseMotion(encounter, true)

	local finalCFrame = encounter.introFinalCFrame
	if finalCFrame ~= nil and encounter.bossModel.Parent ~= nil then
		encounter.bossModel:PivotTo(finalCFrame)
	end
	BossPhysicsStabilizer.Recover(encounter.bossModel, encounter.bossHumanoid)

	local activatedAt = os.clock()
	local activatedAtServerTime = Workspace:GetServerTimeNow()
	encounter.timerPhase = "fight"
	encounter.spawnedAt = activatedAt
	encounter.timerStartedAt = activatedAt
	encounter.timerEndsAt = activatedAt + BOSS_ENCOUNTER_DURATION_SECONDS
	encounter.timerStartedAtServerTime = activatedAtServerTime
	encounter.timerEndsAtServerTime = activatedAtServerTime + BOSS_ENCOUNTER_DURATION_SECONDS
	encounter.nextAbilityAvailableAt = activatedAt + BOSS_ATTACK_SPAWN_DELAY_SECONDS
	encounter.lastRetargetAt = 0
	encounter.lastMoveCommandAt = 0
	encounter.currentTargetUserId = nil

	encounter.bossModel:SetAttribute(BOSS_INVULNERABLE_ATTRIBUTE, false)
	encounter.bossHumanoid.WalkSpeed = encounter.bossDefinition.walkSpeed
	encounter.bossHumanoid.AutoRotate = true
	self:_setServerNetworkOwnership(encounter.bossModel)
	if encounter.animationController then
		encounter.animationController:SetLocomotionSuppressed(false)
	end
	self:_setState(encounter, "Idle")

	self:_notifyBossHealthStateChanged()
	self:_notifyBossTimerStateChanged()
	self:_notifyEncounterStateChanged()

	Logger.Print(string.format(
		"[BossArenaRuntimeService] Boss '%s' intro complete; fight timer started for %d second(s).",
		encounter.bossId,
		BOSS_ENCOUNTER_DURATION_SECONDS
	))
end

function BossArenaRuntimeService:_beginBossIntroRise(encounter: EncounterState)
	if self._encounter ~= encounter then
		return
	end
	if encounter.timerPhase ~= "intro" then
		return
	end

	local finalCFrame = encounter.introFinalCFrame
	if finalCFrame == nil or encounter.bossModel.Parent == nil then
		encounter.timerPhase = "intro_rise"
		self:_activateBossFight(encounter)
		return
	end

	encounter.timerPhase = "intro_rise"
	self:_setState(encounter, "IntroRise")
	self:_notifyBossTimerStateChanged()
	self:_notifyEncounterStateChanged()

	local cframeValue = Instance.new("CFrameValue")
	cframeValue.Value = encounter.bossModel:GetPivot()
	encounter.introRiseCFrameValue = cframeValue
	encounter.introRiseCFrameConnection = cframeValue:GetPropertyChangedSignal("Value"):Connect(function()
		if self._encounter ~= encounter or encounter.bossModel.Parent == nil then
			return
		end

		encounter.bossModel:PivotTo(cframeValue.Value)
	end)

	local tween = TweenService:Create(
		cframeValue,
		TweenInfo.new(BOSS_INTRO_RISE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Value = finalCFrame,
		}
	)
	encounter.introRiseTween = tween
	encounter.introRiseCompletedConnection = tween.Completed:Connect(function(playbackState: Enum.PlaybackState)
		if self._encounter ~= encounter then
			return
		end
		if playbackState ~= Enum.PlaybackState.Completed then
			return
		end

		self:_activateBossFight(encounter)
	end)
	tween:Play()
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
	self:_cancelActiveCast(encounter)
	self:_cleanupBossIntroRiseMotion(encounter, true)
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
	self:_notifyBossTimerStateChanged()
	self:_notifyEncounterStateChanged()
	self:_notifyRosterStateChanged()
	self:_notifyBossResultsStateChanged()
end

function BossArenaRuntimeService:_resolveBossSourceModel(bossId: string): Model
	local bossesFolder = getBossesFolder()
	local bossModel = bossesFolder:FindFirstChild(bossId)
	if bossModel == nil then
		Logger.Error(string.format(
			"[BossArenaRuntimeService] Missing boss model '%s' under %s.",
			bossId,
			bossesFolder:GetFullName()
		), 0)
	end
	if not bossModel:IsA("Model") then
		Logger.Error(string.format(
			"[BossArenaRuntimeService] %s.%s must be a Model.",
			bossesFolder:GetFullName(),
			bossId
		), 0)
	end

	return bossModel
end

function BossArenaRuntimeService:_resolveArenaSourceModel(arenaDefinition: any): Model
	local bossArenasFolder = getBossArenasFolder()
	local arenaModel = bossArenasFolder:FindFirstChild(arenaDefinition.assetName)
	if arenaModel == nil then
		Logger.Error(string.format(
			"[BossArenaRuntimeService] Missing arena model '%s' under %s.",
			arenaDefinition.assetName,
			bossArenasFolder:GetFullName()
		), 0)
	end
	if not arenaModel:IsA("Model") then
		Logger.Error(string.format(
			"[BossArenaRuntimeService] %s.%s must be a Model.",
			bossArenasFolder:GetFullName(),
			arenaDefinition.assetName
		), 0)
	end

	return arenaModel
end

function BossArenaRuntimeService:_cloneArenaLighting(): { Instance }
	local appliedInstances = {}
	local bossArenasFolder = getBossArenasFolder()
	local lightingFolder = bossArenasFolder:FindFirstChild(ARENA_LIGHTING_FOLDER_NAME)

	if lightingFolder == nil then
		return appliedInstances
	end
	if not lightingFolder:IsA("Folder") then
		Logger.Error(string.format(
			"[BossArenaRuntimeService] %s.%s must be a Folder.",
			bossArenasFolder:GetFullName(),
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
		self:_notifyRosterStateChanged()
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

function BossArenaRuntimeService:_tryPositionCurrentRosterCharacter(
	encounter: EncounterState,
	player: Player,
	character: Model
): boolean
	if self._encounter ~= encounter then
		return false
	end
	if player.Parent ~= Players then
		return false
	end
	if encounter.rosterUserIds[player.UserId] ~= true then
		return false
	end
	if player.Character ~= character then
		return false
	end

	return self:_positionPlayerInArena(encounter, player)
end

function BossArenaRuntimeService:_scheduleRosterCharacterPlacement(player: Player, character: Model)
	local scheduledEncounter = self._encounter
	if scheduledEncounter == nil then
		return
	end
	if scheduledEncounter.rosterUserIds[player.UserId] ~= true then
		return
	end

	local nextToken = (self._characterPlacementTokens[player] or 0) + 1
	self._characterPlacementTokens[player] = nextToken

	task.spawn(function()
		for _ = 1, CHARACTER_PLACEMENT_RETRY_COUNT do
			if self._characterPlacementTokens[player] ~= nextToken then
				return
			end

			if self._encounter ~= scheduledEncounter then
				return
			end
			if scheduledEncounter.rosterUserIds[player.UserId] ~= true then
				return
			end
			if player.Character ~= character then
				return
			end

			if self:_tryPositionCurrentRosterCharacter(scheduledEncounter, player, character) then
				return
			end

			task.wait(CHARACTER_PLACEMENT_RETRY_INTERVAL_SECONDS)
		end
	end)
end

function BossArenaRuntimeService:_bindPlayerCharacterPlacement(player: Player)
	if self._playerCharacterConnections[player] ~= nil then
		return
	end

	self._playerCharacterConnections[player] = player.CharacterAdded:Connect(function(character)
		self:_scheduleRosterCharacterPlacement(player, character)
	end)
end

function BossArenaRuntimeService:_disconnectPlayerCharacterPlacement(player: Player)
	local connection = self._playerCharacterConnections[player]
	if connection ~= nil then
		connection:Disconnect()
		self._playerCharacterConnections[player] = nil
	end

	self._characterPlacementTokens[player] = nil
end

function BossArenaRuntimeService:_spawnBossEncounter(payload: any)
	self:_clearEncounter(nil)

	local bossId = payload.bossName
	local bossDefinition = Bosses.GetDefinition(bossId)
	if bossDefinition == nil then
		Logger.Error(string.format(
			"[BossArenaRuntimeService] No local boss definition exists for '%s'.",
			bossId
		), 0)
	end

	local arenaId = payload.arenaId
	if arenaId ~= bossDefinition.arenaId then
		Logger.Error(string.format(
			"[BossArenaRuntimeService] Payload arena '%s' does not match boss '%s' arena '%s'.",
			tostring(arenaId),
			bossId,
			bossDefinition.arenaId
		), 0)
	end

	local arenaDefinition = BossArenas.GetDefinition(arenaId)
	if arenaDefinition == nil then
		Logger.Error(string.format(
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
		Logger.Error(string.format(
			"[BossArenaRuntimeService] Arena '%s' %s.",
			arenaId,
			tostring(bossSpawnError)
		), 0)
	end

	-- Player placement is intentionally plural and separate from boss placement.
	local playerSpawns = collectNamedBaseParts(arenaModel, arenaDefinition.playerSpawnName)
	if #playerSpawns <= 0 then
		arenaModel:Destroy()
		Logger.Error(string.format(
			"[BossArenaRuntimeService] Arena '%s' is missing BaseParts named '%s'.",
			arenaId,
			arenaDefinition.playerSpawnName
		), 0)
	end

	local appliedLightingInstances = self:_cloneArenaLighting()
	local aggroRadius, leashRadius = self:_resolveArenaRadii(bossDefinition, bossSpawn, arenaModel)
	local encounterScaling = BossEncounterScaling.GetForPartySize(resolveEncounterPartySize(payload))

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
		Logger.Error(string.format(
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
		Logger.Error(string.format(
			"[BossArenaRuntimeService] Boss model '%s' must contain a root BasePart.",
			bossId
		), 0)
	end

	applyBossBodyCollisionGroup(bossModel)
	BossPhysicsStabilizer.Apply(bossModel, bossHumanoid, bossRootPart)

	local bossSpawnCFrame = getFeetAlignedBossSpawnCFrame(bossSpawn.CFrame, bossHumanoid, bossRootPart)
	bossModel:PivotTo(bossSpawnCFrame)
	BossPhysicsStabilizer.Recover(bossModel, bossHumanoid)
	createBossHitboxCollider(bossModel, bossRootPart)
	local bossIntroSpawnCFrame = getUndergroundBossIntroCFrame(bossModel, bossSpawnCFrame)
	local introRiseAnchorStates = anchorBossModelForIntro(bossModel)
	bossModel:PivotTo(bossIntroSpawnCFrame)
	BossPhysicsStabilizer.ResetMotion(bossModel)
	applyBossBaseHealth(bossHumanoid, bossDefinition.baseHealth)
	applyBossHealthScaling(bossHumanoid, encounterScaling.healthMultiplier)

	bossModel:SetAttribute(BOSS_INVULNERABLE_ATTRIBUTE, true)
	bossHumanoid.WalkSpeed = 0
	bossHumanoid.AutoRotate = false

	local animationController = BossAnimationController.Attach(bossModel, bossHumanoid, {
		scaleMultiplier = bossDefinition.scaleMultiplier,
	})
	animationController:SetLocomotionSuppressed(true)

	local spawnedAt = os.clock()
	local timerStartedAtServerTime = Workspace:GetServerTimeNow()
	self._encounter = {
		payload = payload,
		bossId = bossId,
		arenaId = arenaId,
		bossDefinition = bossDefinition,
		encounterScaling = encounterScaling,
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
		damageByUserId = {},
		rewardEligibleDamageThreshold = math.max(0, bossHumanoid.MaxHealth * BOSS_REWARD_DAMAGE_CONTRIBUTION_RATIO),
		state = "Spawning",
		currentTargetUserId = nil,
		lastRetargetAt = 0,
		lastMoveCommandAt = 0,
		nextAbilityAvailableAt = math.huge,
		cooldowns = {},
		rng = Random.new(),
		spawnedAt = spawnedAt,
		timerStartedAt = spawnedAt,
		timerEndsAt = spawnedAt + BOSS_INTRO_COUNTDOWN_SECONDS,
		timerStartedAtServerTime = timerStartedAtServerTime,
		timerEndsAtServerTime = timerStartedAtServerTime + BOSS_INTRO_COUNTDOWN_SECONDS,
		timerPhase = "intro",
		introFinalCFrame = bossSpawnCFrame,
		introRiseTween = nil,
		introRiseCFrameValue = nil,
		introRiseCFrameConnection = nil,
		introRiseCompletedConnection = nil,
		introRiseAnchorStates = introRiseAnchorStates,
		rewardsGranted = false,
		returnCountdownEndsAt = nil,
		returnCountdownStartedAtServerTime = nil,
		returnCountdownEndsAtServerTime = nil,
		resultsOutcome = nil,
		resultsStartedAt = nil,
		resultsEndsAt = nil,
		resultsStartedAtServerTime = nil,
		resultsEndsAtServerTime = nil,
		resultRewardsByUserId = {},
		replayReadyUserIds = {},
		resultsCompleted = false,
		timedOut = false,
		activeCast = nil,
		bossHealthConnections = {},
	}
	self:_bindBossHealthSignals(self._encounter)
	self:_syncDamageLeaderstats(self._encounter)

	self:_positionQueuedPlayersIfNeeded(self._encounter)
	self:_setState(self._encounter, "Intro")

	Logger.Print(string.format(
		"[BossArenaRuntimeService] Spawned boss '%s' in arena '%s' from BossSpawn '%s' at %.2fx with aggro %.1f and leash %.1f; intro countdown started.",
		bossId,
		arenaId,
		bossSpawn:GetFullName(),
		bossDefinition.scaleMultiplier,
		aggroRadius,
		leashRadius
	))

	self:_notifyBossHealthStateChanged()
	self:_notifyBossTimerStateChanged()
	self:_notifyEncounterStateChanged()
	self:_notifyRosterStateChanged()
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
	if encounter.timerPhase == "results" then
		return nil
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

	local wasRosterMember = encounter.rosterUserIds[player.UserId] == true
	encounter.rosterUserIds[player.UserId] = true
	self:_positionPlayerInArena(encounter, player)
	if not wasRosterMember then
		self:_notifyRosterStateChanged()
	end
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
	targetUserId: number?,
	castId: string?,
	emitPresentation: ((action: string, payload: { [string]: any }?) -> ())?
)
	local targetPlayer = getPlayerByUserId(targetUserId)
	local targetCharacter = if targetPlayer then targetPlayer.Character else nil
	local targetHumanoid = getCharacterHumanoid(targetCharacter)
	local targetRootPart = if targetCharacter then getModelRootPart(targetCharacter) else nil

	return {
		now = os.clock(),
		castId = castId or "",
		bossDefinition = encounter.bossDefinition,
		encounterScaling = encounter.encounterScaling,
		move = moveDefinition,
		bossModel = encounter.bossModel,
		bossHumanoid = encounter.bossHumanoid,
		bossRootPart = encounter.bossRootPart,
		bossState = encounter.state,
		homePosition = encounter.homePosition,
		arenaModel = encounter.arenaModel,
		floorRaycastRoots = collectArenaFloorRaycastRoots(encounter.arenaModel),
		targetPlayer = targetPlayer,
		targetCharacter = targetCharacter,
		targetHumanoid = targetHumanoid,
		targetRootPart = targetRootPart,
		distanceToTarget = if targetRootPart then (targetRootPart.Position - encounter.bossRootPart.Position).Magnitude else nil,
		aliveTargets = aliveTargets,
		EmitPresentation = emitPresentation or function() end,
	}
end

function BossArenaRuntimeService:_notifyMovePresentation(payload: any)
	for callback in pairs(self._movePresentationListeners) do
		local ok, err = pcall(callback, payload)
		if not ok then
			warnWithPrefix(string.format("Boss move presentation callback failed: %s", tostring(err)))
		end
	end
end

function BossArenaRuntimeService:_stampCastEndTimers(encounter: EncounterState, activeCast: CastState, endedAt: number)
	local moveCooldownEndsAt = endedAt + math.max(0, tonumber(activeCast.move.cooldownSeconds) or 0)
	local existingMoveCooldownEndsAt = tonumber(encounter.cooldowns[activeCast.move.id]) or 0
	encounter.cooldowns[activeCast.move.id] = math.max(existingMoveCooldownEndsAt, moveCooldownEndsAt)

	local nextAbilityAvailableAt = endedAt + math.max(0, tonumber(encounter.bossDefinition.abilityCadenceSeconds) or 0)
	encounter.nextAbilityAvailableAt = math.max(encounter.nextAbilityAvailableAt, nextAbilityAvailableAt)
end

function BossArenaRuntimeService:_finishActiveCast(encounter: EncounterState)
	local activeCast = encounter.activeCast
	if activeCast == nil then
		return
	end

	self:_stampCastEndTimers(encounter, activeCast, os.clock())
	encounter.activeCast = nil
	BossPhysicsStabilizer.Recover(encounter.bossModel, encounter.bossHumanoid)
end

function BossArenaRuntimeService:_cancelActiveCast(encounter: EncounterState)
	local activeCast = encounter.activeCast
	if activeCast == nil then
		return
	end

	self:_stampCastEndTimers(encounter, activeCast, os.clock())
	encounter.activeCast = nil
	invokeLifecycleCancel(activeCast.move.id, activeCast.lifecycleHandle)
	BossPhysicsStabilizer.Recover(encounter.bossModel, encounter.bossHumanoid)
end

function BossArenaRuntimeService:_getMoveSelectionWeight(moveDefinition: any, context: any): number?
	local canUseOk, canUse, reason = pcall(function()
		return moveDefinition.module.CanUse(context)
	end)
	if not canUseOk then
		warnWithPrefix(string.format(
			"Boss move '%s' CanUse failed: %s",
			moveDefinition.id,
			tostring(canUse)
		))
		return nil
	end
	if canUse ~= true then
		if typeof(reason) == "string" and reason ~= "" then
			return nil
		end
		return nil
	end

	local effectiveWeight = tonumber(moveDefinition.weight) or 0
	local getSelectionWeight = moveDefinition.module.GetSelectionWeight
	if typeof(getSelectionWeight) == "function" then
		local selectionWeightOk, selectionWeight = pcall(getSelectionWeight, context)
		if not selectionWeightOk then
			warnWithPrefix(string.format(
				"Boss move '%s' GetSelectionWeight failed: %s",
				moveDefinition.id,
				tostring(selectionWeight)
			))
			return nil
		end

		effectiveWeight *= tonumber(selectionWeight) or 0
	end

	if effectiveWeight <= 0 then
		return nil
	end

	return effectiveWeight
end

function BossArenaRuntimeService:_startCast(
	encounter: EncounterState,
	moveDefinition: any,
	targetContext: AliveTargetContext?,
	aliveTargets: { AliveTargetContext }
)
	local now = os.clock()
	local castId = HttpService:GenerateGUID(false)
	local castState: CastState = {
		castId = castId,
		move = moveDefinition,
		startedAt = now,
		executeAt = now + moveDefinition.castTimeSeconds,
		recoveryEndsAt = now + moveDefinition.castTimeSeconds + moveDefinition.recoverySeconds,
		rootDuringCast = moveDefinition.rootDuringCast == true,
		executed = false,
		targetUserId = if targetContext then targetContext.player.UserId else nil,
		lifecycleHandle = nil,
		completedAt = nil,
	}

	encounter.activeCast = castState
	self:_setState(encounter, "Casting")

	if shouldFaceTargetOnCast(moveDefinition) then
		BossFacing.FaceModelTowardTarget(
			encounter.bossModel,
			encounter.bossRootPart,
			resolveCastTargetRootPart(targetContext)
		)
		BossPhysicsStabilizer.Recover(encounter.bossModel, encounter.bossHumanoid)
	end

	local function emitPresentation(action: string, payload: { [string]: any }?)
		self:_notifyMovePresentation({
			castId = castState.castId,
			bossModel = encounter.bossModel,
			bossId = encounter.bossId,
			moveId = moveDefinition.id,
			moduleId = moveDefinition.moduleId,
			action = action,
			payload = payload,
			serverTime = Workspace:GetServerTimeNow(),
		})
	end

	local previewContext = self:_buildMoveContext(
		encounter,
		moveDefinition,
		aliveTargets,
		castState.targetUserId,
		castState.castId,
		emitPresentation
	)
	Logger.Print(string.format(
		"[BossArenaRuntimeService] Boss '%s' in arena '%s' started cast '%s' targeting %s.",
		encounter.bossId,
		encounter.arenaId,
		moveDefinition.id,
		if previewContext.targetPlayer then previewContext.targetPlayer.Name else "arena"
	))

	local startCast = moveDefinition.module.StartCast
	if typeof(startCast) == "function" then
		local startCastOk, lifecycleHandleOrError = pcall(startCast, previewContext)
		if not startCastOk then
			warnWithPrefix(string.format(
				"Boss move '%s' StartCast failed: %s",
				moveDefinition.id,
				tostring(lifecycleHandleOrError)
			))
		else
			if typeof(lifecycleHandleOrError) == "table" and typeof(lifecycleHandleOrError.IsComplete) == "function" then
				castState.lifecycleHandle = lifecycleHandleOrError
			elseif lifecycleHandleOrError ~= nil then
				warnWithPrefix(string.format(
					"Boss move '%s' StartCast returned an invalid lifecycle handle.",
					moveDefinition.id
				))
			end
			castState.executed = true
		end
	end
end

function BossArenaRuntimeService:_emitMoveStub(
	encounter: EncounterState,
	moveDefinition: any,
	aliveTargets: { AliveTargetContext },
	targetUserId: number?
)
	local context = self:_buildMoveContext(encounter, moveDefinition, aliveTargets, targetUserId, "", nil)
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

	Logger.Print(string.format("[BossArenaRuntimeService] MoveStub %s", serializedPayload))
end

function BossArenaRuntimeService:_updateCast(encounter: EncounterState, aliveTargets: { AliveTargetContext })
	local activeCast = encounter.activeCast
	if activeCast == nil then
		return
	end

	local now = os.clock()

	if activeCast.lifecycleHandle ~= nil then
		if activeCast.completedAt == nil then
			if not invokeLifecycleIsComplete(activeCast.move.id, activeCast.lifecycleHandle) then
				return
			end

			activeCast.completedAt = now
			local recoveryEndsAt = invokeLifecycleRecoveryEndsAt(activeCast.move.id, activeCast.lifecycleHandle)
			if recoveryEndsAt ~= nil and recoveryEndsAt > now then
				activeCast.recoveryEndsAt = recoveryEndsAt
			else
				self:_finishActiveCast(encounter)
				return
			end
		end

		if now >= activeCast.recoveryEndsAt then
			self:_finishActiveCast(encounter)
		end
		return
	end

	if not activeCast.executed and now >= activeCast.executeAt then
		self:_emitMoveStub(encounter, activeCast.move, aliveTargets, activeCast.targetUserId)
		activeCast.executed = true
	end

	if now >= activeCast.recoveryEndsAt then
		self:_finishActiveCast(encounter)
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

	if activeCast ~= nil then
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
	local now = os.clock()
	if now - encounter.spawnedAt < BOSS_ATTACK_SPAWN_DELAY_SECONDS then
		return
	end
	if now < encounter.nextAbilityAvailableAt then
		return
	end

	local validMoves = {}

	for _, moveDefinition in ipairs(encounter.bossDefinition.moves) do
		local cooldownEndsAt = encounter.cooldowns[moveDefinition.id] or 0
		if cooldownEndsAt > now then
			continue
		end

		local context = self:_buildMoveContext(
			encounter,
			moveDefinition,
			aliveTargets,
			if targetContext then targetContext.player.UserId else nil,
			"",
			nil
		)
		local effectiveWeight = self:_getMoveSelectionWeight(moveDefinition, context)
		if effectiveWeight ~= nil then
			table.insert(validMoves, {
				move = moveDefinition,
				context = context,
				effectiveWeight = effectiveWeight,
			})
		end
	end

	if #validMoves <= 0 then
		return
	end

	local selectedMove = chooseWeightedMove(validMoves, encounter.rng)
	self:_startCast(encounter, selectedMove.move, targetContext, aliveTargets)
end

function BossArenaRuntimeService:_collectOnlineRosterPlayers(encounter: EncounterState): { Player }
	local rosterPlayers = {}

	for _, player in ipairs(Players:GetPlayers()) do
		if encounter.rosterUserIds[player.UserId] == true then
			table.insert(rosterPlayers, player)
		end
	end

	return rosterPlayers
end

function BossArenaRuntimeService:_getBossLobbyReturnPlaceId(): number
	local route = PlaceProfile.GetRoutes()[BOSS_TIMEOUT_RETURN_ROUTE_ID]
	if typeof(route) ~= "table" then
		return 0
	end

	return math.max(0, math.floor(tonumber(route.placeId) or 0))
end

function BossArenaRuntimeService:_queuePlayersReturnToBossLobby(players: { Player }, reasonLabel: string): number
	local destinationPlaceId = self:_getBossLobbyReturnPlaceId()
	local returnPlayers = {}

	for _, player in ipairs(players) do
		if player.Parent == Players then
			table.insert(returnPlayers, player)
		end
	end

	if destinationPlaceId <= 0 then
		warnWithPrefix(string.format("%s, but route '%s' is not configured.", reasonLabel, BOSS_TIMEOUT_RETURN_ROUTE_ID))
	elseif #returnPlayers > 0 then
		task.spawn(function()
			local teleportOk, teleportError = pcall(function()
				TeleportService:TeleportAsync(destinationPlaceId, returnPlayers)
			end)
			if not teleportOk then
				warnWithPrefix(string.format(
					"%s teleport to place %d failed for %d player(s): %s",
					reasonLabel,
					destinationPlaceId,
					#returnPlayers,
					tostring(teleportError)
				))
			end
		end)
	end

	return #returnPlayers
end

function BossArenaRuntimeService:_queueRosterReturnToBossLobby(
	encounter: EncounterState,
	reasonLabel: string,
	reasonDescription: string
): number
	local rosterPlayers = self:_collectOnlineRosterPlayers(encounter)
	local destinationPlaceId = self:_getBossLobbyReturnPlaceId()

	if destinationPlaceId <= 0 then
		warnWithPrefix(string.format("%s, but route '%s' is not configured.", reasonLabel, BOSS_TIMEOUT_RETURN_ROUTE_ID))
	elseif #rosterPlayers > 0 then
		task.spawn(function()
			local teleportOk, teleportError = pcall(function()
				TeleportService:TeleportAsync(destinationPlaceId, rosterPlayers)
			end)
			if not teleportOk then
				warnWithPrefix(string.format(
					"%s teleport to place %d failed for %d player(s): %s",
					reasonLabel,
					destinationPlaceId,
					#rosterPlayers,
					tostring(teleportError)
				))
			end
		end)
	end

	self:_clearEncounter(string.format("%s Returning %d roster player(s) to boss lobby.", reasonDescription, #rosterPlayers))
	return #rosterPlayers
end

function BossArenaRuntimeService:_timeoutEncounter(encounter: EncounterState)
	if encounter.timedOut == true then
		return
	end

	encounter.timedOut = true
	self:_beginResults(encounter, "defeat")
end

function BossArenaRuntimeService:_collectResultsSplit(encounter: EncounterState): ({ Player }, { Player }, { number })
	local readyPlayers = {}
	local returnPlayers = {}
	local readyUserIds = {}
	local seenUserIds = {}

	local function appendUserId(userId: number)
		local resolvedUserId = math.floor(tonumber(userId) or 0)
		if resolvedUserId <= 0 or seenUserIds[resolvedUserId] == true then
			return
		end
		seenUserIds[resolvedUserId] = true

		if encounter.rosterUserIds[resolvedUserId] ~= true then
			return
		end

		local player = getPlayerByUserId(resolvedUserId)
		if player == nil then
			return
		end

		if encounter.replayReadyUserIds[resolvedUserId] == true then
			table.insert(readyPlayers, player)
			table.insert(readyUserIds, resolvedUserId)
		else
			table.insert(returnPlayers, player)
		end
	end

	for _, userId in ipairs(encounter.rosterOrder) do
		appendUserId(userId)
	end
	for userId in pairs(encounter.rosterUserIds) do
		appendUserId(userId)
	end

	return readyPlayers, returnPlayers, readyUserIds
end

local function filterPotionEffectsByUserIds(potionEffectsByUserId: any, readyUserIds: { number }): any
	if typeof(potionEffectsByUserId) ~= "table" then
		return nil
	end

	local filtered = {}
	for _, userId in ipairs(readyUserIds) do
		local key = tostring(userId)
		local snapshot = potionEffectsByUserId[key]
		if typeof(snapshot) == "table" then
			filtered[key] = snapshot
		end
	end

	return if next(filtered) ~= nil then filtered else nil
end

function BossArenaRuntimeService:_completeResults(encounter: EncounterState)
	if encounter.resultsCompleted == true then
		return
	end
	encounter.resultsCompleted = true

	local readyPlayers, returnPlayers, readyUserIds = self:_collectResultsSplit(encounter)
	self:_queuePlayersReturnToBossLobby(returnPlayers, "Boss results return")

	if #readyPlayers <= 0 then
		self:_clearEncounter(string.format(
			"Boss results finished for '%s' with no replay-ready players. Returning %d player(s) to boss lobby.",
			encounter.bossId,
			#returnPlayers
		))
		return
	end

	local replayPayload, payloadError = BossQueueTeleportPayload.Build(
		encounter.bossId,
		encounter.arenaId,
		tostring(encounter.payload and encounter.payload.portalId or "replay"),
		readyUserIds,
		os.time(),
		filterPotionEffectsByUserIds(encounter.payload and encounter.payload.potionEffectsByUserId, readyUserIds)
	)
	if replayPayload == nil then
		warnWithPrefix(payloadError or "Failed to build replay boss payload.")
		self:_queuePlayersReturnToBossLobby(readyPlayers, "Boss replay fallback return")
		self:_clearEncounter(string.format("Boss replay failed for '%s'; returning ready players to lobby.", encounter.bossId))
		return
	end

	local bossId = encounter.bossId
	local readyCount = #readyPlayers
	self:_clearEncounter(string.format(
		"Boss results finished for '%s'. Replaying with %d ready player(s); returning %d player(s) to boss lobby.",
		bossId,
		readyCount,
		#returnPlayers
	))
	self:_spawnBossEncounter(replayPayload)
end

function BossArenaRuntimeService:_heartbeat()
	if self._encounter == nil then
		self:_tryInitializeEncounterFromExistingPlayers()
		return
	end

	local encounter = self._encounter
	if encounter == nil then
		return
	end

	if encounter.timerPhase ~= "results" then
		self:_refreshRosterFromPlayers()
	end

	self:_syncDamageLeaderstats(encounter)
	if encounter.timerPhase ~= "results" then
		self:_positionQueuedPlayersIfNeeded(encounter)
	end

	if encounter.arenaModel.Parent == nil then
		self:_clearEncounter("Active arena model was removed from Workspace.")
		return
	end
	if encounter.bossModel.Parent == nil then
		self:_clearEncounter("Active boss model was removed from Workspace.")
		return
	end
	if encounter.timerPhase == "intro" then
		if os.clock() >= encounter.timerEndsAt then
			self:_beginBossIntroRise(encounter)
		end
		return
	end
	if encounter.timerPhase == "intro_rise" then
		return
	end
	if encounter.timerPhase == "return" then
		local returnCountdownEndsAt = encounter.returnCountdownEndsAt
		if returnCountdownEndsAt ~= nil and os.clock() >= returnCountdownEndsAt then
			self:_completeResults(encounter)
		end
		return
	end
	if encounter.timerPhase == "results" then
		local resultsEndsAt = encounter.resultsEndsAt
		if resultsEndsAt ~= nil and os.clock() >= resultsEndsAt then
			self:_completeResults(encounter)
		end
		return
	end
	if encounter.bossHumanoid.Health <= 0 then
		self:_beginResults(encounter, "victory")
		return
	end
	if os.clock() >= encounter.timerEndsAt then
		self:_timeoutEncounter(encounter)
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

	Logger.Print("[BossArenaRuntimeService] Ready for boss arena encounter initialization.")
end

function BossArenaRuntimeService:OnPlayerAdded(player: Player)
	if not isEnabledForPlace() then
		return
	end

	self:_bindPlayerCharacterPlacement(player)
	self:_tryInitializeEncounterFromPlayer(player)
	task.defer(function()
		local encounter = self._encounter
		if encounter then
			self:_syncDamageLeaderstats(encounter)
		elseif player.Parent == Players then
			setDamageLeaderstat(player, 0)
		end
	end)
end

function BossArenaRuntimeService:OnPlayerRemoving(player: Player)
	self:_disconnectPlayerCharacterPlacement(player)

	local encounter = self._encounter
	if encounter == nil then
		return
	end

	encounter.rosterUserIds[player.UserId] = nil
	encounter.replayReadyUserIds[player.UserId] = nil
	encounter.placedCharacters[player.UserId] = nil
	if encounter.currentTargetUserId == player.UserId then
		encounter.currentTargetUserId = nil
	end
	self:_notifyRosterStateChanged()
	self:_notifyBossResultsStateChanged()
end

function BossArenaRuntimeService:HasActiveEncounter(): boolean
	return self._encounter ~= nil
end

function BossArenaRuntimeService:GetActiveRosterUserIds(): { number }
	local encounter = self._encounter
	if encounter == nil then
		return {}
	end

	local rosterUserIds = {}
	local seenUserIds = {}

	for _, userId in ipairs(encounter.rosterOrder) do
		local resolvedUserId = math.floor(tonumber(userId) or 0)
		if resolvedUserId <= 0 or seenUserIds[resolvedUserId] == true then
			continue
		end

		local player = getPlayerByUserId(resolvedUserId)
		if player ~= nil and encounter.rosterUserIds[resolvedUserId] == true then
			seenUserIds[resolvedUserId] = true
			table.insert(rosterUserIds, resolvedUserId)
		end
	end

	for userId in pairs(encounter.rosterUserIds) do
		local resolvedUserId = math.floor(tonumber(userId) or 0)
		if resolvedUserId <= 0 or seenUserIds[resolvedUserId] == true then
			continue
		end

		local player = getPlayerByUserId(resolvedUserId)
		if player ~= nil then
			seenUserIds[resolvedUserId] = true
			table.insert(rosterUserIds, resolvedUserId)
		end
	end

	return rosterUserIds
end

function BossArenaRuntimeService:RequestPlayerAbandon(player: Player): (boolean, string?)
	if not isEnabledForPlace() then
		return false, "Boss arena runtime is not enabled for this place."
	end
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "A valid player is required."
	end

	local encounter = self._encounter
	if encounter == nil then
		return false, "There is no active boss encounter."
	end
	if encounter.rosterUserIds[player.UserId] ~= true then
		return false, "You are not in this boss encounter."
	end
	if encounter.timedOut == true or (encounter.timerPhase ~= "intro" and encounter.timerPhase ~= "fight") then
		return false, "This boss encounter cannot be abandoned right now."
	end

	local destinationPlaceId = self:_getBossLobbyReturnPlaceId()
	if destinationPlaceId <= 0 then
		return false, "Boss lobby return route is not configured."
	end

	local oldRosterSize = countRosterMembers(encounter)
	encounter.rosterUserIds[player.UserId] = nil
	encounter.placedCharacters[player.UserId] = nil
	encounter.damageByUserId[player.UserId] = nil
	if encounter.currentTargetUserId == player.UserId then
		encounter.currentTargetUserId = nil
	end
	if encounter.activeCast ~= nil and encounter.activeCast.targetUserId == player.UserId then
		self:_cancelActiveCast(encounter)
	end
	setDamageLeaderstat(player, 0)

	local remainingRosterSize = countRosterMembers(encounter)
	if remainingRosterSize > 0 and oldRosterSize > remainingRosterSize then
		local oldScaling = BossEncounterScaling.GetForPartySize(oldRosterSize)
		local newScaling = BossEncounterScaling.GetForPartySize(remainingRosterSize)
		local oldHealthMultiplier = math.max(0.001, tonumber(oldScaling.healthMultiplier) or 1)
		local newHealthMultiplier = math.max(0.001, tonumber(newScaling.healthMultiplier) or 1)

		encounter.encounterScaling = newScaling
		applyBossHealthRatio(encounter.bossHumanoid, newHealthMultiplier / oldHealthMultiplier)
		encounter.rewardEligibleDamageThreshold = math.max(
			0,
			encounter.bossHumanoid.MaxHealth * BOSS_REWARD_DAMAGE_CONTRIBUTION_RATIO
		)
	end

	task.spawn(function()
		local teleportOk, teleportError = pcall(function()
			TeleportService:TeleportAsync(destinationPlaceId, { player })
		end)
		if not teleportOk then
			warnWithPrefix(string.format(
				"Boss abandon teleport to place %d failed for %s: %s",
				destinationPlaceId,
				player.Name,
				tostring(teleportError)
			))
		end
	end)

	if remainingRosterSize <= 0 then
		self:_clearEncounter(string.format("Player %s abandoned; no roster players remain.", player.Name))
	else
		self:_syncDamageLeaderstats(encounter)
		self:_notifyBossHealthStateChanged()
		self:_notifyBossTimerStateChanged()
		self:_notifyEncounterStateChanged()
		self:_notifyRosterStateChanged()
	end

	return true, "Returning to the boss lobby."
end

function BossArenaRuntimeService:GetActiveBossId(): string?
	local encounter = self._encounter
	if encounter == nil then
		return nil
	end

	return encounter.bossId
end

function BossArenaRuntimeService:GetActiveBossModel(): Model?
	local encounter = self._encounter
	if encounter == nil then
		return nil
	end

	local bossModel = encounter.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		return nil
	end

	return bossModel
end

function BossArenaRuntimeService:IsActiveBossDamageable(): boolean
	local encounter = self._encounter
	if encounter == nil or encounter.timedOut == true then
		return false
	end
	if encounter.timerPhase ~= "fight" then
		return false
	end

	local bossModel = encounter.bossModel
	local bossHumanoid = encounter.bossHumanoid
	if bossModel.Parent == nil or bossHumanoid.Parent == nil then
		return false
	end
	if bossModel:GetAttribute(BOSS_INVULNERABLE_ATTRIBUTE) == true then
		return false
	end

	return bossHumanoid.Health > 0
end

function BossArenaRuntimeService:ApplyPlayerDamageToActiveBoss(player: Player, damageAmount: number): number
	local encounter = self._encounter
	if encounter == nil or encounter.rosterUserIds[player.UserId] ~= true then
		return 0
	end
	if not self:IsActiveBossDamageable() then
		return 0
	end

	local bossModel = encounter.bossModel
	local bossHumanoid = encounter.bossHumanoid
	if bossModel.Parent == nil or bossHumanoid.Parent == nil then
		return 0
	end

	local previousHealth = math.max(0, tonumber(bossHumanoid.Health) or 0)
	local resolvedDamage = math.max(0, tonumber(damageAmount) or 0)
	local requestedDamage = math.min(resolvedDamage, previousHealth)
	if requestedDamage <= 0 then
		return 0
	end

	local previousTotalDamage = encounter.damageByUserId[player.UserId] or 0
	encounter.damageByUserId[player.UserId] = previousTotalDamage + requestedDamage
	setDamageLeaderstat(player, encounter.damageByUserId[player.UserId])

	bossHumanoid:TakeDamage(requestedDamage)

	local currentHealth = math.max(0, tonumber(bossHumanoid.Health) or 0)
	local creditedDamage = math.clamp(previousHealth - currentHealth, 0, requestedDamage)
	if creditedDamage <= 0 then
		encounter.damageByUserId[player.UserId] = previousTotalDamage
		setDamageLeaderstat(player, previousTotalDamage)
		return 0
	end

	if creditedDamage ~= requestedDamage then
		local totalDamage = previousTotalDamage + creditedDamage
		encounter.damageByUserId[player.UserId] = totalDamage
		setDamageLeaderstat(player, totalDamage)
	end

	self:_notifyBossHitConfirmed({
		bossId = encounter.bossId,
		damage = creditedDamage,
		attackerUserId = player.UserId,
		serverTime = Workspace:GetServerTimeNow(),
	})

	return creditedDamage
end

function BossArenaRuntimeService:GetBossHealthState(): BossHealthState?
	return self:_buildBossHealthState(self._encounter)
end

function BossArenaRuntimeService:GetBossTimerState(): BossTimerState?
	return self:_buildBossTimerState(self._encounter)
end

function BossArenaRuntimeService:GetBossResultsState(player: Player?): BossResultsState?
	local encounter = self._encounter
	if encounter == nil or encounter.timerPhase ~= "results" then
		return nil
	end

	local startsAtServerTime = encounter.resultsStartedAtServerTime
	local endsAtServerTime = encounter.resultsEndsAtServerTime
	if startsAtServerTime == nil or endsAtServerTime == nil or endsAtServerTime <= startsAtServerTime then
		return nil
	end

	local userId = if player and player:IsA("Player") then player.UserId else 0
	if userId > 0 and encounter.rosterUserIds[userId] ~= true then
		return nil
	end

	local maxHealth = math.max(1, tonumber(encounter.bossHumanoid.MaxHealth) or 1)
	local damage = if userId > 0 then math.max(0, tonumber(encounter.damageByUserId[userId]) or 0) else 0
	local rewards = if userId > 0 then copyRewardEntries(encounter.resultRewardsByUserId[userId]) else {}

	return {
		outcome = if encounter.resultsOutcome == "victory" then "victory" else "defeat",
		bossId = encounter.bossId,
		damagePercent = math.clamp((damage / maxHealth) * 100, 0, 100),
		startsAtServerTime = startsAtServerTime,
		endsAtServerTime = endsAtServerTime,
		durationSeconds = BOSS_RESULTS_DURATION_SECONDS,
		rewards = rewards,
		readyCount = countReplayReadyPlayers(encounter),
		capacity = countRosterMembers(encounter),
		isReplayReady = userId > 0 and encounter.replayReadyUserIds[userId] == true,
	}
end

function BossArenaRuntimeService:SetPlayerReplayReady(player: Player, isReady: boolean): (boolean, string?)
	if not isEnabledForPlace() then
		return false, "Boss arena runtime is not enabled for this place."
	end
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "A valid player is required."
	end

	local encounter = self._encounter
	if encounter == nil or encounter.timerPhase ~= "results" then
		return false, "Boss results are not active."
	end
	if encounter.rosterUserIds[player.UserId] ~= true then
		return false, "You are not in this boss encounter."
	end
	if encounter.resultsCompleted == true then
		return false, "Boss results have already completed."
	end

	if isReady then
		encounter.replayReadyUserIds[player.UserId] = true
	else
		encounter.replayReadyUserIds[player.UserId] = nil
	end
	self:_notifyBossResultsStateChanged()

	return true, if isReady then "Ready to play again." else "Replay readiness cleared."
end

function BossArenaRuntimeService:ReturnPlayerToBossLobbyFromResults(player: Player): (boolean, string?)
	if not isEnabledForPlace() then
		return false, "Boss arena runtime is not enabled for this place."
	end
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "A valid player is required."
	end

	local encounter = self._encounter
	if encounter == nil or encounter.timerPhase ~= "results" then
		return false, "Boss results are not active."
	end
	if encounter.rosterUserIds[player.UserId] ~= true then
		return false, "You are not in this boss encounter."
	end

	encounter.rosterUserIds[player.UserId] = nil
	encounter.replayReadyUserIds[player.UserId] = nil
	encounter.placedCharacters[player.UserId] = nil
	encounter.damageByUserId[player.UserId] = nil
	setDamageLeaderstat(player, 0)

	self:_queuePlayersReturnToBossLobby({ player }, "Boss results return request")

	if countRosterMembers(encounter) <= 0 then
		self:_clearEncounter(string.format("Player %s returned from results; no roster players remain.", player.Name))
	else
		self:_notifyRosterStateChanged()
		self:_notifyBossResultsStateChanged()
	end

	return true, "Returning to the boss lobby."
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

function BossArenaRuntimeService:ConnectRosterStateChanged(callback: () -> ()): () -> ()
	assert(type(callback) == "function", "Roster state callback must be a function.")
	self._rosterStateListeners[callback] = true

	return function()
		self._rosterStateListeners[callback] = nil
	end
end

function BossArenaRuntimeService:ConnectBossHealthStateChanged(callback: (BossHealthState?) -> ()): () -> ()
	assert(type(callback) == "function", "Boss health callback must be a function.")
	self._bossHealthStateListeners[callback] = true

	return function()
		self._bossHealthStateListeners[callback] = nil
	end
end

function BossArenaRuntimeService:ConnectBossTimerStateChanged(callback: (BossTimerState?) -> ()): () -> ()
	assert(type(callback) == "function", "Boss timer callback must be a function.")
	self._bossTimerStateListeners[callback] = true

	return function()
		self._bossTimerStateListeners[callback] = nil
	end
end

function BossArenaRuntimeService:ConnectBossResultsStateChanged(callback: () -> ()): () -> ()
	assert(type(callback) == "function", "Boss results callback must be a function.")
	self._bossResultsStateListeners[callback] = true

	return function()
		self._bossResultsStateListeners[callback] = nil
	end
end

function BossArenaRuntimeService:ConnectBossHitConfirmed(callback: (BossHitConfirmedPayload) -> ()): () -> ()
	assert(type(callback) == "function", "Boss hit callback must be a function.")
	self._bossHitConfirmedListeners[callback] = true

	return function()
		self._bossHitConfirmedListeners[callback] = nil
	end
end

function BossArenaRuntimeService:ConnectMovePresentation(callback: (any) -> ()): () -> ()
	assert(type(callback) == "function", "Boss move presentation callback must be a function.")
	self._movePresentationListeners[callback] = true

	return function()
		self._movePresentationListeners[callback] = nil
	end
end

return BossArenaRuntimeService
