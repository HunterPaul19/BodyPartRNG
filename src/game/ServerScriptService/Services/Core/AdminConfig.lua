local AdminConfig = {
	AuthorizedUserIds = {
		-- Add live admin Roblox UserIds here, for example:
		-- 123456789,
		86822302,
		60054825,
		7265277081,
	},
	LiveDestructiveUserIds = {
		-- Add live destructive-action Roblox UserIds here.
		86822302,
		60054825,
		7265277081,
	},
	AllowAllPlayersInStudio = true,
	AllowLiveDestructiveActions = false,
}

AdminConfig.AllowedUserIds = AdminConfig.AuthorizedUserIds

return AdminConfig
