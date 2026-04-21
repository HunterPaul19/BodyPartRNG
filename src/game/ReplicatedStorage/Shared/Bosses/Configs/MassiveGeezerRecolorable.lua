local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfigFactory = require(ReplicatedStorage.Shared.Bosses.ConfigFactory)
local BossMoveTags = require(ReplicatedStorage.Shared.Bosses.MoveTags)
local AcidBreath = require(ReplicatedStorage.Shared.Bosses.Moves.MassiveGeezerRecolorable.AcidBreath)
local BodySlam = require(ReplicatedStorage.Shared.Bosses.Moves.MassiveGeezerRecolorable.BodySlam)
local ChickenBoneThrow = require(ReplicatedStorage.Shared.Bosses.Moves.MassiveGeezerRecolorable.ChickenBoneThrow)

return BossConfigFactory.Create({
	bossId = "Massive Geezer RECOLORABLE",
	arenaId = "Spire",
	walkSpeed = 11,
	aggroRadius = 124,
	leashRadius = 188,
	retargetCadenceSeconds = 0.55,
	abilityCadenceSeconds = 3.25,
	retargetSwapBuffer = 10,
	m1 = {
		cooldownSeconds = 3.2,
		maxRange = 13,
		weight = 2,
	},
	moves = {
		{
			label = "Body Slam",
			tags = { BossMoveTags.CloseSingle },
			module = BodySlam,
			moduleId = "Moves.MassiveGeezerRecolorable.BodySlam",
			cooldownSeconds = 6.8,
			minRange = 0,
			maxRange = 15,
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
			minRange = 15,
			maxRange = 90,
			weight = 1,
			rootDuringCast = true,
			castTimeSeconds = 0.85,
			recoverySeconds = 0.75,
		},
		{
			label = "Chicken Bone Throw",
			tags = { BossMoveTags.AOE },
			module = ChickenBoneThrow,
			moduleId = "Moves.MassiveGeezerRecolorable.ChickenBoneThrow",
			cooldownSeconds = 13.0,
			minRange = 0,
			maxRange = 100,
			weight = 0.75,
			rootDuringCast = true,
			castTimeSeconds = 1.0,
			recoverySeconds = 0.8,
		},
	},
})
