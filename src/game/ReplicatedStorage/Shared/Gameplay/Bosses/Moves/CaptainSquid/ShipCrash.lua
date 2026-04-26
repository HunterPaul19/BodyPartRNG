local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Captain Squid",
	moveLabel = "Ship Crash",
	targetMode = "wide_area",
	summaryTemplate = "{moveLabel} sails through {target}'s lane",
	description = "Captain Squid summons a pirate ship that sails forward and damages anyone in its path.",
})
