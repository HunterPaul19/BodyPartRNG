local RollingConfig = require(script.Parent.RollingConfig)

local ChatNotificationConfig = {
	RemotesFolderName = "Remotes",
	FolderName = "ChatNotifications",
	RareRollRemoteName = "RareRoll",
	MinimumRareRollRarity = "Prime",
	MinimumGlobalRollRarity = "Apex",
	GlobalRollTopicName = "BodyPartRNG.ApexRoll.v1",
	RareRollKind = "rareRoll",
	RarityColors = {
		Prime = Color3.fromRGB(255, 179, 0),
		Elite = Color3.fromRGB(247, 0, 255),
		Apex = Color3.fromRGB(255, 0, 0),
	},
}

local RARITY_RANKS = {}
for rank, rarity in ipairs(RollingConfig.DisplayRarityOrder) do
	RARITY_RANKS[rarity] = rank
end

local MINIMUM_RANK = RARITY_RANKS[ChatNotificationConfig.MinimumRareRollRarity] or math.huge
local GLOBAL_MINIMUM_RANK = RARITY_RANKS[ChatNotificationConfig.MinimumGlobalRollRarity] or math.huge

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

function ChatNotificationConfig.IsGlobalRollRarity(value: any): boolean
	return ChatNotificationConfig.GetRarityRank(value) >= GLOBAL_MINIMUM_RANK
end

function ChatNotificationConfig.GetRarityColor(value: any): Color3
	local displayRarity = ChatNotificationConfig.NormalizeDisplayRarity(value)
	return ChatNotificationConfig.RarityColors[displayRarity] or Color3.fromRGB(255, 255, 255)
end

return table.freeze(ChatNotificationConfig)
