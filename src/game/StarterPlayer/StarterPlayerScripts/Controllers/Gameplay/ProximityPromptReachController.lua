local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local LOCAL_PLAYER = Players.LocalPlayer

local BASE_DISTANCE_ATTRIBUTE = "BodyPartRNGBaseActivationDistance"
local DISABLED_ATTRIBUTE = "BodyPartRNGDynamicActivationDistanceDisabled"
local CAP_ATTRIBUTE = "BodyPartRNGMaxActivationDistanceCap"

local NORMAL_CHARACTER_HEIGHT = 5.5
local SCALE_DISTANCE_WEIGHT = 0.5
local MIN_DISTANCE = 8
local MAX_DISTANCE = 32
local REFRESH_INTERVAL_SECONDS = 1

type PromptState = {
	prompt: ProximityPrompt,
	connections: { RBXScriptConnection },
}

local ProximityPromptReachController = {
	_started = false,
	_promptStates = {} :: { [ProximityPrompt]: PromptState },
	_connections = {} :: { RBXScriptConnection },
	_currentCharacter = nil :: Model?,
	_characterHeight = NORMAL_CHARACTER_HEIGHT,
}

local function disconnectAll(connections: { RBXScriptConnection })
	for _, connection in ipairs(connections) do
		if connection.Connected then
			connection:Disconnect()
		end
	end
end

local function readPositiveNumberAttribute(instance: Instance, attributeName: string): number?
	local value = instance:GetAttribute(attributeName)
	if typeof(value) ~= "number" or value <= 0 then
		return nil
	end

	return value
end

local function getPromptBaseDistance(prompt: ProximityPrompt): number
	local attributeDistance = readPositiveNumberAttribute(prompt, BASE_DISTANCE_ATTRIBUTE)
	if attributeDistance ~= nil then
		return attributeDistance
	end

	local currentDistance = math.max(0, tonumber(prompt.MaxActivationDistance) or 0)
	prompt:SetAttribute(BASE_DISTANCE_ATTRIBUTE, currentDistance)
	return currentDistance
end

local function getPromptDistanceCap(prompt: ProximityPrompt): number
	local promptCap = readPositiveNumberAttribute(prompt, CAP_ATTRIBUTE)
	if promptCap ~= nil then
		return promptCap
	end

	return MAX_DISTANCE
end

local function measureCharacterHeight(character: Model?): number?
	if character == nil or character.Parent == nil then
		return nil
	end

	local ok, extentsSize = pcall(function()
		return character:GetExtentsSize()
	end)
	if ok and typeof(extentsSize) == "Vector3" and extentsSize.Y > 0 then
		return extentsSize.Y
	end

	return nil
end

function ProximityPromptReachController:_computeSizeFactor(): number
	local characterHeight = math.max(0.1, self._characterHeight or NORMAL_CHARACTER_HEIGHT)
	local heightRatio = math.max(0.1, characterHeight / NORMAL_CHARACTER_HEIGHT)
	return math.max(heightRatio, 1 / heightRatio)
end

function ProximityPromptReachController:_resolveAdjustedDistance(prompt: ProximityPrompt): number
	local baseDistance = getPromptBaseDistance(prompt)
	local sizeFactor = self:_computeSizeFactor()
	local scaledDistance = baseDistance * (1 + ((sizeFactor - 1) * SCALE_DISTANCE_WEIGHT))
	local cap = math.max(MIN_DISTANCE, getPromptDistanceCap(prompt))
	return math.clamp(scaledDistance, MIN_DISTANCE, cap)
end

function ProximityPromptReachController:_applyPrompt(prompt: ProximityPrompt)
	if prompt.Parent == nil or not prompt:IsDescendantOf(Workspace) then
		return
	end

	if prompt:GetAttribute(DISABLED_ATTRIBUTE) == true then
		local baseDistance = readPositiveNumberAttribute(prompt, BASE_DISTANCE_ATTRIBUTE)
		if baseDistance ~= nil then
			prompt.MaxActivationDistance = baseDistance
		end
		return
	end

	prompt.MaxActivationDistance = self:_resolveAdjustedDistance(prompt)
end

function ProximityPromptReachController:_applyAllPrompts()
	for prompt in pairs(self._promptStates) do
		self:_applyPrompt(prompt)
	end
end

function ProximityPromptReachController:_updateCharacterHeight()
	local measuredHeight = measureCharacterHeight(self._currentCharacter)
	if measuredHeight ~= nil then
		self._characterHeight = measuredHeight
	else
		self._characterHeight = NORMAL_CHARACTER_HEIGHT
	end

	self:_applyAllPrompts()
end

function ProximityPromptReachController:_unregisterPrompt(prompt: ProximityPrompt)
	local state = self._promptStates[prompt]
	if state == nil then
		return
	end

	disconnectAll(state.connections)
	self._promptStates[prompt] = nil
end

function ProximityPromptReachController:_registerPrompt(instance: Instance)
	if not instance:IsA("ProximityPrompt") then
		return
	end

	local prompt = instance :: ProximityPrompt
	if self._promptStates[prompt] ~= nil then
		return
	end

	local state: PromptState = {
		prompt = prompt,
		connections = {},
	}
	self._promptStates[prompt] = state

	table.insert(state.connections, prompt.AncestryChanged:Connect(function()
		if prompt.Parent == nil or not prompt:IsDescendantOf(Workspace) then
			self:_unregisterPrompt(prompt)
		end
	end))
	table.insert(state.connections, prompt:GetAttributeChangedSignal(BASE_DISTANCE_ATTRIBUTE):Connect(function()
		self:_applyPrompt(prompt)
	end))
	table.insert(state.connections, prompt:GetAttributeChangedSignal(CAP_ATTRIBUTE):Connect(function()
		self:_applyPrompt(prompt)
	end))
	table.insert(state.connections, prompt:GetAttributeChangedSignal(DISABLED_ATTRIBUTE):Connect(function()
		self:_applyPrompt(prompt)
	end))

	self:_applyPrompt(prompt)
end

function ProximityPromptReachController:_scanWorkspace()
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		self:_registerPrompt(descendant)
	end
end

function ProximityPromptReachController:_bindCharacter(character: Model?)
	self._currentCharacter = character
	self:_updateCharacterHeight()
end

function ProximityPromptReachController:_startRefreshLoop()
	task.spawn(function()
		while self._started do
			self:_updateCharacterHeight()
			task.wait(REFRESH_INTERVAL_SECONDS)
		end
	end)
end

function ProximityPromptReachController:OnStart()
	if self._started then
		return
	end

	self._started = true
	self:_bindCharacter(LOCAL_PLAYER.Character)
	self:_scanWorkspace()

	table.insert(self._connections, LOCAL_PLAYER.CharacterAdded:Connect(function(character)
		self:_bindCharacter(character)
	end))
	table.insert(self._connections, LOCAL_PLAYER.CharacterRemoving:Connect(function(character)
		if self._currentCharacter == character then
			self:_bindCharacter(nil)
		end
	end))
	table.insert(self._connections, Workspace.DescendantAdded:Connect(function(descendant)
		self:_registerPrompt(descendant)
	end))

	self:_startRefreshLoop()
end

return ProximityPromptReachController
