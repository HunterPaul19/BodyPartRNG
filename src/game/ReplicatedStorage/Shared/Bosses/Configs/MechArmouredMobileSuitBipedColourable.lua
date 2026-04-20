local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfigFactory = require(ReplicatedStorage.Shared.Bosses.ConfigFactory)
local BossMoveTags = require(ReplicatedStorage.Shared.Bosses.MoveTags)
local MechaKick = require(ReplicatedStorage.Shared.Bosses.Moves.MechArmouredMobileSuitBipedColourable.MechaKick)
local MechaPunch = require(ReplicatedStorage.Shared.Bosses.Moves.MechArmouredMobileSuitBipedColourable.MechaPunch)
local MissileBarrage = require(ReplicatedStorage.Shared.Bosses.Moves.MechArmouredMobileSuitBipedColourable.MissileBarrage)

return BossConfigFactory.Create({
	bossId = "Mech Armoured Mobile Suit Biped Colourable",
	arenaId = "Spire",
	walkSpeed = 14,
	aggroRadius = 122,
	leashRadius = 182,
	retargetCadenceSeconds = 0.4,
	abilityCadenceSeconds = 3.0,
	retargetSwapBuffer = 8,
	m1 = {
		cooldownSeconds = 3.0,
		maxRange = 12,
		weight = 2,
	},
	moves = {
		{
			label = "Mecha Kick",
			tags = { BossMoveTags.CloseSingle },
			module = MechaKick,
			moduleId = "Moves.MechArmouredMobileSuitBipedColourable.MechaKick",
			cooldownSeconds = 6.0,
			minRange = 0,
			maxRange = 13,
			weight = 2,
			rootDuringCast = false,
			castTimeSeconds = 0.25,
			recoverySeconds = 0.35,
		},
		{
			label = "Missile Barrage",
			tags = { BossMoveTags.RangedSingle },
			module = MissileBarrage,
			moduleId = "Moves.MechArmouredMobileSuitBipedColourable.MissileBarrage",
			cooldownSeconds = 8.5,
			minRange = 16,
			maxRange = 110,
			weight = 1,
			rootDuringCast = true,
			castTimeSeconds = 0.8,
			recoverySeconds = 0.7,
		},
		{
			label = "Mecha Punch",
			tags = { BossMoveTags.AOE },
			module = MechaPunch,
			moduleId = "Moves.MechArmouredMobileSuitBipedColourable.MechaPunch",
			cooldownSeconds = 12.0,
			minRange = 0,
			maxRange = 20,
			weight = 0.75,
			rootDuringCast = true,
			castTimeSeconds = 0.7,
			recoverySeconds = 0.7,
		},
	},
})
