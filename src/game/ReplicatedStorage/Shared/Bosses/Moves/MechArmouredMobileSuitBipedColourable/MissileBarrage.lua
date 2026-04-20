local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Mech Armoured Mobile Suit Biped Colourable",
	moveLabel = "Missile Barrage",
	targetMode = "all_players",
	summaryTemplate = "{moveLabel} rains missiles onto {targets}",
	description = "The mech shoots missiles toward where every player is, targeting the ground without tracking.",
})
