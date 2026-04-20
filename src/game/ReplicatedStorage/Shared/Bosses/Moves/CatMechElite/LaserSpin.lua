local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Cat Mech Elite",
	moveLabel = "Laser Spin",
	targetMode = "wide_area",
	summaryTemplate = "{moveLabel} sweeps spinning lasers across {target}'s space",
	description = "Cat Mech Elite shoots out 12 lasers that spin for 4 seconds and players have to jump over them.",
})
