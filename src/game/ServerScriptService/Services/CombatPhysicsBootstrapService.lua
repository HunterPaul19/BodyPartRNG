local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Combat.Constants)

local CombatPhysicsBootstrapService = {}

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

local function ensureRemotes()
	local remotesFolder = ensureFolder(ReplicatedStorage, Constants.REMOTES_FOLDER_NAME)
	local combatRemotesFolder = ensureFolder(remotesFolder, Constants.COMBAT_REMOTES_FOLDER_NAME)

	for _, remoteName in pairs(Constants.REMOTE_NAMES) do
		ensureRemoteEvent(combatRemotesFolder, remoteName)
	end
end

local function ensureCollisionGroups()
	local collisionGroups = Constants.COLLISION_GROUPS

	ensureCollisionGroup(collisionGroups.BodyPhysics)
	ensureCollisionGroup(collisionGroups.Hitbox)
	ensureCollisionGroup(collisionGroups.HitboxNoCollide)
	ensureCollisionGroup(collisionGroups.Ragdoll)

	setCollidable(collisionGroups.BodyPhysics, collisionGroups.BodyPhysics, false)
	setCollidable(collisionGroups.BodyPhysics, collisionGroups.Hitbox, false)
	setCollidable(collisionGroups.BodyPhysics, collisionGroups.HitboxNoCollide, false)
	setCollidable(collisionGroups.BodyPhysics, collisionGroups.Ragdoll, false)
	setCollidable(collisionGroups.Hitbox, collisionGroups.Hitbox, false)
	setCollidable(collisionGroups.Hitbox, collisionGroups.HitboxNoCollide, false)
	setCollidable(collisionGroups.HitboxNoCollide, collisionGroups.HitboxNoCollide, false)
	setCollidable(collisionGroups.Ragdoll, collisionGroups.Ragdoll, false)
	setCollidable(collisionGroups.Ragdoll, collisionGroups.HitboxNoCollide, false)

	for _, externalGroupName in ipairs({ "Default", "Players" }) do
		if isCollisionGroupRegistered(externalGroupName) then
			if externalGroupName == "Players" then
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

function CombatPhysicsBootstrapService:OnStart()
	ensureRemotes()
	ensureCollisionGroups()
end

return CombatPhysicsBootstrapService
