local MerchantTeleporterHandler = {}

function MerchantTeleporterHandler.grant(_player: Player, _context: any): (boolean, string?)
	return true, nil
end

function MerchantTeleporterHandler.reconcileOnJoin(_player: Player, _context: any)
	return
end

return MerchantTeleporterHandler
