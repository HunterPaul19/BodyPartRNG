local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Cat Mech Elite",
	moveLabel = "Cat Spin",
	targetMode = "wide_area",
	summaryTemplate = "{moveLabel} shreds the space around {target}",
	description = "Cat Mech Elite spins like a blender and deals AOE damage to players close by.",
})
