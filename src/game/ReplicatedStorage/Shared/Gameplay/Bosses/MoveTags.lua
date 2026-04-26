local BossMoveTags = {
	M1 = "M1",
	CloseSingle = "CloseSingle",
	RangedSingle = "RangedSingle",
	AOE = "AOE",
	Summon = "Summon",
}

BossMoveTags.Required = table.freeze({
	BossMoveTags.CloseSingle,
	BossMoveTags.RangedSingle,
	BossMoveTags.AOE,
})

return table.freeze(BossMoveTags)
