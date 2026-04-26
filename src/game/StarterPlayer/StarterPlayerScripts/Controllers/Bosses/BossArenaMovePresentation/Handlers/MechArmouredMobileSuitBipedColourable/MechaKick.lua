type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		DESTROYER_3000_MECHA_KICK_MODULE_ID = "Moves.Destroyer3000.MechaKick",
		MECHA_KICK_MODULE_ID = "Moves.MechArmouredMobileSuitBipedColourable.MechaKick",
	},
	Vfx = {
		DESTROYER_3000_VFX_FOLDER_NAME = "Destroyer3000",
		MECHA_KICK_EXPLOSION_VFX_NAME = "Explosion",
		MECHA_KICK_LEFT_FOOT_VFX_NAME = "LeftFoot",
		MECHA_KICK_VFX_NAME = "MechaKick",
	},
	Timing = {
		MECHA_KICK_EXPLOSION_VFX_LIFETIME_SECONDS = 3,
		MECHA_KICK_LEFT_FOOT_VFX_LIFETIME_SECONDS = 2.5,
	},
}

local DESTROYER_3000_MECHA_KICK_MODULE_ID = Constants.ModuleIds.DESTROYER_3000_MECHA_KICK_MODULE_ID
local DESTROYER_3000_VFX_FOLDER_NAME = Constants.Vfx.DESTROYER_3000_VFX_FOLDER_NAME
local MECHA_KICK_EXPLOSION_VFX_LIFETIME_SECONDS = Constants.Timing.MECHA_KICK_EXPLOSION_VFX_LIFETIME_SECONDS
local MECHA_KICK_EXPLOSION_VFX_NAME = Constants.Vfx.MECHA_KICK_EXPLOSION_VFX_NAME
local MECHA_KICK_LEFT_FOOT_VFX_LIFETIME_SECONDS = Constants.Timing.MECHA_KICK_LEFT_FOOT_VFX_LIFETIME_SECONDS
local MECHA_KICK_LEFT_FOOT_VFX_NAME = Constants.Vfx.MECHA_KICK_LEFT_FOOT_VFX_NAME
local MECHA_KICK_MODULE_ID = Constants.ModuleIds.MECHA_KICK_MODULE_ID
local MECHA_KICK_VFX_NAME = Constants.Vfx.MECHA_KICK_VFX_NAME

local Handler = {}

function Handler:_startMechaKick(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local bossLeftFoot = self:resolveBossLeftFootPart(bossModel)
	if bossLeftFoot == nil then
		self:warnWithPrefix("Mecha Kick presentation could not resolve the live boss LeftFoot.")
		self:_cleanupRecord(record)
		return
	end

	local leftFootSource = self:resolveBossVfxModel(
		DESTROYER_3000_VFX_FOLDER_NAME,
		MECHA_KICK_VFX_NAME,
		MECHA_KICK_LEFT_FOOT_VFX_NAME
	)
	if leftFootSource == nil then
		self:warnWithPrefix("Mecha Kick LeftFoot VFX model is missing from ReplicatedStorage.GameAssets.Effects.Bosses.")
		self:_cleanupRecord(record)
		return
	end

	local payload = event.payload
	local scaleMultiplier = math.max(0.1, tonumber(payload and payload.scaleMultiplier) or 1)
	local leftFootModel = leftFootSource:Clone()
	leftFootModel:ScaleTo(scaleMultiplier)
	self:prepareAttachedEffectModel(leftFootModel)

	if not self:attachEffectModel(leftFootModel, bossLeftFoot) then
		self:warnWithPrefix("Mecha Kick LeftFoot VFX model is missing a BasePart for welding.")
		leftFootModel:Destroy()
		self:_cleanupRecord(record)
		return
	end

	leftFootModel.Parent = self:_ensureCastFolder(record)
	record.leftFootModel = leftFootModel
	self:scaleAttachedSounds(leftFootModel, scaleMultiplier)
	self:playTimedSounds(leftFootModel, scaleMultiplier)
	self:emitEffectInstance(leftFootModel, MECHA_KICK_LEFT_FOOT_VFX_LIFETIME_SECONDS)
end

function Handler:_impactMechaKick(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.impactCFrame) ~= "CFrame" then
		return
	end

	local explosionSource = self:resolveBossVfxModel(
		DESTROYER_3000_VFX_FOLDER_NAME,
		MECHA_KICK_VFX_NAME,
		MECHA_KICK_EXPLOSION_VFX_NAME
	)
	if explosionSource == nil then
		self:warnWithPrefix("Mecha Kick Explosion VFX model is missing from ReplicatedStorage.GameAssets.Effects.Bosses.")
		return
	end

	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	local explosionModel = explosionSource:Clone()
	if not self:pivotFloorEffectInstance(explosionModel, payload.impactCFrame, scaleMultiplier) then
		self:warnWithPrefix("Mecha Kick Explosion VFX model cannot be floor-pivoted.")
		explosionModel:Destroy()
		return
	end
	explosionModel.Parent = self:_ensureVisualFolder()

	self:playAllSounds(explosionModel, scaleMultiplier)
	self:emitEffectInstance(explosionModel, MECHA_KICK_EXPLOSION_VFX_LIFETIME_SECONDS)
	self:_shakeImpact()
end

Handler.moduleIds = {
	MECHA_KICK_MODULE_ID,
	DESTROYER_3000_MECHA_KICK_MODULE_ID,
}
Handler.start = Handler._startMechaKick
Handler.actions = {
	impact = Handler._impactMechaKick,
}
Handler.requiredParentFields = {
	"leftFootModel",
}
Handler.requiresHandle = false

return Handler
