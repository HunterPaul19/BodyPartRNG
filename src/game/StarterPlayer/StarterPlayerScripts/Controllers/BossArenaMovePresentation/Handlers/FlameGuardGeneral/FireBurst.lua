type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		FIRE_BURST_MODULE_ID = "Moves.FlameGuardGeneral.FireBurst",
	},
	Vfx = {
		FIRE_BURST_VFX_NAME = "FlameBurst",
	},
}

local FIRE_BURST_MODULE_ID = Constants.ModuleIds.FIRE_BURST_MODULE_ID
local FIRE_BURST_VFX_NAME = Constants.Vfx.FIRE_BURST_VFX_NAME

local Handler = {}

function Handler:_startFireBurst(record: ActiveRecord, event: PresentationEvent)
	self:_prepareAttachedCastModels(record, event, "Fire Burst", FIRE_BURST_VFX_NAME, {
		enableParticles = true,
		scaleRootSounds = true,
		playTimedSounds = true,
	})
end

function Handler:_impactFireBurst(_record: ActiveRecord, event: PresentationEvent)
	self:_shakeImpact()
end

Handler.moduleIds = {
	FIRE_BURST_MODULE_ID,
}
Handler.start = Handler._startFireBurst
Handler.actions = {
	impact = Handler._impactFireBurst,
}

return Handler
