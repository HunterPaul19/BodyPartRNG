local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local BodyPartRegions = require(ReplicatedStorage.Shared.Character.BodyPartRegions)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local AuraPresentation = require(ReplicatedStorage.Shared.UI.AuraPresentation)
local BodyPartPresentation = require(ReplicatedStorage.Shared.UI.BodyPartPresentation)
local ViewportModelRenderer = require(ReplicatedStorage.Shared.UI.ViewportModelRenderer)
local FrameController = require(script.Parent.FrameController)
local SlotCardRenderer = require(script.Parent.SlotCardRenderer)
local UIController = require(script.Parent.UIController)

local LOCAL_PLAYER = Players.LocalPlayer
local WINDOW_NAME = "PlayerInfo"
local REMOTES_FOLDER_NAME = "Remotes"
local BODY_PARTS_REMOTES_FOLDER_NAME = "BodyParts"
local AURAS_REMOTES_FOLDER_NAME = "Auras"
local GET_PLAYER_INSPECT_SUMMARY_REMOTE_NAME = "GetPlayerInspectSummary"
local GET_EXISTENCE_REMOTE_NAME = "GetTotalInExistenceForPiece"
local GET_AURA_EXISTENCE_REMOTE_NAME = "GetTotalInExistenceForAura"
local INSPECT_REFRESH_INTERVAL = 1.0
local SELECTED_COLOR = Color3.fromRGB(116, 192, 255)
local DEFAULT_OUTLINE_COLOR = Color3.fromRGB(255, 255, 255)
local PART_INFO_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local DEFAULT_SELECT_TEXT = "Select a body part"

type InspectEntry = {
	ownedId: string?,
	pieceId: string?,
	region: string?,
	scale: number?,
	serialNumber: number?,
	rolledSetDisplayName: string?,
	displayRarity: string?,
	displayOddsDenominator: number?,
	rarityDenominator: number?,
	mutation: string?,
	finalPassiveIncomePerSecond: number?,
}

type EquippedAuraInspectEntry = {
	ownedId: string?,
	auraId: string?,
	serialNumber: number?,
	label: string?,
	description: string?,
	tierLabel: string?,
	displayColor: Color3?,
	bonuses: {
		luckBonus: number?,
		rollSpeedBonus: number?,
		moneyMultiplier: number?,
		passiveIncomePerSecondBonus: number?,
	}?,
}

type InspectSummary = {
	userId: number,
	name: string,
	displayName: string,
	currentMoney: number?,
	currentTimePlayed: number?,
	currentSuccessfulRollCount: number?,
	currentOwnedBodyParts: number?,
	currentOwnedAuras: number?,
	stats: any,
	equipped: { [string]: InspectEntry }?,
	equippedAura: EquippedAuraInspectEntry?,
	bonuses: {
		passiveIncomePerSecond: number?,
		luckBonus: number?,
		rollSpeedBonus: number?,
		activeSetId: string?,
	}?,
}

local PlayerInspectController = {}

local function createHighlight(): Highlight
	local highlight = Instance.new("Highlight")
	highlight.Name = "PlayerInspectHighlight"
	highlight.FillTransparency = 0.55
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.Enabled = false
	highlight.Parent = workspace
	return highlight
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

local function getPlayerFromInstance(target: Instance?): Player?
	if not (target and target.Parent) then
		return nil
	end

	local character = target:FindFirstAncestorOfClass("Model")
	if not character then
		return nil
	end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return nil
	end

	return player
end

local function getCharacterScreenBounds(character: Model, camera: Camera): (Vector2?, Vector2?)
	local boundingCFrame, boundingSize = character:GetBoundingBox()
	local halfSize = boundingSize * 0.5
	local minX, minY = math.huge, math.huge
	local maxX, maxY = -math.huge, -math.huge
	local hasVisibleCorner = false

	for _, x in ipairs({ -1, 1 }) do
		for _, y in ipairs({ -1, 1 }) do
			for _, z in ipairs({ -1, 1 }) do
				local worldPoint = boundingCFrame:PointToWorldSpace(Vector3.new(halfSize.X * x, halfSize.Y * y, halfSize.Z * z))
				local screenPoint, onScreen = camera:WorldToViewportPoint(worldPoint)
				if onScreen and screenPoint.Z > 0 then
					hasVisibleCorner = true
					minX = math.min(minX, screenPoint.X)
					minY = math.min(minY, screenPoint.Y)
					maxX = math.max(maxX, screenPoint.X)
					maxY = math.max(maxY, screenPoint.Y)
				end
			end
		end
	end

	if not hasVisibleCorner then
		return nil, nil
	end

	return Vector2.new(minX, minY), Vector2.new(maxX, maxY)
end

local function isPointInsideCharacterBounds(player: Player, screenPoint: Vector2, camera: Camera): boolean
	local character = player.Character
	if not character then
		return false
	end

	local minBound, maxBound = getCharacterScreenBounds(character, camera)
	if not (minBound and maxBound) then
		return false
	end

	local padding = 8
	return screenPoint.X >= (minBound.X - padding)
		and screenPoint.X <= (maxBound.X + padding)
		and screenPoint.Y >= (minBound.Y - padding)
		and screenPoint.Y <= (maxBound.Y + padding)
end

local function getPointerInspectablePlayer(mouse): Player?
	local hoveredPlayer = getPlayerFromInstance(mouse.Target)
	if hoveredPlayer then
		return hoveredPlayer
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end

	local mouseLocation = UserInputService:GetMouseLocation()
	local viewportRay = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
	local raycastResult = workspace:Raycast(viewportRay.Origin, viewportRay.Direction * 1000)
	if raycastResult then
		return getPlayerFromInstance(raycastResult.Instance)
	end

	if isPointInsideCharacterBounds(LOCAL_PLAYER, mouseLocation, camera) then
		return LOCAL_PLAYER
	end

	return nil
end

local function setOutlineColor(button: GuiButton, color: Color3, transparency: number)
	local outline = button:FindFirstChild("Outline")
	if outline and outline:IsA("ImageLabel") then
		outline.ImageColor3 = color
		outline.ImageTransparency = transparency
	end
end

local function captureSlotPlaceholderState(button: ImageButton)
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

local function syncSlotPlaceholder(button: ImageButton?, defaults: any, isFilled: boolean)
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

local function createCharacterPreviewModelFromDescription(description: HumanoidDescription?): Model?
	if not description then
		return nil
	end

	local baseRigModel = BodyPartsCatalog.GetDefaultBaseRig()
	if not (baseRigModel and baseRigModel:IsA("Model")) then
		return nil
	end

	local previewModel = baseRigModel:Clone()
	previewModel.Name = "PlayerInspectPreview"

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

function PlayerInspectController:_ensureState()
	if self._started then
		return
	end

	self._started = true
	self._mouse = LOCAL_PLAYER:GetMouse()
	self._highlight = createHighlight()
	self._hoveredPlayer = nil :: Player?
	self._hoveredRegion = nil :: string?
	self._hoveredAura = false
	self._inspectedPlayer = nil :: Player?
	self._inspectedUserId = nil :: number?
	self._summary = nil :: InspectSummary?
	self._selectedRegion = nil :: string?
	self._selectedAura = false
	self._requestToken = 0
	self._existingRequestToken = 0
	self._existingCounts = {}
	self._pendingExistingCounts = {}
	self._characterRenderToken = 0
	self._partInfoTween = nil :: Tween?
	self._remotes = {}
	self._slotCardRenderer = nil
	self._mountedRegionButtons = {}
	self._slotPlaceholderDefaults = {}
	self._ui = nil
	self._partInfoLabelFontFaces = nil
	self._partInfoEverRolledNativeText = nil
	self._partInfoEverRolledSuffixText = nil
end

function PlayerInspectController:_getRemotesFolder(): Folder?
	local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if not remotesFolder then
		return nil
	end

	local bodyPartsFolder = remotesFolder:FindFirstChild(BODY_PARTS_REMOTES_FOLDER_NAME)
	if bodyPartsFolder and bodyPartsFolder:IsA("Folder") then
		return bodyPartsFolder
	end

	return nil
end

function PlayerInspectController:_getAuraRemotesFolder(): Folder?
	local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if not remotesFolder then
		return nil
	end

	local aurasFolder = remotesFolder:FindFirstChild(AURAS_REMOTES_FOLDER_NAME)
	if aurasFolder and aurasFolder:IsA("Folder") then
		return aurasFolder
	end

	return nil
end

function PlayerInspectController:_ensureRemotes(): boolean
	if self._remotes.getInspectSummary and self._remotes.getExistence then
		return true
	end

	local bodyPartsFolder = self:_getRemotesFolder()
	if not bodyPartsFolder then
		return false
	end

	local getInspectSummary = bodyPartsFolder:FindFirstChild(GET_PLAYER_INSPECT_SUMMARY_REMOTE_NAME)
	local getExistence = bodyPartsFolder:FindFirstChild(GET_EXISTENCE_REMOTE_NAME)
	if not (getInspectSummary and getInspectSummary:IsA("RemoteFunction")) then
		return false
	end
	if not (getExistence and getExistence:IsA("RemoteFunction")) then
		return false
	end

	self._remotes.getInspectSummary = getInspectSummary
	self._remotes.getExistence = getExistence
	return true
end

function PlayerInspectController:_ensureAuraExistenceRemote(): boolean
	if self._remotes.getAuraExistence then
		return true
	end

	local aurasFolder = self:_getAuraRemotesFolder()
	if not aurasFolder then
		return false
	end

	local getAuraExistence = aurasFolder:FindFirstChild(GET_AURA_EXISTENCE_REMOTE_NAME)
	if not (getAuraExistence and getAuraExistence:IsA("RemoteFunction")) then
		return false
	end

	self._remotes.getAuraExistence = getAuraExistence
	return true
end

function PlayerInspectController:_requestInspectSummary(userId: number): InspectSummary?
	if not self:_ensureRemotes() then
		return nil
	end

	local ok, result = pcall(function()
		return self._remotes.getInspectSummary:InvokeServer({
			userId = userId,
		})
	end)
	if not ok or typeof(result) ~= "table" or result.ok ~= true or typeof(result.summary) ~= "table" then
		return nil
	end

	return result.summary
end

function PlayerInspectController:_canRefreshSummary(requestToken: number, userId: number): boolean
	if requestToken ~= self._requestToken then
		return false
	end
	if self._inspectedUserId ~= userId then
		return false
	end
	if not self._ui or not FrameController:IsOpen(WINDOW_NAME) then
		return false
	end

	return Players:GetPlayerByUserId(userId) ~= nil
end

function PlayerInspectController:_startSummaryRefreshLoop(requestToken: number, userId: number)
	task.spawn(function()
		while self:_canRefreshSummary(requestToken, userId) do
			task.wait(INSPECT_REFRESH_INTERVAL)
			if not self:_canRefreshSummary(requestToken, userId) then
				break
			end

			local summary = self:_requestInspectSummary(userId)
			if summary and self:_canRefreshSummary(requestToken, userId) then
				local player = Players:GetPlayerByUserId(userId)
				if player then
					self:_applySummary(player, summary, true)
				end
			end
		end
	end)
end

function PlayerInspectController:_getEquippedEntries(): { [string]: InspectEntry }
	local summary = self._summary
	if summary and typeof(summary.equipped) == "table" then
		return summary.equipped
	end

	return {}
end

function PlayerInspectController:_getEquippedAuraEntry(): EquippedAuraInspectEntry?
	local summary = self._summary
	if summary and typeof(summary.equippedAura) == "table" then
		return summary.equippedAura
	end

	return nil
end

function PlayerInspectController:_setHoveredPlayer(player: Player?)
	self._hoveredPlayer = player
	if player and player.Character then
		self._highlight.Adornee = player.Character
		self._highlight.Enabled = true
	else
		self._highlight.Adornee = nil
		self._highlight.Enabled = false
	end
end

function PlayerInspectController:_setSelectText(text: string)
	local ui = self._ui
	if ui and ui.selectTextLabel then
		ui.selectTextLabel.Text = text
	end
end

function PlayerInspectController:_cancelPartInfoTween()
	if self._partInfoTween then
		self._partInfoTween:Cancel()
		self._partInfoTween = nil
	end
end

function PlayerInspectController:_setPartInfoVisible(isVisible: boolean)
	local ui = self._ui
	if not ui then
		return
	end

	self:_cancelPartInfoTween()

	if not isVisible then
		ui.partInfo.Visible = false
		ui.partInfoScale.Scale = 1
		return
	end

	ui.partInfo.Visible = true
	ui.partInfoScale.Scale = 0.96
	self._partInfoTween = TweenService:Create(ui.partInfoScale, PART_INFO_TWEEN, {
		Scale = 1,
	})
	self._partInfoTween:Play()
end

function PlayerInspectController:_setExistingText(text: string)
	local ui = self._ui
	if ui then
		ui.partInfoLabels.Existing.Text = text
	end
end

function PlayerInspectController:_setEverRolledText(leadingText: string?)
	local ui = self._ui
	local everRolledLabel = ui and ui.partInfoLabels.EverRolled
	if not (everRolledLabel and everRolledLabel:IsA("TextLabel")) then
		return
	end

	if typeof(leadingText) ~= "string" or leadingText == "" then
		everRolledLabel.Text = self._partInfoEverRolledNativeText or everRolledLabel.Text
		return
	end

	local suffixText = self._partInfoEverRolledSuffixText
		or extractTrailingLabelText(self._partInfoEverRolledNativeText, "Ever Rolled")
	everRolledLabel.Text = if suffixText ~= ""
		then string.format("%s %s", leadingText, suffixText)
		else leadingText
end

function PlayerInspectController:_syncHeader()
	local ui = self._ui
	local summary = self._summary
	if not ui then
		return
	end

	if summary then
		ui.headerLabel.Text = summary.displayName
		if ui.usernameLabel then
			ui.usernameLabel.Text = "@" .. summary.name
		end
	else
		ui.headerLabel.Text = "Player Info"
		if ui.usernameLabel then
			ui.usernameLabel.Text = ""
		end
	end
end

function PlayerInspectController:_syncSummaryLabels()
	local ui = self._ui
	if not ui then
		return
	end

	local summaryTexts = BodyPartPresentation.BuildSummaryTexts(self._summary and self._summary.bonuses or {})
	ui.incomeLabel.Text = summaryTexts.income
	ui.luckLabel.Text = summaryTexts.luck
	ui.rollSpeedLabel.Text = summaryTexts.rollSpeed
	if ui.totalOddsAddedLabel then
		ui.totalOddsAddedLabel.Visible = false
	end
end

function PlayerInspectController:_syncRegionButtons()
	local ui = self._ui
	if not ui then
		return
	end

	local equipped = self:_getEquippedEntries()
	for _, region in ipairs(BodyPartRegions.Order) do
		local regionFrame = ui.regionFrames[region]
		local button = ui.regionButtons[region]
		local entry = equipped[region]
		if regionFrame then
			regionFrame.Visible = true
		end
		if button then
			button.Active = true
			syncSlotPlaceholder(button, self._slotPlaceholderDefaults[region], entry ~= nil)
			local isSelected = self._selectedRegion == region and entry ~= nil
			if entry then
				local previewPresentation = BodyPartPresentation.BuildPreviewPresentation({
					record = entry,
					scale = entry.scale,
					appearanceUserId = self._inspectedUserId,
				})
				local mountedButton = if previewPresentation and regionFrame and self._slotCardRenderer
					then self._slotCardRenderer:Render(
						string.format("inspect_%s", region),
						regionFrame,
						function()
							if self:_getEquippedEntries()[region] == nil then
								self:_setSelectedRegion(nil)
								return
							end

							self:_setSelectedRegion(region)
						end,
						BodyPartPresentation.BuildBundleCardPayload(previewPresentation),
						isSelected
					)
					else nil
				if mountedButton and self._mountedRegionButtons[region] ~= mountedButton then
					self._mountedRegionButtons[region] = mountedButton
					mountedButton.MouseEnter:Connect(function()
						self._hoveredRegion = region
						self._hoveredAura = false
						self:_syncModalContents()
					end)

					mountedButton.MouseLeave:Connect(function()
						if self._hoveredRegion == region then
							self._hoveredRegion = nil
							self:_syncModalContents()
						end
					end)
				end
				if mountedButton then
					setOutlineColor(mountedButton, if isSelected then SELECTED_COLOR else DEFAULT_OUTLINE_COLOR, if isSelected then 0 else 0.22)
				end
			else
				if self._slotCardRenderer then
					self._slotCardRenderer:Hide(string.format("inspect_%s", region))
				end
			end

			local isHovered = self._hoveredRegion == region
			local outlineTransparency = if isSelected or isHovered then 0 else 0.2
			setOutlineColor(button, if isSelected then SELECTED_COLOR else DEFAULT_OUTLINE_COLOR, outlineTransparency)
		end
	end
end

function PlayerInspectController:_syncAuraButton()
	local ui = self._ui
	if not ui then
		return
	end

	local auraFrame = ui.auraFrame
	local auraButton = ui.auraButton
	local entry = self:_getEquippedAuraEntry()
	if not auraFrame then
		return
	end

	auraFrame.Visible = entry ~= nil
	if not (auraButton and entry) then
		if auraButton then
			BodyPartPresentation.PopulateBundleCard(auraButton, {
				usageText = "",
				bundleModel = nil,
				iconVisible = true,
			})
			setOutlineColor(auraButton, DEFAULT_OUTLINE_COLOR, 0.45)
		end
		return
	end

	local previewPresentation = AuraPresentation.BuildPreviewPresentation({
		record = entry,
	})
	BodyPartPresentation.PopulateBundleCard(auraButton, {
		nameText = if previewPresentation then previewPresentation.cardNameText else entry.label,
		usageText = if previewPresentation then previewPresentation.cardUsageText else "",
		bundleModel = if previewPresentation then previewPresentation.bundleModel else nil,
		cardAccentColor = if previewPresentation then previewPresentation.cardAccentColor else nil,
		baseFillColor = if previewPresentation then previewPresentation.baseFillColor else nil,
		selectedFillColor = if previewPresentation then previewPresentation.selectedFillColor else nil,
		iconTexture = if previewPresentation then previewPresentation.iconTexture else nil,
		preferIconOverViewport = true,
	})

	local isSelected = self._selectedAura == true
	local isHovered = self._hoveredAura == true
	local outlineTransparency = if isSelected or isHovered then 0 else 0.2
	setOutlineColor(auraButton, if isSelected then SELECTED_COLOR else DEFAULT_OUTLINE_COLOR, outlineTransparency)
end

function PlayerInspectController:_clearPreviewLabels()
	local ui = self._ui
	if not ui then
		return
	end

	for _, label in pairs(ui.partInfoLabels) do
		label.Text = ""
	end
	self:_setEverRolledText(nil)
	self:_applyPartInfoLabelStyles(nil)
end

function PlayerInspectController:_applyPartInfoLabelStyles(previewPresentation: any?)
	local defaultFontFaces = self._partInfoLabelFontFaces
	local ui = self._ui
	if not (defaultFontFaces and ui) then
		return
	end

	local bundleLabel = ui.partInfoLabels.Bundle
	if bundleLabel and bundleLabel:IsA("TextLabel") then
		bundleLabel.FontFace = if previewPresentation and typeof(previewPresentation.bundleFontFace) == "Font"
			then previewPresentation.bundleFontFace
			else defaultFontFaces.Bundle
	end

	local rarityLabel = ui.partInfoLabels.Rarity
	if rarityLabel and rarityLabel:IsA("TextLabel") then
		rarityLabel.FontFace = if previewPresentation and typeof(previewPresentation.rarityFontFace) == "Font"
			then previewPresentation.rarityFontFace
			else defaultFontFaces.Rarity
	end
end

function PlayerInspectController:_requestAuraExistingCount(auraId: string, requestToken: number)
	if self._existingCounts[auraId] ~= nil or self._pendingExistingCounts[auraId] == true then
		return
	end

	if not self:_ensureAuraExistenceRemote() then
		self._existingCounts[auraId] = false
		return
	end

	self._pendingExistingCounts[auraId] = true
	local ok, result = pcall(function()
		return self._remotes.getAuraExistence:InvokeServer({
			auraId = auraId,
		})
	end)

	if requestToken ~= self._existingRequestToken then
		self._pendingExistingCounts[auraId] = nil
		return
	end

	self._pendingExistingCounts[auraId] = nil
	if not ok or typeof(result) ~= "table" or result.ok ~= true then
		self._existingCounts[auraId] = false
	elseif tonumber(result.count) == nil then
		self._existingCounts[auraId] = false
	else
		self._existingCounts[auraId] = math.max(0, math.floor(tonumber(result.count) :: number))
	end

	self:_syncPartInfo()
end

function PlayerInspectController:_requestExistingCount(pieceId: string, requestToken: number)
	if self._existingCounts[pieceId] ~= nil or self._pendingExistingCounts[pieceId] == true then
		return
	end

	if not self:_ensureRemotes() then
		self._existingCounts[pieceId] = false
		return
	end

	self._pendingExistingCounts[pieceId] = true
	local ok, result = pcall(function()
		return self._remotes.getExistence:InvokeServer({
			pieceId = pieceId,
		})
	end)

	if requestToken ~= self._existingRequestToken then
		self._pendingExistingCounts[pieceId] = nil
		return
	end

	self._pendingExistingCounts[pieceId] = nil
	if not ok or typeof(result) ~= "table" or result.ok ~= true then
		self._existingCounts[pieceId] = false
	elseif tonumber(result.count) == nil then
		self._existingCounts[pieceId] = false
	else
		self._existingCounts[pieceId] = math.max(0, math.floor(tonumber(result.count) :: number))
	end

	self:_syncPartInfo()
end

function PlayerInspectController:_prefetchExistingCounts()
	local requestToken = self._existingRequestToken
	local requestedPieceIds = {}

	for _, entry in pairs(self:_getEquippedEntries()) do
		local pieceId = entry and entry.pieceId
		if typeof(pieceId) == "string" and pieceId ~= "" and not requestedPieceIds[pieceId] then
			requestedPieceIds[pieceId] = true
			task.spawn(function()
				self:_requestExistingCount(pieceId, requestToken)
			end)
		end
	end

	local auraEntry = self:_getEquippedAuraEntry()
	local auraId = auraEntry and auraEntry.auraId
	if typeof(auraId) == "string" and auraId ~= "" then
		task.spawn(function()
			self:_requestAuraExistingCount(auraId, requestToken)
		end)
	end
end

function PlayerInspectController:_syncPartInfo()
	local ui = self._ui
	if not ui then
		return
	end

	local selectedRegion = self._selectedRegion
	local selectedAura = self._selectedAura == true
	local previewPresentation = nil
	local existingLookupKey = nil

	if selectedAura then
		local auraEntry = self:_getEquippedAuraEntry()
		if auraEntry then
			previewPresentation = AuraPresentation.BuildPreviewPresentation({
				record = auraEntry,
			})
			existingLookupKey = previewPresentation and previewPresentation.auraId or auraEntry.auraId
		end
	else
		local entry = selectedRegion and self:_getEquippedEntries()[selectedRegion] or nil
		if entry then
			previewPresentation = BodyPartPresentation.BuildPreviewPresentation({
				record = entry,
				scale = entry.scale,
				appearanceUserId = self._inspectedUserId,
			})
			existingLookupKey = previewPresentation and previewPresentation.pieceId or entry.pieceId
		end
	end

	if not previewPresentation then
		self:_clearPreviewLabels()
		self:_setPartInfoVisible(false)
		return
	end

	self:_applyPartInfoLabelStyles(previewPresentation)
	ui.partInfoLabels.Bundle.Text = previewPresentation.bundleText
	self:_setEverRolledText(previewPresentation.inventoryEverRolledText)
	ui.partInfoLabels.Rarity.Text = previewPresentation.rarityText
	ui.partInfoLabels.Mutation.Text = previewPresentation.mutationText
	ui.partInfoLabels.Content.Text = previewPresentation.sizeText
	local cachedExistingCount = if typeof(existingLookupKey) == "string" then self._existingCounts[existingLookupKey] else nil
	if typeof(cachedExistingCount) == "number" then
		self:_setExistingText(
			string.format("Existing: %s", BodyPartPresentation.FormatNumberish(cachedExistingCount))
		)
	elseif typeof(existingLookupKey) == "string" and self._pendingExistingCounts[existingLookupKey] == true then
		self:_setExistingText("Existing: Loading...")
	else
		self:_setExistingText("Existing: N/A")
	end
	ui.partInfoLabels.Cash.Text = previewPresentation.cashText
	ui.partInfoLabels.Chance.Text = previewPresentation.chanceText
	self:_setPartInfoVisible(true)
end

function PlayerInspectController:_syncModalContents()
	self:_syncHeader()
	self:_syncSummaryLabels()
	self:_syncRegionButtons()
	self:_syncAuraButton()

	local equippedEntries = self:_getEquippedEntries()
	local equippedAura = self:_getEquippedAuraEntry()
	local baseText = DEFAULT_SELECT_TEXT
	if self._selectedAura then
		if equippedAura then
			baseText = tostring(equippedAura.label or "Aura")
		else
			self._selectedAura = false
		end
	elseif self._selectedRegion then
		local selectedEntry = equippedEntries[self._selectedRegion]
		if selectedEntry then
			baseText = BodyPartPresentation.GetRegionLabel(self._selectedRegion)
		else
			self._selectedRegion = nil
		end
	end

	if self._selectedAura == false and self._selectedRegion == nil and self._hoveredAura and equippedAura then
		baseText = tostring(equippedAura.label or "Aura")
	end

	self:_setSelectText(baseText)
	self:_syncPartInfo()
end

function PlayerInspectController:_clearState()
	self._requestToken += 1
	self._existingRequestToken += 1
	self._characterRenderToken += 1
	self._summary = nil
	self._existingCounts = {}
	self._pendingExistingCounts = {}
	self._hoveredRegion = nil
	self._hoveredAura = false
	self._selectedRegion = nil
	self._selectedAura = false
	self._inspectedPlayer = nil
	self._inspectedUserId = nil
	if self._ui then
		self:_syncHeader()
		self:_syncSummaryLabels()
		self:_syncRegionButtons()
		self:_syncAuraButton()
		self:_clearPreviewLabels()
		self:_setPartInfoVisible(false)
		self:_setSelectText(DEFAULT_SELECT_TEXT)
	end
end

function PlayerInspectController:_setSelectedRegion(region: string?)
	self._selectedRegion = region
	self._selectedAura = false
	self:_syncModalContents()
end

function PlayerInspectController:_setSelectedAura(isSelected: boolean)
	self._selectedAura = isSelected == true
	if self._selectedAura then
		self._selectedRegion = nil
	end
	self:_syncModalContents()
end

function PlayerInspectController:_renderFallbackCharacter(userId: number, requestToken: number)
	local baseRig = BodyPartsCatalog.GetDefaultBaseRig()
	if baseRig then
		ViewportModelRenderer.RenderBaseRig(self._ui.characterViewport, baseRig)
	end

	task.spawn(function()
		local ok, description = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(userId)
		end)
		if requestToken ~= self._characterRenderToken or not self._ui then
			return
		end
		if not ok or not description or not description:IsA("HumanoidDescription") then
			return
		end

		local previewModel = createCharacterPreviewModelFromDescription(description)
		if not previewModel then
			return
		end

		ViewportModelRenderer.RenderCharacterModel(self._ui.characterViewport, previewModel, nil)
		previewModel:Destroy()
	end)
end

function PlayerInspectController:_syncCharacterViewport()
	return
end

function PlayerInspectController:_applySummary(player: Player, summary: InspectSummary, preserveViewState: boolean?)
	if not self._ui or not FrameController:IsOpen(WINDOW_NAME) then
		return
	end

	self._inspectedPlayer = player
	self._inspectedUserId = summary.userId
	self._summary = summary
	if preserveViewState ~= true then
		self._existingCounts = {}
		self._pendingExistingCounts = {}
		self._existingRequestToken += 1
		self._selectedRegion = nil
		self._selectedAura = false
	end
	self:_prefetchExistingCounts()
	self:_syncModalContents()
	self:_syncCharacterViewport()
end

function PlayerInspectController:_openForPlayer(player: Player)
	self._requestToken += 1
	local requestToken = self._requestToken
	self._inspectedPlayer = player
	self._inspectedUserId = player.UserId
	self._summary = nil
	self._selectedRegion = nil
	self._selectedAura = false
	self._hoveredAura = false
	FrameController:OpenFrame(WINDOW_NAME)
	self:_syncModalContents()
	self:_setSelectText("Loading...")
	self:_syncCharacterViewport()

	task.spawn(function()
		if requestToken ~= self._requestToken then
			return
		end

		local summary = self:_requestInspectSummary(player.UserId)
		if requestToken ~= self._requestToken then
			return
		end

		if not summary then
			FrameController:CloseFrame(WINDOW_NAME)
			self:_clearState()
			return
		end

		self:_applySummary(player, summary)
		self:_startSummaryRefreshLoop(requestToken, player.UserId)
	end)
end

function PlayerInspectController:_bindRegionButtons()
	local ui = self._ui
	if not ui then
		return
	end

	for _, region in ipairs(BodyPartRegions.Order) do
		local button = ui.regionButtons[region]
		if button then
			UIController:CreateButton(button, function()
				if self:_getEquippedEntries()[region] == nil then
					self:_setSelectedRegion(nil)
					return
				end

				self:_setSelectedRegion(region)
			end)

			button.MouseEnter:Connect(function()
				self._hoveredRegion = region
				self._hoveredAura = false
				self:_syncModalContents()
			end)

			button.MouseLeave:Connect(function()
				if self._hoveredRegion == region then
					self._hoveredRegion = nil
					self:_syncModalContents()
				end
			end)
		end
	end

	local auraButton = ui.auraButton
	if auraButton then
		UIController:CreateButton(auraButton, function()
			if self:_getEquippedAuraEntry() == nil then
				self:_setSelectedAura(false)
				return
			end

			self:_setSelectedAura(true)
		end)

		auraButton.MouseEnter:Connect(function()
			self._hoveredAura = true
			self._hoveredRegion = nil
			self:_syncModalContents()
		end)

		auraButton.MouseLeave:Connect(function()
			if self._hoveredAura then
				self._hoveredAura = false
				self:_syncModalContents()
			end
		end)
	end
end

function PlayerInspectController:_cacheUi(playerGui: PlayerGui)
	local modalRoot = playerGui:WaitForChild("ModalRoot", 30)
	if not (modalRoot and modalRoot:IsA("ScreenGui")) then
		error("PlayerGui.ModalRoot is missing.")
	end

	local playerInfoRoot = modalRoot:WaitForChild(WINDOW_NAME, 30)
	if not (playerInfoRoot and playerInfoRoot:IsA("Frame")) then
		error("PlayerGui.ModalRoot.PlayerInfo is missing.")
	end

	local topbar = playerInfoRoot:WaitForChild("Topbar", 30)
	local characterRoot = playerInfoRoot:WaitForChild("Character", 30)
	local characterViewport = characterRoot:WaitForChild("Character", 30)
	local partInfo = playerInfoRoot:WaitForChild("PartInfo", 30)
	local partInfoFrame = partInfo:WaitForChild("Frame", 30)
	local headerLabel = topbar:WaitForChild("Header", 30)
	local selectTextLabel = playerInfoRoot:WaitForChild("SelectText", 30)

	local regionFrames = {}
	local regionButtons = {}
	for _, region in ipairs(BodyPartRegions.Order) do
		local regionFrame = characterViewport:FindFirstChild(region)
		if regionFrame and regionFrame:IsA("Frame") then
			regionFrames[region] = regionFrame
			local button = regionFrame:FindFirstChild("Temp")
			if button and button:IsA("ImageButton") then
				regionButtons[region] = button
				self._slotPlaceholderDefaults[region] = captureSlotPlaceholderState(button)
			end
		end
	end

	local partInfoScale = partInfo:FindFirstChildWhichIsA("UIScale")
	if not partInfoScale then
		partInfoScale = Instance.new("UIScale")
		partInfoScale.Parent = partInfo
	end

	local usernameLabel = topbar:FindFirstChild("Username")
	if usernameLabel and not usernameLabel:IsA("TextLabel") then
		usernameLabel = nil
	end

	local totalOddsAddedLabel = characterRoot:FindFirstChild("TotalOddsAdded")
	if totalOddsAddedLabel and not totalOddsAddedLabel:IsA("TextLabel") then
		totalOddsAddedLabel = nil
	end

	local auraFrame = characterRoot:FindFirstChild("Aura")
	if auraFrame and not auraFrame:IsA("GuiObject") then
		auraFrame = nil
	end
	local auraButton = if auraFrame and auraFrame:IsA("GuiObject")
		then auraFrame:FindFirstChild("Temp")
		else nil
	if auraButton and not auraButton:IsA("ImageButton") then
		auraButton = nil
	end

	self._ui = {
		root = playerInfoRoot,
		topbar = topbar,
		headerLabel = headerLabel,
		usernameLabel = usernameLabel,
		selectTextLabel = selectTextLabel,
		characterViewport = characterViewport,
		partInfo = partInfo,
		partInfoScale = partInfoScale,
		partInfoLabels = {
			Bundle = partInfoFrame:WaitForChild("Bundle", 30),
			EverRolled = partInfoFrame:WaitForChild("EverRolled", 30),
			Rarity = partInfoFrame:WaitForChild("Rarity", 30),
			Mutation = partInfoFrame:WaitForChild("Mutation", 30),
			Content = partInfoFrame:WaitForChild("Content", 30),
			Existing = partInfoFrame:WaitForChild("Existing", 30),
			Cash = partInfoFrame:WaitForChild("Cash", 30),
			Chance = partInfoFrame:WaitForChild("Chance", 30),
		},
		regionFrames = regionFrames,
		regionButtons = regionButtons,
		auraFrame = auraFrame,
		auraButton = auraButton,
		incomeLabel = characterRoot:WaitForChild("Income", 30),
		luckLabel = characterRoot:WaitForChild("Luck", 30),
		rollSpeedLabel = characterRoot:WaitForChild("Roll Speed", 30),
		totalOddsAddedLabel = totalOddsAddedLabel,
	}
	self._slotCardRenderer = SlotCardRenderer.new(playerGui)

	for _, label in pairs(self._ui.partInfoLabels) do
		label.RichText = true
	end
	self._partInfoLabelFontFaces = {
		Bundle = self._ui.partInfoLabels.Bundle.FontFace,
		Rarity = self._ui.partInfoLabels.Rarity.FontFace,
	}
	self._partInfoEverRolledNativeText = self._ui.partInfoLabels.EverRolled.Text
	self._partInfoEverRolledSuffixText = extractTrailingLabelText(self._partInfoEverRolledNativeText, "Ever Rolled")

	playerInfoRoot.Visible = false
	partInfo.Visible = false
	self:_clearState()

	playerInfoRoot:GetPropertyChangedSignal("Visible"):Connect(function()
		if not playerInfoRoot.Visible then
			self:_clearState()
		end
	end)
end

function PlayerInspectController:OnStart()
	self:_ensureState()

	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	self:_cacheUi(playerGui)
	self:_bindRegionButtons()

	self._mouse.Move:Connect(function()
		self:_setHoveredPlayer(getPointerInspectablePlayer(self._mouse))
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
		if gameProcessedEvent then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if UserInputService:GetFocusedTextBox() then
			return
		end

		local targetPlayer = getPointerInspectablePlayer(self._mouse) or self._hoveredPlayer
		if targetPlayer then
			self:_setHoveredPlayer(targetPlayer)
			self:_openForPlayer(targetPlayer)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		if self._hoveredPlayer == player then
			self:_setHoveredPlayer(nil)
		end

		if self._inspectedUserId == player.UserId then
			FrameController:CloseFrame(WINDOW_NAME)
			self:_clearState()
		end
	end)
end

return PlayerInspectController
