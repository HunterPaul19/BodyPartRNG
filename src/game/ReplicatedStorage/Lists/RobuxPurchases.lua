local Marketplace = {
	Offers = {
		quick_roll = {
			offerKey = "quick_roll",
			displayName = "Quick Roll",
			kind = "pass",
			handlerKey = "quick_roll",
			grantMode = "entitlement",
			giftable = true,
			selfPurchase = {
				saleKind = "pass",
				robloxId = 1796153382,
			},
			giftPurchase = {
				saleKind = "product",
				robloxId = 3575813628,
			},
		},

		vip = {
			offerKey = "vip",
			displayName = "VIP",
			kind = "pass",
			handlerKey = "vip",
			grantMode = "entitlement",
			giftable = true,
			selfPurchase = {
				saleKind = "pass",
				robloxId = 1797047296,
			},
			giftPurchase = {
				saleKind = "product",
				robloxId = 3575813394,
			},
		},

		vip_plus = {
			offerKey = "vip_plus",
			displayName = "VIP+",
			kind = "pass",
			handlerKey = "vip_plus",
			grantMode = "entitlement",
			giftable = true,
			selfPurchase = {
				saleKind = "pass",
				robloxId = 1798162264,
			},
			giftPurchase = {
				saleKind = "product",
				robloxId = 3575813471,
			},
		},

		merchant_teleporter = {
			offerKey = "merchant_teleporter",
			displayName = "Merchant Teleporter",
			kind = "pass",
			handlerKey = "merchant_teleporter",
			grantMode = "entitlement",
			giftable = true,
			selfPurchase = {
				saleKind = "pass",
				robloxId = 1796393357,
			},
			giftPurchase = {
				saleKind = "product",
				robloxId = 3575813281,
			},
		},

		starter_pack = {
			offerKey = "starter_pack",
			displayName = "Starter Pack",
			kind = "product",
			handlerKey = "starter_pack",
			grantMode = "one_time",
			giftable = true,
			selfPurchase = {
				saleKind = "product",
				robloxId = 3575813696,
			},
			giftPurchase = {
				saleKind = "product",
				robloxId = 3575813551,
			},
		},
	},
}

Marketplace.SalesByRobloxId = {}
Marketplace.PassOffersById = {}
Marketplace.ProductOffersById = {}

for offerKey, offer in pairs(Marketplace.Offers) do
	offer.offerKey = offerKey

	local selfPurchase = offer.selfPurchase
	if typeof(selfPurchase) == "table" and typeof(selfPurchase.robloxId) == "number" then
		Marketplace.SalesByRobloxId[selfPurchase.robloxId] = {
			offerKey = offerKey,
			purchaseKind = "self",
			saleKind = selfPurchase.saleKind,
			robloxId = selfPurchase.robloxId,
		}

		if selfPurchase.saleKind == "pass" then
			Marketplace.PassOffersById[selfPurchase.robloxId] = offer
		elseif selfPurchase.saleKind == "product" then
			Marketplace.ProductOffersById[selfPurchase.robloxId] = offer
		end
	end

	local giftPurchase = offer.giftPurchase
	if typeof(giftPurchase) == "table" and typeof(giftPurchase.robloxId) == "number" then
		Marketplace.SalesByRobloxId[giftPurchase.robloxId] = {
			offerKey = offerKey,
			purchaseKind = "gift",
			saleKind = giftPurchase.saleKind,
			robloxId = giftPurchase.robloxId,
		}
		Marketplace.ProductOffersById[giftPurchase.robloxId] = offer
	end
end

function Marketplace.GetOffer(offerKey: string)
	return Marketplace.Offers[offerKey]
end

function Marketplace.GetSaleByRobloxId(robloxId: number)
	return Marketplace.SalesByRobloxId[robloxId]
end

return Marketplace
