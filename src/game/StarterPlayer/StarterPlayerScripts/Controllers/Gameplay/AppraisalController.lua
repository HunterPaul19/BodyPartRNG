local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Schema = require(ReplicatedStorage.Lists.Schema)
local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)
local BodyPartEconomy = require(ReplicatedStorage.Shared.Character.BodyPartEconomy)
local AppraisalPricing = require(ReplicatedStorage.Shared.Character.AppraisalPricing)
local AppraisalState = require(ReplicatedStorage.Shared.Character.AppraisalState)
local BodyPartLoadout = require(ReplicatedStorage.Shared.Character.BodyPartLoadout)
local BodyPartRegions = require(ReplicatedStorage.Shared.Character.BodyPartRegions)
local NumberFormatter = require(ReplicatedStorage.Shared.Formatting.NumberFormatter)
local AppraisalConfig = require(ReplicatedStorage.Shared.Config.AppraisalConfig)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local SizeConfig = require(ReplicatedStorage.Shared.Config.SizeConfig)
local LocalizationKeys = require(ReplicatedStorage.Shared.Localization.Keys)
local TranslationHelper = require(ReplicatedStorage.Shared.Localization.TranslationHelper)
local BodyPartPresentation = require(ReplicatedStorage.Shared.UI.BodyPartPresentation)
local ConfirmationWarning = require(ReplicatedStorage.Shared.UI.ConfirmationWarning)
local RollWarningNotifier = require(ReplicatedStorage.Shared.UI.RollWarningNotifier)
local ViewportModelRenderer = require(ReplicatedStorage.Shared.UI.ViewportModelRenderer)

local DataController = require(script.Parent.DataController)
local MerchantPresentationController = require(script.Parent.MerchantPresentationController)
local SlotCardRenderer = require(script.Parent.SlotCardRenderer)
local UIController = require(script.Parent.UIController)

local LOCAL_PLAYER = Players.LocalPlayer
local WINDOW_NAME = "AppraisalUI"
local REMOTES_FOLDER_NAME = "Remotes"
local APPRAISAL_FOLDER_NAME = "Appraisal"
local GET_STATE_REMOTE_NAME = "GetState"
local PERFORM_APPRAISAL_REMOTE_NAME = "PerformAppraisal"
local UPDATED_REMOTE_NAME = "Updated"
local BODY_PARTS_DATA_KEY = Schema.BodyParts and Schema.BodyParts.key or "bodyParts"
local EQUIPPED_LOADOUT_KEY = Schema.EquippedLoadout and Schema.EquippedLoadout.key or "equippedLoadout"
local SELECTED_COLOR = Color3.fromRGB(116, 192, 255)
local EQUIPPED_COLOR = Color3.fromRGB(113, 230, 139)
local DEFAULT_OUTLINE_COLOR = Color3.fromRGB(255, 255, 255)
local DEFAULT_DIALOGUE_NAME = "Appraiser"
local ACTIVE_STATUS_TEXT = "Appraisal rerolls size and mutation for the selected body part."
local INACTIVE_STATUS_TEXT = "Appraisal is unavailable right now."
local DEFAULT_MUTATION_ID = MutationConfig.GetDefault().id
local HIGH_SIZE_IDS = table.freeze({
	large = true,
	huge = true,
	titanic = true,
})

type SlotPlaceholderState = {
	imageTransparency: number,
	children: {
		[string]: {
			visible: boolean,
		},
	},
}

type AppraisalRemotes = {
	getState: RemoteFunction,
	performAppraisal: RemoteFunction,
	updated: RemoteEvent,
}

type PreviewLabels = {
	Bundle: TextLabel,
	Part: TextLabel,
	Rarity: TextLabel,
	Mutation: TextLabel,
	Content: TextLabel,
	Existing: TextLabel,
	Cash: TextLabel,
	Chance: TextLabel,
}

type AppraisalUi = {
	root: GuiObject,
	selectTextLabel: TextLabel,
	selectedLabel: TextLabel,
	slotFrames: { [string]: Frame },
	slotButtons: { [string]: ImageButton },
	previewHolder: Frame,
	previewLabels: PreviewLabels,
	dialogueNameLabel: TextLabel,
	serverStockLabel: TextLabel,
	priceLabel: TextLabel,
	statusLabel: TextLabel,
	rollButton: ImageButton,
	rollButtonLabel: TextLabel?,
	viewportFrame: ViewportFrame?,
	messageRoot: GuiButton,
	messageTitle: TextLabel?,
	messageDescription: TextLabel?,
	messageClose: GuiButton?,
}

local AppraisalController = {}

local function setOutlineColor(button: GuiButton?, color: Color3, transparency: number)
	if not button then
		return
	end

	local outline = button:FindFirstChild("Outline")
	if outline and outline:IsA("ImageLabel") then
		outline.ImageColor3 = color
		outline.ImageTransparency = transparency
	end
end

local function captureSlotPlaceholderState(button: ImageButton): SlotPlaceholderState
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

local function syncSlotPlaceholder(button: ImageButton?, defaults: SlotPlaceholderState?, isFilled: boolean)
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

local function escapeRichText(text: any): string
	return tostring(text)
		:gsub("&", "&amp;")
		:gsub("<", "&lt;")
		:gsub(">", "&gt;")
		:gsub('"', "&quot;")
		:gsub("'", "&apos;")
end

local function formatWholeNumber(value: number): string
	return NumberFormatter.Format(math.max(0, math.floor(tonumber(value) or 0)))
end

local function formatAppraisalCost(value: number): string
	return TranslationHelper.formatByKey(LocalizationKeys.Appraisal.Fields.Cost, {
		Cost = formatWholeNumber(value),
	})
end

local function formatWorth(value: number?): string
	if value == nil then
		return TranslationHelper.formatByKey(LocalizationKeys.Appraisal.Fields.WorthEmpty)
	end

	return TranslationHelper.formatByKey(LocalizationKeys.Appraisal.Fields.Worth, {
		Worth = formatWholeNumber(value),
	})
end

function AppraisalController:_ensureState()
	if self._started then
		return
	end

	self._started = true
	self._isOpen = false
	self._requestInFlight = false
	self._selectedRegion = nil :: string?
	self._slotCardRenderer = nil
	self._slotPlaceholderDefaults = {} :: { [string]: SlotPlaceholderState }
	self._ui = nil :: AppraisalUi?
	self._defaultSelectText = "Select a body part"
	self._defaultSelectedText = "Selected:"
	self._previewLabelFontFaces = nil
	self._remotes = nil :: AppraisalRemotes?
	self._appraisalState = AppraisalState.CreateEmptyState()
	self._speakerModel = nil :: Model?
end

function AppraisalController:_getOwnedLookup(): { [string]: any }
	local bodyPartsState = DataController:Get(BODY_PARTS_DATA_KEY)
	if typeof(bodyPartsState) == "table" and typeof(bodyPartsState.ownedById) == "table" then
		return bodyPartsState.ownedById
	end

	return {}
end

function AppraisalController:_getEquippedState(): BodyPartLoadout.EquippedState
	return BodyPartLoadout.NormalizeEquippedState(
		DataController:Get(EQUIPPED_LOADOUT_KEY),
		self:_getOwnedLookup()
	)
end

function AppraisalController:_getEntryForRegion(region: string): BodyPartLoadout.LoadoutEntry?
	return self:_getEquippedState()[region]
end

function AppraisalController:_getSelectedEntry(): BodyPartLoadout.LoadoutEntry?
	local selectedRegion = self._selectedRegion
	if not selectedRegion then
		return nil
	end

	return self:_getEntryForRegion(selectedRegion)
end

function AppraisalController:_buildPreviewPresentationForRegion(region: string)
	local entry = self:_getEntryForRegion(region)
	if not entry then
		return nil
	end

	local ownedRecord = self:_getOwnedLookup()[entry.ownedId]
	local piece = BodyPartsCatalog.GetPiece(entry.pieceId)
	if not piece then
		return nil
	end

	return BodyPartPresentation.BuildPreviewPresentation({
		record = ownedRecord,
		entry = entry,
		piece = piece,
		visualScale = entry.scale,
		displayScale = ownedRecord and ownedRecord.sizeMultiplier or nil,
	})
end

function AppraisalController:_getSelectedAppraisalCost(): number
	local entry = self:_getSelectedEntry()
	if not entry then
		return 0
	end

	local ownedRecord = self:_getOwnedLookup()[entry.ownedId]
	local piece = BodyPartsCatalog.GetPiece(entry.pieceId)
	if not (ownedRecord and piece) then
		return 0
	end

	return AppraisalPricing.GetCost(ownedRecord, piece)
end

function AppraisalController:_getSelectedOwnedRecord()
	local entry = self:_getSelectedEntry()
	if not entry then
		return nil
	end

	return self:_getOwnedLookup()[entry.ownedId]
end

function AppraisalController:_getSelectedWorth(): number?
	local entry = self:_getSelectedEntry()
	if not entry then
		return nil
	end

	local ownedRecord = self:_getOwnedLookup()[entry.ownedId]
	local piece = BodyPartsCatalog.GetPiece(entry.pieceId)
	if not piece then
		return nil
	end

	return BodyPartEconomy.GetSellValue(ownedRecord, piece)
end

function AppraisalController:_getSelectedAppraisalRiskMessage(): string?
	local selectedEntry = self:_getSelectedEntry()
	local ownedRecord = self:_getSelectedOwnedRecord()
	if not (selectedEntry and ownedRecord) then
		return nil
	end

	local mutationId = MutationConfig.NormalizeId(ownedRecord.mutationId or ownedRecord.mutation)
	local hasRiskyMutation = mutationId ~= DEFAULT_MUTATION_ID

	local sizeScale = tonumber(ownedRecord.sizeMultiplier) or tonumber(selectedEntry.scale) or 1
	local sizeEntry = SizeConfig.GetByScale(sizeScale)
	local sizeId = if sizeEntry then sizeEntry.id else SizeConfig.NormalizeId(ownedRecord.sizeId)
	local hasRiskySize = HIGH_SIZE_IDS[sizeId] == true

	if not hasRiskyMutation and not hasRiskySize then
		return nil
	end

	local riskDescriptors = {}
	if hasRiskyMutation then
		table.insert(riskDescriptors, TranslationHelper.formatByKey(LocalizationKeys.Appraisal.Risk.Mutation, {
			MutationName = MutationConfig.GetDisplayName(mutationId),
		}))
	end
	if hasRiskySize then
		table.insert(
			riskDescriptors,
			TranslationHelper.formatByKey(LocalizationKeys.Appraisal.Risk.Size, {
				SizeDescriptor = BodyPartPresentation.GetSizeDescriptor(
					sizeScale,
					if sizeEntry then sizeEntry.id else ownedRecord.sizeId
				),
				SizeMultiplier = BodyPartPresentation.FormatMultiplier(sizeScale),
			})
		)
	end

	local riskText = ""
	if #riskDescriptors == 1 then
		riskText = riskDescriptors[1]
	else
		riskText = TranslationHelper.formatByKey(LocalizationKeys.Appraisal.Risk.JoinTwo, {
			FirstRisk = riskDescriptors[1],
			SecondRisk = riskDescriptors[2],
		})
	end

	return TranslationHelper.formatByKey(LocalizationKeys.Appraisal.Risk.Continue, {
		RiskText = riskText,
	})
end

function AppraisalController:_applyPreviewLabelStyles(previewModel: any?)
	local defaultFontFaces = self._previewLabelFontFaces
	local previewLabels = self._ui and self._ui.previewLabels or nil
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

function AppraisalController:_setSelectText(text: string?)
	local label = self._ui and self._ui.selectTextLabel or nil
	if label then
		TranslationHelper.setLiteralText(
			label,
			if typeof(text) == "string" and text ~= "" then text else TranslationHelper.formatByKey(LocalizationKeys.Appraisal.Select.Default)
		)
	end
end

function AppraisalController:_setSelectedText(region: string?)
	local label = self._ui and self._ui.selectedLabel or nil
	if not label then
		return
	end

	if typeof(region) ~= "string" or region == "" then
		TranslationHelper.setSourceText(label, self._defaultSelectedText)
		return
	end

	local prefix = self._defaultSelectedText
	local colonIndex = string.find(prefix, ":", 1, true)
	if colonIndex then
		prefix = string.sub(prefix, 1, colonIndex)
	end

	TranslationHelper.setKeyText(label, LocalizationKeys.Appraisal.Select.Selected, {
		RegionLabel = BodyPartPresentation.GetLocalizedRegionLabel(region),
	}, "Text", string.format("%s {RegionLabel}", prefix))
end

function AppraisalController:_hidePreview()
	local ui = self._ui
	if not ui then
		return
	end

	ui.previewHolder.Visible = false
	self:_applyPreviewLabelStyles(nil)
end

function AppraisalController:_syncPreview()
	local ui = self._ui
	if not ui then
		return
	end

	local region = self._selectedRegion
	if not region then
		self:_setSelectText(nil)
		self:_setSelectedText(nil)
		self:_hidePreview()
		return
	end

	local previewModel = self:_buildPreviewPresentationForRegion(region)
	self:_setSelectText(nil)
	self:_setSelectedText(region)

	if not previewModel then
		self:_hidePreview()
		return
	end

	ui.previewHolder.Visible = true
	self:_applyPreviewLabelStyles(previewModel)
	TranslationHelper.setLiteralText(ui.previewLabels.Bundle, previewModel.inventoryBundleText or previewModel.bundleText)
	TranslationHelper.setLiteralText(ui.previewLabels.Part, previewModel.partText)
	TranslationHelper.setLiteralText(ui.previewLabels.Rarity, previewModel.rarityText)
	TranslationHelper.setLiteralText(ui.previewLabels.Mutation, previewModel.mutationText)
	TranslationHelper.setLiteralText(ui.previewLabels.Content, previewModel.sizeText)
	TranslationHelper.setKeyText(ui.previewLabels.Existing, LocalizationKeys.BodyPart.Preview.Existing, {
		Count = TranslationHelper.formatByKey(LocalizationKeys.Common.NotAvailable),
	})
	TranslationHelper.setLiteralText(ui.previewLabels.Cash, previewModel.cashText)
	TranslationHelper.setLiteralText(ui.previewLabels.Chance, previewModel.chanceText)
end

function AppraisalController:_syncSlots()
	local ui = self._ui
	if not ui then
		return
	end

	local equipped = self:_getEquippedState()
	for _, region in ipairs(BodyPartRegions.Order) do
		local slotFrame = ui.slotFrames[region]
		local button = ui.slotButtons[region]
		local entry = equipped[region]
		local isSelected = self._selectedRegion == region

		syncSlotPlaceholder(button, self._slotPlaceholderDefaults[region], entry ~= nil)

		if entry and slotFrame and self._slotCardRenderer then
			local previewModel = self:_buildPreviewPresentationForRegion(region)
			if previewModel then
				local mountedButton = self._slotCardRenderer:Render(
					string.format("appraisal_%s", region),
					slotFrame,
					function()
						self._selectedRegion = region
						self:_syncUi()
					end,
					BodyPartPresentation.BuildBundleCardPayload(previewModel),
					isSelected
				)
				setOutlineColor(
					mountedButton,
					if isSelected then SELECTED_COLOR else DEFAULT_OUTLINE_COLOR,
					if isSelected then 0 else 0.22
				)
			else
				self._slotCardRenderer:Hide(string.format("appraisal_%s", region))
			end
		elseif self._slotCardRenderer then
			self._slotCardRenderer:Hide(string.format("appraisal_%s", region))
		end

		setOutlineColor(
			button,
			if isSelected then SELECTED_COLOR else if entry then EQUIPPED_COLOR else DEFAULT_OUTLINE_COLOR,
			if isSelected then 0 else if entry then 0.1 else 0.45
		)
	end
end

function AppraisalController:_syncDialogueName()
	local ui = self._ui
	if ui then
		TranslationHelper.setSourceText(ui.dialogueNameLabel, DEFAULT_DIALOGUE_NAME)
	end
end

function AppraisalController:_syncServerStock()
	local ui = self._ui
	if ui then
		ui.serverStockLabel.Text = formatWorth(self:_getSelectedWorth())
	end
end

function AppraisalController:_syncPrice()
	local ui = self._ui
	if ui then
		ui.priceLabel.Text = formatAppraisalCost(self:_getSelectedAppraisalCost())
	end
end

function AppraisalController:_syncStatus()
	local ui = self._ui
	if not ui then
		return
	end

	local state = self._appraisalState
	TranslationHelper.setKeyText(
		ui.statusLabel,
		if state.isAvailable then LocalizationKeys.Appraisal.Status.Active else LocalizationKeys.Appraisal.Status.Inactive
	)
end

function AppraisalController:_setRollButtonEnabled(enabled: boolean)
	local ui = self._ui
	if not ui then
		return
	end

	local button = ui.rollButton
	button.Active = enabled
	button.Selectable = enabled
	button.AutoButtonColor = false

	if ui.rollButtonLabel then
		TranslationHelper.setKeyText(ui.rollButtonLabel, LocalizationKeys.Appraisal.Fields.Action)
		ui.rollButtonLabel.TextTransparency = if enabled then 0 else 0.35
	end

	for _, child in ipairs(button:GetChildren()) do
		if child:IsA("ImageLabel") then
			if child.Name == "Rays" then
				child.ImageTransparency = if enabled then 0 else 0.45
			else
				child.ImageTransparency = if enabled then 0 else 0.25
			end
		end
	end
end

function AppraisalController:_canAppraise(): boolean
	if not self._isOpen or self._requestInFlight then
		return false
	end

	local state = self._appraisalState
	if not state.isAvailable then
		return false
	end

	return self:_getSelectedEntry() ~= nil
end

function AppraisalController:_syncRollButton()
	self:_setRollButtonEnabled(self:_canAppraise())
end

function AppraisalController:_showInsufficientFundsWarning(message: string?)
	if typeof(RollWarningNotifier.ShowInsufficientFundsWarning) == "function" then
		RollWarningNotifier.ShowInsufficientFundsWarning(
			if typeof(message) == "string" and message ~= ""
				then message
				else TranslationHelper.formatByKey(LocalizationKeys.Appraisal.Message.InsufficientFunds)
		)
		return
	end

	self:_showMessage(
		DEFAULT_DIALOGUE_NAME,
		if typeof(message) == "string" and message ~= ""
			then message
			else TranslationHelper.formatByKey(LocalizationKeys.Appraisal.Message.InsufficientFunds)
	)
end

function AppraisalController:_syncUi()
	self:_syncDialogueName()
	self:_syncSlots()
	self:_syncPreview()
	self:_syncServerStock()
	self:_syncPrice()
	self:_syncStatus()
	self:_syncRollButton()
end

function AppraisalController:_clearPortrait()
	local ui = self._ui
	if not ui or not ui.viewportFrame then
		return
	end

	ViewportModelRenderer.Clear(ui.viewportFrame)
	ui.viewportFrame.Visible = false
end

function AppraisalController:_renderPortrait()
	local ui = self._ui
	if not ui or not ui.viewportFrame then
		return
	end

	local rendered = ViewportModelRenderer.RenderDialoguePortrait(ui.viewportFrame, self._speakerModel)
	ui.viewportFrame.Visible = rendered
	if not rendered then
		ViewportModelRenderer.Clear(ui.viewportFrame)
	end
end

function AppraisalController:_hideMessage()
	local ui = self._ui
	if ui then
		ui.messageRoot.Visible = false
	end
end

function AppraisalController:_showMessage(title: string, description: string)
	local ui = self._ui
	if not ui then
		return
	end

	ui.messageRoot.Visible = true
	if ui.messageTitle then
		TranslationHelper.setLiteralText(ui.messageTitle, title)
	end
	if ui.messageDescription then
		TranslationHelper.setLiteralText(ui.messageDescription, description)
	end
end

function AppraisalController:_buildSuccessDescription(appraisalResult: any): string
	local before = if typeof(appraisalResult) == "table" then appraisalResult.before else nil
	local after = if typeof(appraisalResult) == "table" then appraisalResult.after else nil

	local beforeMutation = escapeRichText(if typeof(before) == "table" then before.mutationDisplayName or "Unknown" else "Unknown")
	local afterMutation = escapeRichText(if typeof(after) == "table" then after.mutationDisplayName or "Unknown" else "Unknown")

	local beforeSizeId = if typeof(before) == "table" then before.sizeId else nil
	local afterSizeId = if typeof(after) == "table" then after.sizeId else nil
	local beforeSizeScale = if typeof(before) == "table" then tonumber(before.sizeScale) or 1 else 1
	local afterSizeScale = if typeof(after) == "table" then tonumber(after.sizeScale) or 1 else 1
	local beforeSizeDescriptor = escapeRichText(BodyPartPresentation.GetSizeDescriptor(beforeSizeScale, beforeSizeId))
	local afterSizeDescriptor = escapeRichText(BodyPartPresentation.GetSizeDescriptor(afterSizeScale, afterSizeId))

	return TranslationHelper.formatByKey(LocalizationKeys.Appraisal.Message.Success, {
		BeforeMutation = beforeMutation,
		AfterMutation = afterMutation,
		BeforeSize = beforeSizeDescriptor,
		BeforeScale = BodyPartPresentation.FormatMultiplier(beforeSizeScale),
		AfterSize = afterSizeDescriptor,
		AfterScale = BodyPartPresentation.FormatMultiplier(afterSizeScale),
	})
end

function AppraisalController:_ensureRemotes(): boolean
	if self._remotes and self._remotes.getState and self._remotes.performAppraisal and self._remotes.updated then
		return true
	end

	local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME) or ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, 10)
	if not (remotesFolder and remotesFolder:IsA("Folder")) then
		return false
	end

	local appraisalFolder = remotesFolder:FindFirstChild(APPRAISAL_FOLDER_NAME) or remotesFolder:WaitForChild(APPRAISAL_FOLDER_NAME, 10)
	if not (appraisalFolder and appraisalFolder:IsA("Folder")) then
		return false
	end

	local getState = appraisalFolder:FindFirstChild(GET_STATE_REMOTE_NAME)
	local performAppraisal = appraisalFolder:FindFirstChild(PERFORM_APPRAISAL_REMOTE_NAME)
	local updated = appraisalFolder:FindFirstChild(UPDATED_REMOTE_NAME)
	if not (getState and getState:IsA("RemoteFunction")) then
		return false
	end
	if not (performAppraisal and performAppraisal:IsA("RemoteFunction")) then
		return false
	end
	if not (updated and updated:IsA("RemoteEvent")) then
		return false
	end

	self._remotes = {
		getState = getState,
		performAppraisal = performAppraisal,
		updated = updated,
	}

	return true
end

function AppraisalController:_invokeRemote(remote: RemoteFunction, payload: any?): any?
	local ok, result = pcall(function()
		if payload ~= nil then
			return remote:InvokeServer(payload)
		end

		return remote:InvokeServer()
	end)
	if not ok then
		Logger.Warn(string.format("[AppraisalController] Remote %s failed: %s", remote.Name, tostring(result)))
		return nil
	end

	return result
end

function AppraisalController:_requestState(showFailureMessage: boolean?): boolean
	if not self:_ensureRemotes() then
		self._appraisalState = AppraisalState.CreateEmptyState()
		if showFailureMessage then
			self:_showMessage(DEFAULT_DIALOGUE_NAME, TranslationHelper.formatByKey(LocalizationKeys.Appraisal.Message.NotReady))
		end
		return false
	end

	local result = self:_invokeRemote(self._remotes.getState)
	if typeof(result) ~= "table" then
		self._appraisalState = AppraisalState.CreateEmptyState()
		if showFailureMessage then
			self:_showMessage(DEFAULT_DIALOGUE_NAME, TranslationHelper.formatByKey(LocalizationKeys.Appraisal.Message.NotReady))
		end
		return false
	end

	self._appraisalState = AppraisalState.CloneState(result.appraisalState)
	if result.ok ~= true and showFailureMessage then
		self:_showMessage(
			DEFAULT_DIALOGUE_NAME,
			tostring(result.message or TranslationHelper.formatByKey(LocalizationKeys.Appraisal.Message.Unavailable))
		)
	end

	return result.ok == true
end

function AppraisalController:_performAppraisal()
	if not self:_canAppraise() then
		return
	end

	if not self:_ensureRemotes() then
		self:_showMessage(DEFAULT_DIALOGUE_NAME, TranslationHelper.formatByKey(LocalizationKeys.Appraisal.Message.NotReady))
		return
	end

	local selectedRegion = self._selectedRegion
	local selectedEntry = self:_getSelectedEntry()
	if not (selectedRegion and selectedEntry) then
		self:_showMessage(DEFAULT_DIALOGUE_NAME, TranslationHelper.formatByKey(LocalizationKeys.Appraisal.Message.SelectFirst))
		return
	end

	local riskMessage = self:_getSelectedAppraisalRiskMessage()
	if riskMessage and ConfirmationWarning.Prompt(riskMessage) ~= true then
		return
	end

	self._requestInFlight = true
	self:_syncRollButton()

	local result = self:_invokeRemote(self._remotes.performAppraisal, {
		region = selectedRegion,
		ownedId = selectedEntry.ownedId,
	})

	self._requestInFlight = false

	if typeof(result) ~= "table" then
		self:_syncUi()
		self:_showMessage(DEFAULT_DIALOGUE_NAME, "The appraisal could not be completed.")
		return
	end

	self._appraisalState = AppraisalState.CloneState(result.appraisalState)
	self:_syncUi()

	if result.ok == true then
		SoundUtil.Play(AppraisalConfig.successSoundName)
		self:_showMessage(DEFAULT_DIALOGUE_NAME, self:_buildSuccessDescription(result.appraisalResult))
		return
	end

	if result.code == "INSUFFICIENT_MONEY" then
		self:_hideMessage()
		self:_showInsufficientFundsWarning(tostring(result.message or ""))
		return
	end

	self:_showMessage(DEFAULT_DIALOGUE_NAME, tostring(result.message or "The appraisal could not be completed."))
end

function AppraisalController:_resetSelectionState()
	self._selectedRegion = nil
	self:_setSelectText(self._defaultSelectText)
	self:_setSelectedText(nil)
	self:_hidePreview()

	if self._slotCardRenderer then
		for _, region in ipairs(BodyPartRegions.Order) do
			self._slotCardRenderer:Hide(string.format("appraisal_%s", region))
		end
	end
end

function AppraisalController:_cacheUi(playerGui: PlayerGui)
	local modalRoot = playerGui:WaitForChild("ModalRoot", 30)
	if not (modalRoot and modalRoot:IsA("ScreenGui")) then
		Logger.Error("PlayerGui.ModalRoot is missing.")
	end

	local appraisalRoot = modalRoot:WaitForChild(WINDOW_NAME, 30)
	if not (appraisalRoot and appraisalRoot:IsA("GuiObject")) then
		Logger.Error("PlayerGui.ModalRoot.AppraisalUI is missing.")
	end

	local previewRoot = appraisalRoot:WaitForChild("CharacterPreview", 30)
	local characterRoot = previewRoot:WaitForChild("Character", 30)
	local characterViewport = characterRoot:WaitForChild("Character", 30)
	local previewHolder = appraisalRoot:WaitForChild("ItemPreviewHolder", 30)
	local previewDetails = previewHolder:WaitForChild("Frame", 30)
	local selectTextLabel = previewRoot:WaitForChild("SelectText", 30)
	local main = appraisalRoot:WaitForChild("Main", 30)

	local slotFrames = {}
	local slotButtons = {}
	for _, region in ipairs(BodyPartRegions.Order) do
		local slotFrame = characterViewport:FindFirstChild(region)
		if slotFrame and slotFrame:IsA("Frame") then
			slotFrames[region] = slotFrame

			local slotButton = slotFrame:FindFirstChild("Temp")
			if slotButton and slotButton:IsA("ImageButton") then
				slotButtons[region] = slotButton
				self._slotPlaceholderDefaults[region] = captureSlotPlaceholderState(slotButton)
			end
		end
	end

	local itemDesc = main:WaitForChild("ItemDesc", 30)
	local statusLabel = itemDesc:FindFirstChildWhichIsA("TextLabel")
	assert(statusLabel and statusLabel:IsA("TextLabel"), "AppraisalUI.Main.ItemDesc.TextLabel is missing.")

	local messageRoot = main:WaitForChild("MessageUI", 30)
	assert(messageRoot and messageRoot:IsA("GuiButton"), "AppraisalUI.Main.MessageUI is missing.")
	local messageFrame = messageRoot:FindFirstChild("Message", true)
	local messageTitle = if messageFrame then messageFrame:FindFirstChild("Title") else nil
	local messageDescription = if messageFrame then messageFrame:FindFirstChild("Description") else nil
	local messageClose = if messageFrame then messageFrame:FindFirstChild("Close") else nil

	local viewportFrame = main:FindFirstChild("ViewportFrame")
	if viewportFrame and not viewportFrame:IsA("ViewportFrame") then
		viewportFrame = nil
	end

	local rollButton = main:WaitForChild("RollButton", 30)
	assert(rollButton and rollButton:IsA("ImageButton"), "AppraisalUI.Main.RollButton is missing.")

	self._ui = {
		root = appraisalRoot,
		selectTextLabel = selectTextLabel,
		selectedLabel = main:WaitForChild("Selected", 30),
		slotFrames = slotFrames,
		slotButtons = slotButtons,
		previewHolder = previewHolder,
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
		dialogueNameLabel = main:WaitForChild("DialogueName", 30),
		serverStockLabel = main:WaitForChild("ServerStock", 30),
		priceLabel = main:WaitForChild("Price", 30),
		statusLabel = statusLabel,
		rollButton = rollButton,
		rollButtonLabel = rollButton:FindFirstChildWhichIsA("TextLabel"),
		viewportFrame = viewportFrame,
		messageRoot = messageRoot,
		messageTitle = if messageTitle and messageTitle:IsA("TextLabel") then messageTitle else nil,
		messageDescription = if messageDescription and messageDescription:IsA("TextLabel") then messageDescription else nil,
		messageClose = if messageClose and messageClose:IsA("GuiButton") then messageClose else nil,
	}

	for _, label in pairs(self._ui.previewLabels) do
		label.RichText = true
	end

	if self._ui.messageDescription then
		self._ui.messageDescription.RichText = true
	end

	self._defaultSelectText = selectTextLabel.Text
	self._defaultSelectedText = self._ui.selectedLabel.Text
	self._previewLabelFontFaces = {
		Bundle = self._ui.previewLabels.Bundle.FontFace,
		Rarity = self._ui.previewLabels.Rarity.FontFace,
	}
	self._slotCardRenderer = SlotCardRenderer.new(playerGui)

	for _, region in ipairs(BodyPartRegions.Order) do
		local slotButton = slotButtons[region]
		if slotButton then
			UIController:CreateButton(slotButton, function()
				self._selectedRegion = region
				self:_syncUi()
			end)
		end
	end

	UIController:CreateButton(self._ui.rollButton, function()
		self:_performAppraisal()
	end)

	if self._ui.messageClose then
		UIController:CreateButton(self._ui.messageClose, function()
			self:_hideMessage()
		end)
	end

	self:_hideMessage()
	self:_clearPortrait()
	self:_resetSelectionState()
	self:_syncUi()
end

function AppraisalController:OnStart()
	self:_ensureState()

	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	self:_cacheUi(playerGui)
	self:_ensureRemotes()

	MerchantPresentationController.FramePrepared:Connect(function(frameName: string, _root: GuiObject, options: any)
		if frameName ~= WINDOW_NAME then
			return
		end

		self._isOpen = true
		self._requestInFlight = false
		self._speakerModel = if typeof(options) == "table"
			and typeof(options.speakerModel) == "Instance"
			and options.speakerModel:IsA("Model")
			then options.speakerModel
			else nil

		self:_hideMessage()
		self:_requestState(false)
		self:_resetSelectionState()
		self:_renderPortrait()
		self:_syncUi()
	end)

	MerchantPresentationController.Closed:Connect(function(frameName: string)
		if frameName ~= WINDOW_NAME then
			return
		end

		self._isOpen = false
		self._requestInFlight = false
		self._speakerModel = nil
		self:_hideMessage()
		self:_clearPortrait()
		self:_resetSelectionState()
		self:_syncUi()
	end)

	local function refreshIfOpen(key: string?)
		if not self._isOpen then
			return
		end
		if key ~= nil and key ~= BODY_PARTS_DATA_KEY and key ~= EQUIPPED_LOADOUT_KEY then
			return
		end

		self:_syncUi()
	end

	DataController.DataReceived:Connect(function()
		refreshIfOpen(nil)
	end)

	DataController.DataUpdated:Connect(function(key)
		refreshIfOpen(key)
	end)

	if self._remotes then
		self._remotes.updated.OnClientEvent:Connect(function(payload: any)
			self._appraisalState = AppraisalState.CloneState(
				if typeof(payload) == "table" and payload.appraisalState ~= nil then payload.appraisalState else payload
			)
			if self._isOpen then
				self:_syncUi()
			end
		end)
	end

	self:_resetSelectionState()
	self:_syncUi()
end

return AppraisalController
