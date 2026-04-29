local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssetPaths = require(ReplicatedStorage.Shared.Assets.GameAssetPaths)
local GameAssetResolver = require(ReplicatedStorage.Shared.Assets.GameAssetResolver)
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AdminActionRegistry = require(ReplicatedStorage.Shared.Admin.AdminActionRegistry)
local AdminConfig = require(script.Parent.AdminConfig)
local AuraService = require(script.Parent.AuraService)
local BodyPartService = require(script.Parent.BodyPartService)
local DataService = require(script.Parent.DataService)
local AchievementConfig = require(ReplicatedStorage.Shared.Config.AchievementConfig)
local AchievementState = require(ReplicatedStorage.Shared.Titles.AchievementState)
local BodyPartRegions = require(ReplicatedStorage.Shared.Character.BodyPartRegions)
local BodyPartLoadout = require(ReplicatedStorage.Shared.Character.BodyPartLoadout)
local BodyPartVisuals = require(ReplicatedStorage.Shared.Character.BodyPartVisuals)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local CraftingMaterialConfig = require(ReplicatedStorage.Shared.Config.CraftingMaterialConfig)
local MerchantShopConfig = require(ReplicatedStorage.Shared.Config.MerchantShopConfig)
local MerchantShopService = require(script.Parent.MerchantShopService)
local Notify = require(ReplicatedStorage.Shared.UI.Notify)
local PotionConfig = require(ReplicatedStorage.Shared.Config.PotionConfig)
local PotionService = require(script.Parent.PotionService)
local PurchaseReceiptService = require(script.Parent.PurchaseReceiptService)
local RequestLimiter = require(script.Parent.Common.RequestLimiter)
local RollService = require(script.Parent.RollService)
local RollTypes = require(ReplicatedStorage.Shared.Config.RollTypes)
local RollTargetRegions = require(ReplicatedStorage.Shared.Character.RollTargetRegions)
local Schema = require(ReplicatedStorage.Lists.Schema)
local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)
local AccessoryConfig = require(ReplicatedStorage.Shared.Config.AccessoryConfig)
local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
local TutorialService = require(script.Parent.TutorialService)

local REMOTES_FOLDER_NAME = "Remotes"
local ADMIN_ACTION_REMOTE_NAME = "AdminAction"
local ACCESS_ATTRIBUTE = "CanUseAdminPanel"
local OVERVIEW_TAB_ID = "overview"
local BODY_PARTS_TAB_ID = "bodyParts"
local ROLL_SOURCES_TAB_ID = "cases"
local PLAYERS_TAB_ID = "players"
local PROGRESSION_TAB_ID = "progression"
local DIAGNOSTICS_TAB_ID = "diagnostics"
local MONEY_KEY = Schema.Money and Schema.Money.key or "money"
local TIME_PLAYED_KEY = Schema.TimePlayed and Schema.TimePlayed.key or "timePlayed"
local ACHIEVEMENTS_KEY = Schema.Achievements and Schema.Achievements.key or "achievements"
local MIN_SANDBOX_SCALE = 0.4
local MAX_SANDBOX_SCALE = 2.5
local MIN_NOTIFICATION_DURATION = 1
local MAX_NOTIFICATION_DURATION = 10
local MAX_NOTIFICATION_TEXT_LENGTH = 240
local TEST_PYRAMID_DISTANCE = 40
local TEST_PYRAMID_WIDTH = 24
local TEST_PYRAMID_LAYERS = 8
local TEST_PYRAMID_DURATION_SECONDS = 5
local MAX_CHEST_PREVIEW_REWARD_COUNT = 10

local remotesFolder: Folder? = nil
local adminActionRemote: RemoteFunction? = nil
local sandboxStateByPlayer: { [Player]: { [string]: { bundleName: string, scale: number } } } = {}
local characterAddedConnections: { [Player]: RBXScriptConnection } = {}
local recentEvents = {}
local MAX_RECENT_EVENTS = 40
local MAX_SIMULATION_COUNT = 10000
local VALID_CHEST_IDS = table.freeze({
	Basic = true,
	VIP = true,
	["VIP+"] = true,
	BossTier1 = true,
	BossTier2 = true,
	BossTier3 = true,
})
local ADMIN_CHEST_ACTION_IDS = table.freeze({
	trigger_daily_free_chest = "DailyFree",
	trigger_vip_chest = "VIP",
	trigger_vip_plus_chest = "VIPPlus",
})

local AdminService = {}

local function response(ok: boolean, code: string, message: string, data: any?)
	return {
		ok = ok,
		code = code,
		message = message,
		data = data or {},
	}
end

local function resolveDailyChestService(): (any?, string?)
	local serviceModule = script.Parent:FindFirstChild("DailyChestService")
	if not (serviceModule and serviceModule:IsA("ModuleScript")) then
		return nil, "DailyChestService is not synced yet. Rojo sync and restart Play Solo."
	end

	local ok, service = pcall(require, serviceModule)
	if not ok then
		Logger.Warn(string.format("[AdminService] DailyChestService require failed: %s", tostring(service)))
		return nil, "DailyChestService failed to load. Check the server output."
	end
	if typeof(service) ~= "table" or typeof(service.GrantChestPackageForAdmin) ~= "function" then
		return nil, "DailyChestService does not expose GrantChestPackageForAdmin."
	end

	return service, nil
end

local function trimText(value: any): string
	if typeof(value) ~= "string" then
		return ""
	end

	local normalized = string.gsub(value, "\r\n", "\n")
	normalized = string.gsub(normalized, "\r", "\n")
	return string.match(normalized, "^%s*(.-)%s*$") or ""
end

local function pushRecentEvent(kind: string, message: string, data: any?)
	table.insert(recentEvents, 1, {
		atUnix = os.time(),
		kind = kind,
		message = message,
		data = data,
	})

	while #recentEvents > MAX_RECENT_EVENTS do
		table.remove(recentEvents)
	end
end

local function toWholeNumber(value: any, defaultValue: number?): number
	local numericValue = tonumber(value)
	if numericValue == nil or numericValue ~= numericValue then
		return math.floor(defaultValue or 0)
	end
	return math.floor(numericValue)
end

local function hasUserId(list: { any }?, userId: number): boolean
	if typeof(list) ~= "table" then
		return false
	end

	for _, allowedUserId in ipairs(list) do
		if tonumber(allowedUserId) == userId then
			return true
		end
	end

	return false
end

local function isDestructiveUserId(userId: number): boolean
	if RunService:IsStudio() and AdminConfig.AllowAllPlayersInStudio then
		return true
	end

	return AdminConfig.AllowLiveDestructiveActions == true
		and hasUserId(AdminConfig.LiveDestructiveUserIds, userId)
end

local function validateActionRequest(player: Player, tabId: string, actionId: string, payload: any): (boolean, string?, any?)
	local action = AdminActionRegistry.GetAction(tabId, actionId)
	if not action then
		return true, nil, nil
	end

	if action.environment == AdminActionRegistry.Environment.StudioOnly and not RunService:IsStudio() then
		return false, "This admin action is Studio-only.", action
	end

	if action.risk == AdminActionRegistry.Risk.Destructive and not isDestructiveUserId(player.UserId) then
		return false, "This destructive admin action is not enabled for your user in this environment.", action
	end

	if action.requiresConfirmation == true then
		local confirmation = trimText(payload and payload.confirmation)
		if confirmation ~= tostring(action.confirmationText or "") then
			return false, string.format("Type %s in the confirmation field before running this action.", tostring(action.confirmationText or "")), action
		end
	end

	return true, nil, action
end

local function getPayloadTargetPlayer(payload: any, fallbackPlayer: Player?): (Player?, string?)
	local targetUserId = toWholeNumber(payload and payload.userId, fallbackPlayer and fallbackPlayer.UserId or 0)
	if targetUserId <= 0 then
		return nil, "A valid target userId is required."
	end

	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if not targetPlayer then
		return nil, "That player is no longer in this server."
	end

	return targetPlayer, nil
end

local function getCharacterRoot(player: Player): BasePart?
	local character = player.Character
	if not (character and character:IsA("Model")) then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.RootPart then
		return humanoid.RootPart
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	return if character.PrimaryPart and character.PrimaryPart:IsA("BasePart") then character.PrimaryPart else nil
end

local function safeJsonEncode(value: any): string
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(value)
	end)
	if ok then
		return encoded
	end
	return "{}"
end

local function ensureRemotesFolder(): Folder
	if remotesFolder and remotesFolder.Parent == ReplicatedStorage then
		return remotesFolder
	end

	local existing = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		remotesFolder = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = REMOTES_FOLDER_NAME
	folder.Parent = ReplicatedStorage
	remotesFolder = folder
	return folder
end

local function ensureAdminActionRemote(): RemoteFunction
	local folder = ensureRemotesFolder()

	if adminActionRemote and adminActionRemote.Parent == folder then
		return adminActionRemote
	end

	local existing = folder:FindFirstChild(ADMIN_ACTION_REMOTE_NAME)
	if existing and existing:IsA("RemoteFunction") then
		adminActionRemote = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = ADMIN_ACTION_REMOTE_NAME
	remote.Parent = folder
	adminActionRemote = remote
	return remote
end

local function isAllowedUserId(userId: number): boolean
	if RunService:IsStudio() and AdminConfig.AllowAllPlayersInStudio then
		return true
	end

	for _, authorizedUserId in ipairs(AdminConfig.AuthorizedUserIds or AdminConfig.AllowedUserIds or {}) do
		if tonumber(authorizedUserId) == userId then
			return true
		end
	end

	return false
end

local function getBodyPartsFolder(): Folder?
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	if not (gameAssets and gameAssets:IsA("Folder")) then
		return nil
	end

	local bodyParts = GameAssetResolver.FindFirst({ GameAssetPaths.Models.BodyParts, GameAssetPaths.Legacy.BodyParts })
	if bodyParts and bodyParts:IsA("Folder") then
		return bodyParts
	end

	return nil
end

local function getDefaultBaseRig(): Model?
	local bodyParts = getBodyPartsFolder()
	if not bodyParts then
		return nil
	end

	local baseRigs = bodyParts:FindFirstChild("BaseRigs")
	if not (baseRigs and baseRigs:IsA("Folder")) then
		return nil
	end

	local defaultR15 = baseRigs:FindFirstChild("DefaultR15")
	if defaultR15 and defaultR15:IsA("Model") then
		return defaultR15
	end

	return nil
end

local function getRegionBundlesFolder(region: string): Folder?
	local bodyParts = getBodyPartsFolder()
	if not bodyParts then
		return nil
	end

	local bundles = bodyParts:FindFirstChild("Bundles")
	if not (bundles and bundles:IsA("Folder")) then
		return nil
	end

	local regionFolder = bundles:FindFirstChild(region)
	if not (regionFolder and regionFolder:IsA("Folder")) then
		return nil
	end

	return regionFolder
end

local function parseBundleOptionKey(optionKey: string): (string, string)
	local slashIndex = string.find(optionKey, "/", 1, true)
	if slashIndex then
		local assetGroup = string.sub(optionKey, 1, slashIndex - 1)
		local assetModel = string.sub(optionKey, slashIndex + 1)
		if assetGroup ~= "" and assetModel ~= "" then
			return assetGroup, assetModel
		end
	end

	return "Examples", optionKey
end

local function getBundleModel(region: string, optionKey: string): Model?
	local bundlesFolder = getRegionBundlesFolder(region)
	if not bundlesFolder then
		return nil
	end

	local assetGroup, assetModel = parseBundleOptionKey(optionKey)
	local groupFolder = bundlesFolder:FindFirstChild(assetGroup)
	if not (groupFolder and groupFolder:IsA("Folder")) then
		return nil
	end

	local bundle = groupFolder:FindFirstChild(assetModel)
	if bundle and bundle:IsA("Model") then
		return bundle
	end

	return nil
end

local function getRegionBundleNames(region: string): { string }
	local names = {}
	local bundlesFolder = getRegionBundlesFolder(region)
	if not bundlesFolder then
		return names
	end

	for _, groupFolder in ipairs(bundlesFolder:GetChildren()) do
		if groupFolder:IsA("Folder") then
			for _, child in ipairs(groupFolder:GetChildren()) do
				if child:IsA("Model") then
					table.insert(names, string.format("%s/%s", groupFolder.Name, child.Name))
				end
			end
		end
	end

	table.sort(names)
	return names
end

local function getSandboxOptions()
	local regions = {}
	for _, region in ipairs(BodyPartRegions.Order) do
		regions[region] = getRegionBundleNames(region)
	end

	return {
		regions = regions,
		defaultRegion = BodyPartRegions.Order[1],
		defaultScale = 1,
	}
end

local function getLiveCharacter(player: Player): (Model?, Humanoid?)
	local character = player.Character
	if not (character and character:IsA("Model") and character.Parent) then
		return nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return nil, nil
	end

	return character, humanoid
end

local function resolveCharacterRootPart(character: Model, humanoid: Humanoid): BasePart?
	if humanoid.RootPart and humanoid.RootPart:IsA("BasePart") then
		return humanoid.RootPart
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	if character.PrimaryPart and character.PrimaryPart:IsA("BasePart") then
		return character.PrimaryPart
	end

	return nil
end

local function clearSandboxState(player: Player)
	sandboxStateByPlayer[player] = nil
end

local function getOrCreateSandboxState(player: Player): { [string]: { bundleName: string, scale: number } }
	local sandboxState = sandboxStateByPlayer[player]
	if sandboxState then
		return sandboxState
	end

	sandboxState = {}
	sandboxStateByPlayer[player] = sandboxState
	return sandboxState
end

local function buildVisualApplyRequest(player: Player): (BodyPartVisuals.ApplyRequest?, string?)
	local baseRig = getDefaultBaseRig()
	if not baseRig then
		return nil, "ReplicatedStorage.GameAssets.Models.BodyParts.BaseRigs.DefaultR15 is missing."
	end

	local sandboxState = sandboxStateByPlayer[player] or {}
	local regions = {}

	for _, region in ipairs(BodyPartRegions.Order) do
		local regionState = sandboxState[region]
		if regionState then
			local bundleModel = getBundleModel(region, regionState.bundleName)
			if not bundleModel then
				return nil, string.format("The %s example bundle '%s' no longer exists.", region, regionState.bundleName)
			end

			regions[region] = {
				bundle = bundleModel,
				scale = regionState.scale,
				aura = nil,
			}
		end
	end

	return {
		baseRig = baseRig,
		regions = regions,
	}, nil
end

local function summarizeApplyResult(prefix: string, applyResult: BodyPartVisuals.ApplyResult): string
	local message = prefix
	if not applyResult then
		return message
	end

	local detail = ""
	if applyResult.hipHeight ~= nil then
		detail = string.format(" HipHeight: %.2f.", applyResult.hipHeight)
	end

	if #applyResult.errors > 0 then
		return string.format("%s %s%s", prefix, table.concat(applyResult.errors, " | "), detail)
	end

	return string.format("%s Applied regions: %s.%s", prefix, table.concat(applyResult.appliedRegions, ", "), detail)
end

local function applyCurrentSandbox(player: Player): (boolean, string, BodyPartVisuals.ApplyResult?)
	local character, humanoid = getLiveCharacter(player)
	if not character then
		clearSandboxState(player)
		return false, "Your character is not currently available. Respawn and try again.", nil
	end

	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		clearSandboxState(player)
		return false, "Your current character is not an R15 rig.", nil
	end

	local request, requestError = buildVisualApplyRequest(player)
	if not request then
		return false, requestError or "Failed to build the sandbox visual request.", nil
	end

	local applyResult = BodyPartVisuals.Apply(character, request)
	if not applyResult.success then
		return false, summarizeApplyResult("Visual sandbox apply failed.", applyResult), applyResult
	end

	return true, summarizeApplyResult("Visual sandbox applied.", applyResult), applyResult
end

local function resetFullCharacter(player: Player): (boolean, string, BodyPartVisuals.ApplyResult?)
	local character, humanoid = getLiveCharacter(player)
	if not character then
		clearSandboxState(player)
		return false, "Your character is not currently available. Respawn and try again.", nil
	end

	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		clearSandboxState(player)
		return false, "Your current character is not an R15 rig.", nil
	end

	local baseRig = getDefaultBaseRig()
	if not baseRig then
		return false, "ReplicatedStorage.GameAssets.Models.BodyParts.BaseRigs.DefaultR15 is missing.", nil
	end

	local resetResult = BodyPartVisuals.Reset(character, baseRig)
	if not resetResult.success then
		return false, summarizeApplyResult("Visual sandbox reset failed.", resetResult), resetResult
	end

	return true, summarizeApplyResult("Visual sandbox reset.", resetResult), resetResult
end

local function handleGetVisualSandboxOptions()
	return response(true, "OK", "Visual sandbox options loaded.", getSandboxOptions())
end

local function handleTestDialogue()
	return response(true, "OK", "Launching the sample merchant dialogue.", {
		dialogueId = "merchant_default",
		context = {
			source = "admin_panel",
		},
	})
end

local function handleGuideToCrafting()
	return response(true, "OK", "Showing the local objective guide to crafting.", {
		objectiveId = "crafting",
		targetPath = "Workspace.Crafting.Craftsman.HumanoidRootPart",
		fallbackTargetPath = "Workspace.Crafting",
	})
end

local function handleShowMerchant(payload: any?)
	local merchantState = MerchantShopService:ForceAppear(toWholeNumber(payload and payload.durationSeconds, 300))
	pushRecentEvent("merchant", "Forced merchant active from admin panel.", {
		durationSeconds = toWholeNumber(payload and payload.durationSeconds, 300),
	})
	return response(true, "OK", "The merchant has been forced onto the map.", {
		merchantState = merchantState,
	})
end

local function buildPlayerSummary(player: Player)
	return {
		userId = player.UserId,
		name = player.Name,
		displayName = player.DisplayName,
		money = DataService:GetMoney(player),
		timePlayed = DataService:GetTimePlayed(player),
		timeShards = DataService:GetTimeShardsBalance(player),
		successfulRollCount = DataService:GetSuccessfulRollCount(player),
		selectedRollType = DataService:GetSelectedRollType(player),
		selectedRollRegion = DataService:GetSelectedRollRegion(player),
		quickRollEnabled = DataService:GetQuickRollEnabled(player),
		vipOwned = DataService:GetVipOwned(player),
		vipPlusOwned = DataService:GetVipPlusOwned(player),
	}
end

local function handleRefreshServerState()
	local players = {}
	for _, player in ipairs(Players:GetPlayers()) do
		table.insert(players, buildPlayerSummary(player))
	end

	return response(true, "OK", string.format("Refreshed state for %d player(s).", #players), {
		placeId = game.PlaceId,
		jobId = game.JobId,
		isStudio = RunService:IsStudio(),
		serverTime = Workspace:GetServerTimeNow(),
		players = players,
	})
end

local function handleRunSmokeTest()
	local checks = {
		adminRemote = adminActionRemote ~= nil and adminActionRemote.Parent ~= nil,
		bodyPartCatalogHasPieces = #BodyPartsCatalog.GetAllPieces() > 0,
		rollTypesConfigured = #RollTypes.GetOrdered() > 0,
		potionsConfigured = #PotionConfig.GetAll() > 0,
		merchantEntriesConfigured = #MerchantShopConfig.GetAll() > 0,
	}
	local failed = {}
	for checkName, ok in pairs(checks) do
		if ok ~= true then
			table.insert(failed, checkName)
		end
	end

	local ok = #failed == 0
	return response(ok, if ok then "OK" else "SMOKE_FAILED", if ok then "Smoke test passed." else ("Smoke test failed: " .. table.concat(failed, ", ")), {
		checks = checks,
		failed = failed,
	})
end

local function handleDumpSessionSummary()
	local totalMoney = 0
	local totalRolls = 0
	local players = {}
	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		local summary = buildPlayerSummary(targetPlayer)
		totalMoney += summary.money
		totalRolls += summary.successfulRollCount
		table.insert(players, summary)
	end

	local merchantState = nil
	if Players:GetPlayers()[1] then
		merchantState = MerchantShopService:GetShopState(Players:GetPlayers()[1]).shopState
	end

	return response(true, "OK", string.format("%d player(s), $%d total money, %d total rolls.", #players, totalMoney, totalRolls), {
		players = players,
		totalMoney = totalMoney,
		totalRolls = totalRolls,
		merchantState = merchantState,
		recentEvents = recentEvents,
	})
end

local function handleSendNotification(player: Player, payload: any)
	local targetKind = if typeof(payload.targetKind) == "string" then string.lower(payload.targetKind) else ""
	if targetKind == "" then
		targetKind = "self"
	end

	local text = trimText(payload.text)
	if text == "" then
		return response(false, "BAD_REQUEST", "Notification text is required.")
	end
	if string.len(text) > MAX_NOTIFICATION_TEXT_LENGTH then
		return response(false, "BAD_REQUEST", string.format("Notification text must be %d characters or fewer.", MAX_NOTIFICATION_TEXT_LENGTH))
	end

	local duration = tonumber(payload.duration)
	if duration == nil or duration ~= duration then
		return response(false, "BAD_REQUEST", "Notification duration must be a number.")
	end
	duration = math.clamp(duration, MIN_NOTIFICATION_DURATION, MAX_NOTIFICATION_DURATION)

	if targetKind == "self" then
		Notify.Send(player, text, {
			channel = "admin",
			duration = duration,
		})
		return response(true, "OK", "Sent the notification to your client.", {
			targetKind = targetKind,
			recipientCount = 1,
		})
	end

	if targetKind == "all" then
		local recipientCount = #Players:GetPlayers()
		Notify.Send("all", text, {
			channel = "admin",
			duration = duration,
		})
		return response(
			true,
			"OK",
			string.format("Broadcast the notification to %d player%s.", recipientCount, if recipientCount == 1 then "" else "s"),
			{
				targetKind = targetKind,
				recipientCount = recipientCount,
			}
		)
	end

	if targetKind == "player" then
		local targetUserId = math.floor(tonumber(payload.userId) or 0)
		if targetUserId <= 0 then
			return response(false, "BAD_REQUEST", "A valid target userId is required.")
		end

		local targetPlayer = Players:GetPlayerByUserId(targetUserId)
		if not targetPlayer then
			return response(false, "BAD_REQUEST", "That player is no longer in this server.")
		end

		Notify.Send(targetPlayer, text, {
			channel = "admin",
			duration = duration,
		})
		return response(true, "OK", string.format("Sent the notification to %s (@%s).", targetPlayer.DisplayName, targetPlayer.Name), {
			targetKind = targetKind,
			recipientCount = 1,
			userId = targetPlayer.UserId,
		})
	end

	return response(false, "BAD_REQUEST", "Notification targets must be self, all, or player.")
end

local function handleGetRuntimeState(player: Player)
	return response(true, "OK", "Loaded body part runtime state.", BodyPartService:GetClientState(player))
end

local function getTargetPlayerFromPayload(payload: any): (Player?, string?)
	if typeof(payload) ~= "table" then
		return nil, "A payload table is required."
	end

	local targetUserId = math.floor(tonumber(payload.userId) or 0)
	if targetUserId <= 0 then
		return nil, "A valid target userId is required."
	end

	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if not targetPlayer then
		return nil, "That player is no longer in this server."
	end

	return targetPlayer, nil
end

local function handleInspectPlayerProfile(payload: any)
	local targetPlayer, errorMessage = getTargetPlayerFromPayload(payload)
	if not targetPlayer then
		return response(false, "BAD_REQUEST", errorMessage or "Could not resolve the target player.")
	end

	return response(true, "OK", "Loaded player summary.", BodyPartService:GetPlayerInspectSummary(targetPlayer))
end

local function handleRepairMarketplaceEntitlement(player: Player, payload: any)
	local targetUserId = tonumber(payload.userId) or player.UserId
	local offerKey = trimText(payload.offerKey)
	if offerKey == "" then
		offerKey = "vip_plus"
	end

	local result = PurchaseReceiptService:RepairEntitlementForUser(
		player,
		targetUserId,
		offerKey,
		trimText(payload.reason)
	)
	local code = result.code
	if code == nil then
		code = if result.ok == true then "OK" else "REPAIR_FAILED"
	end

	return response(
		result.ok == true,
		tostring(code),
		tostring(result.message or "Marketplace entitlement repair completed."),
		result.data
	)
end

local function handleReloadPlayerState(payload: any)
	local targetPlayer, errorMessage = getPayloadTargetPlayer(payload, nil)
	if not targetPlayer then
		return response(false, "BAD_REQUEST", errorMessage or "Could not resolve the target player.")
	end

	BodyPartService:NotifyClient(targetPlayer, "Admin refreshed your body part state.")
	RollService:NotifyClient(targetPlayer, "Admin refreshed your rolling state.")
	PotionService:NotifyClient(targetPlayer, "Admin refreshed your potion state.")

	return response(true, "OK", string.format("Refreshed replicated state for %s.", targetPlayer.Name), {
		player = buildPlayerSummary(targetPlayer),
		bodyParts = BodyPartService:GetClientState(targetPlayer),
		rolling = RollService:GetRollingState(targetPlayer),
		potions = PotionService:GetPotionState(targetPlayer),
	})
end

local function handleTriggerTutorial(payload: any)
	local targetPlayer, errorMessage = getPayloadTargetPlayer(payload, nil)
	if not targetPlayer then
		return response(false, "BAD_REQUEST", errorMessage or "Could not resolve the target player.")
	end

	local requestedStepId = trimText(payload.stepId)
	local stepId = if requestedStepId ~= "" then TutorialConfig.NormalizeStepId(requestedStepId) else TutorialConfig.Steps.Welcome
	local state = TutorialService:StartTutorialForAdmin(targetPlayer, stepId)
	pushRecentEvent("tutorial", string.format("Triggered tutorial replay for %s at %s.", targetPlayer.Name, state.stepId), {
		userId = targetPlayer.UserId,
		stepId = state.stepId,
	})

	return response(true, "OK", string.format("Triggered tutorial for %s at %s.", targetPlayer.Name, state.stepId), {
		userId = targetPlayer.UserId,
		tutorial = state,
	})
end

local function handleTeleportToPlayer(player: Player, payload: any)
	local targetPlayer, errorMessage = getPayloadTargetPlayer(payload, nil)
	if not targetPlayer then
		return response(false, "BAD_REQUEST", errorMessage or "Could not resolve the target player.")
	end

	local sourceRoot = getCharacterRoot(player)
	local targetRoot = getCharacterRoot(targetPlayer)
	if not sourceRoot or not targetRoot then
		return response(false, "CHARACTER_MISSING", "Both characters need valid root parts.")
	end

	player.Character:PivotTo(targetRoot.CFrame * CFrame.new(3, 0, 0))
	return response(true, "OK", string.format("Teleported to %s.", targetPlayer.Name))
end

local function handleBringPlayer(player: Player, payload: any)
	local targetPlayer, errorMessage = getPayloadTargetPlayer(payload, nil)
	if not targetPlayer then
		return response(false, "BAD_REQUEST", errorMessage or "Could not resolve the target player.")
	end

	local sourceRoot = getCharacterRoot(player)
	local targetRoot = getCharacterRoot(targetPlayer)
	if not sourceRoot or not targetRoot then
		return response(false, "CHARACTER_MISSING", "Both characters need valid root parts.")
	end

	targetPlayer.Character:PivotTo(sourceRoot.CFrame * CFrame.new(3, 0, 0))
	return response(true, "OK", string.format("Brought %s to you.", targetPlayer.Name))
end

local function handleRespawnPlayer(payload: any)
	local targetPlayer, errorMessage = getPayloadTargetPlayer(payload, nil)
	if not targetPlayer then
		return response(false, "BAD_REQUEST", errorMessage or "Could not resolve the target player.")
	end

	targetPlayer:LoadCharacter()
	return response(true, "OK", string.format("Respawned %s.", targetPlayer.Name))
end

local function handleKickPlayer(payload: any)
	local targetPlayer, errorMessage = getPayloadTargetPlayer(payload, nil)
	if not targetPlayer then
		return response(false, "BAD_REQUEST", errorMessage or "Could not resolve the target player.")
	end

	local reason = trimText(payload.reason)
	if reason == "" then
		reason = "Admin action."
	end

	pushRecentEvent("moderation", string.format("Kicked %s.", targetPlayer.Name), {
		userId = targetPlayer.UserId,
		reason = reason,
	})
	targetPlayer:Kick(reason)
	return response(true, "OK", string.format("Kicked %s.", targetPlayer.Name))
end

local function handleResetPlayerData(payload: any)
	local targetUserId = toWholeNumber(payload and payload.userId, 0)
	if targetUserId <= 0 then
		return response(false, "BAD_REQUEST", "A valid target userId is required.")
	end

	local ok, wipeError = DataService:WipeByUserId(targetUserId)
	if not ok then
		return response(false, "WIPE_FAILED", wipeError or "Failed to reset player data.")
	end

	pushRecentEvent("moderation", string.format("Reset profile data for userId %d.", targetUserId), {
		userId = targetUserId,
	})
	return response(true, "OK", string.format("Reset profile data for userId %d.", targetUserId))
end

local function handlePreviewRarityTable(player: Player, payload: any?)
	local debugData = RollService:GetProbabilityDebug(player, payload)
	return response(
		true,
		"OK",
		string.format("Sol's roll list preview: %s", tostring(debugData.summary or "No preview available.")),
		debugData
	)
end

local function handleGetLuckOverride(player: Player)
	return response(true, "OK", "Loaded current luck override.", RollService:GetAdminLuckOverrideState(player))
end

local function handleSetLuckOverride(player: Player, payload: any)
	local totalLuck = tonumber(payload.totalLuck)
	if totalLuck == nil or totalLuck ~= totalLuck then
		return response(false, "BAD_REQUEST", "totalLuck must be numeric.")
	end

	return response(true, "OK", "Applied admin luck override.", RollService:SetAdminLuckOverride(player, totalLuck))
end

local function handleClearLuckOverride(player: Player)
	return response(true, "OK", "Cleared admin luck override.", RollService:ClearAdminLuckOverride(player))
end

local function handleGrantMoney(payload: any)
	local targetPlayer, errorMessage = getPayloadTargetPlayer(payload, nil)
	if not targetPlayer then
		return response(false, "BAD_REQUEST", errorMessage or "Could not resolve the target player.")
	end

	local amount = tonumber(payload.amount)
	if amount == nil or amount ~= amount then
		return response(false, "BAD_REQUEST", "Amount must be numeric.")
	end

	local mode = string.lower(trimText(payload.mode))
	local previousMoney = DataService:GetMoney(targetPlayer)
	local updatedMoney
	if mode == "set" then
		local targetMoney = math.max(0, math.floor(amount))
		updatedMoney = DataService:AdjustMoney(targetPlayer, targetMoney - previousMoney, "admin_set")
	else
		updatedMoney = DataService:AdjustMoney(targetPlayer, amount, "admin_grant")
	end

	return response(true, "OK", string.format("%s money: %d -> %d.", targetPlayer.Name, previousMoney, updatedMoney), {
		previousMoney = previousMoney,
		updatedMoney = updatedMoney,
	})
end

local function handleAddTimeShards(payload: any)
	local targetPlayer, errorMessage = getPayloadTargetPlayer(payload, nil)
	if not targetPlayer then
		return response(false, "BAD_REQUEST", errorMessage or "Could not resolve the target player.")
	end

	local amount = tonumber(payload.amount)
	if amount == nil or amount ~= amount then
		return response(false, "BAD_REQUEST", "Amount must be numeric.")
	end

	local previousBalance = DataService:GetTimeShardsBalance(targetPlayer)
	local updatedBalance = DataService:AdjustTimeShardsBalance(targetPlayer, amount, "admin_grant")
	return response(true, "OK", string.format("%s Time Shards: %d -> %d.", targetPlayer.Name, previousBalance, updatedBalance), {
		previousBalance = previousBalance,
		updatedBalance = updatedBalance,
	})
end

local function handleSetTimePlayed(payload: any)
	local targetPlayer, errorMessage = getPayloadTargetPlayer(payload, nil)
	if not targetPlayer then
		return response(false, "BAD_REQUEST", errorMessage or "Could not resolve the target player.")
	end

	local seconds = math.max(0, toWholeNumber(payload.seconds, 0))
	DataService:Set(targetPlayer, TIME_PLAYED_KEY, seconds)
	return response(true, "OK", string.format("Set %s time played to %d seconds.", targetPlayer.Name, seconds), {
		timePlayed = seconds,
	})
end

local function handleGrantPotion(payload: any)
	local targetPlayer, errorMessage = getPayloadTargetPlayer(payload, nil)
	if not targetPlayer then
		return response(false, "BAD_REQUEST", errorMessage or "Could not resolve the target player.")
	end

	local potionId = trimText(payload.potionId)
	local amount = math.max(1, toWholeNumber(payload.amount, 1))
	local ok, message = PotionService:GrantPotionUses(targetPlayer, potionId, amount)
	return response(ok, if ok then "OK" else "GRANT_FAILED", message, PotionService:GetPotionState(targetPlayer))
end

local function handleGrantAllPotions(player: Player, payload: any?)
	local amount = math.max(1, toWholeNumber(payload and payload.amount, 1))
	local ok, message, data = PotionService:GrantAllPotionUses(player, amount)
	return response(ok, if ok then "OK" else "GRANT_FAILED", message, data)
end

local function handleClearAllPotionEffects(player: Player)
	local ok, message, data = PotionService:ClearActivePotions(player)
	return response(ok, if ok then "OK" else "CLEAR_FAILED", message, data)
end

local function handleSetRollType(payload: any)
	local targetPlayer, errorMessage = getPayloadTargetPlayer(payload, nil)
	if not targetPlayer then
		return response(false, "BAD_REQUEST", errorMessage or "Could not resolve the target player.")
	end

	local rollTypeId = trimText(payload.rollTypeId)
	local ok, message = RollService:SelectRollType(targetPlayer, rollTypeId)
	return response(ok, if ok then "OK" else "ROLL_TYPE_FAILED", message, RollService:GetRollingState(targetPlayer))
end

local function handleUnlockAchievement(payload: any)
	local targetPlayer, errorMessage = getPayloadTargetPlayer(payload, nil)
	if not targetPlayer then
		return response(false, "BAD_REQUEST", errorMessage or "Could not resolve the target player.")
	end

	local achievementId = trimText(payload.achievementId)
	if not AchievementConfig.Get(achievementId) then
		return response(false, "BAD_REQUEST", "That achievement does not exist.")
	end

	DataService:Set(targetPlayer, ACHIEVEMENTS_KEY, function(currentValue)
		local state = AchievementState.Normalize(currentValue)
		state.completedIds[achievementId] = true
		return state
	end)

	local title = TitleConfig.GetByAchievementId(achievementId)
	return response(true, "OK", string.format("Unlocked achievement %s for %s.", achievementId, targetPlayer.Name), {
		achievementId = achievementId,
		titleId = title and title.id or nil,
	})
end

local function handleEquipTitle(payload: any)
	local targetPlayer, errorMessage = getPayloadTargetPlayer(payload, nil)
	if not targetPlayer then
		return response(false, "BAD_REQUEST", errorMessage or "Could not resolve the target player.")
	end

	local titleId = trimText(payload.titleId)
	if titleId ~= "" and not TitleConfig.Get(titleId) then
		return response(false, "BAD_REQUEST", "That title does not exist.")
	end

	local ok, message = DataService:SetEquippedTitleId(targetPlayer, if titleId == "" then nil else titleId)
	return response(ok, if ok then "OK" else "TITLE_FAILED", message or "Title updated.", {
		titleId = titleId,
	})
end

local function handleEquipOwnedBodyPart(player: Player, payload: any)
	local ownedId = payload.ownedId
	local scale = payload.scale

	local ok, message = BodyPartService:EquipOwnedBodyPart(player, ownedId, scale)
	return response(ok, if ok then "OK" else "EQUIP_FAILED", message, BodyPartService:GetClientState(player))
end

local function handleUnequipRuntimeRegion(player: Player, payload: any)
	local ok, message = BodyPartService:UnequipRegion(player, payload.region)
	return response(ok, if ok then "OK" else "UNEQUIP_FAILED", message, BodyPartService:GetClientState(player))
end

local function handleClearRuntimeLoadout(player: Player)
	local ok, message = BodyPartService:ClearLoadout(player)
	return response(ok, if ok then "OK" else "CLEAR_FAILED", message, BodyPartService:GetClientState(player))
end

local function buildAdminGrantedBodyPartPayload(pieceId: string): (any?, string?)
	local piece = BodyPartsCatalog.GetPiece(pieceId)
	if not piece then
		return nil, string.format("Unknown body part pieceId '%s'.", tostring(pieceId))
	end

	local setConfig = BodyPartsCatalog.GetSetForPiece(pieceId)
	return {
		pieceId = piece.id,
		rarityDenominator = math.max(1, math.floor(tonumber(piece.rarity) or 1)),
		rolledSetId = if setConfig then setConfig.id else nil,
		rolledSetDisplayName = if setConfig then setConfig.rollDisplay.displayName else nil,
		displayOddsDenominator = if setConfig then math.max(1, math.floor(tonumber(setConfig.rollDisplay.chance) or 1)) else math.max(1, math.floor(tonumber(piece.rarity) or 1)),
		displayRarity = if setConfig then setConfig.rollDisplay.rarity else "Unknown",
		mutationId = "none",
		mutation = "None",
		sizeId = "normal",
	}, nil
end

local function handleGrantBodyPart(player: Player, payload: any)
	local pieceId = payload.pieceId
	if typeof(pieceId) ~= "string" or pieceId == "" then
		return response(false, "BAD_REQUEST", "A valid pieceId is required.")
	end

	local grantPayload, payloadError = buildAdminGrantedBodyPartPayload(pieceId)
	if not grantPayload then
		return response(false, "BAD_REQUEST", payloadError or "Could not prepare the body part grant.")
	end

	local grantedRecord, grantError = DataService:AddOwnedBodyPart(player, grantPayload)
	if not grantedRecord then
		return response(false, "GRANT_FAILED", grantError or "Could not grant that body part.")
	end

	local piece = BodyPartsCatalog.GetPiece(pieceId)
	local pieceName = if piece then piece.displayName else pieceId
	return response(true, "OK", string.format('Granted "%s" (#%s).', pieceName, tostring(grantedRecord.serialNumber)), {
		runtimeState = BodyPartService:GetClientState(player),
		grantedRecord = grantedRecord,
	})
end

local function handleGrantAura(player: Player, payload: any)
	local auraId = payload.auraId
	if typeof(auraId) ~= "string" or auraId == "" then
		return response(false, "BAD_REQUEST", "A valid auraId is required.")
	end

	local auraConfig = AuraConfig.Get(auraId)
	if not auraConfig then
		return response(false, "BAD_REQUEST", string.format("Unknown auraId '%s'.", tostring(auraId)))
	end

	local hadAuraAlready = DataService:GetOwnedAuraByAuraId(player, auraId) ~= nil
	local ok, message, didGrant = AuraService:GrantAuraUnlock(player, auraId)
	if not ok then
		return response(false, "GRANT_FAILED", message or "Could not grant that aura.")
	end

	local ownedRecord = DataService:GetOwnedAuraByAuraId(player, auraId)
	local finalMessage = if hadAuraAlready or not didGrant
		then string.format('You already own "%s".', auraConfig.label)
		else (message or string.format('Granted "%s".', auraConfig.label))

	return response(true, "OK", finalMessage, {
		grantedRecord = ownedRecord,
	})
end

local function handleGrantAccessory(player: Player, payload: any, expectedSlot: AccessoryConfig.AccessorySlot)
	local accessoryId = payload.accessoryId
	if typeof(accessoryId) ~= "string" or accessoryId == "" then
		return response(false, "BAD_REQUEST", "A valid accessoryId is required.")
	end

	local accessoryConfig = AccessoryConfig.Get(accessoryId)
	if not accessoryConfig then
		return response(false, "BAD_REQUEST", string.format("Unknown accessoryId '%s'.", tostring(accessoryId)))
	end
	if accessoryConfig.slot ~= expectedSlot then
		return response(false, "BAD_REQUEST", string.format('"%s" is not a %s accessory.', accessoryConfig.label, expectedSlot))
	end

	local grantedRecord, grantError = DataService:AddOwnedAccessory(player, {
		accessoryId = accessoryConfig.id,
	})
	if not grantedRecord then
		return response(false, "GRANT_FAILED", grantError or "Could not grant that accessory.")
	end

	return response(true, "OK", string.format('Granted "%s" (%s).', accessoryConfig.label, grantedRecord.ownedId), {
		grantedRecord = grantedRecord,
		accessoryState = {
			ownedAccessories = DataService:GetOwnedAccessories(player),
			equippedAccessories = DataService:GetEquippedAccessories(player),
		},
	})
end

local function resolvePayloadTargetOrSelf(player: Player, payload: any): (Player?, string?)
	local targetPlayer, errorMessage = getPayloadTargetPlayer(payload, player)
	if targetPlayer then
		return targetPlayer, nil
	end
	if payload and payload.userId ~= nil then
		return nil, errorMessage or "Could not resolve the target player."
	end
	return player, nil
end

local function buildCraftingMaterialGrantData(targetPlayer: Player)
	return {
		craftingMaterials = DataService:GetCraftingMaterialsState(targetPlayer),
	}
end

local function handleGrantCraftingMaterial(player: Player, payload: any)
	local targetPlayer, errorMessage = resolvePayloadTargetOrSelf(player, payload)
	if not targetPlayer then
		return response(false, "BAD_REQUEST", errorMessage or "Could not resolve the target player.")
	end

	local materialId = trimText(payload.materialId)
	local materialConfig = CraftingMaterialConfig.Get(materialId)
	if not materialConfig then
		return response(false, "BAD_REQUEST", "A valid materialId is required.")
	end

	local amount = math.max(1, toWholeNumber(payload.amount, 1))
	local updatedAmount, grantError = DataService:AddCraftingMaterial(targetPlayer, materialConfig.id, amount)
	if not updatedAmount then
		return response(false, "GRANT_FAILED", grantError or "Could not grant that crafting material.")
	end

	return response(
		true,
		"OK",
		string.format('Granted %s x%d to %s (%d total).', materialConfig.label, amount, targetPlayer.Name, updatedAmount),
		buildCraftingMaterialGrantData(targetPlayer)
	)
end

local function handleGrantAllCraftingMaterials(player: Player, payload: any)
	local targetPlayer, errorMessage = resolvePayloadTargetOrSelf(player, payload)
	if not targetPlayer then
		return response(false, "BAD_REQUEST", errorMessage or "Could not resolve the target player.")
	end

	local amount = math.max(1, toWholeNumber(payload.amount, 1))
	local grantedAmounts = {}
	for _, materialConfig in ipairs(CraftingMaterialConfig.GetAll()) do
		local updatedAmount, grantError = DataService:AddCraftingMaterial(targetPlayer, materialConfig.id, amount)
		if not updatedAmount then
			return response(
				false,
				"GRANT_FAILED",
				grantError or string.format("Could not grant %s.", materialConfig.label),
				buildCraftingMaterialGrantData(targetPlayer)
			)
		end
		grantedAmounts[materialConfig.id] = updatedAmount
	end

	return response(
		true,
		"OK",
		string.format("Granted %d of each configured crafting material to %s.", amount, targetPlayer.Name),
		{
			grantedAmounts = grantedAmounts,
			craftingMaterials = DataService:GetCraftingMaterialsState(targetPlayer),
		}
	)
end

local function handleApplyVisualRegion(player: Player, payload: any)
	local region = payload.region
	local bundleName = payload.bundleName
	local scaleValue = payload.scale

	if typeof(region) ~= "string" or not BodyPartRegions.IsValid(region) then
		return response(false, "BAD_REQUEST", "A valid body region is required.")
	end

	if typeof(bundleName) ~= "string" or bundleName == "" then
		return response(false, "BAD_REQUEST", "A valid bundle name is required.")
	end

	if typeof(scaleValue) ~= "number" or scaleValue <= 0 or scaleValue ~= scaleValue then
		return response(false, "BAD_REQUEST", "Scale must be a positive number.")
	end

	local bundleModel = getBundleModel(region, bundleName)
	if not bundleModel then
		return response(false, "NOT_FOUND", string.format("No example bundle named '%s' exists for %s.", bundleName, region))
	end

	local sandboxState = getOrCreateSandboxState(player)
	local clampedScale = math.clamp(scaleValue, MIN_SANDBOX_SCALE, MAX_SANDBOX_SCALE)
	sandboxState[region] = {
		bundleName = bundleName,
		scale = clampedScale,
	}

	local ok, message, applyResult = applyCurrentSandbox(player)
	return response(ok, if ok then "OK" else "APPLY_FAILED", message, {
		scale = clampedScale,
		region = region,
		bundleName = bundleName,
		applyResult = applyResult,
	})
end

local function handleResetVisualRegion(player: Player, payload: any)
	local region = payload.region
	if typeof(region) ~= "string" or not BodyPartRegions.IsValid(region) then
		return response(false, "BAD_REQUEST", "A valid body region is required.")
	end

	local sandboxState = getOrCreateSandboxState(player)
	sandboxState[region] = nil

	if next(sandboxState) == nil then
		clearSandboxState(player)
		local ok, message, resetResult = resetFullCharacter(player)
		return response(ok, if ok then "OK" else "RESET_FAILED", message, {
			region = region,
			applyResult = resetResult,
		})
	end

	local ok, message, applyResult = applyCurrentSandbox(player)
	return response(ok, if ok then "OK" else "APPLY_FAILED", message, {
		region = region,
		applyResult = applyResult,
	})
end

local function handleResetVisualCharacter(player: Player)
	clearSandboxState(player)
	local ok, message, resetResult = resetFullCharacter(player)
	return response(ok, if ok then "OK" else "RESET_FAILED", message, {
		applyResult = resetResult,
	})
end

local function grantBodyPartToTarget(targetPlayer: Player, pieceId: string): (any?, string?)
	local grantPayload, payloadError = buildAdminGrantedBodyPartPayload(pieceId)
	if not grantPayload then
		return nil, payloadError or "Could not prepare the body part grant."
	end

	return DataService:AddOwnedBodyPart(targetPlayer, grantPayload)
end

local function handleForceCaseReward(player: Player, payload: any)
	local targetPlayer, errorMessage = getPayloadTargetPlayer(payload, player)
	if not targetPlayer then
		return response(false, "BAD_REQUEST", errorMessage or "Could not resolve the target player.")
	end

	local pieceId = trimText(payload.pieceId)
	if pieceId == "" then
		return response(false, "BAD_REQUEST", "pieceId is required.")
	end

	local grantedRecord, grantError = grantBodyPartToTarget(targetPlayer, pieceId)
	if not grantedRecord then
		return response(false, "GRANT_FAILED", grantError or "Could not grant that body part.")
	end

	return response(true, "OK", string.format("Granted roll-source reward %s to %s.", pieceId, targetPlayer.Name), {
		grantedRecord = grantedRecord,
		runtimeState = BodyPartService:GetClientState(targetPlayer),
	})
end

local function normalizeChestId(value: any): string?
	local chestId = trimText(value)
	if chestId == "" then
		chestId = "Basic"
	end

	if VALID_CHEST_IDS[chestId] == true then
		return chestId
	end

	local lowered = string.lower(chestId)
	for validChestId in pairs(VALID_CHEST_IDS) do
		if string.lower(validChestId) == lowered then
			return validChestId
		end
	end

	return nil
end

local function normalizeOptionalRollTypeId(value: any): string?
	local rollTypeId = trimText(value)
	if rollTypeId == "" or rollTypeId == "selected" then
		return nil
	end

	if not RollTypes.Get(rollTypeId) then
		return nil
	end

	return rollTypeId
end

local function normalizeOptionalRollRegion(value: any): string?
	local rollRegion = trimText(value)
	if rollRegion == "" or rollRegion == "selected" then
		return nil
	end

	if RollTargetRegions.IsValid(rollRegion) then
		return rollRegion
	end

	return nil
end

local function handlePreviewChestOpening(player: Player, payload: any)
	local targetPlayer, errorMessage = getPayloadTargetPlayer(payload, player)
	if not targetPlayer then
		return response(false, "BAD_REQUEST", errorMessage or "Could not resolve the target player.")
	end

	local chestId = normalizeChestId(payload and payload.chestId)
	if not chestId then
		return response(false, "BAD_REQUEST", "Chest ID must be Basic, VIP, VIP+, BossTier1, BossTier2, or BossTier3.")
	end

	local count = math.clamp(toWholeNumber(payload and payload.count, 5), 1, MAX_CHEST_PREVIEW_REWARD_COUNT)
	local options = {
		count = count,
		rollTypeId = normalizeOptionalRollTypeId(payload and payload.rollTypeId),
		rollRegion = normalizeOptionalRollRegion(payload and payload.rollRegion),
	}
	local preview = RollService:PreviewChestRewards(targetPlayer, options)
	if typeof(preview) ~= "table" or preview.ok ~= true then
		return response(false, "PREVIEW_FAILED", tostring(preview and preview.message or "Could not generate chest preview rewards."))
	end

	pushRecentEvent("chest_preview", string.format("Previewed %s chest opening for %s.", chestId, targetPlayer.Name), {
		chestId = chestId,
		targetUserId = targetPlayer.UserId,
		rewardCount = preview.rewardCount,
		rollTypeId = preview.rollTypeId,
		rollRegion = preview.rollRegion,
	})

	return response(true, "OK", string.format("Previewing %s with %d reward(s) for %s.", chestId, preview.rewardCount or count, targetPlayer.Name), {
		chestId = chestId,
		targetUserId = targetPlayer.UserId,
		targetName = targetPlayer.Name,
		rewards = preview.rewards,
		rewardCount = preview.rewardCount,
		rollTypeId = preview.rollTypeId,
		rollTypeDisplayName = preview.rollTypeDisplayName,
		rollRegion = preview.rollRegion,
		probabilitySummary = preview.probabilitySummary,
	})
end

local function handleTriggerAdminChest(player: Player, actionId: string)
	local chestId = ADMIN_CHEST_ACTION_IDS[actionId]
	if not chestId then
		return response(false, "BAD_REQUEST", "Unknown admin chest trigger.")
	end

	local dailyChestService, serviceError = resolveDailyChestService()
	if not dailyChestService then
		return response(false, "SERVICE_UNAVAILABLE", serviceError or "DailyChestService is unavailable.")
	end

	local ok, message, package = dailyChestService:GrantChestPackageForAdmin(player, chestId)
	if not ok or typeof(package) ~= "table" then
		return response(false, "GRANT_FAILED", message or "Failed to grant chest rewards.")
	end

	pushRecentEvent("admin_chest_trigger", string.format("Triggered %s for %s.", package.displayName or chestId, player.Name), {
		chestId = package.chestId,
		visualChestId = package.visualChestId,
		targetUserId = player.UserId,
		rewardCount = if typeof(package.rewards) == "table" then #package.rewards else 0,
	})

	return response(true, "OK", message, package)
end

local function handleGrantFullSet(payload: any)
	local targetPlayer, errorMessage = getPayloadTargetPlayer(payload, nil)
	if not targetPlayer then
		return response(false, "BAD_REQUEST", errorMessage or "Could not resolve the target player.")
	end

	local setId = trimText(payload.setId)
	local pieces = BodyPartsCatalog.GetPiecesForSet(setId)
	if not pieces or #pieces == 0 then
		return response(false, "BAD_REQUEST", "No configured pieces exist for that setId.")
	end

	local grantedRecords = {}
	for _, piece in ipairs(pieces) do
		local grantedRecord, grantError = grantBodyPartToTarget(targetPlayer, piece.id)
		if not grantedRecord then
			return response(false, "GRANT_FAILED", grantError or string.format("Failed to grant %s.", piece.id))
		end
		table.insert(grantedRecords, grantedRecord)
	end

	return response(true, "OK", string.format("Granted %d piece(s) from set %s to %s.", #grantedRecords, setId, targetPlayer.Name), {
		grantedRecords = grantedRecords,
		runtimeState = BodyPartService:GetClientState(targetPlayer),
	})
end

local function handleClearBodyParts(payload: any)
	local targetPlayer, errorMessage = getPayloadTargetPlayer(payload, nil)
	if not targetPlayer then
		return response(false, "BAD_REQUEST", errorMessage or "Could not resolve the target player.")
	end

	local ownedBodyParts = DataService:GetOwnedBodyParts(targetPlayer)
	local equippedState = BodyPartService:GetSessionLoadout(targetPlayer)
	local equippedOwnedIds = {}
	for _, entry in pairs(equippedState) do
		if typeof(entry) == "table" and typeof(entry.ownedId) == "string" then
			equippedOwnedIds[entry.ownedId] = true
		end
	end

	local removeIds = {}
	for ownedId, record in pairs(ownedBodyParts) do
		if equippedOwnedIds[ownedId] ~= true and record.isFavorite ~= true then
			table.insert(removeIds, ownedId)
		end
	end

	if #removeIds == 0 then
		return response(true, "OK", "No unequipped, unfavorited body parts were available to clear.")
	end

	local removedRecords, removeError = DataService:RemoveOwnedBodyParts(targetPlayer, removeIds)
	if not removedRecords then
		return response(false, "CLEAR_FAILED", removeError or "Failed to clear body parts.")
	end

	BodyPartService:NotifyClient(targetPlayer, "Admin cleared unequipped body parts.")
	return response(true, "OK", string.format("Cleared %d body part(s) from %s.", #removedRecords, targetPlayer.Name), {
		removedCount = #removedRecords,
		runtimeState = BodyPartService:GetClientState(targetPlayer),
	})
end

local function handleEquipBestLoadout(payload: any)
	local targetPlayer, errorMessage = getPayloadTargetPlayer(payload, nil)
	if not targetPlayer then
		return response(false, "BAD_REQUEST", errorMessage or "Could not resolve the target player.")
	end

	local ok, message = BodyPartService:EquipBestLoadout(targetPlayer)
	return response(ok, if ok then "OK" else "EQUIP_FAILED", message, BodyPartService:GetClientState(targetPlayer))
end

local function handleInspectLoadoutBonuses(payload: any)
	local targetPlayer, errorMessage = getPayloadTargetPlayer(payload, nil)
	if not targetPlayer then
		return response(false, "BAD_REQUEST", errorMessage or "Could not resolve the target player.")
	end

	return response(true, "OK", string.format("Loaded bonuses for %s.", targetPlayer.Name), {
		sessionBonuses = BodyPartService:GetComputedLoadoutBonuses(targetPlayer),
		persistedBonuses = BodyPartService:GetPersistedLoadoutBonuses(targetPlayer),
		equipped = BodyPartLoadout.CloneEquippedState(BodyPartService:GetSessionLoadout(targetPlayer)),
	})
end

local function handleTestPyramidHitbox(player: Player)
	local character, humanoid = getLiveCharacter(player)
	if not character or not humanoid then
		return response(false, "CHARACTER_MISSING", "Your character is not currently available. Respawn and try again.")
	end

	local head = character:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return response(false, "HEAD_MISSING", "Your character does not have a valid Head part.")
	end

	local rootPart = resolveCharacterRootPart(character, humanoid)
	if not rootPart then
		return response(false, "ROOT_MISSING", "Your character does not have a valid root part.")
	end

	local forward = rootPart.CFrame.LookVector
	local planarForward = Vector3.new(forward.X, 0, forward.Z)
	if planarForward.Magnitude <= 0.001 then
		planarForward = Vector3.new(head.CFrame.LookVector.X, 0, head.CFrame.LookVector.Z)
	end
	if planarForward.Magnitude <= 0.001 then
		planarForward = Vector3.new(0, 0, -1)
	end
	planarForward = planarForward.Unit

	local hitbox = Hitbox.new({
		Character = character,
		HitboxCFrame = CFrame.lookAt(head.Position, head.Position + planarForward),
		HitboxShape = "Pyramid",
		PyramidDistance = TEST_PYRAMID_DISTANCE,
		PyramidWidth = TEST_PYRAMID_WIDTH,
		PyramidLayers = TEST_PYRAMID_LAYERS,
		HitboxType = "SpacialQuery",
		Time = TEST_PYRAMID_DURATION_SECONDS,
		MaxParts = 128,
	})
	hitbox:Visible(true)

	return response(
		true,
		"OK",
		string.format(
			"Spawned a visible pyramid hitbox from your head for %d seconds. Distance: %d, base width: %d, layers: %d.",
			TEST_PYRAMID_DURATION_SECONDS,
			TEST_PYRAMID_DISTANCE,
			TEST_PYRAMID_WIDTH,
			TEST_PYRAMID_LAYERS
		)
	)
end

local function handleInspectRollSources()
	local entries = {}
	for _, rollType in ipairs(RollTypes.GetOrdered()) do
		table.insert(entries, {
			id = rollType.id,
			displayName = rollType.displayName,
			moneyCost = rollType.moneyCost,
			luckMultiplier = rollType.luckMultiplier,
			bandLuckScalar = rollType.bandLuckScalar,
			uiOrder = rollType.uiOrder,
		})
	end

	return response(true, "OK", string.format("Loaded %d roll source(s).", #entries), {
		rollTypes = entries,
	})
end

local function normalizeRollSimulationPayload(payload: any): any
	local options = {}
	options.count = math.clamp(toWholeNumber(payload and payload.count, 100), 1, MAX_SIMULATION_COUNT)

	local rollTypeId = trimText(payload and payload.rollTypeId)
	if rollTypeId ~= "" and rollTypeId ~= "selected" then
		options.rollTypeId = rollTypeId
	end

	local rollRegion = trimText(payload and payload.rollRegion)
	if rollRegion ~= "" and rollRegion ~= "selected" and RollTargetRegions.IsValid(rollRegion) then
		options.rollRegion = rollRegion
	end

	local totalLuck = tonumber(payload and payload.totalLuck)
	if totalLuck ~= nil and totalLuck == totalLuck then
		options.totalLuck = totalLuck
	end

	return options
end

local function handleSimulateRollBatch(player: Player, payload: any)
	local targetPlayer = player
	local resolvedTarget, targetError = getPayloadTargetPlayer(payload, player)
	if resolvedTarget then
		targetPlayer = resolvedTarget
	elseif payload and payload.userId ~= nil then
		return response(false, "BAD_REQUEST", targetError or "Could not resolve the target player.")
	end

	local options = normalizeRollSimulationPayload(payload)
	local simulation = RollService:SimulateRolls(targetPlayer, options)
	return response(true, "OK", string.format("Simulated %d roll(s) for %s.", simulation.count, targetPlayer.Name), simulation)
end

local function handleCaptureRuntimeSnapshot(player: Player)
	local players = {}
	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		table.insert(players, buildPlayerSummary(targetPlayer))
	end

	return response(true, "OK", "Captured runtime snapshot.", {
		capturedAtUnix = os.time(),
		serverTime = Workspace:GetServerTimeNow(),
		placeId = game.PlaceId,
		jobId = game.JobId,
		isStudio = RunService:IsStudio(),
		playerCount = #players,
		players = players,
		requestingPlayer = buildPlayerSummary(player),
		recentEvents = recentEvents,
	})
end

local function handleViewRecentEvents()
	return response(true, "OK", string.format("Loaded %d recent event(s).", #recentEvents), {
		events = recentEvents,
	})
end

local function handleInspectReplication(payload: any)
	local targetPlayer, errorMessage = getPayloadTargetPlayer(payload, nil)
	if not targetPlayer then
		return response(false, "BAD_REQUEST", errorMessage or "Could not resolve the target player.")
	end

	local data = DataService:Get(targetPlayer)
	local payloadText = safeJsonEncode(data)
	return response(true, "OK", string.format("Loaded replicated data snapshot for %s (%d bytes JSON).", targetPlayer.Name, #payloadText), {
		player = buildPlayerSummary(targetPlayer),
		payloadBytes = #payloadText,
		data = data,
	})
end

local function handleExportDebugPayload(payload: any)
	local targetPlayer, errorMessage = getPayloadTargetPlayer(payload, nil)
	if not targetPlayer then
		return response(false, "BAD_REQUEST", errorMessage or "Could not resolve the target player.")
	end

	local debugPayload = {
		capturedAtUnix = os.time(),
		player = buildPlayerSummary(targetPlayer),
		data = DataService:Get(targetPlayer),
		bodyParts = BodyPartService:GetClientState(targetPlayer),
		rolling = RollService:GetRollingState(targetPlayer),
		potions = PotionService:GetPotionState(targetPlayer),
		merchant = MerchantShopService:GetShopState(targetPlayer).shopState,
	}
	local encoded = safeJsonEncode(debugPayload)
	return response(true, "OK", string.format("Exported debug payload for %s (%d bytes JSON).", targetPlayer.Name, #encoded), {
		payload = debugPayload,
		json = encoded,
		bytes = #encoded,
	})
end

local function handleInspectBossArena()
	local runtimeService = nil
	local ok, result = pcall(function()
		return require(script.Parent.BossArenaRuntimeService)
	end)
	if ok then
		runtimeService = result
	end

	if runtimeService == nil then
		return response(false, "UNAVAILABLE", "Boss arena runtime service is unavailable.")
	end

	local data = {}
	if typeof(runtimeService.GetBossHealthState) == "function" then
		data.healthState = runtimeService:GetBossHealthState()
	end
	if typeof(runtimeService.GetBossTimerState) == "function" then
		data.timerState = runtimeService:GetBossTimerState()
	end
	if typeof(runtimeService.GetEncounterState) == "function" then
		data.encounterState = runtimeService:GetEncounterState()
	end

	return response(true, "OK", "Loaded boss arena state.", data)
end

function AdminService:IsPlayerAllowed(player: Player): boolean
	return isAllowedUserId(player.UserId)
end

function AdminService:RefreshPlayerAccess(player: Player)
	player:SetAttribute(ACCESS_ATTRIBUTE, self:IsPlayerAllowed(player))
end

function AdminService:HandleAction(player: Player, request: any)
	if not self:IsPlayerAllowed(player) then
		return response(false, "FORBIDDEN", "You do not have access to the admin panel.")
	end

	if typeof(request) ~= "table" then
		return response(false, "BAD_REQUEST", "Admin requests must be sent as a table.")
	end

	local tabId = request.tabId
	local actionId = request.actionId
	local payload = request.payload

	if typeof(tabId) ~= "string" or tabId == "" then
		return response(false, "BAD_REQUEST", "Admin requests must include a valid tabId.")
	end

	if typeof(actionId) ~= "string" or actionId == "" then
		return response(false, "BAD_REQUEST", "Admin requests must include a valid actionId.")
	end

	if payload ~= nil and typeof(payload) ~= "table" then
		return response(false, "BAD_REQUEST", "Admin request payloads must be omitted or sent as a table.")
	end
	payload = payload or {}

	local isValidAction, validationMessage = validateActionRequest(player, tabId, actionId, payload)
	if not isValidAction then
		return response(false, "FORBIDDEN", validationMessage or "That admin action is not allowed.")
	end

	if tabId == OVERVIEW_TAB_ID and actionId == "test_dialogue" then
		return handleTestDialogue()
	end

	if tabId == OVERVIEW_TAB_ID and actionId == "guide_to_crafting" then
		return handleGuideToCrafting()
	end

	if tabId == OVERVIEW_TAB_ID and actionId == "show_merchant" then
		return handleShowMerchant(payload)
	end

	if tabId == OVERVIEW_TAB_ID and actionId == "refresh_server_state" then
		return handleRefreshServerState()
	end

	if tabId == OVERVIEW_TAB_ID and actionId == "run_smoke_test" then
		return handleRunSmokeTest()
	end

	if tabId == OVERVIEW_TAB_ID and actionId == "dump_session_summary" then
		return handleDumpSessionSummary()
	end

	if tabId == OVERVIEW_TAB_ID and actionId == "send_notification" then
		return handleSendNotification(player, payload)
	end

	if tabId == PLAYERS_TAB_ID and actionId == "inspect_player_profile" then
		return handleInspectPlayerProfile(payload)
	end

	if tabId == PLAYERS_TAB_ID and actionId == "repair_marketplace_entitlement" then
		return handleRepairMarketplaceEntitlement(player, payload)
	end

	if tabId == PLAYERS_TAB_ID and actionId == "reload_player_state" then
		return handleReloadPlayerState(payload)
	end

	if tabId == PLAYERS_TAB_ID and actionId == "trigger_tutorial" then
		return handleTriggerTutorial(payload)
	end

	if tabId == PLAYERS_TAB_ID and actionId == "teleport_to_player" then
		return handleTeleportToPlayer(player, payload)
	end

	if tabId == PLAYERS_TAB_ID and actionId == "bring_player" then
		return handleBringPlayer(player, payload)
	end

	if tabId == PLAYERS_TAB_ID and actionId == "respawn_player" then
		return handleRespawnPlayer(payload)
	end

	if tabId == PLAYERS_TAB_ID and actionId == "kick_player" then
		return handleKickPlayer(payload)
	end

	if tabId == PLAYERS_TAB_ID and actionId == "reset_player_data" then
		return handleResetPlayerData(payload)
	end

	if tabId == PROGRESSION_TAB_ID and actionId == "grant_money" then
		return handleGrantMoney(payload)
	end

	if tabId == PROGRESSION_TAB_ID and actionId == "add_time_shards" then
		return handleAddTimeShards(payload)
	end

	if tabId == PROGRESSION_TAB_ID and actionId == "grant_potion" then
		return handleGrantPotion(payload)
	end

	if tabId == PROGRESSION_TAB_ID and actionId == "grant_all_potions" then
		return handleGrantAllPotions(player, payload)
	end

	if tabId == PROGRESSION_TAB_ID and actionId == "clear_all_potion_effects" then
		return handleClearAllPotionEffects(player)
	end

	if tabId == PROGRESSION_TAB_ID and actionId == "set_time_played" then
		return handleSetTimePlayed(payload)
	end

	if tabId == PROGRESSION_TAB_ID and actionId == "set_roll_type" then
		return handleSetRollType(payload)
	end

	if tabId == PROGRESSION_TAB_ID and actionId == "unlock_achievement" then
		return handleUnlockAchievement(payload)
	end

	if tabId == PROGRESSION_TAB_ID and actionId == "equip_title" then
		return handleEquipTitle(payload)
	end

	if tabId == PROGRESSION_TAB_ID and actionId == "get_luck_override" then
		return handleGetLuckOverride(player)
	end

	if tabId == PROGRESSION_TAB_ID and actionId == "set_luck_override" then
		return handleSetLuckOverride(player, payload)
	end

	if tabId == PROGRESSION_TAB_ID and actionId == "clear_luck_override" then
		return handleClearLuckOverride(player)
	end

	if tabId == DIAGNOSTICS_TAB_ID and actionId == "test_pyramid_hitbox" then
		return handleTestPyramidHitbox(player)
	end

	if tabId == DIAGNOSTICS_TAB_ID and actionId == "capture_runtime_snapshot" then
		return handleCaptureRuntimeSnapshot(player)
	end

	if tabId == DIAGNOSTICS_TAB_ID and actionId == "view_recent_events" then
		return handleViewRecentEvents()
	end

	if tabId == DIAGNOSTICS_TAB_ID and actionId == "inspect_replication" then
		return handleInspectReplication(payload)
	end

	if tabId == DIAGNOSTICS_TAB_ID and actionId == "export_debug_payload" then
		return handleExportDebugPayload(payload)
	end

	if tabId == DIAGNOSTICS_TAB_ID and actionId == "inspect_boss_arena" then
		return handleInspectBossArena()
	end

	if tabId == ROLL_SOURCES_TAB_ID and actionId == "inspect_roll_sources" then
		return handleInspectRollSources()
	end

	if tabId == ROLL_SOURCES_TAB_ID and actionId == "select_roll_source" then
		return handleSetRollType(payload)
	end

	if tabId == ROLL_SOURCES_TAB_ID and (actionId == "simulate_case_batch" or actionId == "force_modifier_roll") then
		return handleSimulateRollBatch(player, payload)
	end

	if tabId == ROLL_SOURCES_TAB_ID and actionId == "force_case_reward" then
		return handleForceCaseReward(player, payload)
	end

	if tabId == ROLL_SOURCES_TAB_ID and actionId == "preview_chest_opening" then
		return handlePreviewChestOpening(player, payload)
	end

	if tabId == ROLL_SOURCES_TAB_ID and ADMIN_CHEST_ACTION_IDS[actionId] ~= nil then
		return handleTriggerAdminChest(player, actionId)
	end

	if tabId == BODY_PARTS_TAB_ID then
		if actionId == "grant_body_part" then
			return handleGrantBodyPart(player, payload)
		end

		if actionId == "grant_head_accessory" then
			return handleGrantAccessory(player, payload, "HeadAccessory")
		end

		if actionId == "grant_gear_accessory" then
			return handleGrantAccessory(player, payload, "GearAccessory")
		end

		if actionId == "grant_crafting_material" then
			return handleGrantCraftingMaterial(player, payload)
		end

		if actionId == "grant_all_crafting_materials" then
			return handleGrantAllCraftingMaterials(player, payload)
		end

		if actionId == "grant_full_set" then
			return handleGrantFullSet(payload)
		end

		if actionId == "clear_body_parts" then
			return handleClearBodyParts(payload)
		end

		if actionId == "equip_best_loadout" then
			return handleEquipBestLoadout(payload)
		end

		if actionId == "grant_aura" then
			return handleGrantAura(player, payload)
		end

		if actionId == "get_runtime_state" then
			return handleGetRuntimeState(player)
		end

		if actionId == "equip_owned_body_part" then
			return handleEquipOwnedBodyPart(player, payload)
		end

		if actionId == "unequip_runtime_region" then
			return handleUnequipRuntimeRegion(player, payload)
		end

		if actionId == "clear_runtime_loadout" then
			return handleClearRuntimeLoadout(player)
		end

		if actionId == "preview_rarity_table" then
			return handlePreviewRarityTable(player, payload)
		end

		if actionId == "force_modifier_roll" then
			return handleSimulateRollBatch(player, payload)
		end

		if actionId == "inspect_loadout_bonuses" then
			return handleInspectLoadoutBonuses(payload)
		end

		if actionId == "get_visual_sandbox_options" then
			return handleGetVisualSandboxOptions()
		end

		if actionId == "apply_visual_region" then
			return handleApplyVisualRegion(player, payload)
		end

		if actionId == "reset_visual_region" then
			return handleResetVisualRegion(player, payload)
		end

		if actionId == "reset_visual_character" then
			return handleResetVisualCharacter(player)
		end
	end

	return response(false, "NOT_IMPLEMENTED", "This admin action is scaffolded but not implemented yet.", {
		tabId = tabId,
		actionId = actionId,
	})
end

function AdminService:OnStart()
	local remote = ensureAdminActionRemote()
	remote.OnServerInvoke = function(player: Player, request: any)
		local allowed = RequestLimiter:Allow(player, "remote.admin")
		if not allowed then
			return response(false, "RATE_LIMITED", "You're sending admin actions too quickly.")
		end

		local ok, result = pcall(function()
			return self:HandleAction(player, request)
		end)

		if ok then
			return result
		end

		Logger.Warn(string.format("[AdminService] AdminAction failed for %s: %s", player.Name, tostring(result)))
		return response(false, "INTERNAL_ERROR", "The admin action failed on the server.")
	end
end

function AdminService:OnPlayerAdded(player: Player)
	self:RefreshPlayerAccess(player)

	if characterAddedConnections[player] then
		characterAddedConnections[player]:Disconnect()
	end

	characterAddedConnections[player] = player.CharacterAdded:Connect(function()
		clearSandboxState(player)
	end)
end

function AdminService:OnPlayerRemoving(player: Player)
	if characterAddedConnections[player] then
		characterAddedConnections[player]:Disconnect()
		characterAddedConnections[player] = nil
	end

	clearSandboxState(player)
end

return AdminService
