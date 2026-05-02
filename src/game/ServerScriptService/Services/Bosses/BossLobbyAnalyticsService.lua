local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Diagnostics.Logger)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

type DepartureContext = {
	reason: string,
	bossName: string?,
	portalId: string?,
}

type SessionState = {
	enteredAtClock: number,
	departureContext: DepartureContext?,
}

local ACTIVE_PROFILE_ID = "boss_lobby"
local ANALYTICS_VERSION = "boss_lobby_v1"

local EVENT_ENTERED = "BossLobbyEntered"
local EVENT_DEPARTED = "BossLobbyDeparted"

local REASON_LEFT_GAME = "left_game"
local REASON_RETURNED_HOME = "returned_home"
local REASON_ENTERED_BOSS_ARENA = "entered_boss_arena"

local BossLobbyAnalyticsService = {
	_started = false,
	_sessionsByPlayer = {} :: { [Player]: SessionState },
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
end

local function normalizeString(value: any, fallback: string): string
	if typeof(value) ~= "string" then
		return fallback
	end

	local trimmed = string.match(value, "%S.*")
	if not trimmed then
		return fallback
	end

	return trimmed
end

local function buildCustomFields(reason: string, bossName: string?, portalId: string?)
	local normalizedBossName = normalizeString(bossName, "none")
	local normalizedPortalId = normalizeString(portalId, "none")

	return {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = reason,
		[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = normalizedBossName,
		[Enum.AnalyticsCustomFieldKeys.CustomField03.Name] = string.format("%s:%s", ANALYTICS_VERSION, normalizedPortalId),
	}
end

local function logCustomEvent(player: Player, eventName: string, value: number, reason: string, bossName: string?, portalId: string?)
	local ok, err = pcall(function()
		AnalyticsService:LogCustomEvent(player, eventName, value, buildCustomFields(reason, bossName, portalId))
	end)

	if not ok then
		Logger.Warn(string.format(
			"[BossLobbyAnalyticsService] Failed to log %s for %s: %s",
			eventName,
			player.Name,
			tostring(err)
		))
	end
end

function BossLobbyAnalyticsService:_getOrCreateSession(player: Player): SessionState
	local session = self._sessionsByPlayer[player]
	if session ~= nil then
		return session
	end

	session = {
		enteredAtClock = os.clock(),
		departureContext = nil,
	}
	self._sessionsByPlayer[player] = session
	return session
end

function BossLobbyAnalyticsService:_logDeparted(player: Player, session: SessionState)
	local context = session.departureContext or {
		reason = REASON_LEFT_GAME,
		bossName = nil,
		portalId = nil,
	}
	local durationSeconds = math.max(0, math.floor(os.clock() - session.enteredAtClock))

	logCustomEvent(player, EVENT_DEPARTED, durationSeconds, context.reason, context.bossName, context.portalId)
end

function BossLobbyAnalyticsService:MarkReturningHome(player: Player)
	if not isEnabledForPlace() then
		return
	end

	local session = self:_getOrCreateSession(player)
	session.departureContext = {
		reason = REASON_RETURNED_HOME,
		bossName = nil,
		portalId = nil,
	}
end

function BossLobbyAnalyticsService:CancelReturningHome(player: Player)
	local session = self._sessionsByPlayer[player]
	if session == nil then
		return
	end
	if session.departureContext == nil or session.departureContext.reason ~= REASON_RETURNED_HOME then
		return
	end

	session.departureContext = nil
end

function BossLobbyAnalyticsService:MarkEnteringBossArena(player: Player, bossName: string?, portalId: string?)
	if not isEnabledForPlace() then
		return
	end

	local session = self:_getOrCreateSession(player)
	session.departureContext = {
		reason = REASON_ENTERED_BOSS_ARENA,
		bossName = bossName,
		portalId = portalId,
	}
end

function BossLobbyAnalyticsService:CancelEnteringBossArena(player: Player)
	local session = self._sessionsByPlayer[player]
	if session == nil then
		return
	end
	if session.departureContext == nil or session.departureContext.reason ~= REASON_ENTERED_BOSS_ARENA then
		return
	end

	session.departureContext = nil
end

function BossLobbyAnalyticsService:OnStart()
	if self._started then
		return
	end

	self._started = true

	if not isEnabledForPlace() then
		return
	end

	for _, player in ipairs(Players:GetPlayers()) do
		self:OnPlayerAdded(player)
	end
end

function BossLobbyAnalyticsService:OnPlayerAdded(player: Player)
	if not isEnabledForPlace() then
		return
	end
	if player.Parent ~= Players then
		return
	end
	if self._sessionsByPlayer[player] ~= nil then
		return
	end

	self._sessionsByPlayer[player] = {
		enteredAtClock = os.clock(),
		departureContext = nil,
	}

	task.spawn(function()
		logCustomEvent(player, EVENT_ENTERED, 1, "entered", nil, nil)
	end)
end

function BossLobbyAnalyticsService:OnPlayerRemoving(player: Player)
	if not isEnabledForPlace() then
		self._sessionsByPlayer[player] = nil
		return
	end

	local session = self._sessionsByPlayer[player]
	if session == nil then
		return
	end

	self._sessionsByPlayer[player] = nil
	self:_logDeparted(player, session)
end

return BossLobbyAnalyticsService
