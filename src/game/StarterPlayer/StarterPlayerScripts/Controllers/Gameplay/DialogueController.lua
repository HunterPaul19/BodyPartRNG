local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DialogueDefinitions = require(ReplicatedStorage.Shared.Config.DialogueDefinitions)
local DefinitionUtil = require(ReplicatedStorage.Shared.Gameplay.Dialogue.DefinitionUtil)
local DialogueRegistry = require(ReplicatedStorage.Shared.Gameplay.Dialogue.Registry)
local RemoteFunctionTimeout = require(ReplicatedStorage.Shared.Remotes.RemoteFunctionTimeout)
local ViewportModelRenderer = require(ReplicatedStorage.Shared.UI.ViewportModelRenderer)

local MainInterfaceController = require(script.Parent.MainInterfaceController)
local DailyChestController = require(script.Parent.DailyChestController)
local UIController = require(script.Parent.UIController)

local LOCAL_PLAYER = Players.LocalPlayer
local DIALOGUE_PANEL_NAME = "Dialogue"
local REMOTE_INVOKE_TIMEOUT_SECONDS = 8
local PANEL_CLOSE_DELAY = 0.12
local TYPEWRITER_GRAPHEMES_PER_SECOND = 45
local POSITIVE_CHOICE_COLOR = Color3.fromRGB(113, 230, 139)
local REMOTES_FOLDER_NAME = "Remotes"
local DIALOGUE_REMOTES_FOLDER_NAME = "Dialogue"
local RUN_ACTION_REMOTE_NAME = "RunAction"
local DIALOGUE_ID_ATTRIBUTE = "DialogueId"
local DIALOGUE_NODE_ID_ATTRIBUTE = "DialogueNodeId"
local DIALOGUE_CHOICE_ID_ATTRIBUTE = "DialogueChoiceId"
local DIALOGUE_ACTION_TYPE_ATTRIBUTE = "DialogueActionType"
local DIALOGUE_FRAME_NAME_ATTRIBUTE = "DialogueFrameName"

type DialogueDefinition = DialogueDefinitions.DialogueDefinition
type DialogueNode = DialogueDefinitions.DialogueNode
type DialogueChoice = DialogueDefinitions.DialogueChoice

type ResolvedChoice = {
	choice: DialogueChoice,
	disabled: boolean,
	button: GuiButton?,
}

type DialogueUiRefs = {
	mainInterface: ScreenGui,
	dialogueRoot: Frame,
	itemName: TextLabel,
	itemDescLabel: TextLabel,
	selection: Frame,
	scrollingFrame: ScrollingFrame,
	buttonTemplate: ImageButton,
	layout: UIListLayout,
	viewportFrame: ViewportFrame?,
	messageUi: GuiObject?,
}

type PanelVisibilitySnapshot = {
	panels: { [string]: boolean },
	blackTransparency: number,
	blurSize: number,
}

local DialogueController = {
	_started = false,
	_ui = nil :: DialogueUiRefs?,
	_guiController = nil,
	_activeDialogueId = nil :: string?,
	_currentNodeId = nil :: string?,
	_context = nil :: { [string]: any }?,
	_isTyping = false,
	_activeRevealToken = 0,
	_savedPanelVisibility = nil :: PanelVisibilitySnapshot?,
	_resolvedChoicesById = {} :: { [string]: ResolvedChoice },
	_renderedButtons = {} :: { GuiButton },
	_connections = {} :: { RBXScriptConnection },
	_typingConnection = nil :: RBXScriptConnection?,
	_runActionRemote = nil :: RemoteFunction?,
	_beforeOpenHook = nil :: (() -> number?)?,
	_portraitResolver = nil :: ((context: { [string]: any }?) -> Model?)?,
	_refreshSignals = {} :: { any },
}

local function getPlayerGui(): PlayerGui
	return LOCAL_PLAYER:WaitForChild("PlayerGui")
end

local function deepCopyContext(context: { [string]: any }?): { [string]: any }
	local copy = {}
	if typeof(context) ~= "table" then
		return copy
	end

	for key, value in pairs(context) do
		copy[key] = value
	end

	return copy
end

local function getGraphemeCount(text: string): number
	local length = utf8.len(text)
	if length then
		return length
	end

	return string.len(text)
end

local function getActionPayload(choice: DialogueChoice): { [string]: any }?
	local action = choice.action
	if typeof(action) ~= "table" or typeof(action.payload) ~= "table" then
		return nil
	end

	return action.payload
end

local function getVisibleSizedGuiObject(target: Instance?): GuiObject?
	if not (target and target:IsA("GuiObject")) then
		return nil
	end

	if target.Parent ~= nil and target.Visible == true and target.AbsoluteSize.X > 0 and target.AbsoluteSize.Y > 0 then
		return target
	end

	return nil
end

local function getChoiceTutorialTarget(button: GuiButton?): GuiObject?
	local buttonTarget = getVisibleSizedGuiObject(button)
	if buttonTarget then
		return buttonTarget
	end

	if button then
		return getVisibleSizedGuiObject(button:FindFirstChild("Content"))
	end

	return nil
end

local function clearDialogueRootAttributes(dialogueRoot: Instance?)
	if not dialogueRoot then
		return
	end

	dialogueRoot:SetAttribute(DIALOGUE_ID_ATTRIBUTE, nil)
	dialogueRoot:SetAttribute(DIALOGUE_NODE_ID_ATTRIBUTE, nil)
end

local function setChoiceAttributes(button: GuiButton, choice: DialogueChoice)
	local action = choice.action
	button:SetAttribute(DIALOGUE_CHOICE_ID_ATTRIBUTE, choice.id)
	button:SetAttribute(DIALOGUE_ACTION_TYPE_ATTRIBUTE, if action then action.type else nil)
	button:SetAttribute(DIALOGUE_FRAME_NAME_ATTRIBUTE, if action then action.frameName else nil)
end

local function stylePositiveChoiceButton(button: ImageButton)
	button.ImageColor3 = POSITIVE_CHOICE_COLOR

	for _, childName in ipairs({ "Cover", "Cover2", "Rays" }) do
		local child = button:FindFirstChild(childName)
		if child and child:IsA("ImageLabel") then
			child.ImageColor3 = POSITIVE_CHOICE_COLOR
		end
	end
end

function DialogueController:_getGuiController()
	self._guiController = MainInterfaceController
	return self._guiController
end

function DialogueController:_capturePanelVisibility()
	local guiController = self:_getGuiController()
	self._savedPanelVisibility = guiController:GetPanelVisibilitySnapshot()
end

function DialogueController:_restorePanelVisibility()
	local snapshot = self._savedPanelVisibility
	self._savedPanelVisibility = nil

	if not snapshot then
		return
	end

	local guiController = self:_getGuiController()
	guiController:RestorePanelVisibility(snapshot, {
		[DIALOGUE_PANEL_NAME] = true,
	})
end

function DialogueController:_updateCanvasSize()
	local ui = self:_ensureUi()
	ui.scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, ui.layout.AbsoluteContentSize.Y)
end

function DialogueController:_ensureUi(): DialogueUiRefs
	if self._ui and self._ui.dialogueRoot.Parent then
		return self._ui
	end

	local playerGui = getPlayerGui()
	local mainInterface = playerGui:WaitForChild("MainInterface", 30)
	assert(mainInterface and mainInterface:IsA("ScreenGui"), "PlayerGui.MainInterface is missing.")

	local dialogueRoot = mainInterface:WaitForChild("DialogueUI", 30)
	assert(dialogueRoot and dialogueRoot:IsA("Frame"), "PlayerGui.MainInterface.DialogueUI is missing.")
	dialogueRoot.Active = true

	local itemName = dialogueRoot:WaitForChild("ItemName", 30)
	assert(itemName and itemName:IsA("TextLabel"), "DialogueUI.ItemName is missing.")

	local itemDesc = dialogueRoot:WaitForChild("ItemDesc", 30)
	assert(itemDesc and itemDesc:IsA("Frame"), "DialogueUI.ItemDesc is missing.")

	local itemDescLabel = itemDesc:WaitForChild("TextLabel", 30)
	assert(itemDescLabel and itemDescLabel:IsA("TextLabel"), "DialogueUI.ItemDesc.TextLabel is missing.")
	itemDescLabel.MaxVisibleGraphemes = -1

	local selection = dialogueRoot:WaitForChild("Selection", 30)
	assert(selection and selection:IsA("Frame"), "DialogueUI.Selection is missing.")

	local scrollingFrame = selection:WaitForChild("ScrollingFrame", 30)
	assert(scrollingFrame and scrollingFrame:IsA("ScrollingFrame"), "DialogueUI.Selection.ScrollingFrame is missing.")

	local layout = scrollingFrame:FindFirstChildWhichIsA("UIListLayout")
	assert(layout, "DialogueUI.Selection.ScrollingFrame.UIListLayout is missing.")

	local buttonTemplate = nil :: ImageButton?
	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child:IsA("ImageButton") then
			if not buttonTemplate then
				buttonTemplate = child
			end
			child.Visible = false
			child.Active = false
			child.AutoButtonColor = false
		end
	end

	assert(buttonTemplate, "DialogueUI.Selection.ScrollingFrame needs at least one Button template.")

	local viewportFrame = dialogueRoot:FindFirstChild("ViewportFrame")
	if viewportFrame and not viewportFrame:IsA("ViewportFrame") then
		viewportFrame = nil
	end

	local messageUi = dialogueRoot:FindFirstChild("MessageUI")
	if messageUi and messageUi:IsA("GuiObject") then
		messageUi.Visible = false
	end

	self._ui = {
		mainInterface = mainInterface,
		dialogueRoot = dialogueRoot,
		itemName = itemName,
		itemDescLabel = itemDescLabel,
		selection = selection,
		scrollingFrame = scrollingFrame,
		buttonTemplate = buttonTemplate,
		layout = layout,
		viewportFrame = viewportFrame,
		messageUi = messageUi,
	}

	clearDialogueRootAttributes(dialogueRoot)
	self:_updateCanvasSize()

	return self._ui
end

function DialogueController:_clearPortrait()
	local ui = self:_ensureUi()
	local viewportFrame = ui.viewportFrame
	if not viewportFrame then
		return
	end

	ViewportModelRenderer.Clear(viewportFrame)
	viewportFrame.Visible = false
end

function DialogueController:_resolvePortraitModel(): Model?
	local resolver = self._portraitResolver
	if resolver then
		local ok, result = pcall(resolver, self._context)
		if ok and typeof(result) == "Instance" and result:IsA("Model") then
			return result
		end
	end

	return nil
end

function DialogueController:_renderPortrait()
	local ui = self:_ensureUi()
	local viewportFrame = ui.viewportFrame
	if not viewportFrame then
		return
	end

	local portraitModel = self:_resolvePortraitModel()
	local rendered = ViewportModelRenderer.RenderDialoguePortrait(viewportFrame, portraitModel)
	viewportFrame.Visible = rendered
	if not rendered then
		ViewportModelRenderer.Clear(viewportFrame)
	end
end

function DialogueController:_getDialogueDefinition(dialogueId: string): DialogueDefinition?
	return DefinitionUtil.GetDefinition(dialogueId)
end

function DialogueController:_getCurrentNode(): DialogueNode?
	local dialogueId = self._activeDialogueId
	local nodeId = self._currentNodeId
	if not (dialogueId and nodeId) then
		return nil
	end

	local definition = self:_getDialogueDefinition(dialogueId)
	if not definition then
		return nil
	end

	return definition.nodesById[nodeId]
end

function DialogueController:_evaluateConditions(conditionIds: { string }?): boolean
	return DialogueRegistry.EvaluateConditions(self:_buildSession(), conditionIds)
end

function DialogueController:_destroyRenderedButtons()
	for _, button in ipairs(self._renderedButtons) do
		if button.Parent then
			button:Destroy()
		end
	end

	table.clear(self._renderedButtons)
	table.clear(self._resolvedChoicesById)
end

function DialogueController:_nextRevealToken(): number
	self._activeRevealToken += 1
	return self._activeRevealToken
end

function DialogueController:_stopTyping()
	self._isTyping = false
	self._activeRevealToken += 1

	if self._ui and self._ui.itemDescLabel.Parent then
		self._ui.itemDescLabel.MaxVisibleGraphemes = -1
	end
end

function DialogueController:_renderChoices(node: DialogueNode)
	local layoutOrder = 1
	for _, choice in ipairs(node.choices) do
		local conditionsMet = self:_evaluateConditions(choice.conditionIds)
		local behavior = choice.conditionBehavior or "hide"

		if conditionsMet then
			self:_createChoiceButton(choice, false, layoutOrder)
			layoutOrder += 1
		elseif behavior == "disable" then
			self:_createChoiceButton(choice, true, layoutOrder)
			layoutOrder += 1
		end
	end

	if layoutOrder == 1 then
		self:_renderFallbackChoice()
	end

	self:_updateCanvasSize()
end

function DialogueController:_completeReveal(node: DialogueNode, revealToken: number): boolean
	if self._activeRevealToken ~= revealToken then
		return false
	end

	local ui = self:_ensureUi()
	self._isTyping = false
	self._activeRevealToken += 1
	ui.itemDescLabel.MaxVisibleGraphemes = -1

	if self._currentNodeId ~= node.id then
		return false
	end

	self:_renderChoices(node)
	return true
end

function DialogueController:_startReveal(node: DialogueNode)
	local ui = self:_ensureUi()
	local totalGraphemes = getGraphemeCount(node.text)
	local revealToken = self:_nextRevealToken()

	self._isTyping = totalGraphemes > 0
	ui.itemDescLabel.MaxVisibleGraphemes = if totalGraphemes > 0 then 0 else -1

	if totalGraphemes <= 0 then
		self:_completeReveal(node, revealToken)
		return
	end

	task.spawn(function()
		local startTime = os.clock()

		while self._activeRevealToken == revealToken do
			local elapsed = os.clock() - startTime
			local visibleCount = math.clamp(math.floor(elapsed * TYPEWRITER_GRAPHEMES_PER_SECOND), 0, totalGraphemes)
			ui.itemDescLabel.MaxVisibleGraphemes = visibleCount

			if visibleCount >= totalGraphemes then
				break
			end

			RunService.RenderStepped:Wait()
		end

		self:_completeReveal(node, revealToken)
	end)
end

function DialogueController:_skipTyping(): boolean
	if not self._isTyping then
		return false
	end

	local currentNode = self:_getCurrentNode()
	if not currentNode then
		return false
	end

	return self:_completeReveal(currentNode, self._activeRevealToken)
end

function DialogueController:_styleDisabledButton(button: ImageButton, textLabel: TextLabel, choice: DialogueChoice)
	button.Active = false
	button.AutoButtonColor = false
	button.Selectable = false
	button.ImageTransparency = 0.35
	textLabel.TextTransparency = 0.15
	textLabel.Text = choice.disabledText or choice.text
end

function DialogueController:_createChoiceButton(choice: DialogueChoice, disabled: boolean, layoutOrder: number)
	local ui = self:_ensureUi()
	local button = ui.buttonTemplate:Clone()
	local content = button:FindFirstChild("Content")
	assert(content and content:IsA("TextLabel"), "Dialogue choice button template is missing Content.")

	button.Name = string.format("Choice_%s", choice.id)
	button.Visible = true
	button.LayoutOrder = layoutOrder
	button.Active = not disabled
	button.AutoButtonColor = false
	button.Selectable = not disabled
	button.ImageTransparency = 0
	content.TextTransparency = 0
	content.Text = choice.text
	setChoiceAttributes(button, choice)

	local payload = getActionPayload(choice)
	if payload and payload.style == "positive" then
		stylePositiveChoiceButton(button)
	end

	button.Parent = ui.scrollingFrame

	if disabled then
		self:_styleDisabledButton(button, content, choice)
	else
		UIController:CreateButton(button, function()
			DialogueController.ChooseChoice(choice.id)
		end)
	end

	table.insert(self._renderedButtons, button)
	self._resolvedChoicesById[choice.id] = {
		choice = choice,
		disabled = disabled,
		button = button,
	}
end

function DialogueController:_renderFallbackChoice()
	local fallbackChoice: DialogueChoice = {
		id = "__close",
		text = "Goodbye.",
		action = {
			type = "closeDialogue",
		},
	}

	self:_createChoiceButton(fallbackChoice, false, 1)
end

function DialogueController:_renderNode(node: DialogueNode)
	local ui = self:_ensureUi()
	self:_stopTyping()
	ui.itemName.Text = node.speakerName
	ui.itemName.Visible = node.speakerName ~= ""
	ui.itemDescLabel.Text = node.text
	ui.dialogueRoot:SetAttribute(DIALOGUE_ID_ATTRIBUTE, self._activeDialogueId)
	ui.dialogueRoot:SetAttribute(DIALOGUE_NODE_ID_ATTRIBUTE, node.id)
	self:_destroyRenderedButtons()
	ui.itemDescLabel.MaxVisibleGraphemes = 0
	self:_updateCanvasSize()
	self:_startReveal(node)
end

function DialogueController:_setCurrentNode(nodeId: string): boolean
	local dialogueId = self._activeDialogueId
	if not dialogueId then
		return false
	end

	local definition = self:_getDialogueDefinition(dialogueId)
	if not definition then
		return false
	end

	local node = definition.nodesById[nodeId]
	if not node then
		Logger.Warn(string.format("[DialogueController] Node '%s' was not found for dialogue '%s'.", nodeId, dialogueId))
		return false
	end

	self._currentNodeId = nodeId
	self:_renderNode(node)
	return true
end

function DialogueController:_resolveInitialNodeId(definition: DialogueDefinition): string
	for _, rule in ipairs(definition.initialNodeRules or {}) do
		local nodeId = if typeof(rule) == "table" then rule.nodeId else nil
		if typeof(nodeId) ~= "string" or nodeId == "" then
			continue
		end
		if definition.nodesById[nodeId] == nil then
			Logger.Warn(string.format(
				"[DialogueController] Initial node '%s' was not found for dialogue '%s'.",
				nodeId,
				definition.id
			))
			continue
		end
		if self:_evaluateConditions(rule.conditionIds) then
			return nodeId
		end
	end

	return definition.rootNodeId
end

function DialogueController:_closeDialogue(afterClose: (() -> ())?)
	local guiController = self:_getGuiController()
	self:_stopTyping()
	self._activeDialogueId = nil
	self._currentNodeId = nil
	self._context = nil
	self:_destroyRenderedButtons()
	if self._ui then
		clearDialogueRootAttributes(self._ui.dialogueRoot)
	end
	self:_clearPortrait()

	guiController:ClosePanel(DIALOGUE_PANEL_NAME, true)

	local afterCloseCallback = afterClose
	if afterClose then
		task.delay(PANEL_CLOSE_DELAY, function()
			self:_restorePanelVisibility()
			afterCloseCallback()
		end)
		return
	end

	task.delay(PANEL_CLOSE_DELAY, function()
		self:_restorePanelVisibility()
	end)
end

function DialogueController:_openDialoguePanel()
	local guiController = self:_getGuiController()
	guiController:OpenExclusive(DIALOGUE_PANEL_NAME)
end

function DialogueController:_ensureRunActionRemote(): RemoteFunction?
	if self._runActionRemote and self._runActionRemote.Parent then
		return self._runActionRemote
	end

	local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME) or ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, 5)
	if not (remotesFolder and remotesFolder:IsA("Folder")) then
		return nil
	end

	local dialogueFolder = remotesFolder:FindFirstChild(DIALOGUE_REMOTES_FOLDER_NAME)
		or remotesFolder:WaitForChild(DIALOGUE_REMOTES_FOLDER_NAME, 5)
	if not (dialogueFolder and dialogueFolder:IsA("Folder")) then
		return nil
	end

	local remote = dialogueFolder:FindFirstChild(RUN_ACTION_REMOTE_NAME)
	if not (remote and remote:IsA("RemoteFunction")) then
		return nil
	end

	self._runActionRemote = remote
	return remote
end

function DialogueController:_buildSafeActionContext(): { [string]: any }
	local context = self._context
	if typeof(context) ~= "table" then
		return {}
	end

	local safeContext = {}
	if typeof(context.interactionType) == "string" then
		safeContext.interactionType = context.interactionType
	end
	if typeof(context.dialogueFrameName) == "string" then
		safeContext.dialogueFrameName = context.dialogueFrameName
	end
	if typeof(context.sourceInstance) == "Instance" then
		safeContext.sourcePath = context.sourceInstance:GetFullName()
	end

	return safeContext
end

function DialogueController:_runServerAction(choice: DialogueChoice, action: DialogueRegistry.DialogueAction): boolean
	local dialogueId = self._activeDialogueId
	local nodeId = self._currentNodeId
	if not (dialogueId and nodeId) then
		return false
	end

	local remote = self:_ensureRunActionRemote()
	if not remote then
		Logger.Warn(string.format("[DialogueController] Unsupported action type '%s'.", tostring(action.type)))
		return false
	end

	local ok, result, timedOut = RemoteFunctionTimeout.Invoke(remote, {
		dialogueId = dialogueId,
		nodeId = nodeId,
		choiceId = choice.id,
		context = self:_buildSafeActionContext(),
	}, REMOTE_INVOKE_TIMEOUT_SECONDS)

	if not ok then
		local reason = if timedOut then "timed out" else "failed"
		Logger.Warn(string.format("[DialogueController] Server action '%s' %s: %s", tostring(action.type), reason, tostring(result)))
		return false
	end
	if typeof(result) ~= "table" or result.ok ~= true then
		local message = if typeof(result) == "table" then result.message else nil
		Logger.Warn(string.format("[DialogueController] Server action '%s' rejected: %s", tostring(action.type), tostring(message)))
		return false
	end

	local data = if typeof(result.data) == "table" then result.data else {}
	local rewardPresentation = if typeof(data.rewardPresentation) == "table" then data.rewardPresentation else {}
	local dailyChests = if typeof(rewardPresentation.dailyChests) == "table" then rewardPresentation.dailyChests else nil
	if data.closeDialogue == true then
		if dailyChests and #dailyChests > 0 then
			self:_closeDialogue(function()
				DailyChestController.OpenChestPackages(dailyChests)
			end)
		else
			self:_closeDialogue()
		end
		return true
	end
	if typeof(data.nextNodeId) == "string" and data.nextNodeId ~= "" then
		local changedNode = self:_setCurrentNode(data.nextNodeId)
		if changedNode and dailyChests and #dailyChests > 0 then
			task.spawn(function()
				DailyChestController.OpenChestPackages(dailyChests)
			end)
		end
		return changedNode
	end

	if dailyChests and #dailyChests > 0 then
		task.spawn(function()
			DailyChestController.OpenChestPackages(dailyChests)
		end)
	end

	return true
end

function DialogueController:_buildSession(): DialogueRegistry.DialogueSession
	return {
		dialogueId = self._activeDialogueId,
		nodeId = self._currentNodeId,
		context = self._context,
		setCurrentNode = function(nodeId: string)
			return self:_setCurrentNode(nodeId)
		end,
		closeDialogue = function(afterClose: (() -> ())?)
			self:_closeDialogue(afterClose)
		end,
		runServerAction = function(choice: DialogueChoice, action: DialogueRegistry.DialogueAction)
			return self:_runServerAction(choice, action)
		end,
	}
end

function DialogueController:_rerenderChoicesIfOpen()
	if not self:IsOpen() then
		return
	end

	local currentNode = self:_getCurrentNode()
	if not currentNode then
		return
	end
	if self._isTyping then
		return
	end

	self:_destroyRenderedButtons()
	self:_renderChoices(currentNode)
end

function DialogueController:_beginDialogue(dialogueId: string)
	local definition = self:_getDialogueDefinition(dialogueId)
	if not definition then
		return false
	end

	if not self:_setCurrentNode(self:_resolveInitialNodeId(definition)) then
		return false
	end

	self:_renderPortrait()
	self:_openDialoguePanel()
	return true
end

function DialogueController:_performAction(choice: DialogueChoice)
	local action = choice.action

	if not action and choice.nextNodeId then
		return self:_setCurrentNode(choice.nextNodeId)
	end

	if not action then
		return false
	end

	return DialogueRegistry.RunAction(self:_buildSession(), choice, action)
end

function DialogueController:OnStart()
	if self._started then
		return
	end

	self._started = true
	self:_ensureUi()
	self:_clearPortrait()

	table.insert(self._connections, self._ui.layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		self:_updateCanvasSize()
	end))

	self._typingConnection = self._ui.dialogueRoot.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self:_skipTyping()
		end
	end)
	table.insert(self._connections, self._typingConnection)

	for _, signal in ipairs(self._refreshSignals) do
		table.insert(self._connections, signal:Connect(function()
			self:_rerenderChoicesIfOpen()
		end))
	end
end

function DialogueController.StartDialogue(dialogueId: string, context: { [string]: any }?): boolean
	DialogueController:OnStart()

	local definition = DialogueController:_getDialogueDefinition(dialogueId)
	if not definition then
		Logger.Warn(string.format("[DialogueController] Dialogue '%s' was not found.", dialogueId))
		return false
	end

	DialogueController._activeDialogueId = dialogueId
	DialogueController._context = deepCopyContext(context)
	DialogueController:_capturePanelVisibility()

	local beforeOpenHook = DialogueController._beforeOpenHook
	local openDelay = if beforeOpenHook then beforeOpenHook() else 0
	if typeof(openDelay) == "number" and openDelay > 0 then
		task.delay(openDelay, function()
			if DialogueController._activeDialogueId == dialogueId then
				DialogueController:_beginDialogue(dialogueId)
			end
		end)
		return true
	end

	return DialogueController:_beginDialogue(dialogueId)
end

function DialogueController.ChooseChoice(choiceId: string): boolean
	local resolved = DialogueController._resolvedChoicesById[choiceId]
	if not resolved then
		return false
	end

	if resolved.disabled then
		return false
	end

	return DialogueController:_performAction(resolved.choice)
end

function DialogueController.CloseDialogue()
	if not DialogueController.IsOpen() then
		return false
	end

	DialogueController:_closeDialogue()
	return true
end

function DialogueController.IsOpen(): boolean
	return DialogueController._activeDialogueId ~= nil and DialogueController._currentNodeId ~= nil
end

function DialogueController.IsDialogueOpen(dialogueId: string): boolean
	return DialogueController._activeDialogueId == dialogueId and DialogueController._currentNodeId ~= nil
end

function DialogueController.SetBeforeOpenHook(hook: (() -> number?)?)
	if hook ~= nil and type(hook) ~= "function" then
		error("DialogueController before-open hook must be a function or nil.", 2)
	end

	DialogueController._beforeOpenHook = hook
end

function DialogueController.SetPortraitResolver(resolver: ((context: { [string]: any }?) -> Model?)?)
	if resolver ~= nil and type(resolver) ~= "function" then
		error("DialogueController portrait resolver must be a function or nil.", 2)
	end

	DialogueController._portraitResolver = resolver
end

function DialogueController.RegisterRefreshSignal(signal: any)
	if typeof(signal) ~= "RBXScriptSignal" and (typeof(signal) ~= "table" or type(signal.Connect) ~= "function") then
		error("DialogueController refresh signal must provide Connect.", 2)
	end

	table.insert(DialogueController._refreshSignals, signal)
	if DialogueController._started then
		table.insert(DialogueController._connections, signal:Connect(function()
			DialogueController:_rerenderChoicesIfOpen()
		end))
	end
end

function DialogueController:GetTutorialTarget(targetId: string): GuiObject?
	if typeof(targetId) ~= "string" or targetId == "" or not self:IsOpen() then
		return nil
	end

	for _, resolved in pairs(self._resolvedChoicesById) do
		local payload = getActionPayload(resolved.choice)
		if not resolved.disabled and payload and payload.tutorialTargetId == targetId then
			return getChoiceTutorialTarget(resolved.button)
		end
	end

	return nil
end

return DialogueController
