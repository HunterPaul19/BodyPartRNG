local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Mech Armoured Mobile Suit Biped Colourable",
	moveLabel = "Mecha Kick",
	targetMode = "single",
	summaryTemplate = "{moveLabel} lashes into {target}",
	description = "The mech does a fast kick that hits any players close to it.",
})
