local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ObjectiveGuideConfig = require(ReplicatedStorage.Shared.Config.ObjectiveGuideConfig)

local LOCAL_PLAYER = Players.LocalPlayer
local GUIDE_FOLDER_NAME = "ObjectiveGuide"
local OBJECTIVE_FOLDER_PREFIX = "Objective_"
local BEAM_NAME = "Beam"
local BEAM_VISUAL_NAME = "TutorialBeam"
local BEAM_START_NAME = "BeamStart"
local BEAM_END_NAME = "BeamEnd"
local ATTACHMENT_NAME = "GuideAttachment"
local LEGACY_DIRECT_CHILD_NAMES = table.freeze({
	[BEAM_NAME] = true,
	[BEAM_VISUAL_NAME] = true,
	[BEAM_START_NAME] = true,
	[BEAM_END_NAME] = true,
})

type ObjectiveOptions = {
	arrivalRadius: number?,
	color: Color3?,
	fallbackTargetPath: string?,
	fallbackTargetPaths: { string }?,
	heightOffset: number?,
	beamWidth: number?,
	projectTargetToGround: boolean?,
}

type ActiveObjective = {
	id: string,
	target: any,
	options: ObjectiveOptions,
	folder: Folder?,
	beamPart: Part?,
	beamStartPart: Part?,
	beamEndPart: Part?,
	beamStartAttachment: Attachment?,
	beamEndAttachment: Attachment?,
	beam: Beam?,
	beamDefaultWidth0: number,
	beamDefaultWidth1: number,
}

local ObjectiveGuideController = {
	_started = false,
	_activeObjectives = {} :: { [string]: ActiveObjective },
	_renderConnection = nil :: RBXScriptConnection?,
	_folder = nil :: Folder?,
	_warnedKeys = {} :: { [string]: boolean },
}

local function warnOnce(self, key: string, message: string)
	if self._warnedKeys[key] == true then
		return
	end

	self._warnedKeys[key] = true
	Logger.Warn(message)
end

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value < math.huge and value > -math.huge
end

local function readPositiveNumber(value: any, fallback: number): number
	if isFiniteNumber(value) and value > 0 then
		return value
	end

	return fallback
end

local function sanitizeInstanceName(value: string): string
	return string.gsub(value, "[^%w_]", "_")
end

local function setPartVisual(part: Part, color: Color3, width: number, length: number, cframe: CFrame)
	part.Color = color
	part.Size = Vector3.new(width, ObjectiveGuideConfig.DefaultBeamThickness, math.max(0.1, length))
	part.CFrame = cframe
	part.Transparency = 0.18
end

local function createGuidePart(name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Transparency = 1
	part.Size = Vector3.new(1, ObjectiveGuideConfig.DefaultBeamThickness, 1)
	return part
end

local function createGuideAttachment(parent: BasePart): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = ATTACHMENT_NAME
	attachment.Parent = parent
	return attachment
end

local function resolveBeamTemplate(): Beam?
	local path = ObjectiveGuideConfig.BeamTemplatePath
	local current: Instance? = ReplicatedStorage
	for _, segment in ipairs(path) do
		if typeof(segment) ~= "string" or segment == "" or current == nil then
			return nil
		end
		current = current:FindFirstChild(segment)
	end

	return if current and current:IsA("Beam") then current else nil
end

local function setBeamColor(beam: Beam, color: Color3)
	beam.Color = ColorSequence.new(color)
end

local function setBeamVisual(beam: Beam, color: Color3, width0: number, width1: number)
	setBeamColor(beam, color)
	beam.Width0 = width0
	beam.Width1 = width1
	beam.Enabled = true
end

local function splitPath(path: string): { string }
	local segments = {}
	for segment in string.gmatch(path, "[^%.]+") do
		if segment ~= "game" and segment ~= "" then
			table.insert(segments, segment)
		end
	end
	return segments
end

local function resolveRoot(segment: string): Instance?
	if segment == "Workspace" or segment == "workspace" then
		return Workspace
	end
	if segment == "ReplicatedStorage" then
		return ReplicatedStorage
	end
	if segment == "LocalPlayer" then
		return LOCAL_PLAYER
	end

	return game:FindFirstChild(segment)
end

local function resolveInstancePath(path: string): Instance?
	local segments = splitPath(path)
	if #segments <= 0 then
		return nil
	end

	local current = resolveRoot(segments[1])
	for index = 2, #segments do
		if current == nil then
			return nil
		end
		current = current:FindFirstChild(segments[index])
	end

	return current
end

local function getCharacterRoot(): BasePart?
	local character = LOCAL_PLAYER.Character
	if not (character and character:IsA("Model")) then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.RootPart then
		return humanoid.RootPart
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function getCharacterTorso(): BasePart?
	local character = LOCAL_PLAYER.Character
	if not (character and character:IsA("Model")) then
		return nil
	end

	for _, partName in ipairs({ "UpperTorso", "Torso", "LowerTorso" }) do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			return part
		end
	end

	return getCharacterRoot()
end

local function findPositionSource(instance: Instance): Instance?
	if instance:IsA("BasePart") or instance:IsA("Attachment") then
		return instance
	end
	if instance:IsA("ProximityPrompt") and instance.Parent and instance.Parent:IsA("BasePart") then
		return instance.Parent
	end
	if instance:IsA("Model") then
		local root = instance:FindFirstChild("HumanoidRootPart", true)
		if root and root:IsA("BasePart") then
			return root
		end
		if instance.PrimaryPart then
			return instance.PrimaryPart
		end
		local part = instance:FindFirstChildWhichIsA("BasePart", true)
		if part then
			return part
		end
	end

	local current = instance.Parent
	while current do
		if current:IsA("BasePart") then
			return current
		end
		current = current.Parent
	end

	return nil
end

local function getInstancePosition(instance: Instance): Vector3?
	local source = findPositionSource(instance)
	if source == nil then
		return nil
	end
	if source:IsA("Attachment") then
		return source.WorldPosition
	end
	if source:IsA("BasePart") then
		return source.Position
	end

	return nil
end

local function getObjectiveColor(objective: ActiveObjective, targetInstance: Instance?): Color3
	if objective.options.color ~= nil then
		return objective.options.color :: Color3
	end

	local attributeName = ObjectiveGuideConfig.Attributes.Color
	local colorAttribute = targetInstance and targetInstance:GetAttribute(attributeName)
	if typeof(colorAttribute) == "Color3" then
		return colorAttribute
	end

	return ObjectiveGuideConfig.DefaultColor
end

local function getObjectiveRadius(objective: ActiveObjective, targetInstance: Instance?): number
	if objective.options.arrivalRadius ~= nil then
		return readPositiveNumber(objective.options.arrivalRadius, ObjectiveGuideConfig.DefaultArrivalRadius)
	end

	local radiusAttribute = targetInstance and targetInstance:GetAttribute(ObjectiveGuideConfig.Attributes.Radius)
	return readPositiveNumber(radiusAttribute, ObjectiveGuideConfig.DefaultArrivalRadius)
end

local function isTargetEnabled(targetInstance: Instance?): boolean
	if targetInstance == nil then
		return true
	end

	local enabled = targetInstance:GetAttribute(ObjectiveGuideConfig.Attributes.Enabled)
	return enabled ~= false
end

local function collectFallbackTargetPaths(options: ObjectiveOptions): { string }
	local paths = {}
	if typeof(options.fallbackTargetPath) == "string" and options.fallbackTargetPath ~= "" then
		table.insert(paths, options.fallbackTargetPath)
	end
	if typeof(options.fallbackTargetPaths) == "table" then
		for _, path in ipairs(options.fallbackTargetPaths) do
			if typeof(path) == "string" and path ~= "" then
				table.insert(paths, path)
			end
		end
	end
	return paths
end

function ObjectiveGuideController:_ensureRootFolder(): Folder
	if self._folder and self._folder.Parent == Workspace then
		return self._folder
	end

	local existing = Workspace:FindFirstChild(GUIDE_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		self._folder = existing
		return existing
	elseif existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = GUIDE_FOLDER_NAME
	folder.Parent = Workspace
	self._folder = folder
	return folder
end

function ObjectiveGuideController:_cleanupLegacyDirectChildren()
	local folder = self:_ensureRootFolder()
	for _, child in ipairs(folder:GetChildren()) do
		if LEGACY_DIRECT_CHILD_NAMES[child.Name] == true then
			child:Destroy()
		end
	end
end

function ObjectiveGuideController:_ensureBeam(objective: ActiveObjective)
	if objective.beam ~= nil and objective.beam.Parent ~= nil then
		return
	end

	if objective.folder == nil then
		return
	end

	local template = resolveBeamTemplate()
	if template == nil then
		warnOnce(
			self,
			"missingBeamTemplate",
			"[ObjectiveGuideController] ReplicatedStorage.Particles.TutorialBeam is missing or is not a Beam; using neon fallback."
		)
		return
	end

	local beam = template:Clone()
	beam.Name = BEAM_VISUAL_NAME
	beam.Attachment0 = objective.beamEndAttachment
	beam.Attachment1 = objective.beamStartAttachment
	beam.Enabled = false
	beam.Parent = objective.folder

	objective.beam = beam
	objective.beamDefaultWidth0 = readPositiveNumber(beam.Width0, ObjectiveGuideConfig.DefaultBeamWidth)
	objective.beamDefaultWidth1 = readPositiveNumber(beam.Width1, ObjectiveGuideConfig.DefaultBeamWidth)
end

function ObjectiveGuideController:_ensureParts(objective: ActiveObjective)
	if objective.folder and objective.folder.Parent == self:_ensureRootFolder() then
		if objective.beam == nil then
			self:_ensureBeam(objective)
		end
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = OBJECTIVE_FOLDER_PREFIX .. sanitizeInstanceName(objective.id)
	folder.Parent = self:_ensureRootFolder()

	local beamPart = createGuidePart(BEAM_NAME)
	beamPart.Parent = folder

	local beamStartPart = createGuidePart(BEAM_START_NAME)
	beamStartPart.Parent = folder

	local beamEndPart = createGuidePart(BEAM_END_NAME)
	beamEndPart.Parent = folder

	objective.folder = folder
	objective.beamPart = beamPart
	objective.beamStartPart = beamStartPart
	objective.beamEndPart = beamEndPart
	objective.beamStartAttachment = createGuideAttachment(beamStartPart)
	objective.beamEndAttachment = createGuideAttachment(beamEndPart)
	objective.beamDefaultWidth0 = ObjectiveGuideConfig.DefaultBeamWidth
	objective.beamDefaultWidth1 = ObjectiveGuideConfig.DefaultBeamWidth
	self:_ensureBeam(objective)
end

function ObjectiveGuideController:_hideParts(objective: ActiveObjective?)
	if objective == nil then
		for _, activeObjective in pairs(self._activeObjectives) do
			self:_hideParts(activeObjective)
		end
		return
	end

	if objective.beamPart then
		objective.beamPart.Transparency = 1
	end
	if objective.beam then
		objective.beam.Enabled = false
	end
end

function ObjectiveGuideController:_destroyObjective(objective: ActiveObjective)
	self:_hideParts(objective)
	if objective.folder then
		objective.folder:Destroy()
	end
end

function ObjectiveGuideController:_getRaycastParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter = {}
	if LOCAL_PLAYER.Character then
		table.insert(filter, LOCAL_PLAYER.Character)
	end
	if self._folder then
		table.insert(filter, self._folder)
	end
	params.FilterDescendantsInstances = filter
	return params
end

function ObjectiveGuideController:_projectToGround(position: Vector3, heightOffset: number): Vector3
	local origin = position + Vector3.new(0, ObjectiveGuideConfig.GroundRaycastUpOffset, 0)
	local direction = Vector3.new(0, -ObjectiveGuideConfig.GroundRaycastDownDistance, 0)
	local hit = Workspace:Raycast(origin, direction, self:_getRaycastParams())
	if hit then
		return hit.Position + Vector3.new(0, heightOffset, 0)
	end

	return Vector3.new(position.X, position.Y + heightOffset, position.Z)
end

function ObjectiveGuideController:_resolveTargetPosition(objective: ActiveObjective): (Vector3?, Instance?)
	local target = objective.target
	if typeof(target) == "Vector3" then
		return target, nil
	end
	if typeof(target) == "CFrame" then
		return target.Position, nil
	end
	if typeof(target) == "Instance" then
		return getInstancePosition(target), target
	end
	if typeof(target) == "string" then
		local resolved = resolveInstancePath(target)
		if resolved then
			return getInstancePosition(resolved), resolved
		end

		for _, fallbackPath in ipairs(collectFallbackTargetPaths(objective.options)) do
			local fallback = resolveInstancePath(fallbackPath)
			if fallback then
				warnOnce(self, "fallback:" .. target, string.format(
					"[ObjectiveGuideController] Target '%s' is missing; using fallback '%s'.",
					target,
					fallbackPath
				))
				return getInstancePosition(fallback), fallback
			end
		end

		warnOnce(self, "missing:" .. target, string.format("[ObjectiveGuideController] Target '%s' is missing.", target))
	end

	return nil, nil
end

function ObjectiveGuideController:_renderObjective(objective: ActiveObjective)
	self:_ensureParts(objective)

	local torsoPart = getCharacterTorso()
	if torsoPart == nil then
		self:_hideParts(objective)
		return
	end

	local targetPosition, targetInstance = self:_resolveTargetPosition(objective)
	if targetPosition == nil or not isTargetEnabled(targetInstance) then
		self:_hideParts(objective)
		return
	end

	local heightOffset = readPositiveNumber(objective.options.heightOffset, ObjectiveGuideConfig.DefaultHeightOffset)
	local projectTargetToGround = objective.options.projectTargetToGround ~= false
	local startPosition = torsoPart.Position
	local endPosition = if projectTargetToGround then self:_projectToGround(targetPosition, heightOffset) else targetPosition
	local offset = endPosition - startPosition
	local planarOffset = Vector3.new(offset.X, 0, offset.Z)
	local distance = planarOffset.Magnitude
	local arrivalRadius = getObjectiveRadius(objective, targetInstance)
	if distance <= math.max(arrivalRadius, ObjectiveGuideConfig.MinVisibleDistance) then
		self:_hideParts(objective)
		return
	end

	local forward = planarOffset.Unit
	local visibleLength = math.min(distance - arrivalRadius, ObjectiveGuideConfig.MaxBeamLength)
	if visibleLength <= ObjectiveGuideConfig.MinVisibleDistance then
		self:_hideParts(objective)
		return
	end

	local beamStart = startPosition + forward * 3
	local beamEnd = beamStart + forward * visibleLength
	if projectTargetToGround then
		beamEnd = Vector3.new(beamEnd.X, endPosition.Y, beamEnd.Z)
	else
		local targetOffset = endPosition - beamStart
		local targetPlanarDistance = Vector3.new(targetOffset.X, 0, targetOffset.Z).Magnitude
		if targetPlanarDistance > 0.1 then
			beamEnd = beamStart:Lerp(endPosition, math.clamp(visibleLength / targetPlanarDistance, 0, 1))
		end
	end
	local beamLength = (beamEnd - beamStart).Magnitude
	local color = getObjectiveColor(objective, targetInstance)
	local requestedBeamWidth = objective.options.beamWidth
	local beamWidth0 = objective.beamDefaultWidth0
	local beamWidth1 = objective.beamDefaultWidth1
	if requestedBeamWidth ~= nil then
		local beamWidth = readPositiveNumber(requestedBeamWidth, ObjectiveGuideConfig.DefaultBeamWidth)
		beamWidth0 = beamWidth
		beamWidth1 = beamWidth
	end

	if beamLength <= 0.1 then
		self:_hideParts(objective)
		return
	end

	local beam = objective.beam
	if beam ~= nil and objective.beamPart ~= nil and objective.beamStartPart ~= nil and objective.beamEndPart ~= nil then
		objective.beamPart.Transparency = 1
		objective.beamStartPart.CFrame = CFrame.new(beamStart)
		objective.beamEndPart.CFrame = CFrame.new(beamEnd)
		setBeamVisual(beam, color, beamWidth0, beamWidth1)
		return
	end

	if objective.beamPart == nil then
		return
	end

	local beamCenter = beamStart:Lerp(beamEnd, 0.5)
	setPartVisual(objective.beamPart, color, beamWidth0, beamLength, CFrame.lookAt(beamCenter, beamEnd))
end

function ObjectiveGuideController:_render()
	if next(self._activeObjectives) == nil then
		self:_hideParts()
		return
	end

	for _, objective in pairs(self._activeObjectives) do
		self:_renderObjective(objective)
	end
end

function ObjectiveGuideController:_startRenderLoop()
	if self._renderConnection then
		return
	end

	self._renderConnection = RunService.RenderStepped:Connect(function()
		self:_render()
	end)
end

function ObjectiveGuideController.ShowObjective(objectiveId: string, targetOrPosition: any, options: ObjectiveOptions?)
	if typeof(objectiveId) ~= "string" or objectiveId == "" then
		Logger.Warn("[ObjectiveGuideController] ShowObjective requires a non-empty objectiveId.")
		return false
	end
	if targetOrPosition == nil then
		Logger.Warn(string.format("[ObjectiveGuideController] ShowObjective('%s') requires a target.", objectiveId))
		return false
	end

	local objective = ObjectiveGuideController._activeObjectives[objectiveId]
	if objective then
		objective.target = targetOrPosition
		objective.options = options or {}
	else
		objective = {
			id = objectiveId,
			target = targetOrPosition,
			options = options or {},
			folder = nil,
			beamPart = nil,
			beamStartPart = nil,
			beamEndPart = nil,
			beamStartAttachment = nil,
			beamEndAttachment = nil,
			beam = nil,
			beamDefaultWidth0 = ObjectiveGuideConfig.DefaultBeamWidth,
			beamDefaultWidth1 = ObjectiveGuideConfig.DefaultBeamWidth,
		}
		ObjectiveGuideController._activeObjectives[objectiveId] = objective
	end

	ObjectiveGuideController:_startRenderLoop()
	return true
end

function ObjectiveGuideController.ShowTaggedObjective(objectiveId: string, options: ObjectiveOptions?)
	for _, instance in ipairs(CollectionService:GetTagged(ObjectiveGuideConfig.TargetTag)) do
		local targetId = instance:GetAttribute(ObjectiveGuideConfig.Attributes.Id)
		if targetId == objectiveId and isTargetEnabled(instance) then
			return ObjectiveGuideController.ShowObjective(objectiveId, instance, options)
		end
	end

	Logger.Warn(string.format(
		"[ObjectiveGuideController] No tagged objective target found for '%s' with tag '%s'.",
		tostring(objectiveId),
		ObjectiveGuideConfig.TargetTag
	))
	return false
end

function ObjectiveGuideController.ClearObjective(objectiveId: string?)
	ObjectiveGuideController:_cleanupLegacyDirectChildren()

	if objectiveId == nil then
		for id, objective in pairs(ObjectiveGuideController._activeObjectives) do
			ObjectiveGuideController:_destroyObjective(objective)
			ObjectiveGuideController._activeObjectives[id] = nil
		end
		return
	end

	local objective = ObjectiveGuideController._activeObjectives[objectiveId]
	if objective == nil then
		return
	end

	ObjectiveGuideController:_destroyObjective(objective)
	ObjectiveGuideController._activeObjectives[objectiveId] = nil
end

function ObjectiveGuideController.IsObjectiveActive(objectiveId: string): boolean
	return ObjectiveGuideController._activeObjectives[objectiveId] ~= nil
end

function ObjectiveGuideController:OnStart()
	if self._started then
		return
	end

	self._started = true
	self:_ensureRootFolder()
	self:_cleanupLegacyDirectChildren()
	self:_hideParts()
	self:_startRenderLoop()
end

return ObjectiveGuideController
