local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfigFactory = require(ReplicatedStorage.Shared.Bosses.ConfigFactory)
local BossMoveTags = require(ReplicatedStorage.Shared.Bosses.MoveTags)
local BullCharge = require(ReplicatedStorage.Shared.Bosses.Moves.OinanThickhoof.BullCharge)
local BullRoar = require(ReplicatedStorage.Shared.Bosses.Moves.OinanThickhoof.BullRoar)
local Stomp = require(ReplicatedStorage.Shared.Bosses.Moves.OinanThickhoof.Stomp)

return BossConfigFactory.Create({
	bossId = "Oinan Thickhoof",
	arenaId = "Suburban",
	walkSpeed = 14,
	aggroRadius = 120,
	leashRadius = 180,
	retargetCadenceSeconds = 0.4,
	abilityCadenceSeconds = 2.75,
	retargetSwapBuffer = 8,
	m1 = {
		cooldownSeconds = 3.0,
		weight = 2,
	},
	moves = {
		{
			label = "Stomp",
			tags = { BossMoveTags.CloseSingle },
			module = Stomp,
			moduleId = "Moves.OinanThickhoof.Stomp",
			cooldownSeconds = 6.0,
			weight = 2,
			rootDuringCast = true,
			castTimeSeconds = 0.3,
			recoverySeconds = 0.45,
		},
		{
			label = "Bull Charge",
			tags = { BossMoveTags.RangedSingle },
			module = BullCharge,
			moduleId = "Moves.OinanThickhoof.BullCharge",
			cooldownSeconds = 8.5,
			weight = 1,
			rootDuringCast = true,
			castTimeSeconds = 0.4,
			recoverySeconds = 0.7,
		},
		{
			label = "Bull Roar",
			tags = { BossMoveTags.AOE },
			module = BullRoar,
			moduleId = "Moves.OinanThickhoof.BullRoar",
			cooldownSeconds = 12.0,
			weight = 0.75,
			rootDuringCast = true,
			castTimeSeconds = 0.8,
			recoverySeconds = 0.7,
		},
	},
})
