local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChatNotificationConfig = require(ReplicatedStorage.Shared.Config.ChatNotificationConfig)
local Logger = require(ReplicatedStorage.Shared.Diagnostics.Logger)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local SizeConfig = require(ReplicatedStorage.Shared.Config.SizeConfig)

local remotesFolder: Folder? = nil
local chatNotificationsFolder: Folder? = nil
local rareRollRemote: RemoteEvent? = nil
local globalRollSubscription: RBXScriptConnection? = nil
local seenGlobalMessageIds: { [string]: boolean } = {}
local nextGlobalMessageId = 0

local ChatNotificationService = {}

local function ensureRemotesFolder(): Folder
	if remotesFolder and remotesFolder.Parent == ReplicatedStorage then
		return remotesFolder
	end

	local existing = ReplicatedStorage:FindFirstChild(ChatNotificationConfig.RemotesFolderName)
	if existing and existing:IsA("Folder") then
		remotesFolder = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = ChatNotificationConfig.RemotesFolderName
	folder.Parent = ReplicatedStorage
	remotesFolder = folder
	return folder
end

local function ensureChatNotificationsFolder(): Folder
	local rootFolder = ensureRemotesFolder()
	if chatNotificationsFolder and chatNotificationsFolder.Parent == rootFolder then
		return chatNotificationsFolder
	end

	local existing = rootFolder:FindFirstChild(ChatNotificationConfig.FolderName)
	if existing and existing:IsA("Folder") then
		chatNotificationsFolder = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = ChatNotificationConfig.FolderName
	folder.Parent = rootFolder
	chatNotificationsFolder = folder
	return folder
end

local function ensureRareRollRemote(): RemoteEvent
	local folder = ensureChatNotificationsFolder()
	if rareRollRemote and rareRollRemote.Parent == folder then
		return rareRollRemote
	end

	local existing = folder:FindFirstChild(ChatNotificationConfig.RareRollRemoteName)
	if existing and existing:IsA("RemoteEvent") then
		rareRollRemote = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = ChatNotificationConfig.RareRollRemoteName
	remote.Parent = folder
	rareRollRemote = remote
	return remote
end

local function resolveString(value: any): string?
	if typeof(value) == "string" and value ~= "" then
		return value
	end

	return nil
end

local function buildRareRollPayload(player: Player, rollResult: any): any?
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end
	if typeof(rollResult) ~= "table" then
		return nil
	end

	local setResult = if typeof(rollResult.setResult) == "table" then rollResult.setResult else {}
	local finalResult = if typeof(rollResult.finalResult) == "table" then rollResult.finalResult else {}
	local mutationResult = if typeof(rollResult.mutationResult) == "table" then rollResult.mutationResult else {}
	local sizeResult = if typeof(rollResult.sizeResult) == "table" then rollResult.sizeResult else {}
	local displayRarity = ChatNotificationConfig.NormalizeDisplayRarity(setResult.displayRarity or finalResult.Rarity)
	if not ChatNotificationConfig.IsRareRollRarity(displayRarity) then
		return nil
	end

	local mutationId = resolveString(mutationResult.id) or resolveString(finalResult.MutationId) or MutationConfig.GetDefault().id
	local sizeId = resolveString(sizeResult.id) or resolveString(finalResult.SizeId) or SizeConfig.GetDefault().id

	return {
		kind = ChatNotificationConfig.RareRollKind,
		playerName = player.Name,
		userId = player.UserId,
		setDisplayName = resolveString(setResult.displayName) or resolveString(finalResult.Name) or "Unknown",
		pieceDisplayName = resolveString(finalResult.BodyPart) or "Body Part",
		displayRarity = displayRarity,
		displayOddsDenominator = tonumber(setResult.displayOddsDenominator)
			or tonumber(finalResult.DisplayOddsDenominator)
			or tonumber(finalResult.Chance)
			or 1,
		mutationDisplayName = resolveString(mutationResult.displayName)
			or resolveString(finalResult.Mutation)
			or MutationConfig.GetDisplayName(mutationId),
		mutationId = mutationId,
		sizeDisplayName = resolveString(sizeResult.displayName)
			or resolveString(finalResult.Size)
			or SizeConfig.GetDisplayName(sizeId),
		sizeId = sizeId,
	}
end

local function getOriginJobId(): string
	local jobId = game.JobId
	if typeof(jobId) == "string" and jobId ~= "" then
		return jobId
	end

	return "studio"
end

local function createGlobalMessageId(): string
	nextGlobalMessageId += 1
	return string.format("%s:%d:%d", getOriginJobId(), os.time(), nextGlobalMessageId)
end

local function cloneGlobalPayload(payload: any): any
	local globalPayload = table.clone(payload)
	globalPayload.originJobId = getOriginJobId()
	globalPayload.messageId = createGlobalMessageId()
	return globalPayload
end

local function isValidGlobalPayload(payload: any): boolean
	if typeof(payload) ~= "table" then
		return false
	end
	if payload.kind ~= ChatNotificationConfig.RareRollKind then
		return false
	end
	if typeof(payload.messageId) ~= "string" or payload.messageId == "" then
		return false
	end
	if typeof(payload.originJobId) ~= "string" or payload.originJobId == "" then
		return false
	end
	if payload.originJobId == getOriginJobId() then
		return false
	end

	local displayRarity = ChatNotificationConfig.NormalizeDisplayRarity(payload.displayRarity)
	return ChatNotificationConfig.IsGlobalRollRarity(displayRarity)
end

local function publishGlobalRoll(payload: any)
	if not ChatNotificationConfig.IsGlobalRollRarity(payload.displayRarity) then
		return
	end

	local globalPayload = cloneGlobalPayload(payload)
	seenGlobalMessageIds[globalPayload.messageId] = true

	local ok, err = pcall(function()
		MessagingService:PublishAsync(ChatNotificationConfig.GlobalRollTopicName, globalPayload)
	end)
	if not ok then
		Logger.Warn(string.format("[ChatNotificationService] Failed to publish global roll: %s", tostring(err)))
	end
end

local function handleGlobalRollMessage(message: any)
	local payload = if typeof(message) == "table" then message.Data else nil
	if not isValidGlobalPayload(payload) then
		return
	end
	if seenGlobalMessageIds[payload.messageId] == true then
		return
	end

	seenGlobalMessageIds[payload.messageId] = true
	ensureRareRollRemote():FireAllClients(payload)
end

local function subscribeToGlobalRolls()
	if globalRollSubscription then
		return
	end

	local ok, result = pcall(function()
		return MessagingService:SubscribeAsync(ChatNotificationConfig.GlobalRollTopicName, handleGlobalRollMessage)
	end)
	if ok then
		globalRollSubscription = result
	else
		Logger.Warn(string.format("[ChatNotificationService] Failed to subscribe to global rolls: %s", tostring(result)))
	end
end

function ChatNotificationService:AnnounceRareRoll(player: Player, rollResult: any)
	local payload = buildRareRollPayload(player, rollResult)
	if not payload then
		return false
	end

	ensureRareRollRemote():FireAllClients(payload)
	publishGlobalRoll(payload)
	return true
end

function ChatNotificationService:OnStart()
	ensureRareRollRemote()
	subscribeToGlobalRolls()
end

return ChatNotificationService
