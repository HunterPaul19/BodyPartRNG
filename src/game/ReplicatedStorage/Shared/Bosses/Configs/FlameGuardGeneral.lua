local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfigFactory = require(ReplicatedStorage.Shared.Bosses.ConfigFactory)
local BossMoveTags = require(ReplicatedStorage.Shared.Bosses.MoveTags)
local FireBurst = require(ReplicatedStorage.Shared.Bosses.Moves.FlameGuardGeneral.FireBurst)
local FlameSlash = require(ReplicatedStorage.Shared.Bosses.Moves.FlameGuardGeneral.FlameSlash)
local PrometheusSlash = require(ReplicatedStorage.Shared.Bosses.Moves.FlameGuardGeneral.PrometheusSlash)

return BossConfigFactory.Create({
	bossId = "Flame Guard General",
	arenaId = "Spire",
	recommendedCombatScore = 150,
	baseHealth = 5000,
	scaleMultiplier = 12.5,
	walkSpeed = 13,
	aggroRadius = 118,
	leashRadius = 176,
	retargetCadenceSeconds = 0.45,
	abilityCadenceSeconds = 4.5,
	retargetSwapBuffer = 9,
	m1 = {
		animationFolderName = "FlameGuardGeneral",
		cooldownSeconds = 3.0,
		weight = 2,
	},
	moves = {
		{
			label = "Flame Slash",
			tags = { BossMoveTags.CloseSingle },
			module = FlameSlash,
			moduleId = "Moves.FlameGuardGeneral.FlameSlash",
			cooldownSeconds = 6.0,
			weight = 2,
			rootDuringCast = true,
			castTimeSeconds = 0.3,
			recoverySeconds = 0.45,
		},
		{
			label = "Prometheus Slash",
			tags = { BossMoveTags.RangedSingle },
			module = PrometheusSlash,
			moduleId = "Moves.FlameGuardGeneral.PrometheusSlash",
			cooldownSeconds = 8.5,
			weight = 1,
			rootDuringCast = true,
			castTimeSeconds = 0.85,
			recoverySeconds = 0.65,
		},
		{
			label = "Fire Burst",
			tags = { BossMoveTags.AOE },
			module = FireBurst,
			moduleId = "Moves.FlameGuardGeneral.FireBurst",
			cooldownSeconds = 12.0,
			weight = 0.75,
			rootDuringCast = true,
			castTimeSeconds = 1.2,
			recoverySeconds = 2.8,
		},
	},
})
