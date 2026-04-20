local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Magma Fiend",
	moveLabel = "Eruption",
	targetMode = "all_players",
	summaryTemplate = "{moveLabel} bursts lava beneath {targets}",
	description = "Magma Fiend creates a burst of lava underneath every player.",
})
