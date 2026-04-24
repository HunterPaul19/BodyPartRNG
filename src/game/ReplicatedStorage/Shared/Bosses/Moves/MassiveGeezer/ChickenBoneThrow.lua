local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Massive Geezer",
	moveLabel = "Chicken Bone Throw",
	targetMode = "all_players",
	summaryTemplate = "{moveLabel} peppers {targets} with bone projectiles",
	description = "Massive Geezer throws chicken bone projectiles at all players.",
})
