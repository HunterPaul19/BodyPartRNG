local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossArenas = require(ReplicatedStorage.Shared.BossArenas)
local Agrynoth = require(ReplicatedStorage.Shared.Bosses.Configs.Agrynoth)
local BroccoliBro = require(ReplicatedStorage.Shared.Bosses.Configs.BroccoliBro)
local CaptainSquid = require(ReplicatedStorage.Shared.Bosses.Configs.CaptainSquid)
local CatMechElite = require(ReplicatedStorage.Shared.Bosses.Configs.CatMechElite)
local FlameGuardGeneral = require(ReplicatedStorage.Shared.Bosses.Configs.FlameGuardGeneral)
local MagmaFiend = require(ReplicatedStorage.Shared.Bosses.Configs.MagmaFiend)
local MassiveGeezerRecolorable = require(ReplicatedStorage.Shared.Bosses.Configs.MassiveGeezerRecolorable)
local MechArmouredMobileSuitBipedColourable =
	require(ReplicatedStorage.Shared.Bosses.Configs.MechArmouredMobileSuitBipedColourable)
local MerfinTheGreat = require(ReplicatedStorage.Shared.Bosses.Configs.MerfinTheGreat)
local OinanThickhoof = require(ReplicatedStorage.Shared.Bosses.Configs.OinanThickhoof)

local Bosses = {}

local BOSS_DEFINITIONS = {
	Agrynoth,
	BroccoliBro,
	CaptainSquid,
	CatMechElite,
	FlameGuardGeneral,
	MagmaFiend,
	MassiveGeezerRecolorable,
	MechArmouredMobileSuitBipedColourable,
	MerfinTheGreat,
	OinanThickhoof,
}

local definitionsById = {}

for _, definition in ipairs(BOSS_DEFINITIONS) do
	if definitionsById[definition.bossId] ~= nil then
		error(string.format("[Bosses] Duplicate boss definition for '%s'.", definition.bossId), 0)
	end
	if BossArenas.HasDefinition(definition.arenaId) ~= true then
		error(string.format(
			"[Bosses] Boss '%s' references unknown arena '%s'.",
			definition.bossId,
			tostring(definition.arenaId)
		), 0)
	end

	definitionsById[definition.bossId] = definition
end

function Bosses.GetDefinition(bossId: string)
	if typeof(bossId) ~= "string" or bossId == "" then
		return nil
	end

	return definitionsById[bossId]
end

function Bosses.GetAll()
	local definitions = table.create(#BOSS_DEFINITIONS)
	for index, definition in ipairs(BOSS_DEFINITIONS) do
		definitions[index] = definition
	end
	return definitions
end

function Bosses.HasDefinition(bossId: string): boolean
	return Bosses.GetDefinition(bossId) ~= nil
end

return table.freeze(Bosses)
