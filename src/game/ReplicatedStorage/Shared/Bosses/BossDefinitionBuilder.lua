local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossMoveTags = require(ReplicatedStorage.Shared.Bosses.MoveTags)

local BossDefinitionBuilder = {}

local DEFAULT_SCALE_MULTIPLIER = 12.5
local DEFAULT_WALK_SPEED = 14
local DEFAULT_AGGRO_RADIUS = 100
local DEFAULT_LEASH_RADIUS = 150
local DEFAULT_RETARGET_CADENCE_SECONDS = 0.5
local DEFAULT_ABILITY_CADENCE_SECONDS = 1.25
local DEFAULT_RETARGET_SWAP_BUFFER = 8
local DEFAULT_MOVE_TO_REFRESH_SECONDS = 0.25

local function normalizeString(value: any): string
	if typeof(value) ~= "string" then
		return ""
	end

	local trimmed = string.match(value, "%S.*")
	return trimmed or ""
end

local function normalizePositiveNumber(value: any, defaultValue: number): number
	local resolvedValue = tonumber(value)
	if resolvedValue == nil then
		return defaultValue
	end

	return math.max(0, resolvedValue)
end

local function normalizeTags(tags: any): { string }
	local normalizedTags = {}
	local seenTags = {}

	if typeof(tags) ~= "table" then
		return normalizedTags
	end

	for _, tag in ipairs(tags) do
		local normalizedTag = normalizeString(tag)
		if normalizedTag ~= "" and seenTags[normalizedTag] ~= true then
			seenTags[normalizedTag] = true
			table.insert(normalizedTags, normalizedTag)
		end
	end

	return normalizedTags
end

local function validateMoveTags(moveId: string, tags: { string })
	if #tags <= 0 then
		error(string.format("[BossDefinitionBuilder] Boss move '%s' must define at least one tag.", moveId), 0)
	end
end

local function freezeMoveDefinition(moveDefinition: any)
	local moveId = normalizeString(moveDefinition.id)
	if moveId == "" then
		error("[BossDefinitionBuilder] Boss moves must include a non-empty id.", 0)
	end

	local tags = normalizeTags(moveDefinition.tags)
	validateMoveTags(moveId, tags)

	local moduleValue = moveDefinition.module
	if typeof(moduleValue) ~= "table" then
		error(string.format("[BossDefinitionBuilder] Boss move '%s' must include a module table.", moveId), 0)
	end

	local moduleId = normalizeString(moveDefinition.moduleId)
	if moduleId == "" then
		moduleId = moveId
	end

	local animationFolderName = normalizeString(moveDefinition.animationFolderName)
	if animationFolderName == "" then
		animationFolderName = nil
	end

	local minRange = normalizePositiveNumber(moveDefinition.minRange, 0)
	local maxRange = normalizePositiveNumber(moveDefinition.maxRange, minRange)

	if maxRange < minRange then
		error(string.format(
			"[BossDefinitionBuilder] Boss move '%s' has maxRange %.2f smaller than minRange %.2f.",
			moveId,
			maxRange,
			minRange
		), 0)
	end

	return table.freeze({
		id = moveId,
		tags = table.freeze(tags),
		cooldownSeconds = normalizePositiveNumber(moveDefinition.cooldownSeconds, 1),
		minRange = minRange,
		maxRange = maxRange,
		weight = math.max(0.01, normalizePositiveNumber(moveDefinition.weight, 1)),
		rootDuringCast = moveDefinition.rootDuringCast == true,
		castTimeSeconds = normalizePositiveNumber(moveDefinition.castTimeSeconds, 0),
		recoverySeconds = normalizePositiveNumber(moveDefinition.recoverySeconds, 0),
		animationFolderName = animationFolderName,
		module = moduleValue,
		moduleId = moduleId,
	})
end

local function validateRequiredTags(bossId: string, moves: { any })
	local coveredTags = {}

	for _, moveDefinition in ipairs(moves) do
		for _, tag in ipairs(moveDefinition.tags) do
			coveredTags[tag] = true
		end
	end

	for _, requiredTag in ipairs(BossMoveTags.Required) do
		if coveredTags[requiredTag] ~= true then
			error(string.format(
				"[BossDefinitionBuilder] Boss '%s' is missing a move tagged '%s'.",
				bossId,
				requiredTag
			), 0)
		end
	end
end

function BossDefinitionBuilder.Create(definition: any)
	if typeof(definition) ~= "table" then
		error("[BossDefinitionBuilder] Boss definition must be a table.", 0)
	end

	local bossId = normalizeString(definition.bossId)
	if bossId == "" then
		error("[BossDefinitionBuilder] Boss definition must include a non-empty bossId.", 0)
	end

	local displayName = normalizeString(definition.displayName)
	if displayName == "" then
		displayName = bossId
	end

	local arenaId = normalizeString(definition.arenaId)
	if arenaId == "" then
		error(string.format("[BossDefinitionBuilder] Boss '%s' must include a non-empty arenaId.", bossId), 0)
	end

	local frozenMoves = {}
	local seenMoveIds = {}

	if typeof(definition.moves) ~= "table" or #definition.moves <= 0 then
		error(string.format("[BossDefinitionBuilder] Boss '%s' must include at least one move.", bossId), 0)
	end

	for _, moveDefinition in ipairs(definition.moves) do
		local frozenMoveDefinition = freezeMoveDefinition(moveDefinition)
		if seenMoveIds[frozenMoveDefinition.id] == true then
			error(string.format(
				"[BossDefinitionBuilder] Boss '%s' contains duplicate move id '%s'.",
				bossId,
				frozenMoveDefinition.id
			), 0)
		end

		seenMoveIds[frozenMoveDefinition.id] = true
		table.insert(frozenMoves, frozenMoveDefinition)
	end

	validateRequiredTags(bossId, frozenMoves)

	local aggroRadius = normalizePositiveNumber(definition.aggroRadius, DEFAULT_AGGRO_RADIUS)
	local leashRadius = normalizePositiveNumber(definition.leashRadius, DEFAULT_LEASH_RADIUS)
	if leashRadius < aggroRadius then
		leashRadius = aggroRadius
	end

	return table.freeze({
		bossId = bossId,
		displayName = displayName,
		arenaId = arenaId,
		scaleMultiplier = math.max(0.1, normalizePositiveNumber(definition.scaleMultiplier, DEFAULT_SCALE_MULTIPLIER)),
		walkSpeed = normalizePositiveNumber(definition.walkSpeed, DEFAULT_WALK_SPEED),
		aggroRadius = aggroRadius,
		leashRadius = leashRadius,
		retargetCadenceSeconds = normalizePositiveNumber(
			definition.retargetCadenceSeconds,
			DEFAULT_RETARGET_CADENCE_SECONDS
		),
		abilityCadenceSeconds = normalizePositiveNumber(
			definition.abilityCadenceSeconds,
			DEFAULT_ABILITY_CADENCE_SECONDS
		),
		retargetSwapBuffer = normalizePositiveNumber(
			definition.retargetSwapBuffer,
			DEFAULT_RETARGET_SWAP_BUFFER
		),
		moveToRefreshSeconds = normalizePositiveNumber(
			definition.moveToRefreshSeconds,
			DEFAULT_MOVE_TO_REFRESH_SECONDS
		),
		moves = table.freeze(frozenMoves),
	})
end

return table.freeze(BossDefinitionBuilder)
