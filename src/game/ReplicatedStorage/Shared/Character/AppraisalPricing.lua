local BodyPartEconomy = require(script.Parent.BodyPartEconomy)

local AppraisalPricing = {}

AppraisalPricing.COST_MULTIPLIER = 3

local function normalizeWhole(value: any): number
	return math.max(0, math.floor(tonumber(value) or 0))
end

function AppraisalPricing.GetCostForSellValue(sellValue: any): number
	return normalizeWhole(sellValue) * AppraisalPricing.COST_MULTIPLIER
end

function AppraisalPricing.GetCost(record: any, piece: any): number
	return AppraisalPricing.GetCostForSellValue(BodyPartEconomy.GetSellValue(record, piece))
end

return table.freeze(AppraisalPricing)
