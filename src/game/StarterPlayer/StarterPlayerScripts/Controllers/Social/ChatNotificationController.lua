local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local ChatNotificationConfig = require(ReplicatedStorage.Shared.Config.ChatNotificationConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local SizeConfig = require(ReplicatedStorage.Shared.Config.SizeConfig)
local BodyPartPresentation = require(ReplicatedStorage.Shared.UI.BodyPartPresentation)

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

local function getRarityTextColor(displayRarity: string): Color3
	local fallbackColor = ChatNotificationConfig.GetRarityColor(displayRarity)
	local rarityStyle = BodyPartPresentation.ResolveSetRarityStyle({
		rollDisplay = {
			color = fallbackColor,
		},
	}, displayRarity, fallbackColor)

	if typeof(rarityStyle) == "table" and typeof(rarityStyle.textColor) == "Color3" then
		return rarityStyle.textColor
	end

	return fallbackColor
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

local function pieceDisplayNameIncludesSetName(setDisplayName: string, pieceDisplayName: string): boolean
	if setDisplayName == "" then
		return false
	end

	if string.sub(pieceDisplayName, 1, #setDisplayName) ~= setDisplayName then
		return false
	end

	local nextCharacter = string.sub(pieceDisplayName, #setDisplayName + 1, #setDisplayName + 1)
	return nextCharacter == "" or string.match(nextCharacter, "%s") ~= nil
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

	local setDisplayName = tostring(payload.setDisplayName or "Unknown")
	local pieceDisplayName = tostring(payload.pieceDisplayName or "Body Part")
	if not pieceDisplayNameIncludesSetName(setDisplayName, pieceDisplayName) then
		table.insert(parts, escapeRichText(setDisplayName))
	end
	table.insert(parts, escapeRichText(pieceDisplayName))

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

	local rarityColor = getRarityTextColor(displayRarity)
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
			Logger.Warn("[ChatNotificationController] Rare roll remote was not available.")
			return
		end

		remote.OnClientEvent:Connect(function(payload)
			local message = buildRareRollMessage(payload)
			if not message then
				return
			end

			local channel = getTextChannel()
			if not channel then
				Logger.Warn("[ChatNotificationController] No TextChannel is available for rare roll notification.")
				return
			end

			channel:DisplaySystemMessage(message)
		end)
	end)
end

return ChatNotificationController
