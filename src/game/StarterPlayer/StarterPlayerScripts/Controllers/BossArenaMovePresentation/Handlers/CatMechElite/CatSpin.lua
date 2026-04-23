type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		CAT_MECH_ELITE_CAT_SPIN_MODULE_ID = "Moves.CatMechElite.CatSpin",
	},
	Vfx = {
		CAT_MECH_ELITE_VFX_FOLDER_NAME = "CatMechElite",
		CAT_SPIN_VFX_NAME = "CatSpin",
		CAT_SPIN_ROOT_PART_MODEL_NAME = "RootPart",
	},
}

local CAT_MECH_ELITE_CAT_SPIN_MODULE_ID = Constants.ModuleIds.CAT_MECH_ELITE_CAT_SPIN_MODULE_ID
local CAT_MECH_ELITE_VFX_FOLDER_NAME = Constants.Vfx.CAT_MECH_ELITE_VFX_FOLDER_NAME
local CAT_SPIN_ROOT_PART_MODEL_NAME = Constants.Vfx.CAT_SPIN_ROOT_PART_MODEL_NAME
local CAT_SPIN_VFX_NAME = Constants.Vfx.CAT_SPIN_VFX_NAME

local Handler = {}

function Handler:_startCatSpin(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local bossRootPart = self:resolveBossRootPart(bossModel)
	if bossRootPart == nil then
		self:warnWithPrefix("Cat Spin presentation could not resolve the live boss RootPart.")
		self:_cleanupRecord(record)
		return
	end

	local rootSource = self:resolveBossVfxModel(
		CAT_MECH_ELITE_VFX_FOLDER_NAME,
		CAT_SPIN_VFX_NAME,
		CAT_SPIN_ROOT_PART_MODEL_NAME
	)
	if rootSource == nil then
		self:warnWithPrefix("Cat Spin RootPart VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local payload = event.payload
	local scaleMultiplier = math.max(0.1, tonumber(payload and payload.scaleMultiplier) or 1)
	local activeWindowSeconds = math.max(0.1, tonumber(payload and payload.activeWindowSeconds) or 1.5)
	local castFolder = self:_ensureCastFolder(record)
	local rootModel = rootSource:Clone()
	rootModel:ScaleTo(scaleMultiplier)
	self:prepareAttachedEffectModel(rootModel)
	self:enableVfxDescendants(rootModel)
	self:scaleAttachedSounds(rootModel, scaleMultiplier)

	rootModel.Parent = castFolder
	record.rootModel = rootModel

	if not self:attachEffectModel(rootModel, bossRootPart) then
		self:warnWithPrefix("Cat Spin RootPart VFX model is missing BasePart configuration.")
		self:_cleanupRecord(record)
		return
	end

	self:playAllSoundsFromConfiguredPositions(rootModel, scaleMultiplier)
	self:emitEffectInstance(rootModel, activeWindowSeconds)
end

Handler.moduleIds = {
	CAT_MECH_ELITE_CAT_SPIN_MODULE_ID,
}
Handler.start = Handler._startCatSpin
Handler.requiredParentFields = {
	"rootModel",
}
Handler.requiresHandle = false

return Handler
