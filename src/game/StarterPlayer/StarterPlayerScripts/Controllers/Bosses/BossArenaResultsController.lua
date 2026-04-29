local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BossQueueConstants = require(ReplicatedStorage.Shared.BossQueue.Constants)
local CraftingMaterialConfig = require(ReplicatedStorage.Shared.Config.CraftingMaterialConfig)
local NumberFormatter = require(ReplicatedStorage.Shared.Formatting.NumberFormatter)
local Notify = require(ReplicatedStorage.Shared.UI.Notify)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local LOCAL_PLAYER = Players.LocalPlayer
local REMOTES_FOLDER_NAME = "Remotes"
local BOSS_ARENA_FOLDER_NAME = "BossArena"
local GET_RESULTS_STATE_REMOTE_NAME = "GetResultsState"
local RESULTS_STATE_CHANGED_REMOTE_NAME = "ResultsStateChanged"
local SET_REPLAY_READY_REMOTE_NAME = "SetReplayReady"
local RETURN_TO_LOBBY_REMOTE_NAME = "ReturnToBossLobby"
local ACTIVE_PROFILE_ID = "boss_arena"
local GENERATED_REWARD_ATTRIBUTE = "BossResultsGeneratedReward"
local TEMPLATE_SUFFIX = "Template"
local DEFEAT_COLOR = Color3.fromRGB(255, 67, 67)

type BossResultRewardEntry = {
	kind: string?,
	pieceId: string?,
	displayName: string,
	setId: string?,
	displayRarity: string?,
	displayOddsDenominator: number?,
	isBossPart: boolean?,
	materialId: string?,
	amount: number?,
	dropTier: string?,
	chance: number?,
	displayColor: Color3?,
}

type BossResultsState = {
	outcome: string,
	bossId: string,
	damagePercent: number,
	startsAtServerTime: number,
	endsAtServerTime: number,
	durationSeconds: number,
	rewards: { BossResultRewardEntry },
	rewardStatus: string,
	readyCount: number,
	capacity: number,
	isReplayReady: boolean,
}

type ResultsRemotes = {
	getState: RemoteFunction,
	stateChanged: RemoteEvent,
	setReplayReady: RemoteFunction,
	returnToLobby: RemoteFunction,
}

type TextLabelState = {
	text: string,
	textColor3: Color3,
	gradientEnabledByChild: { [Instance]: boolean },
}

type ResultsUi = {
	root: Frame,
	rewardsList: ScrollingFrame,
	outcomeLabel: TextLabel,
	damageLabel: TextLabel,
	playAgainButton: GuiButton,
	returnButton: GuiButton,
	votesLabel: TextLabel,
	templatesByRarity: { [string]: Frame },
	defaultOutcomeLabelState: TextLabelState,
	defaultDamageLabelState: TextLabelState,
}

local BossArenaResultsController = {
	_started = false,
	_remotes = nil :: ResultsRemotes?,
	_ui = nil :: ResultsUi?,
	_stateChangedConnection = nil :: RBXScriptConnection?,
	_playAgainConnection = nil :: RBXScriptConnection?,
	_returnConnection = nil :: RBXScriptConnection?,
	_requestInFlight = false,
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
end

local function warnWithPrefix(message: string)
	Logger.Warn(string.format("[BossArenaResultsController] %s", message))
end

local function normalizeRarity(value: any): string
	if typeof(value) ~= "string" or value == "" then
		return "Basic"
	end

	return value
end

local function materialTierToTemplateRarity(dropTier: any): string
	if dropTier == "Epic" then
		return "Elite"
	end
	if dropTier == "Rare" then
		return "Prime"
	end
	return "Basic"
end

local function isMaterialReward(reward: BossResultRewardEntry): boolean
	return reward.kind == "material" or typeof(reward.materialId) == "string"
end

local function getRewardTemplateRarity(reward: BossResultRewardEntry): string
	if isMaterialReward(reward) then
		return materialTierToTemplateRarity(reward.dropTier)
	end

	return normalizeRarity(reward.displayRarity)
end

local function escapeRichText(value: any): string
	local text = tostring(value or "")
	text = string.gsub(text, "&", "&amp;")
	text = string.gsub(text, "<", "&lt;")
	text = string.gsub(text, ">", "&gt;")
	return text
end

local function toRichTextColor(color: Color3): string
	return string.format(
		"rgb(%d,%d,%d)",
		math.round(color.R * 255),
		math.round(color.G * 255),
		math.round(color.B * 255)
	)
end

local function captureTextLabelState(label: TextLabel): TextLabelState
	local gradientEnabledByChild = {}
	for _, child in ipairs(label:GetChildren()) do
		if child:IsA("UIGradient") then
			gradientEnabledByChild[child] = child.Enabled
		end
	end

	return {
		text = label.Text,
		textColor3 = label.TextColor3,
		gradientEnabledByChild = gradientEnabledByChild,
	}
end

local function restoreTextLabelState(label: TextLabel, state: TextLabelState)
	label.Text = state.text
	label.TextColor3 = state.textColor3
	for child, enabled in pairs(state.gradientEnabledByChild) do
		if child.Parent == label and child:IsA("UIGradient") then
			child.Enabled = enabled
		end
	end
end

local function setTextLabelFlatColor(label: TextLabel, color: Color3)
	label.TextColor3 = color
	for _, child in ipairs(label:GetChildren()) do
		if child:IsA("UIGradient") then
			child.Enabled = false
		end
	end
end

local function getRarityFromTemplateName(name: string): string?
	if not string.match(name, TEMPLATE_SUFFIX .. "$") then
		return nil
	end

	local rarity = string.sub(name, 1, #name - #TEMPLATE_SUFFIX)
	if rarity == "" then
		return nil
	end

	return rarity
end

local function parseTemplateRichTextColor(template: Frame): string
	local description = template:FindFirstChild("Description")
	if description and description:IsA("TextLabel") then
		local rgb = string.match(description.Text, "rgb%(([%d%s,]+)%)")
		if rgb and rgb ~= "" then
			return rgb
		end
	end

	return "255,255,255"
end

local function formatRewardDescription(template: Frame, reward: BossResultRewardEntry): string
	if isMaterialReward(reward) then
		local materialConfig = if typeof(reward.materialId) == "string" then CraftingMaterialConfig.Get(reward.materialId) else nil
		local displayName = escapeRichText(reward.displayName or (materialConfig and materialConfig.label) or "Material")
		local amount = math.max(1, math.floor(tonumber(reward.amount) or 1))
		local displayColor = Color3.new(1, 1, 1)
		if typeof(reward.displayColor) == "Color3" then
			displayColor = reward.displayColor
		elseif materialConfig then
			displayColor = materialConfig.displayColor
		end

		return string.format(
			"<font color=\"%s\">%s</font> x%s",
			toRichTextColor(displayColor),
			displayName,
			NumberFormatter.Format(amount)
		)
	end

	local colorText = parseTemplateRichTextColor(template)
	local displayName = escapeRichText(reward.displayName)
	local oddsDenominator = math.max(1, math.floor(tonumber(reward.displayOddsDenominator) or 1))
	return string.format(
		"<font color=\"rgb(%s)\">%s</font> (1 in %s)",
		colorText,
		displayName,
		tostring(oddsDenominator)
	)
end

local function resolveHeaderLabels(root: Frame): (TextLabel, TextLabel)
	local labels = {}
	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("TextLabel") and child.Name == "Header" then
			table.insert(labels, child)
		end
	end

	table.sort(labels, function(a, b)
		return a.Position.Y.Scale < b.Position.Y.Scale
	end)

	local outcomeLabel = labels[1]
	local damageLabel = labels[2]
	if not (outcomeLabel and damageLabel) then
		Logger.Error("[BossArenaResultsController] Results outcome and damage labels are missing.", 0)
	end

	return outcomeLabel, damageLabel
end

local function collectTemplatesByRarity(rewardsList: ScrollingFrame): { [string]: Frame }
	local templatesByRarity = {}
	for _, child in ipairs(rewardsList:GetChildren()) do
		if child:IsA("Frame") then
			local rarity = getRarityFromTemplateName(child.Name)
			if rarity then
				templatesByRarity[rarity] = templatesByRarity[rarity] or child
				child.Visible = false
			end
		end
	end

	return templatesByRarity
end

local function normalizeResultsState(state: any): BossResultsState?
	if typeof(state) ~= "table" then
		return nil
	end

	local bossId = if typeof(state.bossId) == "string" and state.bossId ~= "" then state.bossId else nil
	local outcome = if state.outcome == "victory" then "victory" elseif state.outcome == "defeat" then "defeat" else nil
	local startsAtServerTime = tonumber(state.startsAtServerTime)
	local endsAtServerTime = tonumber(state.endsAtServerTime)
	if bossId == nil or outcome == nil or startsAtServerTime == nil or endsAtServerTime == nil then
		return nil
	end

	return {
		outcome = outcome,
		bossId = bossId,
		damagePercent = math.clamp(tonumber(state.damagePercent) or 0, 0, 100),
		startsAtServerTime = startsAtServerTime,
		endsAtServerTime = endsAtServerTime,
		durationSeconds = math.max(0, math.floor(tonumber(state.durationSeconds) or 0)),
		rewards = if typeof(state.rewards) == "table" then state.rewards else {},
		rewardStatus = if state.rewardStatus == "pending"
			then "pending"
			elseif state.rewardStatus == "failed" then "failed"
			else "ready",
		readyCount = math.max(0, math.floor(tonumber(state.readyCount) or 0)),
		capacity = math.max(1, math.floor(tonumber(state.capacity) or BossQueueConstants.QueueCapacity)),
		isReplayReady = state.isReplayReady == true,
	}
end

function BossArenaResultsController:_getPlayerGui(): PlayerGui
	return LOCAL_PLAYER:WaitForChild("PlayerGui")
end

function BossArenaResultsController:_ensureRemotes(): ResultsRemotes?
	if self._remotes then
		return self._remotes
	end

	local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, 30)
	if not (remotesFolder and remotesFolder:IsA("Folder")) then
		warnWithPrefix("ReplicatedStorage.Remotes is missing.")
		return nil
	end

	local bossArenaFolder = remotesFolder:WaitForChild(BOSS_ARENA_FOLDER_NAME, 30)
	if not (bossArenaFolder and bossArenaFolder:IsA("Folder")) then
		warnWithPrefix("ReplicatedStorage.Remotes.BossArena is missing.")
		return nil
	end

	local getState = bossArenaFolder:WaitForChild(GET_RESULTS_STATE_REMOTE_NAME, 30)
	local stateChanged = bossArenaFolder:WaitForChild(RESULTS_STATE_CHANGED_REMOTE_NAME, 30)
	local setReplayReady = bossArenaFolder:WaitForChild(SET_REPLAY_READY_REMOTE_NAME, 30)
	local returnToLobby = bossArenaFolder:WaitForChild(RETURN_TO_LOBBY_REMOTE_NAME, 30)

	if not (getState and getState:IsA("RemoteFunction")) then
		warnWithPrefix("BossArena.GetResultsState is missing.")
		return nil
	end
	if not (stateChanged and stateChanged:IsA("RemoteEvent")) then
		warnWithPrefix("BossArena.ResultsStateChanged is missing.")
		return nil
	end
	if not (setReplayReady and setReplayReady:IsA("RemoteFunction")) then
		warnWithPrefix("BossArena.SetReplayReady is missing.")
		return nil
	end
	if not (returnToLobby and returnToLobby:IsA("RemoteFunction")) then
		warnWithPrefix("BossArena.ReturnToBossLobby is missing.")
		return nil
	end

	self._remotes = {
		getState = getState,
		stateChanged = stateChanged,
		setReplayReady = setReplayReady,
		returnToLobby = returnToLobby,
	}

	return self._remotes
end

function BossArenaResultsController:_ensureUi(): ResultsUi
	if self._ui and self._ui.root.Parent ~= nil then
		return self._ui
	end

	local playerGui = self:_getPlayerGui()
	local mainInterface = playerGui:WaitForChild("MainInterface", 30)
	if not (mainInterface and mainInterface:IsA("ScreenGui")) then
		Logger.Error("[BossArenaResultsController] PlayerGui.MainInterface is missing.", 0)
	end

	local root = mainInterface:WaitForChild("Results", 30)
	if not (root and root:IsA("Frame")) then
		Logger.Error("[BossArenaResultsController] PlayerGui.MainInterface.Results is missing.", 0)
	end

	local rewardsList = root:WaitForChild("RewardsList", 30)
	if not (rewardsList and rewardsList:IsA("ScrollingFrame")) then
		Logger.Error("[BossArenaResultsController] Results.RewardsList is missing.", 0)
	end

	local buttons = root:WaitForChild("Buttons", 30)
	local playAgainButton = buttons and buttons:FindFirstChild("PlayAgain")
	local returnButton = buttons and buttons:FindFirstChild("Return")
	local votesLabel = playAgainButton and playAgainButton:FindFirstChild("Votes")
	if not (playAgainButton and playAgainButton:IsA("GuiButton")) then
		Logger.Error("[BossArenaResultsController] Results.Buttons.PlayAgain is missing.", 0)
	end
	if not (returnButton and returnButton:IsA("GuiButton")) then
		Logger.Error("[BossArenaResultsController] Results.Buttons.Return is missing.", 0)
	end
	if not (votesLabel and votesLabel:IsA("TextLabel")) then
		Logger.Error("[BossArenaResultsController] Results.Buttons.PlayAgain.Votes is missing.", 0)
	end

	local outcomeLabel, damageLabel = resolveHeaderLabels(root)
	local ui = {
		root = root,
		rewardsList = rewardsList,
		outcomeLabel = outcomeLabel,
		damageLabel = damageLabel,
		playAgainButton = playAgainButton,
		returnButton = returnButton,
		votesLabel = votesLabel,
		templatesByRarity = collectTemplatesByRarity(rewardsList),
		defaultOutcomeLabelState = captureTextLabelState(outcomeLabel),
		defaultDamageLabelState = captureTextLabelState(damageLabel),
	}

	root.Visible = false
	self._ui = ui
	return ui
end

function BossArenaResultsController:_clearGeneratedRewards()
	local ui = self:_ensureUi()
	for _, child in ipairs(ui.rewardsList:GetChildren()) do
		if child:GetAttribute(GENERATED_REWARD_ATTRIBUTE) == true then
			child:Destroy()
		end
	end
end

function BossArenaResultsController:_renderRewards(rewards: { BossResultRewardEntry })
	local ui = self:_ensureUi()
	self:_clearGeneratedRewards()

	for index, reward in ipairs(rewards) do
		if typeof(reward) ~= "table" then
			continue
		end

		local rarity = getRewardTemplateRarity(reward)
		local template = ui.templatesByRarity[rarity] or ui.templatesByRarity.Basic
		if template == nil then
			continue
		end

		local row = template:Clone()
		row.Name = string.format("GeneratedReward_%02d", index)
		row:SetAttribute(GENERATED_REWARD_ATTRIBUTE, true)
		row.LayoutOrder = index
		row.Visible = true

		local leftLabel = row:FindFirstChild("Left")
		if leftLabel and leftLabel:IsA("TextLabel") then
			leftLabel.Text = if isMaterialReward(reward) then "Crafting Material Acquired" else "Body Part Acquired"
		end

		local description = row:FindFirstChild("Description")
		if description and description:IsA("TextLabel") then
			description.RichText = true
			description.Text = formatRewardDescription(template, reward)
		end

		row.Parent = ui.rewardsList
	end
end

function BossArenaResultsController:_renderState(state: BossResultsState?)
	local ui = self:_ensureUi()
	local normalizedState = normalizeResultsState(state)
	if normalizedState == nil then
		ui.root.Visible = false
		self:_clearGeneratedRewards()
		restoreTextLabelState(ui.outcomeLabel, ui.defaultOutcomeLabelState)
		restoreTextLabelState(ui.damageLabel, ui.defaultDamageLabelState)
		ui.votesLabel.Text = BossQueueConstants.FormatOccupancyText(0)
		return
	end

	if normalizedState.outcome == "victory" then
		restoreTextLabelState(ui.outcomeLabel, ui.defaultOutcomeLabelState)
		ui.outcomeLabel.Text = string.format("You defeated %s!", normalizedState.bossId)
		self:_renderRewards(normalizedState.rewards)
	else
		restoreTextLabelState(ui.outcomeLabel, ui.defaultOutcomeLabelState)
		ui.outcomeLabel.Text = "You were defeated"
		setTextLabelFlatColor(ui.outcomeLabel, DEFEAT_COLOR)
		self:_clearGeneratedRewards()
	end

	ui.damageLabel.Text = string.format("You dealt %d%% damage", math.round(normalizedState.damagePercent))
	ui.votesLabel.Text = string.format(
		"%d/%d",
		math.clamp(normalizedState.readyCount, 0, normalizedState.capacity),
		normalizedState.capacity
	)
	ui.playAgainButton.Active = normalizedState.isReplayReady ~= true
	ui.playAgainButton.AutoButtonColor = normalizedState.isReplayReady ~= true
	ui.root.Visible = true
end

function BossArenaResultsController:_invokeResponse(remote: RemoteFunction, ...): any?
	local ok, response = pcall(function(...)
		return remote:InvokeServer(...)
	end, ...)

	if ok then
		return response
	end

	warnWithPrefix(string.format("Remote %s failed: %s", remote.Name, tostring(response)))
	Notify.Show("The boss results request failed.", {
		title = "Boss",
		channel = "system",
	})
	return nil
end

function BossArenaResultsController:_requestReplayReady()
	if self._requestInFlight then
		return
	end

	local remotes = self:_ensureRemotes()
	if not remotes then
		return
	end

	self._requestInFlight = true
	local response = self:_invokeResponse(remotes.setReplayReady, true)
	self._requestInFlight = false

	if typeof(response) == "table" then
		self:_renderState(response.state)
		if response.ok ~= true and typeof(response.message) == "string" then
			Notify.Show(response.message, {
				title = "Boss",
				channel = "system",
			})
		end
	end
end

function BossArenaResultsController:_requestReturnToLobby()
	if self._requestInFlight then
		return
	end

	local remotes = self:_ensureRemotes()
	if not remotes then
		return
	end

	self._requestInFlight = true
	local response = self:_invokeResponse(remotes.returnToLobby)
	self._requestInFlight = false

	if typeof(response) == "table" then
		self:_renderState(response.state)
		if response.ok ~= true and typeof(response.message) == "string" then
			Notify.Show(response.message, {
				title = "Boss",
				channel = "system",
			})
		end
	end
end

function BossArenaResultsController:_bindUi()
	local ui = self:_ensureUi()

	if self._playAgainConnection then
		self._playAgainConnection:Disconnect()
	end
	if self._returnConnection then
		self._returnConnection:Disconnect()
	end

	self._playAgainConnection = ui.playAgainButton.MouseButton1Click:Connect(function()
		self:_requestReplayReady()
	end)
	self._returnConnection = ui.returnButton.MouseButton1Click:Connect(function()
		self:_requestReturnToLobby()
	end)
end

function BossArenaResultsController:_bindRemotes()
	local remotes = self:_ensureRemotes()
	if not remotes then
		return
	end

	if self._stateChangedConnection then
		self._stateChangedConnection:Disconnect()
	end

	self._stateChangedConnection = remotes.stateChanged.OnClientEvent:Connect(function(state: BossResultsState?)
		self:_renderState(state)
	end)
end

function BossArenaResultsController:_refreshState()
	local remotes = self:_ensureRemotes()
	if not remotes then
		self:_renderState(nil)
		return
	end

	self:_renderState(self:_invokeResponse(remotes.getState))
end

function BossArenaResultsController:OnStart()
	if self._started then
		return
	end
	self._started = true

	if RunService:IsClient() ~= true or not isEnabledForPlace() then
		return
	end

	self:_ensureUi()
	self:_bindUi()
	self:_bindRemotes()
	self:_refreshState()
end

return BossArenaResultsController
