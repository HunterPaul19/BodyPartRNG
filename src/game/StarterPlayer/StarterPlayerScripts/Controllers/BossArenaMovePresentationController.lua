local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CameraShaker = require(ReplicatedStorage.Shared.Camera.CameraShaker)
local EmitModule = require(ReplicatedStorage.Shared.Effects.EmitModule)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local REMOTES_FOLDER_NAME = "Remotes"
local BOSS_ARENA_FOLDER_NAME = "BossArena"
local MOVE_PRESENTATION_REMOTE_NAME = "BossMovePresentation"
local ACTIVE_PROFILE_ID = "boss_arena"
local VISUAL_FOLDER_NAME = "BossMoveClientEffects"
local FLAME_SLASH_MODULE_ID = "Moves.FlameGuardGeneral.FlameSlash"
local PROMETHEUS_SLASH_MODULE_ID = "Moves.FlameGuardGeneral.PrometheusSlash"
local FIRE_BURST_MODULE_ID = "Moves.FlameGuardGeneral.FireBurst"
local FLAME_GUARD_GENERAL_VFX_FOLDER_NAME = "FlameGuardGeneral"
local FLAME_SLASH_VFX_NAME = "FlameSlash"
local PROMETHEUS_SLASH_VFX_NAME = "PrometheusSlash"
local FIRE_BURST_VFX_NAME = "FlameBurst"
local FIRE_BURST_RING_VFX_NAME = "MapRing"
local FIRE_BURST_RING_DIAMETER_PER_SIZE_STUD = 85
local FLAME_SLASH_SHAKE_MAGNITUDE = 1.15
local FLAME_SLASH_SHAKE_ROUGHNESS = 11
local FLAME_SLASH_SHAKE_FADE_IN = 0.03
local FLAME_SLASH_SHAKE_FADE_OUT = 0.2

type PresentationEvent = {
	castId: string,
	bossModel: Model?,
	bossId: string?,
	moveId: string?,
	moduleId: string?,
	action: string?,
	payload: { [string]: any }?,
	serverTime: number?,
}

type SlashMotionData = {
	startPosition: Vector3,
	direction: Vector3,
	travelDistance: number,
	travelDuration: number,
	startedAtServerTime: number,
	yRotation: number,
}

type ActiveRecord = {
	castId: string,
	moduleId: string,
	bossModel: Model?,
	castFolder: Folder?,
	handleModel: Model?,
	rootModel: Model?,
	slashModel: Model?,
	slashMotion: SlashMotionData?,
	stopRequested: boolean?,
}

local BossArenaMovePresentationController = {
	_started = false,
	_remote = nil :: RemoteEvent?,
	_remoteConnection = nil :: RBXScriptConnection?,
	_cleanupConnection = nil :: RBXScriptConnection?,
	_cameraShaker = nil :: any,
	_recordsByCastId = {} :: { [string]: ActiveRecord },
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
end

local function warnWithPrefix(message: string)
	warn(string.format("[BossArenaMovePresentationController] %s", message))
end

local function resolveBossHandlePart(bossModel: Model?): BasePart?
	if bossModel == nil then
		return nil
	end

	local handle = bossModel:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		return handle
	end

	local recursiveHandle = bossModel:FindFirstChild("Handle", true)
	if recursiveHandle and recursiveHandle:IsA("BasePart") then
		return recursiveHandle
	end

	return nil
end

local function resolveBossRootPart(bossModel: Model?): BasePart?
	if bossModel == nil then
		return nil
	end

	local rootPart = bossModel:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	local primaryPart = bossModel.PrimaryPart
	if primaryPart then
		return primaryPart
	end

	return bossModel:FindFirstChildWhichIsA("BasePart", true)
end

local function resolveVfxModel(effectFolderName: string, modelName: string): Model?
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	if not (gameAssets and gameAssets:IsA("Folder")) then
		return nil
	end

	local vfxFolder = gameAssets:FindFirstChild("VFX")
	if not (vfxFolder and vfxFolder:IsA("Folder")) then
		return nil
	end

	local flameGuardGeneralFolder = vfxFolder:FindFirstChild(FLAME_GUARD_GENERAL_VFX_FOLDER_NAME)
	if not (flameGuardGeneralFolder and flameGuardGeneralFolder:IsA("Folder")) then
		return nil
	end

	local effectFolder = flameGuardGeneralFolder:FindFirstChild(effectFolderName)
	if not (effectFolder and effectFolder:IsA("Folder")) then
		return nil
	end

	local effectModel = effectFolder:FindFirstChild(modelName)
	if effectModel and effectModel:IsA("Model") then
		return effectModel
	end

	return nil
end

local function resolveVfxInstance(effectFolderName: string, instanceName: string): Instance?
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	if not (gameAssets and gameAssets:IsA("Folder")) then
		return nil
	end

	local vfxFolder = gameAssets:FindFirstChild("VFX")
	if not (vfxFolder and vfxFolder:IsA("Folder")) then
		return nil
	end

	local flameGuardGeneralFolder = vfxFolder:FindFirstChild(FLAME_GUARD_GENERAL_VFX_FOLDER_NAME)
	if not (flameGuardGeneralFolder and flameGuardGeneralFolder:IsA("Folder")) then
		return nil
	end

	local effectFolder = flameGuardGeneralFolder:FindFirstChild(effectFolderName)
	if not (effectFolder and effectFolder:IsA("Folder")) then
		return nil
	end

	return effectFolder:FindFirstChild(instanceName)
end

local function prepareAttachedEffectModel(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end
end

local function prepareMovingEffectModel(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end
end

local function prepareMovingEffectPart(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
end

local function resolveFireBurstRingSize(outerRadius: number, templatePart: BasePart): Vector3
	local diameter = math.max(0, outerRadius * 2)
	local height = math.max(0.05, templatePart.Size.Y)
	local specialMesh = templatePart:FindFirstChildOfClass("SpecialMesh")
	if specialMesh then
		local mappedDiameter = diameter / FIRE_BURST_RING_DIAMETER_PER_SIZE_STUD
		return Vector3.new(mappedDiameter, height, mappedDiameter)
	end

	return Vector3.new(diameter, height, diameter)
end

local function resolveFireBurstRingCFrame(position: Vector3, size: Vector3): CFrame
	return CFrame.new(position + Vector3.new(0, size.Y * 0.5, 0))
end

local function enableParticleEmitters(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = true
		end
	end
end

local function createWeld(part0: BasePart, part1: BasePart)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part0
	weld.Part1 = part1
	weld.Parent = part0
	return weld
end

local function resolveEffectModelPrimaryPart(effectModel: Model): BasePart?
	local primaryPart = effectModel.PrimaryPart
	if primaryPart then
		return primaryPart
	end

	local basePart = effectModel:FindFirstChildWhichIsA("BasePart", true)
	if basePart then
		pcall(function()
			effectModel.PrimaryPart = basePart
		end)
	end

	return basePart
end

local function attachEffectModel(effectModel: Model, targetPart: BasePart)
	local primaryPart = resolveEffectModelPrimaryPart(effectModel)
	if primaryPart == nil then
		return false
	end

	effectModel:PivotTo(targetPart.CFrame)
	createWeld(primaryPart, targetPart)
	return true
end

local function scaleAttachedSounds(root: Instance, scaleMultiplier: number)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Sound") then
			descendant.EmitterSize *= scaleMultiplier
		end
	end
end

local function collectEmittableVisuals(root: Instance): { Instance }
	local visuals = {}

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") or descendant:IsA("Beam") or descendant:IsA("RayValue") then
			table.insert(visuals, descendant)
		end
	end

	return visuals
end

local function emitVisuals(instances: { Instance })
	if #instances <= 0 then
		return
	end

	local ok, err = pcall(function()
		EmitModule.emit(table.unpack(instances))
	end)
	if not ok then
		warnWithPrefix(string.format("Failed to emit boss move visuals: %s", tostring(err)))
	end
end

local function playSound(sound: Sound?)
	if sound == nil then
		return
	end

	sound.TimePosition = 0
	sound:Play()
end

local function playAllSounds(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Sound") then
			playSound(descendant)
		end
	end
end

function BossArenaMovePresentationController:_ensureRemote(): RemoteEvent?
	if self._remote then
		return self._remote
	end

	local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, 30)
	if not (remotesFolder and remotesFolder:IsA("Folder")) then
		warnWithPrefix("ReplicatedStorage.Remotes is missing.")
		return nil
	end

	local bossArenaFolder = remotesFolder:WaitForChild(BOSS_ARENA_FOLDER_NAME, 30)
	if not (bossArenaFolder and bossArenaFolder:IsA("Folder")) then
		warnWithPrefix("ReplicatedStorage.Remotes.BossArena is missing.")
		return nil
	end

	local remote = bossArenaFolder:WaitForChild(MOVE_PRESENTATION_REMOTE_NAME, 30)
	if not (remote and remote:IsA("RemoteEvent")) then
		warnWithPrefix("BossArena.BossMovePresentation is missing.")
		return nil
	end

	self._remote = remote
	return remote
end

function BossArenaMovePresentationController:_ensureVisualFolder(): Folder
	local folder = Workspace:FindFirstChild(VISUAL_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end

	local created = Instance.new("Folder")
	created.Name = VISUAL_FOLDER_NAME
	created.Parent = Workspace
	return created
end

function BossArenaMovePresentationController:_ensureCameraShaker()
	if self._cameraShaker then
		return self._cameraShaker
	end

	local shaker = CameraShaker.new(Enum.RenderPriority.Camera.Value + 1, function(shakeCFrame: CFrame)
		local camera = Workspace.CurrentCamera
		if camera then
			camera.CFrame = camera.CFrame * shakeCFrame
		end
	end)
	shaker:Start()
	self._cameraShaker = shaker
	return shaker
end

function BossArenaMovePresentationController:_shakeImpact()
	self:_ensureCameraShaker():ShakeOnce(
		FLAME_SLASH_SHAKE_MAGNITUDE,
		FLAME_SLASH_SHAKE_ROUGHNESS,
		FLAME_SLASH_SHAKE_FADE_IN,
		FLAME_SLASH_SHAKE_FADE_OUT
	)
end

function BossArenaMovePresentationController:_cleanupRecord(record: ActiveRecord?)
	if record == nil then
		return
	end

	self._recordsByCastId[record.castId] = nil
	if record.castFolder and record.castFolder.Parent then
		record.castFolder:Destroy()
	end
end

function BossArenaMovePresentationController:_removeAttachedCastModels(record: ActiveRecord)
	if record.handleModel and record.handleModel.Parent then
		record.handleModel:Destroy()
	end
	if record.rootModel and record.rootModel.Parent then
		record.rootModel:Destroy()
	end
	record.handleModel = nil
	record.rootModel = nil
end

function BossArenaMovePresentationController:_cleanupStaleRecords()
	for _, record in pairs(self._recordsByCastId) do
		if record.bossModel == nil or record.bossModel.Parent == nil then
			self:_cleanupRecord(record)
		elseif record.handleModel and record.handleModel.Parent == nil then
			self:_cleanupRecord(record)
		elseif record.rootModel and record.rootModel.Parent == nil then
			self:_cleanupRecord(record)
		elseif record.slashModel and record.slashModel.Parent == nil then
			self:_cleanupRecord(record)
		elseif resolveBossHandlePart(record.bossModel) == nil or resolveBossRootPart(record.bossModel) == nil then
			self:_cleanupRecord(record)
		end
	end
end

function BossArenaMovePresentationController:_updatePrometheusSlashMotion(record: ActiveRecord, nowServerTime: number)
	local slashModel = record.slashModel
	local slashMotion = record.slashMotion
	if slashModel == nil or slashMotion == nil or slashModel.Parent == nil then
		return
	end

	local elapsed = math.max(0, nowServerTime - slashMotion.startedAtServerTime)
	local alpha = math.clamp(elapsed / math.max(0.001, slashMotion.travelDuration), 0, 1)
	local center = slashMotion.startPosition + (slashMotion.direction * (slashMotion.travelDistance * alpha))
	slashModel:PivotTo(CFrame.lookAt(center, center + slashMotion.direction) * CFrame.Angles(0, slashMotion.yRotation, 0))

	if alpha >= 1 and record.stopRequested then
		self:_cleanupRecord(record)
	end
end

function BossArenaMovePresentationController:_updateActiveRecords()
	self:_cleanupStaleRecords()

	local nowServerTime = Workspace:GetServerTimeNow()
	for _, record in pairs(self._recordsByCastId) do
		if record.moduleId == PROMETHEUS_SLASH_MODULE_ID then
			self:_updatePrometheusSlashMotion(record, nowServerTime)
		end
	end
end

function BossArenaMovePresentationController:_prepareAttachedCastModels(
	record: ActiveRecord,
	event: PresentationEvent,
	moveLabel: string,
	effectFolderName: string,
	options: { enableParticles: boolean?, scaleRootSounds: boolean?, playAllSounds: boolean? }?
): boolean
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return false
	end

	local bossHandle = resolveBossHandlePart(bossModel)
	local bossRootPart = resolveBossRootPart(bossModel)
	if bossHandle == nil or bossRootPart == nil then
		warnWithPrefix(string.format("%s presentation could not resolve the live boss Handle/RootPart.", moveLabel))
		self:_cleanupRecord(record)
		return false
	end

	local handleSource = resolveVfxModel(effectFolderName, "Handle")
	local rootSource = resolveVfxModel(effectFolderName, "RootPart")
	if handleSource == nil or rootSource == nil then
		warnWithPrefix(string.format("%s presentation VFX models are missing from ReplicatedStorage.GameAssets.VFX.", moveLabel))
		self:_cleanupRecord(record)
		return false
	end

	local handleModel = handleSource:Clone()
	local rootModel = rootSource:Clone()
	local scaleMultiplier = math.max(0.1, tonumber(event.payload and event.payload.scaleMultiplier) or 1)

	handleModel:ScaleTo(scaleMultiplier)
	rootModel:ScaleTo(scaleMultiplier)
	prepareAttachedEffectModel(handleModel)
	prepareAttachedEffectModel(rootModel)
	scaleAttachedSounds(handleModel, scaleMultiplier)
	if options and options.scaleRootSounds then
		scaleAttachedSounds(rootModel, scaleMultiplier)
	end
	if options and options.enableParticles then
		enableParticleEmitters(handleModel)
		enableParticleEmitters(rootModel)
	end

	local castFolder = Instance.new("Folder")
	castFolder.Name = record.castId
	castFolder.Parent = self:_ensureVisualFolder()
	record.castFolder = castFolder
	record.handleModel = handleModel
	record.rootModel = rootModel

	handleModel.Parent = castFolder
	rootModel.Parent = castFolder

	if not attachEffectModel(handleModel, bossHandle) or not attachEffectModel(rootModel, bossRootPart) then
		warnWithPrefix(string.format("%s presentation VFX models are missing BasePart configuration.", moveLabel))
		self:_cleanupRecord(record)
		return false
	end

	if options and options.playAllSounds then
		playAllSounds(handleModel)
		playAllSounds(rootModel)
	end

	emitVisuals(collectEmittableVisuals(handleModel))
	emitVisuals(collectEmittableVisuals(rootModel))
	return true
end

function BossArenaMovePresentationController:_startFlameSlash(record: ActiveRecord, event: PresentationEvent)
	if not self:_prepareAttachedCastModels(record, event, "Flame Slash", FLAME_SLASH_VFX_NAME, nil) then
		return
	end

	local chargingSound = record.handleModel and record.handleModel:FindFirstChild("Charging Flame", true)
	playSound(if chargingSound and chargingSound:IsA("Sound") then chargingSound else nil)
end

function BossArenaMovePresentationController:_impactFlameSlash(record: ActiveRecord, event: PresentationEvent)
	if record.handleModel and record.handleModel.Parent then
		local explosionSound = record.handleModel:FindFirstChild("CrystalExplosion", true)
		playSound(if explosionSound and explosionSound:IsA("Sound") then explosionSound else nil)
	end

	self:_shakeImpact()
end

function BossArenaMovePresentationController:_startPrometheusSlash(record: ActiveRecord, event: PresentationEvent)
	self:_prepareAttachedCastModels(record, event, "Prometheus Slash", PROMETHEUS_SLASH_VFX_NAME, {
		enableParticles = true,
		scaleRootSounds = true,
		playAllSounds = true,
	})
end

function BossArenaMovePresentationController:_impactPrometheusSlash(record: ActiveRecord, event: PresentationEvent)
	local castFolder = record.castFolder
	if castFolder == nil or castFolder.Parent == nil then
		return
	end

	local payload = event.payload
	if typeof(payload) ~= "table" then
		return
	end

	local startPosition = payload.startPosition
	local direction = payload.direction
	local travelDistance = tonumber(payload.travelDistance)
	local visualTravelDistance = tonumber(payload.visualTravelDistance) or tonumber(payload.debrisTravelDistance)
	local travelDuration = tonumber(payload.travelDuration)
	local visualTravelDuration = tonumber(payload.visualTravelDuration)
	local yRotation = tonumber(payload.yRotation)
	local slashScale = tonumber(payload.slashScale) or 12.5
	if typeof(startPosition) ~= "Vector3"
		or typeof(direction) ~= "Vector3"
		or travelDistance == nil
		or travelDuration == nil
		or yRotation == nil
		or direction.Magnitude <= 0.001 then
		return
	end

	local slashSource = resolveVfxModel(PROMETHEUS_SLASH_VFX_NAME, "Slash")
	if slashSource == nil then
		warnWithPrefix("Prometheus Slash slash VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		return
	end

	local slashModel = slashSource:Clone()
	slashModel:ScaleTo(slashScale)
	prepareMovingEffectModel(slashModel)
	enableParticleEmitters(slashModel)

	if resolveEffectModelPrimaryPart(slashModel) == nil then
		warnWithPrefix("Prometheus Slash slash VFX model is missing a BasePart for motion.")
		return
	end

	record.slashModel = slashModel
	record.slashMotion = {
		startPosition = startPosition,
		direction = direction.Unit,
		travelDistance = visualTravelDistance or travelDistance,
		travelDuration = visualTravelDuration or travelDuration,
		startedAtServerTime = if typeof(event.serverTime) == "number" then event.serverTime else Workspace:GetServerTimeNow(),
		yRotation = yRotation,
	}

	slashModel.Parent = castFolder
	playAllSounds(slashModel)
	emitVisuals(collectEmittableVisuals(slashModel))
	self:_updatePrometheusSlashMotion(record, Workspace:GetServerTimeNow())
end

function BossArenaMovePresentationController:_startFireBurst(record: ActiveRecord, event: PresentationEvent)
	self:_prepareAttachedCastModels(record, event, "Fire Burst", FIRE_BURST_VFX_NAME, {
		enableParticles = true,
		scaleRootSounds = true,
		playAllSounds = true,
	})
end

function BossArenaMovePresentationController:_impactFireBurst(_record: ActiveRecord, event: PresentationEvent)
	self:_shakeImpact()

	local record = self._recordsByCastId[event.castId]
	if record == nil or record.castFolder == nil or record.castFolder.Parent == nil then
		return
	end

	local payload = event.payload
	if typeof(payload) ~= "table" then
		return
	end

	local impactPosition = payload.impactPosition
	local startRadius = tonumber(payload.startRadius)
	local endRadius = tonumber(payload.endRadius) or startRadius
	local ringThickness = tonumber(payload.ringThickness) or 0
	local durationSeconds = math.max(0, tonumber(payload.durationSeconds) or 0)
	if typeof(impactPosition) ~= "Vector3" or startRadius == nil then
		return
	end

	local ringSource = resolveVfxInstance(FIRE_BURST_VFX_NAME, FIRE_BURST_RING_VFX_NAME)
	if not (ringSource and ringSource:IsA("BasePart")) then
		warnWithPrefix("Fire Burst MapRing VFX part is missing from ReplicatedStorage.GameAssets.VFX.")
		return
	end

	local ringPart = ringSource:Clone()
	prepareMovingEffectPart(ringPart)
	ringPart.Parent = record.castFolder

	local startOuterRadius = math.max(0, startRadius + (ringThickness * 0.5))
	local endOuterRadius = math.max(0, (endRadius or startRadius) + (ringThickness * 0.5))
	local startSize = resolveFireBurstRingSize(startOuterRadius, ringPart)
	local endSize = resolveFireBurstRingSize(endOuterRadius, ringPart)
	ringPart.Size = startSize
	ringPart.CFrame = resolveFireBurstRingCFrame(impactPosition, startSize)

	if durationSeconds <= 0 then
		ringPart.Size = endSize
		ringPart.CFrame = resolveFireBurstRingCFrame(impactPosition, endSize)
		return
	end

	local tween = TweenService:Create(
		ringPart,
		TweenInfo.new(durationSeconds, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
		{ Size = endSize }
	)
	tween:Play()

	task.delay(durationSeconds, function()
		if ringPart.Parent ~= nil then
			ringPart.CFrame = resolveFireBurstRingCFrame(impactPosition, ringPart.Size)
		end
	end)
end

function BossArenaMovePresentationController:_handleEvent(payload: any)
	if typeof(payload) ~= "table" then
		return
	end

	local event = payload :: PresentationEvent
	local castId = event.castId
	local moduleId = event.moduleId
	local action = event.action
	if type(castId) ~= "string" or castId == "" or type(moduleId) ~= "string" or type(action) ~= "string" then
		return
	end

	if moduleId ~= FLAME_SLASH_MODULE_ID
		and moduleId ~= PROMETHEUS_SLASH_MODULE_ID
		and moduleId ~= FIRE_BURST_MODULE_ID then
		return
	end

	if action == "start" then
		self:_cleanupRecord(self._recordsByCastId[castId])

		local record: ActiveRecord = {
			castId = castId,
			moduleId = moduleId,
			bossModel = event.bossModel,
			castFolder = nil,
			handleModel = nil,
			rootModel = nil,
			slashModel = nil,
			slashMotion = nil,
			stopRequested = false,
		}
		self._recordsByCastId[castId] = record

		if moduleId == FLAME_SLASH_MODULE_ID then
			self:_startFlameSlash(record, event)
		elseif moduleId == PROMETHEUS_SLASH_MODULE_ID then
			self:_startPrometheusSlash(record, event)
		elseif moduleId == FIRE_BURST_MODULE_ID then
			self:_startFireBurst(record, event)
		end
		return
	end

	local record = self._recordsByCastId[castId]
	if record == nil then
		return
	end

	if action == "impact" then
		if moduleId == FLAME_SLASH_MODULE_ID then
			self:_impactFlameSlash(record, event)
		elseif moduleId == PROMETHEUS_SLASH_MODULE_ID then
			self:_impactPrometheusSlash(record, event)
		elseif moduleId == FIRE_BURST_MODULE_ID then
			self:_impactFireBurst(record, event)
		end
	elseif action == "stop" then
		if moduleId == PROMETHEUS_SLASH_MODULE_ID and record.slashModel and record.slashMotion and record.slashModel.Parent then
			record.stopRequested = true
			self:_removeAttachedCastModels(record)
			self:_updatePrometheusSlashMotion(record, Workspace:GetServerTimeNow())
			return
		end

		self:_cleanupRecord(record)
	end
end

function BossArenaMovePresentationController:OnStart()
	if self._started then
		return
	end
	self._started = true

	if not isEnabledForPlace() then
		return
	end

	local remote = self:_ensureRemote()
	if remote == nil then
		return
	end

	self:_ensureCameraShaker()
	self._remoteConnection = remote.OnClientEvent:Connect(function(payload)
		self:_handleEvent(payload)
	end)
	self._cleanupConnection = RunService.Heartbeat:Connect(function()
		self:_updateActiveRecords()
	end)
end

return BossArenaMovePresentationController
