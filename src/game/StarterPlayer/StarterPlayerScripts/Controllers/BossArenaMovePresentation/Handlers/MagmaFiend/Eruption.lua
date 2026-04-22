type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		MAGMA_ERUPTION_MODULE_ID = "Moves.MagmaFiend.Eruption",
	},
	Vfx = {
		MAGMA_ERUPTION_FLOOR_MODEL_NAME = "Floor",
		MAGMA_ERUPTION_LEFT_HAND_MODEL_NAME = "LeftHand",
		MAGMA_ERUPTION_RIGHT_HAND_MODEL_NAME = "RightHand",
		MAGMA_ERUPTION_VFX_NAME = "EruptionThrow",
		MAGMA_FIEND_VFX_FOLDER_NAME = "MagmaFiend",
	},
	Timing = {
		MAGMA_ERUPTION_VFX_LIFETIME_SECONDS = 3,
	},
}

local MAGMA_ERUPTION_FLOOR_MODEL_NAME = Constants.Vfx.MAGMA_ERUPTION_FLOOR_MODEL_NAME
local MAGMA_ERUPTION_LEFT_HAND_MODEL_NAME = Constants.Vfx.MAGMA_ERUPTION_LEFT_HAND_MODEL_NAME
local MAGMA_ERUPTION_MODULE_ID = Constants.ModuleIds.MAGMA_ERUPTION_MODULE_ID
local MAGMA_ERUPTION_RIGHT_HAND_MODEL_NAME = Constants.Vfx.MAGMA_ERUPTION_RIGHT_HAND_MODEL_NAME
local MAGMA_ERUPTION_VFX_LIFETIME_SECONDS = Constants.Timing.MAGMA_ERUPTION_VFX_LIFETIME_SECONDS
local MAGMA_ERUPTION_VFX_NAME = Constants.Vfx.MAGMA_ERUPTION_VFX_NAME
local MAGMA_FIEND_VFX_FOLDER_NAME = Constants.Vfx.MAGMA_FIEND_VFX_FOLDER_NAME

local Handler = {}

function Handler:_clearMagmaEruptionWarnings(record: ActiveRecord)
	if record.eruptionWarningHandles == nil then
		return
	end

	for _, warningHandle in pairs(record.eruptionWarningHandles) do
		warningHandle:Destroy()
	end

	record.eruptionWarningHandles = nil
end

function Handler:_startMagmaEruption(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local bossLeftHand = self:resolveBossLeftHandPart(bossModel)
	local bossRightHand = self:resolveBossRightHandPart(bossModel)
	if bossLeftHand == nil or bossRightHand == nil then
		self:warnWithPrefix("Magma Eruption presentation could not resolve the live boss LeftHand/RightHand.")
		self:_cleanupRecord(record)
		return
	end

	local leftHandSource = self:resolveBossVfxModel(
		MAGMA_FIEND_VFX_FOLDER_NAME,
		MAGMA_ERUPTION_VFX_NAME,
		MAGMA_ERUPTION_LEFT_HAND_MODEL_NAME
	)
	local rightHandSource = self:resolveBossVfxModel(
		MAGMA_FIEND_VFX_FOLDER_NAME,
		MAGMA_ERUPTION_VFX_NAME,
		MAGMA_ERUPTION_RIGHT_HAND_MODEL_NAME
	)
	if leftHandSource == nil or rightHandSource == nil then
		self:warnWithPrefix("Magma Eruption hand VFX models are missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local castFolder = self:_ensureCastFolder(record)
	local scaleMultiplier = math.max(0.1, tonumber(event.payload and event.payload.scaleMultiplier) or 1)
	local leftHandModel = leftHandSource:Clone()
	local rightHandModel = rightHandSource:Clone()
	leftHandModel:ScaleTo(scaleMultiplier)
	rightHandModel:ScaleTo(scaleMultiplier)
	self:prepareAttachedEffectModel(leftHandModel)
	self:prepareAttachedEffectModel(rightHandModel)
	self:scaleAttachedSounds(leftHandModel, scaleMultiplier)
	self:scaleAttachedSounds(rightHandModel, scaleMultiplier)

	leftHandModel.Parent = castFolder
	rightHandModel.Parent = castFolder
	record.leftHandModel = leftHandModel
	record.rightHandModel = rightHandModel

	if not self:attachEffectModel(leftHandModel, bossLeftHand) or not self:attachEffectModel(rightHandModel, bossRightHand) then
		self:warnWithPrefix("Magma Eruption hand VFX models are missing BasePart configuration.")
		self:_cleanupRecord(record)
		return
	end

	self:playTimedSounds(leftHandModel, scaleMultiplier)
	self:playTimedSounds(rightHandModel, scaleMultiplier)
	self:emitVisuals(self:collectEmittableVisuals(leftHandModel))
	self:emitVisuals(self:collectEmittableVisuals(rightHandModel))
end

function Handler:_warnMagmaEruption(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.points) ~= "table" then
		return
	end

	self:_clearMagmaEruptionWarnings(record)
	local castFolder = self:_ensureCastFolder(record)
	local warningSeconds = math.max(0.05, tonumber(payload.warningSeconds) or 1)
	record.eruptionWarningHandles = {}

	for _, pointData in ipairs(payload.points) do
		if typeof(pointData) ~= "table" then
			continue
		end

		local floorCFrame = pointData.floorCFrame
		local footprintSize = pointData.footprintSize
		if typeof(floorCFrame) ~= "CFrame" or typeof(footprintSize) ~= "Vector3" then
			continue
		end

		local index = math.max(1, math.floor(tonumber(pointData.index) or (#record.eruptionWarningHandles + 1)))
		record.eruptionWarningHandles[index] = self.Indication.CreateCircle({
			parent = castFolder,
			cframe = floorCFrame,
			diameter = math.max(footprintSize.X, footprintSize.Z),
			duration = warningSeconds,
		})
	end
end

function Handler:_eruptMagmaEruption(record: ActiveRecord, event: PresentationEvent)
	self:_clearMagmaEruptionWarnings(record)
	self:_shakeImpact()

	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.points) ~= "table" then
		self:_cleanupRecord(record)
		return
	end

	local floorSource = self:resolveBossVfxModel(
		MAGMA_FIEND_VFX_FOLDER_NAME,
		MAGMA_ERUPTION_VFX_NAME,
		MAGMA_ERUPTION_FLOOR_MODEL_NAME
	)
	if floorSource == nil then
		self:warnWithPrefix("Magma Eruption floor VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	for _, pointData in ipairs(payload.points) do
		if typeof(pointData) ~= "table" or typeof(pointData.floorCFrame) ~= "CFrame" then
			continue
		end

		local floorModel = floorSource:Clone()
		self:prepareMovingEffectModel(floorModel)
		floorModel:PivotTo(pointData.floorCFrame)
		floorModel.Parent = self:_ensureVisualFolder()

		self:playTimedSounds(floorModel, math.max(0.1, tonumber(payload.scaleMultiplier) or 1))
		self:emitEffectInstance(floorModel, MAGMA_ERUPTION_VFX_LIFETIME_SECONDS)
		self:destroyVfxAfter(floorModel, MAGMA_ERUPTION_VFX_LIFETIME_SECONDS)
	end

	self:_cleanupRecord(record)
end

Handler.moduleIds = {
	MAGMA_ERUPTION_MODULE_ID,
}
Handler.start = Handler._startMagmaEruption
Handler.actions = {
	warn = Handler._warnMagmaEruption,
	erupt = Handler._eruptMagmaEruption,
}
Handler.requiredParentFields = {
	"leftHandModel",
	"rightHandModel",
}
Handler.requiresHandle = false

return Handler
