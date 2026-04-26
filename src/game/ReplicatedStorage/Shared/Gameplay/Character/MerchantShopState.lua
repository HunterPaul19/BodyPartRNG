local MerchantShopConfig = require(script.Parent.Parent.Config.MerchantShopConfig)

local MerchantShopState = {}

export type MerchantShopStockByPotionId = { [string]: number }

export type MerchantShopStateValue = {
	windowId: number,
	isActive: boolean,
	appearsAt: number,
	departsAt: number,
	nextAppearsAt: number,
	stockByPotionId: MerchantShopStockByPotionId,
}

local function normalizeWhole(value: any, minimum: number, maximum: number): number
	return math.clamp(math.floor(tonumber(value) or 0), minimum, maximum)
end

local function normalizeTimestamp(value: any): number
	return math.max(0, math.floor(tonumber(value) or 0))
end

function MerchantShopState.CreateEmptyState(): MerchantShopStateValue
	return {
		windowId = -1,
		isActive = false,
		appearsAt = 0,
		departsAt = 0,
		nextAppearsAt = 0,
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
			cloned[entry.potionId] = normalizeWhole(
				stockByPotionId[entry.potionId],
				0,
				MerchantShopConfig.GetMaxStockForPotionId(entry.potionId)
			)
		end
	end

	return cloned
end

function MerchantShopState.CloneState(state: any): MerchantShopStateValue
	local emptyState = MerchantShopState.CreateEmptyState()
	if typeof(state) ~= "table" then
		return emptyState
	end

	local windowId = math.floor(tonumber(state.windowId or state.cycleId) or emptyState.windowId)

	return {
		windowId = windowId,
		isActive = state.isActive == true,
		appearsAt = normalizeTimestamp(state.appearsAt),
		departsAt = normalizeTimestamp(state.departsAt),
		nextAppearsAt = normalizeTimestamp(state.nextAppearsAt),
		stockByPotionId = MerchantShopState.CloneStockByPotionId(state.stockByPotionId),
	}
end

return table.freeze(MerchantShopState)
