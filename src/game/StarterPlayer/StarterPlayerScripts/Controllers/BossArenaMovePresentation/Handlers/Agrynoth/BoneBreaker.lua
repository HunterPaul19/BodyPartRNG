type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		AGRYNOTH_BONE_BREAKER_MODULE_ID = "Moves.Agrynoth.BoneBreaker",
	},
	Vfx = {
		AGRYNOTH_BONE_BREAKER_EXPLOSION_NAME_PREFIX = "Explosion",
		AGRYNOTH_BONE_BREAKER_LEFT_HAND_VFX_NAME = "LeftHand",
		AGRYNOTH_BONE_BREAKER_ROOT_PART_VFX_NAME = "RootPart",
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
local AGRYNOTH_BONE_BREAKER_ROOT_PART_VFX_NAME = Constants.Vfx.AGRYNOTH_BONE_BREAKER_ROOT_PART_VFX_NAME
local AGRYNOTH_BONE_BREAKER_SOUNDS_FOLDER_NAME = Constants.Vfx.AGRYNOTH_BONE_BREAKER_SOUNDS_FOLDER_NAME
local AGRYNOTH_BONE_BREAKER_VFX_NAME = Constants.Vfx.AGRYNOTH_BONE_BREAKER_VFX_NAME
local AGRYNOTH_VFX_FOLDER_NAME = Constants.Vfx.AGRYNOTH_VFX_FOLDER_NAME

local Handler = {}

local function resolveEventElapsedSeconds(self, event: PresentationEvent): number
	local serverTime = tonumber(event.serverTime)
	if serverTime == nil then
		return 0
	end

	return math.max(0, self.Workspace:GetServerTimeNow() - serverTime)
end

local function resolveScaledAuthoredCFrame(bossRootPart: BasePart, rootPartSource: Model, effectSource: Model, scaleMultiplier: number): CFrame
	local relativeCFrame = rootPartSource:GetPivot():ToObjectSpace(effectSource:GetPivot())
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = relativeCFrame:GetComponents()
	local scaledRelativeCFrame = CFrame.new(
		x * scaleMultiplier,
		y * scaleMultiplier,
		z * scaleMultiplier,
		r00,
		r01,
		r02,
		r10,
		r11,
		r12,
		r20,
		r21,
		r22
	)

	return bossRootPart.CFrame * scaledRelativeCFrame
end

local function withYPosition(cframe: CFrame, yPosition: number): CFrame
	local x, _, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cframe:GetComponents()
	return CFrame.new(x, yPosition, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
end

local function buildGroundRaycastParams(workspaceService: Workspace, ignoreInstances: { Instance }): RaycastParams
	local include = {}

	local activeBossArena = workspaceService:FindFirstChild("ActiveBossArena")
	if activeBossArena then
		table.insert(include, activeBossArena)
	end

	local map = workspaceService:FindFirstChild("Map")
	if map then
		table.insert(include, map)
	end

	local world = workspaceService:FindFirstChild("World")
	local worldMap = world and world:FindFirstChild("Map")
	if worldMap then
		for _, child in ipairs(worldMap:GetChildren()) do
			table.insert(include, child)
		end
	end

	if workspaceService.Terrain then
		table.insert(include, workspaceService.Terrain)
	end

	local params = RaycastParams.new()
	params.IgnoreWater = false
	if #include > 0 then
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = include
	else
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = ignoreInstances
	end

	return params
end

local function resolveFloorY(self, authoredCFrame: CFrame, payload): number
	if typeof(payload) == "table" and typeof(payload.floorCFrame) == "CFrame" then
		return payload.floorCFrame.Position.Y
	end

	local rayOrigin = authoredCFrame.Position + Vector3.new(0, 10, 0)
	local rayDirection = Vector3.new(0, -270, 0)
	local result = self.Workspace:Raycast(rayOrigin, rayDirection, buildGroundRaycastParams(self.Workspace, {}))
	if result then
		return result.Position.Y
	end

	return authoredCFrame.Position.Y
end

local function snapModelBottomToFloor(effectModel: Model, floorY: number)
	local boundingCFrame, boundingSize = effectModel:GetBoundingBox()
	local bottomY = boundingCFrame.Position.Y - (boundingSize.Y * 0.5)
	effectModel:PivotTo(effectModel:GetPivot() + Vector3.new(0, floorY - bottomY, 0))
end

local function collectSounds(root: Instance): { Sound }
	local sounds = {}
	if root:IsA("Sound") then
		table.insert(sounds, root)
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Sound") then
			table.insert(sounds, descendant)
		end
	end
	return sounds
end

local function getSoundDelay(sound: Sound): number
	return math.max(0, tonumber(sound:GetAttribute("Delay")) or tonumber(sound:GetAttribute("Start")) or 0)
end

function Handler:_playAuthoredSoundCueClones(sourceRoot: Instance, parent: Instance, scaleMultiplier: number, elapsedSeconds: number)
	for _, sourceSound in ipairs(collectSounds(sourceRoot)) do
		local soundClone = sourceSound:Clone()
		soundClone.Parent = parent

		local delaySeconds = math.max(0, getSoundDelay(sourceSound) - elapsedSeconds)
		task.delay(delaySeconds, function()
			if soundClone.Parent == nil then
				return
			end

			self:playSoundFromConfiguredPosition(soundClone, scaleMultiplier)
			local cleanupDelay = math.max(1, tonumber(soundClone.TimeLength) or 0) + 1
			self:destroyAfter(soundClone, cleanupDelay)
		end)
	end
end

function Handler:_playAuthoredSoundCuesInPlace(sourceRoot: Instance, scaleMultiplier: number, elapsedSeconds: number)
	for _, sourceSound in ipairs(collectSounds(sourceRoot)) do
		local delaySeconds = math.max(0, getSoundDelay(sourceSound) - elapsedSeconds)
		task.delay(delaySeconds, function()
			if sourceSound.Parent == nil then
				return
			end

			self:playSoundFromConfiguredPosition(sourceSound, scaleMultiplier)
		end)
	end
end

function Handler:_emitAuthoredExplosion(record: ActiveRecord, event: PresentationEvent, hitIndex: number)
	if record.stopRequested == true then
		return
	end

	local bossModel = event.bossModel or record.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local bossRootPart = self:resolveBossRootPart(bossModel)
	if bossRootPart == nil then
		self:warnWithPrefix("Agrynoth Bone Breaker presentation could not resolve the live boss RootPart.")
		self:_cleanupRecord(record)
		return
	end

	local rootPartSource = self:resolveBossVfxModel(
		AGRYNOTH_VFX_FOLDER_NAME,
		AGRYNOTH_BONE_BREAKER_VFX_NAME,
		AGRYNOTH_BONE_BREAKER_ROOT_PART_VFX_NAME
	)
	if rootPartSource == nil then
		self:warnWithPrefix("Agrynoth Bone Breaker RootPart reference VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		return
	end

	local explosionName = string.format("%s%d", AGRYNOTH_BONE_BREAKER_EXPLOSION_NAME_PREFIX, hitIndex)
	local explosionSource = self:resolveBossVfxModel(AGRYNOTH_VFX_FOLDER_NAME, AGRYNOTH_BONE_BREAKER_VFX_NAME, explosionName)
	if explosionSource == nil then
		self:warnWithPrefix(string.format(
			"Agrynoth Bone Breaker %s VFX model is missing from ReplicatedStorage.GameAssets.VFX.",
			explosionName
		))
		return
	end

	local payload = event.payload
	local scaleMultiplier = math.max(0.1, tonumber(payload and payload.scaleMultiplier) or 1)
	local authoredCFrame = resolveScaledAuthoredCFrame(bossRootPart, rootPartSource, explosionSource, scaleMultiplier)
	local floorY = resolveFloorY(self, authoredCFrame, payload)
	local explosionModel = explosionSource:Clone()
	explosionModel:ScaleTo(AGRYNOTH_BONE_BREAKER_EXPLOSION_SCALE)
	self:prepareMovingEffectModel(explosionModel)
	explosionModel:PivotTo(withYPosition(authoredCFrame, floorY))
	snapModelBottomToFloor(explosionModel, floorY)
	explosionModel.Parent = self:_ensureVisualFolder()

	self:emitEffectInstance(explosionModel, AGRYNOTH_BONE_BREAKER_EXPLOSION_LIFETIME_SECONDS)
	self:destroyVfxAfter(explosionModel, AGRYNOTH_BONE_BREAKER_EXPLOSION_LIFETIME_SECONDS)
	self:_shakeImpact()
end

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
	leftHandModel:ScaleTo(scaleMultiplier)
	self:prepareAttachedEffectModel(leftHandModel)
	leftHandModel.Parent = castFolder
	record.leftHandModel = leftHandModel

	if not self:attachEffectModel(leftHandModel, bossLeftHand) then
		self:warnWithPrefix("Agrynoth Bone Breaker LeftHand VFX model is missing a BasePart for welding.")
		self:_cleanupRecord(record)
		return
	end

	self:_playAuthoredSoundCuesInPlace(leftHandModel, scaleMultiplier, resolveEventElapsedSeconds(self, event))
	self:emitEffectInstance(leftHandModel)
end

function Handler:_slamStartAgrynothBoneBreaker(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" then
		payload = {}
	end

	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	local elapsedSeconds = resolveEventElapsedSeconds(self, event)
	local castFolder = self:_ensureCastFolder(record)

	local effectFolder = self:resolveBossVfxFolder(AGRYNOTH_VFX_FOLDER_NAME, AGRYNOTH_BONE_BREAKER_VFX_NAME)
	local soundsFolder = effectFolder and effectFolder:FindFirstChild(AGRYNOTH_BONE_BREAKER_SOUNDS_FOLDER_NAME)
	if soundsFolder then
		self:_playAuthoredSoundCueClones(soundsFolder, castFolder, scaleMultiplier, elapsedSeconds)
	end
end

function Handler:_impactAgrynothBoneBreaker(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" then
		return
	end

	local hitIndex = math.clamp(math.floor(tonumber(payload.hitIndex) or 1), 1, 3)
	self:_emitAuthoredExplosion(record, event, hitIndex)
end

function Handler:_stopAgrynothBoneBreaker(record: ActiveRecord)
	record.stopRequested = true
	self:_cleanupRecord(record)
end

Handler.moduleIds = {
	AGRYNOTH_BONE_BREAKER_MODULE_ID,
}
Handler.start = Handler._startAgrynothBoneBreaker
Handler.actions = {
	impact = Handler._impactAgrynothBoneBreaker,
	slamStart = Handler._slamStartAgrynothBoneBreaker,
	stop = Handler._stopAgrynothBoneBreaker,
}
Handler.requiresHandle = false

return Handler
