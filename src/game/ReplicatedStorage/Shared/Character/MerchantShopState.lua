local MerchantShopConfig = require(script.Parent.Parent.Config.MerchantShopConfig)

local MerchantShopState = {}

export type MerchantShopStockByPotionId = { [string]: number }

export type MerchantShopStateValue = {
	cycleId: number,
	stockByPotionId: MerchantShopStockByPotionId,
}

local function normalizeWhole(value: any, minimum: number, maximum: number): number
	return math.clamp(math.floor(tonumber(value) or 0), minimum, maximum)
end

function MerchantShopState.CreateEmptyState(): MerchantShopStateValue
	return {
		cycleId = -1,
		stockByPotionId = {},
	}
end

function MerchantShopState.CloneStockByPotionId(stockByPotionId: any): MerchantShopStockByPotionId
	local cloned = {}
	if typeof(stockByPotionId) ~= "table" then
		return cloned
	end

	for _, entry in ipairs(MerchantShopConfig.GetAll()) do
		if stockByPotionId[entry.potionId] ~= nil then
			cloned[entry.potionId] = normalizeWhole(stockByPotionId[entry.potionId], 0, 10)
		end
	end

	return cloned
end

function MerchantShopState.CloneState(state: any): MerchantShopStateValue
	local emptyState = MerchantShopState.CreateEmptyState()
	if typeof(state) ~= "table" then
		return emptyState
	end

	return {
		cycleId = math.floor(tonumber(state.cycleId) or emptyState.cycleId),
		stockByPotionId = MerchantShopState.CloneStockByPotionId(state.stockByPotionId),
	}
end

return table.freeze(MerchantShopState)
