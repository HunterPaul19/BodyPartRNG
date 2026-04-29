local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader = require(ReplicatedStorage.Loader)
local EmitModule = require(ReplicatedStorage.Shared.Effects.EmitModule)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)
local Notify = require(ReplicatedStorage.Shared.UI.Notify)
local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)

local StarterPlayerScripts = script.Parent
local playClientSoundConnection: RBXScriptConnection? = nil
local STARTUP_WATCHDOG_SECONDS = 3

local CLIENT_STARTUP_PHASE_DEFINITIONS = {
	{
		label = "Phase1.CoreUI",
		names = {
			"UIController",
			"FrameController",
			"HUDWindowController",
			"MainInterfaceController",
			"BackgroundMusicController",
			"CombatPhysicsController",
			"BossHealthBarController",
			"BossArenaResultsController",
			"CombatHUDController",
			"DashController",
			"PvpController",
			"BossHitFlashController",
			"CombatAudioController",
			"BossArenaTimerController",
			"BossArenaAbandonController",
			"BossArenaM1Controller",
			"BossArenaMovePresentationController",
			"BossLobbyRewardPreviewController",
			"BossArenaStudioTestSuiteController",
			"BossArenaStudioPickerController",
			"ChatNotificationController",
		},
	},
	{
		label = "Phase2.HUDPanels",
		names = {
			"RollController",
			"DialogueController",
			"LeaderboardController",
		},
	},
	{
		label = "Phase3.HUDModal",
		names = {
			"HelpController",
			"StoreController",
			"MerchantTeleportController",
			"TitleController",
			"IndexController",
			"InventoryController",
		},
	},
	{
		label = "Phase4.Features",
		names = {
			"DataController",
			"MoneyHUDController",
			"TimeShardsHUDController",
			"PotionController",
			"FootstepController",
			"MarketplaceController",
			"MerchantShopController",
			"MerchantPresentationController",
			"CraftingController",
			"PlayerInspectController",
			"ProximityPromptReachController",
			"AppraisalController",
		},
	},
}

local function shouldLoadController(moduleScript: ModuleScript): boolean
	if not moduleScript.Name:match("Controller$") then
		return false
	end

	return PlaceProfile.ShouldLoadController(moduleScript.Name)
end

local function bindPlayClientSoundRemote()
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotesFolder then
		return
	end

	local remote = remotesFolder:WaitForChild("PlayClientSound", 10)
	if not (remote and remote:IsA("RemoteEvent")) then
		return
	end

	if playClientSoundConnection then
		playClientSoundConnection:Disconnect()
	end

	playClientSoundConnection = remote.OnClientEvent:Connect(function(soundName: string)
		SoundUtil.Play(soundName)
	end)
end

local function buildStartupPhases(loadedModules, source: string)
	local activeProfile = PlaceProfile.GetActiveProfile()
	local loadedNameSet = {}
	local assignedNameSet = {}

	for _, loadedModule in ipairs(loadedModules) do
		loadedNameSet[loadedModule.name] = true
	end

	local phaseGroups = {}
	local phaseSummaryParts = {}

	for phaseIndex, phaseDefinition in ipairs(CLIENT_STARTUP_PHASE_DEFINITIONS) do
		local phaseNames = {}
		for _, name in ipairs(phaseDefinition.names) do
			if loadedNameSet[name] == true and assignedNameSet[name] ~= true then
				table.insert(phaseNames, name)
				assignedNameSet[name] = true
			end
		end

		if phaseIndex == #CLIENT_STARTUP_PHASE_DEFINITIONS then
			local remainingNames = {}
			for _, loadedModule in ipairs(loadedModules) do
				if assignedNameSet[loadedModule.name] ~= true then
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
				runtime = "Client",
				source = source,
				logLifecycle = true,
				watchdogSeconds = STARTUP_WATCHDOG_SECONDS,
			},
		})
		table.insert(phaseSummaryParts, string.format("%s=[%s]", phaseDefinition.label, table.concat(phaseNames, ", ")))
	end

	Logger.Print(string.format(
		"[ClientBootstrap] Profile='%s' PlaceId=%d %s",
		activeProfile.id,
		math.max(0, math.floor(tonumber(game.PlaceId) or 0)),
		table.concat(phaseSummaryParts, " ")
	))

	return phaseGroups
end

local loaderContext = {
	phase = "Startup",
	runtime = "Client",
	source = script:GetFullName(),
}

EmitModule.init()

local loadedModules = Loader.LoadDescendants(StarterPlayerScripts.Controllers, shouldLoadController, loaderContext)
local startupPhases = buildStartupPhases(loadedModules, script:GetFullName())

Loader.RunOrderedReporting(loadedModules, "OnStart", startupPhases, loaderContext)
task.spawn(bindPlayClientSoundRemote)

return Notify
