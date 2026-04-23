local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Notify = require(ReplicatedStorage.Shared.UI.Notify)
local AchievementState = require(ReplicatedStorage.Shared.Titles.AchievementState)
local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)
local LocalizationKeys = require(ReplicatedStorage.Shared.Localization.Keys)
local TranslationHelper = require(ReplicatedStorage.Shared.Localization.TranslationHelper)
local TitleUtil = require(ReplicatedStorage.Shared.Titles.TitleUtil)
local ToggleSoundUtil = require(ReplicatedStorage.Shared.Audio.ToggleSoundUtil)
local DataController = require(script.Parent.DataController)
local FrameController = require(script.Parent.FrameController)
local UIController = require(script.Parent.UIController)

local LOCAL_PLAYER = Players.LocalPlayer
local WINDOW_NAME = "Titles"
local EQUIPPED_TITLE_KEY = "equippedTitleId"
local ACHIEVEMENTS_KEY = "achievements"
local REMOTES_FOLDER_NAME = "Remotes"
local TITLES_REMOTES_FOLDER_NAME = "Titles"
local SET_EQUIPPED_TITLE_REMOTE_NAME = "SetEquippedTitle"

local TitleController = {}

local function getAchievementsState()
	return AchievementState.Normalize(DataController:Get(ACHIEVEMENTS_KEY))
end

local function getEquippedTitleId(): string?
	return TitleUtil.NormalizeEquippedTitleId(DataController:Get(EQUIPPED_TITLE_KEY))
end

local function titleMatchesSearch(title, searchText: string): boolean
	if searchText == "" then
		return true
	end

	local haystack = string.lower(string.format("%s %s %s", title.label, title.description, title.howToGet))
	return string.find(haystack, searchText, 1, true) ~= nil
end

function TitleController:_ensureState()
	if self._started then
		return
	end

	self._started = true
	self._root = nil
	self._template = nil
	self._scrollingFrame = nil
	self._ui = {}
	self._remote = nil
	self._searchText = ""
	self._selectedTitleId = nil
	self._emptyStateLabel = nil
	self._playerGui = nil
	self._openButtonBound = false
	self._fullUiReady = false
	self._dataBindingsReady = false
end

function TitleController:_getRemote(): RemoteFunction?
	if self._remote and self._remote.Parent then
		return self._remote
	end

	local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, 10)
	if not remotesFolder then
		return nil
	end

	local titlesFolder = remotesFolder:WaitForChild(TITLES_REMOTES_FOLDER_NAME, 10)
	if not titlesFolder then
		return nil
	end

	local remote = titlesFolder:WaitForChild(SET_EQUIPPED_TITLE_REMOTE_NAME, 10)
	if remote and remote:IsA("RemoteFunction") then
		self._remote = remote
		return remote
	end

	return nil
end

function TitleController:_getUnlockedTitles(): { TitleConfig.TitleConfigEntry }
	local searchText = string.lower(self._searchText or "")
	local titles = {}

	for _, title in ipairs(TitleUtil.GetUnlockedTitles(getAchievementsState())) do
		if titleMatchesSearch(title, searchText) then
			table.insert(titles, title)
		end
	end

	return titles
end

function TitleController:_ensureSelection(titles: { TitleConfig.TitleConfigEntry })
	if self._selectedTitleId then
		for _, title in ipairs(titles) do
			if title.id == self._selectedTitleId then
				return
			end
		end
	end

	self._selectedTitleId = if titles[1] then titles[1].id else nil
end

function TitleController:_getSelectedTitle()
	local selectedTitleId = self._selectedTitleId
	if not selectedTitleId then
		return nil
	end

	return TitleConfig.Get(selectedTitleId)
end

function TitleController:_ensureEmptyStateLabel(parent: GuiObject): TextLabel
	if self._emptyStateLabel and self._emptyStateLabel.Parent == parent then
		return self._emptyStateLabel
	end

	local label = Instance.new("TextLabel")
	label.Name = "EmptyStateLabel"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -24, 0, 72)
	label.Position = UDim2.new(0, 12, 0.5, -36)
	label.Font = Enum.Font.GothamSemibold
	label.TextColor3 = Color3.fromRGB(226, 231, 255)
	label.TextSize = 22
	label.TextWrapped = true
	label.RichText = false
	label.Visible = false
	label.ZIndex = parent.ZIndex + 2
	label.Parent = parent
	self._emptyStateLabel = label
	return label
end

function TitleController:_applyRowStyle(row: GuiButton, title, isSelected: boolean, isEquipped: boolean)
	row.ImageColor3 = title.displayColor

	for _, imageName in ipairs({ "Rays", "Cover", "Cover2" }) do
		local image = row:FindFirstChild(imageName)
		if image and image:IsA("ImageLabel") then
			image.ImageColor3 = title.displayColor
			if imageName == "Rays" then
				image.ImageTransparency = if isSelected then 0.05 else 0.35
			elseif imageName == "Cover2" then
				image.ImageTransparency = if isSelected then 0.08 else 0.28
			else
				image.ImageTransparency = if isSelected then 0.02 else 0.18
			end
		end
	end

	local label = row:FindFirstChild("BundleName")
	if label and label:IsA("TextLabel") then
		label.TextColor3 = title.displayColor
		if isEquipped then
			TranslationHelper.setLiteralText(label, string.format(
				"%s [%s]",
				title.label,
				TranslationHelper.formatByKey(LocalizationKeys.Title.Action.EquippedTag)
			))
		else
			TranslationHelper.setSourceText(label, title.label)
		end
	end
end

function TitleController:_syncList()
	local scrollingFrame = self._scrollingFrame
	local template = self._template
	local indexFrame = self._ui.indexFrame
	if not (scrollingFrame and template and indexFrame) then
		return
	end

	local titles = self:_getUnlockedTitles()
	self:_ensureSelection(titles)

	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child:IsA("GuiButton") and child ~= template then
			child:Destroy()
		end
	end

	local equippedTitleId = getEquippedTitleId()
	for index, title in ipairs(titles) do
		local row = template:Clone()
		row.Name = string.format("Title_%s", title.id)
		row.Visible = true
		row.LayoutOrder = index
		row.Parent = scrollingFrame
		self:_applyRowStyle(row, title, self._selectedTitleId == title.id, equippedTitleId == title.id)
		UIController:CreateButton(row, function()
			self._selectedTitleId = title.id
			self:_syncList()
			self:_syncPreview()
		end)
	end

	template.Visible = false
	scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y

	local emptyStateLabel = self:_ensureEmptyStateLabel(indexFrame)
	emptyStateLabel.Visible = #titles == 0
	if #titles == 0 then
		TranslationHelper.setKeyText(
			emptyStateLabel,
			if self._searchText ~= ""
				then LocalizationKeys.Title.EmptyState.SearchNoMatches
				else LocalizationKeys.Title.EmptyState.FirstUnlock
		)
	end
end

function TitleController:_syncPreview()
	local previewHolder = self._ui.previewHolder
	local titleNameLabel = self._ui.titleNameLabel
	local titleDescriptionLabel = self._ui.titleDescriptionLabel
	local equipButton = self._ui.equipButton
	if not (previewHolder and titleNameLabel and titleDescriptionLabel and equipButton) then
		return
	end

	local selectedTitle = self:_getSelectedTitle()
	if not selectedTitle then
		previewHolder.Visible = false
		return
	end

	previewHolder.Visible = true
	TranslationHelper.setSourceText(titleNameLabel, selectedTitle.label)
	titleNameLabel.TextColor3 = selectedTitle.displayColor
	TranslationHelper.setKeyText(titleDescriptionLabel, LocalizationKeys.Title.Preview.UnlockBy, {
		Description = selectedTitle.description,
		HowToGet = selectedTitle.howToGet,
	})

	local equippedTitleId = getEquippedTitleId()
	local isEquipped = equippedTitleId == selectedTitle.id
	local buttonText = equipButton:FindFirstChild("TextLabel")
	if buttonText and buttonText:IsA("TextLabel") then
		TranslationHelper.setKeyText(
			buttonText,
			if isEquipped then LocalizationKeys.Title.Action.Unequip else LocalizationKeys.Title.Action.Equip
		)
	end

	for _, imageName in ipairs({ "Rays", "Cover", "Cover2" }) do
		local image = equipButton:FindFirstChild(imageName)
		if image and image:IsA("ImageLabel") then
			image.ImageColor3 = selectedTitle.displayColor
		end
	end
end

function TitleController:_syncAll()
	self:_syncList()
	self:_syncPreview()
end

function TitleController:_submitEquipToggle()
	local selectedTitle = self:_getSelectedTitle()
	if not selectedTitle then
		return
	end

	local remote = self:_getRemote()
	if not remote then
		Notify.Show(TranslationHelper.formatByKey(LocalizationKeys.Title.Message.RemoteUnavailable), { channel = "titles" })
		return
	end

	local isEquipped = getEquippedTitleId() == selectedTitle.id
	local ok, response = pcall(function()
		return remote:InvokeServer({
			titleId = if isEquipped then nil else selectedTitle.id,
		})
	end)

	if not ok then
		Notify.Show(TranslationHelper.formatByKey(LocalizationKeys.Title.Message.UpdateFailed), { channel = "titles" })
		return
	end

	if typeof(response) == "table" and typeof(response.message) == "string" and response.message ~= "" then
		Notify.Show(response.message, { channel = "titles" })
	end

	if typeof(response) ~= "table" or response.ok ~= true then
		return
	end

	self:_syncAll()
	ToggleSoundUtil.PlayToggle(isEquipped ~= true)
end

function TitleController:_bindOpenButton(openButton: GuiButton)
	UIController:CreateButton(openButton, function()
		local wasOpen = FrameController:IsOpen(WINDOW_NAME)
		FrameController:ToggleFrame(WINDOW_NAME)
		if not wasOpen then
			task.defer(function()
				self:_ensureFullUi(self._playerGui or LOCAL_PLAYER:WaitForChild("PlayerGui"))
				self:_syncAll()
			end)
		end
	end)
end

function TitleController:_cacheOpenButton(playerGui: PlayerGui)
	local mainInterface = playerGui:WaitForChild("MainInterface", 30)
	if not (mainInterface and mainInterface:IsA("ScreenGui")) then
		error("PlayerGui.MainInterface is missing.")
	end

	local openButton = mainInterface:WaitForChild("Main", 30):WaitForChild("Titles", 30)
	if not (openButton and openButton:IsA("GuiButton")) then
		error("Titles open button is missing.")
	end

	self._ui.openButton = openButton
end

function TitleController:_cacheUi(playerGui: PlayerGui)
	local mainInterface = playerGui:WaitForChild("MainInterface", 30)
	local modalRoot = playerGui:WaitForChild("ModalRoot", 30)
	if not (mainInterface and mainInterface:IsA("ScreenGui")) then
		error("PlayerGui.MainInterface is missing.")
	end
	if not (modalRoot and modalRoot:IsA("ScreenGui")) then
		error("PlayerGui.ModalRoot is missing.")
	end

	local titlesRoot = modalRoot:WaitForChild(WINDOW_NAME, 30)
	local openButton = mainInterface:WaitForChild("Main", 30):WaitForChild("Titles", 30)
	if not (titlesRoot and titlesRoot:IsA("GuiObject") and openButton and openButton:IsA("GuiButton")) then
		error("Titles UI hierarchy is missing required instances.")
	end

	local scrollingFrame = titlesRoot:WaitForChild("Index", 30):WaitForChild("ScrollingFrame", 30)
	local template = scrollingFrame:WaitForChild("Template", 30)
	local previewHolder = titlesRoot:WaitForChild("TitlePreviewHolder", 30)
	local equipButton = previewHolder:WaitForChild("EquipButton", 30)
	local titleNameLabel = previewHolder:WaitForChild("TitleName", 30)
	local titleDescriptionLabel = previewHolder:WaitForChild("TitleDescription", 30)
	local searchTextBox = titlesRoot:WaitForChild("SearchBar", 30):WaitForChild("TextBox", 30)
	local closeButton = titlesRoot:WaitForChild("Topbar", 30):WaitForChild("CloseButton", 30)

	if not (
		scrollingFrame:IsA("ScrollingFrame")
		and template:IsA("GuiButton")
		and previewHolder:IsA("Frame")
		and equipButton:IsA("GuiButton")
		and titleNameLabel:IsA("TextLabel")
		and titleDescriptionLabel:IsA("TextLabel")
		and searchTextBox:IsA("TextBox")
		and closeButton:IsA("GuiButton")
	) then
		error("Titles UI hierarchy is missing required instances.")
	end

	self._root = titlesRoot
	self._scrollingFrame = scrollingFrame
	self._template = template
	self._ui = {
		openButton = openButton,
		closeButton = closeButton,
		indexFrame = titlesRoot:WaitForChild("Index", 30),
		searchTextBox = searchTextBox,
		previewHolder = previewHolder,
		equipButton = equipButton,
		titleNameLabel = titleNameLabel,
		titleDescriptionLabel = titleDescriptionLabel,
	}

	self._template.Visible = false
	self._ui.previewHolder.Visible = false
end

function TitleController:_ensureFullUi(playerGui: PlayerGui)
	if self._fullUiReady then
		return
	end

	self:_cacheUi(playerGui)

	ToggleSoundUtil.MarkToggleButton(self._ui.equipButton)

	UIController:CreateButton(self._ui.closeButton, function()
		FrameController:CloseFrame(WINDOW_NAME)
	end)
	UIController:CreateButton(self._ui.equipButton, function()
		self:_submitEquipToggle()
	end)

	self._ui.searchTextBox:GetPropertyChangedSignal("Text"):Connect(function()
		self._searchText = self._ui.searchTextBox.Text
		self:_syncAll()
	end)

	if not self._dataBindingsReady then
		DataController.DataReceived:Connect(function()
			self:_syncAll()
		end)

		DataController.DataUpdated:Connect(function(key)
			if key == ACHIEVEMENTS_KEY or key == EQUIPPED_TITLE_KEY then
				self:_syncAll()
			end
		end)

		self._dataBindingsReady = true
	end

	self._fullUiReady = true
end

function TitleController:OnStart()
	self:_ensureState()

	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	self._playerGui = playerGui
	self:_cacheOpenButton(playerGui)

	if not self._openButtonBound then
		self:_bindOpenButton(self._ui.openButton)
		self._openButtonBound = true
	end
end

return TitleController
