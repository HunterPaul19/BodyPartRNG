local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfigFactory = require(ReplicatedStorage.Shared.Bosses.ConfigFactory)
local BossMoveTags = require(ReplicatedStorage.Shared.Bosses.MoveTags)
local BubbleBlast = require(ReplicatedStorage.Shared.Bosses.Moves.MerfinTheGreat.BubbleBlast)
local WaterBomb = require(ReplicatedStorage.Shared.Bosses.Moves.MerfinTheGreat.WaterBomb)
local WaveCrash = require(ReplicatedStorage.Shared.Bosses.Moves.MerfinTheGreat.WaveCrash)

return BossConfigFactory.Create({
	bossId = "Merfin the Great",
	arenaId = "Sakura",
	walkSpeed = 13,
	aggroRadius = 118,
	leashRadius = 175,
	retargetCadenceSeconds = 0.45,
	abilityCadenceSeconds = 3.0,
	retargetSwapBuffer = 9,
	m1 = {
		cooldownSeconds = 3.0,
		maxRange = 12,
		weight = 2,
	},
	moves = {
		{
			label = "Wave Crash",
			tags = { BossMoveTags.CloseSingle },
			module = WaveCrash,
			moduleId = "Moves.MerfinTheGreat.WaveCrash",
			cooldownSeconds = 6.0,
			minRange = 0,
			maxRange = 16,
			weight = 2,
			rootDuringCast = true,
			castTimeSeconds = 0.35,
			recoverySeconds = 0.5,
		},
		{
			label = "Water Bomb",
			tags = { BossMoveTags.RangedSingle },
			module = WaterBomb,
			moduleId = "Moves.MerfinTheGreat.WaterBomb",
			cooldownSeconds = 8.5,
			minRange = 16,
			maxRange = 95,
			weight = 1,
			rootDuringCast = true,
			castTimeSeconds = 0.95,
			recoverySeconds = 0.7,
		},
		{
			label = "Bubble Blast",
			tags = { BossMoveTags.AOE },
			module = BubbleBlast,
			moduleId = "Moves.MerfinTheGreat.BubbleBlast",
			cooldownSeconds = 12.0,
			minRange = 0,
			maxRange = 100,
			weight = 0.75,
			rootDuringCast = true,
			castTimeSeconds = 0.9,
			recoverySeconds = 0.8,
		},
	},
})
