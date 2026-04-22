type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		DESTROYER_3000_MECHA_PUNCH_MODULE_ID = "Moves.Destroyer3000.MechaPunch",
		MECHA_PUNCH_MODULE_ID = "Moves.MechArmouredMobileSuitBipedColourable.MechaPunch",
	},
	Vfx = {
		DESTROYER_3000_VFX_FOLDER_NAME = "Destroyer3000",
		MECHA_PUNCH_EXPLOSION_VFX_NAME = "Explosion",
		MECHA_PUNCH_RIGHT_HAND_VFX_NAME = "RightHand",
		MECHA_PUNCH_ROOT_PART_VFX_NAME = "RootPart",
		MECHA_PUNCH_VFX_NAME = "MechaPunch",
	},
	Timing = {
		MECHA_PUNCH_EXPLOSION_VFX_LIFETIME_SECONDS = 3,
	},
}

local DESTROYER_3000_MECHA_PUNCH_MODULE_ID = Constants.ModuleIds.DESTROYER_3000_MECHA_PUNCH_MODULE_ID
local DESTROYER_3000_VFX_FOLDER_NAME = Constants.Vfx.DESTROYER_3000_VFX_FOLDER_NAME
local MECHA_PUNCH_EXPLOSION_VFX_LIFETIME_SECONDS = Constants.Timing.MECHA_PUNCH_EXPLOSION_VFX_LIFETIME_SECONDS
local MECHA_PUNCH_EXPLOSION_VFX_NAME = Constants.Vfx.MECHA_PUNCH_EXPLOSION_VFX_NAME
local MECHA_PUNCH_MODULE_ID = Constants.ModuleIds.MECHA_PUNCH_MODULE_ID
local MECHA_PUNCH_RIGHT_HAND_VFX_NAME = Constants.Vfx.MECHA_PUNCH_RIGHT_HAND_VFX_NAME
local MECHA_PUNCH_ROOT_PART_VFX_NAME = Constants.Vfx.MECHA_PUNCH_ROOT_PART_VFX_NAME
local MECHA_PUNCH_VFX_NAME = Constants.Vfx.MECHA_PUNCH_VFX_NAME

local Handler = {}

function Handler:_startMechaPunch(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local bossRootPart = self:resolveBossRootPart(bossModel)
	local bossRightHand = self:resolveBossRightHandPart(bossModel)
	if bossRootPart == nil or bossRightHand == nil then
		self:warnWithPrefix("Mecha Punch presentation could not resolve the live boss RootPart/RightHand.")
		self:_cleanupRecord(record)
		return
	end

	local rootPartSource = self:resolveBossVfxModel(
		DESTROYER_3000_VFX_FOLDER_NAME,
		MECHA_PUNCH_VFX_NAME,
		MECHA_PUNCH_ROOT_PART_VFX_NAME
	)
	local rightHandSource = self:resolveBossVfxModel(
		DESTROYER_3000_VFX_FOLDER_NAME,
		MECHA_PUNCH_VFX_NAME,
		MECHA_PUNCH_RIGHT_HAND_VFX_NAME
	)
	if rootPartSource == nil or rightHandSource == nil then
		self:warnWithPrefix("Mecha Punch RootPart/RightHand VFX models are missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local payload = event.payload
	local scaleMultiplier = math.max(0.1, tonumber(payload and payload.scaleMultiplier) or 1)
	local castFolder = self:_ensureCastFolder(record)
	local rootPartModel = rootPartSource:Clone()
	local rightHandModel = rightHandSource:Clone()
	rootPartModel:ScaleTo(scaleMultiplier)
	rightHandModel:ScaleTo(scaleMultiplier)
	self:prepareAttachedEffectModel(rootPartModel)
	self:prepareAttachedEffectModel(rightHandModel)
	self:scaleAttachedSounds(rootPartModel, scaleMultiplier)
	self:scaleAttachedSounds(rightHandModel, scaleMultiplier)

	rootPartModel.Parent = castFolder
	rightHandModel.Parent = castFolder
	record.rootModel = rootPartModel
	record.rightHandModel = rightHandModel

	if not self:attachEffectModel(rootPartModel, bossRootPart) or not self:attachEffectModel(rightHandModel, bossRightHand) then
		self:warnWithPrefix("Mecha Punch attached VFX models are missing BasePart configuration.")
		self:_cleanupRecord(record)
		return
	end

	self:playAllSounds(rootPartModel)
	self:playAllSounds(rightHandModel)
	self:emitVisuals(self:collectEmittableVisuals(rootPartModel))
	self:emitVisuals(self:collectEmittableVisuals(rightHandModel))
end

function Handler:_impactMechaPunch(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.impactCFrame) ~= "CFrame" then
		return
	end

	local explosionSource = self:resolveBossVfxInstance(
		DESTROYER_3000_VFX_FOLDER_NAME,
		MECHA_PUNCH_VFX_NAME,
		MECHA_PUNCH_EXPLOSION_VFX_NAME
	)
	if explosionSource == nil then
		self:warnWithPrefix("Mecha Punch Explosion VFX instance is missing from ReplicatedStorage.GameAssets.VFX.")
		return
	end

	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	local explosionInstance = explosionSource:Clone()
	if explosionInstance:IsA("Model") then
		explosionInstance:ScaleTo(scaleMultiplier)
		self:prepareMovingEffectModel(explosionInstance)
		explosionInstance:PivotTo(payload.impactCFrame)
	elseif explosionInstance:IsA("BasePart") then
		explosionInstance.Size *= scaleMultiplier
		self:prepareMovingEffectPart(explosionInstance)
		explosionInstance.CFrame = payload.impactCFrame
	elseif explosionInstance:IsA("PVInstance") then
		explosionInstance:PivotTo(payload.impactCFrame)
	else
		self:warnWithPrefix("Mecha Punch Explosion VFX instance cannot be pivoted.")
		explosionInstance:Destroy()
		return
	end

	explosionInstance.Parent = self:_ensureVisualFolder()
	self:playAllSounds(explosionInstance)
	self:emitEffectInstance(explosionInstance, MECHA_PUNCH_EXPLOSION_VFX_LIFETIME_SECONDS)
	self:destroyAfter(explosionInstance, MECHA_PUNCH_EXPLOSION_VFX_LIFETIME_SECONDS)
	self:_shakeImpact()
end

Handler.moduleIds = {
	MECHA_PUNCH_MODULE_ID,
	DESTROYER_3000_MECHA_PUNCH_MODULE_ID,
}
Handler.start = Handler._startMechaPunch
Handler.actions = {
	impact = Handler._impactMechaPunch,
}
Handler.requiredParentFields = {
	"rootModel",
	"rightHandModel",
}
Handler.requiresHandle = false

return Handler
