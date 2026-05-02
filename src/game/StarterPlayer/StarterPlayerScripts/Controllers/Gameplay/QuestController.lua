local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local FrameController = require(script.Parent.FrameController)
local QuestBoardOnboardingGuideController = require(script.Parent.QuestBoardOnboardingGuideController)
local UIController = require(script.Parent.UIController)
local Notify = require(ReplicatedStorage.Shared.UI.Notify)

local LOCAL_PLAYER = Players.LocalPlayer
local WINDOW_NAME = "QuestsFrame"
local REMOTES_FOLDER_NAME = "Remotes"
local QUESTS_FOLDER_NAME = "Quests"
local GET_STATE_REMOTE_NAME = "GetQuestState"
local ACCEPT_REMOTE_NAME = "AcceptQuest"
local CLAIM_REMOTE_NAME = "ClaimQuest"
local MARK_BOARD_OPENED_REMOTE_NAME = "MarkQuestBoardOpened"
local UPDATED_REMOTE_NAME = "QuestUpdated"
local QUEST_BOARD_MODEL_NAME = "Quest Board"
local QUEST_BOARD_PROMPT_PARENT_NAME = "PromptPart"
local QUEST_BOARD_PROMPT_NAME = "BoardPrompt"

local HUD_QUEST_PREFIX = "QuestHud_"
local HUD_STEP_PREFIX = "QuestHudStep_"
local MODAL_ROW_PREFIX = "QuestRow_"
local REWARD_ROW_PREFIX = "QuestReward_"

local ONBOARDING_LESSON_QUEST_IDS = table.freeze({
	stan_paid_roll_intro = true,
	stan_appraisal_intro = true,
	stan_crafting_intro = true,
	stan_boss_intro = true,
})
local ONBOARDING_LESSON_ORDER = table.freeze({
	stan_paid_roll_intro = 1,
	stan_appraisal_intro = 2,
	stan_crafting_intro = 3,
	stan_boss_intro = 4,
})

type QuestRemotes = {
	getState: RemoteFunction,
	acceptQuest: RemoteFunction,
	claimQuest: RemoteFunction,
	markBoardOpened: RemoteFunction,
	questUpdated: RemoteEvent,
}

type QuestUi = {
	hudRoot: GuiObject,
	hudList: ScrollingFrame,
	hudTemplate: GuiObject,
	hudHeaderTemplate: GuiObject,
	hudStepTemplate: GuiObject,
	modalRoot: GuiObject,
	tabQuestsButton: GuiButton,
	tabDailyButton: GuiButton,
	questsNotification: TextLabel?,
	dailyNotification: TextLabel?,
	list: ScrollingFrame,
	normalRowTemplate: GuiObject,
	claimRowTemplate: GuiObject,
	board: GuiObject,
	boardQuestName: TextLabel,
	boardDescription: TextLabel,
	boardRewards: ScrollingFrame,
	boardRewardTemplate: GuiObject,
	boardRewardEmpty: GuiObject?,
	startButton: GuiButton,
	startButtonLabel: TextLabel?,
	inProgressLabel: TextLabel?,
}

local QuestController = {
	_started = false,
	_ui = nil :: QuestUi?,
	_remotes = nil :: QuestRemotes?,
	_state = nil :: any,
	_filter = "main",
	_selectedQuestId = nil :: string?,
	_requestInFlight = false,
}

local function showNotification(text: string, tone: string?)
	Notify.Show(text, {
		channel = "quests",
		duration = 3,
		tone = tone,
	})
end

local function getTextLabel(root: Instance, name: string): TextLabel?
	local label = root:FindFirstChild(name, true)
	return if label and label:IsA("TextLabel") then label else nil
end

local function findDirectTextLabel(root: Instance): TextLabel?
	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("TextLabel") then
			return child
		end
	end
	return nil
end

local function setButtonText(button: GuiButton, text: string)
	local label = findDirectTextLabel(button)
	if label then
		label.Text = text
	end
end

local function clearGeneratedChildren(container: Instance, prefix: string)
	for _, child in ipairs(container:GetChildren()) do
		if string.find(child.Name, prefix, 1, true) == 1 then
			child:Destroy()
		end
	end
end

local function hideTemplate(template: GuiObject?)
	if not template then
		return
	end
	template.Visible = false
	if template:IsA("GuiButton") then
		template.Active = false
	end
end

local function raiseGuiTree(root: GuiObject, minZIndex: number)
	root.ZIndex = math.max(root.ZIndex, minZIndex)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = math.max(descendant.ZIndex, minZIndex)
		end
	end
end

local function getDefinition(entry: any): any
	return if typeof(entry) == "table" then entry.definition else nil
end

local function getParts(definition: any): { any }
	if typeof(definition) ~= "table" then
		return {}
	end
	if typeof(definition.parts) == "table" and #definition.parts > 0 then
		return definition.parts
	end
	return {
		{
			description = definition.description,
			objectives = if typeof(definition.objectives) == "table" then definition.objectives else {},
		},
	}
end

local function getPartCount(definition: any): number
	return math.max(1, #getParts(definition))
end

local function getActiveQuest(entry: any): any
	return if typeof(entry) == "table" then entry.activeQuest else nil
end

local function getCurrentPartIndex(entry: any): number
	local activeQuest = getActiveQuest(entry)
	if typeof(activeQuest) == "table" then
		return math.max(1, math.floor(tonumber(activeQuest.currentPartIndex) or 1))
	end
	return 1
end

local function getCurrentPart(entry: any): any
	local definition = getDefinition(entry)
	local parts = getParts(definition)
	local index = math.clamp(getCurrentPartIndex(entry), 1, math.max(1, #parts))
	return parts[index] or parts[1] or {}
end

local function getCurrentObjectives(entry: any): { any }
	local part = getCurrentPart(entry)
	if typeof(part.objectives) == "table" then
		return part.objectives
	end
	return {}
end

local function getQuestDescription(entry: any): string
	local definition = getDefinition(entry)
	local part = getCurrentPart(entry)
	if typeof(part.description) == "string" and part.description ~= "" then
		return part.description
	end
	return tostring(if definition then definition.description else "")
end

local function getCompletedParts(entry: any): number
	local definition = getDefinition(entry)
	local totalParts = getPartCount(definition)
	if entry and (entry.isCompleted == true or entry.isClaimed == true) then
		return totalParts
	end

	local activeQuest = getActiveQuest(entry)
	if typeof(activeQuest) ~= "table" then
		return 0
	end

	if activeQuest.status == "readyToClaim" then
		return totalParts
	end

	return math.clamp(math.floor(tonumber(activeQuest.completedParts) or 0), 0, totalParts)
end

local function isMainQuest(entry: any): boolean
	local definition = getDefinition(entry)
	local kind = if typeof(definition) == "table" then definition.kind else nil
	return kind == "main" or kind == "unlock"
end

local function isDailyQuest(entry: any): boolean
	local definition = getDefinition(entry)
	return typeof(definition) == "table" and definition.kind == "daily"
end

local function isOnboardingLesson(entryOrDefinition: any): boolean
	local definition = if typeof(entryOrDefinition) == "table" and entryOrDefinition.definition ~= nil
		then entryOrDefinition.definition
		else entryOrDefinition
	local questId = if typeof(definition) == "table" then definition.id else nil
	return typeof(questId) == "string" and ONBOARDING_LESSON_QUEST_IDS[questId] == true
end

local function isBoardVisibleQuest(entry: any): boolean
	local definition = getDefinition(entry)
	return typeof(definition) == "table" and definition.boardVisible ~= false
end

local function shouldShowInFilter(entry: any, filterName: string): boolean
	if not isBoardVisibleQuest(entry) then
		return false
	end

	if filterName == "main" then
		return isMainQuest(entry)
	end
	return not isMainQuest(entry)
end

local function getObjectiveProgress(activeQuest: any, objective: any): any
	local objectiveId = if typeof(objective) == "table" then objective.id else nil
	if typeof(activeQuest) == "table" and typeof(activeQuest.objectives) == "table" and typeof(objectiveId) == "string" then
		local progress = activeQuest.objectives[objectiveId]
		if typeof(progress) == "table" then
			return progress
		end
	end

	return {
		progress = 0,
		completed = false,
	}
end

local function getObjectiveTarget(objective: any): number
	return math.max(1, math.floor(tonumber(if typeof(objective) == "table" then objective.targetValue else 1) or 1))
end

local function formatWholeNumber(value: any): string
	local rounded = math.max(0, math.floor(tonumber(value) or 0))
	local text = tostring(rounded)
	local left, num, right = string.match(text, "^([^%d]*%d)(%d*)(.-)$")
	if not left then
		return text
	end
	return left .. (num:reverse():gsub("(%d%d%d)", "%1,"):reverse()) .. right
end

local function formatRewardRows(rewards: any): { string }
	local rows = {}
	if typeof(rewards) ~= "table" then
		return rows
	end

	local money = math.floor(tonumber(rewards.money) or 0)
	if money > 0 then
		table.insert(rows, "$" .. formatWholeNumber(money))
	end
	local timeShards = math.floor(tonumber(rewards.timeShards) or 0)
	if timeShards > 0 then
		table.insert(rows, formatWholeNumber(timeShards) .. " Time Shards")
	end

	for _, reward in ipairs(rewards.materials or {}) do
		table.insert(rows, string.format("%s x%s", tostring(reward.materialId or "Material"), formatWholeNumber(reward.amount or 1)))
	end
	for _, reward in ipairs(rewards.potions or {}) do
		table.insert(rows, string.format("%s x%s", tostring(reward.potionId or "Potion"), formatWholeNumber(reward.amount or 1)))
	end
	for _, reward in ipairs(rewards.dailyChests or {}) do
		table.insert(rows, string.format("%s x%s", tostring(reward.chestId or "Daily Chest"), formatWholeNumber(reward.amount or 1)))
	end
	for _, flag in ipairs(rewards.unlockFlags or {}) do
		table.insert(rows, "Unlock: " .. tostring(flag))
	end
	for _, achievementId in ipairs(rewards.achievementIds or {}) do
		table.insert(rows, "Achievement: " .. tostring(achievementId))
	end
	for _, _ in ipairs(rewards.bodyParts or {}) do
		table.insert(rows, "Body part reward")
	end
	for _, _ in ipairs(rewards.accessories or {}) do
		table.insert(rows, "Accessory reward")
	end
	for _, _ in ipairs(rewards.auras or {}) do
		table.insert(rows, "Aura reward")
	end

	return rows
end

local function setTabCount(label: TextLabel?, count: number)
	if not label then
		return
	end
	label.Visible = count > 0
	label.Text = tostring(count)
end

local function setHudStoryIconsVisible(header: GuiObject, visible: boolean)
	local top = header:FindFirstChild("Top")
	if not top then
		return
	end

	for _, child in ipairs(top:GetChildren()) do
		if child.Name == "Icon" and child:IsA("GuiObject") then
			child.Visible = visible
		end
	end
end

local function isQuestBoardPrompt(prompt: ProximityPrompt): boolean
	if prompt.Name ~= QUEST_BOARD_PROMPT_NAME then
		return false
	end

	local promptPart = prompt.Parent
	if not (promptPart and promptPart.Name == QUEST_BOARD_PROMPT_PARENT_NAME) then
		return false
	end

	local questBoard = promptPart.Parent
	return questBoard ~= nil and questBoard.Name == QUEST_BOARD_MODEL_NAME and questBoard.Parent == Workspace
end

function QuestController:_ensureRemotes(): boolean
	if self._remotes and self._remotes.getState.Parent then
		return true
	end

	local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, 30)
	local questsFolder = remotesFolder and remotesFolder:WaitForChild(QUESTS_FOLDER_NAME, 30)
	local getState = questsFolder and questsFolder:WaitForChild(GET_STATE_REMOTE_NAME, 30)
	local acceptQuest = questsFolder and questsFolder:WaitForChild(ACCEPT_REMOTE_NAME, 30)
	local claimQuest = questsFolder and questsFolder:WaitForChild(CLAIM_REMOTE_NAME, 30)
	local markBoardOpened = questsFolder and questsFolder:WaitForChild(MARK_BOARD_OPENED_REMOTE_NAME, 30)
	local questUpdated = questsFolder and questsFolder:WaitForChild(UPDATED_REMOTE_NAME, 30)

	if not (
		getState and getState:IsA("RemoteFunction")
		and acceptQuest and acceptQuest:IsA("RemoteFunction")
		and claimQuest and claimQuest:IsA("RemoteFunction")
		and markBoardOpened and markBoardOpened:IsA("RemoteFunction")
		and questUpdated and questUpdated:IsA("RemoteEvent")
	) then
		Logger.Warn("[QuestController] Quest remotes are missing.")
		return false
	end

	self._remotes = {
		getState = getState,
		acceptQuest = acceptQuest,
		claimQuest = claimQuest,
		markBoardOpened = markBoardOpened,
		questUpdated = questUpdated,
	}
	return true
end

function QuestController:_resolveRowTemplates(list: ScrollingFrame): (GuiObject, GuiObject)
	local normalTemplate = nil :: GuiObject?
	local claimTemplate = nil :: GuiObject?

	for _, child in ipairs(list:GetChildren()) do
		if child.Name == "Template" and child:IsA("GuiObject") then
			if child:FindFirstChild("ClaimButton") then
				claimTemplate = child
			else
				normalTemplate = child
			end
		end
	end

	assert(normalTemplate and claimTemplate, "QuestsFrame list needs normal and claim row templates.")
	return normalTemplate, claimTemplate
end

function QuestController:_ensureUi(): QuestUi
	if self._ui and self._ui.modalRoot.Parent then
		return self._ui
	end

	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	local mainInterface = playerGui:WaitForChild("MainInterface", 30)
	local modalRoot = playerGui:WaitForChild("ModalRoot", 30)
	assert(mainInterface and mainInterface:IsA("ScreenGui"), "PlayerGui.MainInterface is missing.")
	assert(modalRoot and modalRoot:IsA("ScreenGui"), "PlayerGui.ModalRoot is missing.")

	local hudRoot = mainInterface:WaitForChild("QuestHolder", 30)
	local hudList = hudRoot:WaitForChild("ScrollingFrame", 30)
	local hudTemplate = hudList:WaitForChild("QuestTemplate", 30)
	local hudHeaderTemplate = hudTemplate:WaitForChild("Template", 30)
	local hudStepTemplate = hudTemplate:WaitForChild("StepTemplate", 30)
	assert(hudRoot:IsA("GuiObject") and hudList:IsA("ScrollingFrame") and hudTemplate:IsA("GuiObject"))
	assert(hudHeaderTemplate:IsA("GuiObject") and hudStepTemplate:IsA("GuiObject"))

	local questsRoot = modalRoot:WaitForChild(WINDOW_NAME, 30)
	local buttons = questsRoot:WaitForChild("Buttons", 30)
	local tabQuestsButton = buttons:WaitForChild("Quests", 30)
	local tabDailyButton = buttons:WaitForChild("Daily", 30)
	local questsPanel = questsRoot:WaitForChild("Quests", 30)
	local list = questsPanel:WaitForChild("ScrollingFrame", 30)
	local normalRowTemplate, claimRowTemplate = self:_resolveRowTemplates(list)
	local board = questsRoot:WaitForChild("QuestBoard", 30)
	local rewards = board:WaitForChild("Rewards", 30)
	local rewardTemplate = rewards:WaitForChild("Template", 30)
	local startButton = board:WaitForChild("StartQuestButton", 30)
	assert(questsRoot:IsA("GuiObject") and tabQuestsButton:IsA("GuiButton") and tabDailyButton:IsA("GuiButton"))
	assert(list:IsA("ScrollingFrame") and board:IsA("GuiObject") and rewards:IsA("ScrollingFrame"))
	assert(rewardTemplate:IsA("GuiObject") and startButton:IsA("GuiButton"))

	hudList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rewards.AutomaticCanvasSize = Enum.AutomaticSize.Y
	hudRoot.Visible = false
	hideTemplate(hudTemplate)
	hideTemplate(normalRowTemplate)
	hideTemplate(claimRowTemplate)
	hideTemplate(rewardTemplate)

	self._ui = {
		hudRoot = hudRoot,
		hudList = hudList,
		hudTemplate = hudTemplate,
		hudHeaderTemplate = hudHeaderTemplate,
		hudStepTemplate = hudStepTemplate,
		modalRoot = questsRoot,
		tabQuestsButton = tabQuestsButton,
		tabDailyButton = tabDailyButton,
		questsNotification = getTextLabel(tabQuestsButton, "NotificationCount"),
		dailyNotification = getTextLabel(tabDailyButton, "NotificationCount"),
		list = list,
		normalRowTemplate = normalRowTemplate,
		claimRowTemplate = claimRowTemplate,
		board = board,
		boardQuestName = board:WaitForChild("QuestName", 30) :: TextLabel,
		boardDescription = board:WaitForChild("Description", 30) :: TextLabel,
		boardRewards = rewards,
		boardRewardTemplate = rewardTemplate,
		boardRewardEmpty = board:FindFirstChild("RewardNotExists"),
		startButton = startButton,
		startButtonLabel = findDirectTextLabel(startButton),
		inProgressLabel = board:FindFirstChild("InProgress") :: TextLabel?,
	}

	return self._ui
end

function QuestController:_getQuestEntries(): { any }
	if typeof(self._state) == "table" and typeof(self._state.quests) == "table" then
		return self._state.quests
	end
	return {}
end

function QuestController:_findQuestEntry(questId: string?): any?
	if typeof(questId) ~= "string" then
		return nil
	end

	for _, entry in ipairs(self:_getQuestEntries()) do
		local definition = getDefinition(entry)
		if typeof(definition) == "table" and definition.id == questId then
			return entry
		end
	end
	return nil
end

function QuestController:_getVisibleQuestEntries(): { any }
	local entries = {}
	for _, entry in ipairs(self:_getQuestEntries()) do
		if shouldShowInFilter(entry, self._filter) then
			table.insert(entries, entry)
		end
	end
	table.sort(entries, function(left, right)
		local leftDefinition = getDefinition(left) or {}
		local rightDefinition = getDefinition(right) or {}
		local leftOnboardingOrder = ONBOARDING_LESSON_ORDER[leftDefinition.id]
		local rightOnboardingOrder = ONBOARDING_LESSON_ORDER[rightDefinition.id]
		if leftOnboardingOrder ~= nil or rightOnboardingOrder ~= nil then
			return (leftOnboardingOrder or math.huge) < (rightOnboardingOrder or math.huge)
		end
		return tostring(leftDefinition.displayName or leftDefinition.id) < tostring(rightDefinition.displayName or rightDefinition.id)
	end)
	return entries
end

function QuestController:_applyState(state: any)
	if typeof(state) == "table" then
		self._state = state
	end
	self:_syncUi()
end

function QuestController:_invokeQuestRemote(remote: RemoteFunction, questId: string, failureMessage: string)
	if self._requestInFlight then
		return
	end

	self._requestInFlight = true
	local ok, result = pcall(function()
		return remote:InvokeServer({
			questId = questId,
		})
	end)
	self._requestInFlight = false

	if not ok then
		Logger.Warn(string.format("[QuestController] Quest remote failed: %s", tostring(result)))
		showNotification(failureMessage)
		return
	end
	if typeof(result) ~= "table" then
		showNotification(failureMessage)
		return
	end

	if typeof(result.state) == "table" then
		self:_applyState(result.state)
	end

	if result.ok ~= true then
		showNotification(tostring(result.message or failureMessage))
	end
end

function QuestController:_requestState(showFailure: boolean?)
	if not self:_ensureRemotes() then
		return
	end

	local remotes = self._remotes :: QuestRemotes
	local ok, result = pcall(function()
		return remotes.getState:InvokeServer()
	end)
	if not ok then
		Logger.Warn(string.format("[QuestController] GetQuestState failed: %s", tostring(result)))
		if showFailure then
			showNotification("Quests are not ready right now.")
		end
		return
	end
	if typeof(result) == "table" and typeof(result.state) == "table" then
		self:_applyState(result.state)
	end
end

function QuestController:_acceptQuest(questId: string)
	if not self:_ensureRemotes() then
		showNotification("Quests are not ready right now.")
		return
	end
	self:_invokeQuestRemote((self._remotes :: QuestRemotes).acceptQuest, questId, "Could not start quest.")
end

function QuestController:_claimQuest(questId: string)
	if not self:_ensureRemotes() then
		showNotification("Quests are not ready right now.")
		return
	end
	self:_invokeQuestRemote((self._remotes :: QuestRemotes).claimQuest, questId, "Could not claim quest.")
end

function QuestController:_markQuestBoardOpened()
	if not self:_ensureRemotes() then
		return
	end

	task.spawn(function()
		local ok, result = pcall(function()
			return (self._remotes :: QuestRemotes).markBoardOpened:InvokeServer()
		end)
		if not ok then
			Logger.Warn(string.format("[QuestController] MarkQuestBoardOpened failed: %s", tostring(result)))
			return
		end
		if typeof(result) == "table" and typeof(result.state) == "table" then
			self:_applyState(result.state)
		end
	end)
end

function QuestController:_syncHud()
	local ui = self:_ensureUi()
	clearGeneratedChildren(ui.hudList, HUD_QUEST_PREFIX)
	hideTemplate(ui.hudTemplate)

	local activeEntries = {}
	for _, entry in ipairs(self:_getQuestEntries()) do
		local activeQuest = getActiveQuest(entry)
		if isMainQuest(entry)
			and not isDailyQuest(entry)
			and entry.isActive == true
			and typeof(activeQuest) == "table"
			and activeQuest.status ~= "claimed"
		then
			table.insert(activeEntries, entry)
		end
	end

	ui.hudRoot.Visible = #activeEntries > 0
	for index, entry in ipairs(activeEntries) do
		local definition = getDefinition(entry)
		local activeQuest = getActiveQuest(entry)
		local objectives = getCurrentObjectives(entry)
		local questFrame = ui.hudTemplate:Clone()
		questFrame.Name = string.format("%s%03d", HUD_QUEST_PREFIX, index)
		questFrame.LayoutOrder = index
		questFrame.Size = UDim2.new(1, 0, 0, 0)
		questFrame.AutomaticSize = Enum.AutomaticSize.Y
		questFrame.Visible = true
		questFrame.Parent = ui.hudList

		local header = questFrame:FindFirstChild("Template")
		if header and header:IsA("GuiObject") then
			header.Visible = true
			setHudStoryIconsVisible(header, isMainQuest(entry))
			local questName = getTextLabel(header, "QuestName")
			if questName then
				questName.Text = tostring(definition and definition.displayName or "Quest")
			end
			local questDescription = getTextLabel(header, "QuestDescription")
			if questDescription then
				questDescription.Text = getQuestDescription(entry)
			end
		end

		local stepTemplate = questFrame:FindFirstChild("StepTemplate")
		if not (stepTemplate and stepTemplate:IsA("GuiObject")) then
			continue
		end
		stepTemplate.Parent = nil
		for objectiveIndex, objective in ipairs(objectives) do
			local step = stepTemplate:Clone()
			step.Name = string.format("%s%03d", HUD_STEP_PREFIX, objectiveIndex)
			step.LayoutOrder = objectiveIndex
			step.Visible = true
			step.Parent = questFrame

			local progress = getObjectiveProgress(activeQuest, objective)
			local target = getObjectiveTarget(objective)
			local completed = progress.completed == true or (tonumber(progress.progress) or 0) >= target
			local label = getTextLabel(step, "QuestProgress")
			if label then
				label.RichText = true
				local text = string.format(
					" %s: %s/%s",
					tostring(objective.description or "Objective"),
					formatWholeNumber(progress.progress),
					formatWholeNumber(target)
				)
				label.Text = if completed then string.format("<s>%s</s>", text) else text
			end

			local checked = step:FindFirstChild("Checked")
			local unchecked = step:FindFirstChild("Unchecked")
			if checked and checked:IsA("GuiObject") then
				checked.Visible = completed
			end
			if unchecked and unchecked:IsA("GuiObject") then
				unchecked.Visible = not completed
			end
		end
	end
end

function QuestController:_setRowProgress(row: GuiObject, entry: any)
	local definition = getDefinition(entry)
	local totalParts = getPartCount(definition)
	local completedParts = getCompletedParts(entry)
	local progress = if totalParts > 0 then math.clamp(completedParts / totalParts, 0, 1) else 0
	local progressTextValue = string.format("%s / %s", formatWholeNumber(completedParts), formatWholeNumber(totalParts))

	if isDailyQuest(entry) then
		local activeQuest = getActiveQuest(entry)
		local totalObjectiveProgress = 0
		local totalObjectiveTarget = 0
		for _, objective in ipairs(getCurrentObjectives(entry)) do
			local target = getObjectiveTarget(objective)
			local objectiveProgress = getObjectiveProgress(activeQuest, objective)
			totalObjectiveProgress += math.clamp(math.floor(tonumber(objectiveProgress.progress) or 0), 0, target)
			totalObjectiveTarget += target
		end
		if totalObjectiveTarget > 0 then
			if entry.isCompleted == true or entry.isClaimed == true then
				totalObjectiveProgress = totalObjectiveTarget
			end
			progress = math.clamp(totalObjectiveProgress / totalObjectiveTarget, 0, 1)
			progressTextValue = string.format(
				"%s / %s",
				formatWholeNumber(totalObjectiveProgress),
				formatWholeNumber(totalObjectiveTarget)
			)
		end
	end

	local bar = row:FindFirstChild("Bar", true)
	if bar and bar:IsA("GuiObject") then
		bar.Size = UDim2.new(progress, 0, bar.Size.Y.Scale, bar.Size.Y.Offset)
	end

	local progressText = getTextLabel(row, "ProgressText")
	if progressText then
		progressText.Text = progressTextValue
	end
end

function QuestController:_setRowSelected(row: GuiObject, selected: boolean)
	local stroke = row:FindFirstChildWhichIsA("UIStroke")
	if stroke then
		stroke.Transparency = if selected then 0 else 0.45
	end
end

function QuestController:_populateQuestRow(row: GuiObject, entry: any, layoutOrder: number)
	local definition = getDefinition(entry) or {}
	row.LayoutOrder = layoutOrder
	row.Visible = true

	local questName = getTextLabel(row, "QuestName")
	if questName then
		questName.Text = tostring(definition.displayName or definition.id or "Quest")
	end

	self:_setRowProgress(row, entry)
	self:_setRowSelected(row, self._selectedQuestId == definition.id)

	local isReadyToClaim = entry.isActive == true
		and typeof(entry.activeQuest) == "table"
		and entry.activeQuest.status == "readyToClaim"
	local isCompleted = entry.isCompleted == true
		or entry.isClaimed == true
		or (typeof(entry.activeQuest) == "table" and entry.activeQuest.status == "claimed")

	local checked = row:FindFirstChild("Checked")
	local unchecked = row:FindFirstChild("Unchecked")
	if checked and checked:IsA("GuiObject") then
		checked.Visible = isCompleted or isReadyToClaim
	end
	if unchecked and unchecked:IsA("GuiObject") then
		unchecked.Visible = not (isCompleted or isReadyToClaim)
	end

	local completedText = row:FindFirstChild("CompletedText")
	if completedText and completedText:IsA("GuiObject") then
		completedText.Visible = entry.isClaimed == true
	end

	local selectButton = row:FindFirstChild("Select")
	if selectButton and selectButton:IsA("GuiButton") then
		UIController:CreateButton(selectButton, function()
			self._selectedQuestId = definition.id
			self:_syncModal()
		end)
	end

	local claimButton = row:FindFirstChild("ClaimButton")
	if claimButton and claimButton:IsA("GuiButton") then
		claimButton.Visible = isReadyToClaim
		setButtonText(claimButton, if isOnboardingLesson(definition) then "Claim Reward" else "Claim")
		if isReadyToClaim then
			local selectZIndex = if selectButton and selectButton:IsA("GuiObject") then selectButton.ZIndex else row.ZIndex
			raiseGuiTree(claimButton, selectZIndex + 1)
		end
		UIController:CreateButton(claimButton, function()
			if typeof(definition.id) == "string" then
				self:_claimQuest(definition.id)
			end
		end)
	end
end

function QuestController:_syncRewards(entry: any)
	local ui = self:_ensureUi()
	clearGeneratedChildren(ui.boardRewards, REWARD_ROW_PREFIX)
	hideTemplate(ui.boardRewardTemplate)

	local definition = getDefinition(entry)
	local rewardRows = formatRewardRows(if definition then definition.rewards else nil)
	if ui.boardRewardEmpty and ui.boardRewardEmpty:IsA("GuiObject") then
		ui.boardRewardEmpty.Visible = #rewardRows == 0
	end

	for index, rewardText in ipairs(rewardRows) do
		local row = ui.boardRewardTemplate:Clone()
		row.Name = string.format("%s%03d", REWARD_ROW_PREFIX, index)
		row.LayoutOrder = index
		row.Visible = true
		local label = getTextLabel(row, "RewardName")
		if label then
			label.Text = rewardText
		end
		row.Parent = ui.boardRewards
	end
end

function QuestController:_syncDetail()
	local ui = self:_ensureUi()
	local entry = self:_findQuestEntry(self._selectedQuestId)
	if not entry then
		local visibleEntries = self:_getVisibleQuestEntries()
		entry = visibleEntries[1]
		local definition = getDefinition(entry)
		self._selectedQuestId = if definition then definition.id else nil
	end
	if not entry then
		ui.boardQuestName.Text = "Quest Board"
		ui.boardDescription.Text = "No quests are available right now."
		ui.startButton.Visible = false
		if ui.inProgressLabel then
			ui.inProgressLabel.Visible = false
		end
		self:_syncRewards(nil)
		return
	end

	local definition = getDefinition(entry) or {}
	ui.boardQuestName.Text = tostring(definition.displayName or definition.id or "Quest")
	ui.boardDescription.Text = tostring(definition.description or getQuestDescription(entry))
	self:_syncRewards(entry)

	local activeQuest = getActiveQuest(entry)
	local isReadyToClaim = entry.isActive == true and typeof(activeQuest) == "table" and activeQuest.status == "readyToClaim"
	local isClaimed = typeof(activeQuest) == "table" and activeQuest.status == "claimed"
	local isActive = entry.isActive == true and not isReadyToClaim and not isClaimed
	local canStart = entry.isAvailable == true and entry.isActive ~= true

	ui.startButton.Visible = canStart
	ui.startButton.Active = canStart
	if canStart then
		setButtonText(ui.startButton, if isOnboardingLesson(definition) then "Claim" else "Start Quest")
	end

	if ui.inProgressLabel then
		ui.inProgressLabel.Visible = not canStart
		if isReadyToClaim then
			ui.inProgressLabel.Text = "- Ready to Claim -"
		elseif isActive then
			ui.inProgressLabel.Text = "- Quest in Progress -"
		elseif entry.isClaimed == true or entry.isCompleted == true then
			ui.inProgressLabel.Text = "- Quest Complete -"
		else
			ui.inProgressLabel.Text = tostring(entry.lockReason or "- Quest Unavailable -")
		end
	end
end

function QuestController:_syncModal()
	local ui = self:_ensureUi()
	clearGeneratedChildren(ui.list, MODAL_ROW_PREFIX)
	hideTemplate(ui.normalRowTemplate)
	hideTemplate(ui.claimRowTemplate)

	local entries = self:_getVisibleQuestEntries()
	local selectedIsVisible = false
	for _, entry in ipairs(entries) do
		local definition = getDefinition(entry)
		if definition and definition.id == self._selectedQuestId then
			selectedIsVisible = true
			break
		end
	end
	if not selectedIsVisible then
		local firstDefinition = getDefinition(entries[1])
		self._selectedQuestId = if firstDefinition then firstDefinition.id else nil
	end

	for index, entry in ipairs(entries) do
		local activeQuest = getActiveQuest(entry)
		local isReadyToClaim = entry.isActive == true
			and typeof(activeQuest) == "table"
			and activeQuest.status == "readyToClaim"
		local template = if isReadyToClaim then ui.claimRowTemplate else ui.normalRowTemplate
		local row = template:Clone()
		row.Name = string.format("%s%03d", MODAL_ROW_PREFIX, index)
		self:_populateQuestRow(row, entry, index)
		row.Parent = ui.list
	end

	local mainCount = 0
	local dailyCount = 0
	for _, entry in ipairs(self:_getQuestEntries()) do
		if not isBoardVisibleQuest(entry) then
			continue
		end

		local activeQuest = getActiveQuest(entry)
		local hasAttention = entry.isAvailable == true
			or (entry.isActive == true and typeof(activeQuest) == "table" and activeQuest.status == "readyToClaim")
		if hasAttention then
			if isMainQuest(entry) then
				mainCount += 1
			else
				dailyCount += 1
			end
		end
	end
	setTabCount(ui.questsNotification, mainCount)
	setTabCount(ui.dailyNotification, dailyCount)
	self:_syncDetail()
end

function QuestController:_syncUi()
	if not self._ui then
		self:_ensureUi()
	end
	self:_syncHud()
	self:_syncModal()
end

function QuestController:_bindUi()
	local ui = self:_ensureUi()
	UIController:CreateButton(ui.tabQuestsButton, function()
		self._filter = "main"
		self:_syncModal()
	end)
	UIController:CreateButton(ui.tabDailyButton, function()
		self._filter = "daily"
		self:_syncModal()
	end)
	UIController:CreateButton(ui.startButton, function()
		local entry = self:_findQuestEntry(self._selectedQuestId)
		local definition = getDefinition(entry)
		if definition and typeof(definition.id) == "string" then
			self:_acceptQuest(definition.id)
		end
	end)
end

function QuestController:_bindQuestBoardPrompt()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player?)
		if player and player ~= LOCAL_PLAYER then
			return
		end
		if isQuestBoardPrompt(prompt) then
			self:OpenQuestBoard()
		end
	end)
end

function QuestController:OpenQuestBoard()
	local opened = FrameController:OpenFrame(WINDOW_NAME)
	if opened == true then
		QuestBoardOnboardingGuideController.MarkQuestBoardOpened()
	end
	self:_markQuestBoardOpened()
	self:_requestState(false)
end

function QuestController:OnStart()
	if self._started then
		return
	end
	self._started = true

	self:_ensureUi()
	self:_bindUi()
	self:_bindQuestBoardPrompt()
	self:_ensureRemotes()
	if self._remotes then
		self._remotes.questUpdated.OnClientEvent:Connect(function(state: any, message: string?)
			self:_applyState(state)
			if typeof(message) == "string" and message ~= "" then
				showNotification(message, "good")
			end
		end)
	end

	task.defer(function()
		self:_requestState(false)
	end)
end

return QuestController
