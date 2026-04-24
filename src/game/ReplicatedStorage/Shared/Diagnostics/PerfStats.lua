local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local PerfStats = {}

local WARN_COOLDOWN_SECONDS = 5
local MAX_SERIALIZE_DEPTH = 4
local PAYLOAD_ESTIMATE_SAMPLE_INTERVAL = 10

local THRESHOLDS = table.freeze({
	BodyPartVisualsApply = { ms = 25 },
	BodyPartVisualsReset = { ms = 20 },
	BodyPartSellAll = { ms = 8 },
	FoliageStep = { ms = 4 },
	InventorySyncList = { ms = 10 },
	LeaderboardRefreshRows = { ms = 8 },
	LoadoutUpdated = { ms = 2, bytes = 15000 },
	PassiveIncomeTick = { ms = 4 },
	PerformRoll = { ms = 10, bytes = 25000 },
	RollingUpdated = { ms = 2, bytes = 12000 },
})

local lastWarnAtByLabel: { [string]: number } = {}
local payloadEstimateCountByLabel: { [string]: number } = {}

local function toSafeValue(value: any, depth: number, seen: { [any]: boolean }): any
	if depth >= MAX_SERIALIZE_DEPTH then
		return "<max-depth>"
	end

	local valueType = typeof(value)
	if valueType == "nil"
		or valueType == "boolean"
		or valueType == "number"
		or valueType == "string"
	then
		return value
	end

	if valueType == "Color3" then
		return string.format("Color3(%d,%d,%d)", value.R * 255, value.G * 255, value.B * 255)
	end

	if valueType == "Vector2" or valueType == "Vector3" or valueType == "UDim2" or valueType == "CFrame" then
		return tostring(value)
	end

	if valueType == "EnumItem" then
		return tostring(value)
	end

	if valueType == "Instance" then
		return string.format("<%s:%s>", value.ClassName, value.Name)
	end

	if valueType ~= "table" then
		return string.format("<%s>", valueType)
	end

	if seen[value] then
		return "<cycle>"
	end

	seen[value] = true

	local isArray = #value > 0
	if isArray then
		local copy = table.create(math.min(#value, 50))
		for index = 1, math.min(#value, 50) do
			copy[index] = toSafeValue(value[index], depth + 1, seen)
		end
		if #value > 50 then
			copy[51] = string.format("<+%d more>", #value - 50)
		end
		seen[value] = nil
		return copy
	end

	local copy = {}
	local count = 0
	for key, child in pairs(value) do
		count += 1
		if count > 50 then
			copy.__truncated = string.format("+%d more", count - 50)
			break
		end

		copy[tostring(key)] = toSafeValue(child, depth + 1, seen)
	end

	seen[value] = nil
	return copy
end

local function shouldWarn(label: string, elapsedMs: number, payloadBytes: number?): boolean
	local thresholds = THRESHOLDS[label]
	if not thresholds then
		return false
	end

	if thresholds.ms and elapsedMs >= thresholds.ms then
		return true
	end

	if thresholds.bytes and payloadBytes and payloadBytes >= thresholds.bytes then
		return true
	end

	return false
end

local function shouldEstimatePayloadBytes(label: string): boolean
	local thresholds = THRESHOLDS[label]
	if not (thresholds and thresholds.bytes) then
		return false
	end

	local count = (payloadEstimateCountByLabel[label] or 0) + 1
	payloadEstimateCountByLabel[label] = count
	return count == 1 or count % PAYLOAD_ESTIMATE_SAMPLE_INTERVAL == 0
end

function PerfStats.Begin(): number
	return os.clock()
end

function PerfStats.EstimatePayloadBytes(payload: any): number?
	local safePayload = toSafeValue(payload, 0, {})
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(safePayload)
	end)
	if not ok then
		return nil
	end

	return #encoded
end

function PerfStats.Measure(label: string, startedAt: number, metadata: { payload: any?, detail: string? }?): (number, number?)
	local elapsedMs = (os.clock() - startedAt) * 1000
	local payloadBytes = nil
	if metadata and metadata.payload ~= nil and shouldEstimatePayloadBytes(label) then
		payloadBytes = PerfStats.EstimatePayloadBytes(metadata.payload)
	end

	if shouldWarn(label, elapsedMs, payloadBytes) then
		local now = os.clock()
		local lastWarnAt = lastWarnAtByLabel[label] or 0
		if now - lastWarnAt >= WARN_COOLDOWN_SECONDS then
			lastWarnAtByLabel[label] = now

			local environment = if RunService:IsServer() then "server" else "client"
			local payloadText = if payloadBytes then string.format(", payload=%dB", payloadBytes) else ""
			local detailText = if metadata and metadata.detail then string.format(", %s", metadata.detail) else ""
			warn(string.format("[PerfStats][%s] %s took %.2fms%s%s", environment, label, elapsedMs, payloadText, detailText))
		end
	end

	return elapsedMs, payloadBytes
end

return table.freeze(PerfStats)
