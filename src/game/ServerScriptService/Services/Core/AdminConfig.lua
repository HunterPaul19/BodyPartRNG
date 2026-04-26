local AdminConfig = {
	AuthorizedUserIds = {
		-- Add live admin Roblox UserIds here, for example:
		-- 123456789,
	},
	LiveDestructiveUserIds = {
		-- Add live destructive-action Roblox UserIds here.
	},
	AllowAllPlayersInStudio = true,
	AllowLiveDestructiveActions = false,
}

AdminConfig.AllowedUserIds = AdminConfig.AuthorizedUserIds

return AdminConfig
