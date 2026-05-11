local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Diagnostics.Logger)
local BadgeConfig = require(ReplicatedStorage.Shared.Config.BadgeConfig)
local BodyPartAcquisitionService = require(script.Parent.BodyPartAcquisitionService)
local DataService = require(script.Parent.DataService)

local ownedBadgeIdsByPlayer: { [Player]: { [number]: boolean } } = {}
local pendingBadgeIdsByPlayer: { [Player]: { [number]: boolean } } = {}
local warnedInvalidBadgeIds: { [string]: boolean } = {}

local BadgeAwardService = {}

local function getBadgeId(entry: BadgeConfig.BadgeConfigEntry?): number?
	if typeof(entry) ~= "table" then
		return nil
	end

	local badgeId = math.floor(tonumber(entry.badgeId) or 0)
	if badgeId <= 0 then
		return nil
	end

	return badgeId
end

local function getOrCreateBadgeMap(storage: { [Player]: { [number]: boolean } }, player: Player): { [number]: boolean }
	local badgeMap = storage[player]
	if badgeMap == nil then
		badgeMap = {}
		storage[player] = badgeMap
	end

	return badgeMap
end

local function warnInvalidBadgeOnce(entry: any)
	local key = if typeof(entry) == "table" then tostring(entry.key) else tostring(entry)
	if warnedInvalidBadgeIds[key] == true then
		return
	end

	warnedInvalidBadgeIds[key] = true
	Logger.Warn(string.format("[BadgeAwardService] Badge config '%s' has an invalid badgeId.", tostring(key)))
end

local function warnBadgeFailure(player: Player, badgeId: number, action: string, message: any)
	Logger.Warn(string.format(
		"[BadgeAwardService] Failed to %s badge %d for %s (%d): %s",
		action,
		badgeId,
		player.Name,
		player.UserId,
		tostring(message)
	))
end

local function isAwardablePlayer(player: Player): boolean
	return player ~= nil and player:IsDescendantOf(Players) and player.UserId > 0
end

function BadgeAwardService:_awardBadgeAsync(player: Player, entry: BadgeConfig.BadgeConfigEntry)
	local badgeId = getBadgeId(entry)
	if badgeId == nil then
		warnInvalidBadgeOnce(entry)
		return
	end
	if not isAwardablePlayer(player) then
		return
	end

	local ownedBadgeIds = getOrCreateBadgeMap(ownedBadgeIdsByPlayer, player)
	if ownedBadgeIds[badgeId] == true then
		return
	end

	local pendingBadgeIds = getOrCreateBadgeMap(pendingBadgeIdsByPlayer, player)
	if pendingBadgeIds[badgeId] == true then
		return
	end

	pendingBadgeIds[badgeId] = true

	task.spawn(function()
		local hasBadgeOk, hasBadge = pcall(BadgeService.UserHasBadgeAsync, BadgeService, player.UserId, badgeId)
		if not isAwardablePlayer(player) then
			pendingBadgeIds[badgeId] = nil
			return
		end

		if not hasBadgeOk then
			warnBadgeFailure(player, badgeId, "check ownership for", hasBadge)
			pendingBadgeIds[badgeId] = nil
			return
		end

		if hasBadge == true then
			ownedBadgeIds[badgeId] = true
			pendingBadgeIds[badgeId] = nil
			return
		end

		local awardOk, awardResult = pcall(BadgeService.AwardBadgeAsync, BadgeService, player.UserId, badgeId)
		if awardOk and awardResult == true then
			ownedBadgeIds[badgeId] = true
		elseif awardOk then
			warnBadgeFailure(player, badgeId, "award", "AwardBadgeAsync returned false")
		else
			warnBadgeFailure(player, badgeId, "award", awardResult)
		end

		pendingBadgeIds[badgeId] = nil
	end)
end

function BadgeAwardService:_handlePlayerDataLoaded(player: Player)
	local playedGameBadge = BadgeConfig.GetPlayedGame()
	if playedGameBadge then
		self:_awardBadgeAsync(player, playedGameBadge)
	end

	self:_awardOwnedBodyPartRarityBadges(player, DataService:GetBodyPartsState(player))
end

function BadgeAwardService:_handleBodyPartAcquired(event: any)
	if typeof(event) ~= "table" then
		return
	end

	local player = event.player
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	local rarityBadge = BadgeConfig.GetForDisplayRarity(event.displayRarity)
	if rarityBadge then
		self:_awardBadgeAsync(player, rarityBadge)
	end
end

function BadgeAwardService:_awardBodyPartRecordRarity(player: Player, record: any)
	if typeof(record) ~= "table" then
		return
	end

	local rarityBadge = BadgeConfig.GetForDisplayRarity(record.displayRarity)
	if rarityBadge then
		self:_awardBadgeAsync(player, rarityBadge)
	end
end

function BadgeAwardService:_awardOwnedBodyPartRarityBadges(player: Player, bodyPartsState: any)
	local ownedById = if typeof(bodyPartsState) == "table" then bodyPartsState.ownedById else nil
	if typeof(ownedById) ~= "table" then
		return
	end

	for _, record in pairs(ownedById) do
		self:_awardBodyPartRecordRarity(player, record)
	end
end

function BadgeAwardService:OnStart()
	DataService.PlayerDataLoaded:Connect(function(player: Player)
		self:_handlePlayerDataLoaded(player)
	end)

	DataService.OwnedBodyPartAdded:Connect(function(player: Player, record: any, _bodyPartsState: any)
		self:_awardBodyPartRecordRarity(player, record)
	end)

	BodyPartAcquisitionService.Acquired:Connect(function(event: any)
		self:_handleBodyPartAcquired(event)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.defer(function()
			if DataService:IsPlayerDataLoaded(player) then
				self:_handlePlayerDataLoaded(player)
			end
		end)
	end
end

function BadgeAwardService:OnPlayerRemoving(player: Player)
	ownedBadgeIdsByPlayer[player] = nil
	pendingBadgeIdsByPlayer[player] = nil
end

return BadgeAwardService
