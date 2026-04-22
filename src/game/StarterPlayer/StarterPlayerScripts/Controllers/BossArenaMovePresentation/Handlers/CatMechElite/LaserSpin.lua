type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		CAT_MECH_ELITE_LASER_SPIN_MODULE_ID = "Moves.CatMechElite.LaserSpin",
	},
	Vfx = {
		CAT_MECH_ELITE_VFX_FOLDER_NAME = "CatMechElite",
		LASER_SPIN_VFX_NAME = "LaserSpin",
		LASER_SPIN_BEAMS_MODEL_NAME = "Beams",
		LASER_SPIN_SOUNDS_FOLDER_NAME = "Sounds",
	},
}

local CAT_MECH_ELITE_LASER_SPIN_MODULE_ID = Constants.ModuleIds.CAT_MECH_ELITE_LASER_SPIN_MODULE_ID
local CAT_MECH_ELITE_VFX_FOLDER_NAME = Constants.Vfx.CAT_MECH_ELITE_VFX_FOLDER_NAME
local LASER_SPIN_BEAMS_MODEL_NAME = Constants.Vfx.LASER_SPIN_BEAMS_MODEL_NAME
local LASER_SPIN_SOUNDS_FOLDER_NAME = Constants.Vfx.LASER_SPIN_SOUNDS_FOLDER_NAME
local LASER_SPIN_VFX_NAME = Constants.Vfx.LASER_SPIN_VFX_NAME

local DEFAULT_ACTIVE_WINDOW_SECONDS = 4
local DEFAULT_SPIN_RADIANS_PER_SECOND = (math.pi * 2) / (DEFAULT_ACTIVE_WINDOW_SECONDS * 2)
local DEFAULT_LASER_SPIN_SCALE = 20

local Handler = {}

local function resolvePrimaryPart(model: Model?): BasePart?
	if model == nil then
		return nil
	end

	local primaryPart = model.PrimaryPart
	if primaryPart then
		return primaryPart
	end

	local middle = model:FindFirstChild("Middle", true)
	if middle and middle:IsA("BasePart") then
		model.PrimaryPart = middle
		return middle
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

function Handler:_updateLaserSpin(record: ActiveRecord, nowServerTime: number)
	local motion = record.laserSpinMotion
	local beamsModel = record.laserSpinBeamsModel
	if motion == nil or beamsModel == nil or beamsModel.Parent == nil then
		return
	end

	local elapsed = math.max(0, nowServerTime - motion.startedAtServerTime)
	if elapsed >= motion.duration then
		self:_cleanupRecord(record)
		return
	end

	beamsModel:PivotTo(motion.baseCFrame * CFrame.Angles(0, elapsed * motion.spinRadiansPerSecond, 0))
end

function Handler:_startLaserSpin(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.baseCFrame) ~= "CFrame" then
		self:warnWithPrefix("Laser Spin presentation is missing baseCFrame payload.")
		self:_cleanupRecord(record)
		return
	end

	local beamsSource = self:resolveBossVfxModel(
		CAT_MECH_ELITE_VFX_FOLDER_NAME,
		LASER_SPIN_VFX_NAME,
		LASER_SPIN_BEAMS_MODEL_NAME
	)
	if beamsSource == nil then
		self:warnWithPrefix("Laser Spin Beams VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local soundsSource = self:resolveBossVfxInstance(
		CAT_MECH_ELITE_VFX_FOLDER_NAME,
		LASER_SPIN_VFX_NAME,
		LASER_SPIN_SOUNDS_FOLDER_NAME
	)
	local castFolder = self:_ensureCastFolder(record)
	local beamsModel = beamsSource:Clone()
	local visualScale = math.max(0.1, tonumber(payload.visualScale) or DEFAULT_LASER_SPIN_SCALE)
	beamsModel:ScaleTo(visualScale)
	self:prepareMovingEffectModel(beamsModel)
	self:scaleAttachedSounds(beamsModel, visualScale)
	beamsModel.Parent = castFolder
	self:enableVfxDescendants(beamsModel)

	local primaryPart = resolvePrimaryPart(beamsModel)
	if primaryPart == nil then
		self:warnWithPrefix("Laser Spin Beams VFX model is missing a PrimaryPart/BasePart.")
		self:_cleanupRecord(record)
		return
	end

	record.laserSpinBeamsModel = beamsModel
	record.laserSpinMotion = {
		baseCFrame = payload.baseCFrame,
		startedAtServerTime = if typeof(event.serverTime) == "number" then event.serverTime else self.Workspace:GetServerTimeNow(),
		duration = math.max(0.1, tonumber(payload.activeWindowSeconds) or DEFAULT_ACTIVE_WINDOW_SECONDS),
		spinRadiansPerSecond = tonumber(payload.spinRadiansPerSecond) or DEFAULT_SPIN_RADIANS_PER_SECOND,
	}

	beamsModel:PivotTo(payload.baseCFrame)
	if soundsSource then
		self:playDelayedSoundClones(soundsSource, primaryPart, visualScale)
	end
	self:_updateLaserSpin(record, self.Workspace:GetServerTimeNow())
end

Handler.moduleIds = {
	CAT_MECH_ELITE_LASER_SPIN_MODULE_ID,
}
Handler.start = Handler._startLaserSpin
Handler.update = Handler._updateLaserSpin
Handler.requiredParentFields = {
	"laserSpinBeamsModel",
}
Handler.requiresHandle = false

return Handler
