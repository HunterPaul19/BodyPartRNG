local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PreviewAppearanceSnapshot = require(script.Parent.PreviewAppearanceSnapshot)

local PreviewAppearanceRegistry = {}

local rootFolder: Folder? = nil
local decodedByUserId: { [number]: any } = {}
local payloadByUserId: { [number]: string } = {}

local function getRootFolder(): Folder?
	if rootFolder and rootFolder.Parent == ReplicatedStorage then
		return rootFolder
	end

	local existing = ReplicatedStorage:FindFirstChild(PreviewAppearanceSnapshot.FolderName)
	if existing and existing:IsA("Folder") then
		rootFolder = existing
		return existing
	end

	return nil
end

local function readSnapshotPayload(folder: Folder): string
	local payload = folder:GetAttribute("Payload")
	if typeof(payload) == "string" then
		return payload
	end
	return ""
end

function PreviewAppearanceRegistry.GetSnapshotForUserId(userId: number?)
	local resolvedUserId = math.floor(tonumber(userId) or 0)
	if resolvedUserId <= 0 then
		return nil
	end

	local root = getRootFolder()
	if not root then
		return nil
	end

	local folder = root:FindFirstChild(tostring(resolvedUserId))
	if not (folder and folder:IsA("Folder")) then
		return nil
	end

	local payload = readSnapshotPayload(folder)
	if payload == "" then
		return nil
	end

	if payloadByUserId[resolvedUserId] ~= payload then
		payloadByUserId[resolvedUserId] = payload
		decodedByUserId[resolvedUserId] = PreviewAppearanceSnapshot.Decode(payload, resolvedUserId)
	end

	return decodedByUserId[resolvedUserId]
end

function PreviewAppearanceRegistry.GetSnapshotForPlayer(player: Player?)
	if not player then
		return nil
	end

	return PreviewAppearanceRegistry.GetSnapshotForUserId(player.UserId)
end

function PreviewAppearanceRegistry.GetLocalPlayerSnapshot()
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return nil
	end

	return PreviewAppearanceRegistry.GetSnapshotForUserId(localPlayer.UserId)
end

return table.freeze(PreviewAppearanceRegistry)
