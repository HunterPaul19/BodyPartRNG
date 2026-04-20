local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreateExplicitBossMoveStub = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateExplicitBossMoveStub)

return CreateExplicitBossMoveStub({
	bossId = "Oinan Thickhoof",
	moveLabel = "Bull Roar",
	targetMode = "wide_area",
	summaryTemplate = "{moveLabel} explodes around {target}",
	description = "Oinan Thickhoof roars and deals damage in a large AOE shockwave.",
})
