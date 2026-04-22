type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		SHIP_CALL_MODULE_ID = "Moves.CaptainSquid.ShipCall",
	},
	Vfx = {
		CAPTAIN_SQUID_SHIP_CALL_VFX_NAME = "ShipCall",
		CAPTAIN_SQUID_VFX_FOLDER_NAME = "CaptainSquid",
		SHIP_CALL_LEFT_HAND_MODEL_NAME = "LeftHand",
		SHIP_CALL_SHIP_MODEL_NAME = "Ship",
	},
}

local CAPTAIN_SQUID_SHIP_CALL_VFX_NAME = Constants.Vfx.CAPTAIN_SQUID_SHIP_CALL_VFX_NAME
local CAPTAIN_SQUID_VFX_FOLDER_NAME = Constants.Vfx.CAPTAIN_SQUID_VFX_FOLDER_NAME
local SHIP_CALL_LEFT_HAND_MODEL_NAME = Constants.Vfx.SHIP_CALL_LEFT_HAND_MODEL_NAME
local SHIP_CALL_MODULE_ID = Constants.ModuleIds.SHIP_CALL_MODULE_ID
local SHIP_CALL_SHIP_MODEL_NAME = Constants.Vfx.SHIP_CALL_SHIP_MODEL_NAME

local Handler = {}

function Handler:_updateShipCallMotion(record: ActiveRecord, nowServerTime: number)
	local shipModel = record.shipModel
	local shipMotion = record.shipMotion
	if shipModel == nil or shipMotion == nil or shipModel.Parent == nil then
		return
	end

	local elapsed = math.max(0, nowServerTime - shipMotion.startedAtServerTime)
	local currentPosition = shipMotion.startCFrame.Position + (shipMotion.direction * (shipMotion.speed * elapsed))
	shipModel:PivotTo(CFrame.new(currentPosition) * (shipMotion.startCFrame - shipMotion.startCFrame.Position))
end

function Handler:_shipShipCall(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	local bossLeftHand = self:resolveBossLeftHandPart(bossModel)
	if bossModel == nil or bossModel.Parent == nil or bossLeftHand == nil then
		self:_cleanupRecord(record)
		return
	end

	local payload = event.payload
	if typeof(payload) ~= "table" then
		return
	end

	local startCFrame = payload.startCFrame
	local direction = payload.direction
	local speed = tonumber(payload.speed)
	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	if typeof(startCFrame) ~= "CFrame" or typeof(direction) ~= "Vector3" or speed == nil or direction.Magnitude <= 0.001 then
		return
	end

	local leftHandSource = self:resolveBossVfxModel(
		CAPTAIN_SQUID_VFX_FOLDER_NAME,
		CAPTAIN_SQUID_SHIP_CALL_VFX_NAME,
		SHIP_CALL_LEFT_HAND_MODEL_NAME
	)
	local shipSource = self:resolveBossVfxModel(
		CAPTAIN_SQUID_VFX_FOLDER_NAME,
		CAPTAIN_SQUID_SHIP_CALL_VFX_NAME,
		SHIP_CALL_SHIP_MODEL_NAME
	)
	if leftHandSource == nil or shipSource == nil then
		self:warnWithPrefix("Ship Call VFX models are missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local castFolder = self:_ensureCastFolder(record)
	local leftHandModel = leftHandSource:Clone()
	local shipModel = shipSource:Clone()
	leftHandModel:ScaleTo(scaleMultiplier)
	shipModel:ScaleTo(scaleMultiplier)
	self:prepareAttachedEffectModel(leftHandModel)
	self:prepareMovingEffectModel(shipModel)
	self:scaleAttachedSounds(leftHandModel, scaleMultiplier)
	self:scaleAttachedSounds(shipModel, scaleMultiplier)

	if self:resolveEffectModelPrimaryPart(leftHandModel) == nil or self:resolveEffectModelPrimaryPart(shipModel) == nil then
		self:warnWithPrefix("Ship Call VFX models are missing BasePart configuration.")
		self:_cleanupRecord(record)
		return
	end

	leftHandModel.Parent = castFolder
	shipModel.Parent = castFolder
	record.leftHandModel = leftHandModel
	record.shipModel = shipModel
	record.shipMotion = {
		startCFrame = startCFrame,
		direction = direction.Unit,
		speed = speed,
		startedAtServerTime = if typeof(event.serverTime) == "number" then event.serverTime else self.Workspace:GetServerTimeNow(),
	}

	if not self:attachEffectModel(leftHandModel, bossLeftHand) then
		self:warnWithPrefix("Ship Call left-hand VFX model is missing BasePart configuration.")
		self:_cleanupRecord(record)
		return
	end

	shipModel:PivotTo(startCFrame)
	self:enableParticleEmitters(shipModel)
	self:playAllSounds(leftHandModel)
	self:playAllSounds(shipModel)
	self:emitVisuals(self:collectEmittableVisuals(leftHandModel))
	self:emitVisuals(self:collectEmittableVisuals(shipModel))
	self:_updateShipCallMotion(record, self.Workspace:GetServerTimeNow())
end

Handler.moduleIds = {
	SHIP_CALL_MODULE_ID,
}
Handler.update = Handler._updateShipCallMotion
Handler.actions = {
	ship = Handler._shipShipCall,
}
Handler.requiredParentFields = {
	"leftHandModel",
	"shipModel",
}

return Handler
