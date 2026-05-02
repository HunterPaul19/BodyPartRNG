local QuestState = {}

export type ObjectiveProgress = {
	progress: number,
	completed: boolean,
}

export type ActiveQuest = {
	questId: string,
	status: string,
	acceptedAt: number,
	completedAt: number?,
	currentPartIndex: number,
	completedParts: number,
	objectives: { [string]: ObjectiveProgress },
}

export type RepeatableQuestState = {
	completionCount: number,
	lastCompletedAt: number,
	cooldownUntil: number,
}

export type DailyQuestState = {
	localDay: number,
	selectedQuestIds: { string },
}

export type QuestStateValue = {
	activeByQuestId: { [string]: ActiveQuest },
	completedByQuestId: { [string]: boolean },
	claimedByQuestId: { [string]: boolean },
	repeatablesByQuestId: { [string]: RepeatableQuestState },
	unlockFlags: { [string]: boolean },
	dailyQuests: DailyQuestState,
}

local function normalizeString(value: any): string
	return if typeof(value) == "string" then value else ""
end

local function normalizeWholeNumber(value: any): number
	return math.max(0, math.floor(tonumber(value) or 0))
end

local function cloneBooleanMap(value: any): { [string]: boolean }
	local clone = {}
	if typeof(value) ~= "table" then
		return clone
	end

	for key, child in pairs(value) do
		if typeof(key) == "string" and key ~= "" and child == true then
			clone[key] = true
		end
	end

	return clone
end

local function normalizeObjectiveProgress(value: any): ObjectiveProgress
	local progress = normalizeWholeNumber(if typeof(value) == "table" then value.progress else value)
	return {
		progress = progress,
		completed = typeof(value) == "table" and value.completed == true,
	}
end

local function normalizeActiveQuest(questId: string, value: any): ActiveQuest?
	if questId == "" or typeof(value) ~= "table" then
		return nil
	end

	local objectives = {}
	if typeof(value.objectives) == "table" then
		for objectiveId, objectiveProgress in pairs(value.objectives) do
			if typeof(objectiveId) == "string" and objectiveId ~= "" then
				objectives[objectiveId] = normalizeObjectiveProgress(objectiveProgress)
			end
		end
	end

	local status = normalizeString(value.status)
	if status ~= "readyToClaim" and status ~= "claimed" then
		status = "active"
	end

	return {
		questId = questId,
		status = status,
		acceptedAt = normalizeWholeNumber(value.acceptedAt),
		completedAt = if value.completedAt ~= nil then normalizeWholeNumber(value.completedAt) else nil,
		currentPartIndex = math.max(1, normalizeWholeNumber(value.currentPartIndex)),
		completedParts = normalizeWholeNumber(value.completedParts),
		objectives = objectives,
	}
end

local function normalizeActiveMap(value: any): { [string]: ActiveQuest }
	local activeByQuestId = {}
	if typeof(value) ~= "table" then
		return activeByQuestId
	end

	for questId, activeQuest in pairs(value) do
		local normalizedQuestId = normalizeString(questId)
		local normalized = normalizeActiveQuest(normalizedQuestId, activeQuest)
		if normalized then
			activeByQuestId[normalizedQuestId] = normalized
		end
	end

	return activeByQuestId
end

local function normalizeRepeatableState(value: any): RepeatableQuestState
	return {
		completionCount = normalizeWholeNumber(if typeof(value) == "table" then value.completionCount else 0),
		lastCompletedAt = normalizeWholeNumber(if typeof(value) == "table" then value.lastCompletedAt else 0),
		cooldownUntil = normalizeWholeNumber(if typeof(value) == "table" then value.cooldownUntil else 0),
	}
end

local function normalizeRepeatableMap(value: any): { [string]: RepeatableQuestState }
	local repeatablesByQuestId = {}
	if typeof(value) ~= "table" then
		return repeatablesByQuestId
	end

	for questId, repeatableState in pairs(value) do
		if typeof(questId) == "string" and questId ~= "" then
			repeatablesByQuestId[questId] = normalizeRepeatableState(repeatableState)
		end
	end

	return repeatablesByQuestId
end

local function normalizeStringList(value: any): { string }
	local results = {}
	if typeof(value) ~= "table" then
		return results
	end

	for _, child in ipairs(value) do
		if typeof(child) == "string" and child ~= "" then
			table.insert(results, child)
		end
	end

	return results
end

local function normalizeDailyQuestState(value: any): DailyQuestState
	if typeof(value) ~= "table" then
		return {
			localDay = -1,
			selectedQuestIds = {},
		}
	end

	return {
		localDay = math.floor(tonumber(value.localDay) or -1),
		selectedQuestIds = normalizeStringList(value.selectedQuestIds),
	}
end

function QuestState.CreateEmptyState(): QuestStateValue
	return {
		activeByQuestId = {},
		completedByQuestId = {},
		claimedByQuestId = {},
		repeatablesByQuestId = {},
		unlockFlags = {},
		dailyQuests = {
			localDay = -1,
			selectedQuestIds = {},
		},
	}
end

function QuestState.Normalize(value: any): QuestStateValue
	local state = QuestState.CreateEmptyState()
	if typeof(value) ~= "table" then
		return state
	end

	state.activeByQuestId = normalizeActiveMap(value.activeByQuestId)
	state.completedByQuestId = cloneBooleanMap(value.completedByQuestId)
	state.claimedByQuestId = cloneBooleanMap(value.claimedByQuestId)
	state.repeatablesByQuestId = normalizeRepeatableMap(value.repeatablesByQuestId)
	state.unlockFlags = cloneBooleanMap(value.unlockFlags)
	state.dailyQuests = normalizeDailyQuestState(value.dailyQuests)
	return state
end

function QuestState.Clone(value: any): QuestStateValue
	return QuestState.Normalize(value)
end

return table.freeze(QuestState)
