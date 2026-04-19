local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Loader = require(ReplicatedStorage.Loader)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local function shouldLoadService(moduleScript: ModuleScript): boolean
	if not moduleScript.Name:match("Service$") then
		return false
	end

	return PlaceProfile.ShouldLoadService(moduleScript.Name)
end

local loaderContext = {
	phase = "Startup",
	runtime = "Server",
	source = script:GetFullName(),
}

local eventContext = {
	phase = "RuntimeEvent",
	runtime = "Server",
	source = script:GetFullName(),
}

local loadedModules = Loader.LoadDescendants(ServerScriptService.Services, shouldLoadService, loaderContext)

Loader.RunAllFatal(loadedModules, "OnStart", loaderContext)
Loader.ConnectFunctionsReporting(loadedModules, Players.PlayerAdded, "OnPlayerAdded", eventContext)
Loader.ConnectFunctionsReporting(loadedModules, Players.PlayerRemoving, "OnPlayerRemoving", eventContext)

for _, player in Players:GetPlayers() do
	Loader.RunAllFatal(loadedModules, "OnPlayerAdded", loaderContext, player)
end
