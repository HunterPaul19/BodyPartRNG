local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Merfin the Great",
	moveLabel = "Water Bomb",
	targetMode = "single",
	summaryTemplate = "{moveLabel} hurls a crashing water sphere at {target}",
	description = "Merfin the Great conjures a giant ball of water above his head and throws it toward a player, exploding in a large radius on impact.",
})
