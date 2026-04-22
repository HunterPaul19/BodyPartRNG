type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		WATER_BOMB_MODULE_ID = "Moves.MerfinTheGreat.WaterBomb",
	},
	Vfx = {
		MERFIN_THE_GREAT_VFX_FOLDER_NAME = "MerfinTheGreat",
		WATER_BOMB_BALL_MODEL_NAME = "Ball",
		WATER_BOMB_EXPLOSION_MODEL_NAME = "BombExplosion",
		WATER_BOMB_FLOOR_MODEL_NAME = "Floor",
		WATER_BOMB_VFX_NAME = "WaterBomb",
	},
	Timing = {
		WATER_BOMB_EXPLOSION_LIFETIME_SECONDS = 3,
		WATER_BOMB_FLOOR_LIFETIME_SECONDS = 2.5,
	},
}

local MERFIN_THE_GREAT_VFX_FOLDER_NAME = Constants.Vfx.MERFIN_THE_GREAT_VFX_FOLDER_NAME
local WATER_BOMB_BALL_MODEL_NAME = Constants.Vfx.WATER_BOMB_BALL_MODEL_NAME
local WATER_BOMB_EXPLOSION_LIFETIME_SECONDS = Constants.Timing.WATER_BOMB_EXPLOSION_LIFETIME_SECONDS
local WATER_BOMB_EXPLOSION_MODEL_NAME = Constants.Vfx.WATER_BOMB_EXPLOSION_MODEL_NAME
local WATER_BOMB_FLOOR_LIFETIME_SECONDS = Constants.Timing.WATER_BOMB_FLOOR_LIFETIME_SECONDS
local WATER_BOMB_FLOOR_MODEL_NAME = Constants.Vfx.WATER_BOMB_FLOOR_MODEL_NAME
local WATER_BOMB_MODULE_ID = Constants.ModuleIds.WATER_BOMB_MODULE_ID
local WATER_BOMB_VFX_NAME = Constants.Vfx.WATER_BOMB_VFX_NAME

local Handler = {}

function Handler:_updateWaterBombMotion(record: ActiveRecord, nowServerTime: number)
	local ballModel = record.projectileModel
	if ballModel == nil or ballModel.Parent == nil then
		return
	end

	local chargeData = record.waterBombChargeData
	if chargeData ~= nil then
		local alpha = math.clamp(
			(nowServerTime - chargeData.startedAtServerTime) / math.max(0.001, chargeData.duration),
			0,
			1
		)
		local position = chargeData.startPosition:Lerp(chargeData.endPosition, alpha)
		local scale = chargeData.startScale + ((chargeData.endScale - chargeData.startScale) * alpha)
		ballModel:ScaleTo(scale)
		ballModel:PivotTo(CFrame.new(position))
		return
	end

	local projectileMotion = record.projectileMotion
	if projectileMotion == nil then
		return
	end

	local alpha = math.clamp(
		(nowServerTime - projectileMotion.startedAtServerTime) / math.max(0.001, projectileMotion.travelDuration),
		0,
		1
	)
	local position = projectileMotion.startPosition:Lerp(projectileMotion.impactPosition, alpha)
	ballModel:PivotTo(CFrame.new(position))
end

function Handler:_startWaterBomb(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" then
		self:_cleanupRecord(record)
		return
	end

	local floorPosition = payload.floorPosition
	local chargeStartPosition = payload.chargeStartPosition
	local chargeEndPosition = payload.chargeEndPosition
	local chargeDurationSeconds = tonumber(payload.chargeDurationSeconds)
	local ballStartScale = tonumber(payload.ballStartScale)
	local ballEndScale = tonumber(payload.ballEndScale)
	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	if typeof(floorPosition) ~= "Vector3"
		or typeof(chargeStartPosition) ~= "Vector3"
		or typeof(chargeEndPosition) ~= "Vector3"
		or chargeDurationSeconds == nil
		or ballStartScale == nil
		or ballEndScale == nil then
		self:_cleanupRecord(record)
		return
	end

	local floorSource = self:resolveBossVfxModel(
		MERFIN_THE_GREAT_VFX_FOLDER_NAME,
		WATER_BOMB_VFX_NAME,
		WATER_BOMB_FLOOR_MODEL_NAME
	)
	local ballSource = self:resolveBossVfxModel(
		MERFIN_THE_GREAT_VFX_FOLDER_NAME,
		WATER_BOMB_VFX_NAME,
		WATER_BOMB_BALL_MODEL_NAME
	)
	if floorSource == nil or ballSource == nil then
		self:warnWithPrefix("Water Bomb floor/ball VFX models are missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local castFolder = self:_ensureCastFolder(record)
	local floorModel = floorSource:Clone()
	local ballModel = ballSource:Clone()
	floorModel:ScaleTo(scaleMultiplier)
	ballModel:ScaleTo(math.max(0.01, ballStartScale))
	self:prepareMovingEffectModel(floorModel)
	self:prepareMovingEffectModel(ballModel)
	self:enableVfxDescendants(ballModel)
	self:scaleAttachedSounds(floorModel, scaleMultiplier)
	self:scaleAttachedSounds(ballModel, math.max(0.1, ballEndScale))

	floorModel.Parent = castFolder
	ballModel.Parent = castFolder
	floorModel:PivotTo(CFrame.new(floorPosition))
	ballModel:PivotTo(CFrame.new(chargeStartPosition))

	self:playAllSounds(floorModel)
	self:playAllSounds(ballModel)
	self:emitEffectInstance(floorModel, WATER_BOMB_FLOOR_LIFETIME_SECONDS)

	record.rootModel = floorModel
	record.projectileModel = ballModel
	record.waterBombChargeData = {
		startPosition = chargeStartPosition,
		endPosition = chargeEndPosition,
		startScale = math.max(0.01, ballStartScale),
		endScale = math.max(0.01, ballEndScale),
		startedAtServerTime = if typeof(event.serverTime) == "number" then event.serverTime else self.Workspace:GetServerTimeNow(),
		duration = math.max(0.05, chargeDurationSeconds),
	}
	self:_updateWaterBombMotion(record, self.Workspace:GetServerTimeNow())
end

function Handler:_throwWaterBomb(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" then
		return
	end

	local startPosition = payload.startPosition
	local impactPosition = payload.impactPosition
	local travelDuration = tonumber(payload.travelDuration)
	local ballScale = math.max(0.01, tonumber(payload.ballScale) or 1)
	if typeof(startPosition) ~= "Vector3" or typeof(impactPosition) ~= "Vector3" or travelDuration == nil then
		return
	end

	local ballModel = record.projectileModel
	if ballModel == nil or ballModel.Parent == nil then
		local ballSource = self:resolveBossVfxModel(
			MERFIN_THE_GREAT_VFX_FOLDER_NAME,
			WATER_BOMB_VFX_NAME,
			WATER_BOMB_BALL_MODEL_NAME
		)
		if ballSource == nil then
			self:warnWithPrefix("Water Bomb ball VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
			self:_cleanupRecord(record)
			return
		end

		ballModel = ballSource:Clone()
		self:prepareMovingEffectModel(ballModel)
		self:enableVfxDescendants(ballModel)
		ballModel.Parent = self:_ensureCastFolder(record)
		record.projectileModel = ballModel
		self:playAllSounds(ballModel)
	end

	record.waterBombChargeData = nil
	record.projectileMotion = {
		startPosition = startPosition,
		impactPosition = impactPosition,
		travelDuration = math.max(0.001, travelDuration),
		startedAtServerTime = if typeof(event.serverTime) == "number" then event.serverTime else self.Workspace:GetServerTimeNow(),
	}

	ballModel:ScaleTo(ballScale)
	ballModel:PivotTo(CFrame.new(startPosition))
	self:_updateWaterBombMotion(record, self.Workspace:GetServerTimeNow())
end

function Handler:_impactWaterBomb(record: ActiveRecord, event: PresentationEvent)
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
	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)

	local explosionSource = self:resolveBossVfxModel(
		MERFIN_THE_GREAT_VFX_FOLDER_NAME,
		WATER_BOMB_VFX_NAME,
		WATER_BOMB_EXPLOSION_MODEL_NAME
	)
	if explosionSource == nil then
		self:warnWithPrefix("Water Bomb explosion VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	if record.projectileModel and record.projectileModel.Parent then
		record.projectileModel:Destroy()
	end
	record.projectileModel = nil
	record.projectileMotion = nil
	record.waterBombChargeData = nil

	local explosionModel = explosionSource:Clone()
	explosionModel:ScaleTo(scaleMultiplier)
	self:prepareMovingEffectModel(explosionModel)
	explosionModel:PivotTo(CFrame.new(impactPosition))
	explosionModel.Parent = self:_ensureVisualFolder()
	self:playAllSounds(explosionModel)
	self:emitEffectInstance(explosionModel, WATER_BOMB_EXPLOSION_LIFETIME_SECONDS)

	self:_cleanupRecord(record)
end

Handler.moduleIds = {
	WATER_BOMB_MODULE_ID,
}
Handler.start = Handler._startWaterBomb
Handler.update = Handler._updateWaterBombMotion
Handler.actions = {
	throw = Handler._throwWaterBomb,
	impact = Handler._impactWaterBomb,
}
Handler.requiredParentFields = {
	"projectileModel",
}

return Handler
