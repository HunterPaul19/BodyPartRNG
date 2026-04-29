local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ObjectiveGuideConfig = require(ReplicatedStorage.Shared.Config.ObjectiveGuideConfig)

local LOCAL_PLAYER = Players.LocalPlayer
local GUIDE_FOLDER_NAME = "ObjectiveGuide"
local BEAM_NAME = "Beam"
local BEAM_VISUAL_NAME = "TutorialBeam"
local BEAM_START_NAME = "BeamStart"
local BEAM_END_NAME = "BeamEnd"
local ATTACHMENT_NAME = "GuideAttachment"

type ObjectiveOptions = {
	arrivalRadius: number?,
	color: Color3?,
	fallbackTargetPath: string?,
	heightOffset: number?,
	beamWidth: number?,
}

type ActiveObjective = {
	id: string,
	target: any,
	options: ObjectiveOptions,
}

local ObjectiveGuideController = {
	_started = false,
	_activeObjective = nil :: ActiveObjective?,
	_renderConnection = nil :: RBXScriptConnection?,
	_folder = nil :: Folder?,
	_beamPart = nil :: Part?,
	_beamStartPart = nil :: Part?,
	_beamEndPart = nil :: Part?,
	_beamStartAttachment = nil :: Attachment?,
	_beamEndAttachment = nil :: Attachment?,
	_beam = nil :: Beam?,
	_beamDefaultWidth0 = ObjectiveGuideConfig.DefaultBeamWidth,
	_beamDefaultWidth1 = ObjectiveGuideConfig.DefaultBeamWidth,
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

local function findPositionSource(instance: Instance): Instance?
	if instance:IsA("BasePart") or instance:IsA("Attachment") then
		return instance
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

function ObjectiveGuideController:_ensureParts()
	if self._folder and self._folder.Parent == Workspace then
		if self._beam == nil then
			self:_ensureBeam()
		end
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = GUIDE_FOLDER_NAME
	folder.Parent = Workspace

	local beamPart = createGuidePart(BEAM_NAME)
	beamPart.Parent = folder

	local beamStartPart = createGuidePart(BEAM_START_NAME)
	beamStartPart.Parent = folder

	local beamEndPart = createGuidePart(BEAM_END_NAME)
	beamEndPart.Parent = folder

	self._folder = folder
	self._beamPart = beamPart
	self._beamStartPart = beamStartPart
	self._beamEndPart = beamEndPart
	self._beamStartAttachment = createGuideAttachment(beamStartPart)
	self._beamEndAttachment = createGuideAttachment(beamEndPart)
	self:_ensureBeam()
end

function ObjectiveGuideController:_ensureBeam()
	if self._beam ~= nil and self._beam.Parent ~= nil then
		return
	end

	if self._folder == nil then
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
	beam.Attachment0 = self._beamEndAttachment
	beam.Attachment1 = self._beamStartAttachment
	beam.Enabled = false
	beam.Parent = self._folder

	self._beam = beam
	self._beamDefaultWidth0 = readPositiveNumber(beam.Width0, ObjectiveGuideConfig.DefaultBeamWidth)
	self._beamDefaultWidth1 = readPositiveNumber(beam.Width1, ObjectiveGuideConfig.DefaultBeamWidth)
end

function ObjectiveGuideController:_hideParts()
	if self._beamPart then
		self._beamPart.Transparency = 1
	end
	if self._beam then
		self._beam.Enabled = false
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

		local fallbackPath = objective.options.fallbackTargetPath
		if typeof(fallbackPath) == "string" and fallbackPath ~= "" then
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

function ObjectiveGuideController:_render()
	local objective = self._activeObjective
	if objective == nil then
		self:_hideParts()
		return
	end

	self:_ensureParts()

	local rootPart = getCharacterRoot()
	if rootPart == nil then
		self:_hideParts()
		return
	end

	local targetPosition, targetInstance = self:_resolveTargetPosition(objective)
	if targetPosition == nil or not isTargetEnabled(targetInstance) then
		self:_hideParts()
		return
	end

	local heightOffset = readPositiveNumber(objective.options.heightOffset, ObjectiveGuideConfig.DefaultHeightOffset)
	local startPosition = self:_projectToGround(rootPart.Position, heightOffset)
	local endPosition = self:_projectToGround(targetPosition, heightOffset)
	local offset = endPosition - startPosition
	local planarOffset = Vector3.new(offset.X, 0, offset.Z)
	local distance = planarOffset.Magnitude
	local arrivalRadius = getObjectiveRadius(objective, targetInstance)
	if distance <= math.max(arrivalRadius, ObjectiveGuideConfig.MinVisibleDistance) then
		self:_hideParts()
		return
	end

	local forward = planarOffset.Unit
	local visibleLength = math.min(distance - arrivalRadius, ObjectiveGuideConfig.MaxBeamLength)
	if visibleLength <= ObjectiveGuideConfig.MinVisibleDistance then
		self:_hideParts()
		return
	end

	local beamStart = startPosition + forward * 3
	local beamEnd = beamStart + forward * visibleLength
	local beamLength = (beamEnd - beamStart).Magnitude
	local color = getObjectiveColor(objective, targetInstance)
	local requestedBeamWidth = objective.options.beamWidth
	local beamWidth0 = self._beamDefaultWidth0
	local beamWidth1 = self._beamDefaultWidth1
	if requestedBeamWidth ~= nil then
		local beamWidth = readPositiveNumber(requestedBeamWidth, ObjectiveGuideConfig.DefaultBeamWidth)
		beamWidth0 = beamWidth
		beamWidth1 = beamWidth
	end

	if beamLength <= 0.1 then
		self:_hideParts()
		return
	end

	local beam = self._beam
	if beam ~= nil and self._beamPart ~= nil and self._beamStartPart ~= nil and self._beamEndPart ~= nil then
		self._beamPart.Transparency = 1
		self._beamStartPart.CFrame = CFrame.new(beamStart)
		self._beamEndPart.CFrame = CFrame.new(beamEnd)
		setBeamVisual(beam, color, beamWidth0, beamWidth1)
		return
	end

	local beamCenter = beamStart:Lerp(beamEnd, 0.5)
	setPartVisual(self._beamPart :: Part, color, beamWidth0, beamLength, CFrame.lookAt(beamCenter, beamEnd))
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

	ObjectiveGuideController._activeObjective = {
		id = objectiveId,
		target = targetOrPosition,
		options = options or {},
	}
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
	local activeObjective = ObjectiveGuideController._activeObjective
	if activeObjective == nil then
		ObjectiveGuideController:_hideParts()
		return
	end
	if objectiveId ~= nil and activeObjective.id ~= objectiveId then
		return
	end

	ObjectiveGuideController._activeObjective = nil
	ObjectiveGuideController:_hideParts()
end

function ObjectiveGuideController.IsObjectiveActive(objectiveId: string): boolean
	local activeObjective = ObjectiveGuideController._activeObjective
	return activeObjective ~= nil and activeObjective.id == objectiveId
end

function ObjectiveGuideController:OnStart()
	if self._started then
		return
	end

	self._started = true
	self:_ensureParts()
	self:_hideParts()
	self:_startRenderLoop()
end

return ObjectiveGuideController
