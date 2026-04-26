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

return CombatPower
