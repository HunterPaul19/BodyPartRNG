local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

type PromptState = {
	prompt: ProximityPrompt,
	connections: { RBXScriptConnection },
}

local ACTIVE_PROFILE_ID = "boss_lobby"
local PROMPT_TAG = "ReturnHomePortalPrompt"
local RETURN_ROUTE_ID = "return_to_main"
local IN_FLIGHT_RESET_SECONDS = 10

local ReturnHomePortalService = {
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

local function getReturnPlaceId(): number
	local route = PlaceProfile.GetRoutes()[RETURN_ROUTE_ID]
	if typeof(route) ~= "table" then
		return 0
	end

	return math.max(0, math.floor(tonumber(route.placeId) or 0))
end

function ReturnHomePortalService:_clearPlayerTeleportToken(player: Player, token: number?)
	local activeToken = self._playerTeleportTokens[player]
	if activeToken == nil then
		return
	end
	if token ~= nil and activeToken ~= token then
		return
	end

	self._playerTeleportTokens[player] = nil
end

function ReturnHomePortalService:_markPlayerTeleportInFlight(player: Player): number
	self._nextTeleportToken += 1
	local token = self._nextTeleportToken
	self._playerTeleportTokens[player] = token

	task.delay(IN_FLIGHT_RESET_SECONDS, function()
		self:_clearPlayerTeleportToken(player, token)
	end)

	return token
end

function ReturnHomePortalService:_teleportPlayerHome(player: Player, prompt: ProximityPrompt)
	if player.Parent ~= Players then
		return
	end
	if self._playerTeleportTokens[player] ~= nil then
		return
	end

	local destinationPlaceId = getReturnPlaceId()
	if destinationPlaceId <= 0 then
		warn(string.format(
			"[ReturnHomePortalService] Prompt %s triggered but route '%s' is not configured.",
			getPromptDebugName(prompt),
			RETURN_ROUTE_ID
		))
		return
	end

	local token = self:_markPlayerTeleportInFlight(player)

	local teleportOk, teleportError = pcall(function()
		TeleportService:TeleportAsync(destinationPlaceId, { player })
	end)

	if teleportOk then
		return
	end

	self:_clearPlayerTeleportToken(player, token)
	warn(string.format(
		"[ReturnHomePortalService] TeleportAsync failed for %s via %s: %s",
		player.Name,
		getPromptDebugName(prompt),
		tostring(teleportError)
	))
end

function ReturnHomePortalService:_registerPrompt(instance: Instance)
	if self._promptsByInstance[instance] then
		return
	end
	if not instance:IsA("ProximityPrompt") then
		warn(string.format(
			"[ReturnHomePortalService] Skipping tagged instance %s: tag '%s' must be applied to a ProximityPrompt.",
			getPromptDebugName(instance),
			PROMPT_TAG
		))
		return
	end
	if not instance:IsDescendantOf(Workspace) then
		warn(string.format(
			"[ReturnHomePortalService] Skipping tagged prompt %s: prompt must be a Workspace descendant.",
			getPromptDebugName(instance)
		))
		return
	end

	local state: PromptState = {
		prompt = instance,
		connections = {},
	}

	table.insert(state.connections, instance.Triggered:Connect(function(player: Player)
		self:_teleportPlayerHome(player, instance)
	end))
	table.insert(state.connections, instance.AncestryChanged:Connect(function()
		if not instance:IsDescendantOf(Workspace) then
			self:_unregisterPrompt(instance)
		end
	end))

	self._promptsByInstance[instance] = state
	print(string.format(
		"[ReturnHomePortalService] Registered return-home prompt %s.",
		getPromptDebugName(instance)
	))
end

function ReturnHomePortalService:_unregisterPrompt(instance: Instance)
	local state = self._promptsByInstance[instance]
	if not state then
		return
	end

	self._promptsByInstance[instance] = nil

	for _, connection in ipairs(state.connections) do
		connection:Disconnect()
	end
end

function ReturnHomePortalService:OnStart()
	if self._started then
		return
	end

	self._started = true

	if not isEnabledForPlace() then
		return
	end

	local destinationPlaceId = getReturnPlaceId()
	if destinationPlaceId <= 0 then
		warn(string.format(
			"[ReturnHomePortalService] Route '%s' is not configured for profile '%s'.",
			RETURN_ROUTE_ID,
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

function ReturnHomePortalService:OnPlayerRemoving(player: Player)
	self:_clearPlayerTeleportToken(player, nil)
end

return ReturnHomePortalService
