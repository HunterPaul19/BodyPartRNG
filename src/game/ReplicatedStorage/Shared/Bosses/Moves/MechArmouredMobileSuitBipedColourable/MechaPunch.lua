local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Mech Armoured Mobile Suit Biped Colourable",
	moveLabel = "Mecha Punch",
	targetMode = "wide_area",
	summaryTemplate = "{moveLabel} detonates across {target}'s space",
	description = "The mech punches in front, creating an explosion that hits in a large radius.",
})
