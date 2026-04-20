local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Merfin the Great",
	moveLabel = "Bubble Blast",
	targetMode = "all_players",
	summaryTemplate = "{moveLabel} peppers {targets} with water shots",
	description = "Merfin the Great shoots out 10 water ball projectiles at players.",
})
