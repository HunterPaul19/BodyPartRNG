local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossQueueTeleportPayload = require(ReplicatedStorage.Shared.BossQueue.TeleportPayload)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

type ArrivalPayload = BossQueueTeleportPayload.BossQueueTeleportPayload

local ACTIVE_PROFILE_ID = "boss_arena"

local BossArenaArrivalService = {
	_payloadByPlayer = {} :: { [Player]: ArrivalPayload },
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
end

local function clonePotionEffectsByUserId(source: BossQueueTeleportPayload.BossQueuePotionEffectsByUserId?)
	local cloned = {}
	if typeof(source) ~= "table" then
		return nil
	end

	for userId, snapshot in pairs(source) do
		if typeof(snapshot) ~= "table" or typeof(snapshot.activeByPotionId) ~= "table" then
			continue
		end

		local activeByPotionId = {}
		for potionId, remainingSeconds in pairs(snapshot.activeByPotionId) do
			activeByPotionId[potionId] = remainingSeconds
		end

		cloned[userId] = {
			capturedAtUnix = snapshot.capturedAtUnix,
			activeByPotionId = activeByPotionId,
		}
	end

	return if next(cloned) ~= nil then cloned else nil
end

local function clonePayload(payload: ArrivalPayload): ArrivalPayload
	return {
		version = payload.version,
		bossName = payload.bossName,
		arenaId = payload.arenaId,
		portalId = payload.portalId,
		queuedUserIds = table.clone(payload.queuedUserIds),
		queueSize = payload.queueSize,
		enqueuedAtUnix = payload.enqueuedAtUnix,
		potionEffectsByUserId = clonePotionEffectsByUserId(payload.potionEffectsByUserId),
	}
end

function BossArenaArrivalService:GetArrivalPayload(player: Player): ArrivalPayload?
	local payload = self._payloadByPlayer[player]
	if not payload then
		return nil
	end

	return clonePayload(payload)
end

function BossArenaArrivalService:OnStart()
	if not isEnabledForPlace() then
		return
	end

	Logger.Print("[BossArenaArrivalService] Ready to resolve boss queue arrivals.")
end

function BossArenaArrivalService:OnPlayerAdded(player: Player)
	if not isEnabledForPlace() then
		return
	end

	local joinDataOk, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if not joinDataOk then
		Logger.Warn(string.format(
			"[BossArenaArrivalService] Failed to read join data for %s: %s",
			player.Name,
			tostring(joinData)
		))
		return
	end

	local payload, payloadError = BossQueueTeleportPayload.FromJoinData(joinData)
	if not payload then
		local teleportData = if typeof(joinData) == "table" then joinData.TeleportData else nil
		if teleportData ~= nil then
			Logger.Warn(string.format(
				"[BossArenaArrivalService] Invalid boss queue payload for %s: %s",
				player.Name,
				tostring(payloadError)
			))
		end
		return
	end

	self._payloadByPlayer[player] = payload

	Logger.Print(string.format(
		"[BossArenaArrivalService] Player %s arrived for boss '%s' in arena '%s' via portal %s with %d queued player(s).",
		player.Name,
		payload.bossName,
		payload.arenaId,
		payload.portalId,
		payload.queueSize
	))
end

function BossArenaArrivalService:OnPlayerRemoving(player: Player)
	self._payloadByPlayer[player] = nil
end

return BossArenaArrivalService
