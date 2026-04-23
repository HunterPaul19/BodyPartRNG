export type EncounterScaling = {
	partySize: number,
	healthMultiplier: number,
	damageMultiplier: number,
}

local EncounterScaling = {}

local PARTY_SIZE_TO_SCALING: { [number]: EncounterScaling } = {
	[1] = table.freeze({
		partySize = 1,
		healthMultiplier = 1.00,
		damageMultiplier = 1.00,
	}),
	[2] = table.freeze({
		partySize = 2,
		healthMultiplier = 1.62,
		damageMultiplier = 1.08,
	}),
	[3] = table.freeze({
		partySize = 3,
		healthMultiplier = 2.24,
		damageMultiplier = 1.16,
	}),
	[4] = table.freeze({
		partySize = 4,
		healthMultiplier = 2.86,
		damageMultiplier = 1.24,
	}),
	[5] = table.freeze({
		partySize = 5,
		healthMultiplier = 3.48,
		damageMultiplier = 1.32,
	}),
	[6] = table.freeze({
		partySize = 6,
		healthMultiplier = 4.10,
		damageMultiplier = 1.40,
	}),
}

local MIN_PARTY_SIZE = 1
local MAX_PARTY_SIZE = 6

function EncounterScaling.GetForPartySize(partySize: number): EncounterScaling
	local resolvedPartySize = math.floor(tonumber(partySize) or MIN_PARTY_SIZE)
	resolvedPartySize = math.clamp(resolvedPartySize, MIN_PARTY_SIZE, MAX_PARTY_SIZE)

	return PARTY_SIZE_TO_SCALING[resolvedPartySize]
end

return table.freeze(EncounterScaling)
