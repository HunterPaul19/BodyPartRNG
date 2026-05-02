local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local QuestConfig = require(ReplicatedStorage.Shared.Config.QuestConfig)
local RollingConfig = require(ReplicatedStorage.Shared.Config.RollingConfig)
local RollTypes = require(ReplicatedStorage.Shared.Config.RollTypes)
local DailyChestState = require(ReplicatedStorage.Shared.Character.DailyChestState)
local QuestState = require(ReplicatedStorage.Shared.Character.QuestState)
local DataService = require(script.Parent.DataService)
local AdminConfig = require(script.Parent.AdminConfig)
local RequestLimiter = require(script.Parent.Common.RequestLimiter)

local REMOTES_FOLDER_NAME = "Remotes"
local QUESTS_FOLDER_NAME = "Quests"
local GET_STATE_REMOTE_NAME = "GetQuestState"
local ACCEPT_REMOTE_NAME = "AcceptQuest"
local ABANDON_REMOTE_NAME = "AbandonQuest"
local CLAIM_REMOTE_NAME = "ClaimQuest"
local MARK_BOARD_OPENED_REMOTE_NAME = "MarkQuestBoardOpened"
local UPDATED_REMOTE_NAME = "QuestUpdated"
local DIALOGUE_ID_ATTRIBUTE = "DialogueId"
local ONBOARDING_QUEST_BOARD_OPENED_FLAG = "onboarding_quest_board_opened"
local DAILY_QUEST_COUNT = 5
local RANDOM_SEED_MODULUS = 2147483647
local PAID_ROLL_TYPE_IDS = {
	roll_2 = true,
	roll_3 = true,
	roll_4 = true,
	roll_5 = true,
	roll_6 = true,
	roll_7 = true,
	roll_8 = true,
}
local OLD_TEST_QUEST_IDS = {
	test_roll_once = true,
	test_equip_body_part = true,
	test_two_part_chain = true,
	test_sell_body_part_repeatable = true,
	test_hold_money_state = true,
}
local OLD_TEST_UNLOCK_FLAGS = {
	test_roll_once_completed = true,
	test_two_part_chain_completed = true,
}

local remotesFolder: Folder? = nil
local questsFolder: Folder? = nil
local getStateRemote: RemoteFunction? = nil
local acceptRemote: RemoteFunction? = nil
local abandonRemote: RemoteFunction? = nil
local claimRemote: RemoteFunction? = nil
local markBoardOpenedRemote: RemoteFunction? = nil
local updatedRemote: RemoteEvent? = nil

local QuestService = {}

local function createOrGetFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function createOrGetRemoteFunction(parent: Instance, name: string): RemoteFunction
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function createOrGetRemoteEvent(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function ensureQuestRemotesFolder(): Folder
	if questsFolder and questsFolder.Parent then
		return questsFolder
	end

	remotesFolder = createOrGetFolder(ReplicatedStorage, REMOTES_FOLDER_NAME)
	questsFolder = createOrGetFolder(remotesFolder, QUESTS_FOLDER_NAME)
	return questsFolder
end

local function response(ok: boolean, message: string, state: any?, extra: any?)
	local result = {
		ok = ok,
		message = message,
		state = state,
	}
	if typeof(extra) == "table" then
		for key, value in pairs(extra) do
			result[key] = value
		end
	end
	return result
end

local function normalizeQuestId(payload: any): string?
	if typeof(payload) == "string" then
		return payload
	end
	if typeof(payload) == "table" and typeof(payload.questId) == "string" then
		return payload.questId
	end
	return nil
end

local function normalizeProviderId(payload: any): string?
	if typeof(payload) == "table" and typeof(payload.providerId) == "string" and payload.providerId ~= "" then
		return payload.providerId
	end
	return nil
end

local function hasProviderId(definition: QuestConfig.QuestDefinition, providerId: string?): boolean
	if typeof(providerId) ~= "string" or providerId == "" then
		return false
	end

	for _, configuredProviderId in ipairs(definition.providerIds or {}) do
		if configuredProviderId == providerId then
			return true
		end
	end

	return false
end

local function requiresProvider(definition: QuestConfig.QuestDefinition): boolean
	return definition.boardVisible == false
end

local function hasUserId(list: { any }?, userId: number): boolean
	if typeof(list) ~= "table" then
		return false
	end

	for _, configuredUserId in ipairs(list) do
		if tonumber(configuredUserId) == userId then
			return true
		end
	end

	return false
end

local function isAdminDevPlayer(player: Player): boolean
	if RunService:IsStudio() and AdminConfig.AllowAllPlayersInStudio == true then
		return true
	end

	return hasUserId(AdminConfig.AuthorizedUserIds, player.UserId) or hasUserId(AdminConfig.AllowedUserIds, player.UserId)
end

local function getNow(): number
	return os.time()
end

local function isActive(player: Player): boolean
	return player.Parent == Players and DataService:IsPlayerDataLoaded(player)
end

local function isDailyQuestDefinition(definition: QuestConfig.QuestDefinition?): boolean
	return typeof(definition) == "table" and definition.kind == "daily"
end

local function cloneDefinition(definition: QuestConfig.QuestDefinition): any
	local clone = table.clone(definition)
	clone.providerIds = table.clone(definition.providerIds or {})
	clone.objectives = table.clone(definition.objectives or {})
	if typeof(definition.parts) == "table" then
		local parts = table.create(#definition.parts)
		for index, part in ipairs(definition.parts) do
			local partClone = table.clone(part)
			partClone.objectives = table.clone(part.objectives or {})
			parts[index] = partClone
		end
		clone.parts = parts
	end
	clone.rewards = table.clone(definition.rewards or {})
	return clone
end

local function objectiveTarget(objective: QuestConfig.QuestObjective): number
	return math.max(1, math.floor(tonumber(objective.targetValue) or 1))
end

local function setObjectiveProgress(activeQuest: QuestState.ActiveQuest, objective: QuestConfig.QuestObjective, progress: number)
	local target = objectiveTarget(objective)
	activeQuest.objectives[objective.id] = {
		progress = math.clamp(math.floor(tonumber(progress) or 0), 0, target),
		completed = progress >= target,
	}
end

local function getObjectiveProgress(activeQuest: QuestState.ActiveQuest, objective: QuestConfig.QuestObjective): QuestState.ObjectiveProgress
	local current = activeQuest.objectives[objective.id]
	if typeof(current) == "table" then
		return {
			progress = math.max(0, math.floor(tonumber(current.progress) or 0)),
			completed = current.completed == true,
		}
	end

	return {
		progress = 0,
		completed = false,
	}
end

local function countEquippedBodyParts(player: Player): number
	local equippedState = DataService:GetEquippedLoadout(player)
	local count = 0
	for _, entry in pairs(equippedState) do
		if typeof(entry) == "table" and typeof(entry.ownedId) == "string" and entry.ownedId ~= "" then
			count += 1
		end
	end
	return count
end

local function isCleanPlusDisplayRarity(value: any): boolean
	local normalized = RollingConfig.NormalizeDisplayRarity(value)
	for index, displayRarity in ipairs(RollingConfig.DisplayRarityOrder) do
		if displayRarity == "Clean" then
			for compareIndex = index, #RollingConfig.DisplayRarityOrder do
				if RollingConfig.DisplayRarityOrder[compareIndex] == normalized then
					return true
				end
			end
			return false
		end
	end

	return normalized == "Clean"
end

local function countPaidRolls(player: Player): number
	local stats = DataService:GetStats(player)
	local byRollType = stats and stats.rolls and stats.rolls.byRollType
	if typeof(byRollType) ~= "table" then
		return 0
	end

	local count = 0
	for rollTypeId, rollCount in pairs(byRollType) do
		if PAID_ROLL_TYPE_IDS[rollTypeId] == true and RollTypes.Get(rollTypeId) ~= nil then
			count += math.max(0, math.floor(tonumber(rollCount) or 0))
		end
	end
	return count
end

local function countCleanPlusRolls(player: Player): number
	local stats = DataService:GetStats(player)
	local byRarity = stats and stats.rolls and stats.rolls.byRarity
	if typeof(byRarity) ~= "table" then
		return 0
	end

	local count = 0
	for displayRarity, rollCount in pairs(byRarity) do
		if isCleanPlusDisplayRarity(displayRarity) then
			count += math.max(0, math.floor(tonumber(rollCount) or 0))
		end
	end
	return count
end

local function countEquippedCleanPlusBodyParts(player: Player): number
	local equippedState = DataService:GetEquippedLoadout(player)
	local ownedBodyParts = DataService:GetOwnedBodyParts(player)
	local count = 0

	for _, entry in pairs(equippedState) do
		local ownedId = if typeof(entry) == "table" then entry.ownedId else nil
		local record = if typeof(ownedId) == "string" then ownedBodyParts[ownedId] else nil
		if typeof(record) == "table" and isCleanPlusDisplayRarity(record.displayRarity) then
			count += 1
		end
	end

	return count
end

local function countLifetimeAppraisals(player: Player): number
	local stats = DataService:GetStats(player)
	if typeof(stats) ~= "table" then
		return 0
	end

	local appraisal = stats.appraisal
	local appraisalCount = if typeof(appraisal) == "table"
		then math.max(0, math.floor(tonumber(appraisal.successCount) or 0))
		else 0

	local spentBySource = stats.economy and stats.economy.spentBySource
	if typeof(spentBySource) == "table" and (tonumber(spentBySource.appraisal_cost) or 0) > 0 then
		appraisalCount = math.max(appraisalCount, 1)
	end

	return appraisalCount
end

local function getStateObjectiveProgress(player: Player, state: QuestState.QuestStateValue, objective: QuestConfig.QuestObjective): number
	local stateType = objective.stateType
	if stateType == "current_money" then
		return DataService:GetMoney(player)
	elseif stateType == "successful_roll_count" then
		return DataService:GetSuccessfulRollCount(player)
	elseif stateType == "owned_body_part_count" then
		local bodyPartsState = DataService:GetBodyPartsState(player)
		local ownedById = if typeof(bodyPartsState) == "table" then bodyPartsState.ownedById else nil
		local count = 0
		if typeof(ownedById) == "table" then
			for _ in pairs(ownedById) do
				count += 1
			end
		end
		return count
	elseif stateType == "equipped_body_part_count" then
		return countEquippedBodyParts(player)
	elseif stateType == "paid_roll_count" then
		return countPaidRolls(player)
	elseif stateType == "clean_plus_roll_count" then
		return countCleanPlusRolls(player)
	elseif stateType == "equipped_clean_plus_body_part_count" then
		return countEquippedCleanPlusBodyParts(player)
	elseif stateType == "appraisal_count" then
		return countLifetimeAppraisals(player)
	elseif stateType == "owned_material_amount" then
		local materialId = objective.filters and objective.filters.materialId
		if typeof(materialId) ~= "string" or materialId == "" then
			return 0
		end
		return DataService:GetCraftingMaterialAmounts(player)[materialId] or 0
	elseif stateType == "unlock_flag" then
		local flag = objective.filters and objective.filters.flag
		return if typeof(flag) == "string" and state.unlockFlags[flag] == true then 1 else 0
	end

	return 0
end

local function getActivePartIndex(definition: QuestConfig.QuestDefinition, activeQuest: QuestState.ActiveQuest): number
	return math.clamp(
		math.floor(tonumber(activeQuest.currentPartIndex) or 1),
		1,
		QuestConfig.GetPartCount(definition)
	)
end

local function resetObjectiveProgressForPart(definition: QuestConfig.QuestDefinition, activeQuest: QuestState.ActiveQuest)
	activeQuest.objectives = {}
	for _, objective in ipairs(QuestConfig.GetPartObjectives(definition, getActivePartIndex(definition, activeQuest))) do
		setObjectiveProgress(activeQuest, objective, 0)
	end
end

local function refreshStateObjectives(player: Player, state: QuestState.QuestStateValue, definition: QuestConfig.QuestDefinition, activeQuest: QuestState.ActiveQuest)
	for _, objective in ipairs(QuestConfig.GetPartObjectives(definition, getActivePartIndex(definition, activeQuest))) do
		if objective.kind == "state" then
			setObjectiveProgress(activeQuest, objective, getStateObjectiveProgress(player, state, objective))
		end
	end
end

local function areAllObjectivesCompleted(definition: QuestConfig.QuestDefinition, activeQuest: QuestState.ActiveQuest): boolean
	for _, objective in ipairs(QuestConfig.GetPartObjectives(definition, getActivePartIndex(definition, activeQuest))) do
		local progress = getObjectiveProgress(activeQuest, objective)
		if progress.completed ~= true and progress.progress < objectiveTarget(objective) then
			return false
		end
	end

	return true
end

local function markReadyIfComplete(player: Player, state: QuestState.QuestStateValue, definition: QuestConfig.QuestDefinition, activeQuest: QuestState.ActiveQuest)
	if activeQuest.status ~= "active" then
		return
	end

	local partCount = QuestConfig.GetPartCount(definition)
	activeQuest.currentPartIndex = getActivePartIndex(definition, activeQuest)
	activeQuest.completedParts = math.clamp(
		math.floor(tonumber(activeQuest.completedParts) or math.max(0, activeQuest.currentPartIndex - 1)),
		0,
		partCount
	)

	while activeQuest.status == "active" do
		refreshStateObjectives(player, state, definition, activeQuest)
		if not areAllObjectivesCompleted(definition, activeQuest) then
			return
		end

		activeQuest.completedParts = math.max(activeQuest.completedParts, activeQuest.currentPartIndex)
		if activeQuest.currentPartIndex >= partCount then
			activeQuest.completedParts = partCount
			activeQuest.status = "readyToClaim"
			activeQuest.completedAt = getNow()
			return
		end

		activeQuest.currentPartIndex += 1
		resetObjectiveProgressForPart(definition, activeQuest)
	end
end

local function cloneObjectiveSnapshot(activeQuest: QuestState.ActiveQuest): { [string]: { progress: number, completed: boolean } }
	local snapshot = {}
	for objectiveId, progress in pairs(activeQuest.objectives or {}) do
		if typeof(progress) == "table" then
			snapshot[objectiveId] = {
				progress = math.floor(tonumber(progress.progress) or 0),
				completed = progress.completed == true,
			}
		end
	end
	return snapshot
end

local function hasActiveQuestChanged(activeQuest: QuestState.ActiveQuest, before: any): boolean
	if activeQuest.status ~= before.status
		or activeQuest.currentPartIndex ~= before.currentPartIndex
		or activeQuest.completedParts ~= before.completedParts
		or activeQuest.completedAt ~= before.completedAt
	then
		return true
	end

	local beforeObjectives = before.objectives or {}
	for objectiveId, progress in pairs(activeQuest.objectives or {}) do
		local previous = beforeObjectives[objectiveId]
		if typeof(progress) ~= "table" then
			if previous ~= nil then
				return true
			end
		elseif typeof(previous) ~= "table"
			or math.floor(tonumber(progress.progress) or 0) ~= previous.progress
			or (progress.completed == true) ~= previous.completed
		then
			return true
		end
	end
	for objectiveId in pairs(beforeObjectives) do
		if activeQuest.objectives[objectiveId] == nil then
			return true
		end
	end

	return false
end

local function hasCompletedOneTime(state: QuestState.QuestStateValue, definition: QuestConfig.QuestDefinition): boolean
	if QuestConfig.IsRepeatable(definition) then
		return false
	end

	return state.completedByQuestId[definition.id] == true or state.claimedByQuestId[definition.id] == true
end

local function meetsPrerequisites(state: QuestState.QuestStateValue, definition: QuestConfig.QuestDefinition): (boolean, string?)
	local prerequisites = definition.prerequisites
	if typeof(prerequisites) ~= "table" then
		return true, nil
	end

	for _, questId in ipairs(prerequisites.completedQuestIds or {}) do
		if state.completedByQuestId[questId] ~= true and state.claimedByQuestId[questId] ~= true then
			return false, "Complete the required quest first."
		end
	end
	for _, flag in ipairs(prerequisites.unlockFlags or {}) do
		if state.unlockFlags[flag] ~= true then
			return false, "Unlock the required progression flag first."
		end
	end

	return true, nil
end

local function getAvailability(
	player: Player,
	state: QuestState.QuestStateValue,
	definition: QuestConfig.QuestDefinition,
	providerId: string?
): (boolean, string?)
	if definition.adminOnly == true and not isAdminDevPlayer(player) then
		return false, "This quest is only available to admins/devs."
	end
	if state.activeByQuestId[definition.id] ~= nil then
		return false, "Quest is already active."
	end
	if hasCompletedOneTime(state, definition) then
		return false, "Quest is already completed."
	end
	if isDailyQuestDefinition(definition) then
		return false, "Daily quests are assigned automatically."
	end

	local prerequisitesMet, prerequisiteMessage = meetsPrerequisites(state, definition)
	if not prerequisitesMet then
		return false, prerequisiteMessage
	end
	if requiresProvider(definition) and not hasProviderId(definition, providerId) then
		return false, "Talk to the quest giver to start this quest."
	end

	local repeatableState = state.repeatablesByQuestId[definition.id]
	if QuestConfig.IsRepeatable(definition) and repeatableState and repeatableState.cooldownUntil > getNow() then
		return false, "Quest is on cooldown."
	end

	return true, nil
end

local function isQuestVisibleToPlayer(player: Player, definition: QuestConfig.QuestDefinition): boolean
	if definition.hidden == true then
		return false
	end
	if definition.adminOnly == true and not isAdminDevPlayer(player) then
		return false
	end
	return true
end

local function buildActiveQuest(definition: QuestConfig.QuestDefinition, now: number): QuestState.ActiveQuest
	local activeQuest = {
		questId = definition.id,
		status = "active",
		acceptedAt = now,
		completedAt = nil,
		currentPartIndex = 1,
		completedParts = 0,
		objectives = {},
	}

	resetObjectiveProgressForPart(definition, activeQuest)

	return activeQuest
end

local function fieldMatches(expected: any, actual: any): boolean
	if typeof(expected) == "table" then
		if actual ~= nil and expected[actual] == true then
			return true
		end
		for _, candidate in ipairs(expected) do
			if candidate == actual then
				return true
			end
		end
		return false
	end

	return expected == actual
end

local function eventMatchesObjective(objective: QuestConfig.QuestObjective, eventType: string, payload: any): boolean
	if objective.kind ~= "event" or objective.eventType ~= eventType then
		return false
	end

	local filters = objective.filters
	if typeof(filters) ~= "table" then
		return true
	end
	local eventPayload = if typeof(payload) == "table" then payload else {}
	for fieldName, expectedValue in pairs(filters) do
		if not fieldMatches(expectedValue, eventPayload[fieldName]) then
			return false
		end
	end

	return true
end

local function getEventIncrement(objective: QuestConfig.QuestObjective, payload: any): number
	if typeof(objective.countField) == "string" and objective.countField ~= "" and typeof(payload) == "table" then
		return math.max(1, math.floor(tonumber(payload[objective.countField]) or 1))
	end

	return 1
end

local function finishClaimedQuestInState(state: QuestState.QuestStateValue, definition: QuestConfig.QuestDefinition, activeQuest: QuestState.ActiveQuest)
	local isDailyQuest = isDailyQuestDefinition(definition)
	if not isDailyQuest then
		state.activeByQuestId[definition.id] = nil
	end

	local now = getNow()
	if isDailyQuest then
		activeQuest.completedAt = activeQuest.completedAt or now
		activeQuest.completedParts = QuestConfig.GetPartCount(definition)
	elseif QuestConfig.IsRepeatable(definition) then
		local repeatableState = state.repeatablesByQuestId[definition.id] or {
			completionCount = 0,
			lastCompletedAt = 0,
			cooldownUntil = 0,
		}
		repeatableState.completionCount += 1
		repeatableState.lastCompletedAt = now
		repeatableState.cooldownUntil = now + QuestConfig.GetCooldownSeconds(definition)
		state.repeatablesByQuestId[definition.id] = repeatableState
	else
		state.completedByQuestId[definition.id] = true
		state.claimedByQuestId[definition.id] = true
	end

	local rewards = definition.rewards or {}
	for _, flag in ipairs(rewards.unlockFlags or {}) do
		if typeof(flag) == "string" and flag ~= "" then
			state.unlockFlags[flag] = true
		end
	end

	activeQuest.status = "claimed"
end

local function grantRewards(player: Player, definition: QuestConfig.QuestDefinition): (boolean, string?, any?)
	local rewards = definition.rewards or {}
	local rewardPresentation = {}

	local money = math.floor(tonumber(rewards.money) or 0)
	if money > 0 then
		DataService:AddMoney(player, money, "quest_reward")
	end

	local timeShards = math.floor(tonumber(rewards.timeShards) or 0)
	if timeShards > 0 then
		DataService:AdjustTimeShardsBalance(player, timeShards, "quest_reward")
		rewardPresentation.timeShards = timeShards
	end

	for _, reward in ipairs(rewards.dailyChests or {}) do
		local chestId = reward.chestId
		local amount = math.max(1, math.floor(tonumber(reward.amount) or 1))
		if typeof(chestId) ~= "string" or chestId == "" then
			return false, "Quest reward chest is invalid.", rewardPresentation
		end

		local DailyChestService = require(script.Parent.DailyChestService)
		for _ = 1, amount do
			local ok, err, package = DailyChestService:GrantChestPackageForQuest(player, chestId)
			if not ok then
				return false, err, rewardPresentation
			end
			if typeof(package) == "table" then
				local chests = rewardPresentation.dailyChests
				if chests == nil then
					chests = {}
					rewardPresentation.dailyChests = chests
				end
				table.insert(chests, package)
			end
		end
	end

	for _, reward in ipairs(rewards.materials or {}) do
		local materialId = reward.materialId
		local amount = math.max(1, math.floor(tonumber(reward.amount) or 1))
		local _, err = DataService:AddCraftingMaterial(player, materialId, amount)
		if err then
			return false, err
		end
	end

	for _, reward in ipairs(rewards.potions or {}) do
		local potionId = reward.potionId
		local amount = math.max(1, math.floor(tonumber(reward.amount) or 1))
		local _, err = DataService:AddOwnedPotionUses(player, potionId, amount)
		if err then
			return false, err
		end
	end

	for _, bodyPartGrant in ipairs(rewards.bodyParts or {}) do
		local _, err = DataService:AddOwnedBodyPart(player, bodyPartGrant)
		if err then
			return false, err
		end
	end

	for _, accessoryGrant in ipairs(rewards.accessories or {}) do
		local _, err = DataService:AddOwnedAccessory(player, accessoryGrant)
		if err then
			return false, err
		end
	end

	for _, auraGrant in ipairs(rewards.auras or {}) do
		local _, err = DataService:AddOwnedAura(player, auraGrant)
		if err then
			return false, err
		end
	end

	if typeof(rewards.achievementIds) == "table" and #rewards.achievementIds > 0 then
		local AchievementService = require(script.Parent.AchievementService)
		for _, achievementId in ipairs(rewards.achievementIds or {}) do
			local ok, err = AchievementService:GrantDirectAward(player, achievementId)
			if not ok then
				return false, err
			end
		end
	end

	return true, nil, rewardPresentation
end

local function tryAutoClaimQuest(
	player: Player,
	state: QuestState.QuestStateValue,
	definition: QuestConfig.QuestDefinition,
	activeQuest: QuestState.ActiveQuest
): (boolean, string?)
	if activeQuest.status ~= "readyToClaim" or QuestConfig.GetCompletionMode(definition) ~= "autoClaim" then
		return false, nil
	end

	local rewardsGranted, rewardError = grantRewards(player, definition)
	if not rewardsGranted then
		return false, rewardError
	end

	finishClaimedQuestInState(state, definition, activeQuest)
	return true, nil
end

local function getCurrentDailyLocalDay(player: Player): number
	local dailyChestState = DataService:GetDailyChestState(player)
	return DailyChestState.GetLocalDay(getNow(), dailyChestState.localUtcOffsetMinutes)
end

local function buildDailyQuestPool(): { QuestConfig.QuestDefinition }
	local pool = {}
	for _, definition in ipairs(QuestConfig.GetAll()) do
		if isDailyQuestDefinition(definition) then
			table.insert(pool, definition)
		end
	end
	table.sort(pool, function(left, right)
		return left.id < right.id
	end)
	return pool
end

local function buildDailyQuestSet(questIds: { string }): { [string]: boolean }
	local set = {}
	for _, questId in ipairs(questIds) do
		if typeof(questId) == "string" and questId ~= "" then
			set[questId] = true
		end
	end
	return set
end

local function sanitizeSelectedDailyQuestIds(selectedQuestIds: { string }, poolById: { [string]: boolean }): { string }
	local sanitized = {}
	local seen = {}
	for _, questId in ipairs(selectedQuestIds) do
		if typeof(questId) == "string" and questId ~= "" and poolById[questId] == true and seen[questId] ~= true then
			table.insert(sanitized, questId)
			seen[questId] = true
			if #sanitized >= DAILY_QUEST_COUNT then
				break
			end
		end
	end
	return sanitized
end

local function getDailySelectionSeed(userId: number, localDay: number): number
	local userComponent = math.abs(math.floor(tonumber(userId) or 0)) % RANDOM_SEED_MODULUS
	local dayComponent = math.max(0, math.floor(tonumber(localDay) or 0)) % RANDOM_SEED_MODULUS
	local seed = (userComponent * 48271 + dayComponent * 69621 + 17) % RANDOM_SEED_MODULUS
	return if seed > 0 then seed else 1
end

local function selectDailyQuestIds(player: Player, localDay: number, pool: { QuestConfig.QuestDefinition }): { string }
	local shuffled = table.create(#pool)
	for index, definition in ipairs(pool) do
		shuffled[index] = definition
	end

	local random = Random.new(getDailySelectionSeed(player.UserId, localDay))
	for index = #shuffled, 2, -1 do
		local swapIndex = random:NextInteger(1, index)
		shuffled[index], shuffled[swapIndex] = shuffled[swapIndex], shuffled[index]
	end

	local selectedQuestIds = {}
	for index = 1, math.min(DAILY_QUEST_COUNT, #shuffled) do
		table.insert(selectedQuestIds, shuffled[index].id)
	end
	table.sort(selectedQuestIds)
	return selectedQuestIds
end

local function cleanupOldTestQuestState(state: QuestState.QuestStateValue): boolean
	local changed = false
	for questId in pairs(OLD_TEST_QUEST_IDS) do
		if state.activeByQuestId[questId] ~= nil then
			state.activeByQuestId[questId] = nil
			changed = true
		end
		if state.completedByQuestId[questId] ~= nil then
			state.completedByQuestId[questId] = nil
			changed = true
		end
		if state.claimedByQuestId[questId] ~= nil then
			state.claimedByQuestId[questId] = nil
			changed = true
		end
		if state.repeatablesByQuestId[questId] ~= nil then
			state.repeatablesByQuestId[questId] = nil
			changed = true
		end
	end
	for flag in pairs(OLD_TEST_UNLOCK_FLAGS) do
		if state.unlockFlags[flag] ~= nil then
			state.unlockFlags[flag] = nil
			changed = true
		end
	end
	return changed
end

local function reconcileDailyQuestState(player: Player, state: QuestState.QuestStateValue): boolean
	local changed = cleanupOldTestQuestState(state)
	local pool = buildDailyQuestPool()
	if #pool <= 0 then
		return changed
	end

	local poolById = {}
	for _, definition in ipairs(pool) do
		poolById[definition.id] = true
	end

	local localDay = getCurrentDailyLocalDay(player)
	local dailyState = state.dailyQuests
	local selectedQuestIds = sanitizeSelectedDailyQuestIds(dailyState.selectedQuestIds, poolById)
	local shouldSelectNewQuests = dailyState.localDay ~= localDay or #selectedQuestIds < math.min(DAILY_QUEST_COUNT, #pool)
	if shouldSelectNewQuests then
		selectedQuestIds = selectDailyQuestIds(player, localDay, pool)
		state.dailyQuests = {
			localDay = localDay,
			selectedQuestIds = selectedQuestIds,
		}
		changed = true
	elseif #selectedQuestIds ~= #dailyState.selectedQuestIds then
		state.dailyQuests = {
			localDay = localDay,
			selectedQuestIds = selectedQuestIds,
		}
		changed = true
	end

	local selectedSet = buildDailyQuestSet(selectedQuestIds)
	for questId, activeQuest in pairs(state.activeByQuestId) do
		local definition = QuestConfig.Get(questId)
		if isDailyQuestDefinition(definition) and selectedSet[questId] ~= true then
			state.activeByQuestId[questId] = nil
			changed = true
		elseif definition == nil and string.find(questId, "daily_", 1, true) == 1 then
			state.activeByQuestId[questId] = nil
			changed = true
		elseif activeQuest.questId ~= questId then
			activeQuest.questId = questId
			changed = true
		end
	end

	for _, questId in ipairs(selectedQuestIds) do
		local definition = QuestConfig.Get(questId)
		if definition and state.activeByQuestId[questId] == nil then
			local activeQuest = buildActiveQuest(definition, getNow())
			refreshStateObjectives(player, state, definition, activeQuest)
			state.activeByQuestId[questId] = activeQuest
			changed = true
		end
	end

	return changed
end

function QuestService:GetRawState(player: Player): QuestState.QuestStateValue
	if not isActive(player) then
		return QuestState.CreateEmptyState()
	end

	local state = DataService:GetQuestState(player)
	if reconcileDailyQuestState(player, state) then
		state = DataService:SetQuestState(player, state)
	end
	return state
end

function QuestService:GetQuestState(player: Player): any
	local state = self:GetRawState(player)
	local questEntries = {}
	local selectedDailyQuestIds = buildDailyQuestSet(state.dailyQuests.selectedQuestIds)

	for _, definition in ipairs(QuestConfig.GetAll()) do
		if not isQuestVisibleToPlayer(player, definition) then
			continue
		end
		if isDailyQuestDefinition(definition) and selectedDailyQuestIds[definition.id] ~= true then
			continue
		end

		local isAvailable, lockReason = getAvailability(player, state, definition)
		local activeQuest = state.activeByQuestId[definition.id]
		if activeQuest then
			markReadyIfComplete(player, state, definition, activeQuest)
		end
		local isClaimedActiveDaily = isDailyQuestDefinition(definition)
			and typeof(activeQuest) == "table"
			and activeQuest.status == "claimed"

		table.insert(questEntries, {
			definition = cloneDefinition(definition),
			isAvailable = isAvailable,
			lockReason = lockReason,
			isActive = activeQuest ~= nil and not isClaimedActiveDaily,
			isCompleted = state.completedByQuestId[definition.id] == true or isClaimedActiveDaily,
			isClaimed = state.claimedByQuestId[definition.id] == true or isClaimedActiveDaily,
			repeatable = QuestConfig.IsRepeatable(definition),
			repeatableState = state.repeatablesByQuestId[definition.id],
			activeQuest = activeQuest,
		})
	end

	return {
		quests = questEntries,
		activeByQuestId = state.activeByQuestId,
		completedByQuestId = state.completedByQuestId,
		claimedByQuestId = state.claimedByQuestId,
		repeatablesByQuestId = state.repeatablesByQuestId,
		unlockFlags = state.unlockFlags,
		dailyQuests = state.dailyQuests,
		serverTime = getNow(),
	}
end

function QuestService:NotifyClient(player: Player, message: string?)
	if updatedRemote and isActive(player) then
		updatedRemote:FireClient(player, self:GetQuestState(player), message)
	end
end

function QuestService:MarkQuestBoardOpened(player: Player)
	if not isActive(player) then
		return response(false, "Player data is not loaded.", self:GetQuestState(player))
	end

	local state = self:GetRawState(player)
	if state.unlockFlags[ONBOARDING_QUEST_BOARD_OPENED_FLAG] ~= true then
		state.unlockFlags[ONBOARDING_QUEST_BOARD_OPENED_FLAG] = true
		DataService:SetQuestState(player, state)
		self:NotifyClient(player, nil)
	end

	return response(true, "Quest board opened.", self:GetQuestState(player))
end

function QuestService:AcceptQuest(player: Player, payload: any)
	if not isActive(player) then
		return response(false, "Player data is not loaded.", self:GetQuestState(player))
	end

	local questId = normalizeQuestId(payload)
	local providerId = normalizeProviderId(payload)
	local definition = QuestConfig.Get(questId)
	if not definition then
		return response(false, "That quest does not exist.", self:GetQuestState(player))
	end

	local state = self:GetRawState(player)
	local isAvailable, lockReason = getAvailability(player, state, definition, providerId)
	if not isAvailable then
		return response(false, lockReason or "That quest is not available.", self:GetQuestState(player))
	end

	local activeQuest = buildActiveQuest(definition, getNow())
	refreshStateObjectives(player, state, definition, activeQuest)
	markReadyIfComplete(player, state, definition, activeQuest)
	state.activeByQuestId[definition.id] = activeQuest
	local autoClaimed, autoClaimError = tryAutoClaimQuest(player, state, definition, activeQuest)
	DataService:SetQuestState(player, state)

	local message = if autoClaimed
		then "Quest complete."
		elseif activeQuest.status == "readyToClaim" then "Quest objective complete."
		else "Quest accepted."
	if autoClaimError then
		message = autoClaimError
	end
	self:NotifyClient(player, message)
	return response(true, message, self:GetQuestState(player), {
		activeQuest = activeQuest,
	})
end

function QuestService:AbandonQuest(player: Player, payload: any)
	if not isActive(player) then
		return response(false, "Player data is not loaded.", self:GetQuestState(player))
	end

	local questId = normalizeQuestId(payload)
	local definition = QuestConfig.Get(questId)
	if not definition then
		return response(false, "That quest does not exist.", self:GetQuestState(player))
	end
	if not QuestConfig.IsAbandonable(definition) then
		return response(false, "That quest cannot be abandoned.", self:GetQuestState(player))
	end

	local state = self:GetRawState(player)
	if not state.activeByQuestId[definition.id] then
		return response(false, "That quest is not active.", self:GetQuestState(player))
	end

	state.activeByQuestId[definition.id] = nil
	DataService:SetQuestState(player, state)
	self:NotifyClient(player, "Quest abandoned.")
	return response(true, "Quest abandoned.", self:GetQuestState(player))
end

function QuestService:ClaimQuest(player: Player, payload: any)
	if not isActive(player) then
		return response(false, "Player data is not loaded.", self:GetQuestState(player))
	end

	local questId = normalizeQuestId(payload)
	local providerId = normalizeProviderId(payload)
	local definition = QuestConfig.Get(questId)
	if not definition then
		return response(false, "That quest does not exist.", self:GetQuestState(player))
	end
	if requiresProvider(definition) and not hasProviderId(definition, providerId) then
		return response(false, "Talk to the quest giver to claim this quest.", self:GetQuestState(player))
	end

	local state = self:GetRawState(player)
	local activeQuest = state.activeByQuestId[definition.id]
	if not activeQuest then
		return response(false, "That quest is not active.", self:GetQuestState(player))
	end

	markReadyIfComplete(player, state, definition, activeQuest)
	if activeQuest.status ~= "readyToClaim" then
		return response(false, "That quest is not complete yet.", self:GetQuestState(player))
	end

	local rewardsGranted, rewardError, rewardPresentation = grantRewards(player, definition)
	if not rewardsGranted then
		return response(false, rewardError or "Failed to grant quest rewards.", self:GetQuestState(player))
	end

	finishClaimedQuestInState(state, definition, activeQuest)
	DataService:SetQuestState(player, state)
	self:NotifyClient(player, "Quest complete.")
	return response(true, "Quest complete.", self:GetQuestState(player), {
		rewardPresentation = rewardPresentation,
	})
end

function QuestService:RecordEvent(player: Player, eventType: string, payload: any?)
	if not isActive(player) or typeof(eventType) ~= "string" or eventType == "" then
		return false
	end

	local state = self:GetRawState(player)
	local changed = false

	for questId, activeQuest in pairs(state.activeByQuestId) do
		if activeQuest.status ~= "active" then
			continue
		end

		local definition = QuestConfig.Get(questId)
		if not definition then
			continue
		end

		local before = {
			status = activeQuest.status,
			currentPartIndex = activeQuest.currentPartIndex,
			completedParts = activeQuest.completedParts,
			completedAt = activeQuest.completedAt,
			objectives = cloneObjectiveSnapshot(activeQuest),
		}

		for _, objective in ipairs(QuestConfig.GetPartObjectives(definition, getActivePartIndex(definition, activeQuest))) do
			if eventMatchesObjective(objective, eventType, payload) then
				local current = getObjectiveProgress(activeQuest, objective)
				setObjectiveProgress(activeQuest, objective, current.progress + getEventIncrement(objective, payload))
				changed = true
			end
		end

		markReadyIfComplete(player, state, definition, activeQuest)
		if hasActiveQuestChanged(activeQuest, before) then
			changed = true
		end
		local autoClaimed = tryAutoClaimQuest(player, state, definition, activeQuest)
		if autoClaimed then
			changed = true
		end
	end

	if changed then
		DataService:SetQuestState(player, state)
		self:NotifyClient(player, "Quest progress updated.")
	end

	return changed
end

local function readStringAttributeFromAncestors(source: Instance?, attributeName: string): string?
	local current = source
	while current do
		local value = current:GetAttribute(attributeName)
		if typeof(value) == "string" and value ~= "" then
			return value
		end
		current = current.Parent
	end

	return nil
end

function QuestService:OnStart()
	local folder = ensureQuestRemotesFolder()
	getStateRemote = createOrGetRemoteFunction(folder, GET_STATE_REMOTE_NAME)
	acceptRemote = createOrGetRemoteFunction(folder, ACCEPT_REMOTE_NAME)
	abandonRemote = createOrGetRemoteFunction(folder, ABANDON_REMOTE_NAME)
	claimRemote = createOrGetRemoteFunction(folder, CLAIM_REMOTE_NAME)
	markBoardOpenedRemote = createOrGetRemoteFunction(folder, MARK_BOARD_OPENED_REMOTE_NAME)
	updatedRemote = createOrGetRemoteEvent(folder, UPDATED_REMOTE_NAME)

	getStateRemote.OnServerInvoke = function(player: Player)
		if not RequestLimiter:Allow(player, "remote.quests.get_state") then
			return response(false, "You're refreshing quests too quickly.", self:GetQuestState(player))
		end
		return response(true, "Loaded quests.", self:GetQuestState(player))
	end

	acceptRemote.OnServerInvoke = function(player: Player, payload: any)
		if not RequestLimiter:Allow(player, "remote.quests.accept") then
			return response(false, "You're accepting quests too quickly.", self:GetQuestState(player))
		end
		return self:AcceptQuest(player, payload)
	end

	abandonRemote.OnServerInvoke = function(player: Player, payload: any)
		if not RequestLimiter:Allow(player, "remote.quests.abandon") then
			return response(false, "You're abandoning quests too quickly.", self:GetQuestState(player))
		end
		return self:AbandonQuest(player, payload)
	end

	claimRemote.OnServerInvoke = function(player: Player, payload: any)
		if not RequestLimiter:Allow(player, "remote.quests.claim") then
			return response(false, "You're claiming quests too quickly.", self:GetQuestState(player))
		end
		return self:ClaimQuest(player, payload)
	end

	markBoardOpenedRemote.OnServerInvoke = function(player: Player)
		if not RequestLimiter:Allow(player, "remote.quests.mark_board_opened") then
			return response(false, "You're opening the quest board too quickly.", self:GetQuestState(player))
		end
		return self:MarkQuestBoardOpened(player)
	end

	DataService.MoneyChanged:Connect(function(player: Player, previousValue: number, newValue: number, delta: number, source: string?)
		if source == "quest_reward" then
			return
		end

		self:RecordEvent(player, "money_changed", {
			previousValue = previousValue,
			newValue = newValue,
			delta = delta,
			source = source,
			amount = math.max(0, math.floor(tonumber(delta) or 0)),
		})
	end)

	DataService.OwnedBodyPartAdded:Connect(function(player: Player, record: any)
		self:RecordEvent(player, "body_part_acquired", record)
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		local dialogueId = readStringAttributeFromAncestors(prompt, DIALOGUE_ID_ATTRIBUTE)
		if typeof(dialogueId) ~= "string" or dialogueId == "" then
			return
		end

		self:RecordEvent(player, "dialogue_prompt_triggered", {
			dialogueId = dialogueId,
			promptName = prompt.Name,
			sourceName = if prompt.Parent then prompt.Parent.Name else "",
		})
	end)
end

return QuestService
