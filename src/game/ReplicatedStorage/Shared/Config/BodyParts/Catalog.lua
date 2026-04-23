local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RollMath = require(ReplicatedStorage.Shared.Rolling.RollMath)
local RawPieces = require(script.Parent.Pieces)
local RawSets = require(script.Parent.Sets)

export type BodyRegion = "Head" | "Torso" | "LeftArm" | "RightArm" | "LeftLeg" | "RightLeg"

export type AttachRuleConfig = {
	templateChildName: string?,
	offsetCFrame: CFrame?,
	visualOffsetCFrame: CFrame?,
	hideCharacterPart: boolean?,
}

export type PieceConfig = {
	id: string,
	displayName: string,
	region: BodyRegion,
	setId: string,
	assetGroup: string,
	assetModel: string,
	rarity: number,
	passiveIncomePerSecond: number,
	luckBonus: number,
	rollSpeedBonus: number,
	speedBonus: number,
	damageBonus: number,
	healthBonus: number,
	attachRules: { [string]: AttachRuleConfig }?,
}

export type SetBonus = {
	passiveIncomePerSecond: number,
	luckBonus: number,
	rollSpeedBonus: number,
	speedBonus: number,
	damageBonus: number,
	healthBonus: number,
}

export type RollDisplay = {
	displayName: string,
	rarity: string,
	chance: number,
	passiveIncomePerSecond: number,
	color: Color3,
	fontFace: Font,
	fontWeight: Enum.FontWeight,
}

export type SetConfig = {
	id: string,
	displayName: string,
	bundleLink: string?,
	bundleId: number?,
	rollEnabled: boolean?,
	rollDisplay: RollDisplay,
	piecesByRegion: { [BodyRegion]: string },
	strength: number,
	health: number,
	speed: number,
	fullSetBonus: SetBonus,
}

export type RollEntry = SetConfig & {
	baseChance: number,
	displayedDenominator: number,
}

local Catalog = {}

local BASE_PLAYER_STATS = table.freeze({
	speed = 16,
	damage = 20,
	health = 100,
})

local REGION_ORDER: { BodyRegion } = {
	"Head",
	"Torso",
	"LeftArm",
	"RightArm",
	"LeftLeg",
	"RightLeg",
}

local REGION_LABELS: { [BodyRegion]: string } = {
	Head = "Head",
	Torso = "Torso",
	LeftArm = "Left Arm",
	RightArm = "Right Arm",
	LeftLeg = "Left Leg",
	RightLeg = "Right Leg",
}

local REGION_COMBAT_WEIGHTS = table.freeze({
	strength = table.freeze({
		Head = 0.15,
		Torso = 0.20,
		LeftArm = 0.25,
		RightArm = 0.25,
		LeftLeg = 0.075,
		RightLeg = 0.075,
	}),
	health = table.freeze({
		Head = 0.20,
		Torso = 0.30,
		LeftArm = 0.10,
		RightArm = 0.10,
		LeftLeg = 0.15,
		RightLeg = 0.15,
	}),
	speed = table.freeze({
		Head = 0.05,
		Torso = 0.10,
		LeftArm = 0.10,
		RightArm = 0.10,
		LeftLeg = 0.325,
		RightLeg = 0.325,
	}),
})

local VALID_REGIONS: { [string]: boolean } = {}
for _, region in ipairs(REGION_ORDER) do
	VALID_REGIONS[region] = true
end

local REQUIRED_PIECE_NUMBER_FIELDS = {
	"rarity",
	"passiveIncomePerSecond",
	"luckBonus",
	"rollSpeedBonus",
	"speedBonus",
	"damageBonus",
	"healthBonus",
}

local REQUIRED_SET_BONUS_FIELDS = {
	"passiveIncomePerSecond",
	"luckBonus",
	"rollSpeedBonus",
	"speedBonus",
	"damageBonus",
	"healthBonus",
}

local REQUIRED_SET_COMBAT_TOTAL_FIELDS = {
	"strength",
	"health",
	"speed",
}

local REQUIRED_ROLL_DISPLAY_NUMBER_FIELDS = {
	"chance",
	"passiveIncomePerSecond",
}

local function pushError(errors: { string }, message: string)
	table.insert(errors, message)
end

local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, child in pairs(value) do
		copy[key] = deepCopy(child)
	end

	return copy
end

local function deepFreeze(value: any): any
	if typeof(value) ~= "table" or table.isfrozen(value) then
		return value
	end

	for _, child in pairs(value) do
		if typeof(child) == "table" then
			deepFreeze(child)
		end
	end

	return table.freeze(value)
end

local function getBodyPartsRoot(): Folder?
	local gameAssets = ReplicatedStorage:WaitForChild("GameAssets", 10)
	if not (gameAssets and gameAssets:IsA("Folder")) then
		return nil
	end

	local bodyParts = gameAssets:WaitForChild("BodyParts", 10)
	if bodyParts and bodyParts:IsA("Folder") then
		return bodyParts
	end

	return nil
end

local function getDefaultBaseRig(): Model?
	local bodyParts = getBodyPartsRoot()
	if not bodyParts then
		return nil
	end

	local baseRigs = bodyParts:WaitForChild("BaseRigs", 10)
	if not (baseRigs and baseRigs:IsA("Folder")) then
		return nil
	end

	local baseRig = baseRigs:WaitForChild("DefaultR15", 10)
	if baseRig and baseRig:IsA("Model") then
		return baseRig
	end

	return nil
end

local function resolveBundleModelForPiece(piece: PieceConfig): Model?
	local bodyParts = getBodyPartsRoot()
	if not bodyParts then
		return nil
	end

	local bundles = bodyParts:WaitForChild("Bundles", 10)
	if not (bundles and bundles:IsA("Folder")) then
		return nil
	end

	local regionFolder = bundles:FindFirstChild(piece.region)
	if not (regionFolder and regionFolder:IsA("Folder")) then
		return nil
	end

	local groupFolder = regionFolder:FindFirstChild(piece.assetGroup)
	if not (groupFolder and groupFolder:IsA("Folder")) then
		return nil
	end

	local bundleModel = groupFolder:FindFirstChild(piece.assetModel)
	if bundleModel and bundleModel:IsA("Model") then
		return bundleModel
	end

	return nil
end

local function getCombatStatTier(chance: any): number
	local denominator = math.max(1, tonumber(chance) or 1)
	if denominator >= 1000000 then
		return 5
	elseif denominator >= 250000 then
		return 4
	elseif denominator >= 50000 then
		return 3
	elseif denominator >= 5000 then
		return 2
	elseif denominator >= 100 then
		return 1
	end

	return 0
end

local function hasExplicitSetCombatStats(setConfig: any): boolean
	return typeof(setConfig) == "table"
		and typeof(setConfig.strength) == "number"
		and typeof(setConfig.health) == "number"
		and typeof(setConfig.speed) == "number"
end

local function getDerivedPieceCombatStatsFromSet(setConfig: any, region: BodyRegion?): (number?, number?, number?)
	if not hasExplicitSetCombatStats(setConfig) or typeof(region) ~= "string" then
		return nil, nil, nil
	end

	local strengthWeight = REGION_COMBAT_WEIGHTS.strength[region] or 0
	local healthWeight = REGION_COMBAT_WEIGHTS.health[region] or 0
	local speedWeight = REGION_COMBAT_WEIGHTS.speed[region] or 0

	return (tonumber(setConfig.speed) or 0) * speedWeight,
		(tonumber(setConfig.strength) or 0) * strengthWeight,
		(tonumber(setConfig.health) or 0) * healthWeight
end

local function getDefaultPieceCombatStats(piece: any, setConfig: any?): (number, number, number)
	local region = if typeof(piece) == "table" then piece.region else nil
	local derivedSpeedBonus, derivedDamageBonus, derivedHealthBonus = getDerivedPieceCombatStatsFromSet(setConfig, region)
	if derivedSpeedBonus ~= nil and derivedDamageBonus ~= nil and derivedHealthBonus ~= nil then
		return derivedSpeedBonus, derivedDamageBonus, derivedHealthBonus
	end

	local weight = getCombatStatTier(piece and piece.rarity) + 1
	local speedBonus = 0.1 * weight
	local damageBonus = 0.5 * weight
	local healthBonus = 2 * weight

	if region == "Torso" then
		healthBonus += 3 * weight
	elseif region == "LeftArm" or region == "RightArm" then
		damageBonus += 0.5 * weight
	elseif region == "LeftLeg" or region == "RightLeg" then
		speedBonus += 0.15 * weight
	elseif region == "Head" then
		damageBonus += 0.25 * weight
		healthBonus += weight
	end

	return speedBonus, damageBonus, healthBonus
end

local function withDefaultPieceCombatStats(piece: any, setConfig: any?): any
	if typeof(piece) ~= "table" then
		return piece
	end

	local normalized = deepCopy(piece)
	local defaultSpeedBonus, defaultDamageBonus, defaultHealthBonus = getDefaultPieceCombatStats(normalized, setConfig)
	normalized.speedBonus = tonumber(normalized.speedBonus) or defaultSpeedBonus
	normalized.damageBonus = tonumber(normalized.damageBonus) or defaultDamageBonus
	normalized.healthBonus = tonumber(normalized.healthBonus) or defaultHealthBonus
	return normalized
end

local function withDefaultSetCombatStats(setConfig: any): any
	if typeof(setConfig) ~= "table" then
		return setConfig
	end

	local normalized = deepCopy(setConfig)
	if typeof(normalized.fullSetBonus) ~= "table" then
		return normalized
	end

	normalized.fullSetBonus.speedBonus = tonumber(normalized.fullSetBonus.speedBonus) or 0
	normalized.fullSetBonus.damageBonus = tonumber(normalized.fullSetBonus.damageBonus) or 0
	normalized.fullSetBonus.healthBonus = tonumber(normalized.fullSetBonus.healthBonus) or 0

	if not hasExplicitSetCombatStats(normalized) then
		normalized.strength = nil
		normalized.health = nil
		normalized.speed = nil
	end

	return normalized
end

local function finalizeSetCombatStats(setConfig: any, piecesById: { [string]: PieceConfig }): any
	if typeof(setConfig) ~= "table" then
		return setConfig
	end

	local normalized = deepCopy(setConfig)
	if hasExplicitSetCombatStats(normalized) then
		normalized.strength = tonumber(normalized.strength) or 0
		normalized.health = tonumber(normalized.health) or 0
		normalized.speed = tonumber(normalized.speed) or 0
		return normalized
	end

	local totalStrength = 0
	local totalHealth = 0
	local totalSpeed = 0
	local piecesByRegion = if typeof(normalized.piecesByRegion) == "table" then normalized.piecesByRegion else {}

	for _, region in ipairs(REGION_ORDER) do
		local pieceId = piecesByRegion[region]
		local piece = if typeof(pieceId) == "string" then piecesById[pieceId] else nil
		if piece then
			totalStrength += tonumber(piece.damageBonus) or 0
			totalHealth += tonumber(piece.healthBonus) or 0
			totalSpeed += tonumber(piece.speedBonus) or 0
		end
	end

	normalized.strength = totalStrength
	normalized.health = totalHealth
	normalized.speed = totalSpeed
	return normalized
end

local function getExpectedPieceDisplayName(setDisplayName: string, region: BodyRegion): string
	return string.format("%s %s", setDisplayName, REGION_LABELS[region] or tostring(region))
end

local function validatePieceConfig(pieceKey: string, piece: any, seenPieceIds: { [string]: boolean }, errors: { string })
	if typeof(piece) ~= "table" then
		pushError(errors, `Piece "{pieceKey}" must be a table`)
		return
	end

	if piece.id ~= pieceKey then
		pushError(errors, `Piece "{pieceKey}" must have id "{pieceKey}"`)
	end

	if typeof(piece.id) == "string" then
		if seenPieceIds[piece.id] then
			pushError(errors, `Duplicate piece id "{piece.id}" detected`)
		else
			seenPieceIds[piece.id] = true
		end
	end

	if typeof(piece.displayName) ~= "string" or piece.displayName == "" then
		pushError(errors, `Piece "{pieceKey}" is missing a displayName`)
	end

	if typeof(piece.region) ~= "string" or not VALID_REGIONS[piece.region] then
		pushError(errors, `Piece "{pieceKey}" has invalid region "{tostring(piece.region)}"`)
	end

	if typeof(piece.setId) ~= "string" or piece.setId == "" then
		pushError(errors, `Piece "{pieceKey}" is missing a setId`)
	end

	if typeof(piece.assetGroup) ~= "string" or piece.assetGroup == "" then
		pushError(errors, `Piece "{pieceKey}" is missing an assetGroup`)
	end

	if typeof(piece.assetModel) ~= "string" or piece.assetModel == "" then
		pushError(errors, `Piece "{pieceKey}" is missing an assetModel`)
	end

	for _, fieldName in ipairs(REQUIRED_PIECE_NUMBER_FIELDS) do
		if typeof(piece[fieldName]) ~= "number" then
			pushError(errors, `Piece "{pieceKey}" must provide numeric field "{fieldName}"`)
		end
	end
end

local function validateSetConfig(setKey: string, setConfig: any, piecesById: { [string]: PieceConfig }, seenSetIds: { [string]: boolean }, errors: { string })
	if typeof(setConfig) ~= "table" then
		pushError(errors, `Set "{setKey}" must be a table`)
		return
	end

	if setConfig.id ~= setKey then
		pushError(errors, `Set "{setKey}" must have id "{setKey}"`)
	end

	if typeof(setConfig.id) == "string" then
		if seenSetIds[setConfig.id] then
			pushError(errors, `Duplicate set id "{setConfig.id}" detected`)
		else
			seenSetIds[setConfig.id] = true
		end
	end

	if typeof(setConfig.displayName) ~= "string" or setConfig.displayName == "" then
		pushError(errors, `Set "{setKey}" is missing a displayName`)
	end
	if setConfig.rollEnabled ~= nil and typeof(setConfig.rollEnabled) ~= "boolean" then
		pushError(errors, `Set "{setKey}" must provide rollEnabled as a boolean when present`)
	end
	if setConfig.bundleLink ~= nil and (typeof(setConfig.bundleLink) ~= "string" or setConfig.bundleLink == "") then
		pushError(errors, `Set "{setKey}" must provide bundleLink as a non-empty string when present`)
	end
	if setConfig.bundleId ~= nil and (typeof(setConfig.bundleId) ~= "number" or setConfig.bundleId <= 0) then
		pushError(errors, `Set "{setKey}" must provide bundleId as a positive number when present`)
	end

	if typeof(setConfig.rollDisplay) ~= "table" then
		pushError(errors, `Set "{setKey}" must provide rollDisplay`)
	else
		if typeof(setConfig.rollDisplay.displayName) ~= "string" or setConfig.rollDisplay.displayName == "" then
			pushError(errors, `Set "{setKey}" must provide rollDisplay.displayName`)
		end
		if typeof(setConfig.rollDisplay.rarity) ~= "string" or setConfig.rollDisplay.rarity == "" then
			pushError(errors, `Set "{setKey}" must provide rollDisplay.rarity`)
		end
		if typeof(setConfig.rollDisplay.color) ~= "Color3" then
			pushError(errors, `Set "{setKey}" must provide rollDisplay.color as a Color3`)
		end
		if typeof(setConfig.rollDisplay.fontFace) ~= "Font" then
			pushError(errors, `Set "{setKey}" must provide rollDisplay.fontFace as a Font`)
		end
		if typeof(setConfig.rollDisplay.fontWeight) ~= "EnumItem" then
			pushError(errors, `Set "{setKey}" must provide rollDisplay.fontWeight as an EnumItem`)
		end
		for _, fieldName in ipairs(REQUIRED_ROLL_DISPLAY_NUMBER_FIELDS) do
			if typeof(setConfig.rollDisplay[fieldName]) ~= "number" then
				pushError(errors, `Set "{setKey}" must provide numeric rollDisplay field "{fieldName}"`)
			end
		end
	end

	if typeof(setConfig.piecesByRegion) ~= "table" then
		pushError(errors, `Set "{setKey}" must provide piecesByRegion`)
	else
		local seenRegions: { [string]: boolean } = {}
		local seenPieceIds: { [string]: boolean } = {}

		for region, pieceId in pairs(setConfig.piecesByRegion) do
			if typeof(region) ~= "string" or not VALID_REGIONS[region] then
				pushError(errors, `Set "{setKey}" contains invalid region "{tostring(region)}"`)
			elseif seenRegions[region] then
				pushError(errors, `Set "{setKey}" contains duplicate region "{region}"`)
			else
				seenRegions[region] = true
			end

			if typeof(pieceId) ~= "string" then
				pushError(errors, `Set "{setKey}" region "{tostring(region)}" must reference a piece id`)
			else
				local piece = piecesById[pieceId]
				if not piece then
					pushError(errors, `Set "{setKey}" references missing piece "{pieceId}"`)
				else
					if piece.region ~= region then
						pushError(errors, `Set "{setKey}" region "{region}" must point to a "{region}" piece`)
					end
					if piece.setId ~= setKey then
						pushError(errors, `Piece "{pieceId}" must point back to set "{setKey}"`)
					end
					if typeof(setConfig.displayName) == "string" then
						local expectedDisplayName = getExpectedPieceDisplayName(setConfig.displayName, region)
						if piece.displayName ~= expectedDisplayName then
							pushError(
								errors,
								`Piece "{pieceId}" displayName "{piece.displayName}" must match "{expectedDisplayName}"`
							)
						end
					end
				end

				if seenPieceIds[pieceId] then
					pushError(errors, `Set "{setKey}" references piece "{pieceId}" more than once`)
				else
					seenPieceIds[pieceId] = true
				end
			end
		end

		for _, region in ipairs(REGION_ORDER) do
			if not seenRegions[region] then
				pushError(errors, `Set "{setKey}" is missing region "{region}"`)
			end
		end
	end

	if typeof(setConfig.fullSetBonus) ~= "table" then
		pushError(errors, `Set "{setKey}" must provide fullSetBonus`)
	else
		for _, fieldName in ipairs(REQUIRED_SET_BONUS_FIELDS) do
			if typeof(setConfig.fullSetBonus[fieldName]) ~= "number" then
				pushError(errors, `Set "{setKey}" must provide numeric fullSetBonus field "{fieldName}"`)
			end
		end
	end

	for _, fieldName in ipairs(REQUIRED_SET_COMBAT_TOTAL_FIELDS) do
		if typeof(setConfig[fieldName]) ~= "number" then
			pushError(errors, `Set "{setKey}" must provide numeric field "{fieldName}"`)
		end
	end
end

local function buildCatalog()
	local errors = {}
	local seenPieceIds: { [string]: boolean } = {}
	local seenSetIds: { [string]: boolean } = {}
	local piecesById: { [string]: PieceConfig } = {}
	local setsById: { [string]: SetConfig } = {}
	local piecesForSet: { [string]: { PieceConfig } } = {}
	local setByPieceId: { [string]: SetConfig } = {}
	local allPieces = {}
	local allSets = {}
	local normalizedRawSetsById: { [string]: any } = {}

	for setKey, rawSetConfig in pairs(RawSets) do
		normalizedRawSetsById[setKey] = withDefaultSetCombatStats(rawSetConfig)
	end

	for pieceKey, rawPiece in pairs(RawPieces) do
		local setConfig = if typeof(rawPiece) == "table" and typeof(rawPiece.setId) == "string"
			then normalizedRawSetsById[rawPiece.setId]
			else nil
		local piece = withDefaultPieceCombatStats(rawPiece, setConfig)
		validatePieceConfig(pieceKey, piece, seenPieceIds, errors)
		if typeof(piece) == "table" and typeof(piece.id) == "string" and piece.id ~= "" then
			piecesById[piece.id] = piece
		end
	end

	for setKey, normalizedRawSetConfig in pairs(normalizedRawSetsById) do
		local setConfig = finalizeSetCombatStats(normalizedRawSetConfig, piecesById)
		validateSetConfig(setKey, setConfig, piecesById, seenSetIds, errors)
		if typeof(setConfig) == "table" and typeof(setConfig.id) == "string" and setConfig.id ~= "" then
			setsById[setConfig.id] = setConfig
		end
	end

	for pieceId, piece in pairs(piecesById) do
		local setConfig = setsById[piece.setId]
		if not setConfig then
			pushError(errors, `Piece "{pieceId}" references missing set "{tostring(piece.setId)}"`)
		elseif typeof(setConfig.piecesByRegion) ~= "table" then
			pushError(errors, `Set "{piece.setId}" must provide piecesByRegion`)
		elseif setConfig.piecesByRegion[piece.region] ~= pieceId then
			pushError(errors, `Set "{piece.setId}" does not map region "{piece.region}" back to piece "{pieceId}"`)
		end
	end

	if not getDefaultBaseRig() then
		pushError(errors, 'Missing base rig "ReplicatedStorage.GameAssets.BodyParts.BaseRigs.DefaultR15"')
	end

	for pieceId, piece in pairs(piecesById) do
		if typeof(piece.region) == "string" and typeof(piece.assetGroup) == "string" and typeof(piece.assetModel) == "string" then
			if resolveBundleModelForPiece(piece) then
				continue
			end
		end

		if typeof(piece.region) == "string" and typeof(piece.assetGroup) == "string" and typeof(piece.assetModel) == "string" then
			pushError(
				errors,
				`Missing bundle model for piece "{pieceId}" at ReplicatedStorage.GameAssets.BodyParts.Bundles.{piece.region}.{piece.assetGroup}.{piece.assetModel}`
			)
		end
	end

	if #errors > 0 then
		error("BodyParts.Catalog validation failed:\n- " .. table.concat(errors, "\n- "))
	end

	local frozenPiecesById: { [string]: PieceConfig } = {}
	for pieceId, piece in pairs(piecesById) do
		frozenPiecesById[pieceId] = deepFreeze(deepCopy(piece))
	end
	table.freeze(frozenPiecesById)

	local frozenSetsById: { [string]: SetConfig } = {}
	for setId, setConfig in pairs(setsById) do
		frozenSetsById[setId] = deepFreeze(deepCopy(setConfig))
	end
	table.freeze(frozenSetsById)

	for setId, setConfig in pairs(frozenSetsById) do
		local orderedPieces = {}
		for _, region in ipairs(REGION_ORDER) do
			local pieceId = setConfig.piecesByRegion[region]
			local piece = frozenPiecesById[pieceId]
			table.insert(orderedPieces, piece)
			table.insert(allPieces, piece)
			setByPieceId[pieceId] = setConfig
		end
		piecesForSet[setId] = deepFreeze(orderedPieces)
		table.insert(allSets, setConfig)
	end
	table.freeze(piecesForSet)
	table.freeze(setByPieceId)
	table.freeze(allPieces)
	table.sort(allSets, function(a, b)
		local chanceA = math.max(1, tonumber(a.rollDisplay.chance) or math.huge)
		local chanceB = math.max(1, tonumber(b.rollDisplay.chance) or math.huge)
		if chanceA ~= chanceB then
			return chanceA < chanceB
		end

		return a.id < b.id
	end)
	table.freeze(allSets)

	local rollableSets = {}
	for _, setConfig in ipairs(allSets) do
		if setConfig.rollEnabled ~= false then
			table.insert(rollableSets, setConfig)
		end
	end
	table.freeze(rollableSets)

	local rollEntries = RollMath.RebuildExactBaseChances(rollableSets, function(setConfig)
		return setConfig.rollDisplay.chance
	end)
	for index, entry in ipairs(rollEntries) do
		rollEntries[index] = deepFreeze(entry)
	end
	table.freeze(rollEntries)

	return frozenPiecesById, frozenSetsById, piecesForSet, setByPieceId, allPieces, allSets, rollEntries
end

local PIECES_BY_ID, SETS_BY_ID, PIECES_FOR_SET, SET_BY_PIECE_ID, ALL_PIECES, ALL_SETS, ROLL_ENTRIES = buildCatalog()

function Catalog.GetPiece(pieceId: string): PieceConfig?
	return PIECES_BY_ID[pieceId]
end

function Catalog.GetSet(setId: string): SetConfig?
	return SETS_BY_ID[setId]
end

function Catalog.GetPiecesForSet(setId: string): { PieceConfig }?
	return PIECES_FOR_SET[setId]
end

function Catalog.GetSetForPiece(pieceId: string): SetConfig?
	return SET_BY_PIECE_ID[pieceId]
end

function Catalog.GetAllPieces(): { PieceConfig }
	return ALL_PIECES
end

function Catalog.GetAllSets(): { SetConfig }
	return ALL_SETS
end

function Catalog.GetRollEntries(): { RollEntry }
	return ROLL_ENTRIES
end

function Catalog.GetBasePlayerStats(): { speed: number, damage: number, health: number }
	return BASE_PLAYER_STATS
end

function Catalog.ResolveBundleModel(pieceId: string): Model?
	local piece = PIECES_BY_ID[pieceId]
	if not piece then
		return nil
	end

	return resolveBundleModelForPiece(piece)
end

function Catalog.ResolveAttachRules(pieceId: string): { [string]: AttachRuleConfig }?
	local piece = PIECES_BY_ID[pieceId]
	if not piece or typeof(piece.attachRules) ~= "table" then
		return nil
	end

	return deepCopy(piece.attachRules)
end

function Catalog.GetDefaultBaseRig(): Model?
	return getDefaultBaseRig()
end

function Catalog.GetFullSetBonus(equippedPieceIdsByRegion: { [BodyRegion]: string }): SetBonus?
	if typeof(equippedPieceIdsByRegion) ~= "table" then
		return nil
	end

	local matchingSetId = nil

	for _, region in ipairs(REGION_ORDER) do
		local pieceId = equippedPieceIdsByRegion[region]
		if typeof(pieceId) ~= "string" then
			return nil
		end

		local piece = PIECES_BY_ID[pieceId]
		if not piece or piece.region ~= region then
			return nil
		end

		if matchingSetId == nil then
			matchingSetId = piece.setId
		elseif matchingSetId ~= piece.setId then
			return nil
		end
	end

	if not matchingSetId then
		return nil
	end

	local setConfig = SETS_BY_ID[matchingSetId]
	return if setConfig then setConfig.fullSetBonus else nil
end

return table.freeze(Catalog)
