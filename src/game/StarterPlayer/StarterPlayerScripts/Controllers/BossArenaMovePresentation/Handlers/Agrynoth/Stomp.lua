type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		AGRYNOTH_STOMP_MODULE_ID = "Moves.Agrynoth.Stomp",
	},
	Vfx = {
		AGRYNOTH_STOMP_FLOOR_VFX_NAME = "FloorFx",
		AGRYNOTH_STOMP_VFX_NAME = "Stomp",
		AGRYNOTH_VFX_FOLDER_NAME = "Agrynoth",
	},
	Timing = {
		AGRYNOTH_STOMP_VFX_LIFETIME_SECONDS = 3,
	},
}

local AGRYNOTH_STOMP_FLOOR_VFX_NAME = Constants.Vfx.AGRYNOTH_STOMP_FLOOR_VFX_NAME
local AGRYNOTH_STOMP_MODULE_ID = Constants.ModuleIds.AGRYNOTH_STOMP_MODULE_ID
local AGRYNOTH_STOMP_VFX_LIFETIME_SECONDS = Constants.Timing.AGRYNOTH_STOMP_VFX_LIFETIME_SECONDS
local AGRYNOTH_STOMP_VFX_NAME = Constants.Vfx.AGRYNOTH_STOMP_VFX_NAME
local AGRYNOTH_VFX_FOLDER_NAME = Constants.Vfx.AGRYNOTH_VFX_FOLDER_NAME

local Handler = {}

function Handler:_stompAgrynothStomp(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.impactCFrame) ~= "CFrame" then
		self:_cleanupRecord(record)
		return
	end

	local effectSource = self:resolveBossVfxInstance(
		AGRYNOTH_VFX_FOLDER_NAME,
		AGRYNOTH_STOMP_VFX_NAME,
		AGRYNOTH_STOMP_FLOOR_VFX_NAME
	)
	if effectSource == nil then
		self:warnWithPrefix("Agrynoth Stomp FloorFx VFX instance is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	local effectInstance = effectSource:Clone()
	if effectInstance:IsA("Model") then
		effectInstance:ScaleTo(scaleMultiplier)
		self:prepareMovingEffectModel(effectInstance)
		effectInstance:PivotTo(payload.impactCFrame)
	elseif effectInstance:IsA("BasePart") then
		effectInstance.Size *= scaleMultiplier
		self:prepareMovingEffectPart(effectInstance)
		effectInstance.CFrame = payload.impactCFrame
	elseif effectInstance:IsA("PVInstance") then
		effectInstance:PivotTo(payload.impactCFrame)
	else
		self:warnWithPrefix("Agrynoth Stomp FloorFx VFX instance cannot be pivoted.")
		effectInstance:Destroy()
		self:_cleanupRecord(record)
		return
	end

	effectInstance.Parent = self:_ensureCastFolder(record)
	self:playAllSounds(effectInstance, scaleMultiplier)
	self:emitEffectInstance(effectInstance, AGRYNOTH_STOMP_VFX_LIFETIME_SECONDS)
	self:_shakeImpact()
end

Handler.moduleIds = {
	AGRYNOTH_STOMP_MODULE_ID,
}
Handler.actions = {
	stomp = Handler._stompAgrynothStomp,
}
Handler.requiresHandle = false

return Handler
