local HttpService = game:GetService("HttpService")

local CollisionGroupOverrides = {}

local stateByCharacter = setmetatable({}, { __mode = "k" })

local function getBaseParts(character)
	local parts = {}
	for _, instance in ipairs(character:GetDescendants()) do
		if instance:IsA("BasePart") then
			table.insert(parts, instance)
		end
	end
	return parts
end

local function snapshotCollisionGroups(character)
	local snapshot = {}
	for _, part in ipairs(getBaseParts(character)) do
		snapshot[part] = part.CollisionGroup
	end
	return snapshot
end

local function restoreSnapshot(snapshot)
	for part, originalGroup in pairs(snapshot) do
		if part and part.Parent then
			pcall(function()
				part.CollisionGroup = originalGroup
			end)
		end
	end
end

local function applyGroup(character, groupName)
	for _, part in ipairs(getBaseParts(character)) do
		pcall(function()
			part.CollisionGroup = groupName
		end)
	end
end

local function getCharacterState(character)
	local state = stateByCharacter[character]
	if state then
		return state
	end

	state = {
		stack = {},
	}
	stateByCharacter[character] = state
	return state
end

function CollisionGroupOverrides.Push(character, groupName)
	if not character or not character:IsA("Model") or typeof(groupName) ~= "string" or groupName == "" then
		return nil
	end

	local state = getCharacterState(character)
	local frame = {
		token = HttpService:GenerateGUID(false),
		groupName = groupName,
		snapshot = snapshotCollisionGroups(character),
	}

	table.insert(state.stack, frame)
	applyGroup(character, groupName)
	return frame.token
end

function CollisionGroupOverrides.Pop(character, token)
	local state = stateByCharacter[character]
	if not state or not token then
		return false
	end

	local frameIndex = nil
	for index = #state.stack, 1, -1 do
		if state.stack[index].token == token then
			frameIndex = index
			break
		end
	end

	if not frameIndex then
		return false
	end

	local frame = state.stack[frameIndex]
	restoreSnapshot(frame.snapshot)
	table.remove(state.stack, frameIndex)

	for index = frameIndex, #state.stack do
		applyGroup(character, state.stack[index].groupName)
	end

	if #state.stack <= 0 then
		stateByCharacter[character] = nil
	end

	return true
end

function CollisionGroupOverrides.Clear(character)
	local state = stateByCharacter[character]
	if not state then
		return false
	end

	if state.stack[1] then
		restoreSnapshot(state.stack[1].snapshot)
	end

	stateByCharacter[character] = nil
	return true
end

return CollisionGroupOverrides
