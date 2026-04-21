local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfigFactory = require(ReplicatedStorage.Shared.Bosses.ConfigFactory)
local BossMoveTags = require(ReplicatedStorage.Shared.Bosses.MoveTags)
local Eruption = require(ReplicatedStorage.Shared.Bosses.Moves.MagmaFiend.Eruption)
local MagmaThrow = require(ReplicatedStorage.Shared.Bosses.Moves.MagmaFiend.MagmaThrow)
local Stomp = require(ReplicatedStorage.Shared.Bosses.Moves.MagmaFiend.Stomp)

return BossConfigFactory.Create({
	bossId = "Magma Fiend",
	arenaId = "Suburban",
	walkSpeed = 12,
	aggroRadius = 117,
	leashRadius = 178,
	retargetCadenceSeconds = 0.5,
	abilityCadenceSeconds = 3.0,
	retargetSwapBuffer = 9,
	m1 = {
		cooldownSeconds = 3.0,
		weight = 2,
	},
	moves = {
		{
			label = "Stomp",
			tags = { BossMoveTags.CloseSingle },
			module = Stomp,
			moduleId = "Moves.MagmaFiend.Stomp",
			cooldownSeconds = 6.0,
			weight = 2,
			rootDuringCast = true,
			castTimeSeconds = 0.35,
			recoverySeconds = 0.45,
		},
		{
			label = "Magma Throw",
			tags = { BossMoveTags.RangedSingle },
			module = MagmaThrow,
			moduleId = "Moves.MagmaFiend.MagmaThrow",
			cooldownSeconds = 8.5,
			weight = 1,
			rootDuringCast = true,
			castTimeSeconds = 0.75,
			recoverySeconds = 0.6,
		},
		{
			label = "Eruption",
			tags = { BossMoveTags.AOE },
			module = Eruption,
			moduleId = "Moves.MagmaFiend.Eruption",
			cooldownSeconds = 12.0,
			weight = 0.75,
			rootDuringCast = true,
			castTimeSeconds = 1.05,
			recoverySeconds = 0.8,
		},
	},
})
