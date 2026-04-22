type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		OINAN_THICKHOOF_ROAR_MODULE_ID = "Moves.OinanThickhoof.BullRoar",
	},
	Vfx = {
		OINAN_THICKHOOF_ROAR_IMPACT_VFX_NAME = "Roar",
		OINAN_THICKHOOF_ROAR_START_VFX_NAME = "Start",
		OINAN_THICKHOOF_ROAR_VFX_NAME = "BullRoar",
		OINAN_THICKHOOF_VFX_FOLDER_NAME = "OinanThickhoof",
	},
	Timing = {
		OINAN_THICKHOOF_ROAR_VFX_LIFETIME_SECONDS = 3,
	},
}

local OINAN_THICKHOOF_ROAR_IMPACT_VFX_NAME = Constants.Vfx.OINAN_THICKHOOF_ROAR_IMPACT_VFX_NAME
local OINAN_THICKHOOF_ROAR_MODULE_ID = Constants.ModuleIds.OINAN_THICKHOOF_ROAR_MODULE_ID
local OINAN_THICKHOOF_ROAR_START_VFX_NAME = Constants.Vfx.OINAN_THICKHOOF_ROAR_START_VFX_NAME
local OINAN_THICKHOOF_ROAR_VFX_LIFETIME_SECONDS = Constants.Timing.OINAN_THICKHOOF_ROAR_VFX_LIFETIME_SECONDS
local OINAN_THICKHOOF_ROAR_VFX_NAME = Constants.Vfx.OINAN_THICKHOOF_ROAR_VFX_NAME
local OINAN_THICKHOOF_VFX_FOLDER_NAME = Constants.Vfx.OINAN_THICKHOOF_VFX_FOLDER_NAME

local Handler = {}

function Handler:_emitOinanRoarVfx(
	record: ActiveRecord,
	event: PresentationEvent,
	effectModelName: string
)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local bossRootPart = self:resolveBossRootPart(bossModel)
	if bossRootPart == nil then
		self:warnWithPrefix("Bull Roar presentation could not resolve the live boss RootPart.")
		self:_cleanupRecord(record)
		return
	end

	local effectSource = self:resolveBossVfxModel(
		OINAN_THICKHOOF_VFX_FOLDER_NAME,
		OINAN_THICKHOOF_ROAR_VFX_NAME,
		effectModelName
	)
	if effectSource == nil then
		self:warnWithPrefix("Bull Roar VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local payload = event.payload
	local scaleMultiplier = math.max(0.1, tonumber(payload and payload.scaleMultiplier) or 1)
	local effectModel = effectSource:Clone()
	effectModel:ScaleTo(scaleMultiplier)
	self:prepareMovingEffectModel(effectModel)
	effectModel:PivotTo(bossRootPart.CFrame)
	effectModel.Parent = self:_ensureVisualFolder()
	self:playAllSounds(effectModel, scaleMultiplier)
	self:emitEffectInstance(effectModel, OINAN_THICKHOOF_ROAR_VFX_LIFETIME_SECONDS)
end

function Handler:_startOinanRoar(record: ActiveRecord, event: PresentationEvent)
	self:_emitOinanRoarVfx(record, event, OINAN_THICKHOOF_ROAR_START_VFX_NAME)
end

function Handler:_roarOinanRoar(record: ActiveRecord, event: PresentationEvent)
	self:_shakeImpact()
	self:_emitOinanRoarVfx(record, event, OINAN_THICKHOOF_ROAR_IMPACT_VFX_NAME)
end

Handler.moduleIds = {
	OINAN_THICKHOOF_ROAR_MODULE_ID,
}
Handler.start = Handler._startOinanRoar
Handler.actions = {
	roar = Handler._roarOinanRoar,
}
Handler.requiresHandle = false

return Handler
