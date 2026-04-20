local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Captain Squid",
	moveLabel = "Hook",
	targetMode = "single",
	summaryTemplate = "{moveLabel} snags {target} and hurls them away",
	description = "Captain Squid grabs a player with his hook and throws them away.",
})
