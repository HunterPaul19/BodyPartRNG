local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local NumberFormatter = require(ReplicatedStorage.Shared.Formatting.NumberFormatter)
local BodyPartLoadout = require(ReplicatedStorage.Shared.Character.BodyPartLoadout)
local BodyPartRegions = require(ReplicatedStorage.Shared.Character.BodyPartRegions)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local ViewportModelRenderer = require(ReplicatedStorage.Shared.UI.ViewportModelRenderer)
local DataController = require(script.Parent.DataController)
local FrameController = require(script.Parent.FrameController)
local UIController = require(script.Parent.UIController)

local LOCAL_PLAYER = Players.LocalPlayer
local WINDOW_NAME = "Inventory"
local BODY_PARTS_DATA_KEY = "bodyParts"
local BODY_PARTS_REMOTES_FOLDER_NAME = "BodyParts"
local GET_STATE_REMOTE_NAME = "GetSessionLoadout"
local EQUIP_REMOTE_NAME = "EquipOwnedBodyPart"
local UPDATED_REMOTE_NAME = "LoadoutUpdated"
local ITEM_COUNT_COLOR = Color3.fromRGB(205, 200, 0)
local MUTATION_COLOR = Color3.fromRGB(210, 201, 0)
local FALLBACK_TEXT_COLOR = Color3.fromRGB(170, 170, 170)
local SELECTED_COLOR = Color3.fromRGB(116, 192, 255)
local EQUIPPED_COLOR = Color3.fromRGB(113, 230, 139)
local DEFAULT_OUTLINE_COLOR = Color3.fromRGB(255, 255, 255)
local INVENTORY_DEFAULT_ANCHOR_X = 0.4
local INVENTORY_PREVIEW_ANCHOR_X = 0.5
local INVENTORY_ANCHOR_Y = 0.5
local INVENTORY_ANCHOR_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local FILTER_BUTTON_TO_REGION = {
	Heads = "Head",
	Torsos = "Torso",
	LeftArms = "LeftArm",
	RightArms = "RightArm",
	LeftLegs = "LeftLeg",
	RightLegs = "RightLeg",
}

local REGION_TO_LABEL = {
	Head = "Head",
	Torso = "Torso",
	LeftArm = "Left Arm",
	RightArm = "Right Arm",
	LeftLeg = "Left Leg",
	RightLeg = "Right Leg",
}

local REGION_TO_PLURAL_LABEL = {
	Head = "Heads",
	Torso = "Torsos",
	LeftArm = "Left Arms",
	RightArm = "Right Arms",
	LeftLeg = "Left Legs",
	RightLeg = "Right Legs",
}

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
}

type BodyPartClientState = {
	equipped: BodyPartLoadout.EquippedState?,
	ownedBodyParts: { [string]: OwnedBodyPartRecord }?,
	bonuses: {
		passiveIncomePerSecond: number?,
		luckBonus: number?,
		rollSpeedBonus: number?,
		activeSetId: string?,
	}?,
	message: string?,
}

type PreviewState = {
	kind: "owned" | "equipped",
	ownedId: string?,
	region: string?,
	entry: BodyPartLoadout.LoadoutEntry?,
}

type InventoryRecordView = {
	ownedId: string,
	record: OwnedBodyPartRecord,
	piece: any,
	setConfig: any,
	bundleModel: Model?,
	searchText: string,
}

local InventoryController = {}

local function showNotification(text: string, title: string?)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = title or "Inventory",
			Text = tostring(text),
			Duration = 4,
		})
	end)
end

local function toRichTextColor(color: Color3): string
	return string.format(
		"rgb(%d,%d,%d)",
		math.round(color.R * 255),
		math.round(color.G * 255),
		math.round(color.B * 255)
	)
end

local function formatNumberish(value: number?): string
	local numericValue = tonumber(value) or 0
	if math.abs(numericValue - math.round(numericValue)) < 0.005 then
		return NumberFormatter.Format(math.round(numericValue))
	end

	return string.format("%.2f", numericValue):gsub("0+$", ""):gsub("%.$", "")
end

local function formatMoneyPerSecond(value: number?): string
	return string.format("$%s/s", formatNumberish(value))
end

local function formatMultiplier(value: number?): string
	local numericValue = math.max(0, tonumber(value) or 0)
	local roundedTenths = math.round(numericValue * 10) / 10
	if math.abs(numericValue - roundedTenths) < 0.005 then
		return string.format("%.1f", roundedTenths)
	end

	return string.format("%.2f", numericValue):gsub("0+$", ""):gsub("%.$", "")
end

local function formatChance(value: number?): string
	local denominator = math.max(1, math.floor(tonumber(value) or 1))
	return string.format("1/%s", formatNumberish(denominator))
end

local function getSizeDescriptor(scale: number?): string
	local numericScale = tonumber(scale) or 1
	if numericScale <= 0.5 then
		return "Tiny"
	elseif numericScale < 0.95 then
		return "Small"
	elseif numericScale <= 1.05 then
		return "Normal"
	elseif numericScale < 1.5 then
		return "Large"
	else
		return "Huge"
	end
end

local function getRecordPassiveIncomePerSecond(record: OwnedBodyPartRecord?, piece): number
	return tonumber(record and record.finalPassiveIncomePerSecond) or tonumber(piece and piece.passiveIncomePerSecond) or 0
end

function InventoryController:_ensureState()
	if self._started then
		return
	end

	self._started = true
	self._inventoryRoot = nil
	self._listTemplate = nil
	self._scrollingFrame = nil
	self._ui = {}
	self._remotes = {}
	self._loadoutState = nil :: BodyPartClientState?
	self._selectedFilterRegion = nil :: string?
	self._selectedOwnedId = nil :: string?
	self._previewState = nil :: PreviewState?
	self._searchText = ""
	self._rowsByOwnedId = {}
	self._inventoryAnchorTween = nil
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

	local fallback = self._loadoutState and self._loadoutState.ownedBodyParts
	if typeof(fallback) == "table" then
		return fallback
	end

	return {}
end

function InventoryController:_getRemotesFolder(): Folder?
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

function InventoryController:_ensureRemotes(): boolean
	if self._remotes.getState and self._remotes.equip and self._remotes.updated then
		return true
	end

	local bodyPartsFolder = self:_getRemotesFolder()
	if not bodyPartsFolder then
		return false
	end

	local getStateRemote = bodyPartsFolder:FindFirstChild(GET_STATE_REMOTE_NAME)
	local equipRemote = bodyPartsFolder:FindFirstChild(EQUIP_REMOTE_NAME)
	local updatedRemote = bodyPartsFolder:FindFirstChild(UPDATED_REMOTE_NAME)

	if not (getStateRemote and getStateRemote:IsA("RemoteFunction")) then
		return false
	end
	if not (equipRemote and equipRemote:IsA("RemoteFunction")) then
		return false
	end
	if not (updatedRemote and updatedRemote:IsA("RemoteEvent")) then
		return false
	end

	self._remotes.getState = getStateRemote
	self._remotes.equip = equipRemote
	self._remotes.updated = updatedRemote
	return true
end

function InventoryController:_resolvePreviewModel()
	local previewState = self._previewState
	if not previewState then
		return nil
	end

	local ownedLookup = self:_getOwnedLookup()
	local ownedRecord = previewState.ownedId and ownedLookup[previewState.ownedId] or nil
	local entry = previewState.entry
	local pieceId = if ownedRecord then ownedRecord.pieceId else if entry then entry.pieceId else nil
	local piece = if pieceId then BodyPartsCatalog.GetPiece(pieceId) else nil
	local setConfig = if piece then BodyPartsCatalog.GetSetForPiece(piece.id) else nil
	if not piece then
		return nil
	end

	local previewScale = if entry and typeof(entry.scale) == "number" then entry.scale else ownedRecord and ownedRecord.sizeMultiplier or 1
	local rarityChance = ownedRecord and (ownedRecord.displayOddsDenominator or ownedRecord.rarityDenominator) or setConfig and setConfig.rollDisplay and setConfig.rollDisplay.chance or piece.rarity
	local mutation = if ownedRecord and ownedRecord.mutation and ownedRecord.mutation ~= "" then ownedRecord.mutation else "None"
	local mutationColor = if mutation == "None" then FALLBACK_TEXT_COLOR else MUTATION_COLOR
	local bundleName = if ownedRecord and ownedRecord.rolledSetDisplayName and ownedRecord.rolledSetDisplayName ~= ""
		then ownedRecord.rolledSetDisplayName
		else if setConfig and setConfig.rollDisplay and setConfig.rollDisplay.displayName then setConfig.rollDisplay.displayName else piece.displayName
	local bundleSuffix = if ownedRecord and ownedRecord.serialNumber then string.format(" (#%s)", tostring(ownedRecord.serialNumber)) else ""
	local displayRarity = if ownedRecord and ownedRecord.displayRarity and ownedRecord.displayRarity ~= ""
		then ownedRecord.displayRarity
		else tostring(setConfig and setConfig.rollDisplay and setConfig.rollDisplay.rarity or "Unknown")
	local passiveIncomePerSecond = getRecordPassiveIncomePerSecond(ownedRecord, piece)

	return {
		bundleText = string.format(
			'Bundle: <font color="%s">%s</font>%s',
			toRichTextColor(if setConfig and setConfig.rollDisplay and setConfig.rollDisplay.color then setConfig.rollDisplay.color else EQUIPPED_COLOR),
			tostring(bundleName),
			bundleSuffix
		),
		partText = string.format("Part: %s", REGION_TO_LABEL[piece.region] or tostring(piece.region)),
		rarityText = string.format(
			'Rarity: <font color="%s">%s</font>',
			toRichTextColor(if setConfig and setConfig.rollDisplay and setConfig.rollDisplay.color then setConfig.rollDisplay.color else FALLBACK_TEXT_COLOR),
			displayRarity
		),
		mutationText = string.format(
			'Mutation: <font color="%s">%s</font>',
			toRichTextColor(mutationColor),
			mutation
		),
		sizeText = string.format("Size: %s (%sx)", getSizeDescriptor(previewScale), formatMultiplier(previewScale)),
		existingText = "Existing: ??? Exist",
		cashText = string.format(
			'Cash Per Sec: <font color="%s">%s</font>',
			toRichTextColor(ITEM_COUNT_COLOR),
			formatMoneyPerSecond(passiveIncomePerSecond)
		),
		chanceText = string.format("Chance: %s", formatChance(rarityChance)),
		bundleModel = BodyPartsCatalog.ResolveBundleModel(piece.id),
	}
end

function InventoryController:_setPreviewState(previewState: PreviewState?)
	self._previewState = previewState
	self:_syncPreview()
	self:_syncSlotButtons()
end

function InventoryController:_clearPreview()
	self._selectedOwnedId = nil
	self:_setPreviewState(nil)
	self:_syncList()
	self:_syncEquipButton()
end

function InventoryController:_setSelectedOwnedItem(ownedId: string)
	self._selectedOwnedId = ownedId
	self:_setPreviewState({
		kind = "owned",
		ownedId = ownedId,
	})
	self:_syncList()
	self:_syncEquipButton()
end

function InventoryController:_setPreviewForRegion(region: string)
	local equipped = self._loadoutState and self._loadoutState.equipped
	local entry = equipped and equipped[region]
	self._selectedOwnedId = nil

	if entry then
		self:_setPreviewState({
			kind = "equipped",
			ownedId = entry.ownedId,
			region = region,
			entry = entry,
		})
	else
		self:_setPreviewState(nil)
	end

	self:_syncList()
	self:_syncEquipButton()
end

function InventoryController:_getInventoryRecords(): { InventoryRecordView }
	local records = {}

	for ownedId, record in pairs(self:_getOwnedLookup()) do
		if typeof(record) ~= "table" then
			continue
		end

		local piece = record.pieceId and BodyPartsCatalog.GetPiece(record.pieceId)
		if not piece then
			continue
		end

		local setConfig = BodyPartsCatalog.GetSetForPiece(piece.id)
		local searchText = string.lower(
			string.format(
				"%s %s",
				tostring(piece.displayName or ""),
				tostring(setConfig and setConfig.displayName or "")
			)
		)

		table.insert(records, {
			ownedId = ownedId,
			record = record,
			piece = piece,
			setConfig = setConfig,
			bundleModel = BodyPartsCatalog.ResolveBundleModel(piece.id),
			searchText = searchText,
		})
	end

	table.sort(records, function(a, b)
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

	return records
end

function InventoryController:_getVisibleRecords(): { InventoryRecordView }
	local visibleRecords = {}
	local searchText = string.lower(self._searchText or "")
	local selectedFilterRegion = self._selectedFilterRegion

	for _, record in ipairs(self:_getInventoryRecords()) do
		if selectedFilterRegion and record.piece.region ~= selectedFilterRegion then
			continue
		end

		if searchText ~= "" and not string.find(record.searchText, searchText, 1, true) then
			continue
		end

		table.insert(visibleRecords, record)
	end

	return visibleRecords
end

function InventoryController:_setOutlineColor(button: GuiButton, color: Color3, transparency: number)
	local outline = button:FindFirstChild("Outline")
	if outline and outline:IsA("ImageLabel") then
		outline.ImageColor3 = color
		outline.ImageTransparency = transparency
	end
end

function InventoryController:_syncFilterButtons()
	local activeRegion = self._selectedFilterRegion

	for buttonName, button in pairs(self._ui.filterButtons) do
		local isActive = FILTER_BUTTON_TO_REGION[buttonName] == activeRegion
		self:_setOutlineColor(button, if isActive then SELECTED_COLOR else DEFAULT_OUTLINE_COLOR, if isActive then 0 else 0.2)
	end
end

function InventoryController:_syncSlotButtons()
	local equipped = self._loadoutState and self._loadoutState.equipped or {}
	local previewState = self._previewState

	for region, button in pairs(self._ui.slotButtons) do
		local entry = equipped and equipped[region]
		local isPreviewRegion = previewState ~= nil and previewState.kind == "equipped" and previewState.region == region
		local outlineColor = DEFAULT_OUTLINE_COLOR
		local outlineTransparency = 0.3

		if isPreviewRegion then
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
end

function InventoryController:_syncCapacityLabel()
	local visibleCount = #self:_getVisibleRecords()
	local label = "Body Parts"
	if self._selectedFilterRegion then
		label = REGION_TO_PLURAL_LABEL[self._selectedFilterRegion] or self._selectedFilterRegion
	end

	self._ui.capacityLabel.Text = string.format("%d/100 %s", visibleCount, label)
end

function InventoryController:_syncSummaryLabels()
	local bonuses = self._loadoutState and self._loadoutState.bonuses or {}
	local passiveIncome = tonumber(bonuses.passiveIncomePerSecond) or 0
	local luckBonus = tonumber(bonuses.luckBonus) or 0
	local rollSpeedBonus = tonumber(bonuses.rollSpeedBonus) or 0

	self._ui.incomeLabel.Text = string.format("%s Income", formatMoneyPerSecond(passiveIncome))
	self._ui.luckLabel.Text = string.format("x%s Luck", formatMultiplier(1 + luckBonus))
	self._ui.rollSpeedLabel.Text = string.format("x%s Roll Speed", formatMultiplier(1 + rollSpeedBonus))
end

function InventoryController:_syncPreview()
	local previewHolder = self._ui.previewHolder
	local previewModel = self:_resolvePreviewModel()
	previewHolder.Visible = previewModel ~= nil

	if not previewModel then
		ViewportModelRenderer.Clear(self._ui.previewViewport)
		self:_syncInventoryAnchor(false)
		return
	end

	ViewportModelRenderer.RenderBundle(self._ui.previewViewport, previewModel.bundleModel)
	self._ui.previewLabels.Bundle.Text = previewModel.bundleText
	self._ui.previewLabels.Part.Text = previewModel.partText
	self._ui.previewLabels.Rarity.Text = previewModel.rarityText
	self._ui.previewLabels.Mutation.Text = previewModel.mutationText
	self._ui.previewLabels.Content.Text = previewModel.sizeText
	self._ui.previewLabels.Existing.Text = previewModel.existingText
	self._ui.previewLabels.Cash.Text = previewModel.cashText
	self._ui.previewLabels.Chance.Text = previewModel.chanceText
	self:_syncInventoryAnchor(true)
end

function InventoryController:_syncCharacterViewport()
	ViewportModelRenderer.RenderBaseRig(self._ui.characterViewport, BodyPartsCatalog.GetDefaultBaseRig())
end

function InventoryController:_syncEquipButton()
	local equipButton = self._ui.equipButton
	local selectedRecord = self._selectedOwnedId and self:_getOwnedLookup()[self._selectedOwnedId] or nil
	local enabled = selectedRecord ~= nil

	equipButton.Active = enabled
	equipButton.AutoButtonColor = false

	local buttonText = equipButton:FindFirstChild("TextLabel")
	if buttonText and buttonText:IsA("TextLabel") then
		buttonText.TextTransparency = if enabled then 0 else 0.35
	end

	for _, child in ipairs(equipButton:GetChildren()) do
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
	local scrollingFrame = self._scrollingFrame
	local template = self._listTemplate
	local selectedOwnedId = self._selectedOwnedId

	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child ~= template and child:IsA("Frame") then
			child:Destroy()
		end
	end

	self._rowsByOwnedId = {}

	for index, recordView in ipairs(self:_getVisibleRecords()) do
		local row = template:Clone()
		row.Name = string.format("Owned_%s", recordView.ownedId)
		row.Visible = true
		row.LayoutOrder = index
		row.Parent = scrollingFrame

		local base = row:FindFirstChild("Base")
		if base and base:IsA("ImageButton") then
			local itemName = base:FindFirstChild("ItemName")
			if itemName and itemName:IsA("TextLabel") then
				itemName.Text = recordView.piece.displayName
			end

			local itemCount = base:FindFirstChild("ItemCount")
			if itemCount and itemCount:IsA("TextLabel") then
				itemCount.Text = formatMoneyPerSecond(getRecordPassiveIncomePerSecond(recordView.record, recordView.piece))
			end

			local itemViewport = base:FindFirstChild("ItemViewport")
			if itemViewport and itemViewport:IsA("ViewportFrame") then
				ViewportModelRenderer.RenderBundle(itemViewport, recordView.bundleModel)
			end

			UIController:CreateButton(base, function()
				self:_setSelectedOwnedItem(recordView.ownedId)
			end)

			self._rowsByOwnedId[recordView.ownedId] = base
		end
	end

	for ownedId, button in pairs(self._rowsByOwnedId) do
		local isSelected = ownedId == selectedOwnedId
		self:_setOutlineColor(button, if isSelected then SELECTED_COLOR else DEFAULT_OUTLINE_COLOR, if isSelected then 0 else 0.22)
	end
end

function InventoryController:_syncList()
	self:_refreshRows()
	self:_syncCapacityLabel()
end

function InventoryController:_applyLoadoutState(state: BodyPartClientState?)
	self._loadoutState = if typeof(state) == "table" then state else nil

	local selectedOwnedId = self._selectedOwnedId
	if selectedOwnedId and self:_getOwnedLookup()[selectedOwnedId] == nil then
		self._selectedOwnedId = nil
	end

	local previewState = self._previewState
	if previewState and previewState.kind == "owned" and previewState.ownedId and self:_getOwnedLookup()[previewState.ownedId] == nil then
		self._previewState = nil
	elseif previewState and previewState.kind == "equipped" and previewState.region then
		local equipped = self._loadoutState and self._loadoutState.equipped
		local entry = equipped and equipped[previewState.region]
		if entry then
			self._previewState = {
				kind = "equipped",
				ownedId = entry.ownedId,
				region = previewState.region,
				entry = entry,
			}
		else
			self._previewState = nil
		end
	end

	self:_syncList()
	self:_syncPreview()
	self:_syncSummaryLabels()
	self:_syncSlotButtons()
	self:_syncEquipButton()
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

function InventoryController:_bindFilterButtons()
	for buttonName, region in pairs(FILTER_BUTTON_TO_REGION) do
		local button = self._ui.filterButtons[buttonName]
		if button then
			UIController:CreateButton(button, function()
				if self._selectedFilterRegion == region then
					self._selectedFilterRegion = nil
				else
					self._selectedFilterRegion = region
				end

				self:_syncFilterButtons()
				self:_syncList()
			end)
		end
	end

	for _, auraButton in ipairs(self._ui.auraButtons) do
		auraButton.Visible = false
		auraButton.Active = false
	end
end

function InventoryController:_bindSlotButtons()
	for region, button in pairs(self._ui.slotButtons) do
		UIController:CreateButton(button, function()
			self:_setPreviewForRegion(region)
		end)
	end
end

function InventoryController:_bindOpenButton(openButton: GuiButton)
	UIController:CreateButton(openButton, function()
		local wasOpen = FrameController:IsOpen(WINDOW_NAME)
		FrameController:ToggleFrame(WINDOW_NAME)
		if not wasOpen then
			task.defer(function()
				self:_syncCharacterViewport()
				self:_syncPreview()
				self:_requestLoadoutState()
			end)
		end
	end)
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
	local previewDetails = previewHolder:WaitForChild("Frame", 30)
	local characterRoot = inventoryRoot:WaitForChild("Character", 30)
	local characterFrame = characterRoot:WaitForChild("Character", 30)
	local topBar = inventoryRoot:WaitForChild("TopBar", 30)
	local topBarButtons = topBar:WaitForChild("ItemTypes", 30)
	local openButton = mainInterface:WaitForChild("Main", 30):WaitForChild("ExtraButtons", 30):WaitForChild("Inventory", 30)

	if not (
		scrollingFrame:IsA("ScrollingFrame")
		and template:IsA("Frame")
		and previewHolder:IsA("Frame")
		and previewViewport:IsA("ViewportFrame")
		and characterRoot:IsA("Frame")
		and characterFrame:IsA("ViewportFrame")
		and topBar:IsA("Frame")
		and topBarButtons:IsA("Frame")
		and openButton:IsA("GuiButton")
	) then
		error("Inventory UI hierarchy is missing required instances.")
	end

	self._inventoryRoot = inventoryRoot
	self._scrollingFrame = scrollingFrame
	self._listTemplate = template

	local filterButtons = {}
	local auraButtons = {}
	for _, child in ipairs(topBarButtons:GetChildren()) do
		if child:IsA("ImageButton") then
			if child.Name == "Auras" then
				table.insert(auraButtons, child)
			elseif FILTER_BUTTON_TO_REGION[child.Name] then
				filterButtons[child.Name] = child
			end
		end
	end

	local slotButtons = {}
	for _, region in ipairs(BodyPartRegions.Order) do
		local slotFrame = characterFrame:FindFirstChild(region)
		if slotFrame and slotFrame:IsA("Frame") then
			local slotButton = slotFrame:FindFirstChild("Temp")
			if slotButton and slotButton:IsA("ImageButton") then
				slotButtons[region] = slotButton
			end
		end
	end

	self._ui = {
		openButton = openButton,
		previewHolder = previewHolder,
		previewViewport = previewViewport,
		characterViewport = characterFrame,
		previewLabels = {
			Bundle = previewDetails:WaitForChild("Bundle", 30),
			Part = previewDetails:WaitForChild("Part", 30),
			Rarity = previewDetails:WaitForChild("Rarity", 30),
			Mutation = previewDetails:WaitForChild("Mutation", 30),
			Content = previewDetails:WaitForChild("Content", 30),
			Existing = previewDetails:WaitForChild("Existing", 30),
			Cash = previewDetails:WaitForChild("Cash", 30),
			Chance = previewDetails:WaitForChild("Chance", 30),
		},
		filterButtons = filterButtons,
		auraButtons = auraButtons,
		searchBox = topBar:WaitForChild("TextBox", 30),
		slotButtons = slotButtons,
		equipButton = previewHolder:WaitForChild("EquipButton", 30),
		capacityLabel = inventoryRoot:WaitForChild("Capacity", 30),
		incomeLabel = inventoryRoot:WaitForChild("Character", 30):WaitForChild("Income", 30),
		luckLabel = inventoryRoot:WaitForChild("Character", 30):WaitForChild("Luck", 30),
		rollSpeedLabel = inventoryRoot:WaitForChild("Character", 30):WaitForChild("Roll Speed", 30),
	}

	self._listTemplate.Visible = false
	self._scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	self._inventoryRoot.AnchorPoint = Vector2.new(INVENTORY_DEFAULT_ANCHOR_X, INVENTORY_ANCHOR_Y)
	self._ui.previewHolder.Visible = false
end

function InventoryController:OnStart()
	self:_ensureState()

	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	self:_cacheUi(playerGui)

	self:_bindOpenButton(self._ui.openButton)
	self:_bindFilterButtons()
	self:_bindSlotButtons()

	UIController:CreateButton(self._ui.equipButton, function()
		self:_equipSelectedOwnedItem()
	end)

	if self._ui.searchBox and self._ui.searchBox:IsA("TextBox") then
		self._ui.searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			self._searchText = self._ui.searchBox.Text
			self:_syncList()
		end)
	end

	DataController.DataReceived:Connect(function()
		self:_syncList()
		self:_syncPreview()
		self:_syncEquipButton()
	end)

	DataController.DataUpdated:Connect(function(key)
		if key ~= BODY_PARTS_DATA_KEY then
			return
		end

		self:_syncList()
		self:_syncPreview()
		self:_syncEquipButton()
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

	self:_syncFilterButtons()
	self:_syncSlotButtons()
	self:_syncList()
	self:_syncCharacterViewport()
	self:_syncSummaryLabels()
	self:_syncEquipButton()
end

return InventoryController
