local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Schema = require(ReplicatedStorage.Lists.Schema)
local TimeShardState = require(ReplicatedStorage.Shared.Character.TimeShardState)
local DataService = require(script.Parent.DataService)

local TIME_SHARDS_KEY = Schema.TimeShards and Schema.TimeShards.key or nil
local SECONDS_PER_TIME_SHARD = 60

local TimeShardService = {
	_started = false,
}

local function getEarnedMinutes(timePlayedSeconds: any): number
	local totalSeconds = math.max(0, math.floor(tonumber(timePlayedSeconds) or 0))
	return math.floor(totalSeconds / SECONDS_PER_TIME_SHARD)
end

function TimeShardService:_reconcilePlayer(player: Player, timePlayedSecondsOverride: any?)
	if not TIME_SHARDS_KEY or player.Parent ~= Players then
		return
	end

	local earnedMinutes = getEarnedMinutes(if timePlayedSecondsOverride ~= nil then timePlayedSecondsOverride else DataService:GetTimePlayed(player))
	local currentState = DataService:GetTimeShardsState(player)
	if earnedMinutes <= currentState.awardedMinutes then
		return
	end

	DataService:Set(player, TIME_SHARDS_KEY, function(currentValue)
		local state = TimeShardState.Normalize(currentValue)
		if earnedMinutes <= state.awardedMinutes then
			return state
		end

		local newlyEarnedShards = earnedMinutes - state.awardedMinutes
		return {
			balance = state.balance + newlyEarnedShards,
			awardedMinutes = earnedMinutes,
		}
	end)
end

function TimeShardService:OnStart()
	if self._started then
		return
	end

	self._started = true

	DataService.PlayerDataLoaded:Connect(function(player: Player)
		self:_reconcilePlayer(player)
	end)

	DataService.TimePlayedFlushed:Connect(function(player: Player, _deltaSeconds: number, _previousValue: number, updatedValue: number)
		self:_reconcilePlayer(player, updatedValue)
	end)
end

function TimeShardService:OnPlayerAdded(player: Player)
	task.defer(function()
		self:_reconcilePlayer(player)
	end)
end

return TimeShardService
