local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfigFactory = require(ReplicatedStorage.Shared.Bosses.ConfigFactory)
local BossMoveTags = require(ReplicatedStorage.Shared.Bosses.MoveTags)
local Canonfire = require(ReplicatedStorage.Shared.Bosses.Moves.CaptainSquid.Canonfire)
local Hook = require(ReplicatedStorage.Shared.Bosses.Moves.CaptainSquid.Hook)
local ShipCrash = require(ReplicatedStorage.Shared.Bosses.Moves.CaptainSquid.ShipCrash)

return BossConfigFactory.Create({
	bossId = "Captain Squid",
	arenaId = "Sakura",
	walkSpeed = 12,
	aggroRadius = 116,
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
			label = "Hook",
			tags = { BossMoveTags.CloseSingle },
			module = Hook,
			moduleId = "Moves.CaptainSquid.Hook",
			cooldownSeconds = 6.0,
			minRange = 0,
			maxRange = 14,
			weight = 2,
			rootDuringCast = false,
			castTimeSeconds = 0.4,
			recoverySeconds = 0.7,
		},
		{
			label = "Canonfire",
			tags = { BossMoveTags.RangedSingle },
			module = Canonfire,
			moduleId = "Moves.CaptainSquid.Canonfire",
			cooldownSeconds = 8.5,
			minRange = 16,
			maxRange = 100,
			weight = 1,
			rootDuringCast = true,
			castTimeSeconds = 0.9,
			recoverySeconds = 0.7,
		},
		{
			label = "Ship Crash",
			tags = { BossMoveTags.AOE },
			module = ShipCrash,
			moduleId = "Moves.CaptainSquid.ShipCrash",
			cooldownSeconds = 12.0,
			minRange = 8,
			maxRange = 40,
			weight = 0.75,
			rootDuringCast = true,
			castTimeSeconds = 1.1,
			recoverySeconds = 0.9,
		},
	},
})
