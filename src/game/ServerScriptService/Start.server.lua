local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Loader = require(ReplicatedStorage.Loader)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local STARTUP_WATCHDOG_SECONDS = 3
local PLAYER_LIFECYCLE_WATCHDOG_SECONDS = 15

local SERVER_STARTUP_PHASE_DEFINITIONS = {
	{
		label = "Phase1.CoreData",
		names = {
			"DataService",
			"StatsService",
			"AudioSettingsService",
			"BodyPartService",
			"PotionService",
			"PassiveIncomeService",
			"DailyChestService",
			"TutorialAnalyticsService",
			"TutorialService",
			"PurchaseReceiptService",
			"QuestService",
			"ChatNotificationService",
		},
	},
	{
		label = "Phase2.Combat",
		names = {
			"PlayerLoadoutStatsService",
			"DashService",
			"PvpService",
		},
	},
	{
		label = "Phase3.Rolling",
		names = {
			"RollService",
		},
	},
	{
		label = "Phase4.Remaining",
		names = {},
	},
}

local PLAYER_ADDED_PHASE_DEFINITIONS = {
	{
		label = "PlayerAdded.Data",
		names = {
			"DataService",
		},
	},
	{
		label = "PlayerAdded.DataDependents",
		names = {
			"StatsService",
			"BodyPartService",
			"PotionService",
			"PurchaseReceiptService",
			"PlayerLoadoutStatsService",
			"PassiveIncomeService",
			"DailyChestService",
			"TutorialService",
		},
	},
	{
		label = "PlayerAdded.Remaining",
		names = {},
	},
}

local PLAYER_REMOVING_PHASE_DEFINITIONS = {
	{
		label = "PlayerRemoving.Services",
		names = {},
	},
	{
		label = "PlayerRemoving.Data",
		names = {
			"DataService",
		},
	},
}

local function shouldLoadService(moduleScript: ModuleScript): boolean
	if not moduleScript.Name:match("Service$") then
		return false
	end

	return PlaceProfile.ShouldLoadService(moduleScript.Name)
end

local function buildOrderedGroups(
	loadedModules,
	phaseDefinitions,
	source: string,
	runtime: string,
	logLifecycle: boolean,
	watchdogSeconds: number?,
	remainingPhaseIndex: number
)
	local loadedNameSet = {}
	local assignedNameSet = {}
	local reservedNameSet = {}

	for _, loadedModule in ipairs(loadedModules) do
		loadedNameSet[loadedModule.name] = true
	end
	for _, phaseDefinition in ipairs(phaseDefinitions) do
		for _, name in ipairs(phaseDefinition.names) do
			reservedNameSet[name] = true
		end
	end

	local phaseGroups = {}
	local phaseSummaryParts = {}

	for phaseIndex, phaseDefinition in ipairs(phaseDefinitions) do
		local phaseNames = {}
		for _, name in ipairs(phaseDefinition.names) do
			if loadedNameSet[name] == true and assignedNameSet[name] ~= true then
				table.insert(phaseNames, name)
				assignedNameSet[name] = true
			end
		end

		if phaseIndex == remainingPhaseIndex then
			local remainingNames = {}
			for _, loadedModule in ipairs(loadedModules) do
				if assignedNameSet[loadedModule.name] ~= true and reservedNameSet[loadedModule.name] ~= true then
					assignedNameSet[loadedModule.name] = true
					table.insert(remainingNames, loadedModule.name)
				end
			end
			table.sort(remainingNames)
			for _, name in ipairs(remainingNames) do
				table.insert(phaseNames, name)
			end
		end

		table.insert(phaseGroups, {
			names = phaseNames,
			context = {
				phase = phaseDefinition.label,
				runtime = runtime,
				source = source,
				logLifecycle = logLifecycle,
				watchdogSeconds = watchdogSeconds,
			},
		})
		table.insert(phaseSummaryParts, string.format("%s=[%s]", phaseDefinition.label, table.concat(phaseNames, ", ")))
	end

	return phaseGroups, phaseSummaryParts
end

local function buildStartupPhases(loadedModules, source: string)
	local activeProfile = PlaceProfile.GetActiveProfile()
	local phaseGroups, phaseSummaryParts = buildOrderedGroups(
		loadedModules,
		SERVER_STARTUP_PHASE_DEFINITIONS,
		source,
		"Server",
		true,
		STARTUP_WATCHDOG_SECONDS,
		#SERVER_STARTUP_PHASE_DEFINITIONS
	)

	Logger.Print(string.format(
		"[ServerBootstrap] Profile='%s' PlaceId=%d %s",
		activeProfile.id,
		math.max(0, math.floor(tonumber(game.PlaceId) or 0)),
		table.concat(phaseSummaryParts, " ")
	))

	return phaseGroups
end

local function buildPlayerLifecycleGroups(loadedModules, methodName: string)
	if methodName == "OnPlayerAdded" then
		return buildOrderedGroups(
			loadedModules,
			PLAYER_ADDED_PHASE_DEFINITIONS,
			script:GetFullName(),
			"Server",
			false,
			PLAYER_LIFECYCLE_WATCHDOG_SECONDS,
			#PLAYER_ADDED_PHASE_DEFINITIONS
		)
	end

	return buildOrderedGroups(
		loadedModules,
		PLAYER_REMOVING_PHASE_DEFINITIONS,
		script:GetFullName(),
		"Server",
		false,
		PLAYER_LIFECYCLE_WATCHDOG_SECONDS,
		1
	)
end

local function runPlayerLifecycle(loadedModules, methodName: string, player: Player)
	local groups = buildPlayerLifecycleGroups(loadedModules, methodName)
	local ok, err = xpcall(function()
		Loader.RunOrderedFatal(loadedModules, methodName, groups, {
			phase = methodName,
			runtime = "Server",
			source = script:GetFullName(),
			logLifecycle = false,
			watchdogSeconds = PLAYER_LIFECYCLE_WATCHDOG_SECONDS,
		}, player)
	end, debug.traceback)

	if not ok then
		Logger.Warn(string.format("[ServerBootstrap] %s failed for %s: %s", methodName, player:GetFullName(), tostring(err)))
	end
end

local loaderContext = {
	phase = "Startup",
	runtime = "Server",
	source = script:GetFullName(),
}

local loadedModules = Loader.LoadDescendants(ServerScriptService.Services, shouldLoadService, loaderContext)
local startupPhases = buildStartupPhases(loadedModules, script:GetFullName())

Loader.RunOrderedFatal(loadedModules, "OnStart", startupPhases, loaderContext)
Players.PlayerAdded:Connect(function(player: Player)
	task.spawn(runPlayerLifecycle, loadedModules, "OnPlayerAdded", player)
end)
Players.PlayerRemoving:Connect(function(player: Player)
	runPlayerLifecycle(loadedModules, "OnPlayerRemoving", player)
end)

for _, player in Players:GetPlayers() do
	task.spawn(runPlayerLifecycle, loadedModules, "OnPlayerAdded", player)
end
