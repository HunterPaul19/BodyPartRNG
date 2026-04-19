local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BodyPartCollection = require(ReplicatedStorage.Shared.Character.BodyPartCollection)
local PreviewAppearanceRegistry = require(ReplicatedStorage.Shared.Character.PreviewAppearanceRegistry)
local BodyPartRegions = require(ReplicatedStorage.Shared.Character.BodyPartRegions)
local OwnedBodyParts = require(ReplicatedStorage.Shared.Character.OwnedBodyParts)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local BodyPartPresentation = require(ReplicatedStorage.Shared.UI.BodyPartPresentation)
local ConfirmationWarning = require(ReplicatedStorage.Shared.UI.ConfirmationWarning)
local ViewportModelRenderer = require(ReplicatedStorage.Shared.UI.ViewportModelRenderer)
local DataController = require(script.Parent.DataController)
local FrameController = require(script.Parent.FrameController)
local UIController = require(script.Parent.UIController)

local LOCAL_PLAYER = Players.LocalPlayer
local WINDOW_NAME = "Index"
local BODY_PARTS_DATA_KEY = "bodyParts"
local SELECTED_COLOR = Color3.fromRGB(116, 192, 255)
local DEFAULT_OUTLINE_COLOR = Color3.fromRGB(255, 255, 255)
local INACTIVE_OUTLINE_TRANSPARENCY = 0.55

local RARITY_RANKS = {
	Basic = 1,
	Clean = 2,
	Prime = 3,
	Elite = 4,
	Apex = 5,
}

local REGION_LABELS = {
	Head = "Head",
	Torso = "Torso",
	LeftArm = "Left Arm",
	RightArm = "Right Arm",
	LeftLeg = "Left Leg",
	RightLeg = "Right Leg",
}

local BUTTON_NAME_TO_REGION = {
	Head = "Head",
	Heads = "Head",
	Torso = "Torso",
	Torsos = "Torso",
	LeftArm = "LeftArm",
	LeftArms = "LeftArm",
	RightArm = "RightArm",
	RightArms = "RightArm",
	LeftLeg = "LeftLeg",
	LeftLegs = "LeftLeg",
	RightLeg = "RightLeg",
	RightLegs = "RightLeg",
}

local BUY_BUNDLE_WARNING_TEXT = "This purchase will not grant ANYTHING in OUR game"

type OwnedBodyPartsState = OwnedBodyParts.OwnedBodyPartsState
type SetSummary = BodyPartCollection.SetSummary
type TextLabelStyle = {
	fontFace: Font,
	textColor3: Color3,
	textTransparency: number,
}

local IndexController = {}

local function getBodyPartsState(): OwnedBodyPartsState
	local bodyPartsState = DataController:Get(BODY_PARTS_DATA_KEY)
	if typeof(bodyPartsState) ~= "table" then
		return OwnedBodyParts.CreateEmptyState()
	end

	local emptyState = OwnedBodyParts.CreateEmptyState()
	return {
		ownedById = if typeof(bodyPartsState.ownedById) == "table" then bodyPartsState.ownedById else emptyState.ownedById,
		discoveredPieceIds = if typeof(bodyPartsState.discoveredPieceIds) == "table"
			then bodyPartsState.discoveredPieceIds
			else emptyState.discoveredPieceIds,
		nextOwnedId = if typeof(bodyPartsState.nextOwnedId) == "number" then bodyPartsState.nextOwnedId else emptyState.nextOwnedId,
	}
end

local function getFontWithWeight(fontFace: Font, fontWeight: Enum.FontWeight): Font
	return Font.new(fontFace.Family, fontWeight, fontFace.Style)
end

local function setSelectionCornersVisible(instance: Instance, isVisible: boolean)
	local selectionCorners = instance:FindFirstChild("SelectionCorners")
	if not selectionCorners then
		return
	end

	if selectionCorners:IsA("GuiObject") then
		selectionCorners.Visible = isVisible
	end

	for _, descendant in ipairs(selectionCorners:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			descendant.Visible = isVisible
		end
	end
end

local function setOutlineColor(button: GuiButton, color: Color3, transparency: number)
	local outline = button:FindFirstChild("Outline")
	if outline and outline:IsA("ImageLabel") then
		outline.ImageColor3 = color
		outline.ImageTransparency = transparency
	end
end

local function findFirstChildByNames(parent: Instance, names: { string }): Instance?
	for _, name in ipairs(names) do
		local child = parent:FindFirstChild(name)
		if child then
			return child
		end
	end

	return nil
end

local function findScrollingFrame(container: Instance): ScrollingFrame?
	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("ScrollingFrame") then
			return descendant
		end
	end

	return nil
end

local function summaryMatchesSearch(summary: SetSummary, searchText: string): boolean
	if searchText == "" then
		return true
	end

	local displayName = string.lower(summary.setConfig.rollDisplay.displayName or "")
	if string.find(displayName, searchText, 1, true) then
		return true
	end

	return string.find(string.lower(summary.setId), searchText, 1, true) ~= nil
end

local function findTopLevelLabel(indexRoot: GuiObject, exclude: { [Instance]: boolean }, predicate: (TextLabel) -> boolean): TextLabel?
	for _, child in ipairs(indexRoot:GetChildren()) do
		if child:IsA("TextLabel") and not exclude[child] and predicate(child) then
			return child
		end
	end

	return nil
end

local function sortLabelsByY(labels: { TextLabel }): { TextLabel }
	table.sort(labels, function(a, b)
		if a.AbsolutePosition.Y ~= b.AbsolutePosition.Y then
			return a.AbsolutePosition.Y < b.AbsolutePosition.Y
		end

		return a.AbsolutePosition.X < b.AbsolutePosition.X
	end)

	return labels
end

local function findTemplate(scrollingFrame: ScrollingFrame, preferLocked: boolean): GuiButton?
	local preferredName = if preferLocked then "LockedSetTemplate" else "SetTemplate"
	local preferred = scrollingFrame:FindFirstChild(preferredName)
	if preferred and preferred:IsA("GuiButton") then
		return preferred
	end

	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if not child:IsA("GuiButton") then
			continue
		end

		local bundleLabel = child:FindFirstChild("BundleName")
		if not (bundleLabel and bundleLabel:IsA("TextLabel")) then
			continue
		end

		if preferLocked then
			if string.find(string.lower(bundleLabel.Text), "0/6 unlocked", 1, true) then
				return child
			end
		elseif child.Name == "Template" or bundleLabel.Text == "Zombie" or bundleLabel.Text == "Default" then
			return child
		end
	end

	return nil
end

function IndexController:_ensureState()
	if self._started then
		return
	end

	self._started = true
	self._indexRoot = nil
	self._scrollingFrame = nil
	self._setTemplate = nil
	self._lockedTemplate = nil
	self._ui = {}
	self._rowsBySetId = {}
	self._selectedSetId = nil :: string?
	self._selectedRegion = nil :: string?
	self._searchText = ""
	self._orderedSummaries = {} :: { SetSummary }
	self._summariesBySetId = {} :: { [string]: SetSummary }
	self._catalogOrderBySetId = {} :: { [string]: number }
	self._defaultSetNameLabelStyle = nil :: TextLabelStyle?
	self._defaultPieceNameLabelStyle = nil :: TextLabelStyle?
	self._completedSetCount = 0
	self._bodyPartsRefreshScheduled = false
	self._playerGui = nil
	self._openButtonBound = false
	self._fullUiReady = false
	self._dataBindingsReady = false
end

function IndexController:_getRarityTemplatesFolder(): Folder?
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	if not gameAssets then
		return nil
	end

	local uiFolder = gameAssets:FindFirstChild("UI")
	if not (uiFolder and uiFolder:IsA("Folder")) then
		return nil
	end

	local indexFolder = uiFolder:FindFirstChild("Index")
	if not (indexFolder and indexFolder:IsA("Folder")) then
		return nil
	end

	local rarityTemplates = indexFolder:FindFirstChild("RarityTemplates")
	if rarityTemplates and rarityTemplates:IsA("Folder") then
		return rarityTemplates
	end

	return nil
end

function IndexController:_rebuildDerivedState()
	self._orderedSummaries = BodyPartCollection.GetAllSetSummaries(getBodyPartsState())
	self._summariesBySetId = {}
	self._completedSetCount = 0
	self._catalogOrderBySetId = {}

	for index, setConfig in ipairs(BodyPartsCatalog.GetAllSets()) do
		self._catalogOrderBySetId[setConfig.id] = index
	end

	table.sort(self._orderedSummaries, function(a, b)
		local aDiscovered = a.discoveredCount > 0
		local bDiscovered = b.discoveredCount > 0
		if aDiscovered ~= bDiscovered then
			return aDiscovered and not bDiscovered
		end

		local aRarityRank = RARITY_RANKS[a.setConfig.rollDisplay.rarity] or math.huge
		local bRarityRank = RARITY_RANKS[b.setConfig.rollDisplay.rarity] or math.huge
		if aRarityRank ~= bRarityRank then
			return aRarityRank < bRarityRank
		end

		local aCatalogOrder = self._catalogOrderBySetId[a.setId] or math.huge
		local bCatalogOrder = self._catalogOrderBySetId[b.setId] or math.huge
		if aCatalogOrder ~= bCatalogOrder then
			return aCatalogOrder < bCatalogOrder
		end

		return a.setId < b.setId
	end)

	for _, summary in ipairs(self._orderedSummaries) do
		self._summariesBySetId[summary.setId] = summary
		if summary.discoveredCount == #BodyPartRegions.Order then
			self._completedSetCount += 1
		end
	end
end

function IndexController:_syncSelectionState()
	local searchText = string.lower(self._searchText or "")
	if self._selectedSetId ~= nil then
		local currentSummary = self._summariesBySetId[self._selectedSetId]
		if currentSummary == nil or not summaryMatchesSearch(currentSummary, searchText) then
			self._selectedSetId = nil
			self._selectedRegion = nil
		end
	end

	local summary = self._selectedSetId and self._summariesBySetId[self._selectedSetId] or nil
	if not summary then
		for _, candidateSummary in ipairs(self._orderedSummaries) do
			if candidateSummary.discoveredCount > 0 and summaryMatchesSearch(candidateSummary, searchText) then
				self._selectedSetId = candidateSummary.setId
				summary = candidateSummary
				break
			end
		end

		if not summary then
			self._selectedRegion = nil
			return
		end
	end

	if self._selectedRegion ~= nil and summary.discoveredPieceIdsByRegion[self._selectedRegion] ~= nil then
		return
	end

	self._selectedRegion = nil
	for _, region in ipairs(BodyPartRegions.Order) do
		if summary.discoveredPieceIdsByRegion[region] ~= nil then
			self._selectedRegion = region
			return
		end
	end
end

function IndexController:_getSelectedSummary(): SetSummary?
	return self._selectedSetId and self._summariesBySetId[self._selectedSetId] or nil
end

function IndexController:_getSelectedPieceId(summary: SetSummary?): string?
	if not summary then
		return nil
	end

	if self._selectedRegion and summary.discoveredPieceIdsByRegion[self._selectedRegion] then
		return summary.discoveredPieceIdsByRegion[self._selectedRegion]
	end

	for _, region in ipairs(BodyPartRegions.Order) do
		local pieceId = summary.discoveredPieceIdsByRegion[region]
		if pieceId then
			return pieceId
		end
	end

	return nil
end

function IndexController:_getSelectedBundleId(): number?
	local selectedSummary = self:_getSelectedSummary()
	if not selectedSummary then
		return nil
	end

	local setConfig = selectedSummary.setConfig
	local bundleId = setConfig and setConfig.bundleId or nil
	if typeof(bundleId) ~= "number" or bundleId <= 0 then
		return nil
	end

	return math.floor(bundleId)
end

function IndexController:_buildBuyBundleConfirmationMessage(): string
	return string.format("%s. Continue?", BUY_BUNDLE_WARNING_TEXT)
end

function IndexController:_applyRarityLabel(row: GuiButton, rarity: string)
	local rarityLabel = row:FindFirstChild("Rarity")
	local rarityTemplates = self:_getRarityTemplatesFolder()
	local rarityTemplate = rarityTemplates and rarityTemplates:FindFirstChild(rarity) or nil

	if rarityTemplate and rarityTemplate:IsA("TextLabel") then
		if rarityLabel then
			rarityLabel:Destroy()
		end

		local clonedLabel = rarityTemplate:Clone()
		clonedLabel.Name = "Rarity"
		clonedLabel.Text = rarity
		clonedLabel.Visible = true
		clonedLabel.Parent = row
		return
	end

	if rarityLabel and rarityLabel:IsA("TextLabel") then
		rarityLabel.Text = rarity
	end
end

function IndexController:_applyUnlockedRowStyle(row: GuiButton, summary: SetSummary)
	local rollDisplay = summary.setConfig.rollDisplay
	local bundleLabel = row:FindFirstChild("BundleName")
	local progressLabel = row:FindFirstChild("BundleProgress")
	local outline = row:FindFirstChildWhichIsA("UIStroke")
	if bundleLabel and bundleLabel:IsA("TextLabel") then
		bundleLabel.RichText = false
		bundleLabel.Text = rollDisplay.displayName
		bundleLabel.TextColor3 = rollDisplay.color
		bundleLabel.FontFace = getFontWithWeight(rollDisplay.fontFace, rollDisplay.fontWeight)
		if progressLabel and progressLabel:IsA("TextLabel") then
			progressLabel:Destroy()
		end
	end

	row.ImageColor3 = rollDisplay.color

	for _, childName in ipairs({ "Cover", "Cover2", "Rays" }) do
		local child = row:FindFirstChild(childName)
		if child and child:IsA("ImageLabel") then
			child.ImageColor3 = rollDisplay.color
		end
	end

	if outline then
		outline.Color = rollDisplay.color
	end

	self:_applyRarityLabel(row, rollDisplay.rarity)
end

function IndexController:_applyLockedRowStyle(row: GuiButton, summary: SetSummary)
	local bundleLabel = row:FindFirstChild("BundleName")
	local progressLabel = row:FindFirstChild("BundleProgress")
	if bundleLabel and bundleLabel:IsA("TextLabel") then
		bundleLabel.RichText = false
		bundleLabel.Text = "0/6 Unlocked"
	end
	if progressLabel and progressLabel:IsA("TextLabel") then
		progressLabel:Destroy()
	end

	self:_applyRarityLabel(row, summary.setConfig.rollDisplay.rarity)
end

function IndexController:_refreshRows()
	local scrollingFrame = self._scrollingFrame
	local setTemplate = self._setTemplate
	local lockedTemplate = self._lockedTemplate
	if not (scrollingFrame and setTemplate and lockedTemplate) then
		return
	end

	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child:IsA("GuiButton") and child ~= setTemplate and child ~= lockedTemplate then
			child:Destroy()
		end
	end

	self._rowsBySetId = {}

	local searchText = string.lower(self._searchText or "")
	local visibleIndex = 0
	for _, summary in ipairs(self._orderedSummaries) do
		if not summaryMatchesSearch(summary, searchText) then
			continue
		end

		visibleIndex += 1
		local template = if summary.discoveredCount == 0 then lockedTemplate else setTemplate
		local row = template:Clone()
		row.Name = string.format("Set_%s", summary.setId)
		row.Visible = true
		row.LayoutOrder = visibleIndex
		row.Parent = scrollingFrame

		if summary.discoveredCount == 0 then
			self:_applyLockedRowStyle(row, summary)
		else
			self:_applyUnlockedRowStyle(row, summary)
		end

		setSelectionCornersVisible(row, summary.setId == self._selectedSetId)

		UIController:CreateButton(row, function()
			self._selectedSetId = summary.setId
			self._selectedRegion = nil
			self:_syncSelectionState()
			self:_syncAll()
		end)

		self._rowsBySetId[summary.setId] = row
	end

	setTemplate.Visible = false
	lockedTemplate.Visible = false
end

function IndexController:_syncSummaryLabel()
	local summaryLabel = self._ui.summaryLabel
	if not summaryLabel then
		return
	end

	summaryLabel.Text = string.format("%d/%d Bundles Completed", self._completedSetCount, #self._orderedSummaries)
end

function IndexController:_restoreDefaultPieceNameLabelStyle()
	local pieceNameLabel = self._ui.pieceNameLabel
	local defaultStyle = self._defaultPieceNameLabelStyle
	if not (pieceNameLabel and defaultStyle) then
		return
	end

	pieceNameLabel.FontFace = defaultStyle.fontFace
	pieceNameLabel.TextColor3 = defaultStyle.textColor3
	pieceNameLabel.TextTransparency = defaultStyle.textTransparency
end

function IndexController:_restoreDefaultSetNameLabelStyle()
	local setNameLabel = self._ui.setNameLabel
	local defaultStyle = self._defaultSetNameLabelStyle
	if not (setNameLabel and defaultStyle) then
		return
	end

	setNameLabel.FontFace = defaultStyle.fontFace
	setNameLabel.TextColor3 = defaultStyle.textColor3
	setNameLabel.TextTransparency = defaultStyle.textTransparency
end

function IndexController:_applySetNameLabelStyle(summary: SetSummary?)
	local setNameLabel = self._ui.setNameLabel
	if not setNameLabel then
		return
	end

	local rollDisplay = summary and summary.setConfig and summary.setConfig.rollDisplay or nil
	if not rollDisplay then
		self:_restoreDefaultSetNameLabelStyle()
		return
	end

	if typeof(rollDisplay.fontFace) ~= "Font" or typeof(rollDisplay.fontWeight) ~= "EnumItem" or typeof(rollDisplay.color) ~= "Color3" then
		self:_restoreDefaultSetNameLabelStyle()
		return
	end

	setNameLabel.FontFace = getFontWithWeight(rollDisplay.fontFace, rollDisplay.fontWeight)
	setNameLabel.TextColor3 = rollDisplay.color
	setNameLabel.TextTransparency = 0
end

function IndexController:_applyPieceNameLabelStyle(summary: SetSummary?, selectedPieceId: string?)
	local pieceNameLabel = self._ui.pieceNameLabel
	if not pieceNameLabel then
		return
	end

	if not (summary and typeof(selectedPieceId) == "string" and selectedPieceId ~= "") then
		self:_restoreDefaultPieceNameLabelStyle()
		return
	end

	local rollDisplay = summary.setConfig and summary.setConfig.rollDisplay or nil
	if not rollDisplay then
		self:_restoreDefaultPieceNameLabelStyle()
		return
	end

	if typeof(rollDisplay.fontFace) ~= "Font" or typeof(rollDisplay.fontWeight) ~= "EnumItem" or typeof(rollDisplay.color) ~= "Color3" then
		self:_restoreDefaultPieceNameLabelStyle()
		return
	end

	pieceNameLabel.FontFace = getFontWithWeight(rollDisplay.fontFace, rollDisplay.fontWeight)
	pieceNameLabel.TextColor3 = rollDisplay.color
	pieceNameLabel.TextTransparency = 0
end

function IndexController:_syncPieceButtons()
	local selectedSummary = self:_getSelectedSummary()
	local hasSelection = selectedSummary ~= nil

	for region, button in pairs(self._ui.regionButtons) do
		local regionIndex = table.find(BodyPartRegions.Order, region) or math.huge
		local usageLabel = button:FindFirstChild("Usage")
		if usageLabel and usageLabel:IsA("TextLabel") then
			usageLabel.Text = REGION_LABELS[region] or region
		end

		local icon = button:FindFirstChild("Icon")
		local isDiscovered = hasSelection and selectedSummary.discoveredPieceIdsByRegion[region] ~= nil
		local isSelected = hasSelection and self._selectedRegion == region
		local outlineTransparency = INACTIVE_OUTLINE_TRANSPARENCY
		local outlineColor = DEFAULT_OUTLINE_COLOR

		button.LayoutOrder = regionIndex

		if not (hasSelection and isDiscovered) then
			button.Visible = false
			button.Active = false
			setOutlineColor(button, DEFAULT_OUTLINE_COLOR, 0.7)
			continue
		end

		button.Visible = true
		button.Active = true
		if usageLabel and usageLabel:IsA("TextLabel") then
			usageLabel.TextTransparency = 0
		end
		if icon and icon:IsA("ImageLabel") then
			icon.ImageTransparency = 0.2
		end

		outlineTransparency = 0.18
		if isSelected then
			outlineColor = SELECTED_COLOR
			outlineTransparency = 0
		end

		setOutlineColor(button, outlineColor, outlineTransparency)
	end
end

function IndexController:_clearViewport()
	local viewportFrame = self._ui.viewportFrame
	if not viewportFrame then
		return
	end

	ViewportModelRenderer.Clear(viewportFrame)
end

function IndexController:_renderViewportForPiece(pieceId: string?)
	local viewportFrame = self._ui.viewportFrame
	if not viewportFrame then
		return
	end

	self:_clearViewport()

	if typeof(pieceId) ~= "string" or pieceId == "" then
		return
	end

	local previewPresentation = BodyPartPresentation.BuildPreviewPresentation({
		pieceId = pieceId,
		appearanceUserId = LOCAL_PLAYER.UserId,
	})
	if not previewPresentation or not (previewPresentation.bundleModel and previewPresentation.bundleModel:IsA("Model")) then
		return
	end

	local appearanceSnapshot = PreviewAppearanceRegistry.GetSnapshotForUserId(previewPresentation.appearanceUserId)
	if appearanceSnapshot then
		ViewportModelRenderer.RenderBodyPartPreview(
			viewportFrame,
			previewPresentation.bundleModel,
			previewPresentation.region,
			appearanceSnapshot,
			previewPresentation.previewScale
		)
		return
	end

	ViewportModelRenderer.RenderBundle(viewportFrame, previewPresentation.bundleModel)
end

function IndexController:_syncDetailPanel()
	local selectedSummary = self:_getSelectedSummary()
	local setNameLabel = self._ui.setNameLabel
	local pieceNameLabel = self._ui.pieceNameLabel

	if not selectedSummary then
		if setNameLabel then
			setNameLabel.Text = "Select a Bundle"
		end
		if pieceNameLabel then
			pieceNameLabel.Text = "Select a Piece"
		end
		self:_restoreDefaultSetNameLabelStyle()
		self:_restoreDefaultPieceNameLabelStyle()
		self:_clearViewport()
		return
	end

	local selectedPieceId = self:_getSelectedPieceId(selectedSummary)
	local selectedPiece = selectedPieceId and BodyPartsCatalog.GetPiece(selectedPieceId) or nil
	local discoveredPieceId = self._selectedRegion and selectedSummary.discoveredPieceIdsByRegion[self._selectedRegion] or nil
	local displayedRegion = self._selectedRegion

	if displayedRegion == nil and selectedPiece then
		displayedRegion = selectedPiece.region
	end

	if selectedSummary.discoveredCount == 0 then
		if setNameLabel then
			setNameLabel.Text = "0/6 Unlocked"
		end
		if pieceNameLabel then
			pieceNameLabel.Text = "No Piece Discovered"
		end
		self:_restoreDefaultSetNameLabelStyle()
		self:_restoreDefaultPieceNameLabelStyle()
		self:_clearViewport()
		return
	end

	if setNameLabel then
		setNameLabel.Text = selectedSummary.setConfig.rollDisplay.displayName
	end
	self:_applySetNameLabelStyle(selectedSummary)

	if pieceNameLabel then
		pieceNameLabel.Text = displayedRegion and (REGION_LABELS[displayedRegion] or displayedRegion) or "Select a Piece"
	end
	self:_restoreDefaultPieceNameLabelStyle()

	if discoveredPieceId then
		self:_renderViewportForPiece(discoveredPieceId)
	else
		self:_clearViewport()
	end
end

function IndexController:_syncBuyBundleButton()
	local buyBundleButton = self._ui.buyBundleButton
	if not buyBundleButton then
		return
	end

	local bundleId = self:_getSelectedBundleId()
	local hasBundleId = bundleId ~= nil

	buyBundleButton.Visible = hasBundleId
	buyBundleButton.Active = hasBundleId
	buyBundleButton.AutoButtonColor = false

	local textLabel = buyBundleButton:FindFirstChild("TextLabel")
	if textLabel and textLabel:IsA("TextLabel") then
		textLabel.Text = "Buy Bundle"
		textLabel.TextTransparency = if hasBundleId then 0 else 0.35
	end

	for _, child in ipairs(buyBundleButton:GetChildren()) do
		if child:IsA("ImageLabel") then
			child.ImageTransparency = if hasBundleId then 0 else if child.Name == "Rays" then 0.45 else 0.25
		end
	end
end

function IndexController:_syncAll()
	self:_rebuildDerivedState()
	self:_syncSelectionState()
	self:_syncSummaryLabel()
	self:_refreshRows()
	self:_syncPieceButtons()
	self:_syncDetailPanel()
	self:_syncBuyBundleButton()
end

function IndexController:_flushScheduledBodyPartsRefresh()
	self._bodyPartsRefreshScheduled = false
	if not FrameController:IsOpen(WINDOW_NAME) then
		return
	end

	self:_syncAll()
end

function IndexController:_scheduleBodyPartsRefresh()
	if not FrameController:IsOpen(WINDOW_NAME) or self._bodyPartsRefreshScheduled then
		return
	end

	self._bodyPartsRefreshScheduled = true
	task.defer(function()
		self:_flushScheduledBodyPartsRefresh()
	end)
end

function IndexController:_cacheOpenButton(playerGui: PlayerGui)
	local mainInterface = playerGui:WaitForChild("MainInterface", 30)
	if not (mainInterface and mainInterface:IsA("ScreenGui")) then
		error("PlayerGui.MainInterface is missing.")
	end

	local openButton = mainInterface:WaitForChild("Main", 30):WaitForChild("ExtraButtons", 30):WaitForChild("Index", 30)
	if not (openButton and openButton:IsA("GuiButton")) then
		error("Index open button is missing.")
	end

	self._ui.openButton = openButton
end

function IndexController:_cacheUi(playerGui: PlayerGui)
	local mainInterface = playerGui:WaitForChild("MainInterface", 30)
	local modalRoot = playerGui:WaitForChild("ModalRoot", 30)
	if not (mainInterface and mainInterface:IsA("ScreenGui")) then
		error("PlayerGui.MainInterface is missing.")
	end
	if not (modalRoot and modalRoot:IsA("ScreenGui")) then
		error("PlayerGui.ModalRoot is missing.")
	end

	local indexRoot = modalRoot:WaitForChild("Index", 30)
	if not (indexRoot and indexRoot:IsA("GuiObject")) then
		error("PlayerGui.ModalRoot.Index is missing.")
	end

	local topBar = findFirstChildByNames(indexRoot, { "TopBar", "Topbar" })
	local listContainer = findFirstChildByNames(indexRoot, { "ListPanel", "Index" })
	local selectorPanel = findFirstChildByNames(indexRoot, { "PieceButtons", "SearchBar" })
	local viewportFrame = findFirstChildByNames(indexRoot, { "PieceViewport", "ViewportFrame" })
	local openButton = mainInterface:WaitForChild("Main", 30):WaitForChild("ExtraButtons", 30):WaitForChild("Index", 30)

	if not (
		topBar
		and topBar:IsA("Frame")
		and listContainer
		and listContainer:IsA("Frame")
		and selectorPanel
		and selectorPanel:IsA("Frame")
		and viewportFrame
		and viewportFrame:IsA("ViewportFrame")
		and openButton
		and openButton:IsA("GuiButton")
	) then
		error("Index UI hierarchy is missing required instances.")
	end

	local scrollingFrame = findScrollingFrame(listContainer)
	if not scrollingFrame then
		error("Index list scrolling frame is missing.")
	end

	local setTemplate = findTemplate(scrollingFrame, false)
	local lockedTemplate = findTemplate(scrollingFrame, true)
	if not (setTemplate and lockedTemplate) then
		error("Index row templates are missing.")
	end

	local selectorButtonsContainer = selectorPanel:FindFirstChild("RegionButtons")
		or selectorPanel:FindFirstChild("Rarities")
		or selectorPanel
	local searchBox = selectorPanel:FindFirstChildWhichIsA("TextBox", true)
	local regionButtons = {}
	for _, child in ipairs(selectorButtonsContainer:GetChildren()) do
		if child:IsA("GuiButton") then
			local region = BUTTON_NAME_TO_REGION[child.Name]
			if region then
				regionButtons[region] = child
			else
				child.Visible = false
			end
		end
	end

	local exclude = {
		[topBar] = true,
		[listContainer] = true,
		[selectorPanel] = true,
		[viewportFrame] = true,
	}

	local summaryLabel = findFirstChildByNames(indexRoot, { "SummaryLabel" })
	if not (summaryLabel and summaryLabel:IsA("TextLabel")) then
		summaryLabel = findTopLevelLabel(indexRoot, exclude, function(label)
			return string.find(label.Text, "Bundles Completed", 1, true) ~= nil
		end)
	end

	local setNameLabel = findFirstChildByNames(indexRoot, { "SetNameLabel", "BundleNameLabel" })
	local pieceNameLabel = findFirstChildByNames(indexRoot, { "PieceNameLabel", "RegionNameLabel" })
	if not ((setNameLabel and setNameLabel:IsA("TextLabel")) and (pieceNameLabel and pieceNameLabel:IsA("TextLabel"))) then
		local labels = {}
		for _, child in ipairs(indexRoot:GetChildren()) do
			if child:IsA("TextLabel") and child ~= summaryLabel and not exclude[child] then
				table.insert(labels, child)
			end
		end

		sortLabelsByY(labels)
		setNameLabel = if setNameLabel and setNameLabel:IsA("TextLabel") then setNameLabel else labels[1]
		pieceNameLabel = if pieceNameLabel and pieceNameLabel:IsA("TextLabel") then pieceNameLabel else labels[2]
	end

	local buyBundleButton = viewportFrame:FindFirstChild("BuyBundleButton")
	if not (buyBundleButton and buyBundleButton:IsA("GuiButton")) then
		buyBundleButton = viewportFrame:FindFirstChild("RollButton")
	end

	self._indexRoot = indexRoot
	self._scrollingFrame = scrollingFrame
	self._setTemplate = setTemplate
	self._lockedTemplate = lockedTemplate
	self._ui = {
		openButton = openButton,
		summaryLabel = if summaryLabel and summaryLabel:IsA("TextLabel") then summaryLabel else nil,
		setNameLabel = if setNameLabel and setNameLabel:IsA("TextLabel") then setNameLabel else nil,
		pieceNameLabel = if pieceNameLabel and pieceNameLabel:IsA("TextLabel") then pieceNameLabel else nil,
		searchBox = if searchBox and searchBox:IsA("TextBox") then searchBox else nil,
		regionButtons = regionButtons,
		viewportFrame = viewportFrame,
		buyBundleButton = if buyBundleButton and buyBundleButton:IsA("GuiButton") then buyBundleButton else nil,
	}

	if self._ui.pieceNameLabel then
		self._defaultPieceNameLabelStyle = {
			fontFace = self._ui.pieceNameLabel.FontFace,
			textColor3 = self._ui.pieceNameLabel.TextColor3,
			textTransparency = self._ui.pieceNameLabel.TextTransparency,
		}
	end

	if self._ui.setNameLabel then
		self._defaultSetNameLabelStyle = {
			fontFace = self._ui.setNameLabel.FontFace,
			textColor3 = self._ui.setNameLabel.TextColor3,
			textTransparency = self._ui.setNameLabel.TextTransparency,
		}
	end

	self._setTemplate.Visible = false
	self._lockedTemplate.Visible = false
	self._scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y

	if self._ui.searchBox then
		self._searchText = self._ui.searchBox.Text
	end
end

function IndexController:_bindOpenButton(openButton: GuiButton)
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

function IndexController:_bindRegionButtons()
	for region, button in pairs(self._ui.regionButtons) do
		UIController:CreateButton(button, function()
			local selectedSummary = self:_getSelectedSummary()
			if self._selectedSetId == nil or selectedSummary == nil then
				return
			end

			if selectedSummary.discoveredPieceIdsByRegion[region] == nil then
				return
			end

			self._selectedRegion = region
			self:_syncPieceButtons()
			self:_syncDetailPanel()
		end)
	end
end

function IndexController:_bindBuyBundleButton()
	local buyBundleButton = self._ui.buyBundleButton
	if not buyBundleButton then
		return
	end

	UIController:CreateButton(buyBundleButton, function()
		local bundleId = self:_getSelectedBundleId()
		if not bundleId then
			return
		end

		if ConfirmationWarning.Prompt(self:_buildBuyBundleConfirmationMessage()) ~= true then
			return
		end

		MarketplaceService:PromptBundlePurchase(LOCAL_PLAYER, bundleId)
	end)
end

function IndexController:_ensureFullUi(playerGui: PlayerGui)
	if self._fullUiReady then
		return
	end

	self:_cacheUi(playerGui)
	self:_bindRegionButtons()
	self:_bindBuyBundleButton()

	if self._ui.searchBox then
		self._ui.searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			self._searchText = self._ui.searchBox.Text
			self:_refreshRows()
		end)
	end

	if not self._dataBindingsReady then
		DataController.DataReceived:Connect(function()
			if not FrameController:IsOpen(WINDOW_NAME) then
				return
			end
			self:_syncAll()
		end)

		DataController.DataUpdated:Connect(function(key)
			if key == BODY_PARTS_DATA_KEY then
				self:_scheduleBodyPartsRefresh()
			end
		end)

		self._dataBindingsReady = true
	end

	self._fullUiReady = true
end

function IndexController:OnStart()
	self:_ensureState()

	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	self._playerGui = playerGui
	self:_cacheOpenButton(playerGui)

	if not self._openButtonBound then
		self:_bindOpenButton(self._ui.openButton)
		self._openButtonBound = true
	end
end

return IndexController
