local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Combat.Constants)

local KnockbackNet = {}
local remoteCache = {}

local function ensureFolder(parent: Instance, childName: string): Folder
	local existing = parent:FindFirstChild(childName)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = childName
	folder.Parent = parent
	return folder
end

local function ensureRemoteEvent(parent: Instance, childName: string): RemoteEvent
	local existing = parent:FindFirstChild(childName)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = childName
	remote.Parent = parent
	return remote
end

local function getCombatRemotesFolder(): Folder
	if RunService:IsServer() then
		local remotesFolder = ensureFolder(ReplicatedStorage, Constants.REMOTES_FOLDER_NAME)
		return ensureFolder(remotesFolder, Constants.COMBAT_REMOTES_FOLDER_NAME)
	end

	local remotesFolder = ReplicatedStorage:WaitForChild(Constants.REMOTES_FOLDER_NAME, 30)
	assert(remotesFolder and remotesFolder:IsA("Folder"), "ReplicatedStorage.Remotes is missing.")

	local combatRemotesFolder = remotesFolder:WaitForChild(Constants.COMBAT_REMOTES_FOLDER_NAME, 30)
	assert(
		combatRemotesFolder and combatRemotesFolder:IsA("Folder"),
		"ReplicatedStorage.Remotes.CombatPhysics is missing."
	)

	return combatRemotesFolder
end

local function getRemote(name)
	if remoteCache[name] == nil then
		local combatRemotesFolder = getCombatRemotesFolder()
		if RunService:IsServer() then
			remoteCache[name] = ensureRemoteEvent(combatRemotesFolder, name)
		else
			local remote = combatRemotesFolder:WaitForChild(name, 30)
			assert(remote and remote:IsA("RemoteEvent"), string.format("Combat remote '%s' is missing.", name))
			remoteCache[name] = remote
		end
	end

	return remoteCache[name]
end

function KnockbackNet.getDispatchRemote()
	return getRemote(Constants.REMOTE_NAMES.KnockbackDispatch)
end

function KnockbackNet.getResultRemote()
	return getRemote(Constants.REMOTE_NAMES.KnockbackResult)
end

function KnockbackNet.getObserverDispatchRemote()
	return getRemote(Constants.REMOTE_NAMES.KnockbackObserverDispatch)
end

return KnockbackNet
