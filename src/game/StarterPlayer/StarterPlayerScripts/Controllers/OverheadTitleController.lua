local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TitleUtil = require(ReplicatedStorage.Shared.Titles.TitleUtil)

local LOCAL_PLAYER = Players.LocalPlayer
local BILLBOARD_NAME = "PlayerTitleBillboard"
local BILLBOARD_SIZE = UDim2.fromOffset(260, 58)
local BILLBOARD_OFFSET = Vector3.new(0, 3.4, 0)

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
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
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
		billboard.MaxDistance = 120
		billboard.Size = BILLBOARD_SIZE
		billboard.StudsOffsetWorldSpace = BILLBOARD_OFFSET
		billboard.Adornee = head
		billboard.Parent = character

		local prefixLabel = createTextLabel("PrefixLabel", UDim2.new(1, 0, 0.42, 0), UDim2.fromScale(0, 0), 16)
		prefixLabel.Parent = billboard

		local nameLabel = createTextLabel("NameLabel", UDim2.new(1, 0, 0.52, 0), UDim2.fromScale(0, 0.4), 18)
		nameLabel.Parent = billboard

		state.billboard = billboard
	end

	local prefixLabel = billboard:FindFirstChild("PrefixLabel")
	local nameLabel = billboard:FindFirstChild("NameLabel")
	if not (prefixLabel and prefixLabel:IsA("TextLabel") and nameLabel and nameLabel:IsA("TextLabel")) then
		return
	end

	local richPrefix = TitleUtil.BuildRichTextPrefix(player:GetAttribute("VIP") == true, player:GetAttribute("EquippedTitleId"))
	prefixLabel.Visible = richPrefix ~= ""
	prefixLabel.Text = richPrefix
	nameLabel.Position = if richPrefix ~= "" then UDim2.fromScale(0, 0.42) else UDim2.fromScale(0, 0.2)
	nameLabel.Size = if richPrefix ~= "" then UDim2.new(1, 0, 0.48, 0) else UDim2.new(1, 0, 0.62, 0)
	nameLabel.Text = TitleUtil.EscapeRichText(player.DisplayName)
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

	table.insert(state.playerConnections, player:GetAttributeChangedSignal("VIP"):Connect(function()
		self:_renderBillboard(player)
	end))
	table.insert(state.playerConnections, player:GetAttributeChangedSignal("EquippedTitleId"):Connect(function()
		self:_renderBillboard(player)
	end))
	table.insert(state.playerConnections, player:GetPropertyChangedSignal("DisplayName"):Connect(function()
		self:_renderBillboard(player)
	end))
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
