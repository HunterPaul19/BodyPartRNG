local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Captain Squid",
	moveLabel = "Canonfire",
	targetMode = "single",
	summaryTemplate = "{moveLabel} locks a cannon onto {target}",
	description = "Captain Squid summons a giant cannon that locks onto a player and shoots an explosive cannonball.",
})
