local BossArenas = {}

local ARENA_DEFINITIONS = {
	table.freeze({
		arenaId = "Sakura",
		displayName = "Sakura",
		assetName = "Sakura",
		bossSpawnName = "BossSpawn",
		playerSpawnName = "PlayerSpawn",
	}),
	table.freeze({
		arenaId = "Spire",
		displayName = "Spire",
		assetName = "Spire",
		bossSpawnName = "BossSpawn",
		playerSpawnName = "PlayerSpawn",
	}),
	table.freeze({
		arenaId = "Suburban",
		displayName = "Suburban",
		assetName = "Suburban",
		bossSpawnName = "BossSpawn",
		playerSpawnName = "PlayerSpawn",
	}),
}

local definitionsById = {}

for _, definition in ipairs(ARENA_DEFINITIONS) do
	if definitionsById[definition.arenaId] ~= nil then
		error(string.format("[BossArenas] Duplicate arena definition for '%s'.", definition.arenaId), 0)
	end

	definitionsById[definition.arenaId] = definition
end

function BossArenas.GetDefinition(arenaId: string)
	if typeof(arenaId) ~= "string" or arenaId == "" then
		return nil
	end

	return definitionsById[arenaId]
end

function BossArenas.GetAll()
	local definitions = table.create(#ARENA_DEFINITIONS)
	for index, definition in ipairs(ARENA_DEFINITIONS) do
		definitions[index] = definition
	end

	return definitions
end

function BossArenas.HasDefinition(arenaId: string): boolean
	return BossArenas.GetDefinition(arenaId) ~= nil
end

return table.freeze(BossArenas)
