local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Flame Guard General",
	moveLabel = "Fire Burst",
	targetMode = "wide_area",
	summaryTemplate = "{moveLabel} blasts a jumping shockwave around {target}",
	description = "Flame Guard General stabs his sword into the ground and releases a shockwave of fire that players have to jump over.",
})
