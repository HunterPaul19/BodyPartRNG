type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		OINAN_THICKHOOF_STOMP_MODULE_ID = "Moves.OinanThickhoof.Stomp",
	},
	Vfx = {
		OINAN_THICKHOOF_STOMP_FLOOR_VFX_NAME = "FloorFx",
		OINAN_THICKHOOF_STOMP_VFX_NAME = "Stomp",
		OINAN_THICKHOOF_VFX_FOLDER_NAME = "OinanThickhoof",
	},
	Timing = {
		OINAN_THICKHOOF_STOMP_VFX_LIFETIME_SECONDS = 3,
	},
}

local OINAN_THICKHOOF_STOMP_FLOOR_VFX_NAME = Constants.Vfx.OINAN_THICKHOOF_STOMP_FLOOR_VFX_NAME
local OINAN_THICKHOOF_STOMP_MODULE_ID = Constants.ModuleIds.OINAN_THICKHOOF_STOMP_MODULE_ID
local OINAN_THICKHOOF_STOMP_VFX_LIFETIME_SECONDS = Constants.Timing.OINAN_THICKHOOF_STOMP_VFX_LIFETIME_SECONDS
local OINAN_THICKHOOF_STOMP_VFX_NAME = Constants.Vfx.OINAN_THICKHOOF_STOMP_VFX_NAME
local OINAN_THICKHOOF_VFX_FOLDER_NAME = Constants.Vfx.OINAN_THICKHOOF_VFX_FOLDER_NAME

local Handler = {}

function Handler:_stompOinanStomp(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.impactCFrame) ~= "CFrame" then
		self:_cleanupRecord(record)
		return
	end

	local effectSource = self:resolveBossVfxInstance(
		OINAN_THICKHOOF_VFX_FOLDER_NAME,
		OINAN_THICKHOOF_STOMP_VFX_NAME,
		OINAN_THICKHOOF_STOMP_FLOOR_VFX_NAME
	)
	if effectSource == nil then
		self:warnWithPrefix("Oinan Stomp FloorFx VFX instance is missing from ReplicatedStorage.GameAssets.Effects.Bosses.")
		self:_cleanupRecord(record)
		return
	end

	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	local effectInstance = effectSource:Clone()
	if not self:pivotEffectInstanceAtAuthoredPivot(effectInstance, payload.impactCFrame, scaleMultiplier) then
		self:warnWithPrefix("Oinan Stomp FloorFx VFX instance cannot be pivoted.")
		effectInstance:Destroy()
		self:_cleanupRecord(record)
		return
	end

	effectInstance.Parent = self:_ensureCastFolder(record)
	self:playAllSounds(effectInstance, scaleMultiplier)
	self:emitEffectInstance(effectInstance, OINAN_THICKHOOF_STOMP_VFX_LIFETIME_SECONDS)
	self:_shakeImpact()
end

Handler.moduleIds = {
	OINAN_THICKHOOF_STOMP_MODULE_ID,
}
Handler.actions = {
	stomp = Handler._stompOinanStomp,
}
Handler.requiresHandle = false

return Handler
