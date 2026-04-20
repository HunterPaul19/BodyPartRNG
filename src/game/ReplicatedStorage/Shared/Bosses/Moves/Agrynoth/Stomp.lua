local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Agrynoth",
	moveLabel = "Stomp",
	targetMode = "wide_area",
	summaryTemplate = "{moveLabel} hammers the ground around {target}",
	description = "Agrynoth stomps on the ground when players get close.",
})
