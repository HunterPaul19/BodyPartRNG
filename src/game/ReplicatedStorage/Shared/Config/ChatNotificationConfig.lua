local RollingConfig = require(script.Parent.RollingConfig)

local ChatNotificationConfig = {
	RemotesFolderName = "Remotes",
	FolderName = "ChatNotifications",
	RareRollRemoteName = "RareRoll",
	MinimumRareRollRarity = "Prime",
	RareRollKind = "rareRoll",
	RarityColors = {
		Prime = Color3.fromRGB(96, 165, 250),
		Elite = Color3.fromRGB(236, 72, 153),
		Apex = Color3.fromRGB(245, 158, 11),
	},
}

local RARITY_RANKS = {}
for rank, rarity in ipairs(RollingConfig.DisplayRarityOrder) do
	RARITY_RANKS[rarity] = rank
end

local MINIMUM_RANK = RARITY_RANKS[ChatNotificationConfig.MinimumRareRollRarity] or math.huge

function ChatNotificationConfig.NormalizeDisplayRarity(value: any): string
	return RollingConfig.NormalizeDisplayRarity(value)
end

function ChatNotificationConfig.GetRarityRank(value: any): number
	local displayRarity = ChatNotificationConfig.NormalizeDisplayRarity(value)
	return RARITY_RANKS[displayRarity] or 0
end

function ChatNotificationConfig.IsRareRollRarity(value: any): boolean
	return ChatNotificationConfig.GetRarityRank(value) >= MINIMUM_RANK
end

function ChatNotificationConfig.GetRarityColor(value: any): Color3
	local displayRarity = ChatNotificationConfig.NormalizeDisplayRarity(value)
	return ChatNotificationConfig.RarityColors[displayRarity] or Color3.fromRGB(255, 255, 255)
end

return table.freeze(ChatNotificationConfig)
