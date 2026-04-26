local AppraisalPricing = {}

AppraisalPricing.COST_MULTIPLIER = 5

local function normalizeWhole(value: any): number
	return math.max(0, math.floor(tonumber(value) or 0))
end

function AppraisalPricing.GetCostForBasePassiveIncome(passiveIncomePerSecond: any): number
	return normalizeWhole(passiveIncomePerSecond) * AppraisalPricing.COST_MULTIPLIER
end

function AppraisalPricing.GetCost(record: any, piece: any): number
	return AppraisalPricing.GetCostForBasePassiveIncome(piece and piece.passiveIncomePerSecond)
end

return table.freeze(AppraisalPricing)
