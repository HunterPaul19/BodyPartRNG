local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Magma Fiend",
	moveLabel = "Magma Throw",
	targetMode = "single",
	summaryTemplate = "{moveLabel} lobs molten rock at {target}",
	description = "Magma Fiend throws a ball of magma at a player that leaves behind a damaging area of lava.",
})
