local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local combatPhysics = script.Parent
local Knockback = require(combatPhysics:WaitForChild("Knockback"))
local Ragdoll = require(combatPhysics:WaitForChild("Ragdoll"))
local KnockbackNet = require(combatPhysics:WaitForChild("Utilities"):WaitForChild("KnockbackNet"))

local dispatchRemote = KnockbackNet.getDispatchRemote()
local resultRemote = KnockbackNet.getResultRemote()

local DEBUG_DEFAULT = true
local SNAPSHOT_SEND_INTERVAL = 1 / 20
local END_RECONCILE_BLEND_TIME = 0.12
local PRE_SETTLE_DRIFT_WARN = 5
local VISUAL_FOLDER_NAME = "CombatPhysicsClientVisuals"
local DEFAULT_LANDED_DISABLE_RAGDOLL_DELAY = 2
local DEFAULT_LANDED_DISABLE_TIMEOUT_BUFFER = 0.75
local activeByID = {}
local activeByTarget = setmetatable({}, { __mode = "k" })

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
	Logger.Print("[CombatPhysics.ClientController][" .. label(character) .. "]", ...)
end

local function getVisualFolder()
	local folder = workspace:FindFirstChild(VISUAL_FOLDER_NAME)
	if folder then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = VISUAL_FOLDER_NAME
	folder.Parent = workspace
	return folder
end

local function sanitizeProxyCharacter(proxyCharacter)
	for _, desc in ipairs(proxyCharacter:GetDescendants()) do
		if desc:IsA("Script") or desc:IsA("LocalScript") or desc:IsA("ModuleScript") then
			desc:Destroy()
		elseif desc:IsA("Tool") then
			desc:Destroy()
		elseif desc:IsA("BasePart") then
			desc.CanCollide = false
			desc.CanTouch = false
			desc.CanQuery = false
			desc.CastShadow = false
		elseif desc:IsA("Humanoid") then
			desc.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			desc.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			desc.NameDisplayDistance = 0
		end
	end
end

local function hideRealCharacter(targetCharacter)
	local hidden = {}
	for _, desc in ipairs(targetCharacter:GetDescendants()) do
		if desc:IsA("BasePart") then
			hidden[desc] = desc.LocalTransparencyModifier
			desc.LocalTransparencyModifier = 1
		end
	end
	return hidden
end

local function restoreRealCharacter(hidden)
	for part, original in pairs(hidden or {}) do
		if part and part.Parent then
			part.LocalTransparencyModifier = original
		end
	end
end

local function buildObserverProxy(targetCharacter)
	local previousArchivable = targetCharacter.Archivable
	if not previousArchivable then
		targetCharacter.Archivable = true
	end

	local ok, cloned = pcall(function()
		return targetCharacter:Clone()
	end)
	targetCharacter.Archivable = previousArchivable
	if not ok or not cloned then
		return nil
	end

	cloned.Name = targetCharacter.Name .. "_ObserverProxy"
	sanitizeProxyCharacter(cloned)
	cloned.Parent = getVisualFolder()

	local ragdoll = Ragdoll.getOrCreate(cloned)
	if ragdoll then
		ragdoll:BuildRig()
	end
	log(targetCharacter, "Observer proxy built", "proxy", cloned:GetFullName())
	return cloned
end

local function waitForRagdollEnd(character, data)
	if character:GetAttribute("Ragdoll") ~= true then
		return true, 0
	end

	local knockbackType = data and data.__KnockbackType
	local landed = type(data) == "table" and data.Landed or nil
	local timeout = 5
	if type(landed) == "table" and type(landed.DisableRagdollTimeout) == "number" then
		timeout = math.max(0.5, landed.DisableRagdollTimeout + 0.25)
	elseif knockbackType == "Default" then
		local landedDelay = type(landed) == "table" and landed.DisableRagdollDelay or nil
		if typeof(landedDelay) ~= "number" then
			landedDelay = DEFAULT_LANDED_DISABLE_RAGDOLL_DELAY
		else
			landedDelay = math.max(0, landedDelay)
		end

		local delayTime = type(landed) == "table" and (landed.Delay or 0.2) or 0.15
		local moverDuration = tonumber(data.Duration) or tonumber(data.MoverDuration) or 0.25
		timeout = math.max(
			4,
			moverDuration + delayTime + landedDelay + DEFAULT_LANDED_DISABLE_TIMEOUT_BUFFER
		)
	elseif type(data.RagdollDuration) == "number" then
		timeout = math.max(1, data.RagdollDuration + 1)
	end

	local startWait = os.clock()
	while character.Parent ~= nil and character:GetAttribute("Ragdoll") == true and os.clock() - startWait < timeout do
		task.wait()
	end

	return character:GetAttribute("Ragdoll") ~= true, os.clock() - startWait
end

local function estimateTimeout(payloadData, maxDuration)
	if type(maxDuration) == "number" then
		return math.max(1.5, maxDuration + 0.75)
	end

	if type(payloadData) ~= "table" then
		return 6
	end

	local duration = tonumber(payloadData.Duration) or tonumber(payloadData.MoverDuration) or 0.25
	local ragdoll = tonumber(payloadData.RagdollDuration) or 0
	return math.clamp(duration + ragdoll + 5, 2, 14)
end

local function cleanupRecord(record, knockbackID, reason)
	restoreRealCharacter(record.hiddenParts)
	if record.proxyCharacter and record.proxyCharacter.Parent then
		record.proxyCharacter:Destroy()
	end
	log(record.character, "Stop", "id", knockbackID, "reason", reason)
end

local function shouldBlendOnStop(reason)
	return reason == "complete" or reason == "reconcile-reject" or reason == "server-stop"
end

local function stopRecord(knockbackID, reason)
	local record = activeByID[knockbackID]
	if not record then
		return
	end
	activeByID[knockbackID] = nil
	if activeByTarget[record.character] == record then
		activeByTarget[record.character] = nil
	end

	if record.isAuthority or not record.proxyCharacter or not record.proxyCharacter.Parent or not shouldBlendOnStop(reason) then
		cleanupRecord(record, knockbackID, reason)
		return
	end

	task.spawn(function()
		local proxyRoot = record.proxyCharacter and record.proxyCharacter:FindFirstChild("HumanoidRootPart")
		local targetCFrame = record.snapshotCFrame
		if proxyRoot and typeof(targetCFrame) == "CFrame" then
			local preSettleDrift = (proxyRoot.Position - targetCFrame.Position).Magnitude
			log(record.character, "Pre-settle drift", "id", knockbackID, "drift", preSettleDrift)
			if preSettleDrift > PRE_SETTLE_DRIFT_WARN then
				Logger.Warn("[CombatPhysics.ClientController] Pre-settle drift high", knockbackID, preSettleDrift)
			end

			local startCFrame = proxyRoot.CFrame
			local startTime = os.clock()
			while proxyRoot.Parent and os.clock() - startTime < END_RECONCILE_BLEND_TIME do
				local alpha = math.clamp((os.clock() - startTime) / END_RECONCILE_BLEND_TIME, 0, 1)
				proxyRoot.CFrame = startCFrame:Lerp(targetCFrame, alpha)
				RunService.Heartbeat:Wait()
			end
			if proxyRoot.Parent then
				proxyRoot.CFrame = targetCFrame
			end
		end
		cleanupRecord(record, knockbackID, reason)
	end)
end

local function startSnapshotLoop(record)
	task.spawn(function()
		local nextSend = 0
		while activeByID[record.id] == record do
			local character = record.character
			if not character or character.Parent == nil then
				break
			end

			local now = os.clock()
			if now >= nextSend then
				nextSend = now + SNAPSHOT_SEND_INTERVAL
				local rootPart = character:FindFirstChild("HumanoidRootPart")
				if rootPart then
					resultRemote:FireServer({
						Action = "Snapshot",
						KnockbackID = record.id,
						Character = character,
						RootCFrame = rootPart.CFrame,
						LinearVelocity = rootPart.AssemblyLinearVelocity,
						AngularVelocity = rootPart.AssemblyAngularVelocity,
						ClientTime = now,
					})
				end
			end
			task.wait()
		end
	end)
end

local function handleStart(payload)
	local character = payload.Character
	if not character or not character:IsA("Model") then
		return
	end

	local knockbackType = payload.KnockbackType
	local knockbackID = payload.KnockbackID
	if type(knockbackID) ~= "string" then
		return
	end

	stopRecord(knockbackID, "replace")
	local existingForTarget = activeByTarget[character]
	if existingForTarget then
		stopRecord(existingForTarget.id, "replace-target")
	end

	local payloadData = payload.Data or {}
	local authorityUserId = payload.AuthorityUserId
	local isAuthority = localPlayer ~= nil
		and typeof(authorityUserId) == "number"
		and authorityUserId == localPlayer.UserId
		and character == localPlayer.Character

	local data = table.clone(payloadData)
	data.__KnockbackType = knockbackType
	local simulationCharacter = character
	local proxyCharacter = nil
	local hiddenParts = nil

	if type(payload.GroundMode) == "string" then
		data.GroundMode = payload.GroundMode
	end

	if isAuthority then
		data.__ClientOwned = true
	else
		proxyCharacter = buildObserverProxy(character)
		if not proxyCharacter then
			Logger.Warn("[CombatPhysics.ClientController] Failed to create observer proxy", character:GetFullName())
			return
		end
		hiddenParts = hideRealCharacter(character)
		simulationCharacter = proxyCharacter
		data.__ObserverClient = true
		data.ObserverProxy = true
		data.PvPClientOwned = false

		local proxyRoot = simulationCharacter:FindFirstChild("HumanoidRootPart")
		if proxyRoot then
			local startRootCFrame = payload.StartRootCFrame
			local startLinearVelocity = payload.StartLinearVelocity
			local startAngularVelocity = payload.StartAngularVelocity
			if typeof(startRootCFrame) == "CFrame" then
				proxyRoot.CFrame = startRootCFrame
			end
			if typeof(startLinearVelocity) == "Vector3" then
				proxyRoot.AssemblyLinearVelocity = startLinearVelocity
			end
			if typeof(startAngularVelocity) == "Vector3" then
				proxyRoot.AssemblyAngularVelocity = startAngularVelocity
			end
		end
	end

	local record = {
		id = knockbackID,
		character = character,
		simulationCharacter = simulationCharacter,
		proxyCharacter = proxyCharacter,
		hiddenParts = hiddenParts,
		isAuthority = isAuthority,
		snapshotCFrame = nil,
		expiresAt = os.clock() + estimateTimeout(payloadData, payload.MaxDuration),
	}
	activeByID[knockbackID] = record
	activeByTarget[character] = record

	task.spawn(function()
		local ok, err = Knockback.ExecuteLocal(
			simulationCharacter,
			knockbackType,
			data,
			knockbackID,
			isAuthority and "RemoteDispatchAuthority" or "RemoteDispatchObserver"
		)

		if not ok then
			Logger.Warn("[CombatPhysics.ClientController] ExecuteLocal failed", knockbackType, err)
		end

		if isAuthority then
			local ragdollFinished = true
			if ok then
				ragdollFinished = waitForRagdollEnd(character, data)
			end

			local rootPart = character:FindFirstChild("HumanoidRootPart")
			resultRemote:FireServer({
				Action = "Complete",
				KnockbackID = knockbackID,
				Character = character,
				KnockbackType = knockbackType,
				Completed = ok,
				Error = ok and nil or tostring(err),
				FinalPosition = rootPart and rootPart.Position or nil,
				FinalVelocity = rootPart and rootPart.AssemblyLinearVelocity or nil,
				FinalCFrame = rootPart and rootPart.CFrame or nil,
				RagdollFinished = ragdollFinished,
				ClientTime = os.clock(),
			})
		end
	end)

	if isAuthority then
		startSnapshotLoop(record)
	end
end

local function handleSnapshot(payload)
	local knockbackID = payload.KnockbackID
	if type(knockbackID) ~= "string" then
		return
	end

	local record = activeByID[knockbackID]
	if not record or record.isAuthority then
		return
	end

	if payload.Character and payload.Character ~= record.character then
		return
	end

	if typeof(payload.RootCFrame) == "CFrame" then
		record.snapshotCFrame = payload.RootCFrame
	end
end

local function handleStop(payload)
	local knockbackID = payload.KnockbackID
	if type(knockbackID) ~= "string" then
		return
	end
	local record = activeByID[knockbackID]
	if record and typeof(payload.FinalRootCFrame) == "CFrame" then
		record.snapshotCFrame = payload.FinalRootCFrame
	end
	stopRecord(knockbackID, payload.Reason or "server-stop")
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for knockbackID, record in pairs(activeByID) do
		if now > record.expiresAt then
			stopRecord(knockbackID, "client-timeout")
		end
	end
end)

dispatchRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	local action = payload.Action or "Start"
	if action == "Start" then
		handleStart(payload)
	elseif action == "Snapshot" then
		handleSnapshot(payload)
	elseif action == "Stop" then
		handleStop(payload)
	end
end)

return true
