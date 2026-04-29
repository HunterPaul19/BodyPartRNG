local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NumberFormatter = require(ReplicatedStorage.Shared.Formatting.NumberFormatter)
local Notify = require(ReplicatedStorage.Shared.UI.Notify)
local BodyPartService = require(script.Parent.BodyPartService)
local DataService = require(script.Parent.DataService)

local OFFLINE_EARNING_RATE = 0.01
local OFFLINE_EARNING_MAX_SECONDS = 24 * 60 * 60
local OFFLINE_INCOME_SOURCE = "offline_income"

local processedPlayers: { [Player]: boolean } = {}

local OfflineEarningsService = {}

local function formatMoney(value: number): string
	return NumberFormatter.Format(math.max(0, math.floor(tonumber(value) or 0)))
end

local function formatOfflineDuration(totalSeconds: number): string
	local seconds = math.max(0, math.floor(tonumber(totalSeconds) or 0))
	local days = math.floor(seconds / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	local minutes = math.floor((seconds % 3600) / 60)

	if days > 0 then
		return string.format("%dd %dh", days, hours)
	end
	if hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	end
	if minutes > 0 then
		return string.format("%dm", minutes)
	end

	return string.format("%ds", seconds)
end

local function resolveOfflineReward(player: Player): (number, number)
	local stats = DataService:GetStats(player)
	local lifecycle = if typeof(stats) == "table" and typeof(stats.lifecycle) == "table" then stats.lifecycle else nil
	local lastLeaveAt = math.max(0, math.floor(tonumber(lifecycle and lifecycle.lastLeaveAt) or 0))
	if lastLeaveAt <= 0 then
		return 0, 0
	end

	local offlineSeconds = math.max(0, os.time() - lastLeaveAt)
	if offlineSeconds <= 0 then
		return 0, 0
	end

	local bonuses = BodyPartService:GetPersistedLoadoutBonuses(player)
	local passiveIncomePerSecond = math.max(0, tonumber(bonuses and bonuses.passiveIncomePerSecond) or 0)
	if passiveIncomePerSecond <= 0 then
		return 0, offlineSeconds
	end

	local paidOfflineSeconds = math.min(offlineSeconds, OFFLINE_EARNING_MAX_SECONDS)
	local reward = math.max(0, math.floor(passiveIncomePerSecond * paidOfflineSeconds * OFFLINE_EARNING_RATE))
	return reward, offlineSeconds
end

function OfflineEarningsService:_grantOfflineReward(player: Player)
	if processedPlayers[player] then
		return
	end
	processedPlayers[player] = true

	local reward, offlineSeconds = resolveOfflineReward(player)
	if reward <= 0 then
		return
	end

	DataService:AddMoney(player, reward, OFFLINE_INCOME_SOURCE)
	Notify.Send(
		player,
		string.format(
			"You earned $%s while away for %s.",
			formatMoney(reward),
			formatOfflineDuration(offlineSeconds)
		),
		{
			channel = "system",
			duration = 6,
			tone = "good",
		}
	)
end

function OfflineEarningsService:OnStart()
	DataService.PlayerDataLoaded:Connect(function(player: Player)
		self:_grantOfflineReward(player)
	end)
end

function OfflineEarningsService:OnPlayerRemoving(player: Player)
	processedPlayers[player] = nil
end

return OfflineEarningsService
