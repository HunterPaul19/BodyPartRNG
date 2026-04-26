local StateUtil = {}

local activeStates = setmetatable({}, { __mode = "k" })
local movementTokens = setmetatable({}, { __mode = "k" })

local function getCharacterTable(store, character)
	local value = store[character]
	if not value then
		value = {}
		store[character] = value
	end
	return value
end

function StateUtil.getBuffMultiplier(character, buffName)
	if not character or not buffName then
		return 1
	end

	local direct = character:GetAttribute(buffName)
	if typeof(direct) == "number" then
		return direct
	end

	local withSuffix = character:GetAttribute(buffName .. "Multiplier")
	if typeof(withSuffix) == "number" then
		return withSuffix
	end

	local buffs = character:FindFirstChild("Buffs")
	if buffs then
		local buff = buffs:FindFirstChild(buffName)
		if buff and (buff:IsA("NumberValue") or buff:IsA("IntValue")) then
			return buff.Value
		end
	end

	return 1
end

function StateUtil.createState(character, stateName, duration)
	if not character or not stateName then
		return
	end

	local charStates = getCharacterTable(activeStates, character)
	charStates[stateName] = (charStates[stateName] or 0) + 1
	character:SetAttribute(stateName, true)

	if typeof(duration) == "number" and duration > 0 then
		task.delay(duration, function()
			StateUtil.removeState(character, stateName)
		end)
	end
end

function StateUtil.removeState(character, stateName)
	if not character or not stateName then
		return
	end

	local charStates = activeStates[character]
	if not charStates then
		character:SetAttribute(stateName, nil)
		return
	end

	local count = (charStates[stateName] or 0) - 1
	if count <= 0 then
		charStates[stateName] = nil
		character:SetAttribute(stateName, nil)
	else
		charStates[stateName] = count
	end
end

function StateUtil.createMovement(character, propertyName, propertyValue, duration)
	if not character or not propertyName then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local ok, originalValue = pcall(function()
		return humanoid[propertyName]
	end)
	if not ok then
		return
	end

	local tokenStore = getCharacterTable(movementTokens, character)
	local token = (tokenStore[propertyName] or 0) + 1
	tokenStore[propertyName] = token

	pcall(function()
		humanoid[propertyName] = propertyValue
	end)

	if typeof(duration) == "number" and duration > 0 then
		task.delay(duration, function()
			if humanoid.Parent == nil then
				return
			end
			if tokenStore[propertyName] ~= token then
				return
			end
			pcall(function()
				humanoid[propertyName] = originalValue
			end)
		end)
	end
end

return StateUtil
