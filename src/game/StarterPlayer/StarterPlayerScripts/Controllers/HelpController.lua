local Players = game:GetService("Players")

local FrameController = require(script.Parent.FrameController)
local UIController = require(script.Parent.UIController)

local LOCAL_PLAYER = Players.LocalPlayer
local WINDOW_NAME = "Help"
local ACTIVE_PAGE_COUNT = 2
local RUNTIME_UNUSED_PAGES_NAME = "UnusedPagesRuntime"

local PLACEHOLDER_PAGES = {
	{
		title = "How to Play",
		body = table.concat({
			"Roll for body parts and chase rarer pieces as you go.",
			"Equip better parts to improve your setup and earn more passive money over time.",
			"Use those upgrades to roll faster, get luckier, and push into stronger progression.",
		}, "\n\n"),
	},
	{
		title = "Useful Windows",
		body = table.concat({
			"Inventory lets you review and equip the parts you already own.",
			"Index tracks discovered bundles so you can see what you still need to find.",
			"Auto Sell helps you clear lower-value drops while you hunt for better pieces.",
			"More help pages will be added here later.",
		}, "\n\n"),
	},
}

type PageEntry = {
	root: Frame,
	titleLabel: TextLabel,
	bodyLabel: TextLabel,
}

local HelpController = {}

local function compareGuiPosition(a: GuiObject, b: GuiObject): boolean
	if a.Position.Y.Scale ~= b.Position.Y.Scale then
		return a.Position.Y.Scale < b.Position.Y.Scale
	end

	if a.Position.Y.Offset ~= b.Position.Y.Offset then
		return a.Position.Y.Offset < b.Position.Y.Offset
	end

	if a.Position.X.Scale ~= b.Position.X.Scale then
		return a.Position.X.Scale < b.Position.X.Scale
	end

	return a.Position.X.Offset < b.Position.X.Offset
end

local function getTextLabelsInDisplayOrder(pageFrame: Frame): { TextLabel }
	local labels = {}

	for _, child in ipairs(pageFrame:GetChildren()) do
		if child:IsA("TextLabel") then
			table.insert(labels, child)
		end
	end

	table.sort(labels, compareGuiPosition)
	return labels
end

function HelpController:_ensureState()
	if self._started then
		return
	end

	self._started = true
	self._root = nil
	self._currentPage = 1
	self._pages = {} :: { PageEntry }
	self._ui = {
		openButton = nil :: GuiButton?,
		leftButton = nil :: GuiButton?,
		rightButton = nil :: GuiButton?,
		pageNumberLabel = nil :: TextLabel?,
		pageLayout = nil :: UIPageLayout?,
	}
end

function HelpController:_setLabelLayout(titleLabel: TextLabel, bodyLabel: TextLabel)
	titleLabel.TextScaled = false
	titleLabel.TextSize = 28
	titleLabel.TextWrapped = true
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	titleLabel.TextYAlignment = Enum.TextYAlignment.Center

	bodyLabel.TextScaled = false
	bodyLabel.TextSize = 20
	bodyLabel.TextWrapped = true
	bodyLabel.TextXAlignment = Enum.TextXAlignment.Center
	bodyLabel.TextYAlignment = Enum.TextYAlignment.Top
	bodyLabel.Size = UDim2.fromScale(0.72, 0.5)
	bodyLabel.Position = UDim2.fromScale(0.14, 0.28)
end

function HelpController:_applyPlaceholderCopy()
	for index, pageData in ipairs(PLACEHOLDER_PAGES) do
		local page = self._pages[index]
		if not page then
			continue
		end

		self:_setLabelLayout(page.titleLabel, page.bodyLabel)
		page.titleLabel.Text = pageData.title
		page.bodyLabel.Text = pageData.body
	end
end

function HelpController:_syncPageNumber()
	local pageNumberLabel = self._ui.pageNumberLabel
	if not pageNumberLabel then
		return
	end

	pageNumberLabel.Text = string.format("Page %d", self._currentPage)
end

function HelpController:_syncArrowState()
	local leftButton = self._ui.leftButton
	local rightButton = self._ui.rightButton
	local pageCount = #self._pages

	if leftButton then
		leftButton.Active = self._currentPage > 1
		leftButton.AutoButtonColor = false
	end

	if rightButton then
		rightButton.Active = self._currentPage < pageCount
		rightButton.AutoButtonColor = false
	end
end

function HelpController:_showPage(pageNumber: number)
	local pageCount = #self._pages
	if pageCount == 0 then
		return
	end

	local nextPage = math.clamp(pageNumber, 1, pageCount)
	local entry = self._pages[nextPage]
	local pageLayout = self._ui.pageLayout

	self._currentPage = nextPage

	for index, page in ipairs(self._pages) do
		page.root.Visible = index == nextPage
	end

	if pageLayout then
		pageLayout:JumpTo(entry.root)
	end

	self:_syncPageNumber()
	self:_syncArrowState()
end

function HelpController:_moveUnusedPages(helpRoot: GuiObject, pagesContainer: GuiObject, activeFrames: { Frame })
	local runtimeUnusedPages = helpRoot:FindFirstChild(RUNTIME_UNUSED_PAGES_NAME)
	if runtimeUnusedPages and not runtimeUnusedPages:IsA("Folder") then
		runtimeUnusedPages:Destroy()
		runtimeUnusedPages = nil
	end

	if not runtimeUnusedPages then
		runtimeUnusedPages = Instance.new("Folder")
		runtimeUnusedPages.Name = RUNTIME_UNUSED_PAGES_NAME
		runtimeUnusedPages.Parent = helpRoot
	end

	local activeLookup = {}
	for _, frame in ipairs(activeFrames) do
		activeLookup[frame] = true
	end

	for _, child in ipairs(pagesContainer:GetChildren()) do
		if child:IsA("Frame") and not activeLookup[child] then
			child.Visible = false
			child.Parent = runtimeUnusedPages
		end
	end
end

function HelpController:_preparePages(helpRoot: GuiObject, pagesContainer: GuiObject)
	local legacyPaginator = pagesContainer:FindFirstChild("LocalScript")
	if legacyPaginator then
		legacyPaginator:Destroy()
	end

	local pageLayout = pagesContainer:FindFirstChildWhichIsA("UIPageLayout")
	if pageLayout then
		pageLayout.Circular = false
		pageLayout.GamepadInputEnabled = false
		pageLayout.ScrollWheelInputEnabled = false
		pageLayout.TouchInputEnabled = false
	end

	local pageFrames = {}
	for _, child in ipairs(pagesContainer:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(pageFrames, child)
		end
	end

	local activeFrames = {}
	for index = 1, math.min(ACTIVE_PAGE_COUNT, #pageFrames) do
		table.insert(activeFrames, pageFrames[index])
	end

	self:_moveUnusedPages(helpRoot, pagesContainer, activeFrames)
	self._pages = {}

	for _, pageFrame in ipairs(activeFrames) do
		local labels = getTextLabelsInDisplayOrder(pageFrame)
		local titleLabel = labels[1]
		local bodyLabel = labels[2]

		if not (titleLabel and bodyLabel) then
			error("Help page is missing placeholder title/body labels.")
		end

		table.insert(self._pages, {
			root = pageFrame,
			titleLabel = titleLabel,
			bodyLabel = bodyLabel,
		})
	end

	self._ui.pageLayout = pageLayout
	self:_applyPlaceholderCopy()
	self:_showPage(1)
end

function HelpController:_cacheUi(playerGui: PlayerGui)
	local mainInterface = playerGui:WaitForChild("MainInterface", 30)
	local modalRoot = playerGui:WaitForChild("ModalRoot", 30)
	if not (mainInterface and mainInterface:IsA("ScreenGui")) then
		error("PlayerGui.MainInterface is missing.")
	end
	if not (modalRoot and modalRoot:IsA("ScreenGui")) then
		error("PlayerGui.ModalRoot is missing.")
	end

	local helpRoot = modalRoot:WaitForChild(WINDOW_NAME, 30)
	local openButton = mainInterface:WaitForChild("Main", 30):WaitForChild("ExtraButtons", 30):WaitForChild(WINDOW_NAME, 30)
	local leftButton = helpRoot:WaitForChild("Left", 30)
	local rightButton = helpRoot:WaitForChild("Right", 30)
	local pageNumberLabel = helpRoot:WaitForChild("PageNumber", 30)
	local pagesContainer = helpRoot:WaitForChild("Pages", 30)

	if not (
		helpRoot:IsA("GuiObject")
		and openButton:IsA("GuiButton")
		and leftButton:IsA("GuiButton")
		and rightButton:IsA("GuiButton")
		and pageNumberLabel:IsA("TextLabel")
		and pagesContainer:IsA("GuiObject")
	) then
		error("Help UI hierarchy is missing required instances.")
	end

	self._root = helpRoot
	self._ui = {
		openButton = openButton,
		leftButton = leftButton,
		rightButton = rightButton,
		pageNumberLabel = pageNumberLabel,
		pageLayout = nil,
	}

	self:_preparePages(helpRoot, pagesContainer)
end

function HelpController:_bindOpenButton(openButton: GuiButton)
	UIController:CreateButton(openButton, function()
		local wasOpen = FrameController:IsOpen(WINDOW_NAME)
		if not wasOpen then
			self:_showPage(1)
		end

		FrameController:ToggleFrame(WINDOW_NAME)
	end)
end

function HelpController:_bindPageButtons()
	local leftButton = self._ui.leftButton
	local rightButton = self._ui.rightButton
	if not (leftButton and rightButton) then
		return
	end

	UIController:CreateButton(leftButton, function()
		self:_showPage(self._currentPage - 1)
	end)

	UIController:CreateButton(rightButton, function()
		self:_showPage(self._currentPage + 1)
	end)
end

function HelpController:OnStart()
	self:_ensureState()

	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	self:_cacheUi(playerGui)
	self:_bindOpenButton(self._ui.openButton)
	self:_bindPageButtons()
	self:_showPage(1)
end

return HelpController
