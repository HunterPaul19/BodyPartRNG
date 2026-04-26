local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Flame Guard General",
	moveLabel = "Flame Swing",
	targetMode = "single",
	summaryTemplate = "{moveLabel} cleaves into {target}",
	description = "Flame Guard General swings his sword forward, dealing damage to anyone close.",
})
