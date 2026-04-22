type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		FLAME_SLASH_MODULE_ID = "Moves.FlameGuardGeneral.FlameSlash",
	},
	Vfx = {
		FLAME_SLASH_VFX_NAME = "FlameSlash",
	},
}

local FLAME_SLASH_MODULE_ID = Constants.ModuleIds.FLAME_SLASH_MODULE_ID
local FLAME_SLASH_VFX_NAME = Constants.Vfx.FLAME_SLASH_VFX_NAME

local Handler = {}

function Handler:_startFlameSlash(record: ActiveRecord, event: PresentationEvent)
	if not self:_prepareAttachedCastModels(record, event, "Flame Slash", FLAME_SLASH_VFX_NAME, nil) then
		return
	end

	local chargingSound = record.handleModel and record.handleModel:FindFirstChild("Charging Flame", true)
	self:playSound(if chargingSound and chargingSound:IsA("Sound") then chargingSound else nil)
end

function Handler:_impactFlameSlash(record: ActiveRecord, event: PresentationEvent)
	if record.handleModel and record.handleModel.Parent then
		local explosionSound = record.handleModel:FindFirstChild("CrystalExplosion", true)
		self:playSound(if explosionSound and explosionSound:IsA("Sound") then explosionSound else nil)
	end

	self:_shakeImpact()
end

Handler.moduleIds = {
	FLAME_SLASH_MODULE_ID,
}
Handler.start = Handler._startFlameSlash
Handler.actions = {
	impact = Handler._impactFlameSlash,
}
Handler.requiredParentFields = {
	"handleModel",
}

return Handler
