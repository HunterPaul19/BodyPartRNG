local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfigFactory = require(ReplicatedStorage.Shared.Bosses.ConfigFactory)
local BossMoveTags = require(ReplicatedStorage.Shared.Bosses.MoveTags)
local BoneBreaker = require(ReplicatedStorage.Shared.Bosses.Moves.Agrynoth.BoneBreaker)
local Stomp = require(ReplicatedStorage.Shared.Bosses.Moves.Agrynoth.Stomp)
local WarCall = require(ReplicatedStorage.Shared.Bosses.Moves.Agrynoth.WarCall)

return BossConfigFactory.Create({
	bossId = "Agrynoth",
	arenaId = "Suburban",
	recommendedCombatScore = 6500,
	baseHealth = 420000,
	walkSpeed = 12,
	aggroRadius = 122,
	leashRadius = 182,
	retargetCadenceSeconds = 0.5,
	abilityCadenceSeconds = 3.0,
	retargetSwapBuffer = 10,
	m1 = {
		cooldownSeconds = 3.0,
		weight = 2,
	},
	moves = {
		{
			label = "Bone Breaker",
			tags = { BossMoveTags.CloseSingle },
			module = BoneBreaker,
			moduleId = "Moves.Agrynoth.BoneBreaker",
			cooldownSeconds = 6.0,
			weight = 2,
			rootDuringCast = true,
			castTimeSeconds = 0.5,
			recoverySeconds = 0.8,
		},
		{
			label = "War Call",
			tags = { BossMoveTags.RangedSingle, BossMoveTags.Summon },
			module = WarCall,
			moduleId = "Moves.Agrynoth.WarCall",
			cooldownSeconds = 8.5,
			weight = 1,
			rootDuringCast = true,
			castTimeSeconds = 1.1,
			recoverySeconds = 1.0,
		},
		{
			label = "Stomp",
			tags = { BossMoveTags.AOE },
			module = Stomp,
			moduleId = "Moves.Agrynoth.Stomp",
			cooldownSeconds = 12.0,
			weight = 0.75,
			rootDuringCast = true,
			castTimeSeconds = 0.85,
			recoverySeconds = 0.75,
		},
	},
})
