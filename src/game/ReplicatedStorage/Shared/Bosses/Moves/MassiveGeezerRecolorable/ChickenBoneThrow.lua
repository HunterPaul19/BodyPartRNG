local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Massive Geezer RECOLORABLE",
	moveLabel = "Chicken Bone Throw",
	targetMode = "all_players",
	summaryTemplate = "{moveLabel} peppers {targets} with bone projectiles",
	description = "Massive Geezer RECOLORABLE throws chicken bone projectiles at all players.",
})
