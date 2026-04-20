local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Agrynoth",
	moveLabel = "Bone Breaker",
	targetMode = "single",
	summaryTemplate = "{moveLabel} smashes {target} into the ground three times",
	description = "Agrynoth grabs a player and smashes them into the ground three times, creating a shockwave each time.",
})
