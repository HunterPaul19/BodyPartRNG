local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DefinitionUtil = require(ReplicatedStorage.Shared.Gameplay.Dialogue.DefinitionUtil)
local Registry = require(ReplicatedStorage.Shared.Gameplay.Dialogue.Registry)
local Schema = require(ReplicatedStorage.Lists.Schema)

local DataService = require(script.Parent.DataService)
local RequestLimiter = require(script.Parent.Common.RequestLimiter)

local REMOTES_FOLDER_NAME = "Remotes"
local DIALOGUE_FOLDER_NAME = "Dialogue"
local RUN_ACTION_REMOTE_NAME = "RunAction"
local VIP_OWNED_KEY = Schema.VipOwned and Schema.VipOwned.key or nil

local dialogueFolder: Folder? = nil
local runActionRemote: RemoteFunction? = nil

local DialogueActionService = {
	_started = false,
	_registered = false,
}

local function response(ok: boolean, message: string, data: any?)
	return {
		ok = ok,
		message = message,
		data = data,
	}
end

local function ensureRemotesFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = REMOTES_FOLDER_NAME
	folder.Parent = ReplicatedStorage
	return folder
end

local function ensureDialogueFolder(): Folder
	local rootFolder = ensureRemotesFolder()
	if dialogueFolder and dialogueFolder.Parent == rootFolder then
		return dialogueFolder
	end

	local existing = rootFolder:FindFirstChild(DIALOGUE_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		dialogueFolder = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = DIALOGUE_FOLDER_NAME
	folder.Parent = rootFolder
	dialogueFolder = folder
	return folder
end

local function ensureRemoteFunction(cachedRemote: RemoteFunction?, remoteName: string): RemoteFunction
	local folder = ensureDialogueFolder()
	if cachedRemote and cachedRemote.Parent == folder then
		return cachedRemote
	end

	local existing = folder:FindFirstChild(remoteName)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = remoteName
	remote.Parent = folder
	return remote
end

local function normalizeActionPayload(payload: any): (string?, string?, string?, { [string]: any }?)
	if typeof(payload) ~= "table" then
		return nil, nil, nil, nil
	end

	local dialogueId = if typeof(payload.dialogueId) == "string" then payload.dialogueId else nil
	local nodeId = if typeof(payload.nodeId) == "string" then payload.nodeId else nil
	local choiceId = if typeof(payload.choiceId) == "string" then payload.choiceId else nil
	local context = if typeof(payload.context) == "table" then payload.context else {}
	return dialogueId, nodeId, choiceId, context
end

function DialogueActionService:_registerDefaultConditions()
	if self._registered then
		return
	end
	self._registered = true

	Registry.RegisterCondition("vipOwned", function(session)
		if not VIP_OWNED_KEY then
			return false
		end

		local player = session and session.player
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return false
		end

		return DataService:Get(player, VIP_OWNED_KEY) == true
	end)
end

function DialogueActionService:RunAction(player: Player, payload: any)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return response(false, "A valid player is required.", nil)
	end

	local dialogueId, nodeId, choiceId, context = normalizeActionPayload(payload)
	if not (dialogueId and nodeId and choiceId) then
		return response(false, "Dialogue action payload is incomplete.", nil)
	end

	local _node, choice = DefinitionUtil.GetChoice(dialogueId, nodeId, choiceId)
	if not choice then
		return response(false, "That dialogue choice is no longer valid.", nil)
	end

	local session = {
		player = player,
		dialogueId = dialogueId,
		nodeId = nodeId,
		context = context,
	}

	if not Registry.EvaluateConditions(session, choice.conditionIds) then
		return response(false, "That dialogue choice is unavailable.", nil)
	end

	local action = choice.action
	if not action and choice.nextNodeId then
		return response(true, "OK", {
			nextNodeId = choice.nextNodeId,
		})
	end
	if not action then
		return response(false, "That dialogue choice has no action.", nil)
	end

	if not Registry.HasAction(action.type) then
		Logger.Warn(string.format("[DialogueActionService] Unsupported server dialogue action '%s'.", tostring(action.type)))
		return response(false, "That dialogue action is not supported by the server.", nil)
	end

	local result = Registry.RunAction(session, choice, action)
	if result ~= true then
		return response(false, "That dialogue action could not be completed.", nil)
	end

	return response(true, "OK", {
		nextNodeId = action.nextNodeId or choice.nextNodeId,
		closeDialogue = action.type == "closeDialogue",
	})
end

function DialogueActionService:OnStart()
	if self._started then
		return
	end

	self._started = true
	self:_registerDefaultConditions()

	runActionRemote = ensureRemoteFunction(runActionRemote, RUN_ACTION_REMOTE_NAME)
	runActionRemote.OnServerInvoke = function(player: Player, payload: any)
		local allowed = RequestLimiter:Allow(player, "remote.dialogue.run_action")
		if not allowed then
			return response(false, "You're using dialogue too quickly.", nil)
		end

		return self:RunAction(player, payload)
	end
end

return DialogueActionService
