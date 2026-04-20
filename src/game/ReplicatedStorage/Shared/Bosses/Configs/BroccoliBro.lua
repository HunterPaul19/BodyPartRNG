local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfigFactory = require(ReplicatedStorage.Shared.Bosses.ConfigFactory)
local BossMoveTags = require(ReplicatedStorage.Shared.Bosses.MoveTags)
local BroccoliSprout = require(ReplicatedStorage.Shared.Bosses.Moves.BroccoliBro.BroccoliSprout)
local Grab = require(ReplicatedStorage.Shared.Bosses.Moves.BroccoliBro.Grab)
local Stomp = require(ReplicatedStorage.Shared.Bosses.Moves.BroccoliBro.Stomp)

return BossConfigFactory.Create({
	bossId = "Broccoli Bro",
	arenaId = "Suburban",
	walkSpeed = 13,
	aggroRadius = 110,
	leashRadius = 165,
	retargetCadenceSeconds = 0.45,
	abilityCadenceSeconds = 3.0,
	retargetSwapBuffer = 8,
	m1 = {
		cooldownSeconds = 3.0,
		maxRange = 12,
		weight = 2,
	},
	moves = {
		{
			label = "Grab",
			tags = { BossMoveTags.CloseSingle },
			module = Grab,
			moduleId = "Moves.BroccoliBro.Grab",
			cooldownSeconds = 6.0,
			minRange = 0,
			maxRange = 12,
			weight = 2,
			rootDuringCast = false,
			castTimeSeconds = 0.3,
			recoverySeconds = 0.45,
		},
		{
			label = "Broccoli Sprout",
			tags = { BossMoveTags.RangedSingle },
			module = BroccoliSprout,
			moduleId = "Moves.BroccoliBro.BroccoliSprout",
			cooldownSeconds = 8.5,
			minRange = 14,
			maxRange = 95,
			weight = 1,
			rootDuringCast = true,
			castTimeSeconds = 0.8,
			recoverySeconds = 0.7,
		},
		{
			label = "Stomp",
			tags = { BossMoveTags.AOE },
			module = Stomp,
			moduleId = "Moves.BroccoliBro.Stomp",
			cooldownSeconds = 12.0,
			minRange = 0,
			maxRange = 20,
			weight = 0.75,
			rootDuringCast = true,
			castTimeSeconds = 0.7,
			recoverySeconds = 0.6,
		},
	},
})
