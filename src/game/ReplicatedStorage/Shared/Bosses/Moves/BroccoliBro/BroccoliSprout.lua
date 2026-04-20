local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Broccoli Bro",
	moveLabel = "Broccoli Sprout",
	targetMode = "all_players",
	summaryTemplate = "{moveLabel} erupts beneath {targets}",
	description = "Broccoli Bro makes giant broccoli trees sprout below all players, dealing damage.",
})
