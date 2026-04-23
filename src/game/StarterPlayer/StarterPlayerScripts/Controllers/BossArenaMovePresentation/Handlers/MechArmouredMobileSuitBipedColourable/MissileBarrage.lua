type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		DESTROYER_MISSILE_BARRAGE_MODULE_ID = "Moves.Destroyer3000.MissileBarrage",
		MECHA_MISSILE_BARRAGE_MODULE_ID = "Moves.MechArmouredMobileSuitBipedColourable.MissileBarrage",
	},
	Vfx = {
		DESTROYER_3000_VFX_FOLDER_NAME = "Destroyer3000",
		DESTROYER_MISSILE_BARRAGE_EXPLODE_VFX_NAME = "Explode",
		DESTROYER_MISSILE_BARRAGE_PROJECTILE_VFX_NAME = "Projectile",
		DESTROYER_MISSILE_BARRAGE_ROOT_PART_VFX_NAME = "RootPart",
		DESTROYER_MISSILE_BARRAGE_SPAWN_VFX_NAME = "Spawn",
		DESTROYER_MISSILE_BARRAGE_UPPER_TORSO_VFX_NAME = "UpperTorso",
		DESTROYER_MISSILE_BARRAGE_VFX_NAME = "MissileBarrage",
	},
	Timing = {
		DESTROYER_MISSILE_BARRAGE_EXPLOSION_LIFETIME_SECONDS = 4.5,
		DESTROYER_MISSILE_BARRAGE_GLINT_EMIT_DELAY_SECONDS = 0.15,
	},
}

local DESTROYER_3000_VFX_FOLDER_NAME = Constants.Vfx.DESTROYER_3000_VFX_FOLDER_NAME
local DESTROYER_MISSILE_BARRAGE_GLINT_EMIT_DELAY_SECONDS =
	Constants.Timing.DESTROYER_MISSILE_BARRAGE_GLINT_EMIT_DELAY_SECONDS
local DESTROYER_MISSILE_BARRAGE_EXPLODE_VFX_NAME = Constants.Vfx.DESTROYER_MISSILE_BARRAGE_EXPLODE_VFX_NAME
local DESTROYER_MISSILE_BARRAGE_EXPLOSION_LIFETIME_SECONDS = Constants.Timing.DESTROYER_MISSILE_BARRAGE_EXPLOSION_LIFETIME_SECONDS
local DESTROYER_MISSILE_BARRAGE_MODULE_ID = Constants.ModuleIds.DESTROYER_MISSILE_BARRAGE_MODULE_ID
local DESTROYER_MISSILE_BARRAGE_PROJECTILE_VFX_NAME = Constants.Vfx.DESTROYER_MISSILE_BARRAGE_PROJECTILE_VFX_NAME
local DESTROYER_MISSILE_BARRAGE_ROOT_PART_VFX_NAME = Constants.Vfx.DESTROYER_MISSILE_BARRAGE_ROOT_PART_VFX_NAME
local DESTROYER_MISSILE_BARRAGE_SPAWN_VFX_NAME = Constants.Vfx.DESTROYER_MISSILE_BARRAGE_SPAWN_VFX_NAME
local DESTROYER_MISSILE_BARRAGE_UPPER_TORSO_VFX_NAME = Constants.Vfx.DESTROYER_MISSILE_BARRAGE_UPPER_TORSO_VFX_NAME
local DESTROYER_MISSILE_BARRAGE_VFX_NAME = Constants.Vfx.DESTROYER_MISSILE_BARRAGE_VFX_NAME
local MECHA_MISSILE_BARRAGE_MODULE_ID = Constants.ModuleIds.MECHA_MISSILE_BARRAGE_MODULE_ID

local Handler = {}

local function findFirstDescendantNamed(root: Instance, name: string): Instance?
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant.Name == name then
			return descendant
		end
	end

	return nil
end

local function setGlintEmitDelay(root: Instance, delaySeconds: number)
	for _, descendant in ipairs(root:GetDescendants()) do
		if not descendant:IsA("ParticleEmitter") then
			continue
		end

		local parent = descendant.Parent
		if parent and string.lower(parent.Name) == "glint" then
			descendant:SetAttribute("EmitDelay", delaySeconds)
		end
	end
end

function Handler:_updateMissileBarrageProjectiles(record: ActiveRecord, nowServerTime: number)
	local projectileModels = record.missileBarrageProjectileModels
	local projectileMotions = record.missileBarrageProjectileMotions
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
		local position = self:resolveQuadraticBezierPosition(
			motion.startPosition,
			motion.controlPosition,
			motion.impactPosition,
			alpha
		)
		local lookAheadAlpha = math.clamp(alpha + 0.03, 0, 1)
		local lookAheadPosition = self:resolveQuadraticBezierPosition(
			motion.startPosition,
			motion.controlPosition,
			motion.impactPosition,
			lookAheadAlpha
		)
		local travelVector = lookAheadPosition - position
		if travelVector.Magnitude > 0.001 then
			projectileModel:PivotTo(CFrame.lookAt(position, position + travelVector.Unit))
		else
			projectileModel:PivotTo(CFrame.new(position))
		end
	end
end

function Handler:_startDestroyerMissileBarrage(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local bossUpperTorso = self:resolveBossUpperTorsoPart(bossModel)
	local bossRootPart = self:resolveBossRootPart(bossModel)
	if bossUpperTorso == nil or bossRootPart == nil then
		self:warnWithPrefix("Missile Barrage presentation could not resolve the live boss UpperTorso/RootPart.")
		self:_cleanupRecord(record)
		return
	end

	local upperTorsoSource = self:resolveBossVfxModel(
		DESTROYER_3000_VFX_FOLDER_NAME,
		DESTROYER_MISSILE_BARRAGE_VFX_NAME,
		DESTROYER_MISSILE_BARRAGE_UPPER_TORSO_VFX_NAME
	)
	local rootPartSource = self:resolveBossVfxModel(
		DESTROYER_3000_VFX_FOLDER_NAME,
		DESTROYER_MISSILE_BARRAGE_VFX_NAME,
		DESTROYER_MISSILE_BARRAGE_ROOT_PART_VFX_NAME
	)
	if upperTorsoSource == nil or rootPartSource == nil then
		self:warnWithPrefix("Missile Barrage UpperTorso/RootPart VFX models are missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local payload = event.payload
	local scaleMultiplier = math.max(0.1, tonumber(payload and payload.scaleMultiplier) or 1)
	local castFolder = self:_ensureCastFolder(record)
	local upperTorsoModel = upperTorsoSource:Clone()
	local rootPartModel = rootPartSource:Clone()
	upperTorsoModel:ScaleTo(scaleMultiplier)
	rootPartModel:ScaleTo(scaleMultiplier)
	self:prepareAttachedEffectModel(upperTorsoModel)
	self:prepareAttachedEffectModel(rootPartModel)
	self:enableVfxDescendants(upperTorsoModel)
	self:enableVfxDescendants(rootPartModel)
	setGlintEmitDelay(upperTorsoModel, DESTROYER_MISSILE_BARRAGE_GLINT_EMIT_DELAY_SECONDS)
	self:scaleAttachedSounds(upperTorsoModel, scaleMultiplier)
	self:scaleAttachedSounds(rootPartModel, scaleMultiplier)

	upperTorsoModel.Parent = castFolder
	rootPartModel.Parent = castFolder
	record.upperTorsoModel = upperTorsoModel
	record.rootModel = rootPartModel
	record.missileBarrageProjectileModels = {}
	record.missileBarrageProjectileMotions = {}

	if not self:attachEffectModel(upperTorsoModel, bossUpperTorso) or not self:attachEffectModel(rootPartModel, bossRootPart) then
		self:warnWithPrefix("Missile Barrage attached VFX models are missing BasePart configuration.")
		self:_cleanupRecord(record)
		return
	end

	self:playTimedSounds(upperTorsoModel, scaleMultiplier)
	self:playTimedSounds(rootPartModel, scaleMultiplier)
	self:emitEffectInstance(upperTorsoModel)
	self:emitEffectInstance(rootPartModel)
end

function Handler:_launchDestroyerMissile(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" then
		return
	end

	local index = math.floor(tonumber(payload.index) or 0)
	local startCFrame = payload.startCFrame
	local startPosition = payload.startPosition
	local controlPosition = payload.controlPosition
	local impactPosition = payload.impactPosition
	local travelDuration = tonumber(payload.travelDuration)
	if index <= 0
		or typeof(startPosition) ~= "Vector3"
		or typeof(controlPosition) ~= "Vector3"
		or typeof(impactPosition) ~= "Vector3"
		or travelDuration == nil then
		return
	end

	local projectileSource = self:resolveBossVfxModel(
		DESTROYER_3000_VFX_FOLDER_NAME,
		DESTROYER_MISSILE_BARRAGE_VFX_NAME,
		DESTROYER_MISSILE_BARRAGE_PROJECTILE_VFX_NAME
	)
	if projectileSource == nil then
		self:warnWithPrefix("Missile Barrage projectile VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local castFolder = self:_ensureCastFolder(record)
	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	local projectileModel = projectileSource:Clone()
	projectileModel:ScaleTo(scaleMultiplier)
	self:prepareMovingEffectModel(projectileModel)
	self:enableVfxDescendants(projectileModel)
	self:scaleAttachedSounds(projectileModel, scaleMultiplier)
	if self:resolveEffectModelPrimaryPart(projectileModel) == nil then
		projectileModel:Destroy()
		self:warnWithPrefix("Missile Barrage projectile VFX model is missing a BasePart for motion.")
		return
	end

	projectileModel.Parent = castFolder
	if typeof(startCFrame) == "CFrame" then
		projectileModel:PivotTo(startCFrame)
	else
		projectileModel:PivotTo(CFrame.new(startPosition))
	end

	local spawnEffect = findFirstDescendantNamed(projectileModel, DESTROYER_MISSILE_BARRAGE_SPAWN_VFX_NAME)
	if spawnEffect then
		self:playTimedSounds(spawnEffect, scaleMultiplier)
		self:emitEffectInstance(spawnEffect)
	end

	record.missileBarrageProjectileModels = record.missileBarrageProjectileModels or {}
	record.missileBarrageProjectileMotions = record.missileBarrageProjectileMotions or {}
	record.missileBarrageProjectileModels[index] = projectileModel
	record.missileBarrageProjectileMotions[index] = {
		startPosition = startPosition,
		controlPosition = controlPosition,
		impactPosition = impactPosition,
		travelDuration = math.max(0.001, travelDuration),
		startedAtServerTime = if typeof(event.serverTime) == "number" then event.serverTime else self.Workspace:GetServerTimeNow(),
	}

	self:_updateMissileBarrageProjectiles(record, self.Workspace:GetServerTimeNow())
end

function Handler:_impactDestroyerMissile(record: ActiveRecord, event: PresentationEvent)
	self:_shakeImpact()

	local payload = event.payload
	if typeof(payload) ~= "table" then
		return
	end

	local index = math.floor(tonumber(payload.index) or 0)
	local impactPosition = payload.impactPosition
	if index <= 0 or typeof(impactPosition) ~= "Vector3" then
		return
	end

	local projectileModel = nil
	if record.missileBarrageProjectileModels then
		projectileModel = record.missileBarrageProjectileModels[index]
		record.missileBarrageProjectileModels[index] = nil
	end
	if record.missileBarrageProjectileMotions then
		record.missileBarrageProjectileMotions[index] = nil
	end
	if projectileModel == nil or projectileModel.Parent == nil then
		return
	end

	projectileModel:PivotTo(CFrame.new(impactPosition))
	projectileModel.Parent = self:_ensureVisualFolder()
	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	local explodeEffect = findFirstDescendantNamed(projectileModel, DESTROYER_MISSILE_BARRAGE_EXPLODE_VFX_NAME)
	if explodeEffect == nil then
		self:warnWithPrefix("Missile Barrage projectile Explode VFX instance is missing from the packaged projectile.")
		self:destroyVfxAfter(projectileModel, 0)
		return
	end

	self:playTimedSounds(explodeEffect, scaleMultiplier)
	self:emitEffectInstance(explodeEffect, DESTROYER_MISSILE_BARRAGE_EXPLOSION_LIFETIME_SECONDS)
	self:destroyVfxAfter(projectileModel, DESTROYER_MISSILE_BARRAGE_EXPLOSION_LIFETIME_SECONDS)
end

Handler.moduleIds = {
	MECHA_MISSILE_BARRAGE_MODULE_ID,
	DESTROYER_MISSILE_BARRAGE_MODULE_ID,
}
Handler.start = Handler._startDestroyerMissileBarrage
Handler.update = Handler._updateMissileBarrageProjectiles
Handler.actions = {
	launch = Handler._launchDestroyerMissile,
	impact = Handler._impactDestroyerMissile,
}
Handler.requiredParentFields = {
	"upperTorsoModel",
	"rootModel",
}
Handler.requiresHandle = false

return Handler
