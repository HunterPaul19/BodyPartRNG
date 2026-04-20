local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Merfin the Great",
	moveLabel = "Wave Crash",
	targetMode = "wide_area",
	summaryTemplate = "{moveLabel} surges through {target}'s path",
	description = "Merfin the Great creates a giant wave of water that travels forward and deals damage to players hit.",
})
