local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Cat Mech Elite",
	moveLabel = "Rainbow Blast",
	targetMode = "single",
	summaryTemplate = "{moveLabel} tracks {target} with a rainbow beam",
	description = "Cat Mech Elite shoots a rainbow laser beam at one player that tracks them for 2 seconds.",
})
