local RaycastUtil = require(script.Parent.RaycastUtil)

local BodyMoverUtil = {}

local BODY_MOVER_CLASSES = {
	BodyVelocity = true,
	BodyPosition = true,
	BodyGyro = true,
	LinearVelocity = true,
	VectorForce = true,
	AlignPosition = true,
	AlignOrientation = true,
	Torque = true,
	AngularVelocity = true,
}

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
	print("[CombatPhysics.BodyMoverUtil][" .. label(character) .. "]", ...)
end

local function isBodyMover(instance)
	return BODY_MOVER_CLASSES[instance.ClassName] == true
end

local function appendExcludeList(baseList, extraList)
	if type(extraList) ~= "table" then
		return baseList
	end
	for _, instance in ipairs(extraList) do
		if typeof(instance) == "Instance" then
			table.insert(baseList, instance)
		end
	end
	return baseList
end

function BodyMoverUtil.clear(character)
	if not character then
		return
	end

	local removed = 0
	for _, descendant in ipairs(character:GetDescendants()) do
		if isBodyMover(descendant) then
			descendant:Destroy()
			removed += 1
		end
	end
	log(character, "Cleared bodymovers", removed)
end

function BodyMoverUtil.createVelocity(part, parent, angularForce)
	if not part then
		warn("[CombatPhysics.BodyMoverUtil] createVelocity missing part")
		return nil
	end

	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.one * 8e4
	bodyVelocity.Parent = parent or part

	if angularForce then
		part:ApplyAngularImpulse(angularForce)
	end

	log(part.Parent, "createVelocity", "parent", bodyVelocity.Parent and bodyVelocity.Parent.Name or "nil")
	return bodyVelocity
end

function BodyMoverUtil.createPosition(part, parent)
	if not part then
		warn("[CombatPhysics.BodyMoverUtil] createPosition missing part")
		return nil
	end

	local bodyPosition = Instance.new("BodyPosition")
	bodyPosition.MaxForce = Vector3.one * math.huge
	bodyPosition.Position = part.Position
	bodyPosition.P = 20000
	bodyPosition.Parent = parent or part

	log(part.Parent, "createPosition", "parent", bodyPosition.Parent and bodyPosition.Parent.Name or "nil")
	return bodyPosition
end

function BodyMoverUtil.createGyro(part, parent)
	if not part then
		warn("[CombatPhysics.BodyMoverUtil] createGyro missing part")
		return nil
	end

	local bodyGyro = Instance.new("BodyGyro")
	bodyGyro.P = 20000
	bodyGyro.MaxTorque = Vector3.one * 4e9
	bodyGyro.Parent = parent or part

	log(part.Parent, "createGyro", "parent", bodyGyro.Parent and bodyGyro.Parent.Name or "nil")
	return bodyGyro
end

function BodyMoverUtil.anticipateLand(character, distanceFromGround, onLand, timeout, options)
	if not character then
		warn("[CombatPhysics.BodyMoverUtil] anticipateLand missing character")
		return false
	end

	if character:GetAttribute("CannotAnticipate") then
		log(character, "anticipateLand blocked by CannotAnticipate")
		return false
	end

	options = type(options) == "table" and options or {}
	local groundMode = type(options.groundMode) == "string" and options.groundMode or "Default"

	local startTime = os.clock()
	local distance = math.max(1, distanceFromGround or 2)

	local groundParams
	if groundMode == "DeterministicMap" then
		groundParams = RaycastUtil.getDeterministicGroundParams({
			ignoreWater = options.ignoreWater,
			extraInclude = options.extraInclude,
		})
	else
		groundParams = RaycastUtil.getGroundParams(character)
		if groundParams.FilterType == Enum.RaycastFilterType.Exclude and type(options.extraExclude) == "table" then
			local merged = {}
			for _, existing in ipairs(groundParams.FilterDescendantsInstances) do
				table.insert(merged, existing)
			end
			appendExcludeList(merged, options.extraExclude)
			groundParams.FilterDescendantsInstances = merged
		end
	end

	log(
		character,
		"anticipateLand start",
		"distance",
		distance,
		"timeout",
		timeout or "nil",
		"groundMode",
		groundMode,
		"filterType",
		tostring(groundParams.FilterType)
	)

	while character.Parent ~= nil do
		if timeout and os.clock() - startTime >= timeout then
			log(character, "anticipateLand timeout", "elapsed", os.clock() - startTime)
			return false
		end

		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			warn("[CombatPhysics.BodyMoverUtil] anticipateLand missing HumanoidRootPart", character:GetFullName())
			return false
		end

		local result = workspace:Raycast(rootPart.Position, Vector3.new(0, -1, 0) * distance, groundParams)

		if result then
			log(character, "anticipateLand hit", result.Instance and result.Instance:GetFullName() or "nil", "y", result.Position.Y)
			if onLand then
				onLand(result)
			end
			return true
		end

		task.wait()
	end

	log(character, "anticipateLand ended: character removed")
	return false
end

return BodyMoverUtil
