local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local MutationCovers = require(ReplicatedStorage.Shared.Config.MutationCovers)
local PotionConfig = require(ReplicatedStorage.Shared.Config.PotionConfig)
local SizeConfig = require(ReplicatedStorage.Shared.Config.SizeConfig)
local SizeIcons = require(ReplicatedStorage.Shared.Config.SizeIcons)
local PerfStats = require(ReplicatedStorage.Shared.Diagnostics.PerfStats)
local NumberFormatter = require(ReplicatedStorage.Shared.Formatting.NumberFormatter)
local OwnedBodyParts = require(ReplicatedStorage.Shared.Character.OwnedBodyParts)
local BodyPartLoadout = require(ReplicatedStorage.Shared.Character.BodyPartLoadout)
local BodyPartRegions = require(ReplicatedStorage.Shared.Character.BodyPartRegions)
local PreviewAppearanceRegistry = require(ReplicatedStorage.Shared.Character.PreviewAppearanceRegistry)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local AuraPresentation = require(ReplicatedStorage.Shared.UI.AuraPresentation)
local BodyPartPresentation = require(ReplicatedStorage.Shared.UI.BodyPartPresentation)
local ConfirmationWarning = require(ReplicatedStorage.Shared.UI.ConfirmationWarning)
local Notify = require(ReplicatedStorage.Shared.UI.Notify)
local PotionPresentation = require(ReplicatedStorage.Shared.UI.PotionPresentation)
local ViewportModelRenderer = require(ReplicatedStorage.Shared.UI.ViewportModelRenderer)
local DataController = require(script.Parent.DataController)
local FrameController = require(script.Parent.FrameController)
local PotionController = require(script.Parent.PotionController)
local SlotCardRenderer = require(script.Parent.SlotCardRenderer)
local UIController = require(script.Parent.UIController)

local LOCAL_PLAYER = Players.LocalPlayer
local WINDOW_NAME = "Inventory"
local BODY_PARTS_DATA_KEY = "bodyParts"
local AURA_DATA_KEY = "auras"
local EQUIPPED_AURA_ID_KEY = "equippedAuraId"
local AUTO_SIZE_ENABLED_KEY = "autoSizeEnabled"
local BODY_PARTS_REMOTES_FOLDER_NAME = "BodyParts"
local AURAS_REMOTES_FOLDER_NAME = "Auras"
local GET_STATE_REMOTE_NAME = "GetSessionLoadout"
local GET_EXISTENCE_REMOTE_NAME = "GetTotalInExistenceForPiece"
local EQUIP_REMOTE_NAME = "EquipOwnedBodyPart"
local EQUIP_BEST_REMOTE_NAME = "EquipBestLoadout"
local UNEQUIP_REMOTE_NAME = "UnequipRegion"
local SET_AUTO_SIZE_ENABLED_REMOTE_NAME = "SetAutoSizeEnabled"
local TOGGLE_FAVORITE_REMOTE_NAME = "ToggleFavoriteOwnedBodyPart"
local SELL_OWNED_REMOTE_NAME = "SellOwnedBodyPart"
local SELL_ALL_REMOTE_NAME = "SellAllUnfavoritedBodyParts"
local UPDATED_REMOTE_NAME = "LoadoutUpdated"
local AURA_GET_STATE_REMOTE_NAME = "GetAuraState"
local AURA_GET_EXISTENCE_REMOTE_NAME = "GetTotalInExistenceForAura"
local AURA_EQUIP_REMOTE_NAME = "EquipOwnedAura"
local AURA_TOGGLE_FAVORITE_REMOTE_NAME = "ToggleFavoriteOwnedAura"
local SELECTED_COLOR = Color3.fromRGB(116, 192, 255)
local EQUIPPED_COLOR = Color3.fromRGB(113, 230, 139)
local DEFAULT_OUTLINE_COLOR = Color3.fromRGB(255, 255, 255)
local INVENTORY_DEFAULT_ANCHOR_X = 0.4
local INVENTORY_PREVIEW_ANCHOR_X = 0.5
local INVENTORY_ANCHOR_Y = 0.5
local INVENTORY_ANCHOR_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local AUTO_SIZE_BUTTON_COLOR_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FILTER_ROW_REPOPULATE_STAGGER = 0.02
local FILTER_ROW_POP_TWEEN = TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FILTER_ROW_POP_START_SCALE = 0.9
local SLOT_OVERLAY_Z_INDEX = 10
local SELL_WARNING_Z_INDEX = 20
local AUTO_SIZE_DESCRIPTION_TEXT = "Makes all of your body parts normal size"

local FILTER_BUTTON_TO_REGION = {
	Heads = "Head",
	Torsos = "Torso",
	LeftArms = "LeftArm",
	RightArms = "RightArm",
	LeftLegs = "LeftLeg",
	RightLegs = "RightLeg",
}

local REGION_TO_LABEL = BodyPartPresentation.RegionToLabel
local REGION_TO_PLURAL_LABEL = BodyPartPresentation.RegionToPluralLabel
local PREVIEW_LABEL_ORDER = table.freeze({
	"Bundle",
	"Part",
	"Rarity",
	"Mutation",
	"Content",
	"Existing",
	"Cash",
	"Chance",
	"EverRolled",
})
local PREVIEW_STAT_NAMES = table.freeze({
	"Strength",
	"Speed",
	"Health",
})
local POTION_PREVIEW_VISIBLE_LABEL_ORDER = table.freeze({
	"Bundle",
	"Part",
	"Rarity",
	"Cash",
	"Chance",
})

type OwnedBodyPartRecord = {
	ownedId: string,
	pieceId: string,
	rarityDenominator: number?,
	displayOddsDenominator: number?,
	displayRarity: string?,
	rolledSetDisplayName: string?,
	mutation: string?,
	mutationId: string?,
	finalPassiveIncomePerSecond: number?,
	sizeMultiplier: number?,
	serialNumber: number?,
	isFavorite: boolean?,
}

type OwnedAuraRecord = {
	ownedId: string,
	auraId: string,
	serialNumber: number?,
	isFavorite: boolean?,
}

type OwnedPotionRecord = {
	potionId: string,
	amount: number?,
	isFavorite: boolean?,
}

type BodyPartClientState = {
	equipped: BodyPartLoadout.EquippedState?,
	ownedBodyParts: { [string]: OwnedBodyPartRecord }?,
	bonuses: {
		passiveIncomePerSecond: number?,
		luckBonus: number?,
		rollSpeedBonus: number?,
		speed: number?,
		damage: number?,
		health: number?,
		speedBonus: number?,
		damageBonus: number?,
		healthBonus: number?,
		activeSetId: string?,
	}?,
	autoSizeEnabled: boolean?,
	message: string?,
}

type AuraClientState = {
	ownedAuras: { [string]: OwnedAuraRecord }?,
	equippedAuraId: string?,
	message: string?,
}

type PreviewState = {
	itemType: "bodyPart" | "aura" | "potion",
	kind: "owned" | "equipped",
	ownedId: string?,
	region: string?,
	entry: BodyPartLoadout.LoadoutEntry?,
	auraId: string?,
	potionId: string?,
}

type InventoryRecordView = {
	ownedId: string,
	itemType: "bodyPart" | "aura" | "potion",
	record: OwnedBodyPartRecord | OwnedAuraRecord | OwnedPotionRecord,
	piece: any?,
	region: string?,
	setConfig: any?,
	auraConfig: AuraConfig.AuraConfigEntry?,
	potionConfig: any?,
	bundleModel: Model?,
	nameText: string,
	usageText: string,
	isFavorite: boolean,
	searchText: string,
	cardAccentColor: Color3?,
	baseFillColor: Color3?,
	selectedFillColor: Color3?,
	mutationCoverTexture: string?,
	previewScale: number?,
	appearanceUserId: number?,
	sizeTagStyle: any?,
	iconTexture: string?,
	preferIconOverViewport: boolean?,
}

type InventoryRecordsCacheEntry = {
	records: { InventoryRecordView },
}

type SlotPlaceholderState = {
	imageTransparency: number,
	children: {
		[string]: {
			visible: boolean,
		},
	},
}

type GuiButtonLayoutState = {
	size: UDim2,
	position: UDim2,
	anchorPoint: Vector2,
	visible: boolean,
}

type GuiObjectLayoutState = {
	size: UDim2,
	position: UDim2,
	anchorPoint: Vector2,
	visible: boolean,
}

type PreviewLabelLayouts = {
	[string]: GuiObjectLayoutState?,
}

type PreviewSecondaryActionButtonLayouts = {
	favorite: GuiButtonLayoutState?,
	sell: GuiButtonLayoutState?,
	auraFavorite: GuiButtonLayoutState?,
}

local InventoryController = {}

local function showNotification(text: string)
	Notify.Show(text, {
		channel = "inventory",
		duration = 4,
	})
end

local toRichTextColor = BodyPartPresentation.ToRichTextColor
local formatNumberish = BodyPartPresentation.FormatNumberish
local formatMoneyPerSecond = BodyPartPresentation.FormatMoneyPerSecond
local formatMultiplier = BodyPartPresentation.FormatMultiplier
local formatChance = BodyPartPresentation.FormatChance
local getSizeDescriptor = BodyPartPresentation.GetSizeDescriptor
local getRecordPassiveIncomePerSecond = BodyPartPresentation.GetRecordPassiveIncomePerSecond

local function resolveSizeTagStyle(scale: number?, sizeId: any)
	local exportedResolver = BodyPartPresentation.GetSizeTagStyle
	if typeof(exportedResolver) == "function" then
		return exportedResolver(scale, sizeId)
	end

	local sizeEntry = SizeConfig.GetByScale(scale)
	if sizeEntry == nil then
		sizeEntry = SizeConfig.Get(SizeConfig.NormalizeId(sizeId)) or SizeConfig.GetDefault()
	end

	if sizeEntry == nil or sizeEntry.id == SizeConfig.GetDefault().id then
		return nil
	end

	local style = SizeIcons[sizeEntry.id]
	if typeof(style) == "table" and typeof(style.image) == "string" and style.image ~= "" then
		return style
	end

	return nil
end

local function formatWholeNumber(value: any): string
	return NumberFormatter.Format(math.max(0, math.floor(tonumber(value) or 0)))
end

local function extractTrailingLabelText(templateText: any, fallback: string): string
	local normalized = if typeof(templateText) == "string" then string.match(templateText, "^%s*(.-)%s*$") or "" else ""
	local remainder = string.match(normalized, "^%S+%s+(.+)$")
	if typeof(remainder) == "string" and remainder ~= "" then
		return remainder
	end
	if normalized ~= "" then
		return normalized
	end
	return fallback
end

local function stripRichText(text: string): string
	return text:gsub("<[^>]->", "")
end

local function collectPreviewStatLabels(statsFrame: Instance?): { [string]: TextLabel }
	local labels = {}
	if statsFrame == nil then
		return labels
	end

	for _, descendant in ipairs(statsFrame:GetDescendants()) do
		if not descendant:IsA("TextLabel") then
			continue
		end

		local plainText = string.lower(stripRichText(descendant.Text or ""))
		if string.find(plainText, "strength", 1, true) then
			labels.Strength = descendant
		elseif string.find(plainText, "speed", 1, true) then
			labels.Speed = descendant
		elseif string.find(plainText, "health", 1, true) then
			labels.Health = descendant
		end
	end

	return labels
end

local function setGuiTreeZIndex(root: Instance, zIndex: number)
	if root:IsA("GuiObject") then
		root.ZIndex = zIndex
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = zIndex
		end
	end
end

local function shiftGuiTreeZIndex(root: Instance, delta: number)
	if delta == 0 then
		return
	end

	if root:IsA("GuiObject") then
		root.ZIndex += delta
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex += delta
		end
	end
end

local function collectSelectionCornerFrames(container: Instance?): { Frame }
	local frames = {}
	if not container then
		return frames
	end

	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("Frame") and (descendant.Name == "Corner1" or descendant.Name == "Corner2") then
			table.insert(frames, descendant)
		end
	end

	return frames
end

local function mergeTopLevelState(previousState: any, incomingState: any)
	if typeof(incomingState) ~= "table" then
		return previousState
	end

	if incomingState._isDelta ~= true or typeof(previousState) ~= "table" then
		return incomingState
	end

	local mergedState = table.clone(previousState)
	for key, value in pairs(incomingState) do
		if key ~= "_isDelta" then
			mergedState[key] = value
		end
	end

	return mergedState
end

local function captureGuiButtonLayout(button: GuiButton?): GuiButtonLayoutState?
	if not button then
		return nil
	end

	return {
		size = button.Size,
		position = button.Position,
		anchorPoint = button.AnchorPoint,
		visible = button.Visible,
	}
end

local function captureGuiObjectLayout(guiObject: GuiObject?): GuiObjectLayoutState?
	if not guiObject then
		return nil
	end

	return {
		size = guiObject.Size,
		position = guiObject.Position,
		anchorPoint = guiObject.AnchorPoint,
		visible = guiObject.Visible,
	}
end

local function applyGuiButtonLayout(button: GuiButton?, layout: GuiButtonLayoutState?)
	if not (button and layout) then
		return
	end

	button.Size = layout.size
	button.Position = layout.position
	button.AnchorPoint = layout.anchorPoint
	button.Visible = layout.visible
end

local function applyGuiObjectLayout(guiObject: GuiObject?, layout: GuiObjectLayoutState?)
	if not (guiObject and layout) then
		return
	end

	guiObject.Size = layout.size
	guiObject.Position = layout.position
	guiObject.AnchorPoint = layout.anchorPoint
	guiObject.Visible = layout.visible
end

local function capturePreviewLabelLayouts(previewLabels: { [string]: TextLabel }): PreviewLabelLayouts
	local layouts: PreviewLabelLayouts = {}

	for _, labelName in ipairs(PREVIEW_LABEL_ORDER) do
		layouts[labelName] = captureGuiObjectLayout(previewLabels[labelName])
	end

	return layouts
end

local function buildHorizontalSpanLayout(primaryLayout: GuiButtonLayoutState?, secondaryLayout: GuiButtonLayoutState?): GuiButtonLayoutState?
	if not primaryLayout then
		return nil
	end

	if not secondaryLayout then
		return primaryLayout
	end

	local primaryLeftScale = primaryLayout.position.X.Scale - primaryLayout.size.X.Scale * primaryLayout.anchorPoint.X
	local primaryLeftOffset = primaryLayout.position.X.Offset - primaryLayout.size.X.Offset * primaryLayout.anchorPoint.X
	local primaryRightScale = primaryLayout.position.X.Scale + primaryLayout.size.X.Scale * (1 - primaryLayout.anchorPoint.X)
	local primaryRightOffset = primaryLayout.position.X.Offset + primaryLayout.size.X.Offset * (1 - primaryLayout.anchorPoint.X)

	local secondaryLeftScale = secondaryLayout.position.X.Scale - secondaryLayout.size.X.Scale * secondaryLayout.anchorPoint.X
	local secondaryLeftOffset = secondaryLayout.position.X.Offset - secondaryLayout.size.X.Offset * secondaryLayout.anchorPoint.X
	local secondaryRightScale = secondaryLayout.position.X.Scale + secondaryLayout.size.X.Scale * (1 - secondaryLayout.anchorPoint.X)
	local secondaryRightOffset = secondaryLayout.position.X.Offset + secondaryLayout.size.X.Offset * (1 - secondaryLayout.anchorPoint.X)

	local leftScale = math.min(primaryLeftScale, secondaryLeftScale)
	local leftOffset = math.min(primaryLeftOffset, secondaryLeftOffset)
	local rightScale = math.max(primaryRightScale, secondaryRightScale)
	local rightOffset = math.max(primaryRightOffset, secondaryRightOffset)
	local size = UDim2.new(
		math.max(0, rightScale - leftScale),
		rightOffset - leftOffset,
		primaryLayout.size.Y.Scale,
		primaryLayout.size.Y.Offset
	)

	return {
		size = size,
		position = UDim2.new(
			leftScale + size.X.Scale * primaryLayout.anchorPoint.X,
			leftOffset + size.X.Offset * primaryLayout.anchorPoint.X,
			primaryLayout.position.Y.Scale,
			primaryLayout.position.Y.Offset
		),
		anchorPoint = primaryLayout.anchorPoint,
		visible = primaryLayout.visible,
	}
end

function InventoryController:_ensureState()
	if self._started then
		return
	end

	self._started = true
	self._playerGui = nil
	self._inventoryRoot = nil
	self._listTemplate = nil
	self._scrollingFrame = nil
	self._ui = {}
	self._remotes = {}
	self._loadoutState = nil :: BodyPartClientState?
	self._auraState = nil :: AuraClientState?
	self._selectedFilterRegion = nil :: string?
	self._selectedSpecialFilter = nil :: string?
	self._selectedOwnedId = nil :: string?
	self._previewState = nil :: PreviewState?
	self._searchText = ""
	self._rowFramesByOwnedId = {}
	self._rowButtonsByOwnedId = {}
	self._slotCardRenderer = nil
	self._slotCardButtonsByRegion = {}
	self._auraSlotCardButton = nil :: ImageButton?
	self._inventoryRecordsCache = {}
	self._inventoryRecordsDirty = true
	self._recordViewsByOwnedId = {}
	self._equippedOwnedIdByRegion = {}
	self._equippedAuraOwnedId = nil :: string?
	self._slotPlaceholderDefaults = {}
	self._auraSlotPlaceholderDefault = nil :: SlotPlaceholderState?
	self._inventoryAnchorTween = nil
	self._cachedCharacterPreviewModel = nil :: Model?
	self._isResolvingCharacterPreviewModel = false
	self._characterPreviewGeneration = 0
	self._previewExistingRequestToken = 0
	self._previewRenderKey = nil :: string?
	self._previewCountKey = nil :: string?
	self._previewExistingCountCache = {}
	self._warnedExistingCountFailure = false
	self._previewLabelFontFaces = nil
	self._previewLabelLayouts = nil :: PreviewLabelLayouts?
	self._previewStatNativeTexts = {}
	self._autoSizeDescriptionText = AUTO_SIZE_DESCRIPTION_TEXT
	self._autoSizeButtonVisualEntries = {}
	self._autoSizeButtonTweens = {}
	self._autoSizeVisualState = nil :: boolean?
	self._previewSecondaryActionButtonLayouts = nil :: PreviewSecondaryActionButtonLayouts?
	self._previewTab = "info"
	self._autoSizeStateHydrated = false
	self._auraActionInFlight = false
	self._auraActionRequestToken = 0
	self._auraStateRefreshScheduled = false
	self._pendingFilterRowAnimation = false
	self._listRowAnimationGeneration = 0
	self._listRowSequenceTweensByOwnedId = {}
	self._bodyPartRefreshScheduled = false
	self._pendingPotionSellOwnedId = nil :: string?
	self._pendingPotionSellQuantity = 1
	self._openButtonBound = false
	self._fullUiReady = false
	self._dataBindingsReady = false
end

function InventoryController:_cancelInventoryAnchorTween()
	if self._inventoryAnchorTween then
		self._inventoryAnchorTween:Cancel()
		self._inventoryAnchorTween = nil
	end
end

function InventoryController:_syncInventoryAnchor(hasPreview: boolean)
	local inventoryRoot = self._inventoryRoot
	if not inventoryRoot then
		return
	end

	local targetAnchor = Vector2.new(
		if hasPreview then INVENTORY_PREVIEW_ANCHOR_X else INVENTORY_DEFAULT_ANCHOR_X,
		INVENTORY_ANCHOR_Y
	)
	local currentAnchor = inventoryRoot.AnchorPoint
	local shouldTween = inventoryRoot.Visible
		and math.abs(currentAnchor.X - targetAnchor.X) > 0.001

	self:_cancelInventoryAnchorTween()

	if not shouldTween then
		inventoryRoot.AnchorPoint = targetAnchor
		return
	end

	self._inventoryAnchorTween = TweenService:Create(inventoryRoot, INVENTORY_ANCHOR_TWEEN, {
		AnchorPoint = targetAnchor,
	})
	self._inventoryAnchorTween:Play()
end

function InventoryController:_getOwnedLookup(): { [string]: OwnedBodyPartRecord }
	local bodyPartsState = DataController:Get(BODY_PARTS_DATA_KEY)
	if typeof(bodyPartsState) == "table" and typeof(bodyPartsState.ownedById) == "table" then
		return bodyPartsState.ownedById
	end

	local latestOwnedBodyParts = self._loadoutState and self._loadoutState.ownedBodyParts
	if typeof(latestOwnedBodyParts) == "table" then
		return latestOwnedBodyParts
	end

	return {}
end

function InventoryController:_getOwnedAuraLookup(): { [string]: OwnedAuraRecord }
	local auraState = DataController:Get(AURA_DATA_KEY)
	if typeof(auraState) == "table" and typeof(auraState.ownedById) == "table" then
		return auraState.ownedById
	end

	local latestOwnedAuras = self._auraState and self._auraState.ownedAuras
	if typeof(latestOwnedAuras) == "table" then
		return latestOwnedAuras
	end

	return {}
end

function InventoryController:_getOwnedPotionLookup(): { [string]: OwnedPotionRecord }
	return PotionController:GetOwnedPotions()
end

function InventoryController:_getEquippedAuraId(): string?
	local equippedAuraId = self._auraState and self._auraState.equippedAuraId
	if typeof(equippedAuraId) == "string" and equippedAuraId ~= "" then
		return equippedAuraId
	end

	local dataValue = DataController:Get(EQUIPPED_AURA_ID_KEY)
	if typeof(dataValue) == "string" and dataValue ~= "" then
		return dataValue
	end

	return nil
end

function InventoryController:_getBodyPartRemotesFolder(): Folder?
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotesFolder then
		return nil
	end

	local bodyPartsFolder = remotesFolder:FindFirstChild(BODY_PARTS_REMOTES_FOLDER_NAME)
	if bodyPartsFolder and bodyPartsFolder:IsA("Folder") then
		return bodyPartsFolder
	end

	return nil
end

function InventoryController:_getAuraRemotesFolder(): Folder?
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotesFolder then
		return nil
	end

	local aurasFolder = remotesFolder:FindFirstChild(AURAS_REMOTES_FOLDER_NAME)
	if aurasFolder and aurasFolder:IsA("Folder") then
		return aurasFolder
	end

	return nil
end

function InventoryController:_ensureRemotes(): boolean
	if self._remotes.getState
		and self._remotes.getExistence
		and self._remotes.equip
		and self._remotes.equipBest
		and self._remotes.unequip
		and self._remotes.setAutoSizeEnabled
		and self._remotes.toggleFavorite
		and self._remotes.sellOwned
		and self._remotes.sellAll
		and self._remotes.updated
	then
		return true
	end

	local bodyPartsFolder = self:_getBodyPartRemotesFolder()
	if not bodyPartsFolder then
		return false
	end

	local getStateRemote = bodyPartsFolder:FindFirstChild(GET_STATE_REMOTE_NAME)
	local getExistenceRemote = bodyPartsFolder:FindFirstChild(GET_EXISTENCE_REMOTE_NAME)
	local equipRemote = bodyPartsFolder:FindFirstChild(EQUIP_REMOTE_NAME)
	local equipBestRemote = bodyPartsFolder:FindFirstChild(EQUIP_BEST_REMOTE_NAME)
	local unequipRemote = bodyPartsFolder:FindFirstChild(UNEQUIP_REMOTE_NAME)
	local setAutoSizeEnabledRemote = bodyPartsFolder:FindFirstChild(SET_AUTO_SIZE_ENABLED_REMOTE_NAME)
	local toggleFavoriteRemote = bodyPartsFolder:FindFirstChild(TOGGLE_FAVORITE_REMOTE_NAME)
	local sellOwnedRemote = bodyPartsFolder:FindFirstChild(SELL_OWNED_REMOTE_NAME)
	local sellAllRemote = bodyPartsFolder:FindFirstChild(SELL_ALL_REMOTE_NAME)
	local updatedRemote = bodyPartsFolder:FindFirstChild(UPDATED_REMOTE_NAME)

	if not (getStateRemote and getStateRemote:IsA("RemoteFunction")) then
		return false
	end
	if not (getExistenceRemote and getExistenceRemote:IsA("RemoteFunction")) then
		return false
	end
	if not (equipRemote and equipRemote:IsA("RemoteFunction")) then
		return false
	end
	if not (equipBestRemote and equipBestRemote:IsA("RemoteFunction")) then
		return false
	end
	if not (unequipRemote and unequipRemote:IsA("RemoteFunction")) then
		return false
	end
	if not (setAutoSizeEnabledRemote and setAutoSizeEnabledRemote:IsA("RemoteFunction")) then
		return false
	end
	if not (toggleFavoriteRemote and toggleFavoriteRemote:IsA("RemoteFunction")) then
		return false
	end
	if not (sellOwnedRemote and sellOwnedRemote:IsA("RemoteFunction")) then
		return false
	end
	if not (sellAllRemote and sellAllRemote:IsA("RemoteFunction")) then
		return false
	end
	if not (updatedRemote and updatedRemote:IsA("RemoteEvent")) then
		return false
	end

	self._remotes.getState = getStateRemote
	self._remotes.getExistence = getExistenceRemote
	self._remotes.equip = equipRemote
	self._remotes.equipBest = equipBestRemote
	self._remotes.unequip = unequipRemote
	self._remotes.setAutoSizeEnabled = setAutoSizeEnabledRemote
	self._remotes.toggleFavorite = toggleFavoriteRemote
	self._remotes.sellOwned = sellOwnedRemote
	self._remotes.sellAll = sellAllRemote
	self._remotes.updated = updatedRemote
	return true
end

function InventoryController:_ensureAuraRemotes(): boolean
	if self._remotes.auraGetState
		and self._remotes.auraGetExistence
		and self._remotes.auraEquip
		and self._remotes.auraToggleFavorite
	then
		return true
	end

	local aurasFolder = self:_getAuraRemotesFolder()
	if not aurasFolder then
		return false
	end

	local getStateRemote = aurasFolder:FindFirstChild(AURA_GET_STATE_REMOTE_NAME)
	local getExistenceRemote = aurasFolder:FindFirstChild(AURA_GET_EXISTENCE_REMOTE_NAME)
	local equipRemote = aurasFolder:FindFirstChild(AURA_EQUIP_REMOTE_NAME)
	local toggleFavoriteRemote = aurasFolder:FindFirstChild(AURA_TOGGLE_FAVORITE_REMOTE_NAME)

	if not (getStateRemote and getStateRemote:IsA("RemoteFunction")) then
		return false
	end
	if not (getExistenceRemote and getExistenceRemote:IsA("RemoteFunction")) then
		return false
	end
	if not (equipRemote and equipRemote:IsA("RemoteFunction")) then
		return false
	end
	if not (toggleFavoriteRemote and toggleFavoriteRemote:IsA("RemoteFunction")) then
		return false
	end

	self._remotes.auraGetState = getStateRemote
	self._remotes.auraGetExistence = getExistenceRemote
	self._remotes.auraEquip = equipRemote
	self._remotes.auraToggleFavorite = toggleFavoriteRemote
	return true
end

function InventoryController:_resolvePreviewModel()
	local previewState = self._previewState
	if not previewState then
		return nil
	end

	if previewState.itemType == "aura" then
		local ownedRecord = previewState.ownedId and self:_getOwnedAuraLookup()[previewState.ownedId] or nil
		if not ownedRecord then
			return nil
		end

		return AuraPresentation.BuildPreviewPresentation({
			record = ownedRecord,
		})
	end

	if previewState.itemType == "potion" then
		local potionId = previewState.potionId or PotionController.GetPotionIdFromOwnedId(previewState.ownedId)
		local ownedRecord = potionId and self:_getOwnedPotionLookup()[potionId] or nil
		if not ownedRecord or potionId == nil then
			return nil
		end

		return PotionPresentation.BuildPreviewPresentation({
			potionId = potionId,
			record = ownedRecord,
			remainingSeconds = PotionController:GetRemainingSeconds(potionId),
			isActive = PotionController:IsActive(potionId),
		})
	end

	local ownedLookup = self:_getOwnedLookup()
	local ownedRecord = previewState.ownedId and ownedLookup[previewState.ownedId] or nil
	local entry = previewState.entry
	local pieceId = if ownedRecord then ownedRecord.pieceId else if entry then entry.pieceId else nil
	local piece = if pieceId then BodyPartsCatalog.GetPiece(pieceId) else nil
	if not piece then
		return nil
	end

	return BodyPartPresentation.BuildPreviewPresentation({
		record = ownedRecord,
		entry = entry,
		piece = piece,
		scale = if entry and typeof(entry.scale) == "number" then entry.scale else ownedRecord and ownedRecord.sizeMultiplier or 1,
	})
end

function InventoryController:_setExistingPreviewText(text: string)
	self._ui.previewLabels.Existing.Text = text
end

function InventoryController:_setEverRolledPreviewText(leadingText: string?)
	local everRolledLabel = self._ui.previewLabels.EverRolled
	if not (everRolledLabel and everRolledLabel:IsA("TextLabel")) then
		return
	end

	if typeof(leadingText) ~= "string" or leadingText == "" then
		everRolledLabel.Text = self._previewEverRolledNativeText or everRolledLabel.Text
		return
	end

	local suffixText = self._previewEverRolledSuffixText or extractTrailingLabelText(self._previewEverRolledNativeText, "Ever Rolled")
	everRolledLabel.Text = if suffixText ~= ""
		then string.format("%s %s", leadingText, suffixText)
		else leadingText
end

function InventoryController:_applyPreviewLabelStyles(previewModel: any?)
	local defaultFontFaces = self._previewLabelFontFaces
	local previewLabels = self._ui.previewLabels
	if not (defaultFontFaces and previewLabels) then
		return
	end

	local bundleLabel = previewLabels.Bundle
	if bundleLabel and bundleLabel:IsA("TextLabel") then
		bundleLabel.FontFace = if previewModel and typeof(previewModel.bundleFontFace) == "Font"
			then previewModel.bundleFontFace
			else defaultFontFaces.Bundle
	end

	local rarityLabel = previewLabels.Rarity
	if rarityLabel and rarityLabel:IsA("TextLabel") then
		rarityLabel.FontFace = if previewModel and typeof(previewModel.rarityFontFace) == "Font"
			then previewModel.rarityFontFace
			else defaultFontFaces.Rarity
	end
end

function InventoryController:_syncPreviewLabelLayout(itemType: string?)
	local previewLabels = self._ui.previewLabels
	local defaultLayouts = self._previewLabelLayouts
	if not (previewLabels and defaultLayouts) then
		return
	end

	if itemType ~= "potion" then
		for _, labelName in ipairs(PREVIEW_LABEL_ORDER) do
			applyGuiObjectLayout(previewLabels[labelName], defaultLayouts[labelName])
		end
		return
	end

	for orderIndex, labelName in ipairs(POTION_PREVIEW_VISIBLE_LABEL_ORDER) do
		local label = previewLabels[labelName]
		local targetSlotName = PREVIEW_LABEL_ORDER[orderIndex]
		local targetLayout = if targetSlotName then defaultLayouts[targetSlotName] else nil
		if label and targetLayout then
			applyGuiObjectLayout(label, targetLayout)
			label.Visible = true
		end
	end

	for _, labelName in ipairs(PREVIEW_LABEL_ORDER) do
		if table.find(POTION_PREVIEW_VISIBLE_LABEL_ORDER, labelName) == nil then
			local label = previewLabels[labelName]
			local defaultLayout = defaultLayouts[labelName]
			if label and defaultLayout then
				applyGuiObjectLayout(label, defaultLayout)
				label.Visible = false
			end
		end
	end
end

function InventoryController:_warnExistingCountFailure(message: string)
	if self._warnedExistingCountFailure then
		return
	end

	self._warnedExistingCountFailure = true
	warn(string.format("[InventoryController] Failed to load existing count: %s", tostring(message)))
end

function InventoryController:_requestBodyPartExistingCount(pieceId: string, requestToken: number)
	local cacheKey = string.format("bodyPart:%s", pieceId)
	local cachedCount = self._previewExistingCountCache[cacheKey]
	if cachedCount ~= nil then
		if requestToken == self._previewExistingRequestToken then
			self:_setExistingPreviewText(string.format("Existing: %s", formatWholeNumber(cachedCount)))
		end
		return
	end

	if not self:_ensureRemotes() then
		self:_warnExistingCountFailure("Body part remotes are not ready.")
		if requestToken == self._previewExistingRequestToken then
			self:_setExistingPreviewText("Existing: N/A")
		end
		return
	end

	local ok, result = pcall(function()
		return self._remotes.getExistence:InvokeServer({
			pieceId = pieceId,
		})
	end)

	if requestToken ~= self._previewExistingRequestToken then
		return
	end

	if not ok then
		self:_warnExistingCountFailure(result)
		self:_setExistingPreviewText("Existing: N/A")
		return
	end

	if typeof(result) ~= "table" or result.ok ~= true then
		self:_warnExistingCountFailure(if typeof(result) == "table" then result.message else "Invalid server response.")
		self:_setExistingPreviewText("Existing: N/A")
		return
	end

	local count = tonumber(result.count)
	if count == nil then
		self:_warnExistingCountFailure("Missing or invalid count in server response.")
		self:_setExistingPreviewText("Existing: N/A")
		return
	end

	self._previewExistingCountCache[cacheKey] = count
	self:_setExistingPreviewText(string.format("Existing: %s", formatWholeNumber(count)))
end

function InventoryController:_requestAuraExistingCount(auraId: string, requestToken: number)
	local cacheKey = string.format("aura:%s", auraId)
	local cachedCount = self._previewExistingCountCache[cacheKey]
	if cachedCount ~= nil then
		if requestToken == self._previewExistingRequestToken then
			self:_setExistingPreviewText(string.format("Existing: %s", formatWholeNumber(cachedCount)))
		end
		return
	end

	if not self:_ensureAuraRemotes() then
		self:_warnExistingCountFailure("Aura remotes are not ready.")
		if requestToken == self._previewExistingRequestToken then
			self:_setExistingPreviewText("Existing: N/A")
		end
		return
	end

	local ok, result = pcall(function()
		return self._remotes.auraGetExistence:InvokeServer({
			auraId = auraId,
		})
	end)

	if requestToken ~= self._previewExistingRequestToken then
		return
	end

	if not ok then
		self:_warnExistingCountFailure(result)
		self:_setExistingPreviewText("Existing: N/A")
		return
	end

	if typeof(result) ~= "table" or result.ok ~= true then
		self:_warnExistingCountFailure(if typeof(result) == "table" then result.message else "Invalid server response.")
		self:_setExistingPreviewText("Existing: N/A")
		return
	end

	local count = tonumber(result.count)
	if count == nil then
		self:_warnExistingCountFailure("Missing or invalid count in aura server response.")
		self:_setExistingPreviewText("Existing: N/A")
		return
	end

	self._previewExistingCountCache[cacheKey] = count
	self:_setExistingPreviewText(string.format("Existing: %s", formatWholeNumber(count)))
end

function InventoryController:_setPreviewState(previewState: PreviewState?)
	self._previewState = previewState
	if previewState == nil then
		self:_setPreviewTab("info")
	end
	if self._ui.potionSellFrame and self._ui.potionSellFrame.Visible and self._pendingPotionSellOwnedId ~= (previewState and previewState.ownedId or nil) then
		self:_setPotionSellModalVisible(false)
	end
	self:_syncPreview()
	self:_syncSlotButtons()
	self:_syncSecondaryActionButtons()
end

function InventoryController:_setPreviewTab(tabName: string?)
	local resolvedTab = if tabName == "stats" then "stats" else "info"
	self._previewTab = resolvedTab

	local infoFrame = self._ui.infoFrame
	local statsFrame = self._ui.statsFrame
	if not (infoFrame and statsFrame) then
		return
	end

	infoFrame.Visible = resolvedTab == "info"
	statsFrame.Visible = resolvedTab == "stats"
end

function InventoryController:_clearPreview()
	self._selectedOwnedId = nil
	self:_setPreviewState(nil)
	self:_syncList()
	self:_syncActionButton()
end

function InventoryController:_setSelectedOwnedItem(ownedId: string)
	self._selectedOwnedId = ownedId
	local itemType = "bodyPart"
	if string.find(ownedId, "aura_", 1, true) == 1 then
		itemType = "aura"
	elseif PotionController.IsPotionOwnedId(ownedId) then
		itemType = "potion"
	end

	if itemType == "bodyPart" then
		local equippedRegion = self:_getEquippedRegionForOwnedId(ownedId)
		local equipped = self._loadoutState and self._loadoutState.equipped
		local entry = equippedRegion and equipped and equipped[equippedRegion] or nil
		if equippedRegion and entry and entry.ownedId == ownedId then
			self:_setPreviewState({
				itemType = "bodyPart",
				kind = "equipped",
				ownedId = ownedId,
				region = equippedRegion,
				entry = entry,
			})
			self:_syncList()
			self:_syncActionButton()
			return
		end
	end

	self:_setPreviewState({
		itemType = itemType,
		kind = "owned",
		ownedId = ownedId,
		potionId = if itemType == "potion" then PotionController.GetPotionIdFromOwnedId(ownedId) else nil,
	})
	self:_syncList()
	self:_syncActionButton()
end

function InventoryController:_setPreviewForRegion(region: string)
	local equipped = self._loadoutState and self._loadoutState.equipped
	local entry = equipped and equipped[region]
	self._selectedOwnedId = nil

	if entry then
		self:_setPreviewState({
			itemType = "bodyPart",
			kind = "equipped",
			ownedId = entry.ownedId,
			region = region,
			entry = entry,
		})
	else
		self:_setPreviewState(nil)
	end

	self:_syncList()
	self:_syncActionButton()
end

function InventoryController:_setPreviewForAura()
	local equippedAuraId = self:_getEquippedAuraId()
	local ownedLookup = self:_getOwnedAuraLookup()
	local equippedOwnedId = self._equippedAuraOwnedId
	self._selectedOwnedId = nil

	if equippedAuraId and equippedOwnedId and ownedLookup[equippedOwnedId] ~= nil then
		self:_setPreviewState({
			itemType = "aura",
			kind = "equipped",
			ownedId = equippedOwnedId,
			auraId = equippedAuraId,
		})
	else
		self:_setPreviewState(nil)
	end

	self:_syncList()
	self:_syncActionButton()
end

function InventoryController:_getAuraPreviewActionRequest(): (string?, string?)
	local previewState = self._previewState
	if not (previewState and previewState.itemType == "aura") then
		return nil, nil
	end

	if previewState.kind == "equipped" then
		return "unequip", nil
	end

	local ownedId = if typeof(previewState.ownedId) == "string" and previewState.ownedId ~= ""
		then previewState.ownedId
		else self._selectedOwnedId
	if typeof(ownedId) ~= "string" or ownedId == "" then
		return nil, nil
	end

	local ownedRecord = self:_getOwnedAuraLookup()[ownedId]
	if not ownedRecord then
		return nil, nil
	end

	if self:_getEquippedAuraId() == ownedRecord.auraId then
		return "unequip", nil
	end

	return "equip", ownedId
end

function InventoryController:_getEquippedRegionForOwnedId(ownedId: string): string?
	for region, equippedOwnedId in pairs(self._equippedOwnedIdByRegion) do
		if equippedOwnedId == ownedId then
			return region
		end
	end

	return nil
end

function InventoryController:_isBodyPartCardSelected(ownedId: string): boolean
	local previewState = self._previewState
	if previewState and previewState.itemType == "bodyPart" then
		if previewState.kind == "equipped" then
			local equippedRegion = self:_getEquippedRegionForOwnedId(ownedId)
			return equippedRegion ~= nil and previewState.region == equippedRegion
		end

		if previewState.kind == "owned" and self._selectedOwnedId ~= nil then
			return ownedId == self._selectedOwnedId
		end
	end

	return ownedId == self._selectedOwnedId
end

function InventoryController:_populateRowButtonForRecord(recordView: InventoryRecordView, isSelected: boolean?)
	local base = self._rowButtonsByOwnedId[recordView.ownedId]
	self:_populateCardButtonForRecord(base, recordView, isSelected)
end

function InventoryController:_isRecordViewEquipped(recordView: InventoryRecordView): boolean
	if recordView.itemType == "bodyPart" then
		return self:_isOwnedIdEquipped(recordView.ownedId)
	end

	if recordView.itemType == "aura" then
		return self._equippedAuraOwnedId ~= nil and recordView.ownedId == self._equippedAuraOwnedId
	end

	return false
end

function InventoryController:_buildCardPayloadForRecord(recordView: InventoryRecordView): any
	return {
		nameText = recordView.nameText,
		usageText = recordView.usageText,
		bundleModel = recordView.bundleModel,
		region = recordView.region,
		previewScale = recordView.previewScale,
		appearanceUserId = recordView.appearanceUserId,
		favoriteVisible = recordView.isFavorite,
		equippedVisible = self:_isRecordViewEquipped(recordView),
		cardAccentColor = recordView.cardAccentColor,
		baseFillColor = recordView.baseFillColor,
		selectedFillColor = recordView.selectedFillColor,
		mutationCoverTexture = recordView.mutationCoverTexture,
		sizeTagStyle = recordView.sizeTagStyle,
		iconTexture = recordView.iconTexture,
		preferIconOverViewport = recordView.preferIconOverViewport,
	}
end

function InventoryController:_populateCardButtonForRecord(base: ImageButton?, recordView: InventoryRecordView, isSelected: boolean?)
	if not base then
		return
	end

	local payload = self:_buildCardPayloadForRecord(recordView)
	payload.isSelected = isSelected == true
	BodyPartPresentation.PopulateBundleCard(base, payload)
end

local function resolveMutationCoverTexture(record: OwnedBodyPartRecord): string?
	local mutationValue = record.mutationId
	if typeof(mutationValue) ~= "string" or mutationValue == "" then
		mutationValue = record.mutation
	end

	local mutationId = MutationConfig.NormalizeId(mutationValue)
	local mutationCoverTexture = MutationCovers[mutationId]
	if typeof(mutationCoverTexture) == "string" and mutationCoverTexture ~= "" then
		return mutationCoverTexture
	end

	return nil
end

function InventoryController:_populateRowButtonByOwnedId(ownedId: string, isSelected: boolean?)
	local recordView = self._recordViewsByOwnedId[ownedId]
	if not recordView then
		return
	end

	self:_populateRowButtonForRecord(recordView, isSelected)
end

function InventoryController:_getInventoryRecords(): { InventoryRecordView }
	local cacheEntry: InventoryRecordsCacheEntry? = self._inventoryRecordsCache
	if not self._inventoryRecordsDirty and cacheEntry then
		return cacheEntry.records
	end

	local records = {}
	local itemTypeOrder = {
		bodyPart = 1,
		aura = 2,
		potion = 3,
	}

	for ownedId, record in pairs(self:_getOwnedLookup()) do
		if typeof(record) ~= "table" then
			continue
		end

		local piece = record.pieceId and BodyPartsCatalog.GetPiece(record.pieceId)
		if not piece then
			continue
		end

		local setConfig = BodyPartsCatalog.GetSetForPiece(piece.id)
		local rarityStyle = BodyPartPresentation.ResolveBodyPartRarityStyle({
			record = record,
			piece = piece,
			setConfig = setConfig,
		}) or {}
		local searchText = string.lower(
			string.format(
				"%s %s",
				tostring(piece.displayName or ""),
				tostring(setConfig and setConfig.displayName or "")
			)
		)

		table.insert(records, {
			ownedId = ownedId,
			itemType = "bodyPart",
			record = record,
			piece = piece,
			region = piece.region,
			setConfig = setConfig,
			auraConfig = nil,
			potionConfig = nil,
			bundleModel = BodyPartsCatalog.ResolveBundleModel(piece.id),
			nameText = BodyPartPresentation.FormatInventoryNameText(piece.displayName, record),
			usageText = formatMoneyPerSecond(getRecordPassiveIncomePerSecond(record, piece)),
			isFavorite = record.isFavorite == true,
			searchText = searchText,
			cardAccentColor = rarityStyle.accentColor,
			baseFillColor = rarityStyle.baseFillColor,
			selectedFillColor = rarityStyle.selectedFillColor,
			mutationCoverTexture = resolveMutationCoverTexture(record),
			previewScale = record.sizeMultiplier or 1,
			appearanceUserId = LOCAL_PLAYER and LOCAL_PLAYER.UserId or nil,
			sizeTagStyle = resolveSizeTagStyle(record.sizeMultiplier, record.sizeId),
			iconTexture = nil,
			preferIconOverViewport = false,
		})
	end

	for ownedId, record in pairs(self:_getOwnedAuraLookup()) do
		if typeof(record) ~= "table" then
			continue
		end

		local auraConfig = record.auraId and AuraConfig.Get(record.auraId) or nil
		if not auraConfig then
			continue
		end

		local previewPresentation = AuraPresentation.BuildPreviewPresentation({
			record = record,
			auraConfig = auraConfig,
		})
		local searchSetName = ""
		if previewPresentation and previewPresentation.auraConfig and typeof(previewPresentation.auraConfig.setId) == "string" then
			local setConfig = BodyPartsCatalog.GetSet(previewPresentation.auraConfig.setId)
			if setConfig and typeof(setConfig.displayName) == "string" then
				searchSetName = setConfig.displayName
			end
		end
		table.insert(records, {
			ownedId = ownedId,
			itemType = "aura",
			record = record,
			piece = nil,
			setConfig = nil,
			auraConfig = auraConfig,
			potionConfig = nil,
			bundleModel = previewPresentation and previewPresentation.bundleModel or nil,
			nameText = if previewPresentation and typeof(previewPresentation.cardNameText) == "string"
				then previewPresentation.cardNameText
				else auraConfig.label,
			usageText = if previewPresentation then previewPresentation.cardUsageText else auraConfig.tierLabel,
			isFavorite = record.isFavorite == true,
			searchText = string.lower(
				string.format(
					"%s %s %s %s",
					tostring(auraConfig.label),
					tostring(auraConfig.description),
					tostring(auraConfig.tierLabel),
					tostring(searchSetName)
				)
			),
			cardAccentColor = if previewPresentation then previewPresentation.cardAccentColor else nil,
			baseFillColor = if previewPresentation then previewPresentation.baseFillColor else nil,
			selectedFillColor = if previewPresentation then previewPresentation.selectedFillColor else nil,
			mutationCoverTexture = nil,
			sizeTagStyle = nil,
			iconTexture = if previewPresentation then previewPresentation.iconTexture else nil,
			preferIconOverViewport = true,
		})
	end

	for potionId, record in pairs(self:_getOwnedPotionLookup()) do
		if typeof(record) ~= "table" then
			continue
		end

		local potionConfig = PotionConfig.Get(potionId)
		if not potionConfig then
			continue
		end

		local ownedId = PotionController.BuildOwnedId(potionConfig.id)
		if ownedId == nil then
			continue
		end

		local previewPresentation = PotionPresentation.BuildPreviewPresentation({
			potionId = potionConfig.id,
			record = record,
			remainingSeconds = PotionController:GetRemainingSeconds(potionConfig.id),
			isActive = PotionController:IsActive(potionConfig.id),
		})
		local isActive = PotionController:IsActive(potionConfig.id)
		local usageText = string.format("x%s", formatWholeNumber(record.amount))
		if isActive then
			usageText = string.format("%s ACTIVE", usageText)
		end

		table.insert(records, {
			ownedId = ownedId,
			itemType = "potion",
			record = record,
			piece = nil,
			setConfig = nil,
			auraConfig = nil,
			potionConfig = potionConfig,
			bundleModel = previewPresentation and previewPresentation.bundleModel or nil,
			nameText = potionConfig.label,
			usageText = usageText,
			isFavorite = record.isFavorite == true,
			searchText = string.lower(
				string.format(
					"%s %s %s",
					tostring(potionConfig.label),
					tostring(previewPresentation and previewPresentation.partText or ""),
					tostring(previewPresentation and previewPresentation.sizeText or "")
				)
			),
			cardAccentColor = if isActive then Color3.fromRGB(255, 223, 94) else nil,
			baseFillColor = nil,
			selectedFillColor = nil,
			mutationCoverTexture = nil,
			sizeTagStyle = nil,
			iconTexture = nil,
			preferIconOverViewport = false,
		})
	end

	table.sort(records, function(a, b)
		if a.isFavorite ~= b.isFavorite then
			return a.isFavorite == true
		end

		if a.itemType ~= b.itemType then
			return (itemTypeOrder[a.itemType] or math.huge) < (itemTypeOrder[b.itemType] or math.huge)
		end

		if a.itemType == "aura" and b.itemType == "aura" then
			local sortOrderA = a.auraConfig and a.auraConfig.sortOrder or math.huge
			local sortOrderB = b.auraConfig and b.auraConfig.sortOrder or math.huge
			if sortOrderA ~= sortOrderB then
				return sortOrderA < sortOrderB
			end
			local serialA = tonumber((a.record :: any).serialNumber) or math.huge
			local serialB = tonumber((b.record :: any).serialNumber) or math.huge
			if serialA ~= serialB then
				return serialA < serialB
			end
			return a.ownedId < b.ownedId
		end

		if a.itemType == "potion" and b.itemType == "potion" then
			local sortOrderA = a.potionConfig and a.potionConfig.sortOrder or math.huge
			local sortOrderB = b.potionConfig and b.potionConfig.sortOrder or math.huge
			if sortOrderA ~= sortOrderB then
				return sortOrderA < sortOrderB
			end
			return a.ownedId < b.ownedId
		end

		local passiveIncomeA = getRecordPassiveIncomePerSecond(a.record, a.piece)
		local passiveIncomeB = getRecordPassiveIncomePerSecond(b.record, b.piece)
		if passiveIncomeA ~= passiveIncomeB then
			return passiveIncomeA > passiveIncomeB
		end
		if a.piece.displayName ~= b.piece.displayName then
			return a.piece.displayName < b.piece.displayName
		end
		return a.ownedId < b.ownedId
	end)

	self._inventoryRecordsCache = {
		records = records,
	}
	self._inventoryRecordsDirty = false

	return records
end

function InventoryController:_markInventoryRecordsDirty()
	self._inventoryRecordsDirty = true
	self._inventoryRecordsCache = nil
	self._previewCountKey = nil
	table.clear(self._previewExistingCountCache)
end

function InventoryController:_getVisibleRecords(): { InventoryRecordView }
	local visibleRecords = {}

	for _, record in ipairs(self:_getInventoryRecords()) do
		if self:_recordMatchesFilters(record) then
			table.insert(visibleRecords, record)
		end
	end

	return visibleRecords
end

function InventoryController:_recordMatchesFilters(record: InventoryRecordView): boolean
	local searchText = string.lower(self._searchText or "")
	local selectedFilterRegion = self._selectedFilterRegion
	local selectedSpecialFilter = self._selectedSpecialFilter

	if selectedSpecialFilter ~= nil then
		if record.itemType ~= selectedSpecialFilter then
			return false
		end
	else
		if selectedFilterRegion then
			if record.itemType ~= "bodyPart" then
				return false
			end
			if record.piece.region ~= selectedFilterRegion then
				return false
			end
		end
	end

	if searchText ~= "" and not string.find(record.searchText, searchText, 1, true) then
		return false
	end

	return true
end

function InventoryController:_rebuildEquippedOwnedIdByRegion()
	self._equippedOwnedIdByRegion = {}
	self._equippedAuraOwnedId = nil

	local equipped = self._loadoutState and self._loadoutState.equipped or nil
	for _, region in ipairs(BodyPartRegions.Order) do
		local entry = equipped and equipped[region]
		if typeof(entry) == "table" and typeof(entry.ownedId) == "string" and entry.ownedId ~= "" then
			self._equippedOwnedIdByRegion[region] = entry.ownedId
		end
	end

	local equippedAuraId = self:_getEquippedAuraId()
	if equippedAuraId then
		for ownedId, record in pairs(self:_getOwnedAuraLookup()) do
			if record.auraId == equippedAuraId then
				self._equippedAuraOwnedId = ownedId
				break
			end
		end
	end
end

function InventoryController:_isOwnedIdEquipped(ownedId: string): boolean
	for _, equippedOwnedId in pairs(self._equippedOwnedIdByRegion) do
		if equippedOwnedId == ownedId then
			return true
		end
	end

	return false
end

function InventoryController:_captureSlotPlaceholderState(button: ImageButton): SlotPlaceholderState
	local children = {}

	for _, child in ipairs(button:GetChildren()) do
		if child:IsA("GuiObject") then
			children[child.Name] = {
				visible = child.Visible,
			}
		end
	end

	return {
		imageTransparency = button.ImageTransparency,
		children = children,
	}
end

function InventoryController:_syncSlotPlaceholder(region: string, isFilled: boolean)
	local button = self._ui.slotButtons[region]
	local defaults = self._slotPlaceholderDefaults[region]
	if not (button and defaults) then
		return
	end

	if isFilled then
		button.ImageTransparency = 1

		for _, childName in ipairs({ "Icon", "Usage", "Viewport" }) do
			local child = button:FindFirstChild(childName)
			if child and child:IsA("GuiObject") then
				child.Visible = false
			end
		end

		local outline = button:FindFirstChild("Outline")
		if outline and outline:IsA("GuiObject") then
			outline.Visible = true
		end
		return
	end

	button.ImageTransparency = defaults.imageTransparency

	for childName, childState in pairs(defaults.children) do
		local child = button:FindFirstChild(childName)
		if child and child:IsA("GuiObject") then
			child.Visible = childState.visible
		end
	end
end

function InventoryController:_ensureRowForRecord(recordView: InventoryRecordView): Frame?
	local row = self._rowFramesByOwnedId[recordView.ownedId]

	if not row then
		row = self._listTemplate:Clone()
		row.Name = string.format("Owned_%s", recordView.ownedId)
		row.Visible = true
		self._rowFramesByOwnedId[recordView.ownedId] = row

		local base = row:FindFirstChild("Base")
		if base and base:IsA("ImageButton") then
			UIController:CreateButton(base, function()
				self:_setSelectedOwnedItem(recordView.ownedId)
			end)
			self._rowButtonsByOwnedId[recordView.ownedId] = base
		end
	end

	self:_populateRowButtonForRecord(recordView, self:_isBodyPartCardSelected(recordView.ownedId))

	return row
end

function InventoryController:_destroyRow(ownedId: string)
	local row = self._rowFramesByOwnedId[ownedId]
	if row then
		row:Destroy()
	end

	self._rowFramesByOwnedId[ownedId] = nil
	self._rowButtonsByOwnedId[ownedId] = nil
end

function InventoryController:_cancelPendingListRowSequence()
	self._listRowAnimationGeneration += 1

	for ownedId, tween in pairs(self._listRowSequenceTweensByOwnedId) do
		if tween then
			tween:Cancel()
		end

		local row = self._rowFramesByOwnedId[ownedId]
		local rowScale = row and row:FindFirstChild("SequenceScale")
		if rowScale and rowScale:IsA("UIScale") then
			rowScale.Scale = 1
		end
	end

	self._listRowSequenceTweensByOwnedId = {}
end

function InventoryController:_getOrCreateListRowSequenceScale(row: Frame): UIScale
	local rowScale = row:FindFirstChild("SequenceScale")
	if rowScale and rowScale:IsA("UIScale") then
		return rowScale
	end

	rowScale = Instance.new("UIScale")
	rowScale.Name = "SequenceScale"
	rowScale.Scale = 1
	rowScale.Parent = row
	return rowScale
end

function InventoryController:_hideAllListRows()
	for ownedId in pairs(self._rowFramesByOwnedId) do
		self:_hideRow(ownedId)
	end
end

function InventoryController:_playFilterRowRepopulateSequence(visibleRecords: { InventoryRecordView })
	self:_cancelPendingListRowSequence()

	if #visibleRecords == 0 then
		return
	end

	local generation = self._listRowAnimationGeneration

	for index, recordView in ipairs(visibleRecords) do
		local ownedId = recordView.ownedId
		local delayTime = FILTER_ROW_REPOPULATE_STAGGER * (index - 1)

		task.delay(delayTime, function()
			if self._listRowAnimationGeneration ~= generation then
				return
			end

			if self._recordViewsByOwnedId[ownedId] == nil then
				return
			end

			self:_mountRowToList(ownedId, index)
			local isSelected = self:_isBodyPartCardSelected(ownedId)
			self:_populateRowButtonByOwnedId(ownedId, isSelected)

			local row = self._rowFramesByOwnedId[ownedId]
			local button = self._rowButtonsByOwnedId[ownedId]
			if button then
				self:_setOutlineColor(button, if isSelected then SELECTED_COLOR else DEFAULT_OUTLINE_COLOR, if isSelected then 0 else 0.22)
			end

			if row then
				local rowScale = self:_getOrCreateListRowSequenceScale(row)
				rowScale.Scale = FILTER_ROW_POP_START_SCALE

				local existingTween = self._listRowSequenceTweensByOwnedId[ownedId]
				if existingTween then
					existingTween:Cancel()
				end

				local tween = TweenService:Create(rowScale, FILTER_ROW_POP_TWEEN, {
					Scale = 1,
				})
				self._listRowSequenceTweensByOwnedId[ownedId] = tween
				tween.Completed:Connect(function()
					if self._listRowSequenceTweensByOwnedId[ownedId] == tween then
						self._listRowSequenceTweensByOwnedId[ownedId] = nil
					end
				end)
				tween:Play()
			end
		end)
	end
end

function InventoryController:_consumePendingFilterRowAnimation(): boolean
	if self._pendingFilterRowAnimation ~= true then
		return false
	end

	self._pendingFilterRowAnimation = false
	return true
end

function InventoryController:_renderMountedSlotCard(
	slotKey: string,
	slotHost: GuiObject?,
	callback: () -> (),
	recordView: InventoryRecordView,
	isSelected: boolean?
): ImageButton?
	if not (slotHost and self._slotCardRenderer) then
		return nil
	end

	local payload = self:_buildCardPayloadForRecord(recordView)
	payload.equippedVisible = false

	return self._slotCardRenderer:Render(
		slotKey,
		slotHost,
		callback,
		payload,
		isSelected == true
	)
end

function InventoryController:_hideMountedSlotCard(slotKey: string)
	if not self._slotCardRenderer then
		return
	end

	self._slotCardRenderer:Hide(slotKey)
end

function InventoryController:_hideRow(ownedId: string)
	local row = self._rowFramesByOwnedId[ownedId]
	if not row then
		return
	end

	row.Visible = false
	row.Parent = nil
end

function InventoryController:_mountRowToList(ownedId: string, layoutOrder: number)
	local row = self._rowFramesByOwnedId[ownedId]
	if not row then
		return
	end

	row.AnchorPoint = self._listTemplate.AnchorPoint
	row.Position = self._listTemplate.Position
	row.Size = self._listTemplate.Size
	row.LayoutOrder = layoutOrder
	row.Visible = true
	row.Parent = self._scrollingFrame
end

function InventoryController:_mountRowToSlot(ownedId: string, region: string)
	local row = self._rowFramesByOwnedId[ownedId]
	local slotFrame = self._ui.slotFrames[region]
	if not (row and slotFrame) then
		return
	end

	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.fromScale(0.5, 0.5)
	row.Size = UDim2.fromScale(1.2, 1.2)
	row.LayoutOrder = 0
	row.Visible = true
	row.Parent = slotFrame
end

function InventoryController:_mountRowToAuraSlot(ownedId: string)
	local row = self._rowFramesByOwnedId[ownedId]
	local slotFrame = self._ui.auraSlotFrame
	if not (row and slotFrame) then
		return
	end

	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.fromScale(0.5, 0.5)
	row.Size = UDim2.fromScale(1.2, 1.2)
	row.LayoutOrder = 0
	row.Visible = true
	row.Parent = slotFrame
end

function InventoryController:_syncRowSelectionStates()
	for ownedId, button in pairs(self._rowButtonsByOwnedId) do
		local isSelected = self:_isBodyPartCardSelected(ownedId)
		self:_populateRowButtonByOwnedId(ownedId, isSelected)
		self:_setOutlineColor(button, if isSelected then SELECTED_COLOR else DEFAULT_OUTLINE_COLOR, if isSelected then 0 else 0.22)
	end
end

function InventoryController:_setOutlineColor(button: GuiButton, color: Color3, transparency: number)
	local outline = button:FindFirstChild("Outline")
	if outline and outline:IsA("ImageLabel") then
		outline.ImageColor3 = color
		outline.ImageTransparency = transparency
	end
end

function InventoryController:_captureAutoSizeButtonVisualEntries(button: GuiButton, label: TextLabel?): { [number]: any }
	local entries = {}

	local function addEntry(instance: Instance?, propertyName: string)
		if not instance then
			return
		end

		local ok, value = pcall(function()
			return (instance :: any)[propertyName]
		end)
		if not ok or typeof(value) ~= "Color3" then
			return
		end

		table.insert(entries, {
			instance = instance,
			propertyName = propertyName,
			offColor = value,
		})
	end

	addEntry(button, "ImageColor3")
	addEntry(button:FindFirstChild("Outline"), "ImageColor3")
	addEntry(button:FindFirstChild("Cover"), "ImageColor3")
	addEntry(button:FindFirstChild("Icon"), "ImageColor3")
	addEntry(label, "TextColor3")

	for _, frame in ipairs(collectSelectionCornerFrames(button:FindFirstChild("SelectionCorners"))) do
		addEntry(frame, "BackgroundColor3")
	end

	if label then
		for _, frame in ipairs(collectSelectionCornerFrames(label:FindFirstChild("SelectionCorners"))) do
			addEntry(frame, "BackgroundColor3")
		end
	end

	return entries
end

function InventoryController:_getAutoSizeEnabled(): boolean
	return DataController:Get(AUTO_SIZE_ENABLED_KEY) == true
end

function InventoryController:_getResolvedAutoSizeEnabled(overrideEnabled: boolean?): boolean
	if overrideEnabled ~= nil then
		return overrideEnabled == true
	end

	local loadoutState = self._loadoutState
	if typeof(loadoutState) == "table" and loadoutState.autoSizeEnabled ~= nil then
		return loadoutState.autoSizeEnabled == true
	end

	return self:_getAutoSizeEnabled()
end

function InventoryController:_getResolvedNormalSizeEnabled(overrideAutoSizeEnabled: boolean?): boolean
	return not self:_getResolvedAutoSizeEnabled(overrideAutoSizeEnabled)
end

function InventoryController:_setAutoSizeButtonVisualState(isEnabled: boolean, shouldAnimate: boolean?)
	local entries = self._autoSizeButtonVisualEntries
	if typeof(entries) ~= "table" or #entries == 0 then
		self._autoSizeVisualState = isEnabled
		return
	end

	if self._autoSizeVisualState == isEnabled then
		return
	end

	for _, entry in ipairs(entries) do
		local instance = entry.instance
		local propertyName = entry.propertyName
		local offColor = entry.offColor
		local targetColor = if isEnabled then EQUIPPED_COLOR else offColor
		if typeof(targetColor) ~= "Color3" then
			continue
		end

		local currentColor = nil
		local ok, value = pcall(function()
			return (instance :: any)[propertyName]
		end)
		if ok and typeof(value) == "Color3" then
			currentColor = value
		end

		if currentColor == targetColor then
			continue
		end

		local existingTween = self._autoSizeButtonTweens[instance]
		if existingTween then
			existingTween:Cancel()
			self._autoSizeButtonTweens[instance] = nil
		end

		if shouldAnimate == true then
			local tween = TweenService:Create(instance, AUTO_SIZE_BUTTON_COLOR_TWEEN, {
				[propertyName] = targetColor,
			})
			self._autoSizeButtonTweens[instance] = tween
			tween.Completed:Connect(function()
				if self._autoSizeButtonTweens[instance] == tween then
					self._autoSizeButtonTweens[instance] = nil
				end
			end)
			tween:Play()
		else
			pcall(function()
				(instance :: any)[propertyName] = targetColor
			end)
		end
	end

	self._autoSizeVisualState = isEnabled
end

function InventoryController:_syncAutoSizeButton(overrideEnabled: boolean?, shouldAnimate: boolean?)
	local label = self._ui.autoSizeLabel
	if not (label and label:IsA("TextLabel")) then
		return
	end

	local isEnabled = self:_getResolvedNormalSizeEnabled(overrideEnabled)
	label.RichText = true
	label.Text = string.format(
		"<b>Normal Size [%s]</b> <br /> %s",
		if isEnabled then "ON" else "OFF",
		self._autoSizeDescriptionText
	)
	self:_setAutoSizeButtonVisualState(isEnabled, shouldAnimate)
end

function InventoryController:_toggleAutoSize()
	if not self:_ensureRemotes() then
		return
	end

	local ok, result = pcall(function()
		return self._remotes.setAutoSizeEnabled:InvokeServer({
			enabled = not self:_getAutoSizeEnabled(),
		})
	end)

	if not ok then
		warn(string.format("[InventoryController] Failed to toggle auto size: %s", tostring(result)))
		return
	end

	if typeof(result) ~= "table" then
		warn("[InventoryController] Auto size toggle returned an invalid response.")
		return
	end

	if result.ok ~= true then
		warn(string.format("[InventoryController] Failed to toggle auto size: %s", tostring(result.message)))
		if typeof(result.state) == "table" then
			self:_applyLoadoutState(result.state)
			self:_syncAutoSizeButton(result.state.autoSizeEnabled == true, false)
		else
			self:_syncAutoSizeButton(nil, false)
		end
		return
	end

	if typeof(result.state) == "table" then
		self:_applyLoadoutState(result.state)
		self:_syncAutoSizeButton(result.state.autoSizeEnabled == true, true)
		return
	end

	self:_syncAutoSizeButton(not self:_getResolvedAutoSizeEnabled(), true)
end

function InventoryController:_equipBestLoadout()
	if not self:_ensureRemotes() then
		return
	end

	local ok, result = pcall(function()
		return self._remotes.equipBest:InvokeServer()
	end)

	if not ok then
		showNotification("Equip best failed. Check the output for details.")
		warn(string.format("[InventoryController] Equip best invoke failed: %s", tostring(result)))
		return
	end

	if typeof(result) ~= "table" then
		showNotification("Equip best returned an invalid response.")
		return
	end

	if result.ok ~= true then
		showNotification(tostring(result.message or "Could not equip your best loadout."))
		self:_applyLoadoutState(result.state)
		return
	end

	showNotification(tostring(result.message or "Equipped best loadout."))
	self:_applyLoadoutState(result.state)
end

function InventoryController:_syncFilterButtons()
	local activeRegion = self._selectedFilterRegion

	for buttonName, button in pairs(self._ui.filterButtons) do
		local isActive = self._selectedSpecialFilter == nil and FILTER_BUTTON_TO_REGION[buttonName] == activeRegion
		self:_setOutlineColor(button, if isActive then SELECTED_COLOR else DEFAULT_OUTLINE_COLOR, if isActive then 0 else 0.2)
	end

	for _, auraButton in ipairs(self._ui.auraButtons) do
		local isActive = self._selectedSpecialFilter == "aura"
		self:_setOutlineColor(auraButton, if isActive then SELECTED_COLOR else DEFAULT_OUTLINE_COLOR, if isActive then 0 else 0.2)
	end

	for _, potionButton in ipairs(self._ui.potionButtons) do
		local isActive = self._selectedSpecialFilter == "potion"
		self:_setOutlineColor(potionButton, if isActive then SELECTED_COLOR else DEFAULT_OUTLINE_COLOR, if isActive then 0 else 0.2)
	end
end

function InventoryController:_syncAuraSlotPlaceholder(isFilled: boolean)
	local button = self._ui.auraSlotButton
	local defaults = self._auraSlotPlaceholderDefault
	if not (button and defaults) then
		return
	end

	if isFilled then
		button.ImageTransparency = 1

		for _, childName in ipairs({ "Icon", "Usage", "Viewport" }) do
			local child = button:FindFirstChild(childName)
			if child and child:IsA("GuiObject") then
				child.Visible = false
			end
		end

		local outline = button:FindFirstChild("Outline")
		if outline and outline:IsA("GuiObject") then
			outline.Visible = true
		end
		return
	end

	button.ImageTransparency = defaults.imageTransparency

	for childName, childState in pairs(defaults.children) do
		local child = button:FindFirstChild(childName)
		if child and child:IsA("GuiObject") then
			child.Visible = childState.visible
		end
	end
end

function InventoryController:_applyFilterRegion(region: string?)
	local shouldAnimate = self._selectedSpecialFilter ~= nil or self._selectedFilterRegion ~= region
	self._selectedSpecialFilter = nil
	self._selectedFilterRegion = region
	self._pendingFilterRowAnimation = shouldAnimate
	self:_syncFilterButtons()
	self:_syncList()
end

function InventoryController:_applySpecialFilter(filterType: string?)
	local nextFilterType = if filterType == "aura" or filterType == "potion" then filterType else nil
	local shouldAnimate = self._selectedSpecialFilter ~= nextFilterType or (nextFilterType ~= nil and self._selectedFilterRegion ~= nil)
	self._selectedSpecialFilter = nextFilterType
	if nextFilterType ~= nil then
		self._selectedFilterRegion = nil
	end
	self._pendingFilterRowAnimation = shouldAnimate
	self:_syncFilterButtons()
	self:_syncList()
end

function InventoryController:_syncSlotButtons()
	local equipped = self._loadoutState and self._loadoutState.equipped or {}
	local previewState = self._previewState

	for region, button in pairs(self._ui.slotButtons) do
		local entry = equipped and equipped[region]
		local isPreviewRegion = previewState ~= nil and previewState.kind == "equipped" and previewState.region == region
		local isSelectedOwnedRegion = previewState ~= nil
			and previewState.kind == "owned"
			and self._selectedOwnedId ~= nil
			and entry ~= nil
			and entry.ownedId == self._selectedOwnedId
		local outlineColor = DEFAULT_OUTLINE_COLOR
		local outlineTransparency = 0.3

		self:_syncSlotPlaceholder(region, entry ~= nil)
		if entry ~= nil then
			local recordView = self._recordViewsByOwnedId[entry.ownedId]
			if recordView then
				local isSelected = isPreviewRegion or isSelectedOwnedRegion
				local slotCardButton = self:_renderMountedSlotCard(
					string.format("inventory_bodyPart_%s", region),
					self._ui.slotFrames[region],
					function()
						self:_setPreviewForRegion(region)
					end,
					recordView,
					isSelected
				)
				self._slotCardButtonsByRegion[region] = slotCardButton
				if slotCardButton then
					self:_setOutlineColor(
						slotCardButton,
						if isSelected then SELECTED_COLOR else DEFAULT_OUTLINE_COLOR,
						if isSelected then 0 else 0.22
					)
				end
			else
				self._slotCardButtonsByRegion[region] = nil
				self:_hideMountedSlotCard(string.format("inventory_bodyPart_%s", region))
			end
		else
			self._slotCardButtonsByRegion[region] = nil
			self:_hideMountedSlotCard(string.format("inventory_bodyPart_%s", region))
		end

		if isPreviewRegion or isSelectedOwnedRegion then
			outlineColor = SELECTED_COLOR
			outlineTransparency = 0
		elseif entry then
			outlineColor = EQUIPPED_COLOR
			outlineTransparency = 0.1
		else
			outlineTransparency = 0.45
		end

		self:_setOutlineColor(button, outlineColor, outlineTransparency)
	end

	local auraButton = self._ui.auraSlotButton
	if auraButton then
		local equippedAuraOwnedId = self._equippedAuraOwnedId
		local isPreviewAura = previewState ~= nil
			and previewState.itemType == "aura"
			and ((previewState.kind == "equipped" and previewState.ownedId == equippedAuraOwnedId) or previewState.ownedId == equippedAuraOwnedId)
		local outlineColor = DEFAULT_OUTLINE_COLOR
		local outlineTransparency = 0.45

		self:_syncAuraSlotPlaceholder(equippedAuraOwnedId ~= nil)
		if equippedAuraOwnedId ~= nil then
			local recordView = self._recordViewsByOwnedId[equippedAuraOwnedId]
			if recordView then
				local isSelected = isPreviewAura
				self._auraSlotCardButton = self:_renderMountedSlotCard(
					"inventory_aura",
					self._ui.auraSlotFrame,
					function()
						self:_setPreviewForAura()
					end,
					recordView,
					isSelected
				)
				if self._auraSlotCardButton then
					self:_setOutlineColor(
						self._auraSlotCardButton,
						if isSelected then SELECTED_COLOR else DEFAULT_OUTLINE_COLOR,
						if isSelected then 0 else 0.22
					)
				end
			else
				self._auraSlotCardButton = nil
				self:_hideMountedSlotCard("inventory_aura")
			end
		else
			self._auraSlotCardButton = nil
			self:_hideMountedSlotCard("inventory_aura")
		end

		if isPreviewAura then
			outlineColor = SELECTED_COLOR
			outlineTransparency = 0
		elseif equippedAuraOwnedId ~= nil then
			outlineColor = EQUIPPED_COLOR
			outlineTransparency = 0.1
		end

		self:_setOutlineColor(auraButton, outlineColor, outlineTransparency)
	end
end

function InventoryController:_syncCapacityLabel()
	local label = "Inventory"
	local currentCount = OwnedBodyParts.CountOwnedRecords(self:_getOwnedLookup())
	local maxCount = OwnedBodyParts.MAX_OWNED_COUNT
	if self._selectedSpecialFilter == "aura" then
		currentCount = #self:_getVisibleRecords()
		label = "Auras"
	elseif self._selectedSpecialFilter == "potion" then
		currentCount = #self:_getVisibleRecords()
		label = "Potions"
		maxCount = #PotionConfig.GetAll()
	end

	self._ui.capacityLabel.Text =
		string.format("%s/%s %s", formatWholeNumber(currentCount), formatWholeNumber(maxCount), label)
end

function InventoryController:_syncSummaryLabels()
	local loadoutBonuses = self._loadoutState and self._loadoutState.bonuses or {}
	local potionBonuses = PotionController:GetRuntimeBonuses()
	local mergedBonuses = {
		passiveIncomePerSecond = (tonumber(loadoutBonuses.passiveIncomePerSecond) or 0)
			* math.max(1, tonumber(potionBonuses.passiveIncomeMultiplier) or 1),
		luckBonus = (tonumber(loadoutBonuses.luckBonus) or 0) + (tonumber(potionBonuses.luckBonus) or 0),
		rollSpeedBonus = (tonumber(loadoutBonuses.rollSpeedBonus) or 0) + (tonumber(potionBonuses.rollSpeedBonus) or 0),
	}
	local summaryTexts = BodyPartPresentation.BuildSummaryTexts(mergedBonuses)
	self._ui.incomeLabel.Text = summaryTexts.income
	self._ui.luckLabel.Text = summaryTexts.luck
	self._ui.rollSpeedLabel.Text = summaryTexts.rollSpeed
	self:_syncPreviewStatLabels()
end

function InventoryController:_syncPreviewStatLabels()
	local previewStatLabels = self._ui.previewStatLabels
	if typeof(previewStatLabels) ~= "table" then
		return
	end

	local statTexts = BodyPartPresentation.BuildPreviewStatTexts(
		self._loadoutState and self._loadoutState.bonuses or nil,
		self._previewStatNativeTexts
	)

	for _, statName in ipairs(PREVIEW_STAT_NAMES) do
		local label = previewStatLabels[statName]
		local text = statTexts[statName]
		if label and label:IsA("TextLabel") and typeof(text) == "string" then
			label.Text = text
		end
	end
end

function InventoryController:_syncPreview()
	local previewHolder = self._ui.previewHolder
	local previewViewport = self._ui.previewViewport
	local previewIcon = self._ui.previewIcon
	local previewModel = self:_resolvePreviewModel()
	local renderKey = if previewModel == nil
		then "none"
		else string.format(
			"%s|%s|%s|%s|%s",
			tostring(previewModel.itemType),
			tostring(previewModel.ownedId or ""),
			tostring(previewModel.pieceId or previewModel.auraId or previewModel.potionId or ""),
			tostring(previewModel.region or ""),
			tostring(previewModel.sizeText or previewModel.rarityText or "")
		)
	self._previewExistingRequestToken += 1
	local requestToken = self._previewExistingRequestToken
	previewHolder.Visible = previewModel ~= nil

	if not previewModel then
		if self._previewRenderKey ~= "none" then
			ViewportModelRenderer.Clear(previewViewport)
		end
		previewViewport.Visible = true
		previewIcon.Visible = false
		previewIcon.Image = ""
		self._previewRenderKey = "none"
		self._previewCountKey = nil
		self:_applyPreviewLabelStyles(nil)
		self:_syncPreviewLabelLayout(nil)
		self:_setEverRolledPreviewText(nil)
		self:_syncPreviewStatLabels()
		self:_setPreviewTab("info")
		self:_syncInventoryAnchor(false)
		return
	end

	self:_setPreviewTab(self._previewTab)

	local iconTexture = if typeof(previewModel.iconTexture) == "string" and previewModel.iconTexture ~= "" then previewModel.iconTexture else nil
	local shouldUsePreviewIcon = previewModel.itemType == "aura" and iconTexture ~= nil

	if shouldUsePreviewIcon then
		if self._previewRenderKey ~= renderKey then
			ViewportModelRenderer.Clear(previewViewport)
		end
		previewViewport.Visible = false
		previewIcon.Image = iconTexture
		previewIcon.Visible = true
	else
		previewIcon.Visible = false
		previewIcon.Image = ""
		previewViewport.Visible = true
		if self._previewRenderKey ~= renderKey then
			if previewModel.itemType == "potion" then
				ViewportModelRenderer.RenderPotion(previewViewport, previewModel.bundleModel)
			else
				local appearanceSnapshot = PreviewAppearanceRegistry.GetSnapshotForUserId(previewModel.appearanceUserId)
				if appearanceSnapshot ~= nil and typeof(previewModel.region) == "string" and previewModel.region ~= "" then
					ViewportModelRenderer.RenderBodyPartPreview(
						previewViewport,
						previewModel.bundleModel,
						previewModel.region,
						appearanceSnapshot,
						previewModel.previewScale
					)
				else
					ViewportModelRenderer.RenderBundle(previewViewport, previewModel.bundleModel)
				end
			end
		end
	end

	self._previewRenderKey = renderKey
	self:_applyPreviewLabelStyles(previewModel)
	self:_syncPreviewLabelLayout(previewModel.itemType)
	self._ui.previewLabels.Bundle.Text = previewModel.inventoryBundleText or previewModel.bundleText
	self._ui.previewLabels.Part.Text = previewModel.partText
	self._ui.previewLabels.Rarity.Text = previewModel.rarityText
	self._ui.previewLabels.Mutation.Text = previewModel.mutationText
	self._ui.previewLabels.Content.Text = previewModel.sizeText
	self:_setExistingPreviewText(previewModel.existingText or "Existing: N/A")
	self:_setEverRolledPreviewText(previewModel.inventoryEverRolledText)
	self._ui.previewLabels.Cash.Text = previewModel.cashText
	self._ui.previewLabels.Chance.Text = previewModel.chanceText
	self:_syncPreviewStatLabels()
	self:_syncInventoryAnchor(true)

	if previewModel.itemType == "potion" then
		self._previewCountKey = nil
		return
	end

	local countKey = if previewModel.itemType == "aura"
		then string.format("aura:%s", tostring(previewModel.auraId))
		else string.format("bodyPart:%s", tostring(previewModel.pieceId))
	if self._previewCountKey ~= countKey then
		self._previewCountKey = countKey
		task.spawn(function()
			if previewModel.itemType == "aura" then
				self:_requestAuraExistingCount(previewModel.auraId, requestToken)
			else
				self:_requestBodyPartExistingCount(previewModel.pieceId, requestToken)
			end
		end)
	elseif self._previewExistingCountCache[countKey] ~= nil then
		self:_setExistingPreviewText(string.format("Existing: %s", formatWholeNumber(self._previewExistingCountCache[countKey])))
	else
		task.spawn(function()
			if previewModel.itemType == "aura" then
				self:_requestAuraExistingCount(previewModel.auraId, requestToken)
			else
				self:_requestBodyPartExistingCount(previewModel.pieceId, requestToken)
			end
		end)
	end
end

function InventoryController:_getPreviewOwnedId(): string?
	local previewState = self._previewState
	if previewState and typeof(previewState.ownedId) == "string" and previewState.ownedId ~= "" then
		return previewState.ownedId
	end

	local selectedOwnedId = self._selectedOwnedId
	if not selectedOwnedId then
		return nil
	end

	if string.find(selectedOwnedId, "aura_", 1, true) == 1 then
		if self:_getOwnedAuraLookup()[selectedOwnedId] ~= nil then
			return selectedOwnedId
		end
	elseif PotionController.IsPotionOwnedId(selectedOwnedId) then
		local potionId = PotionController.GetPotionIdFromOwnedId(selectedOwnedId)
		if potionId and self:_getOwnedPotionLookup()[potionId] ~= nil then
			return selectedOwnedId
		end
	elseif self:_getOwnedLookup()[selectedOwnedId] ~= nil then
		return selectedOwnedId
	end

	return nil
end

function InventoryController:_getPreviewOwnedRecord()
	local ownedId = self:_getPreviewOwnedId()
	if not ownedId then
		return nil
	end

	local previewState = self._previewState
	if previewState and previewState.itemType == "aura" then
		return self:_getOwnedAuraLookup()[ownedId]
	end
	if (previewState and previewState.itemType == "potion") or PotionController.IsPotionOwnedId(ownedId) then
		local potionId = PotionController.GetPotionIdFromOwnedId(ownedId)
		return potionId and self:_getOwnedPotionLookup()[potionId] or nil
	end

	return self:_getOwnedLookup()[ownedId]
end

function InventoryController:_getSellAllEligibleCount(): number
	local count = 0
	for _, recordView in ipairs(self:_getInventoryRecords()) do
		if recordView.itemType == "bodyPart" and recordView.record.isFavorite ~= true and not self:_isOwnedIdEquipped(recordView.ownedId) then
			count += 1
		end
	end

	return count
end

function InventoryController:_buildSellAllConfirmationMessage(): string
	local eligibleCount = self:_getSellAllEligibleCount()
	if eligibleCount <= 0 then
		return "No unfavorited, unequipped body parts are available to sell."
	end

	return string.format(
		"Sell %s unfavorited, unequipped body parts? Favorites and equipped items will stay.",
		formatWholeNumber(eligibleCount)
	)
end

function InventoryController:_getPendingPotionSellRecord(): (string?, OwnedPotionRecord?)
	local ownedId = self._pendingPotionSellOwnedId
	local potionId = PotionController.GetPotionIdFromOwnedId(ownedId)
	if potionId == nil then
		return nil, nil
	end

	return potionId, self:_getOwnedPotionLookup()[potionId]
end

function InventoryController:_syncPotionSellModal()
	local frame = self._ui.potionSellFrame
	if not frame then
		return
	end

	local potionId, ownedRecord = self:_getPendingPotionSellRecord()
	if frame.Visible ~= true or potionId == nil or ownedRecord == nil then
		return
	end

	local potionConfig = PotionConfig.Get(potionId)
	if not potionConfig then
		self._pendingPotionSellOwnedId = nil
		frame.Visible = false
		return
	end

	local ownedAmount = math.max(0, math.floor(tonumber(ownedRecord.amount) or 0))
	if ownedAmount <= 0 then
		self._pendingPotionSellOwnedId = nil
		frame.Visible = false
		return
	end

	self._pendingPotionSellQuantity = math.clamp(math.floor(tonumber(self._pendingPotionSellQuantity) or 1), 1, ownedAmount)
	local sellQuantity = self._pendingPotionSellQuantity
	local sellPricePerUse = PotionConfig.GetSellPrice(potionId)

	self._ui.potionSellTitle.Text = string.format("Sell %s", potionConfig.label)
	self._ui.potionSellOwned.Text = string.format("Owned: x%s", formatWholeNumber(ownedAmount))
	self._ui.potionSellQuantity.Text = string.format("Quantity: x%s", formatWholeNumber(sellQuantity))
	self._ui.potionSellPayout.Text = string.format(
		"Payout: $%s",
		formatWholeNumber(sellPricePerUse * sellQuantity)
	)
end

function InventoryController:_setPotionSellModalVisible(isVisible: boolean)
	local frame = self._ui.potionSellFrame
	if not frame then
		return
	end

	if not isVisible then
		frame.Visible = false
		self._pendingPotionSellOwnedId = nil
		self._pendingPotionSellQuantity = 1
		return
	end

	local previewOwnedId = self:_getPreviewOwnedId()
	if not PotionController.IsPotionOwnedId(previewOwnedId) then
		return
	end

	self._pendingPotionSellOwnedId = previewOwnedId
	self._pendingPotionSellQuantity = 1
	frame.Visible = true
	self:_syncPotionSellModal()
end

function InventoryController:_changePotionSellQuantity(delta: number)
	local _, ownedRecord = self:_getPendingPotionSellRecord()
	if not ownedRecord then
		return
	end

	local ownedAmount = math.max(1, math.floor(tonumber(ownedRecord.amount) or 1))
	self._pendingPotionSellQuantity = math.clamp(
		math.floor((tonumber(self._pendingPotionSellQuantity) or 1) + delta),
		1,
		ownedAmount
	)
	self:_syncPotionSellModal()
end

function InventoryController:_confirmPotionSell()
	local potionId = PotionController.GetPotionIdFromOwnedId(self._pendingPotionSellOwnedId)
	if potionId == nil then
		self:_setPotionSellModalVisible(false)
		return
	end

	local sellQuantity = math.max(1, math.floor(tonumber(self._pendingPotionSellQuantity) or 1))
	if PotionController:SellPotion(potionId, sellQuantity) then
		self:_setPotionSellModalVisible(false)
	else
		self:_syncPotionSellModal()
	end
end

function InventoryController:_syncSecondaryActionButtons()
	local selectedRecord = self:_getPreviewOwnedRecord()
	local hasOwnedSelection = selectedRecord ~= nil
	local isAuraSelection = self._previewState ~= nil and self._previewState.itemType == "aura"
	local layoutDefaults = self._previewSecondaryActionButtonLayouts
	local favoriteButton = self._ui.favoriteButton
	if favoriteButton then
		applyGuiButtonLayout(favoriteButton, layoutDefaults and layoutDefaults.favorite or nil)
		if isAuraSelection then
			applyGuiButtonLayout(favoriteButton, layoutDefaults and layoutDefaults.auraFavorite or nil)
			favoriteButton.Visible = true
		end
		favoriteButton.Active = hasOwnedSelection
		favoriteButton.AutoButtonColor = false

		local buttonText = favoriteButton:FindFirstChild("TextLabel")
		if buttonText and buttonText:IsA("TextLabel") then
			buttonText.Text = if selectedRecord and selectedRecord.isFavorite == true then "Unfavorite" else "Favorite"
			buttonText.TextTransparency = if hasOwnedSelection then 0 else 0.35
		end
	end

	local sellButton = self._ui.sellButton
	if sellButton then
		applyGuiButtonLayout(sellButton, layoutDefaults and layoutDefaults.sell or nil)
		sellButton.Visible = not isAuraSelection
		sellButton.Active = hasOwnedSelection and not isAuraSelection
		sellButton.AutoButtonColor = false
	end
end

function InventoryController:_destroyCachedCharacterPreviewModel()
	local cachedModel = self._cachedCharacterPreviewModel
	if cachedModel and cachedModel.Parent == nil then
		cachedModel:Destroy()
	end

	self._cachedCharacterPreviewModel = nil
end

function InventoryController:_invalidateCharacterPreviewModel()
	self._characterPreviewGeneration += 1
	self._isResolvingCharacterPreviewModel = false
	self:_destroyCachedCharacterPreviewModel()
end

function InventoryController:_getCurrentHumanoidDescription(): HumanoidDescription?
	local character = LOCAL_PLAYER.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	local ok, description = pcall(function()
		return humanoid:GetAppliedDescription()
	end)

	if not ok or not description or not description:IsA("HumanoidDescription") then
		return nil
	end

	return description
end

function InventoryController:_createCharacterPreviewModelFromDescription(description: HumanoidDescription?): Model?
	if not description then
		return nil
	end

	local baseRigModel = BodyPartsCatalog.GetDefaultBaseRig()
	if not (baseRigModel and baseRigModel:IsA("Model")) then
		return nil
	end

	local previewModel = baseRigModel:Clone()
	previewModel.Name = "InventoryCharacterPreview"

	local humanoid = previewModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		previewModel:Destroy()
		return nil
	end

	local ok = pcall(function()
		humanoid:ApplyDescriptionReset(description)
	end)

	if not ok then
		previewModel:Destroy()
		return nil
	end

	return previewModel
end

function InventoryController:_buildDefaultCharacterPreviewModel(): Model?
	local previewModel = self:_createCharacterPreviewModelFromDescription(self:_getCurrentHumanoidDescription())
	if previewModel then
		return previewModel
	end

	local ok, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(LOCAL_PLAYER.UserId)
	end)

	if not ok or not description or not description:IsA("HumanoidDescription") then
		return nil
	end

	return self:_createCharacterPreviewModelFromDescription(description)
end

function InventoryController:_resolveCharacterPreviewModelAsync()
	if self._cachedCharacterPreviewModel or self._isResolvingCharacterPreviewModel then
		return
	end

	self._isResolvingCharacterPreviewModel = true
	local generation = self._characterPreviewGeneration

	task.spawn(function()
		local previewModel = self:_buildDefaultCharacterPreviewModel()
		if self._characterPreviewGeneration ~= generation then
			if previewModel and previewModel.Parent == nil then
				previewModel:Destroy()
			end
			return
		end

		self._isResolvingCharacterPreviewModel = false

		if not previewModel then
			return
		end

		self:_destroyCachedCharacterPreviewModel()
		self._cachedCharacterPreviewModel = previewModel
		ViewportModelRenderer.RenderCharacterModel(self._ui.characterViewport, previewModel, BodyPartsCatalog.GetDefaultBaseRig())
	end)
end

function InventoryController:_syncCharacterViewport()
	local framingModel = BodyPartsCatalog.GetDefaultBaseRig()
	local previewModel = self._cachedCharacterPreviewModel or BodyPartsCatalog.GetDefaultBaseRig()
	ViewportModelRenderer.RenderCharacterModel(self._ui.characterViewport, previewModel, framingModel)

	if self._cachedCharacterPreviewModel == nil then
		self:_resolveCharacterPreviewModelAsync()
	end
end

function InventoryController:_syncActionButton()
	local actionButton = self._ui.equipButton
	local previewState = self._previewState
	local selectedRecord = self:_getPreviewOwnedRecord()
	local equippedEntry = previewState and previewState.itemType == "bodyPart" and previewState.kind == "equipped" and previewState.entry or nil
	local isAuraSelection = previewState ~= nil and previewState.itemType == "aura"
	local isPotionSelection = previewState ~= nil and previewState.itemType == "potion"
	local auraAction = if isAuraSelection then self:_getAuraPreviewActionRequest() else nil
	local isUnequipMode = (equippedEntry ~= nil and previewState ~= nil and previewState.region ~= nil)
		or (isAuraSelection and auraAction == "unequip")
	local enabled = if isPotionSelection
		then selectedRecord ~= nil
		else if isAuraSelection
			then auraAction ~= nil and self._auraActionInFlight ~= true
			else if isUnequipMode then true else selectedRecord ~= nil

	actionButton.Active = enabled
	actionButton.AutoButtonColor = false

	local buttonText = actionButton:FindFirstChild("TextLabel")
	if buttonText and buttonText:IsA("TextLabel") then
		buttonText.Text = if isAuraSelection and self._auraActionInFlight == true
			then "Working..."
			else if isPotionSelection then "Use" else if isUnequipMode then "Unequip" else "Equip"
		buttonText.TextTransparency = if enabled then 0 else 0.35
	end

	for _, child in ipairs(actionButton:GetChildren()) do
		if child:IsA("ImageLabel") then
			if child.Name == "Cover" or child.Name == "Cover2" then
				child.ImageTransparency = if enabled then 0 else 0.25
			elseif child.Name == "Rays" then
				child.ImageTransparency = if enabled then 0 else 0.45
			end
		end
	end
end

function InventoryController:_refreshRows()
	self:_cancelPendingListRowSequence()
	self:_rebuildEquippedOwnedIdByRegion()

	local recordsByOwnedId = {}
	for _, recordView in ipairs(self:_getInventoryRecords()) do
		recordsByOwnedId[recordView.ownedId] = recordView
		self:_ensureRowForRecord(recordView)
	end
	self._recordViewsByOwnedId = recordsByOwnedId

	local ownedIdsToRemove = {}
	for ownedId in pairs(self._rowFramesByOwnedId) do
		if recordsByOwnedId[ownedId] == nil then
			table.insert(ownedIdsToRemove, ownedId)
		end
	end
	for _, ownedId in ipairs(ownedIdsToRemove) do
		self:_destroyRow(ownedId)
	end

	local visibleRecords = self:_getVisibleRecords()
	if self:_consumePendingFilterRowAnimation() then
		self:_hideAllListRows()
		self:_syncRowSelectionStates()
		self:_playFilterRowRepopulateSequence(visibleRecords)
		return
	end

	local visibleOwnedIds = {}
	for index, recordView in ipairs(visibleRecords) do
		self:_mountRowToList(recordView.ownedId, index)
		visibleOwnedIds[recordView.ownedId] = true
	end

	for ownedId in pairs(self._rowFramesByOwnedId) do
		if not visibleOwnedIds[ownedId] then
			self:_hideRow(ownedId)
		end
	end

	self:_syncRowSelectionStates()
end

function InventoryController:_syncList()
	local startedAt = PerfStats.Begin()
	self:_refreshRows()
	self:_syncCapacityLabel()
	PerfStats.Measure("InventorySyncList", startedAt, {
		recordCount = #self:_getInventoryRecords(),
		visibleCount = #self:_getVisibleRecords(),
	})
end

function InventoryController:_syncBodyPartDependentUi()
	self:_syncList()
	self:_syncPreview()
	self:_syncSummaryLabels()
	self:_syncActionButton()
	self:_syncSecondaryActionButtons()
end

function InventoryController:_flushScheduledBodyPartRefresh()
	self._bodyPartRefreshScheduled = false
	if not FrameController:IsOpen(WINDOW_NAME) then
		return
	end

	self:_syncBodyPartDependentUi()
end

function InventoryController:_scheduleBodyPartRefresh()
	self:_markInventoryRecordsDirty()
	if not FrameController:IsOpen(WINDOW_NAME) or self._bodyPartRefreshScheduled then
		return
	end

	self._bodyPartRefreshScheduled = true
	task.defer(function()
		self:_flushScheduledBodyPartRefresh()
	end)
end

function InventoryController:_applyLoadoutState(state: BodyPartClientState?)
	local incomingState = if typeof(state) == "table" then state else nil
	local isDeltaUpdate = incomingState ~= nil and incomingState._isDelta == true
	self._loadoutState = mergeTopLevelState(self._loadoutState, incomingState)
	self:_rebuildEquippedOwnedIdByRegion()

	local selectedOwnedId = self._selectedOwnedId
	if selectedOwnedId then
		local isAuraOwnedId = string.find(selectedOwnedId, "aura_", 1, true) == 1
		local isPotionOwnedId = PotionController.IsPotionOwnedId(selectedOwnedId)
		if isAuraOwnedId then
			if self:_getOwnedAuraLookup()[selectedOwnedId] == nil then
				self._selectedOwnedId = nil
			end
		elseif isPotionOwnedId then
			local potionId = PotionController.GetPotionIdFromOwnedId(selectedOwnedId)
			if potionId == nil or self:_getOwnedPotionLookup()[potionId] == nil then
				self._selectedOwnedId = nil
			end
		elseif self:_getOwnedLookup()[selectedOwnedId] == nil then
			self._selectedOwnedId = nil
		end
	end

	local previewState = self._previewState
	if previewState and previewState.kind == "owned" and previewState.ownedId and self:_getOwnedLookup()[previewState.ownedId] == nil then
		local previewPotionId = PotionController.GetPotionIdFromOwnedId(previewState.ownedId)
		if not (
			(previewState.itemType == "aura" and self:_getOwnedAuraLookup()[previewState.ownedId] ~= nil)
			or (previewState.itemType == "potion" and previewPotionId ~= nil and self:_getOwnedPotionLookup()[previewPotionId] ~= nil)
		) then
			self._previewState = nil
		end
	elseif previewState and previewState.itemType == "bodyPart" and previewState.kind == "equipped" and previewState.region then
		local equipped = self._loadoutState and self._loadoutState.equipped
		local entry = equipped and equipped[previewState.region]
		if entry then
			self._previewState = {
				itemType = "bodyPart",
				kind = "equipped",
				ownedId = entry.ownedId,
				region = previewState.region,
				entry = entry,
			}
		else
			self._previewState = nil
		end
	end

	if not isDeltaUpdate or incomingState.ownedBodyParts ~= nil or incomingState.equipped ~= nil then
		self:_markInventoryRecordsDirty()
		self:_syncBodyPartDependentUi()
	else
		self:_syncRowSelectionStates()
	end
	self:_syncSlotButtons()
	if self._loadoutState and self._loadoutState.autoSizeEnabled ~= nil then
		local autoSizeEnabled = self._loadoutState.autoSizeEnabled == true
		local isEnabled = self:_getResolvedNormalSizeEnabled(autoSizeEnabled)
		local shouldAnimate = self._autoSizeStateHydrated
			and self._autoSizeVisualState ~= nil
			and self._autoSizeVisualState ~= isEnabled
		self:_syncAutoSizeButton(autoSizeEnabled, shouldAnimate)
		self._autoSizeStateHydrated = true
	end
	self:_syncPotionSellModal()
end

function InventoryController:_applyAuraState(state: AuraClientState?)
	self._auraState = if typeof(state) == "table" then state else nil
	self:_markInventoryRecordsDirty()
	self:_rebuildEquippedOwnedIdByRegion()

	local selectedOwnedId = self._selectedOwnedId
	if selectedOwnedId and string.find(selectedOwnedId, "aura_", 1, true) == 1 and self:_getOwnedAuraLookup()[selectedOwnedId] == nil then
		self._selectedOwnedId = nil
	end

	local previewState = self._previewState
	if previewState and previewState.itemType == "aura" then
		local ownedLookup = self:_getOwnedAuraLookup()
		local equippedAuraId = self:_getEquippedAuraId()
		if previewState.kind == "owned" and previewState.ownedId and ownedLookup[previewState.ownedId] == nil then
			self._previewState = nil
		elseif previewState.kind == "equipped" and self._equippedAuraOwnedId ~= nil then
			self._previewState = {
				itemType = "aura",
				kind = "equipped",
				ownedId = self._equippedAuraOwnedId,
				auraId = equippedAuraId,
			}
		elseif previewState.kind == "equipped" and equippedAuraId == nil then
			self._previewState = nil
		elseif previewState.kind == "equipped" and previewState.auraId ~= equippedAuraId then
			self._previewState = nil
		elseif previewState.kind == "equipped" and previewState.ownedId and ownedLookup[previewState.ownedId] == nil then
			self._previewState = nil
		end
	end

	self:_syncList()
	self:_syncPreview()
	self:_syncSummaryLabels()
	self:_syncSlotButtons()
	self:_syncActionButton()
	self:_syncSecondaryActionButtons()
	self:_syncPotionSellModal()
end

function InventoryController:_scheduleAuraStateRefresh()
	self:_markInventoryRecordsDirty()
	if self._auraStateRefreshScheduled == true then
		return
	end

	self._auraStateRefreshScheduled = true
	task.defer(function()
		self._auraStateRefreshScheduled = false
		self:_refreshAuraStateFromData()
	end)
end

function InventoryController:_refreshAuraStateFromData()
	local auraState = DataController:Get(AURA_DATA_KEY)
	local equippedAuraId = DataController:Get(EQUIPPED_AURA_ID_KEY)
	self:_applyAuraState({
		ownedAuras = if typeof(auraState) == "table" and typeof(auraState.ownedById) == "table" then auraState.ownedById else {},
		equippedAuraId = if typeof(equippedAuraId) == "string" then equippedAuraId else nil,
	})
end

function InventoryController:_requestLoadoutState()
	if not self:_ensureRemotes() then
		return
	end

	local ok, result = pcall(function()
		return self._remotes.getState:InvokeServer()
	end)

	if not ok then
		warn(string.format("[InventoryController] Failed to load body part state: %s", tostring(result)))
		return
	end

	if typeof(result) ~= "table" or result.ok ~= true then
		return
	end

	self:_applyLoadoutState(result.state)
end

function InventoryController:_equipSelectedOwnedItem()
	local previewState = self._previewState

	if previewState and previewState.itemType == "potion" then
		local potionId = previewState.potionId or PotionController.GetPotionIdFromOwnedId(previewState.ownedId)
		if potionId == nil then
			self:_clearPreview()
			return
		end

		PotionController:UsePotion(potionId)
		return
	end

	if previewState and previewState.itemType == "aura" then
		local requestedAction, requestedOwnedId = self:_getAuraPreviewActionRequest()
		if requestedAction == nil then
			return
		end

		if self._auraActionInFlight == true then
			return
		end

		if not self:_ensureAuraRemotes() then
			return
		end

		self._auraActionRequestToken += 1
		local requestToken = self._auraActionRequestToken
		self._auraActionInFlight = true
		self:_syncActionButton()

		local ok, result = pcall(function()
			return self._remotes.auraEquip:InvokeServer({
				action = requestedAction,
				ownedId = requestedOwnedId,
			})
		end)

		if requestToken == self._auraActionRequestToken then
			self._auraActionInFlight = false
		end
		self:_syncActionButton()

		if not ok then
			showNotification("Aura action failed. Check the output for details.")
			warn(string.format("[InventoryController] Aura action invoke failed: %s", tostring(result)))
			return
		end

		if typeof(result) ~= "table" then
			showNotification("Aura action returned an invalid response.")
			return
		end

		if result.ok ~= true then
			showNotification(tostring(result.message or "Could not update that aura."))
			if typeof(result.state) == "table" then
				self:_applyAuraState(result.state)
			end
			return
		end

		showNotification(tostring(result.message or "Updated aura."))
		if typeof(result.state) == "table" then
			self:_applyAuraState(result.state)
		else
			self:_refreshAuraStateFromData()
		end
		return
	end

	local selectedOwnedId = self._selectedOwnedId
	if not selectedOwnedId then
		return
	end

	local ownedRecord = self:_getOwnedLookup()[selectedOwnedId]

	if not ownedRecord then
		self:_clearPreview()
		return
	end

	if not self:_ensureRemotes() then
		return
	end

	local ok, result = pcall(function()
		return self._remotes.equip:InvokeServer({
			ownedId = selectedOwnedId,
			scale = tonumber(ownedRecord.sizeMultiplier) or 1,
			applyVisuals = true,
		})
	end)

	if not ok then
		showNotification("Inventory equip failed. Check the output for details.")
		warn(string.format("[InventoryController] Equip invoke failed: %s", tostring(result)))
		return
	end

	if typeof(result) ~= "table" then
		showNotification("Inventory equip returned an invalid response.")
		return
	end

	if result.ok ~= true then
		showNotification(tostring(result.message or "Could not equip that body part."))
		self:_applyLoadoutState(result.state)
		return
	end

	showNotification(tostring(result.message or "Equipped body part."))
	self:_applyLoadoutState(result.state)
end

function InventoryController:_unequipPreviewedRegion()
	local previewState = self._previewState
	if not (previewState and previewState.itemType == "bodyPart" and previewState.kind == "equipped" and typeof(previewState.region) == "string") then
		return
	end

	if not self:_ensureRemotes() then
		return
	end

	local ok, result = pcall(function()
		return self._remotes.unequip:InvokeServer({
			region = previewState.region,
		})
	end)

	if not ok then
		showNotification("Inventory unequip failed. Check the output for details.")
		warn(string.format("[InventoryController] Unequip invoke failed: %s", tostring(result)))
		return
	end

	if typeof(result) ~= "table" then
		showNotification("Inventory unequip returned an invalid response.")
		return
	end

	if result.ok ~= true then
		showNotification(tostring(result.message or "Could not unequip that body part."))
		self:_applyLoadoutState(result.state)
		return
	end

	showNotification(tostring(result.message or "Unequipped body part."))
	self:_applyLoadoutState(result.state)
end

function InventoryController:_toggleFavoriteForPreviewedItem()
	local ownedRecord = self:_getPreviewOwnedRecord()
	if not ownedRecord then
		return
	end

	local previewState = self._previewState
	if previewState and previewState.itemType == "potion" then
		local potionId = previewState.potionId or PotionController.GetPotionIdFromOwnedId(previewState.ownedId)
		if potionId == nil then
			return
		end

		PotionController:ToggleFavorite(potionId, not (ownedRecord.isFavorite == true))
		return
	end

	if previewState and previewState.itemType == "aura" then
		if not self:_ensureAuraRemotes() then
			return
		end

		local ok, result = pcall(function()
			return self._remotes.auraToggleFavorite:InvokeServer({
				ownedId = ownedRecord.ownedId,
				isFavorite = not (ownedRecord.isFavorite == true),
			})
		end)

		if not ok then
			showNotification("Aura favorite failed. Check the output for details.")
			warn(string.format("[InventoryController] Aura favorite invoke failed: %s", tostring(result)))
			return
		end

		if typeof(result) ~= "table" then
			showNotification("Aura favorite returned an invalid response.")
			return
		end

		if result.ok ~= true then
			showNotification(tostring(result.message or "Could not update aura favorite state."))
			if typeof(result.state) == "table" then
				self:_applyAuraState(result.state)
			end
			return
		end

		showNotification(tostring(result.message or "Updated aura favorite state."))
		if typeof(result.state) == "table" then
			self:_applyAuraState(result.state)
		else
			self:_refreshAuraStateFromData()
		end
		return
	end

	if not self:_ensureRemotes() then
		return
	end

	local ok, result = pcall(function()
		return self._remotes.toggleFavorite:InvokeServer({
			ownedId = ownedRecord.ownedId,
			isFavorite = not (ownedRecord.isFavorite == true),
		})
	end)

	if not ok then
		showNotification("Inventory favorite failed. Check the output for details.")
		warn(string.format("[InventoryController] Favorite invoke failed: %s", tostring(result)))
		return
	end

	if typeof(result) ~= "table" then
		showNotification("Inventory favorite returned an invalid response.")
		return
	end

	if result.ok ~= true then
		showNotification(tostring(result.message or "Could not update favorite state."))
		self:_applyLoadoutState(result.state)
		return
	end

	showNotification(tostring(result.message or "Updated favorite state."))
	self:_applyLoadoutState(result.state)
end

function InventoryController:_sellPreviewedItem()
	local ownedRecord = self:_getPreviewOwnedRecord()
	if not ownedRecord then
		return
	end

	if self._previewState and self._previewState.itemType == "aura" then
		return
	end
	if self._previewState and self._previewState.itemType == "potion" then
		self:_setPotionSellModalVisible(true)
		return
	end

	if not self:_ensureRemotes() then
		return
	end

	local ok, result = pcall(function()
		return self._remotes.sellOwned:InvokeServer({
			ownedId = ownedRecord.ownedId,
		})
	end)

	if not ok then
		showNotification("Inventory sell failed. Check the output for details.")
		warn(string.format("[InventoryController] Sell invoke failed: %s", tostring(result)))
		return
	end

	if typeof(result) ~= "table" then
		showNotification("Inventory sell returned an invalid response.")
		return
	end

	if result.ok ~= true then
		showNotification(tostring(result.message or "Could not sell that body part."))
		self:_applyLoadoutState(result.state)
		return
	end

	showNotification(tostring(result.message or "Sold body part."))
	self:_applyLoadoutState(result.state)
end

function InventoryController:_promptSellAllConfirmation()
	if ConfirmationWarning.Prompt(self:_buildSellAllConfirmationMessage()) ~= true then
		return
	end

	self:_confirmSellAll()
end

function InventoryController:_confirmSellAll()
	if not self:_ensureRemotes() then
		return
	end

	local ok, result = pcall(function()
		return self._remotes.sellAll:InvokeServer()
	end)

	if not ok then
		showNotification("Sell all failed. Check the output for details.")
		warn(string.format("[InventoryController] Sell all invoke failed: %s", tostring(result)))
		return
	end

	if typeof(result) ~= "table" then
		showNotification("Sell all returned an invalid response.")
		return
	end

	if result.ok ~= true then
		showNotification(tostring(result.message or "Could not sell your unfavorited body parts."))
		self:_applyLoadoutState(result.state)
		return
	end

	showNotification(tostring(result.message or "Sold unfavorited body parts."))
	self:_applyLoadoutState(result.state)
end

function InventoryController:_bindFilterButtons()
	for buttonName, region in pairs(FILTER_BUTTON_TO_REGION) do
		local button = self._ui.filterButtons[buttonName]
		if button then
			UIController:CreateButton(button, function()
				self:_applyFilterRegion(if self._selectedFilterRegion == region then nil else region)
			end)
		end
	end

	for _, auraButton in ipairs(self._ui.auraButtons) do
		auraButton.Visible = true
		auraButton.Active = true
		UIController:CreateButton(auraButton, function()
			self:_applySpecialFilter(if self._selectedSpecialFilter == "aura" then nil else "aura")
		end)
	end

	for _, potionButton in ipairs(self._ui.potionButtons) do
		potionButton.Visible = true
		potionButton.Active = true
		UIController:CreateButton(potionButton, function()
			self:_applySpecialFilter(if self._selectedSpecialFilter == "potion" then nil else "potion")
		end)
	end
end

function InventoryController:_bindSlotButtons()
	for region, button in pairs(self._ui.slotButtons) do
		UIController:CreateButton(button, function()
			self:_applyFilterRegion(region)

			local equipped = self._loadoutState and self._loadoutState.equipped
			local entry = equipped and equipped[region]
			if entry then
				self:_setPreviewForRegion(region)
				return
			end

			self:_clearPreview()
		end)
	end

	local auraButton = self._ui.auraSlotButton
	if auraButton then
		UIController:CreateButton(auraButton, function()
			self:_applySpecialFilter("aura")

			if self._equippedAuraOwnedId then
				self:_setPreviewForAura()
				return
			end

			self:_clearPreview()
		end)
	end
end

function InventoryController:_bindOpenButton(openButton: GuiButton)
	UIController:CreateButton(openButton, function()
		local wasOpen = FrameController:IsOpen(WINDOW_NAME)
		FrameController:ToggleFrame(WINDOW_NAME)
		if not wasOpen then
			task.defer(function()
				self:_ensureFullUi(self._playerGui or LOCAL_PLAYER:WaitForChild("PlayerGui"))
				self._selectedFilterRegion = nil
				self._selectedSpecialFilter = nil
				self:_markInventoryRecordsDirty()
				self:_syncFilterButtons()
				self:_syncList()
				self:_syncCharacterViewport()
				self:_syncPreview()
				self:_syncSummaryLabels()
				self:_syncSlotButtons()
				self:_syncActionButton()
				self:_syncSecondaryActionButtons()
				self:_syncAutoSizeButton(nil, false)
				self:_syncPotionSellModal()
				self:_requestLoadoutState()
			end)
		end
	end)
end

function InventoryController:_cacheOpenButton(playerGui: PlayerGui)
	local mainInterface = playerGui:WaitForChild("MainInterface", 30)
	if not (mainInterface and mainInterface:IsA("ScreenGui")) then
		error("PlayerGui.MainInterface is missing.")
	end

	local openButton = mainInterface:WaitForChild("Main", 30):WaitForChild("ExtraButtons", 30):WaitForChild("Inventory", 30)
	if not (openButton and openButton:IsA("GuiButton")) then
		error("Inventory open button is missing.")
	end

	self._ui.openButton = openButton
end

function InventoryController:_cacheUi(playerGui: PlayerGui)
	local mainInterface = playerGui:WaitForChild("MainInterface", 30)
	local modalRoot = playerGui:WaitForChild("ModalRoot", 30)
	if not (mainInterface and mainInterface:IsA("ScreenGui")) then
		error("PlayerGui.MainInterface is missing.")
	end
	if not (modalRoot and modalRoot:IsA("ScreenGui")) then
		error("PlayerGui.ModalRoot is missing.")
	end

	local inventoryRoot = modalRoot:WaitForChild("Inventory", 30)
	if not (inventoryRoot and inventoryRoot:IsA("GuiObject")) then
		error("PlayerGui.ModalRoot.Inventory is missing.")
	end

	local scrollingFrame = inventoryRoot:WaitForChild("ScrollingFrame", 30)
	local template = scrollingFrame:WaitForChild("Template", 30)
	local previewHolder = inventoryRoot:WaitForChild("ItemPreviewHolder", 30)
	local previewViewport = previewHolder:WaitForChild("ViewportFrame", 30)
	local previewIcon = previewHolder:WaitForChild("PreviewIcon", 30)
	local previewInfoFrame = previewHolder:WaitForChild("Info", 30)
	local previewStatsFrame = previewHolder:WaitForChild("Stats", 30)
	local infoViewButton = previewHolder:WaitForChild("InfoViewButton", 30)
	local statsViewButton = previewHolder:WaitForChild("StatsViewButton", 30)
	local favoriteButton = previewHolder:WaitForChild("FavoriteButton", 30)
	local sellButton = previewHolder:WaitForChild("SellButton", 30)
	local favoriteButtonLayout = captureGuiButtonLayout(favoriteButton)
	local sellButtonLayout = captureGuiButtonLayout(sellButton)
	local characterRoot = inventoryRoot:WaitForChild("Character", 30)
	local characterFrame = characterRoot:WaitForChild("Character", 30)
	local autoSizeButton = characterRoot:WaitForChild("GiftButton", 30)
	local autoSizeLabel = autoSizeButton:WaitForChild("Usage", 30)
	local sellAllButton = characterRoot:WaitForChild("SellAllButton", 30)
	local equipBestButton = characterRoot:WaitForChild("EquipBest", 30)
	local topBar = inventoryRoot:WaitForChild("TopBar", 30)
	local topBarButtons = topBar:WaitForChild("ItemTypes", 30)
	local potionSellFrame = modalRoot:WaitForChild("PotionSellFrame", 30)
	local openButton = mainInterface:WaitForChild("Main", 30):WaitForChild("ExtraButtons", 30):WaitForChild("Inventory", 30)
	local potionSellTitle = potionSellFrame:WaitForChild("Title", 30)
	local potionSellOwned = potionSellFrame:WaitForChild("Owned", 30)
	local potionSellQuantity = potionSellFrame:WaitForChild("Quantity", 30)
	local potionSellPayout = potionSellFrame:WaitForChild("Payout", 30)
	local potionSellIncrease = potionSellFrame:WaitForChild("Increase", 30)
	local potionSellDecrease = potionSellFrame:WaitForChild("Decrease", 30)
	local potionSellConfirm = potionSellFrame:WaitForChild("Confirm", 30)
	local potionSellNevermind = potionSellFrame:WaitForChild("Nevermind", 30)

	if not (
		scrollingFrame:IsA("ScrollingFrame")
		and template:IsA("Frame")
		and previewHolder:IsA("Frame")
		and previewViewport:IsA("ViewportFrame")
		and previewIcon:IsA("ImageLabel")
		and previewInfoFrame:IsA("Frame")
		and previewStatsFrame:IsA("Frame")
		and infoViewButton:IsA("GuiButton")
		and statsViewButton:IsA("GuiButton")
		and favoriteButton:IsA("GuiButton")
		and sellButton:IsA("GuiButton")
		and characterRoot:IsA("Frame")
		and characterFrame:IsA("ViewportFrame")
		and autoSizeButton:IsA("GuiButton")
		and sellAllButton:IsA("GuiButton")
		and equipBestButton:IsA("GuiButton")
		and topBar:IsA("Frame")
		and topBarButtons:IsA("Frame")
		and potionSellFrame:IsA("GuiObject")
		and potionSellTitle:IsA("TextLabel")
		and potionSellOwned:IsA("TextLabel")
		and potionSellQuantity:IsA("TextLabel")
		and potionSellPayout:IsA("TextLabel")
		and potionSellIncrease:IsA("GuiButton")
		and potionSellDecrease:IsA("GuiButton")
		and potionSellConfirm:IsA("GuiButton")
		and potionSellNevermind:IsA("GuiButton")
		and openButton:IsA("GuiButton")
	) then
		error("Inventory UI hierarchy is missing required instances.")
	end

	self._inventoryRoot = inventoryRoot
	self._scrollingFrame = scrollingFrame
	self._listTemplate = template
	self._slotCardRenderer = SlotCardRenderer.new(playerGui)

	local filterButtons = {}
	local auraButtons = {}
	local potionButtons = {}
	for _, child in ipairs(topBarButtons:GetChildren()) do
		if child:IsA("ImageButton") then
			if child.Name == "Auras" then
				table.insert(auraButtons, child)
			elseif child.Name == "Potions" then
				table.insert(potionButtons, child)
			elseif FILTER_BUTTON_TO_REGION[child.Name] then
				filterButtons[child.Name] = child
			end
		end
	end

	local slotButtons = {}
	local slotFrames = {}
	for _, region in ipairs(BodyPartRegions.Order) do
		local slotFrame = characterFrame:FindFirstChild(region)
		if slotFrame and slotFrame:IsA("Frame") then
			slotFrames[region] = slotFrame

			local slotButton = slotFrame:FindFirstChild("Temp")
			if slotButton and slotButton:IsA("ImageButton") then
				setGuiTreeZIndex(slotButton, SLOT_OVERLAY_Z_INDEX)
				slotButtons[region] = slotButton
				self._slotPlaceholderDefaults[region] = self:_captureSlotPlaceholderState(slotButton)
			end
		end
	end

	local auraSlotFrame = characterFrame:FindFirstChild("Aura")
	local auraSlotButton = nil
	if auraSlotFrame and auraSlotFrame:IsA("Frame") then
		auraSlotButton = auraSlotFrame:FindFirstChild("Temp")
		if auraSlotButton and auraSlotButton:IsA("ImageButton") then
			setGuiTreeZIndex(auraSlotButton, SLOT_OVERLAY_Z_INDEX)
			self._auraSlotPlaceholderDefault = self:_captureSlotPlaceholderState(auraSlotButton)
		else
			auraSlotButton = nil
		end
	end

	self._ui = {
		openButton = openButton,
		previewHolder = previewHolder,
		previewViewport = previewViewport,
		previewIcon = previewIcon,
		infoFrame = previewInfoFrame,
		statsFrame = previewStatsFrame,
		infoViewButton = infoViewButton,
		statsViewButton = statsViewButton,
		favoriteButton = favoriteButton,
		sellButton = sellButton,
		characterViewport = characterFrame,
		autoSizeButton = autoSizeButton,
		autoSizeLabel = autoSizeLabel,
		equipBestButton = equipBestButton,
		previewLabels = {
			Bundle = previewInfoFrame:WaitForChild("Bundle", 30),
			Part = previewInfoFrame:WaitForChild("Part", 30),
			Rarity = previewInfoFrame:WaitForChild("Rarity", 30),
			Mutation = previewInfoFrame:WaitForChild("Mutation", 30),
			Content = previewInfoFrame:WaitForChild("Content", 30),
			Existing = previewInfoFrame:WaitForChild("Existing", 30),
			Cash = previewInfoFrame:WaitForChild("Cash", 30),
			Chance = previewInfoFrame:WaitForChild("Chance", 30),
			EverRolled = previewInfoFrame:WaitForChild("EverRolled", 30),
		},
		previewStatLabels = collectPreviewStatLabels(previewStatsFrame),
		filterButtons = filterButtons,
		auraButtons = auraButtons,
		potionButtons = potionButtons,
		searchBox = topBar:WaitForChild("TextBox", 30),
		slotFrames = slotFrames,
		slotButtons = slotButtons,
		auraSlotFrame = if auraSlotFrame and auraSlotFrame:IsA("Frame") then auraSlotFrame else nil,
		auraSlotButton = auraSlotButton,
		equipButton = previewHolder:WaitForChild("EquipButton", 30),
		sellAllButton = sellAllButton,
		potionSellFrame = potionSellFrame,
		potionSellTitle = potionSellTitle,
		potionSellOwned = potionSellOwned,
		potionSellQuantity = potionSellQuantity,
		potionSellPayout = potionSellPayout,
		potionSellIncrease = potionSellIncrease,
		potionSellDecrease = potionSellDecrease,
		potionSellConfirm = potionSellConfirm,
		potionSellNevermind = potionSellNevermind,
		capacityLabel = inventoryRoot:WaitForChild("Capacity", 30),
		incomeLabel = inventoryRoot:WaitForChild("Character", 30):WaitForChild("Income", 30),
		luckLabel = inventoryRoot:WaitForChild("Character", 30):WaitForChild("Luck", 30),
		rollSpeedLabel = inventoryRoot:WaitForChild("Character", 30):WaitForChild("Roll Speed", 30),
	}
	if self._ui.autoSizeLabel and self._ui.autoSizeLabel:IsA("TextLabel") then
		local descriptionText = string.match(self._ui.autoSizeLabel.Text, "<br%s*/?>%s*(.+)$")
		if typeof(descriptionText) == "string" and descriptionText ~= "" then
			self._autoSizeDescriptionText = descriptionText
		end
	end
	self._autoSizeButtonVisualEntries = self:_captureAutoSizeButtonVisualEntries(autoSizeButton, autoSizeLabel)
	self._previewLabelFontFaces = {
		Bundle = self._ui.previewLabels.Bundle.FontFace,
		Rarity = self._ui.previewLabels.Rarity.FontFace,
	}
	self._previewSecondaryActionButtonLayouts = {
		favorite = favoriteButtonLayout,
		sell = sellButtonLayout,
		auraFavorite = buildHorizontalSpanLayout(favoriteButtonLayout, sellButtonLayout),
	}
	self._previewLabelLayouts = capturePreviewLabelLayouts(self._ui.previewLabels)
	self._previewStatNativeTexts = {}
	for _, statName in ipairs(PREVIEW_STAT_NAMES) do
		local label = self._ui.previewStatLabels[statName]
		if label and label:IsA("TextLabel") then
			self._previewStatNativeTexts[statName] = label.Text
		end
	end
	self._previewEverRolledNativeText = self._ui.previewLabels.EverRolled.Text
	self._previewEverRolledSuffixText = extractTrailingLabelText(self._previewEverRolledNativeText, "Ever Rolled")

	if potionSellFrame.ZIndex < SELL_WARNING_Z_INDEX then
		shiftGuiTreeZIndex(potionSellFrame, SELL_WARNING_Z_INDEX - potionSellFrame.ZIndex)
	end

	self._listTemplate.Visible = false
	self._scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	self._inventoryRoot.AnchorPoint = Vector2.new(INVENTORY_DEFAULT_ANCHOR_X, INVENTORY_ANCHOR_Y)
	self._ui.previewHolder.Visible = false
	self:_setPreviewTab("info")
	self._ui.previewIcon.Visible = false
	self._ui.potionSellFrame.Visible = false
end

function InventoryController:_ensureFullUi(playerGui: PlayerGui)
	if self._fullUiReady then
		return
	end

	self:_cacheUi(playerGui)

	self:_bindFilterButtons()
	self:_bindSlotButtons()

	UIController:CreateButton(self._ui.equipButton, function()
		local previewState = self._previewState
		if previewState and previewState.itemType == "bodyPart" and previewState.kind == "equipped" and previewState.region then
			self:_unequipPreviewedRegion()
		else
			self:_equipSelectedOwnedItem()
		end
	end)
	UIController:CreateButton(self._ui.favoriteButton, function()
		self:_toggleFavoriteForPreviewedItem()
	end)
	UIController:CreateButton(self._ui.sellButton, function()
		self:_sellPreviewedItem()
	end)
	UIController:CreateButton(self._ui.infoViewButton, function()
		self:_setPreviewTab("info")
	end)
	UIController:CreateButton(self._ui.statsViewButton, function()
		self:_setPreviewTab("stats")
	end)
	UIController:CreateButton(self._ui.autoSizeButton, function()
		self:_toggleAutoSize()
	end)
	UIController:CreateButton(self._ui.equipBestButton, function()
		self:_equipBestLoadout()
	end)
	UIController:CreateButton(self._ui.sellAllButton, function()
		self:_promptSellAllConfirmation()
	end)
	UIController:CreateButton(self._ui.potionSellNevermind, function()
		self:_setPotionSellModalVisible(false)
	end)
	UIController:CreateButton(self._ui.potionSellConfirm, function()
		self:_confirmPotionSell()
	end)
	UIController:CreateButton(self._ui.potionSellIncrease, function()
		self:_changePotionSellQuantity(1)
	end)
	UIController:CreateButton(self._ui.potionSellDecrease, function()
		self:_changePotionSellQuantity(-1)
	end)

	if self._ui.searchBox and self._ui.searchBox:IsA("TextBox") then
		self._ui.searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			self._searchText = self._ui.searchBox.Text
			self:_syncList()
		end)
	end

	if not self._dataBindingsReady then
		DataController.DataReceived:Connect(function()
			self:_markInventoryRecordsDirty()
			if not FrameController:IsOpen(WINDOW_NAME) then
				return
			end
			self:_syncList()
			self:_syncPreview()
			self:_syncActionButton()
			self:_syncSecondaryActionButtons()
			self:_syncAutoSizeButton(nil, false)
			self._autoSizeStateHydrated = true
			self:_refreshAuraStateFromData()
			self:_syncPotionSellModal()
		end)

		DataController.DataUpdated:Connect(function(key)
			if key == BODY_PARTS_DATA_KEY then
				self:_scheduleBodyPartRefresh()
				return
			end

			if key == AUTO_SIZE_ENABLED_KEY then
				local autoSizeEnabled = self:_getResolvedAutoSizeEnabled()
				local isEnabled = self:_getResolvedNormalSizeEnabled(autoSizeEnabled)
				local shouldAnimate = self._autoSizeStateHydrated
					and self._autoSizeVisualState ~= nil
					and self._autoSizeVisualState ~= isEnabled
				self:_syncAutoSizeButton(autoSizeEnabled, shouldAnimate)
				self._autoSizeStateHydrated = true
				return
			end

			if key == AURA_DATA_KEY or key == EQUIPPED_AURA_ID_KEY then
				self:_scheduleAuraStateRefresh()
			end
		end)

		PotionController.StateUpdated:Connect(function()
			self:_markInventoryRecordsDirty()
			if not FrameController:IsOpen(WINDOW_NAME) then
				return
			end
			self:_syncList()
			self:_syncPreview()
			self:_syncSummaryLabels()
			self:_syncActionButton()
			self:_syncSecondaryActionButtons()
			self:_syncPotionSellModal()
		end)

		LOCAL_PLAYER.CharacterAdded:Connect(function()
			self:_invalidateCharacterPreviewModel()
			if FrameController:IsOpen(WINDOW_NAME) then
				task.defer(function()
					self:_syncCharacterViewport()
				end)
			end
		end)

		LOCAL_PLAYER.CharacterRemoving:Connect(function()
			self:_invalidateCharacterPreviewModel()
		end)

		task.spawn(function()
			while not self:_ensureRemotes() do
				task.wait(1)
			end

			self._remotes.updated.OnClientEvent:Connect(function(state)
				self:_applyLoadoutState(state)
			end)

			self:_requestLoadoutState()
		end)

		task.spawn(function()
			while not self:_ensureAuraRemotes() do
				task.wait(1)
			end

			local ok, result = pcall(function()
				return self._remotes.auraGetState:InvokeServer()
			end)
			if ok and typeof(result) == "table" and result.ok == true and typeof(result.state) == "table" then
				self:_applyAuraState(result.state)
			else
				self:_refreshAuraStateFromData()
			end
		end)

		self._dataBindingsReady = true
	end

	self._fullUiReady = true
end

function InventoryController:OnStart()
	self:_ensureState()

	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	self._playerGui = playerGui
	self:_cacheOpenButton(playerGui)

	if not self._openButtonBound then
		self:_bindOpenButton(self._ui.openButton)
		self._openButtonBound = true
	end
end

return InventoryController
