type ActiveRecord = any
type PresentationEvent = any

local RunService = game:GetService("RunService")

local Constants = {
	ModuleIds = {
		CAT_MECH_ELITE_RAINBOW_BLAST_MODULE_ID = "Moves.CatMechElite.RainbowBlast",
	},
	Vfx = {
		CAT_MECH_ELITE_VFX_FOLDER_NAME = "CatMechElite",
		RAINBOW_BLAST_VFX_NAME = "RainbowBlast",
		RAINBOW_BLAST_RIGHT_HAND_MODEL_NAME = "Right Hand",
		RAINBOW_BLAST_ROOT_PART_MODEL_NAME = "RootPart",
		RAINBOW_BLAST_TARGET_ROOT_PART_MODEL_NAME = "TargetRootPart",
		RAINBOW_BLAST_BEAM_MODEL_NAME = "Beam",
		RAINBOW_BLAST_END_MODEL_NAME = "End",
	},
}

local CAT_MECH_ELITE_RAINBOW_BLAST_MODULE_ID = Constants.ModuleIds.CAT_MECH_ELITE_RAINBOW_BLAST_MODULE_ID
local CAT_MECH_ELITE_VFX_FOLDER_NAME = Constants.Vfx.CAT_MECH_ELITE_VFX_FOLDER_NAME
local RAINBOW_BLAST_BEAM_MODEL_NAME = Constants.Vfx.RAINBOW_BLAST_BEAM_MODEL_NAME
local RAINBOW_BLAST_END_MODEL_NAME = Constants.Vfx.RAINBOW_BLAST_END_MODEL_NAME
local RAINBOW_BLAST_RIGHT_HAND_MODEL_NAME = Constants.Vfx.RAINBOW_BLAST_RIGHT_HAND_MODEL_NAME
local RAINBOW_BLAST_ROOT_PART_MODEL_NAME = Constants.Vfx.RAINBOW_BLAST_ROOT_PART_MODEL_NAME
local RAINBOW_BLAST_TARGET_ROOT_PART_MODEL_NAME = Constants.Vfx.RAINBOW_BLAST_TARGET_ROOT_PART_MODEL_NAME
local RAINBOW_BLAST_VFX_NAME = Constants.Vfx.RAINBOW_BLAST_VFX_NAME
local TORSO_AIM_MAX_YAW_RADIANS = math.rad(70)
local TORSO_AIM_MAX_PITCH_RADIANS = math.rad(30)
local TORSO_AIM_RESPONSIVENESS = 12
local DEFAULT_BEAM_MAX_LENGTH_STUDS = 500

local Handler = {}

local function createVectorSpring(
	initialPosition: Vector3,
	dampingRatio: number,
	frequency: number,
	maxSpeedStudsPerSecond: number
)
	local self = {
		position = initialPosition,
		velocity = Vector3.zero,
		goal = initialPosition,
		dampingRatio = dampingRatio,
		frequency = frequency,
		maxSpeedStudsPerSecond = maxSpeedStudsPerSecond,
	}

	function self:SetGoal(goal: Vector3)
		self.goal = goal
	end

	function self:Step(dt: number): Vector3
		local clampedDt = math.clamp(dt, 0, 1 / 20)
		local previousPosition = self.position
		local angularFrequency = math.max(0.001, self.frequency) * 2 * math.pi
		local displacement = self.goal - self.position
		local acceleration = (displacement * angularFrequency * angularFrequency)
			- (self.velocity * 2 * self.dampingRatio * angularFrequency)

		self.velocity += acceleration * clampedDt
		self.position += self.velocity * clampedDt
		local movement = self.position - previousPosition
		local maxDistance = math.max(0, self.maxSpeedStudsPerSecond) * clampedDt
		if maxDistance > 0 and movement.Magnitude > maxDistance then
			self.position = previousPosition + (movement.Unit * maxDistance)
			self.velocity = if clampedDt > 0 then (self.position - previousPosition) / clampedDt else Vector3.zero
		end

		return self.position
	end

	return self
end

local function resolvePrimaryPart(model: Model?): BasePart?
	if model == nil then
		return nil
	end

	local primaryPart = model.PrimaryPart
	if primaryPart then
		return primaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function resolveNamedAttachment(root: Instance?, attachmentName: string): Attachment?
	if root == nil then
		return nil
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Attachment") and descendant.Name == attachmentName then
			return descendant
		end
	end

	return nil
end

local function setEmittableDescendantsEnabled(root: Instance, enabled: boolean)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") or descendant:IsA("Trail") then
			descendant.Enabled = enabled
		end
	end
end

local function resolveRainbowBlastWaistJoint(bossModel: Model?): Instance?
	if bossModel == nil then
		return nil
	end

	local upperTorso = bossModel:FindFirstChild("UpperTorso", true)
	if not (upperTorso and upperTorso:IsA("BasePart")) then
		return nil
	end

	local waist = upperTorso:FindFirstChild("Waist")
	if waist and (waist:IsA("Motor6D") or waist:IsA("AnimationConstraint")) then
		return waist
	end

	for _, descendant in ipairs(bossModel:GetDescendants()) do
		if descendant:IsA("Motor6D") and descendant.Name == "Waist" and descendant.Part1 == upperTorso then
			return descendant
		end

		if descendant:IsA("AnimationConstraint") and descendant.Name == "Waist" and descendant.Attachment1 ~= nil and descendant.Attachment1.Parent == upperTorso then
			return descendant
		end
	end

	return nil
end

local function resolveWaistJointParts(waist: Instance): (BasePart?, BasePart?)
	if waist:IsA("Motor6D") then
		return waist.Part0, waist.Part1
	end

	if waist:IsA("AnimationConstraint") then
		local attachment0 = waist.Attachment0
		local attachment1 = waist.Attachment1
		local part0 = if attachment0 and attachment0.Parent and attachment0.Parent:IsA("BasePart")
			then attachment0.Parent
			else nil
		local part1 = if attachment1 and attachment1.Parent and attachment1.Parent:IsA("BasePart")
			then attachment1.Parent
			else nil

		return part0, part1
	end

	return nil, nil
end

local function setWaistJointTransform(waist: Instance?, transform: CFrame)
	if waist == nil or waist.Parent == nil then
		return
	end

	if waist:IsA("Motor6D") or waist:IsA("AnimationConstraint") then
		waist.Transform = transform
	end
end

local function resolveTorsoAimTransform(waist: Instance, targetPosition: Vector3): CFrame
	local part0, part1 = resolveWaistJointParts(waist)
	if part0 == nil then
		return CFrame.identity
	end

	local originPart = part1 or part0
	local offset = targetPosition - originPart.Position
	if offset.Magnitude <= 0.001 then
		return CFrame.identity
	end

	local localDirection = part0.CFrame:VectorToObjectSpace(offset.Unit)
	local planarMagnitude = Vector3.new(localDirection.X, 0, localDirection.Z).Magnitude
	local yaw = math.clamp(math.atan2(-localDirection.X, -localDirection.Z), -TORSO_AIM_MAX_YAW_RADIANS, TORSO_AIM_MAX_YAW_RADIANS)
	local pitch = math.clamp(math.atan2(localDirection.Y, math.max(planarMagnitude, 0.001)), -TORSO_AIM_MAX_PITCH_RADIANS, TORSO_AIM_MAX_PITCH_RADIANS)

	return CFrame.Angles(pitch, yaw, 0)
end

local function resolveBeamVisualEndpoint(originPosition: Vector3, endpoint: Vector3, maxLengthStuds: number): (Vector3, Vector3)
	local offset = endpoint - originPosition
	local rawLength = offset.Magnitude
	local direction = if rawLength > 0.001 then offset.Unit else Vector3.new(0, 0, -1)
	local length = math.min(rawLength, math.max(0.1, maxLengthStuds))

	return originPosition + (direction * length), direction
end

local function resolveProjectedLookVector(axis: Vector3): Vector3
	local worldUp = Vector3.new(0, 1, 0)
	local projectedLook = worldUp - (axis * worldUp:Dot(axis))
	if projectedLook.Magnitude <= 0.001 then
		local worldRight = Vector3.new(1, 0, 0)
		projectedLook = worldRight - (axis * worldRight:Dot(axis))
	end

	if projectedLook.Magnitude <= 0.001 then
		return Vector3.new(0, 0, -1)
	end

	return projectedLook.Unit
end

local function pivotModelAttachmentToWorld(model: Model?, attachment: Attachment?, worldCFrame: CFrame)
	if model == nil or attachment == nil then
		return
	end

	local attachmentRelativeToPivot = model:GetPivot():ToObjectSpace(attachment.WorldCFrame)
	model:PivotTo(worldCFrame * attachmentRelativeToPivot:Inverse())
end

local function resolveBeamStartCFrame(originPosition: Vector3, direction: Vector3): CFrame
	local lookVector = resolveProjectedLookVector(direction)
	return CFrame.lookAt(originPosition, originPosition + lookVector, direction)
end

local function applyBeamCFrame(model: Model?, originPosition: Vector3, endpoint: Vector3, maxLengthStuds: number): (Vector3, Vector3)
	local clampedEndpoint, direction = resolveBeamVisualEndpoint(originPosition, endpoint, maxLengthStuds)
	local startAttachment = resolveNamedAttachment(model, "Start1")
	pivotModelAttachmentToWorld(model, startAttachment, resolveBeamStartCFrame(originPosition, direction))

	return clampedEndpoint, direction
end

local function applyBeamEndCFrame(model: Model?, endpoint: Vector3, direction: Vector3)
	local endAttachment = resolveNamedAttachment(model, "End2")
	pivotModelAttachmentToWorld(model, endAttachment, CFrame.lookAt(endpoint, endpoint + direction, resolveProjectedLookVector(direction)))
end

local function resolveTargetRootPartCFrame(endpoint: Vector3, originPosition: Vector3): CFrame
	local offset = endpoint - originPosition
	if offset.Magnitude <= 0.001 then
		return CFrame.new(endpoint)
	end

	local directionAwayFromBeamStart = offset.Unit
	return CFrame.lookAt(endpoint, endpoint + directionAwayFromBeamStart)
end

function Handler:_repairRainbowBlastBeamAttachments(record: ActiveRecord)
	local beamModel = record.rainbowBlastBeamModel
	local endModel = record.rainbowBlastEndModel
	if beamModel == nil or endModel == nil then
		return
	end

	local startAttachment = resolveNamedAttachment(beamModel, "Start1")
	local endAttachment = resolveNamedAttachment(endModel, "End2")
	if startAttachment == nil or endAttachment == nil then
		return
	end

	for _, descendant in ipairs(endModel:GetDescendants()) do
		if descendant:IsA("Beam") then
			descendant.Attachment0 = startAttachment
			descendant.Attachment1 = endAttachment
		end
	end
end

function Handler:_startRainbowBlastTorsoAim(record: ActiveRecord, bossModel: Model?, targetPosition: Vector3?)
	if typeof(targetPosition) ~= "Vector3" then
		return
	end

	local waist = resolveRainbowBlastWaistJoint(bossModel)
	if waist == nil then
		return
	end

	if record.rainbowBlastTorsoAim then
		if record.rainbowBlastTorsoAim.connection then
			record.rainbowBlastTorsoAim.connection:Disconnect()
		end
		setWaistJointTransform(record.rainbowBlastTorsoAim.waist, CFrame.identity)
	end

	setWaistJointTransform(waist, CFrame.identity)
	record.rainbowBlastTorsoAim = {
		waist = waist,
		currentTransform = CFrame.identity,
		goalPosition = targetPosition,
		lastUpdatedServerTime = nil,
	}
	record.rainbowBlastTorsoAim.connection = RunService.PreSimulation:Connect(function()
		if record.rainbowBlastTorsoAim == nil then
			return
		end

		self:_updateRainbowBlastTorsoAim(record, nil, self.Workspace:GetServerTimeNow())
	end)
	self:_updateRainbowBlastTorsoAim(record, targetPosition, self.Workspace:GetServerTimeNow())
end

function Handler:_updateRainbowBlastTorsoAim(record: ActiveRecord, targetPosition: Vector3?, nowServerTime: number)
	local aim = record.rainbowBlastTorsoAim
	if aim == nil then
		return
	end

	local waist = aim.waist
	if waist == nil or waist.Parent == nil then
		if aim.connection then
			aim.connection:Disconnect()
		end
		record.rainbowBlastTorsoAim = nil
		return
	end

	if typeof(targetPosition) == "Vector3" then
		aim.goalPosition = targetPosition
	end
	if typeof(aim.goalPosition) ~= "Vector3" then
		return
	end

	local lastUpdatedServerTime = if typeof(aim.lastUpdatedServerTime) == "number"
		then aim.lastUpdatedServerTime
		else nowServerTime
	local dt = math.clamp(nowServerTime - lastUpdatedServerTime, 0, 0.1)
	aim.lastUpdatedServerTime = nowServerTime

	local targetTransform = resolveTorsoAimTransform(waist, aim.goalPosition)
	local alpha = 1 - math.exp(-TORSO_AIM_RESPONSIVENESS * dt)
	aim.currentTransform = aim.currentTransform:Lerp(targetTransform, math.clamp(alpha, 0, 1))
	setWaistJointTransform(waist, aim.currentTransform)
end

function Handler:_startRainbowBlast(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local bossRightHand = self:resolveBossRightHandPart(bossModel)
	local bossRootPart = self:resolveBossRootPart(bossModel)
	if bossRightHand == nil or bossRootPart == nil then
		self:warnWithPrefix("Rainbow Blast presentation could not resolve the live boss RightHand/RootPart.")
		self:_cleanupRecord(record)
		return
	end

	local rightHandSource = self:resolveBossVfxModel(
		CAT_MECH_ELITE_VFX_FOLDER_NAME,
		RAINBOW_BLAST_VFX_NAME,
		RAINBOW_BLAST_RIGHT_HAND_MODEL_NAME
	)
	local rootPartSource = self:resolveBossVfxModel(
		CAT_MECH_ELITE_VFX_FOLDER_NAME,
		RAINBOW_BLAST_VFX_NAME,
		RAINBOW_BLAST_ROOT_PART_MODEL_NAME
	)
	local targetSource = self:resolveBossVfxModel(
		CAT_MECH_ELITE_VFX_FOLDER_NAME,
		RAINBOW_BLAST_VFX_NAME,
		RAINBOW_BLAST_TARGET_ROOT_PART_MODEL_NAME
	)
	if rightHandSource == nil or rootPartSource == nil then
		self:warnWithPrefix("Rainbow Blast Right Hand/RootPart VFX models are missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local payload = event.payload
	if typeof(payload) == "table" then
		self:_startRainbowBlastTorsoAim(record, bossModel, payload.initialAimPosition)
	end

	local scaleMultiplier = math.max(0.1, tonumber(payload and payload.scaleMultiplier) or 1)
	local castFolder = self:_ensureCastFolder(record)
	local rightHandModel = rightHandSource:Clone()
	local rootModel = rootPartSource:Clone()
	rightHandModel:ScaleTo(scaleMultiplier)
	rootModel:ScaleTo(scaleMultiplier)
	self:prepareAttachedEffectModel(rightHandModel)
	self:prepareAttachedEffectModel(rootModel)
	self:enableVfxDescendants(rightHandModel)
	self:enableVfxDescendants(rootModel)
	self:scaleAttachedSounds(rightHandModel, scaleMultiplier)
	self:scaleAttachedSounds(rootModel, scaleMultiplier)

	rightHandModel.Parent = castFolder
	rootModel.Parent = castFolder
	record.rightHandModel = rightHandModel
	record.rootModel = rootModel

	local initialAimPosition = if typeof(payload) == "table" then payload.initialAimPosition else nil
	local originPosition = if typeof(payload) == "table" then payload.originPosition else nil
	if typeof(originPosition) ~= "Vector3" then
		originPosition = bossRightHand.Position
	end

	if targetSource and typeof(initialAimPosition) == "Vector3" then
		local targetModel = targetSource:Clone()
		targetModel:ScaleTo(scaleMultiplier)
		self:prepareMovingEffectModel(targetModel)
		setEmittableDescendantsEnabled(targetModel, false)
		targetModel:PivotTo(resolveTargetRootPartCFrame(initialAimPosition, originPosition))
		targetModel.Parent = castFolder
		record.rainbowBlastTargetModel = targetModel

		local glintModel = targetSource:Clone()
		self:prepareAttachedEffectModel(glintModel)
		self:enableVfxDescendants(glintModel)

		local targetRootPart = self:resolvePlayerRootPartByUserId(if typeof(payload) == "table" then payload.targetUserId else nil)
		if targetRootPart and targetRootPart.Parent ~= nil then
			glintModel.Parent = targetRootPart
			if not self:attachEffectModel(glintModel, targetRootPart) then
				glintModel:PivotTo(CFrame.new(targetRootPart.Position))
			end
		else
			glintModel.Parent = castFolder
			glintModel:PivotTo(CFrame.new(initialAimPosition))
		end

		record.rainbowBlastPlayerGlintModel = glintModel
		self:emitEffectInstance(glintModel)
	end

	if not self:attachEffectModel(rightHandModel, bossRightHand) or not self:attachEffectModel(rootModel, bossRootPart) then
		self:warnWithPrefix("Rainbow Blast attached VFX models are missing BasePart configuration.")
		self:_cleanupRecord(record)
		return
	end

	self:playDelayedSoundClones(rightHandModel, castFolder, scaleMultiplier)
	self:playDelayedSoundClones(rootModel, castFolder, scaleMultiplier)
	self:emitEffectInstance(rightHandModel)
	self:emitEffectInstance(rootModel)
end

function Handler:_updateRainbowBlastBeam(record: ActiveRecord, nowServerTime: number)
	local motion = record.rainbowBlastBeamMotion
	if motion == nil then
		self:_updateRainbowBlastTorsoAim(record, nil, nowServerTime)
		return
	end

	local bossModel = record.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local originPart = self:resolveBossRightHandPart(bossModel) or self:resolveBossHeadPart(bossModel) or self:resolveBossRootPart(bossModel)
	if originPart == nil then
		self:_cleanupRecord(record)
		return
	end

	local dt = nowServerTime - motion.lastUpdatedServerTime
	motion.lastUpdatedServerTime = nowServerTime

	local targetRootPart = self:resolvePlayerRootPartByUserId(motion.targetUserId)
	if targetRootPart and targetRootPart.Parent ~= nil then
		motion.spring:SetGoal(targetRootPart.Position)
	end

	local endpoint = motion.spring:Step(dt)
	local originPosition = originPart.Position
	if record.rainbowBlastTargetModel then
		record.rainbowBlastTargetModel:PivotTo(resolveTargetRootPartCFrame(endpoint, originPosition))
	end
	local clampedEndpoint, direction = applyBeamCFrame(record.rainbowBlastBeamModel, originPosition, endpoint, motion.maxLengthStuds)
	applyBeamEndCFrame(record.rainbowBlastEndModel, clampedEndpoint, direction)
	self:_updateRainbowBlastTorsoAim(record, endpoint, nowServerTime)

	if nowServerTime - motion.startedAtServerTime >= motion.duration then
		self:_cleanupRecord(record)
	end
end

function Handler:_beamRainbowBlast(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" then
		return
	end

	local initialAimPosition = payload.initialAimPosition
	if typeof(initialAimPosition) ~= "Vector3" then
		initialAimPosition = payload.initialTargetPosition
	end
	if typeof(initialAimPosition) ~= "Vector3" then
		return
	end
	if record.rainbowBlastTorsoAim == nil then
		self:_startRainbowBlastTorsoAim(record, record.bossModel, initialAimPosition)
	end

	local beamSource = self:resolveBossVfxModel(
		CAT_MECH_ELITE_VFX_FOLDER_NAME,
		RAINBOW_BLAST_VFX_NAME,
		RAINBOW_BLAST_BEAM_MODEL_NAME
	)
	local endSource = self:resolveBossVfxModel(
		CAT_MECH_ELITE_VFX_FOLDER_NAME,
		RAINBOW_BLAST_VFX_NAME,
		RAINBOW_BLAST_END_MODEL_NAME
	)
	if beamSource == nil or endSource == nil then
		self:warnWithPrefix("Rainbow Blast beam/end VFX models are missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	local castFolder = self:_ensureCastFolder(record)
	local beamModel = beamSource:Clone()
	local endModel = endSource:Clone()
	beamModel:ScaleTo(scaleMultiplier)
	endModel:ScaleTo(scaleMultiplier)
	self:prepareMovingEffectModel(beamModel)
	self:prepareMovingEffectModel(endModel)
	self:enableVfxDescendants(beamModel)
	self:enableVfxDescendants(endModel)
	self:scaleAttachedSounds(beamModel, scaleMultiplier)
	self:scaleAttachedSounds(endModel, scaleMultiplier)

	beamModel.Parent = castFolder
	endModel.Parent = castFolder
	record.rainbowBlastBeamModel = beamModel
	record.rainbowBlastEndModel = endModel
	record.rainbowBlastBeamMotion = {
		targetUserId = math.floor(tonumber(payload.targetUserId) or 0),
		startedAtServerTime = if typeof(event.serverTime) == "number" then event.serverTime else self.Workspace:GetServerTimeNow(),
		lastUpdatedServerTime = if typeof(event.serverTime) == "number" then event.serverTime else self.Workspace:GetServerTimeNow(),
		duration = math.max(0.1, tonumber(payload.beamDurationSeconds) or 2),
		maxLengthStuds = math.max(0.1, tonumber(payload.beamMaxLengthStuds) or DEFAULT_BEAM_MAX_LENGTH_STUDS),
		spring = createVectorSpring(
			initialAimPosition,
			math.max(0, tonumber(payload.springDampingRatio) or 0.7),
			math.max(0.001, tonumber(payload.springFrequency) or 3),
			math.max(0, tonumber(payload.springMaxSpeedStudsPerSecond) or 45)
		),
	}

	self:_repairRainbowBlastBeamAttachments(record)
	self:playDelayedSoundClones(beamModel, castFolder, scaleMultiplier)
	self:playDelayedSoundClones(endModel, castFolder, scaleMultiplier)
	self:emitEffectInstance(beamModel)
	self:emitEffectInstance(endModel)
	self:_updateRainbowBlastBeam(record, self.Workspace:GetServerTimeNow())
end

Handler.moduleIds = {
	CAT_MECH_ELITE_RAINBOW_BLAST_MODULE_ID,
}
Handler.start = Handler._startRainbowBlast
Handler.update = Handler._updateRainbowBlastBeam
Handler.actions = {
	beam = Handler._beamRainbowBlast,
}
Handler.requiredParentFields = {
	"rightHandModel",
	"rootModel",
}
Handler.requiresHandle = false

return Handler
