local DataService = require(script.Parent.Parent.DataService)

local VipHandler = {}

local function applyVipState(player: Player, isOwned: boolean)
	DataService:SetVipOwned(player, isOwned)
end

function VipHandler.grant(player: Player, _context: any): (boolean, string?)
	applyVipState(player, true)
	return true, nil
end

function VipHandler.reconcileOnJoin(player: Player, context: any)
	applyVipState(player, typeof(context) == "table" and context.isOwned == true)
end

return VipHandler
