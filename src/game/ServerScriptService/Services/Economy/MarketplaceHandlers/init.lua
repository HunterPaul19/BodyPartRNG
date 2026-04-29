local MerchantTeleporterHandler = require(script.MerchantTeleporterHandler)
local PotionHandler = require(script.PotionHandler)
local QuickRollHandler = require(script.QuickRollHandler)
local StarterPackHandler = require(script.StarterPackHandler)
local TimeShardHandler = require(script.TimeShardHandler)
local VipHandler = require(script.VipHandler)
local VipPlusHandler = require(script.VipPlusHandler)

local MarketplaceHandlers = {
	merchant_teleporter = MerchantTeleporterHandler,
	potion = PotionHandler,
	quick_roll = QuickRollHandler,
	starter_pack = StarterPackHandler,
	time_shards = TimeShardHandler,
	vip = VipHandler,
	vip_plus = VipPlusHandler,
}

function MarketplaceHandlers.Get(handlerKey: string)
	return MarketplaceHandlers[handlerKey]
end

return MarketplaceHandlers
