local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossQueueConstants = require(ReplicatedStorage.Shared.BossQueue.Constants)

export type BossQueueTeleportPayload = {
	version: number,
	bossName: string,
	arenaId: string,
	portalId: string,
	queuedUserIds: { number },
	queueSize: number,
	enqueuedAtUnix: number,
}

local BossQueueTeleportPayload = {}

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

local function normalizeQueuedUserIds(value: any): { number }
	local normalizedUserIds = {}
	local seenUserIds = {}

	if typeof(value) ~= "table" then
		return normalizedUserIds
	end

	for _, userId in ipairs(value) do
		local resolvedUserId = math.floor(tonumber(userId) or 0)
		if resolvedUserId > 0 and seenUserIds[resolvedUserId] ~= true then
			seenUserIds[resolvedUserId] = true
			table.insert(normalizedUserIds, resolvedUserId)
		end
	end

	return normalizedUserIds
end

function BossQueueTeleportPayload.Normalize(payload: any): (BossQueueTeleportPayload?, string?)
	if typeof(payload) ~= "table" then
		return nil, "Boss queue teleport payload must be a table."
	end

	local version = math.max(0, math.floor(tonumber(payload.version) or 0))
	if version <= 0 then
		return nil, "Boss queue teleport payload version is required."
	end

	local bossName = normalizeString(payload.bossName)
	if bossName == "" then
		return nil, "Boss queue teleport payload bossName is required."
	end

	local arenaId = normalizeString(payload.arenaId)
	if arenaId == "" then
		return nil, "Boss queue teleport payload arenaId is required."
	end

	local portalId = normalizeString(payload.portalId)
	if portalId == "" then
		return nil, "Boss queue teleport payload portalId is required."
	end

	local queuedUserIds = normalizeQueuedUserIds(payload.queuedUserIds)
	if #queuedUserIds <= 0 then
		return nil, "Boss queue teleport payload must include queued players."
	end

	local enqueuedAtUnix = math.max(0, math.floor(tonumber(payload.enqueuedAtUnix) or 0))
	if enqueuedAtUnix <= 0 then
		return nil, "Boss queue teleport payload enqueuedAtUnix is required."
	end

	local queueSize = #queuedUserIds

	return {
		version = version,
		bossName = bossName,
		arenaId = arenaId,
		portalId = portalId,
		queuedUserIds = queuedUserIds,
		queueSize = queueSize,
		enqueuedAtUnix = enqueuedAtUnix,
	}, nil
end

function BossQueueTeleportPayload.Build(
	bossName: string,
	arenaId: string,
	portalId: string,
	queuedUserIds: { number },
	enqueuedAtUnix: number
): (BossQueueTeleportPayload?, string?)
	return BossQueueTeleportPayload.Normalize({
		version = BossQueueConstants.PayloadVersion,
		bossName = bossName,
		arenaId = arenaId,
		portalId = portalId,
		queuedUserIds = queuedUserIds,
		queueSize = if typeof(queuedUserIds) == "table" then #queuedUserIds else 0,
		enqueuedAtUnix = enqueuedAtUnix,
	})
end

function BossQueueTeleportPayload.FromJoinData(joinData: any): (BossQueueTeleportPayload?, string?)
	if typeof(joinData) ~= "table" then
		return nil, "Join data must be a table."
	end

	local teleportData = joinData.TeleportData
	if teleportData == nil then
		return nil, "Join data did not include teleport data."
	end

	return BossQueueTeleportPayload.Normalize(teleportData)
end

return BossQueueTeleportPayload
