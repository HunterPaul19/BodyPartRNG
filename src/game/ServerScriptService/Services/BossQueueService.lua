local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local Zone = require(ReplicatedStorage.Packages.ZonePlus)
local BossArenas = require(ReplicatedStorage.Shared.BossArenas)
local Bosses = require(ReplicatedStorage.Shared.Bosses)
local BossQueueConstants = require(ReplicatedStorage.Shared.BossQueue.Constants)
local BossQueueTeleportPayload = require(ReplicatedStorage.Shared.BossQueue.TeleportPayload)
local NumberFormatter = require(ReplicatedStorage.Shared.Formatting.NumberFormatter)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

type PortalState = {
	instance: Model,
	portalId: string,
	bossName: string,
	hitbox: BasePart,
	zone: any,
	recommendedCombatScoreLabel: TextLabel?,
	occupancyLabel: TextLabel,
	countdownLabel: TextLabel,
	playersInZone: { [Player]: number },
	entrySequence: number,
	queuedPlayers: { Player },
	countdownToken: number,
	countdownActive: boolean,
	countdownDeadline: number,
	enqueuedAtUnix: number,
	launchInFlight: boolean,
	connections: { RBXScriptConnection },
}

local ACTIVE_PROFILE_ID = "boss_lobby"

local BossQueueService = {
	_started = false,
	_portalsByInstance = {} :: { [Instance]: PortalState },
	_tagConnections = {} :: { RBXScriptConnection },
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
end

local function normalizeString(value: any): string
	if typeof(value) ~= "string" then
		return ""
	end

	local trimmed = string.match(value, "%S.*")
	if not trimmed then
		return ""
	end

	return trimmed
end

local function resolveBossName(instance: Instance): string
	local configuredBossName = normalizeString(instance:GetAttribute(BossQueueConstants.BossNameAttribute))
	if configuredBossName ~= "" then
		return configuredBossName
	end

	local fallbackBossName = normalizeString(instance:GetAttribute("bossName"))
	if fallbackBossName ~= "" then
		return fallbackBossName
	end

	return ""
end

local function getPortalDebugName(instance: Instance): string
	local portalId = normalizeString(instance:GetAttribute(BossQueueConstants.PortalIdAttribute))
	if instance.Parent == nil then
		if portalId ~= "" then
			return string.format("%s<detached:%s>", instance.Name, portalId)
		end
		return string.format("%s<detached>", instance.Name)
	end

	if portalId ~= "" then
		return string.format("%s[%s]", instance:GetFullName(), portalId)
	end

	return instance:GetFullName()
end

local function formatRecommendedCombatScoreText(score: number): string
	return string.format("Recommended Combat Score: %s", NumberFormatter.Format(math.max(0, score)))
end

local function setCountdownInactive(state: PortalState)
	state.countdownActive = false
	state.countdownDeadline = 0
	state.enqueuedAtUnix = 0
	state.countdownLabel.Visible = false
	state.countdownLabel.Text = BossQueueConstants.DefaultCountdownText
end

local function computeQueuedPlayers(state: PortalState): { Player }
	local orderedEntries = {}

	for player, entryOrder in pairs(state.playersInZone) do
		if player.Parent == Players then
			table.insert(orderedEntries, {
				player = player,
				entryOrder = entryOrder,
			})
		else
			state.playersInZone[player] = nil
		end
	end

	table.sort(orderedEntries, function(a, b)
		if a.entryOrder == b.entryOrder then
			return a.player.UserId < b.player.UserId
		end

		return a.entryOrder < b.entryOrder
	end)

	local queuedPlayers = table.create(math.min(#orderedEntries, BossQueueConstants.QueueCapacity))
	for index = 1, math.min(#orderedEntries, BossQueueConstants.QueueCapacity) do
		table.insert(queuedPlayers, orderedEntries[index].player)
	end

	return queuedPlayers
end

function BossQueueService:_refreshPortalUi(state: PortalState)
	state.queuedPlayers = computeQueuedPlayers(state)
	state.occupancyLabel.Text = BossQueueConstants.FormatOccupancyText(#state.queuedPlayers)
	local bossDefinition = Bosses.GetDefinition(state.bossName)
	if state.recommendedCombatScoreLabel and bossDefinition then
		state.recommendedCombatScoreLabel.Text = formatRecommendedCombatScoreText(bossDefinition.recommendedCombatScore)
	end

	if not state.countdownActive then
		state.countdownLabel.Visible = false
		state.countdownLabel.Text = BossQueueConstants.DefaultCountdownText
	end
end

function BossQueueService:_cancelCountdown(state: PortalState)
	state.countdownToken += 1
	setCountdownInactive(state)
end

function BossQueueService:_refreshPortalState(state: PortalState)
	self:_refreshPortalUi(state)

	if #state.queuedPlayers <= 0 then
		if state.countdownActive then
			self:_cancelCountdown(state)
		end
		return
	end

	if state.launchInFlight or state.countdownActive then
		return
	end

	self:_startCountdown(state)
end

function BossQueueService:_collectTeleportRoster(state: PortalState): ({ Player }, { number })
	local queuedPlayers = computeQueuedPlayers(state)
	local teleportPlayers = {}
	local queuedUserIds = {}

	for _, player in ipairs(queuedPlayers) do
		if player.Parent == Players then
			table.insert(teleportPlayers, player)
			table.insert(queuedUserIds, player.UserId)
		end
	end

	return teleportPlayers, queuedUserIds
end

function BossQueueService:_handleLaunchFailure(state: PortalState, reason: string)
	warn(string.format("[BossQueueService] %s for portal %s.", reason, getPortalDebugName(state.instance)))
	state.launchInFlight = false
	self:_cancelCountdown(state)
	self:_refreshPortalState(state)
end

function BossQueueService:_launchPortal(state: PortalState, countdownToken: number)
	if self._portalsByInstance[state.instance] ~= state then
		return
	end
	if state.countdownToken ~= countdownToken then
		return
	end
	if state.launchInFlight then
		return
	end

	local teleportPlayers, queuedUserIds = self:_collectTeleportRoster(state)
	if #teleportPlayers <= 0 then
		self:_cancelCountdown(state)
		self:_refreshPortalState(state)
		return
	end

	local bossDefinition = Bosses.GetDefinition(state.bossName)
	if bossDefinition == nil then
		self:_handleLaunchFailure(state, string.format("Unknown boss '%s' configured on the portal", state.bossName))
		return
	end

	local arenaId = bossDefinition.arenaId
	if BossArenas.HasDefinition(arenaId) ~= true then
		self:_handleLaunchFailure(
			state,
			string.format("Boss '%s' is mapped to unknown arena '%s'", state.bossName, tostring(arenaId))
		)
		return
	end

	local payload, payloadError = BossQueueTeleportPayload.Build(
		state.bossName,
		arenaId,
		state.portalId,
		queuedUserIds,
		state.enqueuedAtUnix
	)
	if not payload then
		self:_handleLaunchFailure(state, payloadError or "Failed to build boss queue teleport payload")
		return
	end

	state.launchInFlight = true
	self:_cancelCountdown(state)

	local reserveOk, reservedServerCode = pcall(function()
		return TeleportService:ReserveServer(BossQueueConstants.BossArenaPlaceId)
	end)
	if not reserveOk or typeof(reservedServerCode) ~= "string" or reservedServerCode == "" then
		self:_handleLaunchFailure(state, "Failed to reserve a boss arena server")
		return
	end

	local teleportOptions = Instance.new("TeleportOptions")
	teleportOptions.ReservedServerAccessCode = reservedServerCode
	teleportOptions:SetTeleportData(payload)

	local teleportOk, teleportError = pcall(function()
		TeleportService:TeleportAsync(BossQueueConstants.BossArenaPlaceId, teleportPlayers, teleportOptions)
	end)

	state.launchInFlight = false

	if not teleportOk then
		warn(string.format(
			"[BossQueueService] TeleportAsync failed for portal %s: %s",
			getPortalDebugName(state.instance),
			tostring(teleportError)
		))
		self:_cancelCountdown(state)
		self:_refreshPortalState(state)
		return
	end

	for _, player in ipairs(teleportPlayers) do
		state.playersInZone[player] = nil
	end

	print(string.format(
		"[BossQueueService] Teleported %d player(s) for boss '%s' from portal %s.",
		#teleportPlayers,
		state.bossName,
		getPortalDebugName(state.instance)
	))

	self:_refreshPortalState(state)
end

function BossQueueService:_startCountdown(state: PortalState)
	if state.countdownActive or state.launchInFlight or #state.queuedPlayers <= 0 then
		return
	end

	state.countdownToken += 1
	local countdownToken = state.countdownToken
	state.countdownActive = true
	state.countdownDeadline = os.clock() + BossQueueConstants.CountdownSeconds
	state.enqueuedAtUnix = os.time()
	state.countdownLabel.Visible = true

	task.spawn(function()
		local lastDisplayedRemaining = -1

		while self._portalsByInstance[state.instance] == state and state.countdownToken == countdownToken do
			if not state.countdownActive then
				return
			end

			local remainingSeconds = math.max(0, math.ceil(state.countdownDeadline - os.clock()))
			if remainingSeconds ~= lastDisplayedRemaining then
				lastDisplayedRemaining = remainingSeconds
				state.countdownLabel.Text = tostring(remainingSeconds)
			end

			if remainingSeconds <= 0 then
				break
			end

			task.wait(0.1)
		end

		if self._portalsByInstance[state.instance] ~= state then
			return
		end
		if state.countdownToken ~= countdownToken then
			return
		end
		if not state.countdownActive then
			return
		end

		self:_launchPortal(state, countdownToken)
	end)
end

function BossQueueService:_handlePlayerEntered(state: PortalState, player: Player)
	if player.Parent ~= Players then
		return
	end
	if state.playersInZone[player] ~= nil then
		return
	end

	state.entrySequence += 1
	state.playersInZone[player] = state.entrySequence
	self:_refreshPortalState(state)
end

function BossQueueService:_handlePlayerExited(state: PortalState, player: Player)
	if state.playersInZone[player] == nil then
		return
	end

	state.playersInZone[player] = nil
	self:_refreshPortalState(state)
end

function BossQueueService:_buildPortalState(instance: Instance): (PortalState?, string?)
	if not instance:IsA("Model") then
		return nil, "BossPortal tag must be applied to a Model."
	end
	if not instance:IsDescendantOf(Workspace) then
		return nil, "BossPortal model must be a Workspace descendant."
	end

	local portalId = normalizeString(instance:GetAttribute(BossQueueConstants.PortalIdAttribute))
	if portalId == "" then
		return nil, string.format("Missing '%s' attribute.", BossQueueConstants.PortalIdAttribute)
	end

	local bossName = resolveBossName(instance)
	if bossName == "" then
		return nil, string.format("Missing '%s' attribute.", BossQueueConstants.BossNameAttribute)
	end
	if Bosses.HasDefinition(bossName) ~= true then
		return nil, string.format("Unknown boss '%s'.", bossName)
	end
	local bossDefinition = Bosses.GetDefinition(bossName)

	local hitbox = instance:FindFirstChild("Hitbox", true)
	if not (hitbox and hitbox:IsA("BasePart")) then
		return nil, "Missing PartyBox.Hitbox BasePart."
	end

	local billboardGui = instance:FindFirstChildWhichIsA("BillboardGui", true)
	if not billboardGui then
		return nil, "Missing BillboardGui."
	end

	local occupancyLabel = billboardGui:FindFirstChild("x/5", true)
	if not (occupancyLabel and occupancyLabel:IsA("TextLabel")) then
		return nil, "Missing billboard label 'x/5'."
	end

	local countdownLabel = billboardGui:FindFirstChild("Countdown", true)
	if not (countdownLabel and countdownLabel:IsA("TextLabel")) then
		return nil, "Missing billboard label 'Countdown'."
	end

	local recommendedCombatScoreLabel = billboardGui:FindFirstChild("RecommendedCombatScore", true)
	if recommendedCombatScoreLabel ~= nil and not recommendedCombatScoreLabel:IsA("TextLabel") then
		return nil, "Billboard child 'RecommendedCombatScore' must be a TextLabel."
	end
	if recommendedCombatScoreLabel == nil then
		warn(string.format(
			"[BossQueueService] Portal %s is missing optional billboard label 'RecommendedCombatScore'.",
			getPortalDebugName(instance)
		))
	end

	local zone = Zone.new(hitbox)
	zone:setDetection("WholeBody")

	local state: PortalState = {
		instance = instance,
		portalId = portalId,
		bossName = bossName,
		hitbox = hitbox,
		zone = zone,
		recommendedCombatScoreLabel = recommendedCombatScoreLabel,
		occupancyLabel = occupancyLabel,
		countdownLabel = countdownLabel,
		playersInZone = {},
		entrySequence = 0,
		queuedPlayers = {},
		countdownToken = 0,
		countdownActive = false,
		countdownDeadline = 0,
		enqueuedAtUnix = 0,
		launchInFlight = false,
		connections = {},
	}

	setCountdownInactive(state)
	state.occupancyLabel.Text = BossQueueConstants.FormatOccupancyText(0)
	if state.recommendedCombatScoreLabel and bossDefinition then
		state.recommendedCombatScoreLabel.Text = formatRecommendedCombatScoreText(bossDefinition.recommendedCombatScore)
	end

	return state, nil
end

function BossQueueService:_registerPortal(instance: Instance)
	if self._portalsByInstance[instance] then
		return
	end

	local state, buildError = self:_buildPortalState(instance)
	if not state then
		warn(string.format(
			"[BossQueueService] Skipping portal %s: %s",
			getPortalDebugName(instance),
			tostring(buildError)
		))
		return
	end

	table.insert(state.connections, state.zone.playerEntered:Connect(function(player: Player)
		self:_handlePlayerEntered(state, player)
	end))
	table.insert(state.connections, state.zone.playerExited:Connect(function(player: Player)
		self:_handlePlayerExited(state, player)
	end))
	table.insert(state.connections, instance.AncestryChanged:Connect(function(_, _)
		if not instance:IsDescendantOf(Workspace) then
			self:_unregisterPortal(instance)
		end
	end))

	self._portalsByInstance[instance] = state
	self:_refreshPortalState(state)

	print(string.format(
		"[BossQueueService] Registered boss portal %s for boss '%s'.",
		getPortalDebugName(instance),
		state.bossName
	))
end

function BossQueueService:_unregisterPortal(instance: Instance)
	local state = self._portalsByInstance[instance]
	if not state then
		return
	end

	self._portalsByInstance[instance] = nil
	self:_cancelCountdown(state)

	for _, connection in ipairs(state.connections) do
		connection:Disconnect()
	end

	if state.zone and state.zone.destroy then
		state.zone:destroy()
	end
end

function BossQueueService:OnStart()
	if self._started then
		return
	end

	self._started = true

	if not isEnabledForPlace() then
		return
	end

	if BossQueueConstants.BossArenaPlaceId <= 0 then
		warn("[BossQueueService] Boss arena place id is not configured.")
		return
	end

	for _, instance in ipairs(CollectionService:GetTagged(BossQueueConstants.PortalTag)) do
		self:_registerPortal(instance)
	end

	table.insert(self._tagConnections, CollectionService:GetInstanceAddedSignal(BossQueueConstants.PortalTag):Connect(function(instance)
		self:_registerPortal(instance)
	end))
	table.insert(self._tagConnections, CollectionService:GetInstanceRemovedSignal(BossQueueConstants.PortalTag):Connect(function(instance)
		self:_unregisterPortal(instance)
	end))
end

function BossQueueService:OnPlayerRemoving(player: Player)
	if not isEnabledForPlace() then
		return
	end

	for _, state in pairs(self._portalsByInstance) do
		if state.playersInZone[player] ~= nil then
			state.playersInZone[player] = nil
			self:_refreshPortalState(state)
		end
	end
end

return BossQueueService
