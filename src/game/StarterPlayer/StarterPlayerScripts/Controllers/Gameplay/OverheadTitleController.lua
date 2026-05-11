local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatPower = require(ReplicatedStorage.Shared.Combat.CombatPower)
local GameAssetPaths = require(ReplicatedStorage.Shared.Assets.GameAssetPaths)
local GameAssetResolver = require(ReplicatedStorage.Shared.Assets.GameAssetResolver)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local NumberFormatter = require(ReplicatedStorage.Shared.Formatting.NumberFormatter)
local BodyPartPresentation = require(ReplicatedStorage.Shared.UI.BodyPartPresentation)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)
local TitleUtil = require(ReplicatedStorage.Shared.Titles.TitleUtil)

local LOCAL_PLAYER = Players.LocalPlayer
local BOSS_ARENA_PROFILE_ID = "boss_arena"
local BILLBOARD_NAME = "PlayerTitleBillboard"
local BILLBOARD_MAX_DISTANCE = 120
local BILLBOARD_SIZE = UDim2.fromOffset(260, 100)
local BOSS_ARENA_BILLBOARD_SIZE = UDim2.fromOffset(260, 126)
local BILLBOARD_OFFSET = Vector3.new(0, 3.4, 0)
local PREFIX_LABEL_PREFIX = "PrefixLabel"
local PREFIX_CONTAINER_NAME = "PrefixContainer"
local PREFIX_LABEL_TEMPLATE_NAME = "PrefixLabelTemplate"
local PREFIX_ROW_HEIGHT = 18
local NAME_ROW_HEIGHT = 26
local RAREST_PART_LABEL_NAME = "RarestPartLabel"
local RAREST_PART_ROW_HEIGHT = 20
local RAREST_PART_ROW_GAP = 2
local PVP_LABEL_NAME = "PvpLabel"
local PVP_ROW_HEIGHT = 20
local PVP_ROW_GAP = 2
local POWER_LABEL_NAME = "PowerLabel"
local POWER_ROW_HEIGHT = 22
local POWER_ROW_GAP = 2
local POWER_LABEL_FONT_FACE = Font.new("rbxassetid://12187375422", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
local ACCESS_ATTRIBUTE = "CanUseAdminPanel"
local PVP_ENABLED_ATTRIBUTE = "PvpEnabled"
local RAREST_OWNED_BODY_PART_PIECE_ID_ATTRIBUTE = "RarestOwnedBodyPartPieceId"
local RAREST_OWNED_BODY_PART_DISPLAY_RARITY_ATTRIBUTE = "RarestOwnedBodyPartDisplayRarity"
local RAREST_OWNED_BODY_PART_ODDS_DENOMINATOR_ATTRIBUTE = "RarestOwnedBodyPartOddsDenominator"
local POWER_STAT_ATTRIBUTE_NAMES = table.freeze({
	"BodyPartDamage",
	"BodyPartHealth",
	"BodyPartSpeed",
})
local RAREST_OWNED_ATTRIBUTE_NAMES = table.freeze({
	RAREST_OWNED_BODY_PART_PIECE_ID_ATTRIBUTE,
	RAREST_OWNED_BODY_PART_DISPLAY_RARITY_ATTRIBUTE,
	RAREST_OWNED_BODY_PART_ODDS_DENOMINATOR_ATTRIBUTE,
})

type PlayerState = {
	characterConnections: { RBXScriptConnection },
	playerConnections: { RBXScriptConnection },
	billboard: BillboardGui?,
}

local OverheadTitleController = {}
local warnedTemplateIssues: { [string]: boolean } = {}
local baseRarestPartLabelStyles = setmetatable({}, { __mode = "k" })

local function disconnectConnections(connections: { RBXScriptConnection })
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function createTextLabel(name: string, size: UDim2, position: UDim2, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Size = size
	label.Position = position
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = false
	label.TextSize = textSize
	label.TextStrokeTransparency = 0.45
	label.TextWrapped = true
	label.RichText = true
	label.ZIndex = 2
	return label
end

local function createPowerLabel(): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = POWER_LABEL_NAME
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.FontFace = POWER_LABEL_FONT_FACE
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.TextSize = 14
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 1
	label.TextWrapped = true
	label.RichText = false
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.ZIndex = 2
	return label
end

local function createRarestPartLabel(): TextLabel
	local label = createTextLabel(RAREST_PART_LABEL_NAME, UDim2.new(1, 0, 0, RAREST_PART_ROW_HEIGHT), UDim2.new(), 14)
	label.Text = "Rarest: None"
	return label
end

local function createPvpLabel(): TextLabel
	local label = createTextLabel(PVP_LABEL_NAME, UDim2.new(1, 0, 0, PVP_ROW_HEIGHT), UDim2.new(), 15)
	label.Text = "[PVP]"
	label.TextColor3 = Color3.fromRGB(255, 64, 64)
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.35
	label.Visible = false
	return label
end

local function isPrefixLabel(instance: Instance): boolean
	return instance:IsA("TextLabel") and string.match(instance.Name, "^" .. PREFIX_LABEL_PREFIX .. "%d+$") ~= nil
end

local function warnTemplateIssue(message: string)
	if warnedTemplateIssues[message] == true then
		return
	end

	warnedTemplateIssues[message] = true
	warn("[OverheadTitleController] " .. message)
end

local function findTemplateDescendant(root: Instance, name: string, className: string): Instance?
	local descendant = root:FindFirstChild(name, true)
	if descendant and descendant.ClassName == className then
		return descendant
	end

	return nil
end

local function getBillboardTemplate(): BillboardGui?
	local template = GameAssetResolver.Find(GameAssetPaths.UI.PlayerOverhead, BILLBOARD_NAME)
	if not template then
		warnTemplateIssue(
			string.format(
				"Missing %s.%s; using runtime fallback billboard.",
				GameAssetResolver.Format(GameAssetPaths.UI.PlayerOverhead),
				BILLBOARD_NAME
			)
		)
		return nil
	end
	if not template:IsA("BillboardGui") then
		warnTemplateIssue(
			string.format(
				"%s.%s must be a BillboardGui; using runtime fallback billboard.",
				GameAssetResolver.Format(GameAssetPaths.UI.PlayerOverhead),
				BILLBOARD_NAME
			)
		)
		return nil
	end

	local nameLabel = findTemplateDescendant(template, "NameLabel", "TextLabel")
	local prefixContainer = findTemplateDescendant(template, PREFIX_CONTAINER_NAME, "Frame")
	local prefixLabelTemplate = prefixContainer and prefixContainer:FindFirstChild(PREFIX_LABEL_TEMPLATE_NAME)
	local rarestPartLabel = findTemplateDescendant(template, RAREST_PART_LABEL_NAME, "TextLabel")
	local pvpLabel = findTemplateDescendant(template, PVP_LABEL_NAME, "TextLabel")
	local powerLabel = findTemplateDescendant(template, POWER_LABEL_NAME, "TextLabel")
	if not (nameLabel and prefixContainer and prefixLabelTemplate and prefixLabelTemplate:IsA("TextLabel") and rarestPartLabel and pvpLabel and powerLabel) then
		warnTemplateIssue(
			string.format(
				"%s.%s is missing NameLabel, PrefixContainer.%s, RarestPartLabel, PvpLabel, or PowerLabel; using runtime fallback billboard.",
				GameAssetResolver.Format(GameAssetPaths.UI.PlayerOverhead),
				BILLBOARD_NAME,
				PREFIX_LABEL_TEMPLATE_NAME
			)
		)
		return nil
	end

	return template
end

local function createFallbackBillboard(head: BasePart, character: Model): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = BILLBOARD_NAME
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = BILLBOARD_MAX_DISTANCE
	billboard.StudsOffsetWorldSpace = BILLBOARD_OFFSET
	billboard.Adornee = head
	billboard.Parent = character

	local nameLabel = createTextLabel("NameLabel", UDim2.new(1, 0, 0, NAME_ROW_HEIGHT), UDim2.new(0, 0, 0, 26), 18)
	nameLabel.Parent = billboard

	local pvpLabel = createPvpLabel()
	pvpLabel.Parent = billboard

	local rarestPartLabel = createRarestPartLabel()
	rarestPartLabel.Parent = billboard

	return billboard
end

local function createTemplateBillboard(head: BasePart, character: Model): BillboardGui?
	local template = getBillboardTemplate()
	if not template then
		return nil
	end

	local billboard = template:Clone()
	billboard.Name = BILLBOARD_NAME
	billboard.Adornee = head
	billboard.Parent = character
	return billboard
end

local function findBillboardTextLabel(billboard: BillboardGui, name: string): TextLabel?
	local label = billboard:FindFirstChild(name, true)
	if label and label:IsA("TextLabel") then
		return label
	end

	return nil
end

local function getPrefixContainer(billboard: BillboardGui): Frame?
	local container = billboard:FindFirstChild(PREFIX_CONTAINER_NAME, true)
	if container and container:IsA("Frame") then
		return container
	end

	return nil
end

local function getPrefixLabelTemplate(prefixContainer: Frame?): TextLabel?
	local template = prefixContainer and prefixContainer:FindFirstChild(PREFIX_LABEL_TEMPLATE_NAME)
	if template and template:IsA("TextLabel") then
		return template
	end

	return nil
end

local function isBossArenaPowerEnabled(): boolean
	return PlaceProfile.GetActiveProfile().id == BOSS_ARENA_PROFILE_ID
end

local function applyHumanoidOverheadDisplay(humanoid: Humanoid)
	if isBossArenaPowerEnabled() then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
		humanoid.HealthDisplayDistance = BILLBOARD_MAX_DISTANCE
		humanoid.NameDisplayDistance = 0
		return
	end

	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
end

local function getNumberAttribute(player: Player, attributeName: string, fallback: any, minimum: number): number
	local value = tonumber(player:GetAttribute(attributeName))
	if value == nil then
		value = tonumber(fallback)
	end

	return math.max(minimum, value or minimum)
end

local function calculatePlayerPower(player: Player): number
	local basePlayerStats = BodyPartsCatalog.GetBasePlayerStats()
	return CombatPower.CalculateAboveBase({
		damage = getNumberAttribute(player, "BodyPartDamage", basePlayerStats.damage, 0),
		health = getNumberAttribute(player, "BodyPartHealth", basePlayerStats.health, 1),
		speed = getNumberAttribute(player, "BodyPartSpeed", basePlayerStats.speed, 0),
	}, basePlayerStats)
end

local function formatPowerText(player: Player): string
	local roundedPower = math.max(0, math.floor(calculatePlayerPower(player) + 0.5))
	return string.format("Power: %s", NumberFormatter.Format(roundedPower))
end

local function isPvpEnabled(player: Player): boolean
	return player:GetAttribute(PVP_ENABLED_ATTRIBUTE) == true
end

local function clearSupportedTextAdornments(label: TextLabel)
	for _, child in ipairs(label:GetChildren()) do
		if child:IsA("UIGradient") or child:IsA("UIStroke") then
			child:Destroy()
		end
	end
end

local function cloneSupportedTextAdornments(label: TextLabel): { Instance }
	local clones = {}
	for _, child in ipairs(label:GetChildren()) do
		if child:IsA("UIGradient") or child:IsA("UIStroke") then
			table.insert(clones, child:Clone())
		end
	end

	return clones
end

local function captureBaseRarestPartLabelStyle(label: TextLabel)
	if baseRarestPartLabelStyles[label] then
		return
	end

	baseRarestPartLabelStyles[label] = {
		TextColor3 = label.TextColor3,
		FontFace = label.FontFace,
		TextStrokeColor3 = label.TextStrokeColor3,
		TextStrokeTransparency = label.TextStrokeTransparency,
		RichText = label.RichText,
		Adornments = cloneSupportedTextAdornments(label),
	}
end

local function restoreBaseRarestPartLabelStyle(label: TextLabel)
	captureBaseRarestPartLabelStyle(label)
	local style = baseRarestPartLabelStyles[label]
	if not style then
		return
	end

	label.TextColor3 = style.TextColor3
	label.FontFace = style.FontFace
	label.TextStrokeColor3 = style.TextStrokeColor3
	label.TextStrokeTransparency = style.TextStrokeTransparency
	label.RichText = style.RichText
	clearSupportedTextAdornments(label)

	for _, adornment in ipairs(style.Adornments) do
		adornment:Clone().Parent = label
	end
end

local function formatRarestPartText(player: Player): string
	local denominator = tonumber(player:GetAttribute(RAREST_OWNED_BODY_PART_ODDS_DENOMINATOR_ATTRIBUTE))
	if not denominator or denominator < 1 then
		return "Rarest: None"
	end

	return string.format("Rarest: 1/%s", NumberFormatter.Format(math.floor(denominator)))
end

local function applyRarestPartLabelContent(label: TextLabel, player: Player)
	captureBaseRarestPartLabelStyle(label)
	label.Visible = true
	label.Text = formatRarestPartText(player)

	local denominator = tonumber(player:GetAttribute(RAREST_OWNED_BODY_PART_ODDS_DENOMINATOR_ATTRIBUTE))
	local pieceId = player:GetAttribute(RAREST_OWNED_BODY_PART_PIECE_ID_ATTRIBUTE)
	if not denominator or denominator < 1 or typeof(pieceId) ~= "string" or pieceId == "" then
		restoreBaseRarestPartLabelStyle(label)
		return
	end

	local piece = BodyPartsCatalog.GetPiece(pieceId)
	local setConfig = piece and BodyPartsCatalog.GetSetForPiece(pieceId)
	if not setConfig then
		restoreBaseRarestPartLabelStyle(label)
		return
	end

	clearSupportedTextAdornments(label)
	BodyPartPresentation.ApplySetRarityTemplateToLabel(
		label,
		setConfig,
		player:GetAttribute(RAREST_OWNED_BODY_PART_DISPLAY_RARITY_ATTRIBUTE)
	)
end

local function clearPrefixLabels(billboard: BillboardGui)
	for _, child in ipairs(billboard:GetChildren()) do
		if isPrefixLabel(child) then
			child:Destroy()
		end
	end
end

local function clearTemplatePrefixLabels(prefixContainer: Frame)
	for _, child in ipairs(prefixContainer:GetChildren()) do
		if isPrefixLabel(child) then
			child:Destroy()
		end
	end
end

local function formatPrefixSegment(segment): string
	return string.format(
		'<font color="%s"><b>%s</b></font>',
		tostring(segment.colorHex or "#ffffff"),
		TitleUtil.EscapeRichText(segment.text)
	)
end

local function layoutNameLabel(nameLabel: TextLabel, prefixCount: number, topOffset: number?): number
	topOffset = topOffset or 0
	local nameY = topOffset + 26
	if prefixCount <= 0 then
		nameY = topOffset + 26
	else
		nameY = topOffset + 4 + (prefixCount * PREFIX_ROW_HEIGHT) + 12
	end

	nameLabel.Position = UDim2.new(0, 0, 0, nameY)
	nameLabel.Size = UDim2.new(1, 0, 0, NAME_ROW_HEIGHT)
	return nameY + NAME_ROW_HEIGHT
end

local function calculateBillboardHeight(prefixCount: number, nameBottomY: number, showPowerLabel: boolean): number
	local minimumHeight = if showPowerLabel then BOSS_ARENA_BILLBOARD_SIZE.Y.Offset else BILLBOARD_SIZE.Y.Offset
	local rarestPartBottomY = nameBottomY + RAREST_PART_ROW_GAP + RAREST_PART_ROW_HEIGHT
	local contentBottomY = rarestPartBottomY
	if showPowerLabel then
		contentBottomY += POWER_ROW_GAP + POWER_ROW_HEIGHT
	end

	return math.max(minimumHeight, contentBottomY + 12)
end

local function layoutRarestPartLabel(rarestPartLabel: TextLabel, nameBottomY: number): number
	local rarestPartY = nameBottomY + RAREST_PART_ROW_GAP
	rarestPartLabel.Position = UDim2.new(0, 0, 0, rarestPartY)
	rarestPartLabel.Size = UDim2.new(1, 0, 0, RAREST_PART_ROW_HEIGHT)
	return rarestPartY + RAREST_PART_ROW_HEIGHT
end

local function layoutPowerLabel(powerLabel: TextLabel, rarestPartBottomY: number)
	powerLabel.Position = UDim2.new(0, 0, 0, rarestPartBottomY + POWER_ROW_GAP)
	powerLabel.Size = UDim2.new(1, 0, 0, POWER_ROW_HEIGHT)
end

local function layoutPvpLabel(pvpLabel: TextLabel): number
	pvpLabel.Position = UDim2.new(0, 0, 0, 0)
	pvpLabel.Size = UDim2.new(1, 0, 0, PVP_ROW_HEIGHT)
	return PVP_ROW_HEIGHT + PVP_ROW_GAP
end

local function renderFallbackContents(billboard: BillboardGui, player: Player, prefixSegments, showPowerLabel: boolean)
	local nameLabel = billboard:FindFirstChild("NameLabel")
	if not (nameLabel and nameLabel:IsA("TextLabel")) then
		return
	end

	clearPrefixLabels(billboard)

	local pvpLabel = billboard:FindFirstChild(PVP_LABEL_NAME)
	if not (pvpLabel and pvpLabel:IsA("TextLabel")) then
		if pvpLabel then
			pvpLabel:Destroy()
		end
		pvpLabel = createPvpLabel()
		pvpLabel.Parent = billboard
	end
	local showPvpLabel = isPvpEnabled(player)
	pvpLabel.Visible = showPvpLabel
	local topOffset = if showPvpLabel then layoutPvpLabel(pvpLabel) else 0

	for index, segment in ipairs(prefixSegments) do
		local prefixLabel = createTextLabel(
			string.format("%s%d", PREFIX_LABEL_PREFIX, index),
			UDim2.new(1, 0, 0, PREFIX_ROW_HEIGHT),
			UDim2.new(0, 0, 0, topOffset + 4 + ((index - 1) * PREFIX_ROW_HEIGHT)),
			15
		)
		prefixLabel.Text = formatPrefixSegment(segment)
		prefixLabel.Parent = billboard
	end

	local nameBottomY = layoutNameLabel(nameLabel, #prefixSegments, topOffset)
	local rarestPartLabel = billboard:FindFirstChild(RAREST_PART_LABEL_NAME)
	if not (rarestPartLabel and rarestPartLabel:IsA("TextLabel")) then
		if rarestPartLabel then
			rarestPartLabel:Destroy()
		end
		rarestPartLabel = createRarestPartLabel()
		rarestPartLabel.Parent = billboard
	end
	local rarestPartBottomY = layoutRarestPartLabel(rarestPartLabel, nameBottomY)
	applyRarestPartLabelContent(rarestPartLabel, player)

	billboard.Size = UDim2.fromOffset(
		BILLBOARD_SIZE.X.Offset,
		calculateBillboardHeight(#prefixSegments, nameBottomY, showPowerLabel)
	)
	nameLabel.Text = TitleUtil.EscapeRichText(player.DisplayName)

	local powerLabel = billboard:FindFirstChild(POWER_LABEL_NAME)
	if showPowerLabel then
		if not (powerLabel and powerLabel:IsA("TextLabel")) then
			if powerLabel then
				powerLabel:Destroy()
			end
			powerLabel = createPowerLabel()
			powerLabel.Parent = billboard
		end

		layoutPowerLabel(powerLabel, rarestPartBottomY)
		powerLabel.Visible = true
		powerLabel.Text = formatPowerText(player)
	elseif powerLabel then
		powerLabel:Destroy()
	end
end

local function renderTemplateContents(billboard: BillboardGui, player: Player, prefixSegments, showPowerLabel: boolean): boolean
	local nameLabel = findBillboardTextLabel(billboard, "NameLabel")
	local prefixContainer = getPrefixContainer(billboard)
	local prefixLabelTemplate = getPrefixLabelTemplate(prefixContainer)
	local rarestPartLabel = findBillboardTextLabel(billboard, RAREST_PART_LABEL_NAME)
	local pvpLabel = findBillboardTextLabel(billboard, PVP_LABEL_NAME)
	local powerLabel = findBillboardTextLabel(billboard, POWER_LABEL_NAME)
	if not (nameLabel and prefixContainer and prefixLabelTemplate and rarestPartLabel and pvpLabel and powerLabel) then
		return false
	end

	nameLabel.Text = TitleUtil.EscapeRichText(player.DisplayName)
	pvpLabel.Visible = isPvpEnabled(player)
	applyRarestPartLabelContent(rarestPartLabel, player)
	clearTemplatePrefixLabels(prefixContainer)
	prefixContainer.Visible = #prefixSegments > 0
	prefixLabelTemplate.Visible = false

	for index, segment in ipairs(prefixSegments) do
		local prefixLabel = prefixLabelTemplate:Clone()
		prefixLabel.Name = string.format("%s%d", PREFIX_LABEL_PREFIX, index)
		prefixLabel.LayoutOrder = index
		prefixLabel.Text = formatPrefixSegment(segment)
		prefixLabel.Visible = true
		prefixLabel.Parent = prefixContainer
	end

	powerLabel.Visible = showPowerLabel
	if showPowerLabel then
		powerLabel.Text = formatPowerText(player)
	end

	return true
end

function OverheadTitleController:_ensureState()
	if self._started then
		return
	end

	self._started = true
	self._players = {}
end

function OverheadTitleController:_getPlayerState(player: Player): PlayerState
	local state = self._players[player]
	if state then
		return state
	end

	state = {
		characterConnections = {},
		playerConnections = {},
		billboard = nil,
	}
	self._players[player] = state
	return state
end

function OverheadTitleController:_destroyBillboard(player: Player)
	local state = self._players[player]
	if not state then
		return
	end

	if state.billboard then
		state.billboard:Destroy()
		state.billboard = nil
	end
end

function OverheadTitleController:_renderBillboard(player: Player)
	local state = self:_getPlayerState(player)
	local character = player.Character
	if not character then
		self:_destroyBillboard(player)
		return
	end

	local head = character:FindFirstChild("Head")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not (head and head:IsA("BasePart")) then
		self:_destroyBillboard(player)
		return
	end

	if humanoid then
		applyHumanoidOverheadDisplay(humanoid)
	end

	local billboard = state.billboard
	if not billboard or billboard.Parent ~= character then
		if billboard then
			billboard:Destroy()
		end

		billboard = createTemplateBillboard(head, character) or createFallbackBillboard(head, character)

		state.billboard = billboard
	end
	billboard.Adornee = head

	local showPowerLabel = isBossArenaPowerEnabled()
	local prefixSegments = TitleUtil.GetPrefixSegments(
		player:GetAttribute("PremiumTag"),
		player:GetAttribute("EquippedTitleId"),
		player:GetAttribute(ACCESS_ATTRIBUTE) == true
	)

	if not renderTemplateContents(billboard, player, prefixSegments, showPowerLabel) then
		renderFallbackContents(billboard, player, prefixSegments, showPowerLabel)
	end
end

function OverheadTitleController:_bindCharacter(player: Player, character: Model)
	local state = self:_getPlayerState(player)
	disconnectConnections(state.characterConnections)

	table.insert(state.characterConnections, character.ChildAdded:Connect(function(child)
		if child.Name == "Head" or child:IsA("Humanoid") then
			self:_renderBillboard(player)
		end
	end))
	table.insert(state.characterConnections, character.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			self:_destroyBillboard(player)
		end
	end))

	task.defer(function()
		if player.Character == character then
			self:_renderBillboard(player)
		end
	end)
end

function OverheadTitleController:_trackPlayer(player: Player)
	local state = self:_getPlayerState(player)
	disconnectConnections(state.playerConnections)

	table.insert(state.playerConnections, player:GetAttributeChangedSignal("PremiumTag"):Connect(function()
		self:_renderBillboard(player)
	end))
	table.insert(state.playerConnections, player:GetAttributeChangedSignal("EquippedTitleId"):Connect(function()
		self:_renderBillboard(player)
	end))
	table.insert(state.playerConnections, player:GetAttributeChangedSignal(ACCESS_ATTRIBUTE):Connect(function()
		self:_renderBillboard(player)
	end))
	table.insert(state.playerConnections, player:GetAttributeChangedSignal(PVP_ENABLED_ATTRIBUTE):Connect(function()
		self:_renderBillboard(player)
	end))
	for _, attributeName in ipairs(RAREST_OWNED_ATTRIBUTE_NAMES) do
		table.insert(state.playerConnections, player:GetAttributeChangedSignal(attributeName):Connect(function()
			self:_renderBillboard(player)
		end))
	end
	table.insert(state.playerConnections, player:GetPropertyChangedSignal("DisplayName"):Connect(function()
		self:_renderBillboard(player)
	end))
	if isBossArenaPowerEnabled() then
		for _, attributeName in ipairs(POWER_STAT_ATTRIBUTE_NAMES) do
			table.insert(state.playerConnections, player:GetAttributeChangedSignal(attributeName):Connect(function()
				self:_renderBillboard(player)
			end))
		end
	end
	table.insert(state.playerConnections, player.CharacterAdded:Connect(function(character)
		self:_bindCharacter(player, character)
	end))
	table.insert(state.playerConnections, player.CharacterRemoving:Connect(function()
		self:_destroyBillboard(player)
	end))

	if player.Character then
		self:_bindCharacter(player, player.Character)
	end
end

function OverheadTitleController:_untrackPlayer(player: Player)
	local state = self._players[player]
	if not state then
		return
	end

	disconnectConnections(state.playerConnections)
	disconnectConnections(state.characterConnections)
	self:_destroyBillboard(player)
	self._players[player] = nil
end

function OverheadTitleController:OnStart()
	self:_ensureState()

	for _, player in ipairs(Players:GetPlayers()) do
		self:_trackPlayer(player)
	end

	Players.PlayerAdded:Connect(function(player)
		self:_trackPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:_untrackPlayer(player)
	end)

	if LOCAL_PLAYER then
		self:_renderBillboard(LOCAL_PLAYER)
	end
end

return OverheadTitleController
