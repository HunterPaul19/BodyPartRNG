local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfigFactory = require(ReplicatedStorage.Shared.Bosses.ConfigFactory)
local BossMoveTags = require(ReplicatedStorage.Shared.Bosses.MoveTags)
local CatSpin = require(ReplicatedStorage.Shared.Bosses.Moves.CatMechElite.CatSpin)
local CatSummon = require(ReplicatedStorage.Shared.Bosses.Moves.CatMechElite.CatSummon)
local LaserSpin = require(ReplicatedStorage.Shared.Bosses.Moves.CatMechElite.LaserSpin)
local RainbowBlast = require(ReplicatedStorage.Shared.Bosses.Moves.CatMechElite.RainbowBlast)

return BossConfigFactory.Create({
	bossId = "Cat Mech Elite",
	arenaId = "Sakura",
	walkSpeed = 15,
	aggroRadius = 120,
	leashRadius = 178,
	retargetCadenceSeconds = 0.35,
	abilityCadenceSeconds = 3.0,
	retargetSwapBuffer = 7,
	m1 = {
		cooldownSeconds = 3.0,
		maxRange = 11,
		weight = 2,
	},
	moves = {
		{
			label = "Cat Spin",
			tags = { BossMoveTags.CloseSingle },
			module = CatSpin,
			moduleId = "Moves.CatMechElite.CatSpin",
			cooldownSeconds = 6.0,
			minRange = 0,
			maxRange = 16,
			weight = 2,
			rootDuringCast = false,
			castTimeSeconds = 0.35,
			recoverySeconds = 0.45,
		},
		{
			label = "Rainbow Blast",
			tags = { BossMoveTags.RangedSingle },
			module = RainbowBlast,
			moduleId = "Moves.CatMechElite.RainbowBlast",
			cooldownSeconds = 8.5,
			minRange = 16,
			maxRange = 85,
			weight = 1,
			rootDuringCast = true,
			castTimeSeconds = 0.7,
			recoverySeconds = 0.55,
		},
		{
			label = "Laser Spin",
			tags = { BossMoveTags.AOE },
			module = LaserSpin,
			moduleId = "Moves.CatMechElite.LaserSpin",
			cooldownSeconds = 12.0,
			minRange = 0,
			maxRange = 24,
			weight = 0.75,
			rootDuringCast = true,
			castTimeSeconds = 1.0,
			recoverySeconds = 0.9,
		},
		{
			label = "Cat Summon",
			tags = { BossMoveTags.Summon },
			module = CatSummon,
			moduleId = "Moves.CatMechElite.CatSummon",
			cooldownSeconds = 16.0,
			minRange = 0,
			maxRange = 120,
			weight = 0.5,
			rootDuringCast = true,
			castTimeSeconds = 1.0,
			recoverySeconds = 1.0,
		},
	},
})
