local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DialogueDefinitions = require(ReplicatedStorage.Shared.Config.DialogueDefinitions)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local Schema = require(ReplicatedStorage.Lists.Schema)
local ViewportModelRenderer = require(ReplicatedStorage.Shared.UI.ViewportModelRenderer)

local DataController = require(script.Parent.DataController)
local FrameController = require(script.Parent.FrameController)
local MerchantPresentationController = require(script.Parent.MerchantPresentationController)
local UIController = require(script.Parent.UIController)

local LOCAL_PLAYER = Players.LocalPlayer
local DIALOGUE_PANEL_NAME = "Dialogue"
local DEFAULT_SHOP_FRAME_NAME = "ShopUI"
local FRAME_CLOSE_DELAY = FrameController.CloseTween.Time
local PANEL_CLOSE_DELAY = 0.12
local TYPEWRITER_GRAPHEMES_PER_SECOND = 45

type DialogueDefinition = DialogueDefinitions.DialogueDefinition
type DialogueNode = DialogueDefinitions.DialogueNode
type DialogueChoice = DialogueDefinitions.DialogueChoice

type ResolvedChoice = {
	choice: DialogueChoice,
	disabled: boolean,
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

local MONEY_KEY = Schema.Money and Schema.Money.key or nil
local VIP_OWNED_KEY = Schema.VipOwned and Schema.VipOwned.key or nil

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
}

local function getPlayerGui(): PlayerGui
	return LOCAL_PLAYER:WaitForChild("PlayerGui")
end

local function toBoolean(value: any): boolean
	return value == true
end

local function getNumericValue(value: any): number
	return tonumber(value) or 0
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

local ConditionPredicates: { [string]: (context: { [string]: any }?) -> boolean } = {
	vipOwned = function()
		if not VIP_OWNED_KEY then
			return false
		end

		return toBoolean(DataController:Get(VIP_OWNED_KEY))
	end,
	richEnoughForSecretStock = function()
		if not MONEY_KEY then
			return false
		end

		return getNumericValue(DataController:Get(MONEY_KEY)) >= 100000
	end,
}

function DialogueController:_getGuiController()
	if self._guiController then
		return self._guiController
	end

	local mainInterface = self:_ensureUi().mainInterface
	local guiControllerModule = mainInterface:WaitForChild("GUIController", 30)
	self._guiController = require(guiControllerModule)
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
	local context = self._context
	if context then
		local speakerModel = context.speakerModel
		if typeof(speakerModel) == "Instance" and speakerModel:IsA("Model") then
			return speakerModel
		end
	end

	return BodyPartsCatalog.GetDefaultBaseRig()
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
	return DialogueDefinitions.Get(dialogueId)
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
	if not conditionIds or #conditionIds == 0 then
		return true
	end

	for _, conditionId in ipairs(conditionIds) do
		local predicate = ConditionPredicates[conditionId]
		if not predicate then
			warn(string.format("[DialogueController] Unknown condition '%s'.", conditionId))
			return false
		end

		local ok, result = pcall(predicate, self._context)
		if not ok then
			warn(string.format("[DialogueController] Condition '%s' failed: %s", conditionId, tostring(result)))
			return false
		end

		if result ~= true then
			return false
		end
	end

	return true
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
		warn(string.format("[DialogueController] Node '%s' was not found for dialogue '%s'.", nodeId, dialogueId))
		return false
	end

	self._currentNodeId = nodeId
	self:_renderNode(node)
	return true
end

function DialogueController:_closeDialogue(afterClose: (() -> ())?)
	local guiController = self:_getGuiController()
	self:_stopTyping()
	self._activeDialogueId = nil
	self._currentNodeId = nil
	self._context = nil
	self:_destroyRenderedButtons()
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

function DialogueController:_beginDialogue(dialogueId: string)
	if not self:_setCurrentNode((self:_getDialogueDefinition(dialogueId) :: DialogueDefinition).rootNodeId) then
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

	if action.type == "gotoNode" then
		local nextNodeId = action.nextNodeId or choice.nextNodeId
		if not nextNodeId then
			warn(string.format("[DialogueController] Choice '%s' is missing a nextNodeId.", choice.id))
			return false
		end

		return self:_setCurrentNode(nextNodeId)
	end

	if action.type == "closeDialogue" then
		self:_closeDialogue()
		return true
	end

	if action.type == "openFrame" or action.type == "openShopFrame" then
		local context = self._context
		local frameName = action.frameName
			or (context and context.dialogueFrameName)
			or (if action.type == "openShopFrame" then DEFAULT_SHOP_FRAME_NAME else nil)

		if not frameName then
			warn(string.format("[DialogueController] Choice '%s' is missing a frameName.", choice.id))
			return false
		end

		self:_closeDialogue(function()
			local shouldUseMerchantPresentation = context ~= nil
				and typeof(context.dialogueFrameName) == "string"
				and context.dialogueFrameName ~= ""
			if shouldUseMerchantPresentation then
				local opened = MerchantPresentationController:Open(frameName, {
					cameraPart = if context and context.dialogueCameraPart and context.dialogueCameraPart:IsA("BasePart")
						then context.dialogueCameraPart
						else nil,
					sourceInstance = if context and typeof(context.sourceInstance) == "Instance" then context.sourceInstance else nil,
					interactionType = if context and typeof(context.interactionType) == "string" then context.interactionType else nil,
					speakerModel = if context and typeof(context.speakerModel) == "Instance" and context.speakerModel:IsA("Model")
						then context.speakerModel
						else nil,
				})
				if opened then
					return
				end
			end

			FrameController:OpenFrame(frameName)
		end)
		return true
	end

	warn(string.format("[DialogueController] Unsupported action type '%s'.", tostring(action.type)))
	return false
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

	local function rerenderIfOpen()
		if self:IsOpen() then
			local currentNode = self:_getCurrentNode()
			if currentNode then
				if self._isTyping then
					return
				end

				self:_destroyRenderedButtons()
				self:_renderChoices(currentNode)
			end
		end
	end

	table.insert(self._connections, DataController.DataReceived:Connect(rerenderIfOpen))
	table.insert(self._connections, DataController.DataUpdated:Connect(rerenderIfOpen))
end

function DialogueController.StartDialogue(dialogueId: string, context: { [string]: any }?): boolean
	DialogueController:OnStart()

	local definition = DialogueController:_getDialogueDefinition(dialogueId)
	if not definition then
		warn(string.format("[DialogueController] Dialogue '%s' was not found.", dialogueId))
		return false
	end

	DialogueController._activeDialogueId = dialogueId
	DialogueController._context = deepCopyContext(context)
	DialogueController:_capturePanelVisibility()

	local openFrameName = FrameController:GetOpenFrame()
	if openFrameName then
		FrameController:CloseFrame()
		task.delay(FRAME_CLOSE_DELAY, function()
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

return DialogueController
