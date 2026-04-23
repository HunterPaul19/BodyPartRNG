local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfigFactory = require(ReplicatedStorage.Shared.Bosses.ConfigFactory)
local BossMoveTags = require(ReplicatedStorage.Shared.Bosses.MoveTags)
local AcidBreath = require(ReplicatedStorage.Shared.Bosses.Moves.MassiveGeezerRecolorable.AcidBreath)
local BodySlam = require(ReplicatedStorage.Shared.Bosses.Moves.MassiveGeezerRecolorable.BodySlam)
local EatChicken = require(ReplicatedStorage.Shared.Bosses.Moves.MassiveGeezerRecolorable.EatChicken)

return BossConfigFactory.Create({
	bossId = "Massive Geezer RECOLORABLE",
	arenaId = "Spire",
	recommendedCombatScore = 8500,
	baseHealth = 680000,
	walkSpeed = 11,
	aggroRadius = 124,
	leashRadius = 188,
	retargetCadenceSeconds = 0.55,
	abilityCadenceSeconds = 3.25,
	retargetSwapBuffer = 10,
	m1 = {
		cooldownSeconds = 3.2,
		weight = 2,
	},
	moves = {
		{
			label = "Body Slam",
			tags = { BossMoveTags.CloseSingle },
			module = BodySlam,
			moduleId = "Moves.MassiveGeezerRecolorable.BodySlam",
			cooldownSeconds = 6.8,
			weight = 2,
			rootDuringCast = true,
			castTimeSeconds = 0.6,
			recoverySeconds = 0.9,
		},
		{
			label = "Acid Breath",
			tags = { BossMoveTags.RangedSingle },
			module = AcidBreath,
			moduleId = "Moves.MassiveGeezerRecolorable.AcidBreath",
			cooldownSeconds = 9.5,
			weight = 1,
			rootDuringCast = true,
			castTimeSeconds = 0.85,
			recoverySeconds = 0.75,
		},
		{
			label = "Eat Chicken",
			tags = { BossMoveTags.AOE },
			module = EatChicken,
			moduleId = "Moves.MassiveGeezerRecolorable.EatChicken",
			cooldownSeconds = 13.0,
			weight = 0.75,
			rootDuringCast = true,
			castTimeSeconds = 1.0,
			recoverySeconds = 0.8,
		},
	},
})
