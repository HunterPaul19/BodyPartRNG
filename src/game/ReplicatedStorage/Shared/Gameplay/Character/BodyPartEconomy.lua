local BodyPartEconomy = {}

function BodyPartEconomy.GetSellValue(record: any, piece: any): number
	local passiveIncomePerSecond = tonumber(record and record.finalPassiveIncomePerSecond)
		or tonumber(piece and piece.passiveIncomePerSecond)
		or 0
	return math.max(1, math.floor(passiveIncomePerSecond * 60))
end

return table.freeze(BodyPartEconomy)
