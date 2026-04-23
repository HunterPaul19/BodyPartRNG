local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfigFactory = require(ReplicatedStorage.Shared.Bosses.ConfigFactory)
local BossMoveTags = require(ReplicatedStorage.Shared.Bosses.MoveTags)
local SquidCall = require(ReplicatedStorage.Shared.Bosses.Moves.CaptainSquid.SquidCall)
local Hook = require(ReplicatedStorage.Shared.Bosses.Moves.CaptainSquid.Hook)
local ShipCall = require(ReplicatedStorage.Shared.Bosses.Moves.CaptainSquid.ShipCall)

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
		weight = 2,
	},
	moves = {
		{
			label = "Hook",
			tags = { BossMoveTags.CloseSingle },
			module = Hook,
			moduleId = "Moves.CaptainSquid.Hook",
			cooldownSeconds = 14.0,
			weight = 0.5,
			rootDuringCast = true,
			castTimeSeconds = 0.4,
			recoverySeconds = 0.7,
		},
		{
			label = "Squid Call",
			tags = { BossMoveTags.RangedSingle },
			module = SquidCall,
			moduleId = "Moves.CaptainSquid.SquidCall",
			cooldownSeconds = 8.5,
			weight = 1,
			rootDuringCast = true,
			castTimeSeconds = 3.25,
			recoverySeconds = 0.4,
		},
		{
			label = "Ship Call",
			tags = { BossMoveTags.AOE },
			module = ShipCall,
			moduleId = "Moves.CaptainSquid.ShipCall",
			cooldownSeconds = 12.0,
			weight = 0.75,
			rootDuringCast = true,
			castTimeSeconds = 162 / 60,
			recoverySeconds = 0.9,
		},
	},
})
