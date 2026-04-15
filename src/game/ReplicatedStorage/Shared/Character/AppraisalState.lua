local AppraisalConfig = require(script.Parent.Parent.Config.AppraisalConfig)

local AppraisalState = {}

export type AppraisalStateValue = {
	cycleId: number,
	isActive: boolean,
	stockRemaining: number,
	stockPerSpawn: number,
	departsAt: number,
	nextAppearsAt: number,
}

local function normalizeWhole(value: any, minimum: number, maximum: number): number
	return math.clamp(math.floor(tonumber(value) or 0), minimum, maximum)
end

function AppraisalState.CreateEmptyState(): AppraisalStateValue
	return {
		cycleId = -1,
		isActive = false,
		stockRemaining = 0,
		stockPerSpawn = AppraisalConfig.stockPerSpawn,
		departsAt = 0,
		nextAppearsAt = 0,
	}
end

function AppraisalState.CloneState(state: any): AppraisalStateValue
	local emptyState = AppraisalState.CreateEmptyState()
	if typeof(state) ~= "table" then
		return emptyState
	end

	local stockPerSpawn = normalizeWhole(
		state.stockPerSpawn,
		1,
		math.max(1, AppraisalConfig.stockPerSpawn)
	)

	return {
		cycleId = math.floor(tonumber(state.cycleId) or emptyState.cycleId),
		isActive = state.isActive == true,
		stockRemaining = normalizeWhole(state.stockRemaining, 0, stockPerSpawn),
		stockPerSpawn = stockPerSpawn,
		departsAt = math.max(0, tonumber(state.departsAt) or emptyState.departsAt),
		nextAppearsAt = math.max(0, tonumber(state.nextAppearsAt) or emptyState.nextAppearsAt),
	}
end

function AppraisalState.AreEqual(a: any, b: any): boolean
	local left = AppraisalState.CloneState(a)
	local right = AppraisalState.CloneState(b)

	return left.cycleId == right.cycleId
		and left.isActive == right.isActive
		and left.stockRemaining == right.stockRemaining
		and left.stockPerSpawn == right.stockPerSpawn
		and left.departsAt == right.departsAt
		and left.nextAppearsAt == right.nextAppearsAt
end

return table.freeze(AppraisalState)
