local DataStoreService = game:GetService("DataStoreService")

local RateLimitTelemetry = require(script.Parent.Common.RateLimitTelemetry)

local LOG_INTERVAL_SECONDS = 60

local BUDGET_REQUESTS = {
	standardRead = Enum.DataStoreRequestType.GetAsync,
	standardWrite = Enum.DataStoreRequestType.SetIncrementAsync,
	orderedRead = Enum.DataStoreRequestType.GetSortedAsync,
	orderedWrite = Enum.DataStoreRequestType.SetIncrementSortedAsync,
}

local RateLimitObservabilityService = {}

local function getBudgetSnapshot(): { [string]: number }
	local snapshot = {}

	for label, requestType in pairs(BUDGET_REQUESTS) do
		local ok, budgetValue = pcall(function()
			return DataStoreService:GetRequestBudgetForRequestType(requestType)
		end)
		snapshot[label] = if ok then math.max(0, math.floor(tonumber(budgetValue) or 0)) else -1
	end

	return snapshot
end

local function formatCounters(countersByKey: { [string]: number }?): string
	if typeof(countersByKey) ~= "table" then
		return "none"
	end

	local parts = {}
	for key, value in pairs(countersByKey) do
		parts[#parts + 1] = string.format("%s=%d", tostring(key), math.max(0, math.floor(tonumber(value) or 0)))
	end

	table.sort(parts)
	if #parts == 0 then
		return "none"
	end

	return table.concat(parts, ", ")
end

function RateLimitObservabilityService:OnStart()
	if self._started then
		return
	end

	self._started = true
	task.spawn(function()
		while true do
			local budgets = getBudgetSnapshot()
			local telemetry = RateLimitTelemetry.GetSnapshot()
			warn(string.format(
				"[RateLimitObservability] budgets standardRead=%d standardWrite=%d orderedRead=%d orderedWrite=%d | remoteRejected=%s | dataStoreError=%s | platformError=%s",
				budgets.standardRead or -1,
				budgets.standardWrite or -1,
				budgets.orderedRead or -1,
				budgets.orderedWrite or -1,
				formatCounters(telemetry.remote_rejected),
				formatCounters(telemetry.data_store_error),
				formatCounters(telemetry.platform_error)
			))
			task.wait(LOG_INTERVAL_SECONDS)
		end
	end)
end

return RateLimitObservabilityService
