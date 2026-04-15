local DataService = require(script.Parent.Parent.DataService)

local QuickRollHandler = {}

function QuickRollHandler.grant(_player: Player, _context: any): (boolean, string?)
	return true, nil
end

function QuickRollHandler.reconcileOnJoin(player: Player, context: any)
	if typeof(context) ~= "table" or context.isOwned == true then
		return
	end

	DataService:SetQuickRollEnabled(player, false)
end

return QuickRollHandler
