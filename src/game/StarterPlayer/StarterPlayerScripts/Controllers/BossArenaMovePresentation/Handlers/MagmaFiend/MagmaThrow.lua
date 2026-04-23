type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		MAGMA_THROW_MODULE_ID = "Moves.MagmaFiend.MagmaThrow",
	},
	Vfx = {
		MAGMA_FIEND_VFX_FOLDER_NAME = "MagmaFiend",
		MAGMA_THROW_EXPLOSION_MODEL_NAME = "Explosion",
		MAGMA_THROW_LEFT_HAND_MODEL_NAME = "LeftHand",
		MAGMA_THROW_PROJECTILE_MODEL_NAME = "Projectile",
		MAGMA_THROW_ROOT_PART_MODEL_NAME = "RootPart",
		MAGMA_THROW_VFX_NAME = "MagmaThrow",
	},
	Timing = {
		MAGMA_THROW_EXPLOSION_VFX_LIFETIME_SECONDS = 4,
		MAGMA_THROW_LEFT_HAND_VFX_LIFETIME_SECONDS = 2,
		MAGMA_THROW_ROOT_PART_EMIT_DELAY_SECONDS = 92 / 60,
		MAGMA_THROW_ROOT_PART_VFX_LIFETIME_SECONDS = 5,
	},
}

local MAGMA_FIEND_VFX_FOLDER_NAME = Constants.Vfx.MAGMA_FIEND_VFX_FOLDER_NAME
local MAGMA_THROW_EXPLOSION_MODEL_NAME = Constants.Vfx.MAGMA_THROW_EXPLOSION_MODEL_NAME
local MAGMA_THROW_EXPLOSION_VFX_LIFETIME_SECONDS = Constants.Timing.MAGMA_THROW_EXPLOSION_VFX_LIFETIME_SECONDS
local MAGMA_THROW_LEFT_HAND_MODEL_NAME = Constants.Vfx.MAGMA_THROW_LEFT_HAND_MODEL_NAME
local MAGMA_THROW_LEFT_HAND_VFX_LIFETIME_SECONDS = Constants.Timing.MAGMA_THROW_LEFT_HAND_VFX_LIFETIME_SECONDS
local MAGMA_THROW_MODULE_ID = Constants.ModuleIds.MAGMA_THROW_MODULE_ID
local MAGMA_THROW_PROJECTILE_MODEL_NAME = Constants.Vfx.MAGMA_THROW_PROJECTILE_MODEL_NAME
local MAGMA_THROW_ROOT_PART_EMIT_DELAY_SECONDS = Constants.Timing.MAGMA_THROW_ROOT_PART_EMIT_DELAY_SECONDS
local MAGMA_THROW_ROOT_PART_MODEL_NAME = Constants.Vfx.MAGMA_THROW_ROOT_PART_MODEL_NAME
local MAGMA_THROW_ROOT_PART_VFX_LIFETIME_SECONDS = Constants.Timing.MAGMA_THROW_ROOT_PART_VFX_LIFETIME_SECONDS
local MAGMA_THROW_VFX_NAME = Constants.Vfx.MAGMA_THROW_VFX_NAME

local Handler = {}

function Handler:_updateMagmaThrowMotion(record: ActiveRecord, nowServerTime: number)
	local projectileModel = record.projectileModel
	local projectileMotion = record.projectileMotion
	if projectileModel == nil or projectileMotion == nil or projectileModel.Parent == nil then
		return
	end

	local alpha = math.clamp(
		(nowServerTime - projectileMotion.startedAtServerTime) / math.max(0.001, projectileMotion.travelDuration),
		0,
		1
	)
	local position = projectileMotion.startPosition:Lerp(projectileMotion.impactPosition, alpha)
	local travelVector = projectileMotion.impactPosition - projectileMotion.startPosition
	if travelVector.Magnitude > 0.001 then
		projectileModel:PivotTo(CFrame.lookAt(position, position + travelVector.Unit))
	else
		projectileModel:PivotTo(CFrame.new(position))
	end
end

function Handler:_startMagmaThrow(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local bossLeftHand = self:resolveBossLeftHandPart(bossModel)
	local bossRootPart = self:resolveBossRootPart(bossModel)
	if bossLeftHand == nil or bossRootPart == nil then
		self:warnWithPrefix("Magma Throw presentation could not resolve the live boss LeftHand/RootPart.")
		self:_cleanupRecord(record)
		return
	end

	local leftHandSource = self:resolveBossVfxModel(
		MAGMA_FIEND_VFX_FOLDER_NAME,
		MAGMA_THROW_VFX_NAME,
		MAGMA_THROW_LEFT_HAND_MODEL_NAME
	)
	local rootSource = self:resolveBossVfxModel(
		MAGMA_FIEND_VFX_FOLDER_NAME,
		MAGMA_THROW_VFX_NAME,
		MAGMA_THROW_ROOT_PART_MODEL_NAME
	)
	if leftHandSource == nil or rootSource == nil then
		self:warnWithPrefix("Magma Throw left-hand/root VFX models are missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local castFolder = self:_ensureCastFolder(record)
	local scaleMultiplier = math.max(0.1, tonumber(event.payload and event.payload.scaleMultiplier) or 1)
	local leftHandModel = leftHandSource:Clone()
	local rootModel = rootSource:Clone()
	leftHandModel:ScaleTo(scaleMultiplier)
	rootModel:ScaleTo(scaleMultiplier)
	self:prepareAttachedEffectModel(leftHandModel)
	self:prepareAttachedEffectModel(rootModel)
	self:scaleAttachedSounds(leftHandModel, scaleMultiplier)
	self:scaleAttachedSounds(rootModel, scaleMultiplier)
	leftHandModel.Parent = castFolder
	rootModel.Parent = castFolder
	record.leftHandModel = leftHandModel
	record.rootModel = rootModel

	if not self:attachEffectModel(leftHandModel, bossLeftHand) or not self:attachEffectModel(rootModel, bossRootPart) then
		self:warnWithPrefix("Magma Throw left-hand/root VFX models are missing BasePart configuration.")
		self:_cleanupRecord(record)
		return
	end

	self:playAllSoundsFromConfiguredPositions(leftHandModel, scaleMultiplier)
	self:emitEffectInstance(leftHandModel)
	self:playTimedSounds(rootModel, scaleMultiplier)
	self:emitEffectInstanceAfter(
		rootModel,
		MAGMA_THROW_ROOT_PART_VFX_LIFETIME_SECONDS,
		MAGMA_THROW_ROOT_PART_EMIT_DELAY_SECONDS
	)
end

function Handler:_throwMagmaThrow(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" then
		return
	end

	local startPosition = payload.startPosition
	local impactPosition = payload.impactPosition
	local travelDuration = tonumber(payload.travelDuration)
	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	if typeof(startPosition) ~= "Vector3" or typeof(impactPosition) ~= "Vector3" or travelDuration == nil then
		return
	end

	local castFolder = self:_ensureCastFolder(record)
	local projectileSource = self:resolveBossVfxModel(
		MAGMA_FIEND_VFX_FOLDER_NAME,
		MAGMA_THROW_VFX_NAME,
		MAGMA_THROW_PROJECTILE_MODEL_NAME
	)
	if projectileSource == nil then
		self:warnWithPrefix("Magma Throw projectile VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local visualStartPosition = startPosition
	local leftHandModel = record.leftHandModel
	if leftHandModel and leftHandModel.Parent then
		visualStartPosition = leftHandModel:GetPivot().Position
		self:setBasePartTransparency(leftHandModel, 1)
		self:destroyVfxAfter(leftHandModel, MAGMA_THROW_LEFT_HAND_VFX_LIFETIME_SECONDS)
	end

	local projectileModel = projectileSource:Clone()
	projectileModel:ScaleTo(scaleMultiplier)
	self:prepareMovingEffectModel(projectileModel)
	self:enableVfxDescendants(projectileModel)
	self:scaleAttachedSounds(projectileModel, scaleMultiplier)
	if self:resolveEffectModelPrimaryPart(projectileModel) == nil then
		projectileModel:Destroy()
		self:warnWithPrefix("Magma Throw projectile VFX model is missing a BasePart for motion.")
		self:_cleanupRecord(record)
		return
	end

	projectileModel.Parent = castFolder
	projectileModel:PivotTo(CFrame.new(visualStartPosition))
	record.projectileModel = projectileModel
	record.projectileMotion = {
		startPosition = visualStartPosition,
		impactPosition = impactPosition,
		travelDuration = math.max(0.001, travelDuration),
		startedAtServerTime = if typeof(event.serverTime) == "number" then event.serverTime else self.Workspace:GetServerTimeNow(),
	}

	self:playAllSounds(projectileModel, scaleMultiplier)
	self:_updateMagmaThrowMotion(record, self.Workspace:GetServerTimeNow())
end

function Handler:_impactMagmaThrow(record: ActiveRecord, event: PresentationEvent)
	self:_shakeImpact()

	local payload = event.payload
	if typeof(payload) ~= "table" then
		self:_cleanupRecord(record)
		return
	end

	local impactPosition = payload.impactPosition
	if typeof(impactPosition) ~= "Vector3" then
		self:_cleanupRecord(record)
		return
	end

	if record.projectileModel and record.projectileModel.Parent then
		record.projectileModel:Destroy()
	end
	record.projectileModel = nil
	record.projectileMotion = nil

	local explosionSource = self:resolveBossVfxModel(
		MAGMA_FIEND_VFX_FOLDER_NAME,
		MAGMA_THROW_VFX_NAME,
		MAGMA_THROW_EXPLOSION_MODEL_NAME
	)
	if explosionSource == nil then
		self:warnWithPrefix("Magma Throw explosion VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	local explosionModel = explosionSource:Clone()
	explosionModel:ScaleTo(scaleMultiplier)
	self:prepareMovingEffectModel(explosionModel)
	explosionModel:PivotTo(CFrame.new(impactPosition))
	explosionModel.Parent = self:_ensureVisualFolder()

	self:playAllSounds(explosionModel, scaleMultiplier)
	self:emitEffectInstance(explosionModel, MAGMA_THROW_EXPLOSION_VFX_LIFETIME_SECONDS)
	self:_cleanupRecord(record)
end

Handler.moduleIds = {
	MAGMA_THROW_MODULE_ID,
}
Handler.start = Handler._startMagmaThrow
Handler.update = Handler._updateMagmaThrowMotion
Handler.actions = {
	throw = Handler._throwMagmaThrow,
	impact = Handler._impactMagmaThrow,
}
Handler.requiredParentFields = {
	"projectileModel",
}
Handler.requiresHandle = false

return Handler
