type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		MASSIVE_GEEZER_EAT_CHICKEN_MODULE_ID = "Moves.MassiveGeezer.EatChicken",
	},
	Vfx = {
		MASSIVE_GEEZER_EAT_CHICKEN_LEG_VFX_NAME = "ChickenLeg",
		MASSIVE_GEEZER_EAT_CHICKEN_SOUNDS_NAME = "Sounds",
		MASSIVE_GEEZER_EAT_CHICKEN_VFX_NAME = "EatChicken",
		MASSIVE_GEEZER_VFX_FOLDER_NAME = "MassiveGeezer",
	},
	Timing = {
		MASSIVE_GEEZER_EAT_CHICKEN_FLIGHT_FORWARD_YAW_DEGREES = -90,
		MASSIVE_GEEZER_EAT_CHICKEN_HOLD_PITCH_DEGREES = -20,
		MASSIVE_GEEZER_EAT_CHICKEN_HOLD_ROLL_DEGREES = 90,
		MASSIVE_GEEZER_EAT_CHICKEN_PRIMARY_SPIN_MAX_DEGREES_PER_SECOND = 1080,
		MASSIVE_GEEZER_EAT_CHICKEN_PRIMARY_SPIN_MIN_DEGREES_PER_SECOND = 540,
		MASSIVE_GEEZER_EAT_CHICKEN_RELEASE_BLEND_ALPHA = 0.2,
		MASSIVE_GEEZER_EAT_CHICKEN_SECONDARY_SPIN_MAX_DEGREES_PER_SECOND = 220,
		MASSIVE_GEEZER_EAT_CHICKEN_SECONDARY_SPIN_MIN_DEGREES_PER_SECOND = 60,
		MASSIVE_GEEZER_EAT_CHICKEN_SOUND_CLEANUP_SECONDS = 8,
		MASSIVE_GEEZER_EAT_CHICKEN_VISUAL_SCALE_FACTOR = 0.5,
		MASSIVE_GEEZER_EAT_CHICKEN_YAW_STEP_DEGREES = 15,
	},
}

local MASSIVE_GEEZER_EAT_CHICKEN_FLIGHT_FORWARD_YAW_DEGREES =
	Constants.Timing.MASSIVE_GEEZER_EAT_CHICKEN_FLIGHT_FORWARD_YAW_DEGREES
local MASSIVE_GEEZER_EAT_CHICKEN_HOLD_PITCH_DEGREES =
	Constants.Timing.MASSIVE_GEEZER_EAT_CHICKEN_HOLD_PITCH_DEGREES
local MASSIVE_GEEZER_EAT_CHICKEN_HOLD_ROLL_DEGREES =
	Constants.Timing.MASSIVE_GEEZER_EAT_CHICKEN_HOLD_ROLL_DEGREES
local MASSIVE_GEEZER_EAT_CHICKEN_LEG_VFX_NAME = Constants.Vfx.MASSIVE_GEEZER_EAT_CHICKEN_LEG_VFX_NAME
local MASSIVE_GEEZER_EAT_CHICKEN_MODULE_ID = Constants.ModuleIds.MASSIVE_GEEZER_EAT_CHICKEN_MODULE_ID
local MASSIVE_GEEZER_EAT_CHICKEN_PRIMARY_SPIN_MAX_DEGREES_PER_SECOND =
	Constants.Timing.MASSIVE_GEEZER_EAT_CHICKEN_PRIMARY_SPIN_MAX_DEGREES_PER_SECOND
local MASSIVE_GEEZER_EAT_CHICKEN_PRIMARY_SPIN_MIN_DEGREES_PER_SECOND =
	Constants.Timing.MASSIVE_GEEZER_EAT_CHICKEN_PRIMARY_SPIN_MIN_DEGREES_PER_SECOND
local MASSIVE_GEEZER_EAT_CHICKEN_RELEASE_BLEND_ALPHA =
	Constants.Timing.MASSIVE_GEEZER_EAT_CHICKEN_RELEASE_BLEND_ALPHA
local MASSIVE_GEEZER_EAT_CHICKEN_SECONDARY_SPIN_MAX_DEGREES_PER_SECOND =
	Constants.Timing.MASSIVE_GEEZER_EAT_CHICKEN_SECONDARY_SPIN_MAX_DEGREES_PER_SECOND
local MASSIVE_GEEZER_EAT_CHICKEN_SECONDARY_SPIN_MIN_DEGREES_PER_SECOND =
	Constants.Timing.MASSIVE_GEEZER_EAT_CHICKEN_SECONDARY_SPIN_MIN_DEGREES_PER_SECOND
local MASSIVE_GEEZER_EAT_CHICKEN_SOUND_CLEANUP_SECONDS = Constants.Timing.MASSIVE_GEEZER_EAT_CHICKEN_SOUND_CLEANUP_SECONDS
local MASSIVE_GEEZER_EAT_CHICKEN_VISUAL_SCALE_FACTOR =
	Constants.Timing.MASSIVE_GEEZER_EAT_CHICKEN_VISUAL_SCALE_FACTOR
local MASSIVE_GEEZER_EAT_CHICKEN_SOUNDS_NAME = Constants.Vfx.MASSIVE_GEEZER_EAT_CHICKEN_SOUNDS_NAME
local MASSIVE_GEEZER_EAT_CHICKEN_VFX_NAME = Constants.Vfx.MASSIVE_GEEZER_EAT_CHICKEN_VFX_NAME
local MASSIVE_GEEZER_EAT_CHICKEN_YAW_STEP_DEGREES = Constants.Timing.MASSIVE_GEEZER_EAT_CHICKEN_YAW_STEP_DEGREES
local MASSIVE_GEEZER_VFX_FOLDER_NAME = Constants.Vfx.MASSIVE_GEEZER_VFX_FOLDER_NAME

local Handler = {}

local FLIGHT_ROTATION_OFFSET =
	CFrame.Angles(0, math.rad(MASSIVE_GEEZER_EAT_CHICKEN_FLIGHT_FORWARD_YAW_DEGREES), 0)
local HOLD_ROTATION_OFFSET = FLIGHT_ROTATION_OFFSET
	* CFrame.Angles(
		math.rad(MASSIVE_GEEZER_EAT_CHICKEN_HOLD_PITCH_DEGREES),
		0,
		math.rad(MASSIVE_GEEZER_EAT_CHICKEN_HOLD_ROLL_DEGREES)
	)

local function resolveRotationOnly(cframe: CFrame): CFrame
	return cframe - cframe.Position
end

local function resolveHeldChickenCFrame(handPart: BasePart, yawOffset: number): CFrame
	return handPart.CFrame * CFrame.Angles(0, yawOffset, 0) * HOLD_ROTATION_OFFSET
end

local function resolveThrownChickenCFrame(self, startPosition: Vector3, endPosition: Vector3, alpha: number): CFrame
	return self:resolveProjectileCFrame(startPosition, endPosition, alpha) * FLIGHT_ROTATION_OFFSET
end

local function resolveLaunchChickenCFrame(
	self,
	boneModel: Model?,
	startPosition: Vector3,
	endPosition: Vector3
): CFrame
	if boneModel and boneModel.Parent ~= nil then
		return CFrame.new(startPosition) * resolveRotationOnly(boneModel:GetPivot())
	end

	return resolveThrownChickenCFrame(self, startPosition, endPosition, 0)
end

local function resolveChickenVisualScale(scaleMultiplier: number): number
	return math.max(0.1, scaleMultiplier * MASSIVE_GEEZER_EAT_CHICKEN_VISUAL_SCALE_FACTOR)
end

local function quantizeSeedComponent(value: number): number
	return math.floor((value * 100) + if value >= 0 then 0.5 else -0.5)
end

local function mixSeed(seed: number, value: number): number
	return (seed * 1103515245 + value + 12345) % 2147483647
end

local function buildProjectileSpinSeed(index: number, startPosition: Vector3, endPosition: Vector3): number
	local seed = mixSeed(17, index)
	seed = mixSeed(seed, quantizeSeedComponent(startPosition.X))
	seed = mixSeed(seed, quantizeSeedComponent(startPosition.Y))
	seed = mixSeed(seed, quantizeSeedComponent(startPosition.Z))
	seed = mixSeed(seed, quantizeSeedComponent(endPosition.X))
	seed = mixSeed(seed, quantizeSeedComponent(endPosition.Y))
	seed = mixSeed(seed, quantizeSeedComponent(endPosition.Z))
	return math.max(1, seed)
end

local function resolveSignedSpinRadiansPerSecond(randomGenerator: Random, minDegreesPerSecond: number, maxDegreesPerSecond: number): number
	local speedDegreesPerSecond = randomGenerator:NextNumber(minDegreesPerSecond, maxDegreesPerSecond)
	local directionSign = if randomGenerator:NextInteger(0, 1) == 0 then -1 else 1
	return math.rad(speedDegreesPerSecond * directionSign)
end

local function resolveProjectileSpinMotion(index: number, startPosition: Vector3, endPosition: Vector3): { [string]: number }
	local randomGenerator = Random.new(buildProjectileSpinSeed(index, startPosition, endPosition))
	return {
		primarySpinRadiansPerSecond = resolveSignedSpinRadiansPerSecond(
			randomGenerator,
			MASSIVE_GEEZER_EAT_CHICKEN_PRIMARY_SPIN_MIN_DEGREES_PER_SECOND,
			MASSIVE_GEEZER_EAT_CHICKEN_PRIMARY_SPIN_MAX_DEGREES_PER_SECOND
		),
		secondarySpinRadiansPerSecond = resolveSignedSpinRadiansPerSecond(
			randomGenerator,
			MASSIVE_GEEZER_EAT_CHICKEN_SECONDARY_SPIN_MIN_DEGREES_PER_SECOND,
			MASSIVE_GEEZER_EAT_CHICKEN_SECONDARY_SPIN_MAX_DEGREES_PER_SECOND
		),
		primaryPhaseRadians = math.rad(randomGenerator:NextNumber(0, 360)),
		secondaryPhaseRadians = math.rad(randomGenerator:NextNumber(0, 360)),
	}
end

local function resolveProjectileSpinCFrame(motion: { [string]: any }, elapsedFlightSeconds: number, spinBlendAlpha: number): CFrame
	local spinWeight = math.clamp(spinBlendAlpha, 0, 1)
	local primarySpinAngle = (
		(tonumber(motion.primarySpinRadiansPerSecond) or 0) * math.max(0, elapsedFlightSeconds)
		+ (tonumber(motion.primaryPhaseRadians) or 0)
	) * spinWeight
	local secondarySpinAngle = (
		(tonumber(motion.secondarySpinRadiansPerSecond) or 0) * math.max(0, elapsedFlightSeconds)
		+ (tonumber(motion.secondaryPhaseRadians) or 0)
	) * spinWeight
	return CFrame.Angles(primarySpinAngle, 0, 0) * CFrame.Angles(0, 0, secondarySpinAngle)
end

function Handler:_startEatChicken(record: ActiveRecord, event: PresentationEvent)
	local soundsSource = self:resolveBossVfxInstance(
		MASSIVE_GEEZER_VFX_FOLDER_NAME,
		MASSIVE_GEEZER_EAT_CHICKEN_VFX_NAME,
		MASSIVE_GEEZER_EAT_CHICKEN_SOUNDS_NAME
	)
	if soundsSource == nil then
		return
	end

	local payload = event.payload
	local scaleMultiplier = math.max(0.1, tonumber(payload and payload.scaleMultiplier) or 1)
	local sounds = soundsSource:Clone()
	sounds.Parent = self:_ensureCastFolder(record)
	self:playTimedSounds(sounds, scaleMultiplier)
	self:destroySoundAfter(sounds, MASSIVE_GEEZER_EAT_CHICKEN_SOUND_CLEANUP_SECONDS)
end

function Handler:_updateEatChickenBones(record: ActiveRecord, nowServerTime: number)
	local boneModels = record.eatChickenBoneModels
	local boneMotions = record.eatChickenBoneMotions
	if boneModels == nil or boneMotions == nil then
		return
	end

	for index, boneModel in pairs(boneModels) do
		local motion = boneMotions[index]
		if boneModel.Parent == nil then
			boneModels[index] = nil
			boneMotions[index] = nil
			continue
		end
		if motion == nil then
			continue
		end

		local alpha = math.clamp(
			(nowServerTime - motion.startedAtServerTime) / math.max(0.001, motion.travelDuration),
			0,
			1
		)
		local elapsedFlightSeconds = math.max(0, nowServerTime - motion.startedAtServerTime)
		local thrownCFrame = resolveThrownChickenCFrame(self, motion.startPosition, motion.endPosition, alpha)
		local launchCFrame = motion.launchCFrame
		if typeof(launchCFrame) == "CFrame" then
			local blendAlpha = math.clamp(alpha / MASSIVE_GEEZER_EAT_CHICKEN_RELEASE_BLEND_ALPHA, 0, 1)
			boneModel:PivotTo(
				launchCFrame:Lerp(thrownCFrame, blendAlpha)
					* resolveProjectileSpinCFrame(motion, elapsedFlightSeconds, blendAlpha)
			)
		else
			boneModel:PivotTo(thrownCFrame * resolveProjectileSpinCFrame(motion, elapsedFlightSeconds, 1))
		end

		if alpha >= 1 then
			boneModel:Destroy()
			boneModels[index] = nil
			boneMotions[index] = nil
		end
	end
end

function Handler:_spawnEatChickenLegs(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local leftHand = self:resolveBossLeftHandPart(bossModel)
	local rightHand = self:resolveBossRightHandPart(bossModel)
	if leftHand == nil or rightHand == nil then
		self:warnWithPrefix("Eat Chicken presentation could not resolve the live boss LeftHand/RightHand.")
		self:_cleanupRecord(record)
		return
	end

	local chickenSource = self:resolveBossVfxModel(
		MASSIVE_GEEZER_VFX_FOLDER_NAME,
		MASSIVE_GEEZER_EAT_CHICKEN_VFX_NAME,
		MASSIVE_GEEZER_EAT_CHICKEN_LEG_VFX_NAME
	)
	if chickenSource == nil then
		self:warnWithPrefix("Eat Chicken ChickenLeg VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local payload = event.payload
	local countPerHand = math.max(1, math.floor(tonumber(payload and payload.countPerHand) or 8))
	local scaleMultiplier = math.max(0.1, tonumber(payload and payload.scaleMultiplier) or 1)
	local chickenVisualScale = resolveChickenVisualScale(scaleMultiplier)
	local castFolder = self:_ensureCastFolder(record)
	record.eatChickenBoneModels = record.eatChickenBoneModels or {}

	local function attachClone(handPart: BasePart, index: number, globalIndex: number)
		local chickenClone = chickenSource:Clone()
		chickenClone:ScaleTo(chickenVisualScale)
		self:prepareAttachedEffectModel(chickenClone)
		self:scaleAttachedSounds(chickenClone, chickenVisualScale)

		local primaryPart = self:resolveEffectModelPrimaryPart(chickenClone)
		if primaryPart == nil then
			chickenClone:Destroy()
			self:warnWithPrefix("Eat Chicken ChickenLeg VFX model is missing a BasePart.")
			return
		end

		local yawOffset = math.rad((index - ((countPerHand + 1) / 2)) * MASSIVE_GEEZER_EAT_CHICKEN_YAW_STEP_DEGREES)
		chickenClone:PivotTo(resolveHeldChickenCFrame(handPart, yawOffset))
		chickenClone.Parent = castFolder
		self:createWeld(primaryPart, handPart)
		self:playAllSounds(chickenClone, chickenVisualScale)
		record.eatChickenBoneModels[globalIndex] = chickenClone
	end

	for index = 1, countPerHand do
		attachClone(leftHand, index, index)
	end
	for index = 1, countPerHand do
		attachClone(rightHand, index, countPerHand + index)
	end
end

function Handler:_ateEatChicken(record: ActiveRecord)
	local boneModels = record.eatChickenBoneModels
	if boneModels == nil then
		return
	end

	for _, boneModel in pairs(boneModels) do
		if boneModel.Parent ~= nil then
			self:destroyEatChickenMeat(boneModel)
		end
	end
end

function Handler:_throwEatChickenBones(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.projectiles) ~= "table" then
		return
	end

	local chickenSource = self:resolveBossVfxModel(
		MASSIVE_GEEZER_VFX_FOLDER_NAME,
		MASSIVE_GEEZER_EAT_CHICKEN_VFX_NAME,
		MASSIVE_GEEZER_EAT_CHICKEN_LEG_VFX_NAME
	)
	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	local chickenVisualScale = resolveChickenVisualScale(scaleMultiplier)
	local castFolder = self:_ensureCastFolder(record)
	record.eatChickenBoneModels = record.eatChickenBoneModels or {}
	record.eatChickenBoneMotions = record.eatChickenBoneMotions or {}

	for _, projectilePlan in ipairs(payload.projectiles) do
		local index = math.floor(tonumber(projectilePlan.index) or 0)
		local startPosition = projectilePlan.startPosition
		local endPosition = projectilePlan.endPosition
		local travelDuration = tonumber(projectilePlan.travelDuration)
		if index <= 0 or typeof(startPosition) ~= "Vector3" or typeof(endPosition) ~= "Vector3" or travelDuration == nil then
			continue
		end

		local boneModel = record.eatChickenBoneModels[index]
		if boneModel == nil and chickenSource ~= nil then
			boneModel = chickenSource:Clone()
			boneModel:ScaleTo(chickenVisualScale)
			self:destroyEatChickenMeat(boneModel)
			record.eatChickenBoneModels[index] = boneModel
		end
		if boneModel == nil then
			continue
		end

		self:destroyEatChickenMeat(boneModel)
		self:destroyWeldConstraints(boneModel)
		self:prepareMovingEffectModel(boneModel)
		self:scaleAttachedSounds(boneModel, chickenVisualScale)
		if self:resolveEffectModelPrimaryPart(boneModel) == nil then
			boneModel:Destroy()
			record.eatChickenBoneModels[index] = nil
			self:warnWithPrefix("Eat Chicken ChickenLeg VFX model is missing a BasePart for projectile motion.")
			continue
		end

		local launchCFrame = resolveLaunchChickenCFrame(self, boneModel, startPosition, endPosition)
		local spinMotion = resolveProjectileSpinMotion(index, startPosition, endPosition)
		boneModel.Parent = castFolder
		boneModel:PivotTo(launchCFrame)
		record.eatChickenBoneMotions[index] = {
			startPosition = startPosition,
			endPosition = endPosition,
			launchCFrame = launchCFrame,
			primaryPhaseRadians = spinMotion.primaryPhaseRadians,
			primarySpinRadiansPerSecond = spinMotion.primarySpinRadiansPerSecond,
			secondaryPhaseRadians = spinMotion.secondaryPhaseRadians,
			secondarySpinRadiansPerSecond = spinMotion.secondarySpinRadiansPerSecond,
			travelDuration = math.max(0.001, travelDuration),
			startedAtServerTime = if typeof(event.serverTime) == "number" then event.serverTime else self.Workspace:GetServerTimeNow(),
		}
	end
end

Handler.moduleIds = {
	MASSIVE_GEEZER_EAT_CHICKEN_MODULE_ID,
}
Handler.start = Handler._startEatChicken
Handler.update = Handler._updateEatChickenBones
Handler.actions = {
	spawnChicken = Handler._spawnEatChickenLegs,
	ateChicken = Handler._ateEatChicken,
	throwBones = Handler._throwEatChickenBones,
}
Handler.requiresHandle = false

return Handler
