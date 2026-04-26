local DataService = require(script.Parent.Parent.DataService)

local VipPlusHandler = {}

local function applyVipPlusState(player: Player, isOwned: boolean)
	DataService:SetVipPlusOwned(player, isOwned)
end

function VipPlusHandler.grant(player: Player, _context: any): (boolean, string?)
	applyVipPlusState(player, true)
	return true, nil
end

function VipPlusHandler.reconcileOnJoin(player: Player, context: any)
	applyVipPlusState(player, typeof(context) == "table" and context.isOwned == true)
end

return VipPlusHandler
