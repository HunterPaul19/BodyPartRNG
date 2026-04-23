type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		WAVE_CRASH_MODULE_ID = "Moves.MerfinTheGreat.WaveCrash",
	},
	Vfx = {
		WAVE_CRASH_FORWARD_ATTACHMENT_NAME = "ForwardAttachment",
		MERFIN_THE_GREAT_VFX_FOLDER_NAME = "MerfinTheGreat",
		WAVE_CRASH_LEFT_HAND_MODEL_NAME = "LeftHand",
		WAVE_CRASH_RIGHT_HAND_MODEL_NAME = "RightHand",
		WAVE_CRASH_VFX_NAME = "WaveCrash",
		WAVE_CRASH_WAVE_MODEL_NAME = "Wave",
	},
}

local MERFIN_THE_GREAT_VFX_FOLDER_NAME = Constants.Vfx.MERFIN_THE_GREAT_VFX_FOLDER_NAME
local WAVE_CRASH_FORWARD_ATTACHMENT_NAME = Constants.Vfx.WAVE_CRASH_FORWARD_ATTACHMENT_NAME
local WAVE_CRASH_LEFT_HAND_MODEL_NAME = Constants.Vfx.WAVE_CRASH_LEFT_HAND_MODEL_NAME
local WAVE_CRASH_MODULE_ID = Constants.ModuleIds.WAVE_CRASH_MODULE_ID
local WAVE_CRASH_RIGHT_HAND_MODEL_NAME = Constants.Vfx.WAVE_CRASH_RIGHT_HAND_MODEL_NAME
local WAVE_CRASH_VFX_NAME = Constants.Vfx.WAVE_CRASH_VFX_NAME
local WAVE_CRASH_WAVE_MODEL_NAME = Constants.Vfx.WAVE_CRASH_WAVE_MODEL_NAME

local Handler = {}

local function resolvePlanarUnitVector(vector: Vector3): Vector3?
	local planarVector = Vector3.new(vector.X, 0, vector.Z)
	if planarVector.Magnitude <= 0.001 then
		return nil
	end

	return planarVector.Unit
end

local function resolveYawDelta(fromDirection: Vector3, toDirection: Vector3): number
	local dot = math.clamp(fromDirection:Dot(toDirection), -1, 1)
	local crossY = (fromDirection.Z * toDirection.X) - (fromDirection.X * toDirection.Z)
	return math.atan2(crossY, dot)
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

local function resolveAuthoredPlanarFacing(waveModel: Model, authoredPivot: CFrame): (Vector3?, string?)
	local forwardAttachment = resolveNamedAttachment(waveModel, WAVE_CRASH_FORWARD_ATTACHMENT_NAME)
	if forwardAttachment ~= nil then
		local forwardAttachmentFacing = resolvePlanarUnitVector(forwardAttachment.WorldPosition - authoredPivot.Position)
		if forwardAttachmentFacing ~= nil then
			return forwardAttachmentFacing, WAVE_CRASH_FORWARD_ATTACHMENT_NAME
		end
	end

	local pivotFacing = resolvePlanarUnitVector(authoredPivot.RightVector)
	if pivotFacing ~= nil then
		return pivotFacing, "pivot RightVector"
	end

	return nil, nil
end

local function buildWaveVisualCFrame(
	position: Vector3,
	planarDirection: Vector3,
	authoredRotation: CFrame,
	authoredPlanarFacing: Vector3?
): CFrame
	local targetPlanarDirection = resolvePlanarUnitVector(planarDirection)
	if targetPlanarDirection == nil or authoredPlanarFacing == nil then
		return CFrame.new(position) * authoredRotation
	end

	local yawDelta = resolveYawDelta(authoredPlanarFacing, targetPlanarDirection)
	return CFrame.new(position) * CFrame.Angles(0, yawDelta, 0) * authoredRotation
end

function Handler:_updateWaveCrashMotion(record: ActiveRecord, nowServerTime: number)
	local waveModel = record.waveModel
	local waveMotion = record.waveMotion
	if waveModel == nil or waveMotion == nil or waveModel.Parent == nil then
		return
	end

	local elapsed = math.max(0, nowServerTime - waveMotion.startedAtServerTime)
	if elapsed >= waveMotion.durationSeconds then
		self:_cleanupRecord(record)
		return
	end

	local currentPosition = waveMotion.startCFrame.Position + (waveMotion.direction * (waveMotion.speed * elapsed))
	waveModel:PivotTo(
		buildWaveVisualCFrame(
			currentPosition,
			waveMotion.direction,
			waveMotion.authoredRotation,
			waveMotion.authoredPlanarFacing
		)
	)
end

function Handler:_startWaveCrash(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local bossLeftHand = self:resolveBossLeftHandPart(bossModel)
	local bossRightHand = self:resolveBossRightHandPart(bossModel)
	if bossLeftHand == nil or bossRightHand == nil then
		self:warnWithPrefix("Wave Crash presentation could not resolve the live boss LeftHand/RightHand.")
		self:_cleanupRecord(record)
		return
	end

	local leftHandSource = self:resolveBossVfxModel(
		MERFIN_THE_GREAT_VFX_FOLDER_NAME,
		WAVE_CRASH_VFX_NAME,
		WAVE_CRASH_LEFT_HAND_MODEL_NAME
	)
	local rightHandSource = self:resolveBossVfxModel(
		MERFIN_THE_GREAT_VFX_FOLDER_NAME,
		WAVE_CRASH_VFX_NAME,
		WAVE_CRASH_RIGHT_HAND_MODEL_NAME
	)
	if leftHandSource == nil or rightHandSource == nil then
		self:warnWithPrefix("Wave Crash hand VFX models are missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local payload = event.payload
	local scaleMultiplier = math.max(0.1, tonumber(payload and payload.scaleMultiplier) or 1)
	local castFolder = self:_ensureCastFolder(record)
	local leftHandModel = leftHandSource:Clone()
	local rightHandModel = rightHandSource:Clone()
	leftHandModel:ScaleTo(scaleMultiplier)
	rightHandModel:ScaleTo(scaleMultiplier)
	self:prepareAttachedEffectModel(leftHandModel)
	self:prepareAttachedEffectModel(rightHandModel)
	self:enableVfxDescendants(leftHandModel)
	self:enableVfxDescendants(rightHandModel)
	self:scaleAttachedSounds(leftHandModel, scaleMultiplier)
	self:scaleAttachedSounds(rightHandModel, scaleMultiplier)

	leftHandModel.Parent = castFolder
	rightHandModel.Parent = castFolder
	record.leftHandModel = leftHandModel
	record.rightHandModel = rightHandModel

	if not self:attachEffectModel(leftHandModel, bossLeftHand) or not self:attachEffectModel(rightHandModel, bossRightHand) then
		self:warnWithPrefix("Wave Crash hand VFX models are missing BasePart configuration.")
		self:_cleanupRecord(record)
		return
	end

	self:playTimedSounds(leftHandModel, scaleMultiplier)
	self:playTimedSounds(rightHandModel, scaleMultiplier)
	self:emitVisuals(leftHandModel)
	self:emitVisuals(rightHandModel)
end

function Handler:_sendWaveCrash(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" then
		return
	end

	local startCFrame = payload.startCFrame
	local direction = payload.direction
	local speed = tonumber(payload.speed)
	local durationSeconds = tonumber(payload.durationSeconds)
	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	if typeof(startCFrame) ~= "CFrame"
		or typeof(direction) ~= "Vector3"
		or direction.Magnitude <= 0.001
		or speed == nil
		or durationSeconds == nil then
		return
	end

	local waveSource = self:resolveBossVfxModel(
		MERFIN_THE_GREAT_VFX_FOLDER_NAME,
		WAVE_CRASH_VFX_NAME,
		WAVE_CRASH_WAVE_MODEL_NAME
	)
	if waveSource == nil then
		self:warnWithPrefix("Wave Crash wave VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local castFolder = self:_ensureCastFolder(record)
	local waveModel = waveSource:Clone()
	waveModel:ScaleTo(scaleMultiplier)
	self:prepareMovingEffectModel(waveModel)
	self:enableVfxDescendants(waveModel)
	if self:resolveEffectModelPrimaryPart(waveModel) == nil then
		self:warnWithPrefix("Wave Crash wave VFX model is missing a BasePart for motion.")
		self:_cleanupRecord(record)
		return
	end

	local authoredPivot = waveModel:GetPivot()
	local authoredRotation = authoredPivot - authoredPivot.Position

	waveModel.Parent = castFolder
	local authoredPlanarFacing, authoredFacingSource = resolveAuthoredPlanarFacing(waveModel, authoredPivot)
	if authoredPlanarFacing == nil then
		self:warnWithPrefix("Wave Crash wave VFX model is missing a usable ForwardAttachment/pivot facing; preserving authored rotation.")
	elseif authoredFacingSource ~= WAVE_CRASH_FORWARD_ATTACHMENT_NAME then
		self:warnWithPrefix("Wave Crash wave VFX model is missing a usable ForwardAttachment; falling back to pivot RightVector.")
	end
	waveModel:PivotTo(buildWaveVisualCFrame(startCFrame.Position, direction, authoredRotation, authoredPlanarFacing))
	record.waveModel = waveModel
	record.waveMotion = {
		startCFrame = startCFrame,
		direction = direction.Unit,
		speed = math.max(0, speed),
		durationSeconds = math.max(0.05, durationSeconds),
		startedAtServerTime = if typeof(event.serverTime) == "number" then event.serverTime else self.Workspace:GetServerTimeNow(),
		authoredRotation = authoredRotation,
		authoredPlanarFacing = authoredPlanarFacing,
	}

	self:playTimedSounds(waveModel, scaleMultiplier)
	self:emitVisuals(waveModel)
	self:_updateWaveCrashMotion(record, self.Workspace:GetServerTimeNow())
end

Handler.moduleIds = {
	WAVE_CRASH_MODULE_ID,
}
Handler.start = Handler._startWaveCrash
Handler.update = Handler._updateWaveCrashMotion
Handler.actions = {
	send = Handler._sendWaveCrash,
}
Handler.requiredParentFields = {
	"leftHandModel",
	"rightHandModel",
	"waveModel",
}

return Handler
