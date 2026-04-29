local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local StateUtil = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Utilities.StateUtil)
local DashStateRules = require(ReplicatedStorage.Shared.Combat.DashStateRules)

local REMOTES_FOLDER_NAME = "Remotes"
local DASH_FOLDER_NAME = "Dash"
local REQUEST_DASH_REMOTE_NAME = "RequestDash"
local DASH_STARTED_REMOTE_NAME = "DashStarted"

local FRONT_DASH_DURATION_SECONDS = 0.5
local BACK_DASH_DURATION_SECONDS = 0.5
local SIDE_DASH_DURATION_SECONDS = 0.25
local DASH_COOLDOWN_SECONDS = 0.1
local POST_DASH_STUN_SECONDS = 0.4
local RECENT_DAMAGE_LOCKOUT_SECONDS = 0.1

local VALID_DIRECTIONS = {
	Front = true,
	Back = true,
	Left = true,
	Right = true,
}

type CharacterHealthState = {
	character: Model?,
	humanoid: Humanoid?,
	previousHealth: number,
	restoring: boolean,
	connections: { RBXScriptConnection },
}

local remotesFolder: Folder? = nil
local dashFolder: Folder? = nil
local requestDashRemote: RemoteFunction? = nil
local dashStartedRemote: RemoteEvent? = nil

local cooldownEndsAtByPlayer: { [Player]: number } = {}
local characterStateByPlayer: { [Player]: CharacterHealthState } = {}

local DashService = {
	_started = false,
}

local function warnWithPrefix(message: string)
	Logger.Warn(string.format("[DashService] %s", message))
end

local function disconnectConnection(connection: RBXScriptConnection?)
	if connection and connection.Connected then
		connection:Disconnect()
	end
end

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

local function ensureDashFolder(): Folder
	local folder = ensureRemotesFolder()
	if dashFolder and dashFolder.Parent == folder then
		return dashFolder
	end

	local existing = folder:FindFirstChild(DASH_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		dashFolder = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local created = Instance.new("Folder")
	created.Name = DASH_FOLDER_NAME
	created.Parent = folder
	dashFolder = created
	return created
end

local function ensureRequestDashRemote(): RemoteFunction
	local folder = ensureDashFolder()
	if requestDashRemote and requestDashRemote.Parent == folder then
		return requestDashRemote
	end

	local existing = folder:FindFirstChild(REQUEST_DASH_REMOTE_NAME)
	if existing and existing:IsA("RemoteFunction") then
		requestDashRemote = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = REQUEST_DASH_REMOTE_NAME
	remote.Parent = folder
	requestDashRemote = remote
	return remote
end

local function ensureDashStartedRemote(): RemoteEvent
	local folder = ensureDashFolder()
	if dashStartedRemote and dashStartedRemote.Parent == folder then
		return dashStartedRemote
	end

	local existing = folder:FindFirstChild(DASH_STARTED_REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		dashStartedRemote = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = DASH_STARTED_REMOTE_NAME
	remote.Parent = folder
	dashStartedRemote = remote
	return remote
end

local function resolveHumanoid(character: Model?): Humanoid?
	if character == nil then
		return nil
	end

	return character:FindFirstChildOfClass("Humanoid")
end

local function resolveRootPart(character: Model?): BasePart?
	if character == nil then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end
	if character.PrimaryPart and character.PrimaryPart:IsA("BasePart") then
		return character.PrimaryPart
	end

	return nil
end

local function normalizeDirection(direction: any): string
	if typeof(direction) == "string" and VALID_DIRECTIONS[direction] == true then
		return direction
	end

	return "Front"
end

local function getDashDuration(direction: string): number
	if direction == "Left" or direction == "Right" then
		return SIDE_DASH_DURATION_SECONDS
	end
	if direction == "Back" then
		return BACK_DASH_DURATION_SECONDS
	end

	return FRONT_DASH_DURATION_SECONDS
end

local function getServerTime(): number
	return Workspace:GetServerTimeNow()
end

local function isRecentlyDamaged(character: Model): (boolean, number)
	local lastDamagedAt = character:GetAttribute("LastDamagedAtServerTime")
	if typeof(lastDamagedAt) ~= "number" then
		return false, 0
	end

	local elapsed = getServerTime() - lastDamagedAt
	if elapsed >= RECENT_DAMAGE_LOCKOUT_SECONDS then
		return false, 0
	end

	return true, RECENT_DAMAGE_LOCKOUT_SECONDS - elapsed
end

function DashService:_disconnectPlayerState(player: Player)
	local state = characterStateByPlayer[player]
	if state == nil then
		return
	end

	for _, connection in ipairs(state.connections) do
		disconnectConnection(connection)
	end

	characterStateByPlayer[player] = nil
end

function DashService:_bindHumanoid(player: Player, character: Model, humanoid: Humanoid)
	self:_disconnectPlayerState(player)

	local state: CharacterHealthState = {
		character = character,
		humanoid = humanoid,
		previousHealth = math.clamp(tonumber(humanoid.Health) or 0, 0, math.max(1, humanoid.MaxHealth)),
		restoring = false,
		connections = {},
	}
	characterStateByPlayer[player] = state

	table.insert(state.connections, humanoid.HealthChanged:Connect(function(newHealth: number)
		if state.humanoid ~= humanoid or state.character ~= character then
			return
		end

		local maxHealth = math.max(1, tonumber(humanoid.MaxHealth) or 1)
		local resolvedHealth = math.clamp(tonumber(newHealth) or 0, 0, maxHealth)

		if state.restoring then
			state.previousHealth = resolvedHealth
			return
		end

		if resolvedHealth < state.previousHealth then
			if character:GetAttribute("HardIFrames") == true then
				local restoreHealth = math.clamp(state.previousHealth, 0, maxHealth)
				if resolvedHealth < restoreHealth and humanoid.Parent ~= nil then
					state.restoring = true
					humanoid.Health = restoreHealth
					state.restoring = false
					state.previousHealth = restoreHealth
					return
				end
			end

			character:SetAttribute("LastDamagedAtServerTime", getServerTime())
		end

		state.previousHealth = math.clamp(tonumber(humanoid.Health) or resolvedHealth, 0, maxHealth)
	end))

	table.insert(state.connections, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		state.previousHealth = math.clamp(tonumber(humanoid.Health) or state.previousHealth, 0, math.max(1, humanoid.MaxHealth))
	end))
end

function DashService:_bindCharacter(player: Player, character: Model)
	self:_disconnectPlayerState(player)

	local humanoid = resolveHumanoid(character)
	if humanoid then
		self:_bindHumanoid(player, character, humanoid)
	end

	local state = characterStateByPlayer[player]
	if state == nil then
		state = {
			character = character,
			humanoid = nil,
			previousHealth = 0,
			restoring = false,
			connections = {},
		}
		characterStateByPlayer[player] = state
	end

	table.insert(state.connections, character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Humanoid") then
			self:_bindHumanoid(player, character, child)
		end
	end))
end

function DashService:_approveDash(player: Player, rawDirection: any): { [string]: any }
	local now = getServerTime()
	local cooldownEndsAt = cooldownEndsAtByPlayer[player]
	if cooldownEndsAt ~= nil and now < cooldownEndsAt then
		return {
			ok = false,
			code = "COOLDOWN",
			retryAfterSeconds = cooldownEndsAt - now,
		}
	end

	local character = player.Character
	local humanoid = resolveHumanoid(character)
	local rootPart = resolveRootPart(character)
	if character == nil or humanoid == nil or humanoid.Health <= 0 or rootPart == nil then
		return {
			ok = false,
			code = "NO_ALIVE_CHARACTER",
		}
	end

	local blocked, code = DashStateRules.GetBlockedState(character)
	if blocked then
		return {
			ok = false,
			code = code,
		}
	end

	local recentlyDamaged, retryAfterSeconds = isRecentlyDamaged(character)
	if recentlyDamaged then
		return {
			ok = false,
			code = "RECENTLY_DAMAGED",
			retryAfterSeconds = retryAfterSeconds,
		}
	end

	local direction = normalizeDirection(rawDirection)
	local durationSeconds = getDashDuration(direction)
	cooldownEndsAtByPlayer[player] = now + DASH_COOLDOWN_SECONDS

	StateUtil.createState(character, "Dashing", durationSeconds)
	StateUtil.createState(character, "HardIFrames", durationSeconds)

	task.delay(durationSeconds, function()
		if character.Parent == nil then
			return
		end

		StateUtil.createState(character, "DashStun", POST_DASH_STUN_SECONDS)
	end)

	ensureDashStartedRemote():FireAllClients({
		player = player,
		userId = player.UserId,
		direction = direction,
		durationSeconds = durationSeconds,
		serverStartedAt = now,
		position = rootPart.Position,
	})

	return {
		ok = true,
		direction = direction,
		durationSeconds = durationSeconds,
		serverStartedAt = now,
	}
end

function DashService:OnStart()
	if self._started then
		return
	end
	self._started = true

	local requestRemote = ensureRequestDashRemote()
	ensureDashStartedRemote()
	requestRemote.OnServerInvoke = function(player: Player, direction: any): { [string]: any }
		return self:_approveDash(player, direction)
	end

	Logger.Print("[DashService] Ready.")
end

function DashService:OnPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		self:_bindCharacter(player, character)
	end)

	player.CharacterRemoving:Connect(function()
		self:_disconnectPlayerState(player)
	end)

	if player.Character then
		self:_bindCharacter(player, player.Character)
	end
end

function DashService:OnPlayerRemoving(player: Player)
	self:_disconnectPlayerState(player)
	cooldownEndsAtByPlayer[player] = nil
end

return DashService
