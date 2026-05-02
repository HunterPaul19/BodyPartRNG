local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatPower = require(ReplicatedStorage.Shared.Combat.CombatPower)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local NumberFormatter = require(ReplicatedStorage.Shared.Formatting.NumberFormatter)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)
local TitleUtil = require(ReplicatedStorage.Shared.Titles.TitleUtil)

local LOCAL_PLAYER = Players.LocalPlayer
local BOSS_ARENA_PROFILE_ID = "boss_arena"
local BILLBOARD_NAME = "PlayerTitleBillboard"
local BILLBOARD_MAX_DISTANCE = 120
local BILLBOARD_SIZE = UDim2.fromOffset(260, 78)
local BOSS_ARENA_BILLBOARD_SIZE = UDim2.fromOffset(260, 104)
local BILLBOARD_OFFSET = Vector3.new(0, 3.4, 0)
local PREFIX_LABEL_PREFIX = "PrefixLabel"
local PREFIX_ROW_HEIGHT = 18
local NAME_ROW_HEIGHT = 26
local POWER_LABEL_NAME = "PowerLabel"
local POWER_ROW_HEIGHT = 22
local POWER_ROW_GAP = 2
local POWER_LABEL_FONT_FACE = Font.new("rbxassetid://12187375422", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
local ACCESS_ATTRIBUTE = "CanUseAdminPanel"
local POWER_STAT_ATTRIBUTE_NAMES = table.freeze({
	"BodyPartDamage",
	"BodyPartHealth",
	"BodyPartSpeed",
})

type PlayerState = {
	characterConnections: { RBXScriptConnection },
	playerConnections: { RBXScriptConnection },
	billboard: BillboardGui?,
}

local OverheadTitleController = {}

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

local function isPrefixLabel(instance: Instance): boolean
	return instance:IsA("TextLabel") and string.match(instance.Name, "^" .. PREFIX_LABEL_PREFIX .. "%d+$") ~= nil
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

local function clearPrefixLabels(billboard: BillboardGui)
	for _, child in ipairs(billboard:GetChildren()) do
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

local function layoutNameLabel(nameLabel: TextLabel, prefixCount: number): number
	local nameY = 26
	if prefixCount <= 0 then
		nameY = 26
	else
		nameY = 4 + (prefixCount * PREFIX_ROW_HEIGHT) + 12
	end

	nameLabel.Position = UDim2.new(0, 0, 0, nameY)
	nameLabel.Size = UDim2.new(1, 0, 0, NAME_ROW_HEIGHT)
	return nameY + NAME_ROW_HEIGHT
end

local function calculateBillboardHeight(prefixCount: number, nameBottomY: number, showPowerLabel: boolean): number
	local minimumHeight = if showPowerLabel then BOSS_ARENA_BILLBOARD_SIZE.Y.Offset else BILLBOARD_SIZE.Y.Offset
	local contentBottomY = nameBottomY
	if showPowerLabel then
		contentBottomY += POWER_ROW_GAP + POWER_ROW_HEIGHT
	end

	return math.max(minimumHeight, contentBottomY + 12)
end

local function layoutPowerLabel(powerLabel: TextLabel, nameBottomY: number)
	powerLabel.Position = UDim2.new(0, 0, 0, nameBottomY + POWER_ROW_GAP)
	powerLabel.Size = UDim2.new(1, 0, 0, POWER_ROW_HEIGHT)
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

		billboard = Instance.new("BillboardGui")
		billboard.Name = BILLBOARD_NAME
		billboard.AlwaysOnTop = true
		billboard.LightInfluence = 0
		billboard.MaxDistance = BILLBOARD_MAX_DISTANCE
		billboard.StudsOffsetWorldSpace = BILLBOARD_OFFSET
		billboard.Adornee = head
		billboard.Parent = character

		local nameLabel = createTextLabel("NameLabel", UDim2.new(1, 0, 0, NAME_ROW_HEIGHT), UDim2.new(0, 0, 0, 26), 18)
		nameLabel.Parent = billboard

		state.billboard = billboard
	end

	local showPowerLabel = isBossArenaPowerEnabled()

	local nameLabel = billboard:FindFirstChild("NameLabel")
	if not (nameLabel and nameLabel:IsA("TextLabel")) then
		return
	end

	clearPrefixLabels(billboard)

	local prefixSegments = TitleUtil.GetPrefixSegments(
		player:GetAttribute("PremiumTag"),
		player:GetAttribute("EquippedTitleId"),
		player:GetAttribute(ACCESS_ATTRIBUTE) == true
	)
	for index, segment in ipairs(prefixSegments) do
		local prefixLabel = createTextLabel(
			string.format("%s%d", PREFIX_LABEL_PREFIX, index),
			UDim2.new(1, 0, 0, PREFIX_ROW_HEIGHT),
			UDim2.new(0, 0, 0, 4 + ((index - 1) * PREFIX_ROW_HEIGHT)),
			15
		)
		prefixLabel.Text = formatPrefixSegment(segment)
		prefixLabel.Parent = billboard
	end

	local nameBottomY = layoutNameLabel(nameLabel, #prefixSegments)
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

		layoutPowerLabel(powerLabel, nameBottomY)
		powerLabel.Text = formatPowerText(player)
	elseif powerLabel then
		powerLabel:Destroy()
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
