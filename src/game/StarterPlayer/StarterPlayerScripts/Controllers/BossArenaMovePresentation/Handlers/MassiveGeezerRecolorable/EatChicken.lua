type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		MASSIVE_GEEZER_EAT_CHICKEN_MODULE_ID = "Moves.MassiveGeezerRecolorable.EatChicken",
	},
	Vfx = {
		MASSIVE_GEEZER_EAT_CHICKEN_LEG_VFX_NAME = "ChickenLeg",
		MASSIVE_GEEZER_EAT_CHICKEN_SOUNDS_NAME = "Sounds",
		MASSIVE_GEEZER_EAT_CHICKEN_VFX_NAME = "EatChicken",
		MASSIVE_GEEZER_VFX_FOLDER_NAME = "MassiveGeezer",
	},
	Timing = {
		MASSIVE_GEEZER_EAT_CHICKEN_SOUND_CLEANUP_SECONDS = 8,
		MASSIVE_GEEZER_EAT_CHICKEN_YAW_STEP_DEGREES = 15,
	},
}

local MASSIVE_GEEZER_EAT_CHICKEN_LEG_VFX_NAME = Constants.Vfx.MASSIVE_GEEZER_EAT_CHICKEN_LEG_VFX_NAME
local MASSIVE_GEEZER_EAT_CHICKEN_MODULE_ID = Constants.ModuleIds.MASSIVE_GEEZER_EAT_CHICKEN_MODULE_ID
local MASSIVE_GEEZER_EAT_CHICKEN_SOUND_CLEANUP_SECONDS = Constants.Timing.MASSIVE_GEEZER_EAT_CHICKEN_SOUND_CLEANUP_SECONDS
local MASSIVE_GEEZER_EAT_CHICKEN_SOUNDS_NAME = Constants.Vfx.MASSIVE_GEEZER_EAT_CHICKEN_SOUNDS_NAME
local MASSIVE_GEEZER_EAT_CHICKEN_VFX_NAME = Constants.Vfx.MASSIVE_GEEZER_EAT_CHICKEN_VFX_NAME
local MASSIVE_GEEZER_EAT_CHICKEN_YAW_STEP_DEGREES = Constants.Timing.MASSIVE_GEEZER_EAT_CHICKEN_YAW_STEP_DEGREES
local MASSIVE_GEEZER_VFX_FOLDER_NAME = Constants.Vfx.MASSIVE_GEEZER_VFX_FOLDER_NAME

local Handler = {}

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
		boneModel:PivotTo(self:resolveProjectileCFrame(motion.startPosition, motion.endPosition, alpha))

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
	local castFolder = self:_ensureCastFolder(record)
	record.eatChickenBoneModels = record.eatChickenBoneModels or {}

	local function attachClone(handPart: BasePart, index: number, globalIndex: number)
		local chickenClone = chickenSource:Clone()
		chickenClone:ScaleTo(scaleMultiplier)
		self:prepareAttachedEffectModel(chickenClone)
		self:scaleAttachedSounds(chickenClone, scaleMultiplier)

		local primaryPart = self:resolveEffectModelPrimaryPart(chickenClone)
		if primaryPart == nil then
			chickenClone:Destroy()
			self:warnWithPrefix("Eat Chicken ChickenLeg VFX model is missing a BasePart.")
			return
		end

		local yawOffset = math.rad((index - ((countPerHand + 1) / 2)) * MASSIVE_GEEZER_EAT_CHICKEN_YAW_STEP_DEGREES)
		chickenClone:PivotTo(handPart.CFrame * CFrame.Angles(0, yawOffset, 0))
		chickenClone.Parent = castFolder
		self:createWeld(primaryPart, handPart)
		self:playAllSounds(chickenClone, scaleMultiplier)
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
			boneModel:ScaleTo(scaleMultiplier)
			self:destroyEatChickenMeat(boneModel)
			record.eatChickenBoneModels[index] = boneModel
		end
		if boneModel == nil then
			continue
		end

		self:destroyWeldConstraints(boneModel)
		self:prepareMovingEffectModel(boneModel)
		self:scaleAttachedSounds(boneModel, scaleMultiplier)
		if self:resolveEffectModelPrimaryPart(boneModel) == nil then
			boneModel:Destroy()
			record.eatChickenBoneModels[index] = nil
			self:warnWithPrefix("Eat Chicken ChickenLeg VFX model is missing a BasePart for projectile motion.")
			continue
		end

		boneModel.Parent = castFolder
		boneModel:PivotTo(self:resolveProjectileCFrame(startPosition, endPosition, 0))
		record.eatChickenBoneMotions[index] = {
			startPosition = startPosition,
			endPosition = endPosition,
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
