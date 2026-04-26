local RateLimitTelemetry = {}

local countersByCategory = {}

local function normalizeKey(value: any, fallback: string): string
	if typeof(value) ~= "string" or value == "" then
		return fallback
	end

	return value
end

function RateLimitTelemetry.Increment(category: string, key: string, amount: number?)
	local resolvedCategory = normalizeKey(category, "unknown")
	local resolvedKey = normalizeKey(key, "unknown")
	local resolvedAmount = math.max(1, math.floor(tonumber(amount) or 1))

	local countersByKey = countersByCategory[resolvedCategory]
	if countersByKey == nil then
		countersByKey = {}
		countersByCategory[resolvedCategory] = countersByKey
	end

	countersByKey[resolvedKey] = math.max(0, math.floor(tonumber(countersByKey[resolvedKey]) or 0)) + resolvedAmount
end

function RateLimitTelemetry.GetSnapshot(): { [string]: { [string]: number } }
	local snapshot = {}

	for category, countersByKey in pairs(countersByCategory) do
		local categorySnapshot = {}
		for key, value in pairs(countersByKey) do
			categorySnapshot[key] = math.max(0, math.floor(tonumber(value) or 0))
		end
		snapshot[category] = categorySnapshot
	end

	return snapshot
end

return RateLimitTelemetry
