local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AdminConfig = require(script.Parent.AdminConfig)
local AppraisalService = require(script.Parent.AppraisalService)
local AuraService = require(script.Parent.AuraService)
local BodyPartService = require(script.Parent.BodyPartService)
local DataService = require(script.Parent.DataService)
local BodyPartRegions = require(ReplicatedStorage.Shared.Character.BodyPartRegions)
local BodyPartVisuals = require(ReplicatedStorage.Shared.Character.BodyPartVisuals)
local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local RollService = require(script.Parent.RollService)

local REMOTES_FOLDER_NAME = "Remotes"
local ADMIN_ACTION_REMOTE_NAME = "AdminAction"
local ACCESS_ATTRIBUTE = "CanUseAdminPanel"
local BODY_PARTS_TAB_ID = "bodyParts"
local PLAYERS_TAB_ID = "players"
local MIN_SANDBOX_SCALE = 0.4
local MAX_SANDBOX_SCALE = 2.5

local remotesFolder: Folder? = nil
local adminActionRemote: RemoteFunction? = nil
local sandboxStateByPlayer: { [Player]: { [string]: { bundleName: string, scale: number } } } = {}
local characterAddedConnections: { [Player]: RBXScriptConnection } = {}

local AdminService = {}

local function response(ok: boolean, code: string, message: string, data: any?)
	return {
		ok = ok,
		code = code,
		message = message,
		data = data or {},
	}
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

	for _, allowedUserId in ipairs(AdminConfig.AllowedUserIds) do
		if tonumber(allowedUserId) == userId then
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

	local bodyParts = gameAssets:FindFirstChild("BodyParts")
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
		return nil, "ReplicatedStorage.GameAssets.BodyParts.BaseRigs.DefaultR15 is missing."
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
		return false, "ReplicatedStorage.GameAssets.BodyParts.BaseRigs.DefaultR15 is missing.", nil
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

local function handleShowAppraiser()
	local appraisalState = AppraisalService:ForceAppear()
	return response(true, "OK", "The appraiser has been forced onto the map.", {
		appraisalState = appraisalState,
	})
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

local function handlePreviewRarityTable(player: Player)
	local debugData = RollService:GetProbabilityDebug(player)
	return response(
		true,
		"OK",
		string.format("Hidden roll table preview: %s", tostring(debugData.summary or "No preview available.")),
		debugData
	)
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

	if tabId == "overview" and actionId == "test_dialogue" then
		return handleTestDialogue()
	end

	if tabId == "overview" and actionId == "show_appraiser" then
		return handleShowAppraiser()
	end

	if tabId == PLAYERS_TAB_ID and actionId == "inspect_player_profile" then
		return handleInspectPlayerProfile(payload or {})
	end

	if tabId == BODY_PARTS_TAB_ID then
		if actionId == "grant_body_part" then
			return handleGrantBodyPart(player, payload or {})
		end

		if actionId == "grant_aura" then
			return handleGrantAura(player, payload or {})
		end

		if actionId == "get_runtime_state" then
			return handleGetRuntimeState(player)
		end

		if actionId == "equip_owned_body_part" then
			return handleEquipOwnedBodyPart(player, payload or {})
		end

		if actionId == "unequip_runtime_region" then
			return handleUnequipRuntimeRegion(player, payload or {})
		end

		if actionId == "clear_runtime_loadout" then
			return handleClearRuntimeLoadout(player)
		end

		if actionId == "preview_rarity_table" then
			return handlePreviewRarityTable(player)
		end

		if actionId == "get_visual_sandbox_options" then
			return handleGetVisualSandboxOptions()
		end

		if actionId == "apply_visual_region" then
			return handleApplyVisualRegion(player, payload or {})
		end

		if actionId == "reset_visual_region" then
			return handleResetVisualRegion(player, payload or {})
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
		local ok, result = pcall(function()
			return self:HandleAction(player, request)
		end)

		if ok then
			return result
		end

		warn(string.format("[AdminService] AdminAction failed for %s: %s", player.Name, tostring(result)))
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
