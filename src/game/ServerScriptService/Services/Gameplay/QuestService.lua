local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local QuestConfig = require(ReplicatedStorage.Shared.Config.QuestConfig)
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
local UPDATED_REMOTE_NAME = "QuestUpdated"

local remotesFolder: Folder? = nil
local questsFolder: Folder? = nil
local getStateRemote: RemoteFunction? = nil
local acceptRemote: RemoteFunction? = nil
local abandonRemote: RemoteFunction? = nil
local claimRemote: RemoteFunction? = nil
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

local function cloneDefinition(definition: QuestConfig.QuestDefinition): any
	local clone = table.clone(definition)
	clone.providerIds = table.clone(definition.providerIds or {})
	clone.objectives = table.clone(definition.objectives or {})
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

local function refreshStateObjectives(player: Player, state: QuestState.QuestStateValue, definition: QuestConfig.QuestDefinition, activeQuest: QuestState.ActiveQuest)
	for _, objective in ipairs(definition.objectives) do
		if objective.kind == "state" then
			setObjectiveProgress(activeQuest, objective, getStateObjectiveProgress(player, state, objective))
		end
	end
end

local function areAllObjectivesCompleted(definition: QuestConfig.QuestDefinition, activeQuest: QuestState.ActiveQuest): boolean
	for _, objective in ipairs(definition.objectives) do
		local progress = getObjectiveProgress(activeQuest, objective)
		if progress.completed ~= true and progress.progress < objectiveTarget(objective) then
			return false
		end
	end

	return true
end

local function markReadyIfComplete(player: Player, state: QuestState.QuestStateValue, definition: QuestConfig.QuestDefinition, activeQuest: QuestState.ActiveQuest)
	refreshStateObjectives(player, state, definition, activeQuest)
	if activeQuest.status == "active" and areAllObjectivesCompleted(definition, activeQuest) then
		activeQuest.status = "readyToClaim"
		activeQuest.completedAt = getNow()
	end
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

local function getAvailability(player: Player, state: QuestState.QuestStateValue, definition: QuestConfig.QuestDefinition): (boolean, string?)
	if definition.adminOnly == true and not isAdminDevPlayer(player) then
		return false, "This quest is only available to admins/devs."
	end
	if state.activeByQuestId[definition.id] ~= nil then
		return false, "Quest is already active."
	end
	if hasCompletedOneTime(state, definition) then
		return false, "Quest is already completed."
	end

	local prerequisitesMet, prerequisiteMessage = meetsPrerequisites(state, definition)
	if not prerequisitesMet then
		return false, prerequisiteMessage
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
		objectives = {},
	}

	for _, objective in ipairs(definition.objectives) do
		setObjectiveProgress(activeQuest, objective, 0)
	end

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
	state.activeByQuestId[definition.id] = nil

	local now = getNow()
	if QuestConfig.IsRepeatable(definition) then
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

local function grantRewards(player: Player, definition: QuestConfig.QuestDefinition): (boolean, string?)
	local rewards = definition.rewards or {}

	local money = math.floor(tonumber(rewards.money) or 0)
	if money > 0 then
		DataService:AddMoney(player, money, "quest_reward")
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

	return true, nil
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

function QuestService:GetRawState(player: Player): QuestState.QuestStateValue
	if not isActive(player) then
		return QuestState.CreateEmptyState()
	end

	return DataService:GetQuestState(player)
end

function QuestService:GetQuestState(player: Player): any
	local state = self:GetRawState(player)
	local questEntries = {}

	for _, definition in ipairs(QuestConfig.GetAll()) do
		if not isQuestVisibleToPlayer(player, definition) then
			continue
		end

		local isAvailable, lockReason = getAvailability(player, state, definition)
		local activeQuest = state.activeByQuestId[definition.id]
		if activeQuest then
			markReadyIfComplete(player, state, definition, activeQuest)
		end

		table.insert(questEntries, {
			definition = cloneDefinition(definition),
			isAvailable = isAvailable,
			lockReason = lockReason,
			isActive = activeQuest ~= nil,
			isCompleted = state.completedByQuestId[definition.id] == true,
			isClaimed = state.claimedByQuestId[definition.id] == true,
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
		serverTime = getNow(),
	}
end

function QuestService:NotifyClient(player: Player, message: string?)
	if updatedRemote and isActive(player) then
		updatedRemote:FireClient(player, self:GetQuestState(player), message)
	end
end

function QuestService:AcceptQuest(player: Player, payload: any)
	if not isActive(player) then
		return response(false, "Player data is not loaded.", self:GetQuestState(player))
	end

	local questId = normalizeQuestId(payload)
	local definition = QuestConfig.Get(questId)
	if not definition then
		return response(false, "That quest does not exist.", self:GetQuestState(player))
	end

	local state = self:GetRawState(player)
	local isAvailable, lockReason = getAvailability(player, state, definition)
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
	local definition = QuestConfig.Get(questId)
	if not definition then
		return response(false, "That quest does not exist.", self:GetQuestState(player))
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

	local rewardsGranted, rewardError = grantRewards(player, definition)
	if not rewardsGranted then
		return response(false, rewardError or "Failed to grant quest rewards.", self:GetQuestState(player))
	end

	finishClaimedQuestInState(state, definition, activeQuest)
	DataService:SetQuestState(player, state)
	self:NotifyClient(player, "Quest complete.")
	return response(true, "Quest complete.", self:GetQuestState(player))
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

		for _, objective in ipairs(definition.objectives) do
			if eventMatchesObjective(objective, eventType, payload) then
				local current = getObjectiveProgress(activeQuest, objective)
				setObjectiveProgress(activeQuest, objective, current.progress + getEventIncrement(objective, payload))
				changed = true
			end
		end

		local previousStatus = activeQuest.status
		markReadyIfComplete(player, state, definition, activeQuest)
		if activeQuest.status ~= previousStatus then
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

function QuestService:OnStart()
	local folder = ensureQuestRemotesFolder()
	getStateRemote = createOrGetRemoteFunction(folder, GET_STATE_REMOTE_NAME)
	acceptRemote = createOrGetRemoteFunction(folder, ACCEPT_REMOTE_NAME)
	abandonRemote = createOrGetRemoteFunction(folder, ABANDON_REMOTE_NAME)
	claimRemote = createOrGetRemoteFunction(folder, CLAIM_REMOTE_NAME)
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
end

return QuestService
