local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Cat Mech Elite",
	moveLabel = "Cat Summon",
	targetMode = "none",
	summaryTemplate = "{moveLabel} calls in a regular cat mech support drop",
	description = "Cat Mech Elite shoots a flare into the air, then a regular cat mech falls from the sky and attacks players with normal M1s.",
})
