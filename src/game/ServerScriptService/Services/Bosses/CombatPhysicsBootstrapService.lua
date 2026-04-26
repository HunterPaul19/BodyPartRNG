local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Combat.Constants)

type PlayerCollisionConnections = {
	characterAdded: RBXScriptConnection?,
	characterDescendantAdded: RBXScriptConnection?,
}

local CombatPhysicsBootstrapService = {
	_playerConnections = {} :: { [Player]: PlayerCollisionConnections },
}

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

local function isCollisionGroupRegistered(groupName: string): boolean
	for _, collisionGroup in ipairs(PhysicsService:GetRegisteredCollisionGroups()) do
		if collisionGroup.name == groupName then
			return true
		end
	end

	return false
end

local function ensureCollisionGroup(groupName: string)
	if isCollisionGroupRegistered(groupName) then
		return
	end

	PhysicsService:RegisterCollisionGroup(groupName)
end

local function setCollidable(groupA: string, groupB: string, isCollidable: boolean)
	PhysicsService:CollisionGroupSetCollidable(groupA, groupB, isCollidable)
end

local function applyCollisionGroupToPart(instance: Instance, groupName: string)
	if not instance:IsA("BasePart") then
		return
	end

	instance.CollisionGroup = groupName
end

local function applyCollisionGroupToCharacter(character: Model, groupName: string)
	for _, descendant in ipairs(character:GetDescendants()) do
		applyCollisionGroupToPart(descendant, groupName)
	end
end

local function disconnectConnection(connection: RBXScriptConnection?)
	if connection ~= nil then
		connection:Disconnect()
	end
end

local function ensureRemotes()
	local remotesFolder = ensureFolder(ReplicatedStorage, Constants.REMOTES_FOLDER_NAME)
	local combatRemotesFolder = ensureFolder(remotesFolder, Constants.COMBAT_REMOTES_FOLDER_NAME)

	for _, remoteName in pairs(Constants.REMOTE_NAMES) do
		ensureRemoteEvent(combatRemotesFolder, remoteName)
	end
end

local function ensureCollisionGroups()
	local collisionGroups = Constants.COLLISION_GROUPS

	ensureCollisionGroup(collisionGroups.Player)
	ensureCollisionGroup(collisionGroups.BossBody)
	ensureCollisionGroup(collisionGroups.BodyPhysics)
	ensureCollisionGroup(collisionGroups.Hitbox)
	ensureCollisionGroup(collisionGroups.HitboxNoCollide)
	ensureCollisionGroup(collisionGroups.Ragdoll)

	setCollidable(collisionGroups.BossBody, "Default", true)
	setCollidable(collisionGroups.BossBody, collisionGroups.Player, false)
	setCollidable(collisionGroups.BossBody, collisionGroups.BodyPhysics, false)
	setCollidable(collisionGroups.BossBody, collisionGroups.Hitbox, true)
	setCollidable(collisionGroups.BossBody, collisionGroups.HitboxNoCollide, false)
	setCollidable(collisionGroups.BossBody, collisionGroups.Ragdoll, false)
	setCollidable(collisionGroups.BodyPhysics, collisionGroups.BodyPhysics, false)
	setCollidable(collisionGroups.BodyPhysics, collisionGroups.Hitbox, false)
	setCollidable(collisionGroups.BodyPhysics, collisionGroups.HitboxNoCollide, false)
	setCollidable(collisionGroups.BodyPhysics, collisionGroups.Ragdoll, false)
	setCollidable(collisionGroups.Hitbox, collisionGroups.Hitbox, false)
	setCollidable(collisionGroups.Hitbox, collisionGroups.HitboxNoCollide, false)
	setCollidable(collisionGroups.HitboxNoCollide, collisionGroups.HitboxNoCollide, false)
	setCollidable(collisionGroups.Ragdoll, collisionGroups.Ragdoll, false)
	setCollidable(collisionGroups.Ragdoll, collisionGroups.HitboxNoCollide, false)

	for _, externalGroupName in ipairs({ "Default", collisionGroups.Player }) do
		if isCollisionGroupRegistered(externalGroupName) then
			if externalGroupName == collisionGroups.Player then
				setCollidable(collisionGroups.BodyPhysics, externalGroupName, false)
				setCollidable(collisionGroups.HitboxNoCollide, externalGroupName, false)
				setCollidable(collisionGroups.Hitbox, externalGroupName, true)
				setCollidable(collisionGroups.Ragdoll, externalGroupName, true)
			else
				setCollidable(collisionGroups.BodyPhysics, externalGroupName, true)
				setCollidable(collisionGroups.HitboxNoCollide, externalGroupName, false)
				setCollidable(collisionGroups.Hitbox, externalGroupName, true)
				setCollidable(collisionGroups.Ragdoll, externalGroupName, true)
			end
		end
	end
end

function CombatPhysicsBootstrapService:_bindCharacter(player: Player, character: Model)
	local collisionGroups = Constants.COLLISION_GROUPS
	local connections = self._playerConnections[player]
	if connections == nil then
		connections = {}
		self._playerConnections[player] = connections
	end

	disconnectConnection(connections.characterDescendantAdded)
	applyCollisionGroupToCharacter(character, collisionGroups.Player)

	connections.characterDescendantAdded = character.DescendantAdded:Connect(function(descendant)
		applyCollisionGroupToPart(descendant, collisionGroups.Player)
	end)
end

function CombatPhysicsBootstrapService:_disconnectPlayer(player: Player)
	local connections = self._playerConnections[player]
	if connections == nil then
		return
	end

	disconnectConnection(connections.characterAdded)
	disconnectConnection(connections.characterDescendantAdded)

	self._playerConnections[player] = nil
end

function CombatPhysicsBootstrapService:OnStart()
	ensureRemotes()
	ensureCollisionGroups()
end

function CombatPhysicsBootstrapService:OnPlayerAdded(player: Player)
	self:_disconnectPlayer(player)

	local characterAddedConnection = player.CharacterAdded:Connect(function(character)
		self:_bindCharacter(player, character)
	end)

	self._playerConnections[player] = {
		characterAdded = characterAddedConnection,
		characterDescendantAdded = nil,
	}

	if player.Character then
		self:_bindCharacter(player, player.Character)
	end
end

function CombatPhysicsBootstrapService:OnPlayerRemoving(player: Player)
	self:_disconnectPlayer(player)
end

return CombatPhysicsBootstrapService
