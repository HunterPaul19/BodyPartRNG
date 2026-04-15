local MerchantTeleporterHandler = require(script.MerchantTeleporterHandler)
local QuickRollHandler = require(script.QuickRollHandler)
local StarterPackHandler = require(script.StarterPackHandler)
local VipHandler = require(script.VipHandler)
local VipPlusHandler = require(script.VipPlusHandler)

local MarketplaceHandlers = {
	merchant_teleporter = MerchantTeleporterHandler,
	quick_roll = QuickRollHandler,
	starter_pack = StarterPackHandler,
	vip = VipHandler,
	vip_plus = VipPlusHandler,
}

function MarketplaceHandlers.Get(handlerKey: string)
	return MarketplaceHandlers[handlerKey]
end

return MarketplaceHandlers
