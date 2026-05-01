local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local SizeConfig = require(ReplicatedStorage.Shared.Config.SizeConfig)

local CombatPower = {}

export type Stats = {
	damage: number?,
	health: number?,
	speed: number?,
}

function CombatPower.Calculate(stats: Stats?): number
	local safeStats = if typeof(stats) == "table" then stats else {}
	local damage = math.max(0, tonumber(safeStats.damage) or 0)
	local health = math.max(0, tonumber(safeStats.health) or 0)
	local speed = math.max(0, tonumber(safeStats.speed) or 0)

	return damage + (health * 8) + (speed * 25)
end

function CombatPower.CalculateAboveBase(finalStats: Stats?, baseStats: Stats?): number
	local safeFinalStats = if typeof(finalStats) == "table" then finalStats else {}
	local safeBaseStats = if typeof(baseStats) == "table" then baseStats else {}

	return CombatPower.Calculate({
		damage = math.max(0, (tonumber(safeFinalStats.damage) or 0) - (tonumber(safeBaseStats.damage) or 0)),
		health = math.max(0, (tonumber(safeFinalStats.health) or 0) - (tonumber(safeBaseStats.health) or 0)),
		speed = math.max(0, (tonumber(safeFinalStats.speed) or 0) - (tonumber(safeBaseStats.speed) or 0)),
	})
end

function CombatPower.GetBodyPartCombatMultiplier(record: any): number
	local mutationCombatMultiplier = MutationConfig.GetCombatMultiplier(nil)
	if typeof(record) == "table" then
		if typeof(record.mutationId) == "string" and MutationConfig.Get(record.mutationId) ~= nil then
			mutationCombatMultiplier = MutationConfig.GetCombatMultiplier(record.mutationId)
		else
			mutationCombatMultiplier = MutationConfig.GetCombatMultiplier(record.mutation)
		end
	end

	local sizeCombatMultiplier = SizeConfig.GetCombatMultiplier(nil)
	if typeof(record) == "table" then
		local sizeEntry = SizeConfig.GetByScale(record.sizeMultiplier)
		if sizeEntry then
			sizeCombatMultiplier = sizeEntry.combatMultiplier
		else
			sizeCombatMultiplier = SizeConfig.GetCombatMultiplier(record.sizeId)
		end
	end

	return math.max(0, mutationCombatMultiplier) * math.max(0, sizeCombatMultiplier)
end

function CombatPower.GetBodyPartContributionStats(piece: any, record: any): Stats
	local safePiece = if typeof(piece) == "table" then piece else {}
	local multiplier = CombatPower.GetBodyPartCombatMultiplier(record)

	return {
		damage = math.max(0, tonumber(safePiece.damageBonus) or 0) * multiplier,
		health = math.max(0, tonumber(safePiece.healthBonus) or 0) * multiplier,
		speed = math.max(0, tonumber(safePiece.speedBonus) or 0) * multiplier,
	}
end

function CombatPower.CalculateBodyPartPower(piece: any, record: any): number
	return CombatPower.Calculate(CombatPower.GetBodyPartContributionStats(piece, record))
end

return CombatPower
