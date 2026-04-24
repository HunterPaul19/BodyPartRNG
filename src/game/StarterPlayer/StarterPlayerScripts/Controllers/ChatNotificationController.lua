local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local ChatNotificationConfig = require(ReplicatedStorage.Shared.Config.ChatNotificationConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local SizeConfig = require(ReplicatedStorage.Shared.Config.SizeConfig)

local ChatNotificationController = {}

local function escapeRichText(text: any): string
	local escaped = tostring(text or "")
	escaped = string.gsub(escaped, "&", "&amp;")
	escaped = string.gsub(escaped, "<", "&lt;")
	escaped = string.gsub(escaped, ">", "&gt;")
	escaped = string.gsub(escaped, '"', "&quot;")
	escaped = string.gsub(escaped, "'", "&apos;")
	return escaped
end

local function toRichTextColor(color: Color3): string
	return string.format(
		"rgb(%d,%d,%d)",
		math.round(color.R * 255),
		math.round(color.G * 255),
		math.round(color.B * 255)
	)
end

local function formatIntegerWithCommas(value: any): string
	local integerText = tostring(math.max(1, math.floor(tonumber(value) or 1)))
	local sign = ""
	if string.sub(integerText, 1, 1) == "-" then
		sign = "-"
		integerText = string.sub(integerText, 2)
	end

	local reversed = string.reverse(integerText)
	local grouped = string.reverse((string.gsub(reversed, "(%d%d%d)", "%1,")))
	if string.sub(grouped, 1, 1) == "," then
		grouped = string.sub(grouped, 2)
	end

	return sign .. grouped
end

local function getTextChannel(): TextChannel?
	local textChannels = TextChatService:FindFirstChild("TextChannels")
	if not textChannels then
		return nil
	end

	local generalChannel = textChannels:FindFirstChild("RBXGeneral")
	if generalChannel and generalChannel:IsA("TextChannel") then
		return generalChannel
	end

	for _, child in ipairs(textChannels:GetChildren()) do
		if child:IsA("TextChannel") then
			return child
		end
	end

	return nil
end

local function getRareRollRemote(): RemoteEvent?
	local remotesFolder = ReplicatedStorage:WaitForChild(ChatNotificationConfig.RemotesFolderName, 10)
	if not remotesFolder then
		return nil
	end

	local chatNotificationsFolder = remotesFolder:WaitForChild(ChatNotificationConfig.FolderName, 10)
	if not chatNotificationsFolder then
		return nil
	end

	local remote = chatNotificationsFolder:WaitForChild(ChatNotificationConfig.RareRollRemoteName, 10)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end

	return nil
end

local function buildItemText(payload: any): string
	local parts = {}
	local mutationId = payload.mutationId
	local sizeId = payload.sizeId

	if typeof(mutationId) == "string" and MutationConfig.NormalizeId(mutationId) ~= MutationConfig.GetDefault().id then
		table.insert(parts, escapeRichText(payload.mutationDisplayName or MutationConfig.GetDisplayName(mutationId)))
	end

	if typeof(sizeId) == "string" and SizeConfig.NormalizeId(sizeId) ~= SizeConfig.GetDefault().id then
		table.insert(parts, escapeRichText(payload.sizeDisplayName or SizeConfig.GetDisplayName(sizeId)))
	end

	table.insert(parts, escapeRichText(payload.setDisplayName or "Unknown"))
	table.insert(parts, escapeRichText(payload.pieceDisplayName or "Body Part"))

	return table.concat(parts, " ")
end

local function buildRareRollMessage(payload: any): string?
	if typeof(payload) ~= "table" or payload.kind ~= ChatNotificationConfig.RareRollKind then
		return nil
	end

	local displayRarity = ChatNotificationConfig.NormalizeDisplayRarity(payload.displayRarity)
	if not ChatNotificationConfig.IsRareRollRarity(displayRarity) then
		return nil
	end

	local rarityColor = ChatNotificationConfig.GetRarityColor(displayRarity)
	local rarityColorText = toRichTextColor(rarityColor)
	local rarityPrefix = string.upper(displayRarity)
	local messageText = string.format(
		"[%s] %s rolled %s (1/%s)",
		escapeRichText(rarityPrefix),
		escapeRichText(payload.playerName or "Someone"),
		buildItemText(payload),
		formatIntegerWithCommas(payload.displayOddsDenominator)
	)

	return string.format(
		'<font color="%s"><b>%s</b></font>',
		rarityColorText,
		messageText
	)
end

function ChatNotificationController:OnStart()
	task.spawn(function()
		local remote = getRareRollRemote()
		if not remote then
			warn("[ChatNotificationController] Rare roll remote was not available.")
			return
		end

		remote.OnClientEvent:Connect(function(payload)
			local message = buildRareRollMessage(payload)
			if not message then
				return
			end

			local channel = getTextChannel()
			if not channel then
				warn("[ChatNotificationController] No TextChannel is available for rare roll notification.")
				return
			end

			channel:DisplaySystemMessage(message)
		end)
	end)
end

return ChatNotificationController
