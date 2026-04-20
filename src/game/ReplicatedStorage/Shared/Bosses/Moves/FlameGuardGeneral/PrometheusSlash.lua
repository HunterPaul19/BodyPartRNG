local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Flame Guard General",
	moveLabel = "Prometheus Slash",
	targetMode = "wide_area",
	summaryTemplate = "{moveLabel} carves a wall of fire toward {target}",
	description = "Flame Guard General brings his sword up and slashes downward, creating a long ranged AOE wall of fire.",
})
