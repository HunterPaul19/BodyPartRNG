local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local REMOTES_FOLDER_NAME = "Remotes"
local TELEPORT_TRANSITION_FOLDER_NAME = "TeleportTransition"
local PREPARE_REMOTE_NAME = "Prepare"
local DEFAULT_TRANSITION_TEXT = "Teleporting..."

type TeleportTransitionPayload = {
	text: string?,
	hide: boolean?,
}

local remotesFolder: Folder? = nil
local transitionFolder: Folder? = nil
local prepareRemote: RemoteEvent? = nil

local TeleportTransitionService = {
	_started = false,
}

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

local function ensureTransitionFolder(): Folder
	local folder = ensureRemotesFolder()
	if transitionFolder and transitionFolder.Parent == folder then
		return transitionFolder
	end

	local existing = folder:FindFirstChild(TELEPORT_TRANSITION_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		transitionFolder = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local createdFolder = Instance.new("Folder")
	createdFolder.Name = TELEPORT_TRANSITION_FOLDER_NAME
	createdFolder.Parent = folder
	transitionFolder = createdFolder
	return createdFolder
end

local function ensurePrepareRemote(): RemoteEvent
	local folder = ensureTransitionFolder()
	if prepareRemote and prepareRemote.Parent == folder then
		return prepareRemote
	end

	local existing = folder:FindFirstChild(PREPARE_REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		prepareRemote = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = PREPARE_REMOTE_NAME
	remote.Parent = folder
	prepareRemote = remote
	return remote
end

local function normalizePlayers(players: any): { Player }
	if typeof(players) == "Instance" and players:IsA("Player") then
		return { players }
	end

	local normalizedPlayers = {}
	if typeof(players) ~= "table" then
		return normalizedPlayers
	end

	for _, player in ipairs(players) do
		if typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players then
			table.insert(normalizedPlayers, player)
		end
	end

	return normalizedPlayers
end

local function normalizePayload(payload: TeleportTransitionPayload?): TeleportTransitionPayload
	local text = if typeof(payload) == "table" and typeof(payload.text) == "string" and payload.text ~= ""
		then payload.text
		else DEFAULT_TRANSITION_TEXT

	return {
		text = text,
	}
end

function TeleportTransitionService:PreparePlayers(players: any, payload: TeleportTransitionPayload?)
	local teleportPlayers = normalizePlayers(players)
	if #teleportPlayers <= 0 then
		return
	end

	local remote = ensurePrepareRemote()
	local normalizedPayload = normalizePayload(payload)

	for _, player in ipairs(teleportPlayers) do
		local ok, err = pcall(function()
			remote:FireClient(player, normalizedPayload)
		end)
		if not ok then
			Logger.Warn(string.format(
				"[TeleportTransitionService] Failed to prepare teleport screen for %s: %s",
				player.Name,
				tostring(err)
			))
		end
	end
end

function TeleportTransitionService:CancelPlayers(players: any)
	local teleportPlayers = normalizePlayers(players)
	if #teleportPlayers <= 0 then
		return
	end

	local remote = ensurePrepareRemote()
	for _, player in ipairs(teleportPlayers) do
		pcall(function()
			remote:FireClient(player, {
				hide = true,
			})
		end)
	end
end

function TeleportTransitionService:TeleportAsync(placeId: number, players: any, teleportOptions: TeleportOptions?)
	local teleportPlayers = normalizePlayers(players)
	self:PreparePlayers(teleportPlayers, {
		text = DEFAULT_TRANSITION_TEXT,
	})

	local teleportOk, teleportResult = pcall(function()
		if teleportOptions ~= nil then
			return TeleportService:TeleportAsync(placeId, teleportPlayers, teleportOptions)
		end

		return TeleportService:TeleportAsync(placeId, teleportPlayers)
	end)

	if not teleportOk then
		self:CancelPlayers(teleportPlayers)
		error(teleportResult, 2)
	end

	return teleportResult
end

function TeleportTransitionService:OnStart()
	if self._started then
		return
	end

	self._started = true
	ensurePrepareRemote()
end

return TeleportTransitionService
