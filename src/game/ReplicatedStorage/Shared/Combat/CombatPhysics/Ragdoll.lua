local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Combat.Constants)
local Trove = require(script.Parent.Utilities.Trove)
local StateUtil = require(script.Parent.Utilities.StateUtil)
local RaycastUtil = require(script.Parent.Utilities.RaycastUtil)

local Offsets = {
	["Right Shoulder"] = {
		CFrame.new(1.3, 0.75, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1),
		CFrame.new(-0.2, 0.75, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1),
	},
	["Right Hip"] = {
		CFrame.new(0.5, -1, 0, 0, 1, -0, -1, 0, 0, 0, 0, 1),
		CFrame.new(0, 1, 0, 0, 1, -0, -1, 0, 0, 0, 0, 1),
	},
	["Left Shoulder"] = {
		CFrame.new(-1.3, 0.75, 0, -1, 0, 0, 0, -1, 0, 0, 0, 1),
		CFrame.new(0.2, 0.75, 0, -1, 0, 0, 0, -1, 0, 0, 0, 1),
	},
	["Left Hip"] = {
		CFrame.new(-0.5, -1, 0, 0, 1, -0, -1, 0, 0, 0, 0, 1),
		CFrame.new(0, 1, 0, 0, 1, -0, -1, 0, 0, 0, 0, 1),
	},
}

local Ragdoll = {}
Ragdoll.__index = Ragdoll

local registry = setmetatable({}, { __mode = "k" })
local RAGDOLL_RECOVERY_LOCK_TIME = 0.2
local DEBUG_DEFAULT = true

local function shouldDebug(character)
	local workspaceDebug = workspace:GetAttribute("CombatPhysicsDebug")
	if workspaceDebug ~= nil then
		return workspaceDebug
	end

	if character then
		local charDebug = character:GetAttribute("CombatPhysicsDebug")
		if charDebug ~= nil then
			return charDebug
		end
	end

	return DEBUG_DEFAULT
end

local function label(character)
	if not character then
		return "nil"
	end

	local debugId = "?"
	local ok, id = pcall(function()
		return character:GetDebugId(0)
	end)
	if ok and id then
		debugId = id
	end

	return character:GetFullName() .. "|" .. debugId
end

local function log(character, ...)
	if not shouldDebug(character) then
		return
	end

	print("[CombatPhysics.Ragdoll][" .. label(character) .. "]", ...)
end

local function getFlatLookDirection(rootPart)
	local flat = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
	if flat.Magnitude <= 0.001 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

local function setNetworkOwner(rootPart, player, character)
	if not rootPart then
		log(character, "setNetworkOwner skipped: no rootPart")
		return
	end

	if RunService:IsClient() then
		log(character, "setNetworkOwner skipped: client context")
		return
	end

	local ok, err = pcall(function()
		rootPart:SetNetworkOwner(player)
	end)

	if ok then
		log(character, "SetNetworkOwner", player and player.Name or "Server")
	else
		warn("[CombatPhysics.Ragdoll] SetNetworkOwner failed:", err)
	end
end

local function settleCharacterForRecovery(character, rootPart, humanoid)
	for _, instance in ipairs(character:GetDescendants()) do
		if instance:IsA("BasePart") then
			instance.AssemblyLinearVelocity = Vector3.zero
			instance.AssemblyAngularVelocity = Vector3.zero
		end
	end

	local targetPosition = rootPart.Position
	local raycast = workspace:Raycast(
		rootPart.Position + Vector3.new(0, 5, 0),
		Vector3.new(0, -25, 0),
		RaycastUtil.getGroundParams(character)
	)

	if raycast then
		local minimumHeight = raycast.Position.Y + math.max(2.5, humanoid.HipHeight + 1)
		if targetPosition.Y < minimumHeight then
			targetPosition = Vector3.new(targetPosition.X, minimumHeight, targetPosition.Z)
		end
		log(character, "Recovery raycast hit", raycast.Instance and raycast.Instance:GetFullName() or "nil", "targetY", targetPosition.Y)
	else
		log(character, "Recovery raycast missed")
	end

	local flatLook = getFlatLookDirection(rootPart)
	rootPart.CFrame = CFrame.lookAt(targetPosition, targetPosition + flatLook)
end

local function createCollider(part1)
	local existing = part1:FindFirstChild("RagdollCollider")
	if existing and existing:IsA("BasePart") then
		return existing, false
	end

	local collider = Instance.new("Part")
	collider.Size = part1.Size / 2
	collider.Transparency = 1
	collider.CollisionGroup = part1.CollisionGroup
	collider.Name = "RagdollCollider"
	collider.CanCollide = true
	collider.Massless = true

	local noCollision = Instance.new("NoCollisionConstraint")
	noCollision.Part0 = part1
	noCollision.Part1 = collider
	noCollision.Parent = collider

	local weld = Instance.new("Weld")
	weld.Part0 = part1
	weld.Part1 = collider
	weld.Parent = collider

	collider.Parent = part1
	return collider, true
end

local function captureCollisionGroups(self)
	for _, instance in ipairs(self._character:GetDescendants()) do
		if instance:IsA("BasePart") and self._collisionGroupCache[instance] == nil then
			self._collisionGroupCache[instance] = instance.CollisionGroup
		end
	end
end

local function restoreCollisionGroups(self)
	for part, originalGroup in pairs(self._collisionGroupCache) do
		if part and part.Parent then
			pcall(function()
				part.CollisionGroup = originalGroup
			end)
		end
	end
	table.clear(self._collisionGroupCache)
end

function Ragdoll:getCharacter()
	return self._character
end

function Ragdoll:Disable(absolute)
	if not self._character then
		return
	end

	if self._state == "Disabled" then
		log(self._character, "Disable ignored: already disabled")
		return
	end

	if self._character:GetAttribute("Ai") then
		log(self._character, "Disable ignored: AI character")
		return
	end

	local player = Players:GetPlayerFromCharacter(self._character)
	local humanoid = self._character:FindFirstChildOfClass("Humanoid")
	local rootPart = self._character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart then
		warn("[CombatPhysics.Ragdoll] Disable missing humanoid/root", self._character:GetFullName(), humanoid ~= nil, rootPart ~= nil)
		return
	end

	if absolute then
		self._ragdollCache = 0
	else
		self._ragdollCache -= 1
	end
	log(self._character, "Disable requested", "absolute", absolute == true, "cache", self._ragdollCache)

	if self._ragdollCache > 0 then
		log(self._character, "Disable deferred: cache > 0")
		return
	end

	self._state = "Disabled"
	self._disableToken += 1
	local disableToken = self._disableToken

	self._character:SetAttribute("RagdollRecovering", true)
	self._trove:Destroy()
	self._trove = Trove.new()

	CollectionService:RemoveTag(self._character, "Ragdoll")

	local sockets = 0
	local motors = 0
	local weldsDestroyed = 0
	for _, instance in ipairs(self._character:GetDescendants()) do
		if instance:IsA("BallSocketConstraint") and instance.Name == "RagdollSocket" then
			instance.Enabled = false
			sockets += 1
		elseif instance:IsA("Weld") and instance.Name == "RagdollWeld" then
			instance:Destroy()
			weldsDestroyed += 1
		elseif instance:IsA("Motor6D") then
			instance.Enabled = true
			motors += 1
		end
	end
	restoreCollisionGroups(self)
	log(self._character, "Disable toggles", "socketsOff", sockets, "motorsOn", motors, "weldsDestroyed", weldsDestroyed)

	settleCharacterForRecovery(self._character, rootPart, humanoid)

	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
	humanoid.PlatformStand = false
	humanoid.AutoRotate = true
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

	StateUtil.removeState(self._character, "PlatformStand")
	StateUtil.removeState(self._character, "AutoRotate")
	setNetworkOwner(rootPart, nil, self._character)

	task.delay(RAGDOLL_RECOVERY_LOCK_TIME, function()
		if self._disableToken ~= disableToken then
			log(self._character, "Recovery cleanup skipped: stale disable token")
			return
		end
		if not self._character or self._character.Parent == nil then
			return
		end

		local currentHumanoid = self._character:FindFirstChildOfClass("Humanoid")
		local currentRoot = self._character:FindFirstChild("HumanoidRootPart")
		if currentRoot then
			currentRoot.AssemblyLinearVelocity = Vector3.zero
			currentRoot.AssemblyAngularVelocity = Vector3.zero
		end
		if currentHumanoid and currentHumanoid.Health > 0 then
			currentHumanoid.PlatformStand = false
			currentHumanoid.AutoRotate = true
			currentHumanoid:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)
		end
		if currentRoot then
			setNetworkOwner(currentRoot, player, self._character)
		end

		self._character:SetAttribute("Ragdoll", nil)
		self._character:SetAttribute("RagdollRecovering", nil)
		log(self._character, "Recovery cleanup complete")
	end)
end

function Ragdoll:Enable(attacker, duration)
	if not self._character then
		return
	end

	if self._character:GetAttribute("CannotRagdoll") or self._character:GetAttribute("Ai") then
		log(self._character, "Enable blocked", "CannotRagdoll", self._character:GetAttribute("CannotRagdoll"), "Ai", self._character:GetAttribute("Ai"))
		return
	end

	if duration then
		duration *= StateUtil.getBuffMultiplier(self._character, "RagdollReduction")
	end

	local player = Players:GetPlayerFromCharacter(self._character)
	local humanoid = self._character:FindFirstChildOfClass("Humanoid")
	local rootPart = self._character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart then
		warn("[CombatPhysics.Ragdoll] Enable missing humanoid/root", self._character:GetFullName(), humanoid ~= nil, rootPart ~= nil)
		return
	end

	self._ragdollCache += 1
	log(self._character, "Enable requested", "attacker", attacker and attacker.Name or "nil", "duration", duration or "nil", "cache", self._ragdollCache)

	if duration then
		task.delay(duration, function()
			self:Disable()
		end)
	end

	if self._ragdollCache > 1 then
		log(self._character, "Enable short-circuit: already active cache", self._ragdollCache)
		return
	end

	self._state = "Enabled"
	self._disableToken += 1

	self._character:SetAttribute("RagdollRecovering", nil)
	self._character:SetAttribute("Ragdoll", true)
	StateUtil.createState(self._character, "AutoRotate")
	StateUtil.createState(self._character, "PlatformStand")

	if not player then
		local attackerPlayer = Players:GetPlayerFromCharacter(attacker)
		if not attackerPlayer and #Players:GetPlayers() >= 1 then
			local players = Players:GetPlayers()
			attackerPlayer = players[math.random(1, #players)]
		end
		setNetworkOwner(rootPart, attackerPlayer, self._character)
	end

	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, true)
	humanoid.PlatformStand = true
	humanoid.AutoRotate = false
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	local lastEnforceLog = 0
	self._trove:Connect(RunService.Heartbeat, function()
		if self._state ~= "Enabled" then
			return
		end
		if not self._character or self._character.Parent == nil then
			return
		end

		local activeHumanoid = self._character:FindFirstChildOfClass("Humanoid")
		if not activeHumanoid or activeHumanoid.Health <= 0 then
			return
		end

		if not activeHumanoid.PlatformStand then
			activeHumanoid.PlatformStand = true
		end
		if activeHumanoid.AutoRotate then
			activeHumanoid.AutoRotate = false
		end
		if activeHumanoid:GetState() ~= Enum.HumanoidStateType.Physics then
			activeHumanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end

		if (not activeHumanoid.PlatformStand or activeHumanoid:GetState() ~= Enum.HumanoidStateType.Physics)
			and os.clock() - lastEnforceLog >= 0.25 then
			lastEnforceLog = os.clock()
			log(self._character, "State enforcement warning", "state", activeHumanoid:GetState().Name)
		end
	end)

	if not player then
		rootPart:ApplyAngularImpulse(Vector3.new(-90, 0, 0))
	end

	local torso = self._character:FindFirstChild("Torso") or self._character:FindFirstChild("UpperTorso")
	if torso then
		local rootWeld = Instance.new("Weld")
		rootWeld.Part0 = rootPart
		rootWeld.Part1 = torso
		rootWeld.Name = "RagdollWeld"
		rootWeld.Parent = rootPart
		log(self._character, "Root weld created", rootPart.Name, "->", torso.Name)
	else
		warn("[CombatPhysics.Ragdoll] No Torso/UpperTorso found for weld", self._character:GetFullName())
	end

	CollectionService:AddTag(self._character, "Ragdoll")
	captureCollisionGroups(self)

	local socketsOn = 0
	local motorsOff = 0
	local partsRagdollGroup = 0
	for _, instance in ipairs(self._character:GetDescendants()) do
		if instance:IsA("BallSocketConstraint") and instance.Name == "RagdollSocket" then
			instance.Enabled = true
			socketsOn += 1
		elseif instance:IsA("Motor6D") and instance.Name ~= "Neck" then
			instance.Enabled = false
			motorsOff += 1
		elseif instance:IsA("BasePart") then
			instance.CollisionGroup = Constants.COLLISION_GROUPS.Ragdoll
			partsRagdollGroup += 1
		end
	end
	log(self._character, "Enable toggles", "socketsOn", socketsOn, "motorsOff", motorsOff, "partsRagdoll", partsRagdollGroup)
end

function Ragdoll:BuildRig()
	if not self._character then
		return
	end

	local createdSockets = 0
	local existingSockets = 0
	local createdColliders = 0
	local missingJointParts = 0

	for _, joint in ipairs(self._character:GetDescendants()) do
		if joint:IsA("Motor6D") and joint.Name ~= "Neck" then
			if not joint.Part0 or not joint.Part1 then
				missingJointParts += 1
				warn("[CombatPhysics.Ragdoll] Motor6D missing Part0/Part1", self._character:GetFullName(), joint.Name)
				continue
			end

			if joint:FindFirstChild("RagdollSocket") then
				existingSockets += 1
				continue
			end

			local a0 = Instance.new("Attachment")
			a0.Parent = joint.Part0
			a0.CFrame = joint.C0
			a0.Name = "RagdollA0"

			local a1 = Instance.new("Attachment")
			a1.Parent = joint.Part1
			a1.CFrame = joint.C1
			a1.Name = "RagdollA1"

			if Offsets[joint.Name] then
				a0.CFrame = Offsets[joint.Name][1]
				a1.CFrame = Offsets[joint.Name][2]
			end

			local socket = Instance.new("BallSocketConstraint")
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.TwistLimitsEnabled = true
			socket.UpperAngle = 45
			socket.TwistLowerAngle = -45
			socket.TwistUpperAngle = 45
			socket.Name = "RagdollSocket"
			socket.Parent = joint
			socket.Enabled = false
			createdSockets += 1

			local _, created = createCollider(joint.Part1)
			if created then
				createdColliders += 1
			end
		end
	end

	log(self._character, "BuildRig summary", "createdSockets", createdSockets, "existingSockets", existingSockets, "createdColliders", createdColliders, "missingJointParts", missingJointParts)
end

function Ragdoll.new(character)
	if not character or not character:IsA("Model") then
		error("CombatPhysics.Ragdoll.new expects a Character Model")
	end

	local existing = registry[character]
	if existing then
		log(character, "Reusing existing Ragdoll instance")
		return existing
	end

	local self = setmetatable({
		_character = character,
		_state = "Disabled",
		_ragdollCache = 0,
		_disableToken = 0,
		_trove = Trove.new(),
		_collisionGroupCache = {},
	}, Ragdoll)

	self:BuildRig()
	registry[character] = self
	log(character, "Ragdoll instance created")
	return self
end

function Ragdoll.get(character)
	return registry[character]
end

function Ragdoll.getOrCreate(character)
	return registry[character] or Ragdoll.new(character)
end

return Ragdoll
