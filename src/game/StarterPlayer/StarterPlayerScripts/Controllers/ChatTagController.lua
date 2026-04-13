local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TitleUtil = require(ReplicatedStorage.Shared.Titles.TitleUtil)

local ChatTagController = {}

function ChatTagController:OnStart()
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local textSource = message.TextSource
		if not textSource then
			return nil
		end

		local player = Players:GetPlayerByUserId(textSource.UserId)
		if player then
			local richPrefix = TitleUtil.BuildRichTextPrefix(
				player:GetAttribute("VIP") == true,
				player:GetAttribute("EquippedTitleId")
			)
			if richPrefix ~= "" then
				local overrideProperties = Instance.new("TextChatMessageProperties")
				overrideProperties.PrefixText = richPrefix .. " " .. message.PrefixText
				return overrideProperties
			end
		end

		return nil
	end
end

return ChatTagController
