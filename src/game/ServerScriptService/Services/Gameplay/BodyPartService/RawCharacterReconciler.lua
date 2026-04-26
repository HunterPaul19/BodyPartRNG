local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BodyPartRegions = require(ReplicatedStorage.Shared.Character.BodyPartRegions)
local BodyPartSets = require(ReplicatedStorage.Shared.Config.BodyParts.Sets)
local RawCharacterImporter = require(script.Parent.RawCharacterImporter)

local RawCharacterReconciler = {}

local RAW_CHARACTERS_FOLDER_NAME = "RawCharacters"
local PREVIEW_VERSION = 1
local DEFAULT_NEW_ASSET_GROUP = "ImportedCommon"

local REGION_PIECE_SUFFIX = {
	Head = "head",
	Torso = "torso",
	LeftArm = "left_arm",
	RightArm = "right_arm",
	LeftLeg = "left_leg",
	RightLeg = "right_leg",
}

local REGION_DISPLAY_SUFFIX = {
	Head = "Head",
	Torso = "Torso",
	LeftArm = "Left Arm",
	RightArm = "Right Arm",
	LeftLeg = "Left Leg",
	RightLeg = "Right Leg",
}

local function trim(value: string): string
	return string.match(value, "^%s*(.-)%s*$") or value
end

local function collapseWhitespace(value: string): string
	return string.gsub(value, "%s+", " ")
end

local function canonicalizeSlug(value: string): string
	local normalized = string.lower(collapseWhitespace(trim(value)))
	normalized = string.gsub(normalized, "[^%w]+", "_")
	normalized = string.gsub(normalized, "_+", "_")
	normalized = string.gsub(normalized, "^_+", "")
	normalized = string.gsub(normalized, "_+$", "")
	if normalized == "" then
		return "unnamed"
	end
	return normalized
end

local function sortListByKey(list, key)
	table.sort(list, function(left, right)
		local leftValue = tostring(left[key] or "")
		local rightValue = tostring(right[key] or "")
		if leftValue == rightValue then
			return tostring(left.setId or left.rawName or "") < tostring(right.setId or right.rawName or "")
		end
		return leftValue < rightValue
	end)
end

local function getRawCharactersFolder(): Folder
	local folder = Workspace:FindFirstChild(RAW_CHARACTERS_FOLDER_NAME)
	assert(folder and folder:IsA("Folder"), "Workspace.RawCharacters is missing.")
	return folder
end

local function getRawCharacterEntries()
	local entries = {}
	for _, child in ipairs(getRawCharactersFolder():GetChildren()) do
		if child:IsA("Model") then
			table.insert(entries, {
				model = child,
				rawName = child.Name,
				displayName = trim(child.Name),
				slug = canonicalizeSlug(child.Name),
			})
		end
	end

	table.sort(entries, function(left, right)
		return left.rawName < right.rawName
	end)

	return entries
end

local function addIndexEntry(indexMap, key, entry)
	if key == nil or key == "" then
		return
	end

	local bucket = indexMap[key]
	if bucket == nil then
		bucket = {}
		indexMap[key] = bucket
	end

	for _, existing in ipairs(bucket) do
		if existing.setId == entry.setId then
			return
		end
	end

	table.insert(bucket, entry)
end

local function getAllSetDefinitions()
	local definitions = {}
	for setId, setDefinition in pairs(BodyPartSets) do
		definitions[setId] = setDefinition
	end
	return definitions
end

local function buildSetIndexes(setDefinitions)
	local slugIndex = {}
	local exactSourceIndex = {}

	for setId, setDefinition in pairs(setDefinitions) do
		addIndexEntry(slugIndex, canonicalizeSlug(setId), {
			setId = setId,
			matchSource = "id",
		})

		if typeof(setDefinition.assetModel) == "string" and setDefinition.assetModel ~= "" then
			addIndexEntry(slugIndex, canonicalizeSlug(setDefinition.assetModel), {
				setId = setId,
				matchSource = "assetModel",
			})
		end

		if typeof(setDefinition.sourceModelName) == "string" and setDefinition.sourceModelName ~= "" then
			addIndexEntry(slugIndex, canonicalizeSlug(setDefinition.sourceModelName), {
				setId = setId,
				matchSource = "sourceModelName",
			})
			addIndexEntry(exactSourceIndex, setDefinition.sourceModelName, {
				setId = setId,
				matchSource = "sourceModelNameExact",
			})
		end
	end

	return slugIndex, exactSourceIndex
end

local function buildNewConfigDescriptor(rawEntry)
	local piecesByRegion = {}
	local pieceIds = {}

	for _, region in ipairs(BodyPartRegions.Order) do
		local pieceId = string.format("%s_%s", rawEntry.slug, REGION_PIECE_SUFFIX[region])
		piecesByRegion[region] = pieceId
		pieceIds[region] = {
			id = pieceId,
			displayName = string.format("%s %s", rawEntry.displayName, REGION_DISPLAY_SUFFIX[region]),
		}
	end

	return {
		rawName = rawEntry.rawName,
		displayName = rawEntry.displayName,
		setId = rawEntry.slug,
		sourceModelName = rawEntry.displayName,
		assetGroup = DEFAULT_NEW_ASSET_GROUP,
		assetModel = rawEntry.slug,
		piecesByRegion = piecesByRegion,
		pieceIds = pieceIds,
	}
end

local function getUniqueCandidate(candidateBucket)
	if candidateBucket == nil then
		return nil, nil
	end

	if #candidateBucket == 1 then
		return candidateBucket[1], nil
	end

	if #candidateBucket > 1 then
		local conflictedSetIds = {}
		for _, candidate in ipairs(candidateBucket) do
			table.insert(conflictedSetIds, candidate.setId)
		end
		table.sort(conflictedSetIds)
		return nil, conflictedSetIds
	end

	return nil, nil
end

function RawCharacterReconciler.Preview()
	local rawEntries = getRawCharacterEntries()
	local setDefinitions = getAllSetDefinitions()
	local slugIndex, exactSourceIndex = buildSetIndexes(setDefinitions)
	local matchedSetIds = {}
	local matchedConfigs = {}
	local newConfigs = {}
	local missingRawConfigs = {}
	local conflicts = {}

	for _, rawEntry in ipairs(rawEntries) do
		local matchedCandidate, conflictedSetIds = getUniqueCandidate(slugIndex[rawEntry.slug])
		local matchedBy = matchedCandidate and matchedCandidate.matchSource or nil

		if matchedCandidate == nil and conflictedSetIds == nil then
			matchedCandidate, conflictedSetIds = getUniqueCandidate(exactSourceIndex[rawEntry.rawName])
			matchedBy = matchedCandidate and matchedCandidate.matchSource or nil
		end

		if conflictedSetIds ~= nil then
			table.insert(conflicts, {
				rawName = rawEntry.rawName,
				slug = rawEntry.slug,
				conflictedSetIds = conflictedSetIds,
			})
			continue
		end

		if matchedCandidate ~= nil then
			local setDefinition = setDefinitions[matchedCandidate.setId]
			matchedSetIds[matchedCandidate.setId] = true
			table.insert(matchedConfigs, {
				rawName = rawEntry.rawName,
				displayName = rawEntry.displayName,
				slug = rawEntry.slug,
				setId = matchedCandidate.setId,
				assetGroup = setDefinition.assetGroup,
				assetModel = setDefinition.assetModel,
				previousSourceModelName = setDefinition.sourceModelName,
				nextSourceModelName = rawEntry.displayName,
				sourceModelNameChanged = setDefinition.sourceModelName ~= rawEntry.displayName,
				matchedBy = matchedBy,
			})
		else
			table.insert(newConfigs, buildNewConfigDescriptor(rawEntry))
		end
	end

	for setId, setDefinition in pairs(setDefinitions) do
		if typeof(setDefinition.sourceModelName) == "string"
			and setDefinition.sourceModelName ~= ""
			and matchedSetIds[setId] ~= true
		then
			table.insert(missingRawConfigs, {
				setId = setId,
				sourceModelName = setDefinition.sourceModelName,
				assetGroup = setDefinition.assetGroup,
				assetModel = setDefinition.assetModel,
			})
		end
	end

	sortListByKey(matchedConfigs, "rawName")
	sortListByKey(newConfigs, "rawName")
	sortListByKey(missingRawConfigs, "setId")
	sortListByKey(conflicts, "rawName")

	local requiresLocalConfigSync = false
	for _, entry in ipairs(matchedConfigs) do
		if entry.sourceModelNameChanged then
			requiresLocalConfigSync = true
			break
		end
	end
	if #newConfigs > 0 then
		requiresLocalConfigSync = true
	end

	return {
		version = PREVIEW_VERSION,
		rawCharacterFolder = RAW_CHARACTERS_FOLDER_NAME,
		generatedAtUnix = os.time(),
		matchedConfigs = matchedConfigs,
		newConfigs = newConfigs,
		missingRawConfigs = missingRawConfigs,
		conflicts = conflicts,
		requiresLocalConfigSync = requiresLocalConfigSync,
		summary = {
			rawCharacterCount = #rawEntries,
			matchedConfigCount = #matchedConfigs,
			newConfigCount = #newConfigs,
			missingRawConfigCount = #missingRawConfigs,
			conflictCount = #conflicts,
		},
	}
end

function RawCharacterReconciler.ExportPreviewJson()
	return HttpService:JSONEncode(RawCharacterReconciler.Preview())
end

function RawCharacterReconciler.FormatPreview(preview)
	local lines = {
		string.format("Raw characters discovered: %d", preview.summary.rawCharacterCount),
		string.format("Matched configs: %d", preview.summary.matchedConfigCount),
		string.format("New configs needed: %d", preview.summary.newConfigCount),
		string.format("Missing-raw configs: %d", preview.summary.missingRawConfigCount),
		string.format("Conflicts: %d", preview.summary.conflictCount),
		string.format("Requires local config sync: %s", tostring(preview.requiresLocalConfigSync == true)),
	}

	if #preview.matchedConfigs > 0 then
		table.insert(lines, "Matched configs:")
		for _, entry in ipairs(preview.matchedConfigs) do
			local detail = string.format(
				"- %s -> %s (%s/%s via %s)",
				entry.rawName,
				entry.setId,
				tostring(entry.assetGroup),
				tostring(entry.assetModel),
				tostring(entry.matchedBy)
			)
			if entry.sourceModelNameChanged then
				detail = detail .. string.format(
					" sourceModelName %s -> %s",
					tostring(entry.previousSourceModelName),
					tostring(entry.nextSourceModelName)
				)
			end
			table.insert(lines, detail)
		end
	end

	if #preview.newConfigs > 0 then
		table.insert(lines, "New configs:")
		for _, entry in ipairs(preview.newConfigs) do
			table.insert(lines, string.format("- %s -> %s (%s/%s)", entry.rawName, entry.setId, entry.assetGroup, entry.assetModel))
		end
	end

	if #preview.missingRawConfigs > 0 then
		table.insert(lines, "Missing raw configs:")
		for _, entry in ipairs(preview.missingRawConfigs) do
			table.insert(lines, string.format("- %s missing raw '%s'", entry.setId, tostring(entry.sourceModelName)))
		end
	end

	if #preview.conflicts > 0 then
		table.insert(lines, "Conflicts:")
		for _, entry in ipairs(preview.conflicts) do
			table.insert(
				lines,
				string.format("- %s slug '%s' matches multiple sets: %s", entry.rawName, entry.slug, table.concat(entry.conflictedSetIds, ", "))
			)
		end
	end

	return table.concat(lines, "\n")
end

local function buildEmptyImportReport(stripEffects)
	return {
		autoAssignedAssemblies = {},
		invalidSets = {},
		packagedSets = {},
		skippedAccessories = {},
		skippedAssemblies = {},
		strippedEffectCount = 0,
		stripEffectsEnabled = stripEffects == true,
	}
end

function RawCharacterReconciler.Apply(options)
	local preview = RawCharacterReconciler.Preview()
	local stripEffects = true

	if typeof(options) == "table" and typeof(options.stripEffects) == "boolean" then
		stripEffects = options.stripEffects
	end

	if preview.requiresLocalConfigSync or #preview.conflicts > 0 then
		return {
			success = false,
			message = if #preview.conflicts > 0
				then "Resolve raw-to-config conflicts before running the Studio import apply step."
				else "Local config sync is required before running the Studio import apply step.",
			preview = preview,
			importReport = buildEmptyImportReport(stripEffects),
			appliedSetIds = {},
		}
	end

	local matchedSetIds = {}
	for _, entry in ipairs(preview.matchedConfigs) do
		table.insert(matchedSetIds, entry.setId)
	end

	local importReport = RawCharacterImporter.ImportSetIds(matchedSetIds, {
		stripEffects = stripEffects,
	})

	return {
		success = #importReport.invalidSets == 0,
		message = if #matchedSetIds > 0
			then "Reconciliation import apply finished."
			else "No matched set configs were available to import.",
		preview = preview,
		importReport = importReport,
		appliedSetIds = matchedSetIds,
	}
end

function RawCharacterReconciler.FormatApplyReport(result)
	local lines = {
		result.message or "Reconciliation import apply finished.",
		RawCharacterReconciler.FormatPreview(result.preview),
		RawCharacterImporter.FormatReport(result.importReport),
	}

	if #result.appliedSetIds > 0 then
		table.insert(lines, string.format("Applied setIds: %s", table.concat(result.appliedSetIds, ", ")))
	end

	return table.concat(lines, "\n\n")
end

return RawCharacterReconciler
