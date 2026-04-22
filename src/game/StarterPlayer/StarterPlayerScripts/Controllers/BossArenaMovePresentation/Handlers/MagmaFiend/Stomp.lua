type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		MAGMA_STOMP_MODULE_ID = "Moves.MagmaFiend.Stomp",
	},
	Vfx = {
		MAGMA_FIEND_VFX_FOLDER_NAME = "MagmaFiend",
		MAGMA_STOMP_FLOOR_MODEL_NAME = "Floor",
		MAGMA_STOMP_VFX_NAME = "LavaStomp",
	},
	Timing = {
		MAGMA_STOMP_VFX_LIFETIME_SECONDS = 3,
	},
}

local MAGMA_FIEND_VFX_FOLDER_NAME = Constants.Vfx.MAGMA_FIEND_VFX_FOLDER_NAME
local MAGMA_STOMP_FLOOR_MODEL_NAME = Constants.Vfx.MAGMA_STOMP_FLOOR_MODEL_NAME
local MAGMA_STOMP_MODULE_ID = Constants.ModuleIds.MAGMA_STOMP_MODULE_ID
local MAGMA_STOMP_VFX_LIFETIME_SECONDS = Constants.Timing.MAGMA_STOMP_VFX_LIFETIME_SECONDS
local MAGMA_STOMP_VFX_NAME = Constants.Vfx.MAGMA_STOMP_VFX_NAME

local Handler = {}

function Handler:_stompMagmaStomp(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.impactCFrame) ~= "CFrame" then
		self:_cleanupRecord(record)
		return
	end

	local floorSource = self:resolveBossVfxModel(
		MAGMA_FIEND_VFX_FOLDER_NAME,
		MAGMA_STOMP_VFX_NAME,
		MAGMA_STOMP_FLOOR_MODEL_NAME
	)
	if floorSource == nil then
		self:warnWithPrefix("Magma Stomp floor VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	local floorModel = floorSource:Clone()
	floorModel:ScaleTo(scaleMultiplier)
	self:prepareMovingEffectModel(floorModel)
	floorModel:PivotTo(payload.impactCFrame)
	floorModel.Parent = self:_ensureVisualFolder()

	self:playAllSounds(floorModel)
	self:emitEffectInstance(floorModel, MAGMA_STOMP_VFX_LIFETIME_SECONDS)
	self:destroyAfter(floorModel, MAGMA_STOMP_VFX_LIFETIME_SECONDS)
end

Handler.moduleIds = {
	MAGMA_STOMP_MODULE_ID,
}
Handler.actions = {
	stomp = Handler._stompMagmaStomp,
}
Handler.requiresHandle = false

return Handler
