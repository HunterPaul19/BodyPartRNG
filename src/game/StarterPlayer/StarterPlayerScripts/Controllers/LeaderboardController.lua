local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TitleUtil = require(ReplicatedStorage.Shared.Titles.TitleUtil)

local LOCAL_PLAYER = Players.LocalPlayer
local THUMBNAIL_TYPE = Enum.ThumbnailType.HeadShot
local THUMBNAIL_SIZE = Enum.ThumbnailSize.Size420x420
local LEADERBOARD_OPEN_POSITION = UDim2.fromScale(0.5, 0.5)
local LEADERBOARD_CLOSED_POSITION = UDim2.fromScale(1.5, 0.5)

local LeaderboardController = {}

local function getRichDisplayName(player: Player): string
	return TitleUtil.BuildRichTextDisplayName(
		player:GetAttribute("VIP") == true,
		player:GetAttribute("EquippedTitleId"),
		player.DisplayName
	)
end

local function getRichTitlePrefix(player: Player): string
	return TitleUtil.BuildRichTextPrefix(player:GetAttribute("VIP") == true, player:GetAttribute("EquippedTitleId"))
end

local function setCoreWithRetry(key: string, value: any): boolean
	for _ = 1, 8 do
		local ok = pcall(function()
			StarterGui:SetCore(key, value)
		end)
		if ok then
			return true
		end

		task.wait(0.25)
	end

	return false
end

local function disconnectConnections(connections: { RBXScriptConnection })
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function isCloseToPosition(a: UDim2, b: UDim2): boolean
	return math.abs(a.X.Scale - b.X.Scale) < 0.01
		and math.abs(a.X.Offset - b.X.Offset) < 1
		and math.abs(a.Y.Scale - b.Y.Scale) < 0.01
		and math.abs(a.Y.Offset - b.Y.Offset) < 1
end

function LeaderboardController:_ensureState()
	if self._started then
		return
	end

	self._started = true
	self._playerConnections = {}
	self._playerOrder = {}
	self._connections = {}
	self._scrollingFrame = nil
	self._template = nil
	self._playerInfo = nil
	self._leaderboardInner = nil
	self._selectedPlayer = nil
	self._thumbnailRequestId = 0
	self._ui = nil
	self._refreshScheduled = false
end

function LeaderboardController:_scheduleRefresh()
	if self._refreshScheduled then
		return
	end

	self._refreshScheduled = true
	task.defer(function()
		self._refreshScheduled = false
		self:_refreshRows()
	end)
end

function LeaderboardController:_getRollCount(player: Player): number
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		return 0
	end

	local rolls = stats:FindFirstChild("Rolls")
	if rolls and rolls:IsA("IntValue") then
		return math.max(0, rolls.Value)
	end

	return 0
end

function LeaderboardController:_getMoneyText(player: Player): string
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		return "0"
	end

	local money = stats:FindFirstChild("money")
	if money and money:IsA("StringValue") then
		return money.Value
	end

	return "0"
end

function LeaderboardController:_getSortedPlayers(): { Player }
	local entries = {}

	for _, player in ipairs(Players:GetPlayers()) do
		table.insert(entries, {
			player = player,
			name = player.Name,
			rolls = self:_getRollCount(player),
		})
	end

	table.sort(entries, function(a, b)
		if a.rolls ~= b.rolls then
			return a.rolls > b.rolls
		end

		local aName = string.lower(a.name)
		local bName = string.lower(b.name)
		if aName ~= bName then
			return aName < bName
		end

		return a.player.UserId < b.player.UserId
	end)

	local sortedPlayers = {}
	for _, entry in ipairs(entries) do
		table.insert(sortedPlayers, entry.player)
	end

	return sortedPlayers
end

function LeaderboardController:_configureRow(row: Frame, player: Player, order: number)
	row.Name = string.format("Entry_%d", player.UserId)
	row.LayoutOrder = order
	row.Visible = true
	row.Parent = self._scrollingFrame

	local nameLabel = row:FindFirstChild("PlayerName")
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.RichText = true
		nameLabel.Text = getRichDisplayName(player)
	end

	local rollsLabel = row:FindFirstChild("Rolls")
	if rollsLabel and rollsLabel:IsA("TextLabel") then
		rollsLabel.Text = tostring(self:_getRollCount(player))
	end

	local moneyLabel = row:FindFirstChild("Money")
	if moneyLabel and moneyLabel:IsA("TextLabel") then
		moneyLabel.Text = self:_getMoneyText(player)
	end

	local toggle = row:FindFirstChild("Toggle")
	if toggle and toggle:IsA("GuiButton") then
		toggle.Visible = false
		toggle.Active = false
		toggle.AutoButtonColor = false
	end

	local rowButton = Instance.new("TextButton")
	rowButton.Name = "RowButton"
	rowButton.BackgroundTransparency = 1
	rowButton.BorderSizePixel = 0
	rowButton.Text = ""
	rowButton.AutoButtonColor = false
	rowButton.Size = UDim2.fromScale(1, 1)
	rowButton.ZIndex = row.ZIndex + 1
	rowButton.Parent = row

	rowButton.Activated:Connect(function()
		self:_openPlayerInfo(player)
	end)
end

function LeaderboardController:_refreshRows()
	local scrollingFrame = self._scrollingFrame
	local template = self._template
	if not (scrollingFrame and template) then
		return
	end

	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child ~= template and child:IsA("Frame") then
			child:Destroy()
		end
	end

	for index, player in ipairs(self:_getSortedPlayers()) do
		local row = template:Clone()
		self:_configureRow(row, player, index)
	end

	self:_syncSelectedPlayerInfo()
end

function LeaderboardController:_disconnectPlayer(player: Player)
	local connections = self._playerConnections[player]
	if not connections then
		return
	end

	disconnectConnections(connections)
	self._playerConnections[player] = nil
end

function LeaderboardController:_watchRollsValue(rollsValue: IntValue, playerConnections: { RBXScriptConnection })
	table.insert(playerConnections, rollsValue:GetPropertyChangedSignal("Value"):Connect(function()
		self:_scheduleRefresh()
	end))
end

function LeaderboardController:_watchMoneyValue(moneyValue: StringValue, playerConnections: { RBXScriptConnection })
	table.insert(playerConnections, moneyValue:GetPropertyChangedSignal("Value"):Connect(function()
		self:_scheduleRefresh()
	end))
end

function LeaderboardController:_watchLeaderstats(player: Player, playerConnections: { RBXScriptConnection })
	local function bindLeaderstats(stats: Instance)
		if not stats:IsA("Folder") or stats.Name ~= "leaderstats" then
			return
		end

		local rolls = stats:FindFirstChild("Rolls")
		if rolls and rolls:IsA("IntValue") then
			self:_watchRollsValue(rolls, playerConnections)
		end

		local money = stats:FindFirstChild("money")
		if money and money:IsA("StringValue") then
			self:_watchMoneyValue(money, playerConnections)
		end

		table.insert(playerConnections, stats.ChildAdded:Connect(function(child)
			if child.Name == "Rolls" and child:IsA("IntValue") then
				self:_watchRollsValue(child, playerConnections)
				self:_scheduleRefresh()
			elseif child.Name == "money" and child:IsA("StringValue") then
				self:_watchMoneyValue(child, playerConnections)
				self:_scheduleRefresh()
			end
		end))

		self:_scheduleRefresh()
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		bindLeaderstats(leaderstats)
	end

	table.insert(playerConnections, player.ChildAdded:Connect(function(child)
		if child.Name == "leaderstats" then
			bindLeaderstats(child)
		end
	end))
end

function LeaderboardController:_trackPlayer(player: Player)
	self:_disconnectPlayer(player)

	local playerConnections = {}
	self._playerConnections[player] = playerConnections
	self:_watchLeaderstats(player, playerConnections)
	table.insert(playerConnections, player:GetAttributeChangedSignal("VIP"):Connect(function()
		self:_scheduleRefresh()
		if self._selectedPlayer == player then
			self:_syncSelectedPlayerInfo()
		end
	end))
	table.insert(playerConnections, player:GetAttributeChangedSignal("EquippedTitleId"):Connect(function()
		self:_scheduleRefresh()
		if self._selectedPlayer == player then
			self:_syncSelectedPlayerInfo()
		end
	end))
	table.insert(playerConnections, player:GetPropertyChangedSignal("DisplayName"):Connect(function()
		self:_scheduleRefresh()
		if self._selectedPlayer == player then
			self:_syncSelectedPlayerInfo()
		end
	end))
	self:_scheduleRefresh()
end

function LeaderboardController:_getSelectedRollCount(): string
	local selectedPlayer = self._selectedPlayer
	if not selectedPlayer then
		return "0"
	end

	return tostring(self:_getRollCount(selectedPlayer))
end

function LeaderboardController:_setButtonVisible(button: GuiObject?, isVisible: boolean)
	if not button then
		return
	end

	button.Visible = isVisible
	if button:IsA("GuiButton") then
		button.Active = isVisible
		button.AutoButtonColor = isVisible
	end
end

function LeaderboardController:_syncActionButtons()
	local ui = self._ui
	local selectedPlayer = self._selectedPlayer
	if not (ui and selectedPlayer) then
		if ui then
			self:_setButtonVisible(ui.friendButton, false)
			self:_setButtonVisible(ui.blockButton, false)
		end
		return
	end

	local isSelf = selectedPlayer == LOCAL_PLAYER
	self:_setButtonVisible(ui.blockButton, not isSelf)

	if isSelf then
		self:_setButtonVisible(ui.friendButton, false)
		return
	end

	self:_setButtonVisible(ui.friendButton, false)
	task.spawn(function()
		local ok, isFriends = pcall(function()
			return LOCAL_PLAYER:IsFriendsWith(selectedPlayer.UserId)
		end)

		if self._selectedPlayer ~= selectedPlayer then
			return
		end

		self:_setButtonVisible(ui.friendButton, ok and not isFriends)
	end)
end

function LeaderboardController:_loadSelectedThumbnail(player: Player)
	local ui = self._ui
	if not (ui and ui.playerIconImage) then
		return
	end

	self._thumbnailRequestId += 1
	local requestId = self._thumbnailRequestId
	ui.playerIconImage.Visible = true
	ui.playerIconImage.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"

	task.spawn(function()
		local ok, content, isReady = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, THUMBNAIL_TYPE, THUMBNAIL_SIZE)
		end)

		if not ok or self._selectedPlayer ~= player or self._thumbnailRequestId ~= requestId then
			return
		end

		if isReady == false or typeof(content) ~= "string" or content == "" then
			return
		end

		ui.playerIconImage.Image = content
	end)
end

function LeaderboardController:_syncSelectedPlayerInfo()
	local ui = self._ui
	local playerInfo = self._playerInfo
	local selectedPlayer = self._selectedPlayer
	if not (ui and playerInfo) then
		return
	end

	if not selectedPlayer or selectedPlayer.Parent ~= Players then
		playerInfo.Visible = false
		self:_setButtonVisible(ui.friendButton, false)
		self:_setButtonVisible(ui.blockButton, false)
		return
	end

	playerInfo.Visible = true
	ui.displayNameLabel.RichText = true
	ui.displayNameLabel.Text = getRichDisplayName(selectedPlayer)
	ui.usernameLabel.Text = "@" .. selectedPlayer.Name
	ui.rollInfoContext.Text = self:_getSelectedRollCount()
	if ui.titleInfoTitle and ui.titleInfoTitle:IsA("TextLabel") then
		ui.titleInfoTitle.Text = "Title"
	end
	if ui.titleInfoContext and ui.titleInfoContext:IsA("TextLabel") then
		local richPrefix = getRichTitlePrefix(selectedPlayer)
		ui.titleInfoContext.RichText = true
		ui.titleInfoContext.Text = if richPrefix ~= "" then richPrefix else "No title equipped"
	end
	self:_syncActionButtons()
end

function LeaderboardController:_openPlayerInfo(player: Player)
	self._selectedPlayer = player
	self:_syncSelectedPlayerInfo()
	self:_loadSelectedThumbnail(player)
end

function LeaderboardController:_closePlayerInfo()
	self._selectedPlayer = nil
	self._thumbnailRequestId += 1
	self:_syncSelectedPlayerInfo()
end

function LeaderboardController:_promptSendFriendRequest()
	local selectedPlayer = self._selectedPlayer
	if not selectedPlayer or selectedPlayer == LOCAL_PLAYER then
		return
	end

	setCoreWithRetry("PromptSendFriendRequest", selectedPlayer)
end

function LeaderboardController:_promptBlockPlayer()
	local selectedPlayer = self._selectedPlayer
	if not selectedPlayer or selectedPlayer == LOCAL_PLAYER then
		return
	end

	setCoreWithRetry("PromptBlockPlayer", selectedPlayer)
end

function LeaderboardController:_syncCollapseState()
	local leaderboardInner = self._leaderboardInner
	if not leaderboardInner then
		return
	end

	if isCloseToPosition(leaderboardInner.Position, LEADERBOARD_CLOSED_POSITION) then
		self:_closePlayerInfo()
	end
end

function LeaderboardController:_cacheUi(playerGui: PlayerGui)
	local mainInterface = playerGui:WaitForChild("MainInterface", 30)
	if not (mainInterface and mainInterface:IsA("ScreenGui")) then
		error("PlayerGui.MainInterface is missing.")
	end

	local leaderboard = mainInterface:WaitForChild("Leaderboard", 30)
	if not (leaderboard and leaderboard:IsA("Frame")) then
		error("PlayerGui.MainInterface.Leaderboard is missing.")
	end

	local inner = leaderboard:WaitForChild("Inner", 30)
	local scrollingFrame = inner:WaitForChild("ScrollingFrame", 30)
	local template = scrollingFrame:WaitForChild("Template", 30)
	local playerInfo = inner:WaitForChild("PlayerInfo", 30)

	if not (scrollingFrame:IsA("ScrollingFrame") and template:IsA("Frame") and playerInfo:IsA("Frame")) then
		error("Leaderboard UI hierarchy is missing required instances.")
	end

	self._scrollingFrame = scrollingFrame
	self._template = template
	self._playerInfo = playerInfo
	self._leaderboardInner = inner
	self._ui = {
		displayNameLabel = playerInfo:WaitForChild("DisplayName"),
		usernameLabel = playerInfo:WaitForChild("Username"),
		rollInfoContext = playerInfo:WaitForChild("RollInfo"):WaitForChild("Context"),
		titleInfoTitle = playerInfo:WaitForChild("TitleInfo"):WaitForChild("Title"),
		titleInfoContext = playerInfo:WaitForChild("TitleInfo"):WaitForChild("Context"),
		friendButton = playerInfo:WaitForChild("AddFriendButton"),
		blockButton = playerInfo:WaitForChild("BlockButton"),
		closeButton = playerInfo:WaitForChild("CloseButton"),
		playerIconImage = playerInfo:WaitForChild("PlayerIcon"):WaitForChild("Image"),
	}

	self._scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	self._template.Visible = false
	self._playerInfo.Visible = false
	self._ui.playerIconImage.Visible = true
	self:_syncCollapseState()
end

function LeaderboardController:OnStart()
	self:_ensureState()

	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	self:_cacheUi(playerGui)

	self._ui.closeButton.Activated:Connect(function()
		self:_closePlayerInfo()
	end)

	self._ui.friendButton.Activated:Connect(function()
		self:_promptSendFriendRequest()
	end)

	self._ui.blockButton.Activated:Connect(function()
		self:_promptBlockPlayer()
	end)

	if self._leaderboardInner then
		table.insert(self._connections, self._leaderboardInner:GetPropertyChangedSignal("Position"):Connect(function()
			self:_syncCollapseState()
		end))
	end

	for _, player in ipairs(Players:GetPlayers()) do
		self:_trackPlayer(player)
	end

	table.insert(self._connections, Players.PlayerAdded:Connect(function(player)
		self:_trackPlayer(player)
	end))

	table.insert(self._connections, Players.PlayerRemoving:Connect(function(player)
		if self._selectedPlayer == player then
			self:_closePlayerInfo()
		end

		self:_disconnectPlayer(player)
		self:_scheduleRefresh()
	end))

	self:_scheduleRefresh()
end

return LeaderboardController
