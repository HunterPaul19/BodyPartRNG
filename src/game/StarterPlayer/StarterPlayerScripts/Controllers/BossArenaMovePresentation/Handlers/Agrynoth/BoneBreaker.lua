type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		AGRYNOTH_BONE_BREAKER_MODULE_ID = "Moves.Agrynoth.BoneBreaker",
	},
	Vfx = {
		AGRYNOTH_BONE_BREAKER_EXPLOSION_NAME_PREFIX = "Explosion",
		AGRYNOTH_BONE_BREAKER_LEFT_HAND_VFX_NAME = "LeftHand",
		AGRYNOTH_BONE_BREAKER_SOUNDS_FOLDER_NAME = "Sounds",
		AGRYNOTH_BONE_BREAKER_VFX_NAME = "BoneBreaker",
		AGRYNOTH_VFX_FOLDER_NAME = "Agrynoth",
	},
	Timing = {
		AGRYNOTH_BONE_BREAKER_EXPLOSION_LIFETIME_SECONDS = 3,
		AGRYNOTH_BONE_BREAKER_EXPLOSION_SCALE = 3,
	},
}

local AGRYNOTH_BONE_BREAKER_EXPLOSION_LIFETIME_SECONDS = Constants.Timing.AGRYNOTH_BONE_BREAKER_EXPLOSION_LIFETIME_SECONDS
local AGRYNOTH_BONE_BREAKER_EXPLOSION_NAME_PREFIX = Constants.Vfx.AGRYNOTH_BONE_BREAKER_EXPLOSION_NAME_PREFIX
local AGRYNOTH_BONE_BREAKER_EXPLOSION_SCALE = Constants.Timing.AGRYNOTH_BONE_BREAKER_EXPLOSION_SCALE
local AGRYNOTH_BONE_BREAKER_LEFT_HAND_VFX_NAME = Constants.Vfx.AGRYNOTH_BONE_BREAKER_LEFT_HAND_VFX_NAME
local AGRYNOTH_BONE_BREAKER_MODULE_ID = Constants.ModuleIds.AGRYNOTH_BONE_BREAKER_MODULE_ID
local AGRYNOTH_BONE_BREAKER_SOUNDS_FOLDER_NAME = Constants.Vfx.AGRYNOTH_BONE_BREAKER_SOUNDS_FOLDER_NAME
local AGRYNOTH_BONE_BREAKER_VFX_NAME = Constants.Vfx.AGRYNOTH_BONE_BREAKER_VFX_NAME
local AGRYNOTH_VFX_FOLDER_NAME = Constants.Vfx.AGRYNOTH_VFX_FOLDER_NAME

local Handler = {}

function Handler:_startAgrynothBoneBreaker(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local bossLeftHand = self:resolveBossLeftHandPart(bossModel)
	if bossLeftHand == nil then
		self:warnWithPrefix("Agrynoth Bone Breaker presentation could not resolve the live boss LeftHand.")
		self:_cleanupRecord(record)
		return
	end

	local leftHandSource = self:resolveBossVfxModel(
		AGRYNOTH_VFX_FOLDER_NAME,
		AGRYNOTH_BONE_BREAKER_VFX_NAME,
		AGRYNOTH_BONE_BREAKER_LEFT_HAND_VFX_NAME
	)
	if leftHandSource == nil then
		self:warnWithPrefix("Agrynoth Bone Breaker LeftHand VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local castFolder = self:_ensureCastFolder(record)
	local scaleMultiplier = math.max(0.1, tonumber(event.payload and event.payload.scaleMultiplier) or 1)
	local leftHandModel = leftHandSource:Clone()
	self:prepareAttachedEffectModel(leftHandModel)
	leftHandModel.Parent = castFolder
	record.leftHandModel = leftHandModel

	if not self:attachEffectModel(leftHandModel, bossLeftHand) then
		self:warnWithPrefix("Agrynoth Bone Breaker LeftHand VFX model is missing a BasePart for welding.")
		self:_cleanupRecord(record)
		return
	end

	self:playAllSounds(leftHandModel, scaleMultiplier)
	self:emitEffectInstance(leftHandModel)

	local effectFolder = self:resolveBossVfxFolder(AGRYNOTH_VFX_FOLDER_NAME, AGRYNOTH_BONE_BREAKER_VFX_NAME)
	local soundsFolder = effectFolder and effectFolder:FindFirstChild(AGRYNOTH_BONE_BREAKER_SOUNDS_FOLDER_NAME)
	if soundsFolder then
		self:playDelayedSoundClones(soundsFolder, castFolder, scaleMultiplier)
	end
end

function Handler:_impactAgrynothBoneBreaker(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.floorCFrame) ~= "CFrame" then
		return
	end

	local hitIndex = math.clamp(math.floor(tonumber(payload.hitIndex) or 1), 1, 3)
	local soundScaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1) * AGRYNOTH_BONE_BREAKER_EXPLOSION_SCALE
	local explosionName = string.format("%s%d", AGRYNOTH_BONE_BREAKER_EXPLOSION_NAME_PREFIX, hitIndex)
	local explosionSource = self:resolveBossVfxModel(AGRYNOTH_VFX_FOLDER_NAME, AGRYNOTH_BONE_BREAKER_VFX_NAME, explosionName)
	if explosionSource == nil then
		self:warnWithPrefix(string.format(
			"Agrynoth Bone Breaker %s VFX model is missing from ReplicatedStorage.GameAssets.VFX.",
			explosionName
		))
		return
	end

	local explosionModel = explosionSource:Clone()
	explosionModel:ScaleTo(AGRYNOTH_BONE_BREAKER_EXPLOSION_SCALE)
	self:prepareMovingEffectModel(explosionModel)
	local groundCFrame = CFrame.new(payload.floorCFrame.Position)
	explosionModel:PivotTo(groundCFrame)
	local boundingCFrame, boundingSize = explosionModel:GetBoundingBox()
	local bottomY = boundingCFrame.Position.Y - (boundingSize.Y * 0.5)
	explosionModel:PivotTo(explosionModel:GetPivot() + Vector3.new(0, groundCFrame.Position.Y - bottomY, 0))
	explosionModel.Parent = self:_ensureVisualFolder()

	self:playAllSounds(explosionModel, soundScaleMultiplier)
	self:emitEffectInstance(explosionModel, AGRYNOTH_BONE_BREAKER_EXPLOSION_LIFETIME_SECONDS)
	self:destroyVfxAfter(explosionModel, AGRYNOTH_BONE_BREAKER_EXPLOSION_LIFETIME_SECONDS)
	self:_shakeImpact()
end

Handler.moduleIds = {
	AGRYNOTH_BONE_BREAKER_MODULE_ID,
}
Handler.start = Handler._startAgrynothBoneBreaker
Handler.actions = {
	impact = Handler._impactAgrynothBoneBreaker,
}
Handler.requiresHandle = false

return Handler
