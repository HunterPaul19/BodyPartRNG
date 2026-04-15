local StarterPackHandler = {}

function StarterPackHandler.grant(player: Player, _context: any): (boolean, string?)
	player:SetAttribute("StarterPackOwned", true)
	return true, nil
end

function StarterPackHandler.reconcileOnJoin(player: Player, context: any)
	player:SetAttribute("StarterPackOwned", typeof(context) == "table" and context.isOwned == true)
end

return StarterPackHandler
