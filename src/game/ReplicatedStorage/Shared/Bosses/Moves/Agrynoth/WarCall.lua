local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Agrynoth",
	moveLabel = "War Call",
	targetMode = "all_players",
	summaryTemplate = "{moveLabel} summons ogres to hunt {targets}",
	description = "Agrynoth summons an army of ogre NPCs, one for each player, that target players.",
})
