local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Combat.Constants)
local StateUtil = require(script.Parent.Utilities.StateUtil)
local BodyMoverUtil = require(script.Parent.Utilities.BodyMoverUtil)
local CharacterPhysicsContext = require(script.Parent.Utilities.CharacterPhysicsContext)
local KnockbackNet = require(script.Parent.Utilities.KnockbackNet)
local Ragdoll = require(script.Parent.Ragdoll)
local KnockbackTypes = require(script.Parent.KnockbackTypes)

local DEBUG_DEFAULT = true
local SNAPSHOT_BROADCAST_MIN_INTERVAL = 1 / 30

local activeClientKnockbacks = {}
local resultListenerBound = false

local STRIP_CLIENT_KEYS = {
	KnockbackStart = true,
	KnockbackEnd = true,
	Callback = true,
	OnLand = true,
	__ClientHooks = true,
}

local ALLOWED_VALUE_TYPES = {
	number = true,
	string = true,
	boolean = true,
	Vector2 = true,
	Vector3 = true,
	CFrame = true,
	Color3 = true,
	BrickColor = true,
	UDim = true,
	UDim2 = true,
	NumberRange = true,
	NumberSequence = true,
	ColorSequence = true,
	Rect = true,
	EnumItem = true,
	Instance = true,
}

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
	print("[CombatPhysics.Knockback][" .. label(character) .. "]", ...)
end

local function cloneForClient(value, depth)
	depth = depth or 0
	if depth >= 8 then
		return nil
	end

	local valueType = typeof(value)
	if valueType == "table" then
		local out = {}
		for key, item in pairs(value) do
			if typeof(key) == "string" and STRIP_CLIENT_KEYS[key] then
				continue
			end
			local clonedKey = cloneForClient(key, depth + 1)
			local clonedItem = cloneForClient(item, depth + 1)
			if clonedKey ~= nil and clonedItem ~= nil then
				out[clonedKey] = clonedItem
			end
		end
		return out
	end

	if ALLOWED_VALUE_TYPES[valueType] then
		return value
	end

	return nil
end

local function resolvePlayer(candidate)
	if typeof(candidate) ~= "Instance" then
		return nil
	end
	if candidate:IsA("Player") then
		return candidate
	end
	if candidate:IsA("Model") then
		return Players:GetPlayerFromCharacter(candidate)
	end
	return nil
end

local function resolveAttackerPlayer(data)
	if type(data) ~= "table" then
		return nil
	end
	return resolvePlayer(data.Attacker) or resolvePlayer(data.NetworkOwner)
end

local function shouldUseVictimClient(targetPlayer, data)
	if not RunService:IsServer() then
		return false
	end
	if not targetPlayer then
		return false
	end
	if type(data) ~= "table" then
		return false
	end

	if data.PvPClientOwned ~= nil then
		return data.PvPClientOwned == true
	end

	local mode = data.AuthorityMode
	if mode == "Server" then
		return false
	end
	if mode == "VictimClient" or mode == "SharedClientSim" then
		return true
	end

	local attackerPlayer = resolveAttackerPlayer(data)
	if not attackerPlayer then
		return false
	end

	return attackerPlayer ~= targetPlayer
end

local function estimateEnvelope(knockbackType, data, startPosition)
	local duration = tonumber(data.Duration) or tonumber(data.MoverDuration) or 0.25
	local ragdollDuration = tonumber(data.RagdollDuration) or 0

	local maxDistance = 100
	local maxDuration = duration + ragdollDuration + 4

	if knockbackType == "Default" then
		local directionMagnitude = (typeof(data.Direction) == "Vector3" and data.Direction.Magnitude) or 120
		maxDistance = directionMagnitude * math.max(duration, 0.2) * 2 + 40
	elseif knockbackType == "Arc" then
		local dist = tonumber(data.Distance) or 70
		local height = tonumber(data.Height) or 80
		maxDistance = dist + height * 0.75 + 45
		maxDuration += 2
	elseif knockbackType == "Ground" then
		local force = tonumber(data.Force) or 40
		maxDistance = force * 3 + 45
	elseif knockbackType == "ToPoint" then
		if typeof(data.Position) == "Vector3" and typeof(startPosition) == "Vector3" then
			maxDistance = (data.Position - startPosition).Magnitude + 45
		else
			maxDistance = 140
		end
		maxDuration += 2
	end

	return math.clamp(maxDistance, 40, 650), math.clamp(maxDuration, 1.5, 12)
end

local function applyClientOwnedFallback(record, reason)
	local character = record.character
	if not character or character.Parent == nil then
		return
	end

	local context = CharacterPhysicsContext.fromCharacter(character)
	if not context then
		return
	end

	context.ragdoll = Ragdoll.getOrCreate(character)
	BodyMoverUtil.clear(character)
	context:setCollisionGroup(Constants.COLLISION_GROUPS.Hitbox)
	context:createState("AntiStunned", 0.4)
	context:createState("IFrames", 0.15)

	if context.ragdoll and character:GetAttribute("Ragdoll") then
		context.ragdoll:Disable(true)
	end

	log(character, "Client-owned fallback", "reason", reason, "id", record.id)
end

local function broadcastDispatch(payload, exceptPlayer)
	local dispatchRemote = KnockbackNet.getDispatchRemote()
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= exceptPlayer then
			dispatchRemote:FireClient(player, payload)
		end
	end
end

local function finalizeClientOwned(record, accepted, reason, finalRootCFrame)
	if not record then
		return
	end

	local resolvedFinalRoot = typeof(finalRootCFrame) == "CFrame" and finalRootCFrame or record.lastRootCFrame
	broadcastDispatch({
		Action = "Stop",
		Reason = reason,
		Accepted = accepted,
		KnockbackID = record.id,
		Character = record.character,
		KnockbackType = record.knockbackType,
		FinalRootCFrame = resolvedFinalRoot,
		ServerTime = os.clock(),
	})

	if accepted then
		local context = CharacterPhysicsContext.fromCharacter(record.character)
		if context then
			context:setCollisionGroup(Constants.COLLISION_GROUPS.Hitbox)
			local recordData = record.data or {}
			context:createState("IFrames", recordData.IFrames or (record.character:GetAttribute("Owner") and 1 or 0.2))
			context:createState("AntiStunned", recordData.AntiStun ~= nil and recordData.AntiStun or 0.6)
		end
	else
		applyClientOwnedFallback(record, reason)
	end

	activeClientKnockbacks[record.id] = nil
end

local function handleSnapshot(player, payload)
	local knockbackID = payload.KnockbackID
	if type(knockbackID) ~= "string" then
		return
	end

	local record = activeClientKnockbacks[knockbackID]
	if not record or player ~= record.player then
		return
	end

	local rootCFrame = payload.RootCFrame
	if typeof(rootCFrame) ~= "CFrame" then
		return
	end

	local now = os.clock()
	if record.lastSnapshotBroadcast and now - record.lastSnapshotBroadcast < SNAPSHOT_BROADCAST_MIN_INTERVAL then
		return
	end
	record.lastSnapshotBroadcast = now
	record.lastRootCFrame = rootCFrame

	broadcastDispatch({
		Action = "Snapshot",
		KnockbackID = knockbackID,
		Character = record.character,
		KnockbackType = record.knockbackType,
		RootCFrame = rootCFrame,
		LinearVelocity = typeof(payload.LinearVelocity) == "Vector3" and payload.LinearVelocity or nil,
		AngularVelocity = typeof(payload.AngularVelocity) == "Vector3" and payload.AngularVelocity or nil,
		ServerTime = now,
	}, player)
end

local function bindResultListener()
	if not RunService:IsServer() or resultListenerBound then
		return
	end
	resultListenerBound = true

	KnockbackNet.getResultRemote().OnServerEvent:Connect(function(player, payload)
		if typeof(payload) ~= "table" then
			return
		end

		if payload.Action == "Snapshot" then
			handleSnapshot(player, payload)
			return
		end

		local knockbackID = payload.KnockbackID
		if type(knockbackID) ~= "string" then
			return
		end

		local record = activeClientKnockbacks[knockbackID]
		if not record then
			return
		end

		if player ~= record.player then
			warn("[CombatPhysics.Knockback] Client-owned result rejected: player mismatch", knockbackID)
			finalizeClientOwned(record, false, "player-mismatch")
			return
		end

		local elapsed = os.clock() - record.startTime
		local finalPosition = payload.FinalPosition
		local positionDistance = math.huge
		if typeof(finalPosition) == "Vector3" then
			positionDistance = (finalPosition - record.startPosition).Magnitude
		end

		local completed = payload.Completed == true
		local ragdollFinished = payload.RagdollFinished ~= false
		local accepted = completed and ragdollFinished and elapsed <= record.maxDuration and positionDistance <= record.maxDistance

		local finalRootCFrame = typeof(payload.FinalCFrame) == "CFrame" and payload.FinalCFrame or record.lastRootCFrame
		finalizeClientOwned(record, accepted, accepted and "complete" or "reconcile-reject", finalRootCFrame)
	end)
end

if RunService:IsServer() then
	Players.PlayerRemoving:Connect(function(player)
		for _, record in pairs(activeClientKnockbacks) do
			if record.player == player then
				finalizeClientOwned(record, false, "target-left")
			end
		end
	end)
end

local function executeModule(character, requestedModule, data, knockbackID, sourceTag)
	local context = CharacterPhysicsContext.fromCharacter(character)
	if not context then
		warn("[CombatPhysics.Knockback] Failed to create CharacterPhysicsContext", character:GetFullName())
		return false, "NoContext"
	end

	context.ragdoll = Ragdoll.getOrCreate(character)
	if knockbackID then
		character:SetAttribute("KnockbackID", knockbackID)
	end

	log(character, "Executing", "source", sourceTag, "id", knockbackID)
	local ok, err = pcall(requestedModule, data, context, knockbackID)
	if not ok then
		warn("[CombatPhysics.Knockback] KnockbackType error", sourceTag, knockbackID, err)
	end
	return ok, err
end

local KnockbackApi = {}

local function invokeKnockback(character, knockbackType, data)
	if not character or not character:IsA("Model") then
		warn("[CombatPhysics.Knockback] Invalid character argument", character)
		return
	end

	local requestedModule = KnockbackTypes[knockbackType]
	if not requestedModule then
		warn("[CombatPhysics.Knockback] Unknown knockback type:", knockbackType)
		return
	end

	if character:GetAttribute("CannotKnockback") then
		return
	end

	data = data or {}
	if data.Direction then
		local multiplier = StateUtil.getBuffMultiplier(character, "KnockbackDefense")
		data.Direction *= multiplier
	end

	local knockbackID = HttpService:GenerateGUID(false)
	character:SetAttribute("KnockbackID", knockbackID)

	if RunService:IsServer() then
		bindResultListener()

		local targetPlayer = Players:GetPlayerFromCharacter(character)
		if shouldUseVictimClient(targetPlayer, data) then
			local context = CharacterPhysicsContext.fromCharacter(character)
			if not context then
				warn("[CombatPhysics.Knockback] Failed to create CharacterPhysicsContext", character:GetFullName())
				return
			end

			if data.Stun then
				context:createState("Stunned", data.Stun)
			end
			if data.CanDashM1 then
				local stateDuration = typeof(data.CanDashM1) == "number"
					and data.CanDashM1
					or ((data.RagdollDuration or data.Duration or 0.2) / 3)
				context:createState("DashM1_Ragdoll", stateDuration)
			end
			if character:GetAttribute("Owner") then
				context:createState("HardIFrames", (data.RagdollDuration or data.Duration or 0.2) + 2)
			end
			context:setCollisionGroup(Constants.COLLISION_GROUPS.HitboxNoCollide)

			local payloadData = cloneForClient(data) or {}
			payloadData.AuthorityMode = "SharedClientSim"
			payloadData.PvPClientOwned = true
			payloadData.NetworkOwner = character
			payloadData.GroundMode = payloadData.GroundMode or "DeterministicMap"

			local startRootCFrame = context.rootPart and context.rootPart.CFrame or nil
			local startLinearVelocity = context.rootPart and context.rootPart.AssemblyLinearVelocity or nil
			local startAngularVelocity = context.rootPart and context.rootPart.AssemblyAngularVelocity or nil

			local maxDistance, maxDuration = estimateEnvelope(
				knockbackType,
				payloadData,
				context.rootPart and context.rootPart.Position or nil
			)

			local record = {
				id = knockbackID,
				knockbackType = knockbackType,
				player = targetPlayer,
				character = character,
				startTime = os.clock(),
				startPosition = context.rootPart and context.rootPart.Position or Vector3.zero,
				maxDistance = maxDistance,
				maxDuration = maxDuration,
				data = payloadData,
				lastSnapshotBroadcast = 0,
				lastRootCFrame = context.rootPart and context.rootPart.CFrame or nil,
			}
			activeClientKnockbacks[knockbackID] = record

			KnockbackNet.getDispatchRemote():FireAllClients({
				Action = "Start",
				Character = character,
				KnockbackType = knockbackType,
				Data = payloadData,
				KnockbackID = knockbackID,
				AuthorityUserId = targetPlayer.UserId,
				GroundMode = payloadData.GroundMode,
				StartRootCFrame = startRootCFrame,
				StartLinearVelocity = startLinearVelocity,
				StartAngularVelocity = startAngularVelocity,
				MaxDuration = maxDuration,
				ServerTime = os.clock(),
			})

			task.delay(maxDuration + 0.35, function()
				local currentRecord = activeClientKnockbacks[knockbackID]
				if currentRecord then
					finalizeClientOwned(currentRecord, false, "result-timeout")
				end
			end)

			return
		end
	end

	task.spawn(function()
		executeModule(character, requestedModule, data, knockbackID, "Server")
	end)
end

function KnockbackApi.ExecuteLocal(character, knockbackType, data, knockbackID, sourceTag)
	if not character or not character:IsA("Model") then
		return false, "InvalidCharacter"
	end

	local requestedModule = KnockbackTypes[knockbackType]
	if not requestedModule then
		return false, "UnknownType"
	end

	data = data or {}
	return executeModule(character, requestedModule, data, knockbackID, sourceTag or "Client")
end

setmetatable(KnockbackApi, {
	__call = function(_, character, knockbackType, data)
		return invokeKnockback(character, knockbackType, data)
	end,
})

return KnockbackApi
