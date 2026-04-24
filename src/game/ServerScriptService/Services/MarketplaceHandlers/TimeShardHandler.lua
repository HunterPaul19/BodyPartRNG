local DataService = require(script.Parent.Parent.DataService)

local TimeShardHandler = {}

function TimeShardHandler.grant(player: Player, context: any): (boolean, string?)
	local amount = if typeof(context) == "table" then tonumber(context.amount) else nil
	amount = if amount ~= nil then math.floor(amount) else 0
	if amount <= 0 then
		return false, "Time Shard purchase amount is invalid."
	end

	DataService:AdjustTimeShardsBalance(player, amount, "marketplace_time_shards")
	return true, nil
end

return TimeShardHandler
