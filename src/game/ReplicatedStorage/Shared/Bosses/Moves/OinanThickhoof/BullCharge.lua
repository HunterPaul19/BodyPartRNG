local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Oinan Thickhoof",
	moveLabel = "Bull Charge",
	targetMode = "single",
	summaryTemplate = "{moveLabel} tears through {target}'s line",
	description = "Oinan Thickhoof charges forward for 2 seconds, dealing damage to anyone in the path.",
})
