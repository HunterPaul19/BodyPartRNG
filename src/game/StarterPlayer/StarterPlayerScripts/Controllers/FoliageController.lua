local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

type FadeTarget = BasePart | Decal | Texture
type FadeState = {
	Targets: { FadeTarget },
	OriginalValues: { [FadeTarget]: number },
	DesiredFaded: boolean,
}

local FoliageController = {}

FoliageController.TagName = "Foliage"
FoliageController.FadeTransparency = 0.5
FoliageController.FadeDuration = 0.2
FoliageController.HorizontalFadeRadius = 4
FoliageController.QueryInterval = 0.05

local function warnf(message: string, ...)
	warn(string.format("[FoliageController] " .. message, ...))
end

local function getHorizontalDistanceToPart(part: BasePart, point: Vector3): number
	-- Measure distance against the part's XZ footprint so foliage can fade regardless of height offset.
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local halfSize = part.Size * 0.5
	local deltaX = math.max(math.abs(localPoint.X) - halfSize.X, 0)
	local deltaZ = math.max(math.abs(localPoint.Z) - halfSize.Z, 0)

	return math.sqrt(deltaX * deltaX + deltaZ * deltaZ)
end

local function collectFadeTargets(part: BasePart): { FadeTarget }
	local targets = { part :: FadeTarget }

	for _, descendant in ipairs(part:GetDescendants()) do
		if descendant:IsA("Decal") or descendant:IsA("Texture") then
			table.insert(targets, descendant)
		end
	end

	return targets
end

function FoliageController:_ensureState()
	if self._started then
		return
	end

	self._player = Players.LocalPlayer
	self._connections = {}
	self._characterConnections = {}
	self._trackedParts = {}
	self._fadeStates = {}
	self._character = nil
	self._rootPart = nil
	self._accumulator = 0
	self._fadeSpeed = self.FadeTransparency / self.FadeDuration
	self._started = true
end

function FoliageController:_disconnectCharacterConnections()
	for _, connection in ipairs(self._characterConnections) do
		connection:Disconnect()
	end

	self._characterConnections = {}
end

function FoliageController:_restoreFadeImmediately(part: BasePart)
	local fadeState: FadeState? = self._fadeStates[part]
	if not fadeState then
		return
	end

	self._fadeStates[part] = nil

	for _, target in ipairs(fadeState.Targets) do
		if target.Parent ~= nil then
			local originalValue = fadeState.OriginalValues[target]
			if originalValue ~= nil then
				target.LocalTransparencyModifier = originalValue
			end
		end
	end
end

function FoliageController:_setCharacter(character: Model?)
	self:_disconnectCharacterConnections()

	self._character = character
	self._rootPart = nil
	self._accumulator = 0

	if not character then
		return
	end

	self._rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?

	table.insert(self._characterConnections, character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") and descendant.Name == "HumanoidRootPart" then
			self._rootPart = descendant
		end
	end))
	table.insert(self._characterConnections, character.DescendantRemoving:Connect(function(descendant)
		if descendant == self._rootPart then
			self._rootPart = nil
		end
	end))
end

function FoliageController:_cacheCharacter(character: Model)
	self:_restoreAllFadesImmediately()
	self:_setCharacter(character)
end

function FoliageController:_getFadeState(part: BasePart): FadeState
	local fadeState: FadeState? = self._fadeStates[part]
	if fadeState then
		return fadeState
	end

	local targets = collectFadeTargets(part)
	local originalValues = {}

	for _, target in ipairs(targets) do
		originalValues[target] = target.LocalTransparencyModifier
	end

	fadeState = {
		Targets = targets,
		OriginalValues = originalValues,
		DesiredFaded = false,
	}

	self._fadeStates[part] = fadeState
	return fadeState
end

function FoliageController:_setDesiredFade(part: BasePart, shouldFade: boolean)
	self:_getFadeState(part).DesiredFaded = shouldFade
end

function FoliageController:_restoreAllFadesImmediately()
	local fadedParts = {}

	for part in pairs(self._fadeStates) do
		table.insert(fadedParts, part)
	end

	for _, part in ipairs(fadedParts) do
		self:_restoreFadeImmediately(part)
	end
end

function FoliageController:_trackTaggedPart(instance: Instance)
	if not instance:IsA("BasePart") then
		warnf("Ignoring tagged instance '%s' because only BasePart instances are supported.", instance:GetFullName())
		return
	end

	if self._trackedParts[instance] then
		return
	end

	self._trackedParts[instance] = true
end

function FoliageController:_untrackTaggedPart(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end

	if not self._trackedParts[instance] then
		return
	end

	self._trackedParts[instance] = nil

	local fadeState: FadeState? = self._fadeStates[instance]
	if fadeState then
		fadeState.DesiredFaded = false
	end
end

function FoliageController:_refreshTaggedParts()
	local activeParts = {}

	for _, instance in ipairs(CollectionService:GetTagged(self.TagName)) do
		if instance:IsA("BasePart") then
			activeParts[instance] = true
			self:_trackTaggedPart(instance)
		else
			warnf("Ignoring tagged instance '%s' because only BasePart instances are supported.", instance:GetFullName())
		end
	end

	for part in pairs(self._trackedParts) do
		if not activeParts[part] or part.Parent == nil then
			self:_untrackTaggedPart(part)
		end
	end
end

function FoliageController:_refreshDesiredFades()
	local rootPart = self._rootPart
	local rootPosition = rootPart and rootPart.Parent ~= nil and rootPart.Position or nil
	local nearbyParts = {}
	local staleParts = {}

	for part in pairs(self._trackedParts) do
		if part.Parent == nil then
			table.insert(staleParts, part)
		elseif rootPosition ~= nil then
			local horizontalDistance = getHorizontalDistanceToPart(part, rootPosition)
			if horizontalDistance <= self.HorizontalFadeRadius then
				nearbyParts[part] = true
			end
		end
	end

	for _, part in ipairs(staleParts) do
		self._trackedParts[part] = nil
	end

	for part, fadeState in pairs(self._fadeStates) do
		fadeState.DesiredFaded = nearbyParts[part] == true
	end

	for part in pairs(nearbyParts) do
		self:_setDesiredFade(part, true)
	end
end

function FoliageController:_updateFadeTargets(deltaTime: number)
	local completedParts = {}

	for part, fadeState in pairs(self._fadeStates) do
		if part.Parent == nil then
			table.insert(completedParts, part)
			continue
		end

		local isAtGoal = true

		for _, target in ipairs(fadeState.Targets) do
			if target.Parent == nil then
				continue
			end

			local originalValue = fadeState.OriginalValues[target]
			local targetValue = fadeState.DesiredFaded and math.max(originalValue, self.FadeTransparency) or originalValue
			local currentValue = target.LocalTransparencyModifier
			local delta = targetValue - currentValue

			if math.abs(delta) <= 0.001 then
				target.LocalTransparencyModifier = targetValue
				continue
			end

			local step = math.min(math.abs(delta), self._fadeSpeed * deltaTime)
			target.LocalTransparencyModifier = currentValue + if delta > 0 then step else -step

			if math.abs(target.LocalTransparencyModifier - targetValue) > 0.001 then
				isAtGoal = false
			end
		end

		if not fadeState.DesiredFaded and isAtGoal then
			table.insert(completedParts, part)
		end
	end

	for _, part in ipairs(completedParts) do
		local fadeState = self._fadeStates[part]
		if fadeState and not fadeState.DesiredFaded then
			self:_restoreFadeImmediately(part)
		else
			self._fadeStates[part] = nil
		end
	end
end

function FoliageController:_step(deltaTime: number)
	self._accumulator += deltaTime

	if self._accumulator >= self.QueryInterval then
		self._accumulator = 0

		if not self._character or self._character.Parent == nil then
			self:_restoreAllFadesImmediately()
			return
		end

		self:_refreshDesiredFades()
	end

	self:_updateFadeTargets(deltaTime)
end

function FoliageController:OnStart()
	self:_ensureState()
	self:_refreshTaggedParts()

	local player = self._player
	if not player then
		return
	end

	if player.Character then
		self:_cacheCharacter(player.Character)
	end

	table.insert(self._connections, player.CharacterAdded:Connect(function(character)
		self:_cacheCharacter(character)
	end))
	table.insert(self._connections, player.CharacterRemoving:Connect(function()
		self:_restoreAllFadesImmediately()
		self:_setCharacter(nil)
	end))
	table.insert(self._connections, CollectionService:GetInstanceAddedSignal(self.TagName):Connect(function(instance)
		self:_trackTaggedPart(instance)
	end))
	table.insert(self._connections, CollectionService:GetInstanceRemovedSignal(self.TagName):Connect(function(instance)
		self:_untrackTaggedPart(instance)
	end))
	table.insert(self._connections, RunService.Heartbeat:Connect(function(deltaTime: number)
		self:_step(deltaTime)
	end))
end

return FoliageController
