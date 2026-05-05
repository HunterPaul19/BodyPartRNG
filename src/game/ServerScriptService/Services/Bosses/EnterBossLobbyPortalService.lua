local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local BossWorldGuideService = require(script.Parent.BossWorldGuideService)
local BossQueueConstants = require(ReplicatedStorage.Shared.BossQueue.Constants)
local BossQueueTeleportPayload = require(ReplicatedStorage.Shared.BossQueue.TeleportPayload)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)
local TeleportTransitionService = require(script.Parent.TeleportTransitionService)

type PromptState = {
	prompt: ProximityPrompt,
	connections: { RBXScriptConnection },
}

local ACTIVE_PROFILE_ID = "main"
local PROMPT_TAG = "EnterBossLobbyPortalPrompt"
local DESTINATION_ROUTE_ID = "enter_boss_lobby"
local IN_FLIGHT_RESET_SECONDS = 10
local TUTORIAL_BOSS_ID = "Flame Guard General"
local TUTORIAL_ARENA_ID = "Spire"
local TUTORIAL_PORTAL_ID = "boss_world_tutorial"
local TUTORIAL_SOURCE_FLOW = "boss_world_tutorial"
local TUTORIAL_BOSS_HEALTH_MULTIPLIER = 0.25

local EnterBossLobbyPortalService = {
	_started = false,
	_promptsByInstance = {} :: { [Instance]: PromptState },
	_tagConnections = {} :: { RBXScriptConnection },
	_playerTeleportTokens = {} :: { [Player]: number },
	_nextTeleportToken = 0,
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
end

local function getPromptDebugName(prompt: Instance): string
	if prompt.Parent == nil then
		return string.format("%s<detached>", prompt.Name)
	end

	return prompt:GetFullName()
end

local function getDestinationPlaceId(): number
	local route = PlaceProfile.GetRoutes()[DESTINATION_ROUTE_ID]
	if typeof(route) ~= "table" then
		return 0
	end

	return math.max(0, math.floor(tonumber(route.placeId) or 0))
end

function EnterBossLobbyPortalService:_clearPlayerTeleportToken(player: Player, token: number?)
	local activeToken = self._playerTeleportTokens[player]
	if activeToken == nil then
		return
	end
	if token ~= nil and activeToken ~= token then
		return
	end

	self._playerTeleportTokens[player] = nil
end

function EnterBossLobbyPortalService:_markPlayerTeleportInFlight(player: Player): number
	self._nextTeleportToken += 1
	local token = self._nextTeleportToken
	self._playerTeleportTokens[player] = token

	task.delay(IN_FLIGHT_RESET_SECONDS, function()
		self:_clearPlayerTeleportToken(player, token)
	end)

	return token
end

function EnterBossLobbyPortalService:_teleportPlayerToBossTutorial(player: Player, prompt: ProximityPrompt)
	if BossQueueConstants.BossArenaPlaceId <= 0 then
		Logger.Warn(string.format(
			"[EnterBossLobbyPortalService] Prompt %s triggered for boss tutorial but the boss arena place id is not configured.",
			getPromptDebugName(prompt)
		))
		return
	end

	local payload, payloadError = BossQueueTeleportPayload.Build(
		TUTORIAL_BOSS_ID,
		TUTORIAL_ARENA_ID,
		TUTORIAL_PORTAL_ID,
		{ player.UserId },
		os.time(),
		nil,
		TUTORIAL_SOURCE_FLOW,
		TUTORIAL_BOSS_HEALTH_MULTIPLIER
	)
	if payload == nil then
		Logger.Warn(string.format(
			"[EnterBossLobbyPortalService] Failed to build boss tutorial payload for %s via %s: %s",
			player.Name,
			getPromptDebugName(prompt),
			tostring(payloadError)
		))
		return
	end

	local token = self:_markPlayerTeleportInFlight(player)

	local reserveOk, reservedServerCode = pcall(function()
		return TeleportService:ReserveServer(BossQueueConstants.BossArenaPlaceId)
	end)
	if not reserveOk or typeof(reservedServerCode) ~= "string" or reservedServerCode == "" then
		self:_clearPlayerTeleportToken(player, token)
		Logger.Warn(string.format(
			"[EnterBossLobbyPortalService] Failed to reserve boss tutorial server for %s via %s: %s",
			player.Name,
			getPromptDebugName(prompt),
			tostring(reservedServerCode)
		))
		return
	end

	local teleportOptions = Instance.new("TeleportOptions")
	teleportOptions.ReservedServerAccessCode = reservedServerCode
	teleportOptions:SetTeleportData(payload)

	local teleportOk, teleportError = pcall(function()
		TeleportTransitionService:TeleportAsync(BossQueueConstants.BossArenaPlaceId, { player }, teleportOptions)
	end)

	if teleportOk then
		BossWorldGuideService:RecordBossWorldEntered(player, {
			portalId = TUTORIAL_PORTAL_ID,
			sourceFlow = TUTORIAL_SOURCE_FLOW,
			bossId = TUTORIAL_BOSS_ID,
			arenaId = TUTORIAL_ARENA_ID,
			amount = 1,
		})
		BossWorldGuideService:MarkBossTutorialArenaEntered(player)
		return
	end

	self:_clearPlayerTeleportToken(player, token)
	Logger.Warn(string.format(
		"[EnterBossLobbyPortalService] Boss tutorial TeleportAsync failed for %s via %s: %s",
		player.Name,
		getPromptDebugName(prompt),
		tostring(teleportError)
	))
end

function EnterBossLobbyPortalService:_teleportPlayer(player: Player, prompt: ProximityPrompt)
	if player.Parent ~= Players then
		return
	end
	if self._playerTeleportTokens[player] ~= nil then
		return
	end

	if BossWorldGuideService:ShouldRouteToBossTutorial(player) then
		self:_teleportPlayerToBossTutorial(player, prompt)
		return
	end

	local destinationPlaceId = getDestinationPlaceId()
	if destinationPlaceId <= 0 then
		Logger.Warn(string.format(
			"[EnterBossLobbyPortalService] Prompt %s triggered but route '%s' is not configured.",
			getPromptDebugName(prompt),
			DESTINATION_ROUTE_ID
		))
		return
	end

	local token = self:_markPlayerTeleportInFlight(player)

	local teleportOk, teleportError = pcall(function()
		TeleportTransitionService:TeleportAsync(destinationPlaceId, { player })
	end)

	if teleportOk then
		BossWorldGuideService:MarkBossWorldEntered(player)
		return
	end

	self:_clearPlayerTeleportToken(player, token)
	Logger.Warn(string.format(
		"[EnterBossLobbyPortalService] TeleportAsync failed for %s via %s: %s",
		player.Name,
		getPromptDebugName(prompt),
		tostring(teleportError)
	))
end

function EnterBossLobbyPortalService:_registerPrompt(instance: Instance)
	if self._promptsByInstance[instance] then
		return
	end
	if not instance:IsA("ProximityPrompt") then
		Logger.Warn(string.format(
			"[EnterBossLobbyPortalService] Skipping tagged instance %s: tag '%s' must be applied to a ProximityPrompt.",
			getPromptDebugName(instance),
			PROMPT_TAG
		))
		return
	end
	if not instance:IsDescendantOf(Workspace) then
		Logger.Warn(string.format(
			"[EnterBossLobbyPortalService] Skipping tagged prompt %s: prompt must be a Workspace descendant.",
			getPromptDebugName(instance)
		))
		return
	end

	local state: PromptState = {
		prompt = instance,
		connections = {},
	}

	table.insert(state.connections, instance.Triggered:Connect(function(player: Player)
		self:_teleportPlayer(player, instance)
	end))
	table.insert(state.connections, instance.AncestryChanged:Connect(function()
		if not instance:IsDescendantOf(Workspace) then
			self:_unregisterPrompt(instance)
		end
	end))

	self._promptsByInstance[instance] = state
	Logger.Print(string.format(
		"[EnterBossLobbyPortalService] Registered boss lobby prompt %s.",
		getPromptDebugName(instance)
	))
end

function EnterBossLobbyPortalService:_unregisterPrompt(instance: Instance)
	local state = self._promptsByInstance[instance]
	if not state then
		return
	end

	self._promptsByInstance[instance] = nil

	for _, connection in ipairs(state.connections) do
		connection:Disconnect()
	end
end

function EnterBossLobbyPortalService:OnStart()
	if self._started then
		return
	end

	self._started = true

	if not isEnabledForPlace() then
		return
	end

	local destinationPlaceId = getDestinationPlaceId()
	if destinationPlaceId <= 0 then
		Logger.Warn(string.format(
			"[EnterBossLobbyPortalService] Route '%s' is not configured for profile '%s'.",
			DESTINATION_ROUTE_ID,
			ACTIVE_PROFILE_ID
		))
		return
	end

	for _, instance in ipairs(CollectionService:GetTagged(PROMPT_TAG)) do
		self:_registerPrompt(instance)
	end

	table.insert(self._tagConnections, CollectionService:GetInstanceAddedSignal(PROMPT_TAG):Connect(function(instance)
		self:_registerPrompt(instance)
	end))
	table.insert(self._tagConnections, CollectionService:GetInstanceRemovedSignal(PROMPT_TAG):Connect(function(instance)
		self:_unregisterPrompt(instance)
	end))
end

function EnterBossLobbyPortalService:OnPlayerRemoving(player: Player)
	self:_clearPlayerTeleportToken(player, nil)
end

return EnterBossLobbyPortalService
