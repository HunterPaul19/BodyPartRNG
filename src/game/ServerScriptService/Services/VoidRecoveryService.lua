local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local VOID_Y_THRESHOLD = -1000
local RETURN_HEIGHT_ABOVE_SPAWN = 1000
local RECOVERY_COOLDOWN_SECONDS = 1.0

local MAIN_SPAWN_PATH = { "Map", "Spawns", "SpawnLocation" }

local recoveryCooldownUntilByPlayer: { [Player]: number } = {}
local heartbeatConnection: RBXScriptConnection? = nil

local VoidRecoveryService = {}

local function getSpawnLocation(): SpawnLocation?
	local current: Instance? = Workspace

	for _, childName in ipairs(MAIN_SPAWN_PATH) do
		if current == nil then
			break
		end

		current = current:FindFirstChild(childName)
	end

	if current and current:IsA("SpawnLocation") then
		return current
	end

	return Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
end

local function getRecoverableCharacterParts(character: Model): (Humanoid?, BasePart?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return nil, nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil, nil
	end

	return humanoid, root
end

local function buildRecoveryCFrame(characterPivot: CFrame, spawnPosition: Vector3): CFrame
	local rotationOnly = characterPivot - characterPivot.Position
	local recoveryPosition = spawnPosition + Vector3.new(0, RETURN_HEIGHT_ABOVE_SPAWN, 0)

	return CFrame.new(recoveryPosition) * rotationOnly
end

local function recoverCharacter(player: Player, character: Model)
	if (recoveryCooldownUntilByPlayer[player] or 0) > os.clock() then
		return
	end

	local _, root = getRecoverableCharacterParts(character)
	if root == nil then
		return
	end

	local spawnLocation = getSpawnLocation()
	if spawnLocation == nil then
		return
	end

	recoveryCooldownUntilByPlayer[player] = os.clock() + RECOVERY_COOLDOWN_SECONDS

	local linearVelocity = root.AssemblyLinearVelocity
	local targetCFrame = buildRecoveryCFrame(character:GetPivot(), spawnLocation.Position)

	character:PivotTo(targetCFrame)
	root.AssemblyLinearVelocity = linearVelocity
	root.AssemblyAngularVelocity = Vector3.zero
end

local function onHeartbeat()
	local now = os.clock()

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character == nil then
			continue
		end

		local cooldownUntil = recoveryCooldownUntilByPlayer[player]
		if cooldownUntil ~= nil and cooldownUntil > now then
			continue
		end

		local humanoid, root = getRecoverableCharacterParts(character)
		if humanoid == nil or root == nil then
			continue
		end

		if root.Position.Y < VOID_Y_THRESHOLD then
			recoverCharacter(player, character)
		end
	end
end

function VoidRecoveryService:OnStart()
	if heartbeatConnection ~= nil then
		return
	end

	heartbeatConnection = RunService.Heartbeat:Connect(onHeartbeat)
end

function VoidRecoveryService:OnPlayerRemoving(player: Player)
	recoveryCooldownUntilByPlayer[player] = nil
end

return VoidRecoveryService
