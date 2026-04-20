local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Massive Geezer RECOLORABLE",
	moveLabel = "Acid Breath",
	targetMode = "single",
	summaryTemplate = "{moveLabel} drenches {target}'s lane in acid",
	description = "Massive Geezer RECOLORABLE spews acid at a targeted player and leaves a puddle of acid on the ground.",
})
