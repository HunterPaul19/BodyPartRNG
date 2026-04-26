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
local FADE_OUT_SECONDS = 0.35
local SOUND_DELAY_OFFSET_SECONDS = -0.5
local RAINBOW_TWEEN_SECONDS = 0.3
local RAINBOW_COLORS = {
	Color3.fromRGB(255, 64, 64),
	Color3.fromRGB(255, 225, 64),
	Color3.fromRGB(72, 255, 96),
	Color3.fromRGB(64, 235, 255),
	Color3.fromRGB(84, 112, 255),
	Color3.fromRGB(255, 84, 255),
}

local Handler = {}

local function setVfxDescendantsEnabled(root: Instance?, enabled: boolean)
	if root == nil then
		return
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") or descendant:IsA("Trail") then
			descendant.Enabled = enabled
		end
	end
end

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

local function collectBeamParts(model: Model?): { BasePart }
	local beamParts = {}
	if model == nil then
		return beamParts
	end

	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") and child.Name == "Beam" then
			table.insert(beamParts, child)
		end
	end

	return beamParts
end

function Handler:_cancelLaserSpinRainbowTweens(record: ActiveRecord)
	local rainbowTweens = record.laserSpinRainbowTweens
	if typeof(rainbowTweens) == "table" then
		for _, tween in ipairs(rainbowTweens) do
			tween:Cancel()
		end
	end

	local rainbowConnections = record.laserSpinRainbowConnections
	if typeof(rainbowConnections) == "table" then
		for _, connection in ipairs(rainbowConnections) do
			if connection.Connected then
				connection:Disconnect()
			end
		end
	end

	record.laserSpinRainbowTweens = nil
	record.laserSpinRainbowConnections = nil
end

function Handler:_destroyLaserSpin(record: ActiveRecord)
	self:_cancelLaserSpinRainbowTweens(record)

	local beamsModel = record.laserSpinBeamsModel
	if beamsModel ~= nil then
		setVfxDescendantsEnabled(beamsModel, false)
	end

	local castFolder = record.castFolder
	if castFolder ~= nil then
		self:destroyVfxAfter(castFolder, 0)
	elseif beamsModel ~= nil then
		self:destroyVfxAfter(beamsModel, 0)
	end

	record.laserSpinBeamsModel = nil
	record.laserSpinMotion = nil
	record.laserSpinStopping = nil
	record.castFolder = nil
	self.controller._recordsByCastId[record.castId] = nil
end

function Handler:_beginLaserSpinFade(record: ActiveRecord)
	if record.laserSpinStopping then
		return
	end
	record.laserSpinStopping = true

	local beamsModel = record.laserSpinBeamsModel
	if beamsModel == nil or beamsModel.Parent == nil then
		self:_destroyLaserSpin(record)
		return
	end

	self:_cancelLaserSpinRainbowTweens(record)
	setVfxDescendantsEnabled(beamsModel, false)

	for _, beamPart in ipairs(collectBeamParts(beamsModel)) do
		local tween = self.TweenService:Create(
			beamPart,
			TweenInfo.new(FADE_OUT_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Transparency = 1 }
		)
		tween:Play()
	end

	task.delay(FADE_OUT_SECONDS, function()
		self:_destroyLaserSpin(record)
	end)
end

function Handler:_startLaserSpinRainbowTweens(record: ActiveRecord, beamsModel: Model)
	local rainbowTweens = {}
	local rainbowConnections = {}
	record.laserSpinRainbowTweens = rainbowTweens
	record.laserSpinRainbowConnections = rainbowConnections

	for index, beamPart in ipairs(collectBeamParts(beamsModel)) do
		if index % 2 ~= 1 then
			continue
		end

		local colorIndex = ((index - 1) % #RAINBOW_COLORS) + 1
		local function playNextTween()
			if record.laserSpinStopping or beamPart.Parent == nil then
				return
			end

			colorIndex = (colorIndex % #RAINBOW_COLORS) + 1
			local tween = self.TweenService:Create(
				beamPart,
				TweenInfo.new(RAINBOW_TWEEN_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ Color = RAINBOW_COLORS[colorIndex] }
			)
			table.insert(rainbowTweens, tween)

			local connection
			connection = tween.Completed:Connect(function()
				if connection and connection.Connected then
					connection:Disconnect()
				end
				playNextTween()
			end)
			table.insert(rainbowConnections, connection)
			tween:Play()
		end

		beamPart.Color = RAINBOW_COLORS[colorIndex]
		playNextTween()
	end
end

function Handler:_playLaserSpinSounds(
	soundsSource: Instance,
	anchorPart: BasePart,
	emitterParent: Instance?,
	visualScale: number
)
	self:playSoundsAtPosition(soundsSource, anchorPart.CFrame, visualScale, {
		parent = emitterParent,
		includeDelay = true,
		delayOffsetSeconds = SOUND_DELAY_OFFSET_SECONDS,
		useConfiguredStartPosition = false,
		useConfiguredEndPosition = false,
	})
end

function Handler:_updateLaserSpin(record: ActiveRecord, nowServerTime: number)
	local motion = record.laserSpinMotion
	local beamsModel = record.laserSpinBeamsModel
	if record.laserSpinStopping then
		return
	end
	if motion == nil or beamsModel == nil or beamsModel.Parent == nil then
		return
	end

	local elapsed = math.max(0, nowServerTime - motion.startedAtServerTime)
	if elapsed >= motion.duration then
		self:_beginLaserSpinFade(record)
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
		self:warnWithPrefix("Laser Spin Beams VFX model is missing from ReplicatedStorage.GameAssets.Effects.Bosses.")
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
		self:_playLaserSpinSounds(soundsSource, primaryPart, castFolder, visualScale)
	end
	self:_startLaserSpinRainbowTweens(record, beamsModel)
	self:_updateLaserSpin(record, self.Workspace:GetServerTimeNow())
end

function Handler:_stopLaserSpin(record: ActiveRecord, _event: PresentationEvent)
	self:_beginLaserSpinFade(record)
end

Handler.moduleIds = {
	CAT_MECH_ELITE_LASER_SPIN_MODULE_ID,
}
Handler.start = Handler._startLaserSpin
Handler.update = Handler._updateLaserSpin
Handler.actions = {
	stop = Handler._stopLaserSpin,
}
Handler.requiredParentFields = {
	"laserSpinBeamsModel",
}
Handler.requiresHandle = false

return Handler
