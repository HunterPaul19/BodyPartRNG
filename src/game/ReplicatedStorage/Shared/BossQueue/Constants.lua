local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RouteConfig = require(ReplicatedStorage.Shared.PlaceProfiles.RouteConfig)

local BossQueueConstants = {
	PortalTag = "BossPortal",
	BossNameAttribute = "BossName",
	PortalIdAttribute = "PortalId",
	QueueCapacity = 5,
	CountdownSeconds = 15,
	DefaultCountdownText = "15",
	PayloadVersion = 1,
	BossArenaPlaceId = RouteConfig.PlaceIds.boss_arena,
}

function BossQueueConstants.FormatOccupancyText(occupancy: any): string
	local resolvedOccupancy = math.max(0, math.floor(tonumber(occupancy) or 0))
	local clampedOccupancy = math.min(resolvedOccupancy, BossQueueConstants.QueueCapacity)
	return string.format("%d/%d", clampedOccupancy, BossQueueConstants.QueueCapacity)
end

return table.freeze(BossQueueConstants)
