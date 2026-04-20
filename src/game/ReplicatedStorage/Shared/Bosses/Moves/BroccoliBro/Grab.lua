local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Broccoli Bro",
	moveLabel = "Grab",
	targetMode = "single",
	summaryTemplate = "{moveLabel} seizes {target} and spikes them down",
	description = "Broccoli Bro grabs a player and throws them at the ground.",
})
