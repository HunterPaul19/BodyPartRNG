local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfigFactory = require(ReplicatedStorage.Shared.Bosses.ConfigFactory)
local BossMoveTags = require(ReplicatedStorage.Shared.Bosses.MoveTags)
local FireBurst = require(ReplicatedStorage.Shared.Bosses.Moves.FlameGuardGeneral.FireBurst)
local FlameSwing = require(ReplicatedStorage.Shared.Bosses.Moves.FlameGuardGeneral.FlameSwing)
local PrometheusSlash = require(ReplicatedStorage.Shared.Bosses.Moves.FlameGuardGeneral.PrometheusSlash)

return BossConfigFactory.Create({
	bossId = "Flame Guard General",
	arenaId = "Spire",
	walkSpeed = 13,
	aggroRadius = 118,
	leashRadius = 176,
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
			label = "Flame Swing",
			tags = { BossMoveTags.CloseSingle },
			module = FlameSwing,
			moduleId = "Moves.FlameGuardGeneral.FlameSwing",
			cooldownSeconds = 6.0,
			minRange = 0,
			maxRange = 13,
			weight = 2,
			rootDuringCast = false,
			castTimeSeconds = 0.3,
			recoverySeconds = 0.45,
		},
		{
			label = "Prometheus Slash",
			tags = { BossMoveTags.RangedSingle },
			module = PrometheusSlash,
			moduleId = "Moves.FlameGuardGeneral.PrometheusSlash",
			cooldownSeconds = 8.5,
			minRange = 14,
			maxRange = 90,
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
			minRange = 6,
			maxRange = 30,
			weight = 0.75,
			rootDuringCast = true,
			castTimeSeconds = 0.95,
			recoverySeconds = 0.85,
		},
	},
})
