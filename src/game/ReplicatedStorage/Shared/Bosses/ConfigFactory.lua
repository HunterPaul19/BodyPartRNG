local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossDefinitionBuilder = require(ReplicatedStorage.Shared.Bosses.BossDefinitionBuilder)
local BasicM1 = require(ReplicatedStorage.Shared.Bosses.Moves.Common.BasicM1)

local BossConfigFactory = {}
local INCLUDE_BOSS_M1_MOVES = false

local function slugify(value: string): string
	local normalized = string.lower(value)
	normalized = string.gsub(normalized, "[^%w]+", "_")
	normalized = string.gsub(normalized, "^_+", "")
	normalized = string.gsub(normalized, "_+$", "")
	if normalized == "" then
		return "boss"
	end

	return normalized
end

local function createMoveDefinition(bossId: string, moveSpec: { [string]: any })
	local label = if typeof(moveSpec.label) == "string" and moveSpec.label ~= "" then moveSpec.label else "Boss Move"
	local moveSlug = slugify(label)
	local moduleValue = moveSpec.module
	if typeof(moduleValue) ~= "table" then
		error(string.format(
			"[BossConfigFactory] Boss '%s' move '%s' must provide an explicit module table.",
			bossId,
			label
		), 0)
	end

	local moduleId = if typeof(moveSpec.moduleId) == "string" and moveSpec.moduleId ~= ""
		then moveSpec.moduleId
		else string.format("Moves.%s.%s", slugify(bossId), moveSlug)

	return {
		id = string.format("%s_%s", slugify(bossId), moveSlug),
		displayName = label,
		tags = moveSpec.tags,
		cooldownSeconds = moveSpec.cooldownSeconds,
		weight = moveSpec.weight,
		rootDuringCast = moveSpec.rootDuringCast ~= false,
		castTimeSeconds = moveSpec.castTimeSeconds,
		recoverySeconds = moveSpec.recoverySeconds,
		module = moduleValue,
		moduleId = moduleId,
	}
end

local function createM1Definition(bossId: string, m1Spec: { [string]: any }?)
	local resolvedSpec = m1Spec or {}

	return {
		id = string.format("%s_m1", slugify(bossId)),
		displayName = resolvedSpec.displayName or resolvedSpec.label or "M1",
		tags = resolvedSpec.tags or { "M1" },
		cooldownSeconds = resolvedSpec.cooldownSeconds or 1.5,
		weight = resolvedSpec.weight or 6,
		rootDuringCast = resolvedSpec.rootDuringCast ~= false,
		castTimeSeconds = resolvedSpec.castTimeSeconds or 0.18,
		recoverySeconds = resolvedSpec.recoverySeconds or 0.28,
		animationFolderName = resolvedSpec.animationFolderName,
		module = BasicM1,
		moduleId = "Common.BasicM1",
	}
end

function BossConfigFactory.Create(spec: { [string]: any })
	local moves = {}
	if INCLUDE_BOSS_M1_MOVES then
		table.insert(moves, createM1Definition(spec.bossId, spec.m1))
	end

	for _, moveSpec in ipairs(spec.moves or {}) do
		table.insert(moves, createMoveDefinition(spec.bossId, moveSpec))
	end

	return BossDefinitionBuilder.Create({
		bossId = spec.bossId,
		displayName = spec.displayName or spec.bossId,
		arenaId = spec.arenaId,
		scaleMultiplier = spec.scaleMultiplier,
		walkSpeed = spec.walkSpeed,
		aggroRadius = spec.aggroRadius,
		leashRadius = spec.leashRadius,
		retargetCadenceSeconds = spec.retargetCadenceSeconds,
		abilityCadenceSeconds = spec.abilityCadenceSeconds,
		retargetSwapBuffer = spec.retargetSwapBuffer,
		moveToRefreshSeconds = spec.moveToRefreshSeconds,
		moves = moves,
	})
end

return table.freeze(BossConfigFactory)
