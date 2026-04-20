local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Massive Geezer RECOLORABLE",
	moveLabel = "Body Slam",
	targetMode = "single",
	summaryTemplate = "{moveLabel} crashes down onto {target}",
	description = "Massive Geezer RECOLORABLE jumps into the sky and slams his body onto a player.",
})
