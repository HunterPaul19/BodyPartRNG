type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		BUBBLE_BLAST_MODULE_ID = "Moves.MerfinTheGreat.BubbleBlast",
	},
	Vfx = {
		BUBBLE_BLAST_HIT_MODEL_NAME = "Hit",
		BUBBLE_BLAST_LEFT_HAND_MODEL_NAME = "LeftHand",
		BUBBLE_BLAST_PROJECTILE_MODEL_NAME = "Projectile",
		BUBBLE_BLAST_ROOT_PART_MODEL_NAME = "RootPart",
		BUBBLE_BLAST_VFX_NAME = "BubbleBlast",
		MERFIN_THE_GREAT_VFX_FOLDER_NAME = "MerfinTheGreat",
	},
	Timing = {
		BUBBLE_BLAST_HIT_LIFETIME_SECONDS = 2.5,
		BUBBLE_BLAST_ROOT_PART_EMIT_DELAY_SECONDS = 65 / 60,
		BUBBLE_BLAST_PROJECTILE_VISUAL_SCALE = 2.5,
	},
}

local BUBBLE_BLAST_HIT_LIFETIME_SECONDS = Constants.Timing.BUBBLE_BLAST_HIT_LIFETIME_SECONDS
local BUBBLE_BLAST_HIT_MODEL_NAME = Constants.Vfx.BUBBLE_BLAST_HIT_MODEL_NAME
local BUBBLE_BLAST_LEFT_HAND_MODEL_NAME = Constants.Vfx.BUBBLE_BLAST_LEFT_HAND_MODEL_NAME
local BUBBLE_BLAST_MODULE_ID = Constants.ModuleIds.BUBBLE_BLAST_MODULE_ID
local BUBBLE_BLAST_PROJECTILE_MODEL_NAME = Constants.Vfx.BUBBLE_BLAST_PROJECTILE_MODEL_NAME
local BUBBLE_BLAST_PROJECTILE_VISUAL_SCALE = Constants.Timing.BUBBLE_BLAST_PROJECTILE_VISUAL_SCALE
local BUBBLE_BLAST_ROOT_PART_EMIT_DELAY_SECONDS = Constants.Timing.BUBBLE_BLAST_ROOT_PART_EMIT_DELAY_SECONDS
local BUBBLE_BLAST_ROOT_PART_MODEL_NAME = Constants.Vfx.BUBBLE_BLAST_ROOT_PART_MODEL_NAME
local BUBBLE_BLAST_VFX_NAME = Constants.Vfx.BUBBLE_BLAST_VFX_NAME
local MERFIN_THE_GREAT_VFX_FOLDER_NAME = Constants.Vfx.MERFIN_THE_GREAT_VFX_FOLDER_NAME

local Handler = {}

function Handler:_updateBubbleBlastProjectiles(record: ActiveRecord, nowServerTime: number)
	local projectileModels = record.bubbleBlastProjectileModels
	local projectileMotions = record.bubbleBlastProjectileMotions
	if projectileModels == nil or projectileMotions == nil then
		return
	end

	for index, projectileModel in pairs(projectileModels) do
		local motion = projectileMotions[index]
		if projectileModel.Parent == nil or motion == nil then
			continue
		end

		local alpha = math.clamp(
			(nowServerTime - motion.startedAtServerTime) / math.max(0.001, motion.travelDuration),
			0,
			1
		)
		local position = if typeof(motion.controlPosition) == "Vector3"
			then self:resolveQuadraticBezierPosition(
				motion.startPosition,
				motion.controlPosition,
				motion.impactPosition,
				alpha
			)
			else motion.startPosition:Lerp(motion.impactPosition, alpha)
		projectileModel:PivotTo(CFrame.new(position))
	end
end

function Handler:_startBubbleBlast(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local bossLeftHand = self:resolveBossLeftHandPart(bossModel)
	local bossRootPart = self:resolveBossRootPart(bossModel)
	if bossLeftHand == nil or bossRootPart == nil then
		self:warnWithPrefix("Bubble Blast presentation could not resolve the live boss LeftHand/RootPart.")
		self:_cleanupRecord(record)
		return
	end

	local leftHandSource = self:resolveBossVfxModel(
		MERFIN_THE_GREAT_VFX_FOLDER_NAME,
		BUBBLE_BLAST_VFX_NAME,
		BUBBLE_BLAST_LEFT_HAND_MODEL_NAME
	)
	local rootPartSource = self:resolveBossVfxModel(
		MERFIN_THE_GREAT_VFX_FOLDER_NAME,
		BUBBLE_BLAST_VFX_NAME,
		BUBBLE_BLAST_ROOT_PART_MODEL_NAME
	)
	if leftHandSource == nil or rootPartSource == nil then
		self:warnWithPrefix("Bubble Blast LeftHand/RootPart VFX models are missing from ReplicatedStorage.GameAssets.Effects.Bosses.")
		self:_cleanupRecord(record)
		return
	end

	local payload = event.payload
	local scaleMultiplier = math.max(0.1, tonumber(payload and payload.scaleMultiplier) or 1)
	local castFolder = self:_ensureCastFolder(record)
	local leftHandModel = leftHandSource:Clone()
	local rootPartModel = rootPartSource:Clone()
	leftHandModel:ScaleTo(scaleMultiplier)
	rootPartModel:ScaleTo(scaleMultiplier)
	self:prepareAttachedEffectModel(leftHandModel)
	self:prepareAttachedEffectModel(rootPartModel)
	self:enableVfxDescendants(leftHandModel)
	self:scaleAttachedSounds(leftHandModel, scaleMultiplier)
	self:scaleAttachedSounds(rootPartModel, scaleMultiplier)

	leftHandModel.Parent = castFolder
	rootPartModel.Parent = castFolder
	record.leftHandModel = leftHandModel
	record.rootModel = rootPartModel

	if not self:attachEffectModel(leftHandModel, bossLeftHand) or not self:attachEffectModel(rootPartModel, bossRootPart) then
		self:warnWithPrefix("Bubble Blast attached VFX models are missing BasePart configuration.")
		self:_cleanupRecord(record)
		return
	end

	self:playTimedSounds(leftHandModel, scaleMultiplier)
	self:playTimedSounds(rootPartModel, scaleMultiplier)
	self:emitEffectInstance(leftHandModel)
	self:emitEffectInstanceAfter(rootPartModel, nil, BUBBLE_BLAST_ROOT_PART_EMIT_DELAY_SECONDS)
end

function Handler:_launchBubbleBlastProjectiles(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.projectiles) ~= "table" then
		return
	end

	local projectileSource = self:resolveBossVfxModel(
		MERFIN_THE_GREAT_VFX_FOLDER_NAME,
		BUBBLE_BLAST_VFX_NAME,
		BUBBLE_BLAST_PROJECTILE_MODEL_NAME
	)
	if projectileSource == nil then
		self:warnWithPrefix("Bubble Blast projectile VFX model is missing from ReplicatedStorage.GameAssets.Effects.Bosses.")
		self:_cleanupRecord(record)
		return
	end

	local castFolder = self:_ensureCastFolder(record)
	local scaleMultiplier = BUBBLE_BLAST_PROJECTILE_VISUAL_SCALE
	local startedAtServerTime = if typeof(event.serverTime) == "number" then event.serverTime else self.Workspace:GetServerTimeNow()
	record.bubbleBlastProjectileModels = {}
	record.bubbleBlastProjectileMotions = {}

	for _, projectileData in ipairs(payload.projectiles) do
		if typeof(projectileData) ~= "table" then
			continue
		end

		local index = math.floor(tonumber(projectileData.index) or 0)
		local startPosition = projectileData.startPosition
		local controlPosition = projectileData.controlPosition
		local impactPosition = projectileData.impactPosition
		local travelDuration = tonumber(projectileData.travelDuration)
		if index <= 0
			or typeof(startPosition) ~= "Vector3"
			or typeof(impactPosition) ~= "Vector3"
			or travelDuration == nil then
			continue
		end

		local projectileModel = projectileSource:Clone()
		projectileModel:ScaleTo(scaleMultiplier)
		self:prepareMovingEffectModel(projectileModel)
		self:enableVfxDescendants(projectileModel)
		self:scaleAttachedSounds(projectileModel, scaleMultiplier)
		if self:resolveEffectModelPrimaryPart(projectileModel) == nil then
			projectileModel:Destroy()
			self:warnWithPrefix("Bubble Blast projectile VFX model is missing a BasePart for motion.")
			continue
		end

		projectileModel.Parent = castFolder
		projectileModel:PivotTo(CFrame.new(startPosition))
		self:enableVfxDescendants(projectileModel)
		self:playTimedSounds(projectileModel, scaleMultiplier)

		record.bubbleBlastProjectileModels[index] = projectileModel
		record.bubbleBlastProjectileMotions[index] = {
			startPosition = startPosition,
			controlPosition = controlPosition,
			impactPosition = impactPosition,
			travelDuration = math.max(0.001, travelDuration),
			startedAtServerTime = startedAtServerTime,
		}
	end

	self:_updateBubbleBlastProjectiles(record, self.Workspace:GetServerTimeNow())
end

function Handler:_impactBubbleBlast(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" then
		return
	end

	local index = math.floor(tonumber(payload.index) or 0)
	local impactPosition = payload.impactPosition
	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	if typeof(impactPosition) ~= "Vector3" then
		return
	end

	if record.bubbleBlastProjectileModels and index > 0 then
		local projectileModel = record.bubbleBlastProjectileModels[index]
		if projectileModel and projectileModel.Parent then
			projectileModel:Destroy()
		end
		record.bubbleBlastProjectileModels[index] = nil
	end
	if record.bubbleBlastProjectileMotions and index > 0 then
		record.bubbleBlastProjectileMotions[index] = nil
	end

	local hitSource = self:resolveBossVfxModel(
		MERFIN_THE_GREAT_VFX_FOLDER_NAME,
		BUBBLE_BLAST_VFX_NAME,
		BUBBLE_BLAST_HIT_MODEL_NAME
	)
	if hitSource == nil then
		self:warnWithPrefix("Bubble Blast hit VFX model is missing from ReplicatedStorage.GameAssets.Effects.Bosses.")
		return
	end

	local hitModel = hitSource:Clone()
	hitModel:ScaleTo(scaleMultiplier)
	self:prepareMovingEffectModel(hitModel)
	hitModel:PivotTo(CFrame.new(impactPosition))
	hitModel.Parent = self:_ensureVisualFolder()
	self:playAllSounds(hitModel, scaleMultiplier)
	self:emitEffectInstance(hitModel, BUBBLE_BLAST_HIT_LIFETIME_SECONDS)
end

Handler.moduleIds = {
	BUBBLE_BLAST_MODULE_ID,
}
Handler.start = Handler._startBubbleBlast
Handler.update = Handler._updateBubbleBlastProjectiles
Handler.actions = {
	projectiles = Handler._launchBubbleBlastProjectiles,
	impact = Handler._impactBubbleBlast,
}
Handler.requiredParentFields = {
	"leftHandModel",
	"rootModel",
}

return Handler
