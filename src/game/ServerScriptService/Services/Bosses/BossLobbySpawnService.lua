local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local ACTIVE_PROFILE_ID = "boss_lobby"
local MAP_NAME = "ColosseumMap"
local SPAWNS_FOLDER_NAME = "Spawns"

local BossLobbySpawnService = {
	_started = false,
	_assignedSpawnByPlayer = {} :: { [Player]: SpawnLocation },
	_nextSpawnIndex = 0,
	_lastWarnedIssue = "",
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
end

local function warnOnce(service, issue: string)
	if service._lastWarnedIssue == issue then
		return
	end

	service._lastWarnedIssue = issue
	Logger.Warn(string.format("[BossLobbySpawnService] %s", issue))
end

local function getSpawnsFolder(): Folder?
	local map = Workspace:FindFirstChild(MAP_NAME)
	if map == nil then
		return nil
	end

	local spawns = map:FindFirstChild(SPAWNS_FOLDER_NAME)
	if spawns == nil or not spawns:IsA("Folder") then
		return nil
	end

	return spawns
end

local function compareSpawnLocations(left: SpawnLocation, right: SpawnLocation): boolean
	local leftName = left:GetFullName()
	local rightName = right:GetFullName()
	if leftName ~= rightName then
		return leftName < rightName
	end

	local leftPosition = left.Position
	local rightPosition = right.Position
	if leftPosition.X ~= rightPosition.X then
		return leftPosition.X < rightPosition.X
	end
	if leftPosition.Z ~= rightPosition.Z then
		return leftPosition.Z < rightPosition.Z
	end

	return leftPosition.Y < rightPosition.Y
end

function BossLobbySpawnService:_getValidSpawnLocations(): { SpawnLocation }
	local spawnsFolder = getSpawnsFolder()
	if spawnsFolder == nil then
		warnOnce(self, string.format("Missing Workspace.%s.%s.", MAP_NAME, SPAWNS_FOLDER_NAME))
		return {}
	end

	local spawnLocations = {}
	for _, child in ipairs(spawnsFolder:GetChildren()) do
		if child:IsA("SpawnLocation") and child.Enabled == true then
			table.insert(spawnLocations, child)
		end
	end

	table.sort(spawnLocations, compareSpawnLocations)

	if #spawnLocations <= 0 then
		warnOnce(self, string.format("Workspace.%s.%s has no enabled SpawnLocation children.", MAP_NAME, SPAWNS_FOLDER_NAME))
	end

	return spawnLocations
end

function BossLobbySpawnService:_isAssignedSpawnStillValid(spawnLocation: SpawnLocation?): boolean
	if spawnLocation == nil or spawnLocation.Parent == nil or spawnLocation.Enabled ~= true then
		return false
	end

	local spawnsFolder = getSpawnsFolder()
	return spawnsFolder ~= nil and spawnLocation.Parent == spawnsFolder
end

function BossLobbySpawnService:_assignPlayerSpawn(player: Player)
	if player.Parent ~= Players then
		return
	end

	local assignedSpawn = self._assignedSpawnByPlayer[player]
	if self:_isAssignedSpawnStillValid(assignedSpawn) then
		player.RespawnLocation = assignedSpawn
		return
	end

	local spawnLocations = self:_getValidSpawnLocations()
	if #spawnLocations <= 0 then
		return
	end

	self._nextSpawnIndex = (self._nextSpawnIndex % #spawnLocations) + 1
	assignedSpawn = spawnLocations[self._nextSpawnIndex]
	self._assignedSpawnByPlayer[player] = assignedSpawn
	player.RespawnLocation = assignedSpawn
end

function BossLobbySpawnService:OnStart()
	if self._started then
		return
	end

	self._started = true

	if not isEnabledForPlace() then
		return
	end

	for _, player in ipairs(Players:GetPlayers()) do
		self:_assignPlayerSpawn(player)
	end
end

function BossLobbySpawnService:OnPlayerAdded(player: Player)
	if not isEnabledForPlace() then
		return
	end

	self:_assignPlayerSpawn(player)
end

function BossLobbySpawnService:OnPlayerRemoving(player: Player)
	self._assignedSpawnByPlayer[player] = nil
end

return BossLobbySpawnService
