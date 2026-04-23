type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		BROCCOLI_GRAB_MODULE_ID = "Moves.BroccoliBro.Grab",
	},
	Vfx = {
		BROCCOLI_BRO_VFX_FOLDER_NAME = "BroccoliBro",
		BROCCOLI_GRAB_EXPLOSION_FLOOR_ATTACHMENT_NAME = "Floor",
		BROCCOLI_GRAB_EXPLOSION_MODEL_NAME = "ThrowExplosion",
		BROCCOLI_GRAB_IMPACT_EXPLOSION_SCALE_MULTIPLIER = 2,
		BROCCOLI_GRAB_ROOT_PART_SOUNDS_FOLDER_NAME = "RootPartSounds",
		BROCCOLI_GRAB_START_SOUNDS_FOLDER_NAME = "GrabStartSounds",
		BROCCOLI_GRAB_VFX_NAME = "Throw",
	},
	Timing = {
		BROCCOLI_GRAB_EXPLOSION_LIFETIME_SECONDS = 3,
	},
}

local BROCCOLI_BRO_VFX_FOLDER_NAME = Constants.Vfx.BROCCOLI_BRO_VFX_FOLDER_NAME
local BROCCOLI_GRAB_EXPLOSION_FLOOR_ATTACHMENT_NAME = Constants.Vfx.BROCCOLI_GRAB_EXPLOSION_FLOOR_ATTACHMENT_NAME
local BROCCOLI_GRAB_EXPLOSION_LIFETIME_SECONDS = Constants.Timing.BROCCOLI_GRAB_EXPLOSION_LIFETIME_SECONDS
local BROCCOLI_GRAB_EXPLOSION_MODEL_NAME = Constants.Vfx.BROCCOLI_GRAB_EXPLOSION_MODEL_NAME
local BROCCOLI_GRAB_IMPACT_EXPLOSION_SCALE_MULTIPLIER = Constants.Vfx.BROCCOLI_GRAB_IMPACT_EXPLOSION_SCALE_MULTIPLIER
local BROCCOLI_GRAB_MODULE_ID = Constants.ModuleIds.BROCCOLI_GRAB_MODULE_ID
local BROCCOLI_GRAB_ROOT_PART_SOUNDS_FOLDER_NAME = Constants.Vfx.BROCCOLI_GRAB_ROOT_PART_SOUNDS_FOLDER_NAME
local BROCCOLI_GRAB_START_SOUNDS_FOLDER_NAME = Constants.Vfx.BROCCOLI_GRAB_START_SOUNDS_FOLDER_NAME
local BROCCOLI_GRAB_VFX_NAME = Constants.Vfx.BROCCOLI_GRAB_VFX_NAME

local Handler = {}

function Handler:_pivotBroccoliGrabExplosion(effectInstance: Instance, floorCFrame: CFrame, scaleMultiplier: number): boolean
	local floorAttachment = self:resolveNamedAttachment(effectInstance, BROCCOLI_GRAB_EXPLOSION_FLOOR_ATTACHMENT_NAME)
	if floorAttachment == nil then
		return false
	end

	if effectInstance:IsA("Model") then
		effectInstance:ScaleTo(scaleMultiplier)
		self:prepareMovingEffectModel(effectInstance)
		self:pivotModelAttachmentToCFrame(effectInstance, floorAttachment, floorCFrame)
		return true
	end
	if effectInstance:IsA("BasePart") then
		effectInstance.Size *= scaleMultiplier
		self:prepareMovingEffectPart(effectInstance)
		effectInstance.CFrame = floorCFrame * floorAttachment.CFrame:Inverse()
		return true
	end

	return false
end

function Handler:_startBroccoliGrab(record: ActiveRecord, event: PresentationEvent)
	local soundsSource = self:resolveBossVfxInstance(
		BROCCOLI_BRO_VFX_FOLDER_NAME,
		BROCCOLI_GRAB_VFX_NAME,
		BROCCOLI_GRAB_START_SOUNDS_FOLDER_NAME
	)
	if soundsSource == nil then
		self:warnWithPrefix("Broccoli Grab start sounds are missing from ReplicatedStorage.GameAssets.VFX.")
		return
	end

	local scaleMultiplier = math.max(0.1, tonumber(event.payload and event.payload.scaleMultiplier) or 1)
	self:playDelayedSoundClones(soundsSource, self:_ensureCastFolder(record), scaleMultiplier)
end

function Handler:_impactBroccoliGrab(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.floorCFrame) ~= "CFrame" then
		self:_cleanupRecord(record)
		return
	end

	local explosionSource = self:resolveBossVfxInstance(
		BROCCOLI_BRO_VFX_FOLDER_NAME,
		BROCCOLI_GRAB_VFX_NAME,
		BROCCOLI_GRAB_EXPLOSION_MODEL_NAME
	)
	if explosionSource == nil then
		self:warnWithPrefix("Broccoli Grab ThrowExplosion VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	local impactScaleMultiplier = math.max(0.1, scaleMultiplier * BROCCOLI_GRAB_IMPACT_EXPLOSION_SCALE_MULTIPLIER)
	local rootPartSoundsSource = self:resolveBossVfxInstance(
		BROCCOLI_BRO_VFX_FOLDER_NAME,
		BROCCOLI_GRAB_VFX_NAME,
		BROCCOLI_GRAB_ROOT_PART_SOUNDS_FOLDER_NAME
	)
	if rootPartSoundsSource == nil then
		self:warnWithPrefix("Broccoli Grab RootPartSounds are missing from ReplicatedStorage.GameAssets.VFX.")
	else
		self:playDelayedSoundClones(rootPartSoundsSource, self:_ensureCastFolder(record), scaleMultiplier)
	end

	local explosionModel = explosionSource:Clone()
	if not self:_pivotBroccoliGrabExplosion(explosionModel, payload.floorCFrame, impactScaleMultiplier) then
		self:warnWithPrefix("Broccoli Grab ThrowExplosion VFX model is missing a Floor attachment.")
		explosionModel:Destroy()
		self:_cleanupRecord(record)
		return
	end

	explosionModel.Parent = self:_ensureVisualFolder()

	self:playAllSounds(explosionModel, impactScaleMultiplier)
	self:emitEffectInstance(explosionModel, BROCCOLI_GRAB_EXPLOSION_LIFETIME_SECONDS)
	self:_shakeImpact()
	self:_cleanupRecord(record)
end

Handler.moduleIds = {
	BROCCOLI_GRAB_MODULE_ID,
}
Handler.start = Handler._startBroccoliGrab
Handler.actions = {
	impact = Handler._impactBroccoliGrab,
}
Handler.requiresHandle = false

return Handler
