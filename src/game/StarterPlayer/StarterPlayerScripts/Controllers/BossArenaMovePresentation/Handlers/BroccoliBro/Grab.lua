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
local BROCCOLI_GRAB_MODULE_ID = Constants.ModuleIds.BROCCOLI_GRAB_MODULE_ID
local BROCCOLI_GRAB_VFX_NAME = Constants.Vfx.BROCCOLI_GRAB_VFX_NAME

local Handler = {}

function Handler:_impactBroccoliGrab(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.floorCFrame) ~= "CFrame" then
		self:_cleanupRecord(record)
		return
	end

	local explosionSource = self:resolveBossVfxModel(
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
	local explosionModel = explosionSource:Clone()
	explosionModel:ScaleTo(scaleMultiplier)
	self:prepareMovingEffectModel(explosionModel)

	local floorAttachment = self:resolveNamedAttachment(explosionModel, BROCCOLI_GRAB_EXPLOSION_FLOOR_ATTACHMENT_NAME)
	if floorAttachment == nil then
		self:warnWithPrefix("Broccoli Grab ThrowExplosion VFX model is missing a Floor attachment.")
		explosionModel:Destroy()
		self:_cleanupRecord(record)
		return
	end

	self:pivotModelAttachmentToCFrame(explosionModel, floorAttachment, payload.floorCFrame)
	explosionModel.Parent = self:_ensureVisualFolder()

	self:playAllSounds(explosionModel)
	self:emitEffectInstance(explosionModel, BROCCOLI_GRAB_EXPLOSION_LIFETIME_SECONDS)
	self:destroyAfter(explosionModel, BROCCOLI_GRAB_EXPLOSION_LIFETIME_SECONDS)
	self:_shakeImpact()
	self:_cleanupRecord(record)
end

Handler.moduleIds = {
	BROCCOLI_GRAB_MODULE_ID,
}
Handler.actions = {
	impact = Handler._impactBroccoliGrab,
}
Handler.requiresHandle = false

return Handler
