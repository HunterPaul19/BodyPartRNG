local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CameraShaker = require(ReplicatedStorage.Shared.Camera.CameraShaker)
local Indication = require(ReplicatedStorage.Shared.Bosses.Indication)
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
local SQUID_CALL_MODULE_ID = "Moves.CaptainSquid.SquidCall"
local SHIP_CALL_MODULE_ID = "Moves.CaptainSquid.ShipCall"
local WAVE_CRASH_MODULE_ID = "Moves.MerfinTheGreat.WaveCrash"
local WATER_BOMB_MODULE_ID = "Moves.MerfinTheGreat.WaterBomb"
local BUBBLE_BLAST_MODULE_ID = "Moves.MerfinTheGreat.BubbleBlast"
local BROCCOLI_GRAB_MODULE_ID = "Moves.BroccoliBro.Grab"
local BROCCOLI_SPROUT_MODULE_ID = "Moves.BroccoliBro.BroccoliSprout"
local MAGMA_THROW_MODULE_ID = "Moves.MagmaFiend.MagmaThrow"
local MAGMA_STOMP_MODULE_ID = "Moves.MagmaFiend.Stomp"
local MAGMA_ERUPTION_MODULE_ID = "Moves.MagmaFiend.Eruption"
local OINAN_THICKHOOF_CHARGE_MODULE_ID = "Moves.OinanThickhoof.BullCharge"
local OINAN_THICKHOOF_ROAR_MODULE_ID = "Moves.OinanThickhoof.BullRoar"
local OINAN_THICKHOOF_STOMP_MODULE_ID = "Moves.OinanThickhoof.Stomp"
local BROCCOLI_BRO_STOMP_MODULE_ID = "Moves.BroccoliBro.Stomp"
local DESTROYER_MISSILE_BARRAGE_MODULE_ID = "Moves.Destroyer3000.MissileBarrage"
local MECHA_KICK_MODULE_ID = "Moves.MechArmouredMobileSuitBipedColourable.MechaKick"
local DESTROYER_3000_MECHA_KICK_MODULE_ID = "Moves.Destroyer3000.MechaKick"
local DESTROYER_3000_MECHA_PUNCH_MODULE_ID = "Moves.Destroyer3000.MechaPunch"
local FLAME_GUARD_GENERAL_VFX_FOLDER_NAME = "FlameGuardGeneral"
local FLAME_SLASH_VFX_NAME = "FlameSlash"
local PROMETHEUS_SLASH_VFX_NAME = "PrometheusSlash"
local FIRE_BURST_VFX_NAME = "FlameBurst"
local FIRE_BURST_RING_VFX_NAME = "MapRing"
local FIRE_BURST_RING_DIAMETER_PER_SIZE_STUD = 85
local CAPTAIN_SQUID_VFX_FOLDER_NAME = "CaptainSquid"
local CAPTAIN_SQUID_SQUID_CALL_VFX_NAME = "SquidCall"
local CAPTAIN_SQUID_SHIP_CALL_VFX_NAME = "ShipCall"
local SQUID_CALL_LEFT_HAND_MODEL_NAME = "LeftHand"
local SQUID_CALL_CANNON_MODEL_NAME = "Cannon"
local SQUID_CALL_CANNONBALL_MODEL_NAME = "CannonBall"
local SQUID_CALL_CANNON_MIDDLE_NAME = "Middle"
local SQUID_CALL_CANNON_MUZZLE_ATTACHMENT_NAME = "CannonBall"
local SQUID_CALL_PROJECTILE_FLY_ATTACHMENT_NAME = "FlyAtt"
local SQUID_CALL_PROJECTILE_IMPACT_PART_NAME = "BallHit"
local SQUID_CALL_CANNON_ASSET_YAW_OFFSET_RADIANS = math.rad(90)
local SQUID_CALL_LEFT_HAND_LIFETIME_SECONDS = 2.5
local SQUID_CALL_IMPACT_LIFETIME_SECONDS = 2
local SHIP_CALL_LEFT_HAND_MODEL_NAME = "LeftHand"
local SHIP_CALL_SHIP_MODEL_NAME = "Ship"
local MERFIN_THE_GREAT_VFX_FOLDER_NAME = "MerfinTheGreat"
local WAVE_CRASH_VFX_NAME = "WaveCrash"
local WAVE_CRASH_LEFT_HAND_MODEL_NAME = "LeftHand"
local WAVE_CRASH_RIGHT_HAND_MODEL_NAME = "RightHand"
local WAVE_CRASH_WAVE_MODEL_NAME = "Wave"
local WATER_BOMB_VFX_NAME = "WaterBomb"
local WATER_BOMB_FLOOR_MODEL_NAME = "Floor"
local WATER_BOMB_BALL_MODEL_NAME = "Ball"
local WATER_BOMB_EXPLOSION_MODEL_NAME = "BombExplosion"
local WATER_BOMB_FLOOR_LIFETIME_SECONDS = 2.5
local WATER_BOMB_EXPLOSION_LIFETIME_SECONDS = 3
local BUBBLE_BLAST_VFX_NAME = "BubbleBlast"
local BUBBLE_BLAST_LEFT_HAND_MODEL_NAME = "LeftHand"
local BUBBLE_BLAST_ROOT_PART_MODEL_NAME = "RootPart"
local BUBBLE_BLAST_PROJECTILE_MODEL_NAME = "Projectile"
local BUBBLE_BLAST_HIT_MODEL_NAME = "Hit"
local BUBBLE_BLAST_HIT_LIFETIME_SECONDS = 2.5
local BROCCOLI_BRO_VFX_FOLDER_NAME = "BroccoliBro"
local BROCCOLI_GRAB_VFX_NAME = "Throw"
local BROCCOLI_GRAB_EXPLOSION_MODEL_NAME = "ThrowExplosion"
local BROCCOLI_GRAB_EXPLOSION_FLOOR_ATTACHMENT_NAME = "Floor"
local BROCCOLI_GRAB_EXPLOSION_LIFETIME_SECONDS = 3
local BROCCOLI_SPROUT_VFX_NAME = "BroccoliSprout"
local BROCCOLI_SPROUT_FLOOR_VFX_NAME = "Floor"
local BROCCOLI_SPROUT_TREE_VFX_NAME = "Broccoli"
local BROCCOLI_SPROUT_VFX_LIFETIME_SECONDS = 3
local MAGMA_FIEND_VFX_FOLDER_NAME = "MagmaFiend"
local MAGMA_THROW_VFX_NAME = "MagmaThrow"
local MAGMA_THROW_LEFT_HAND_MODEL_NAME = "LeftHand"
local MAGMA_THROW_PROJECTILE_MODEL_NAME = "Projectile"
local MAGMA_THROW_EXPLOSION_MODEL_NAME = "Explosion"
local MAGMA_THROW_ROOT_PART_MODEL_NAME = "RootPart"
local MAGMA_THROW_VFX_LIFETIME_SECONDS = 2
local MAGMA_STOMP_VFX_NAME = "LavaStomp"
local MAGMA_STOMP_FLOOR_MODEL_NAME = "Floor"
local MAGMA_STOMP_VFX_LIFETIME_SECONDS = 3
local MAGMA_ERUPTION_VFX_NAME = "EruptionThrow"
local MAGMA_ERUPTION_LEFT_HAND_MODEL_NAME = "LeftHand"
local MAGMA_ERUPTION_RIGHT_HAND_MODEL_NAME = "RightHand"
local MAGMA_ERUPTION_FLOOR_MODEL_NAME = "Floor"
local MAGMA_ERUPTION_VFX_LIFETIME_SECONDS = 3
local OINAN_THICKHOOF_VFX_FOLDER_NAME = "OinanThickhoof"
local OINAN_THICKHOOF_CHARGE_VFX_NAME = "BullCharge"
local OINAN_THICKHOOF_CHARGE_ROOT_VFX_NAME = "RootPart"
local OINAN_THICKHOOF_ROAR_VFX_NAME = "BullRoar"
local OINAN_THICKHOOF_ROAR_START_VFX_NAME = "Start"
local OINAN_THICKHOOF_ROAR_IMPACT_VFX_NAME = "Roar"
local OINAN_THICKHOOF_ROAR_VFX_LIFETIME_SECONDS = 3
local OINAN_THICKHOOF_STOMP_VFX_NAME = "Stomp"
local OINAN_THICKHOOF_STOMP_FLOOR_VFX_NAME = "FloorFx"
local OINAN_THICKHOOF_STOMP_VFX_LIFETIME_SECONDS = 3
local BROCCOLI_BRO_STOMP_VFX_NAME = "Stomp"
local BROCCOLI_BRO_STOMP_FLOOR_VFX_NAME = "FloorFx"
local BROCCOLI_BRO_STOMP_VFX_LIFETIME_SECONDS = 3
local DESTROYER_3000_VFX_FOLDER_NAME = "Destroyer3000"
local DESTROYER_MISSILE_BARRAGE_VFX_NAME = "MissileBarrage"
local DESTROYER_MISSILE_BARRAGE_PROJECTILE_VFX_NAME = "Projectile"
local DESTROYER_MISSILE_BARRAGE_UPPER_TORSO_VFX_NAME = "UpperTorso"
local DESTROYER_MISSILE_BARRAGE_ROOT_PART_VFX_NAME = "RootPart"
local DESTROYER_MISSILE_BARRAGE_EXPLOSION_LIFETIME_SECONDS = 2.5
local MECHA_KICK_VFX_NAME = "MechaKick"
local MECHA_KICK_LEFT_FOOT_VFX_NAME = "LeftFoot"
local MECHA_KICK_EXPLOSION_VFX_NAME = "Explosion"
local MECHA_KICK_LEFT_FOOT_VFX_LIFETIME_SECONDS = 2.5
local MECHA_KICK_EXPLOSION_VFX_LIFETIME_SECONDS = 3
local MECHA_PUNCH_VFX_NAME = "MechaPunch"
local MECHA_PUNCH_ROOT_PART_VFX_NAME = "RootPart"
local MECHA_PUNCH_RIGHT_HAND_VFX_NAME = "RightHand"
local MECHA_PUNCH_EXPLOSION_VFX_NAME = "Explosion"
local MECHA_PUNCH_EXPLOSION_VFX_LIFETIME_SECONDS = 3
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

type SquidCallAimData = {
	startedAtServerTime: number,
	duration: number,
	targetUserId: number?,
	initialBaseCFrame: CFrame,
	middleLocalCFrame: CFrame,
	lastKnownTargetPosition: Vector3?,
}

type SquidCallProjectileMotionData = {
	startPosition: Vector3,
	impactPosition: Vector3,
	travelDuration: number,
	startedAtServerTime: number,
}

type ShipCallMotionData = {
	startCFrame: CFrame,
	direction: Vector3,
	speed: number,
	startedAtServerTime: number,
}

type WaveCrashMotionData = {
	startCFrame: CFrame,
	direction: Vector3,
	speed: number,
	durationSeconds: number,
	startedAtServerTime: number,
}

type WaterBombChargeData = {
	startPosition: Vector3,
	endPosition: Vector3,
	startScale: number,
	endScale: number,
	startedAtServerTime: number,
	duration: number,
}

type BubbleBlastProjectileMotionData = {
	startPosition: Vector3,
	impactPosition: Vector3,
	travelDuration: number,
	startedAtServerTime: number,
}

type MissileBarrageProjectileMotionData = {
	startPosition: Vector3,
	controlPosition: Vector3,
	impactPosition: Vector3,
	travelDuration: number,
	startedAtServerTime: number,
}

type ActiveRecord = {
	castId: string,
	moduleId: string,
	bossModel: Model?,
	castFolder: Folder?,
	handleModel: Model?,
	upperTorsoModel: Model?,
	rootModel: Model?,
	slashModel: Model?,
	slashMotion: SlashMotionData?,
	leftFootModel: Model?,
	leftHandModel: Model?,
	cannonModel: Model?,
	cannonMiddle: BasePart?,
	cannonMuzzleAttachment: Attachment?,
	squidCallAimData: SquidCallAimData?,
	projectileModel: Model?,
	projectileMotion: SquidCallProjectileMotionData?,
	rightHandModel: Model?,
	shipModel: Model?,
	shipMotion: ShipCallMotionData?,
	waveModel: Model?,
	waveMotion: WaveCrashMotionData?,
	waterBombChargeData: WaterBombChargeData?,
	bubbleBlastProjectileModels: { [number]: Model }?,
	bubbleBlastProjectileMotions: { [number]: BubbleBlastProjectileMotionData }?,
	missileBarrageProjectileModels: { [number]: Model }?,
	missileBarrageProjectileMotions: { [number]: MissileBarrageProjectileMotionData }?,
	eruptionWarningHandles: { [number]: any }?,
	broccoliSproutWarningHandles: { [number]: any }?,
	broccoliSproutTweens: { Tween }?,
	broccoliSproutTweenConnections: { RBXScriptConnection }?,
	broccoliSproutTweenValues: { CFrameValue }?,
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

local function initializeEmitModule()
	local ok, err = pcall(function()
		EmitModule.init()
	end)
	if not ok then
		warnWithPrefix(string.format("Failed to initialize EmitModule: %s", tostring(err)))
	end
end

local function emitEffectInstance(instance: Instance, duration: number?)
	local ok, err = pcall(function()
		EmitModule.emit(instance, duration)
	end)
	if not ok then
		warnWithPrefix(string.format("Failed to emit boss move effect instance: %s", tostring(err)))
	end
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

local function resolveBossUpperTorsoPart(bossModel: Model?): BasePart?
	if bossModel == nil then
		return nil
	end

	local upperTorso = bossModel:FindFirstChild("UpperTorso", true)
	if upperTorso and upperTorso:IsA("BasePart") then
		return upperTorso
	end

	local torso = bossModel:FindFirstChild("Torso", true)
	if torso and torso:IsA("BasePart") then
		return torso
	end

	return nil
end

local function resolveBossLeftHandPart(bossModel: Model?): BasePart?
	if bossModel == nil then
		return nil
	end

	local leftHand = bossModel:FindFirstChild("LeftHand", true)
	if leftHand and leftHand:IsA("BasePart") then
		return leftHand
	end

	local spacedLeftHand = bossModel:FindFirstChild("Left Hand", true)
	if spacedLeftHand and spacedLeftHand:IsA("BasePart") then
		return spacedLeftHand
	end

	return nil
end

local function resolveBossLeftFootPart(bossModel: Model?): BasePart?
	if bossModel == nil then
		return nil
	end

	local leftFoot = bossModel:FindFirstChild("LeftFoot", true)
	if leftFoot and leftFoot:IsA("BasePart") then
		return leftFoot
	end

	local spacedLeftFoot = bossModel:FindFirstChild("Left Foot", true)
	if spacedLeftFoot and spacedLeftFoot:IsA("BasePart") then
		return spacedLeftFoot
	end

	local leftLowerLeg = bossModel:FindFirstChild("LeftLowerLeg", true)
	if leftLowerLeg and leftLowerLeg:IsA("BasePart") then
		return leftLowerLeg
	end

	return nil
end

local function resolveBossRightHandPart(bossModel: Model?): BasePart?
	if bossModel == nil then
		return nil
	end

	local rightHand = bossModel:FindFirstChild("RightHand", true)
	if rightHand and rightHand:IsA("BasePart") then
		return rightHand
	end

	local spacedRightHand = bossModel:FindFirstChild("Right Hand", true)
	if spacedRightHand and spacedRightHand:IsA("BasePart") then
		return spacedRightHand
	end

	return nil
end

local function resolveBossVfxFolder(bossFolderName: string, effectFolderName: string): Folder?
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	if not (gameAssets and gameAssets:IsA("Folder")) then
		return nil
	end

	local vfxFolder = gameAssets:FindFirstChild("VFX")
	if not (vfxFolder and vfxFolder:IsA("Folder")) then
		return nil
	end

	local bossFolder = vfxFolder:FindFirstChild(bossFolderName)
	if not (bossFolder and bossFolder:IsA("Folder")) then
		return nil
	end

	local effectFolder = bossFolder:FindFirstChild(effectFolderName)
	if not (effectFolder and effectFolder:IsA("Folder")) then
		return nil
	end

	return effectFolder
end

local function resolveBossVfxModel(bossFolderName: string, effectFolderName: string, modelName: string): Model?
	local effectFolder = resolveBossVfxFolder(bossFolderName, effectFolderName)
	if not effectFolder then
		return nil
	end

	local effectModel = effectFolder:FindFirstChild(modelName)
	if effectModel and effectModel:IsA("Model") then
		return effectModel
	end

	return nil
end

local function resolveBossVfxInstance(bossFolderName: string, effectFolderName: string, instanceName: string): Instance?
	local effectFolder = resolveBossVfxFolder(bossFolderName, effectFolderName)
	if not effectFolder then
		return nil
	end
	return effectFolder:FindFirstChild(instanceName)
end

local function resolveVfxModel(effectFolderName: string, modelName: string): Model?
	return resolveBossVfxModel(FLAME_GUARD_GENERAL_VFX_FOLDER_NAME, effectFolderName, modelName)
end

local function resolveVfxInstance(effectFolderName: string, instanceName: string): Instance?
	return resolveBossVfxInstance(FLAME_GUARD_GENERAL_VFX_FOLDER_NAME, effectFolderName, instanceName)
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

local function setBasePartTransparency(root: Instance, transparency: number)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Transparency = transparency
		end
	end
end

local function destroyAfter(instance: Instance?, delaySeconds: number)
	if instance == nil then
		return
	end

	task.delay(delaySeconds, function()
		if instance.Parent ~= nil then
			instance:Destroy()
		end
	end)
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

local function enableVfxDescendants(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") or descendant:IsA("Trail") then
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

local function resolveNamedAttachment(root: Instance, attachmentName: string): Attachment?
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Attachment") and string.lower(descendant.Name) == string.lower(attachmentName) then
			return descendant
		end
	end

	return nil
end

local function pivotModelAttachmentToCFrame(effectModel: Model, attachment: Attachment, targetCFrame: CFrame)
	local currentPivot = effectModel:GetPivot()
	local attachmentToPivot = attachment.WorldCFrame:ToObjectSpace(currentPivot)
	effectModel:PivotTo(targetCFrame * attachmentToPivot)
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

local function resolveQuadraticBezierPosition(startPosition: Vector3, controlPosition: Vector3, endPosition: Vector3, alpha: number): Vector3
	local clampedAlpha = math.clamp(alpha, 0, 1)
	local first = startPosition:Lerp(controlPosition, clampedAlpha)
	local second = controlPosition:Lerp(endPosition, clampedAlpha)
	return first:Lerp(second, clampedAlpha)
end

local function resolvePlanarDirection(fromPosition: Vector3, toPosition: Vector3?, fallbackDirection: Vector3?): Vector3
	if typeof(toPosition) == "Vector3" then
		local offset = toPosition - fromPosition
		local planarOffset = Vector3.new(offset.X, 0, offset.Z)
		if planarOffset.Magnitude > 0.001 then
			return planarOffset.Unit
		end
	end

	if typeof(fallbackDirection) == "Vector3" then
		local planarFallback = Vector3.new(fallbackDirection.X, 0, fallbackDirection.Z)
		if planarFallback.Magnitude > 0.001 then
			return planarFallback.Unit
		end
	end

	return Vector3.xAxis
end

local function resolveCannonBaseCFrame(originPosition: Vector3, targetPosition: Vector3?, fallbackDirection: Vector3?): CFrame
	local planarDirection = resolvePlanarDirection(originPosition, targetPosition, fallbackDirection)
	return CFrame.lookAt(originPosition, originPosition + planarDirection) * CFrame.Angles(0, SQUID_CALL_CANNON_ASSET_YAW_OFFSET_RADIANS, 0)
end

local function resolveSquidCallPitch(middleBaseCFrame: CFrame, targetPosition: Vector3?): number
	if typeof(targetPosition) ~= "Vector3" then
		return 0
	end

	local offset = targetPosition - middleBaseCFrame.Position
	local planarDistance = Vector3.new(offset.X, 0, offset.Z).Magnitude
	return math.atan2(offset.Y, math.max(planarDistance, 0.001))
end

local function resolvePlayerRootPartByUserId(userId: number?): BasePart?
	if typeof(userId) ~= "number" then
		return nil
	end

	local player = Players:GetPlayerByUserId(userId)
	if player == nil then
		return nil
	end

	local character = player.Character
	if character == nil then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	local primaryPart = character.PrimaryPart
	if primaryPart then
		return primaryPart
	end

	return character:FindFirstChildWhichIsA("BasePart", true)
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
	if record.eruptionWarningHandles then
		for _, warningHandle in pairs(record.eruptionWarningHandles) do
			warningHandle:Destroy()
		end
		record.eruptionWarningHandles = nil
	end
	if record.broccoliSproutWarningHandles then
		for _, warningHandle in pairs(record.broccoliSproutWarningHandles) do
			warningHandle:Destroy()
		end
		record.broccoliSproutWarningHandles = nil
	end
	if record.broccoliSproutTweens then
		for _, tween in ipairs(record.broccoliSproutTweens) do
			tween:Cancel()
		end
		record.broccoliSproutTweens = nil
	end
	if record.broccoliSproutTweenConnections then
		for _, connection in ipairs(record.broccoliSproutTweenConnections) do
			if connection.Connected then
				connection:Disconnect()
			end
		end
		record.broccoliSproutTweenConnections = nil
	end
	if record.broccoliSproutTweenValues then
		for _, valueObject in ipairs(record.broccoliSproutTweenValues) do
			if valueObject.Parent ~= nil then
				valueObject:Destroy()
			end
		end
		record.broccoliSproutTweenValues = nil
	end
	if record.castFolder and record.castFolder.Parent then
		record.castFolder:Destroy()
	end
	record.missileBarrageProjectileModels = nil
	record.missileBarrageProjectileMotions = nil
end

function BossArenaMovePresentationController:_removeAttachedCastModels(record: ActiveRecord)
	if record.handleModel and record.handleModel.Parent then
		record.handleModel:Destroy()
	end
	if record.upperTorsoModel and record.upperTorsoModel.Parent then
		record.upperTorsoModel:Destroy()
	end
	if record.rootModel and record.rootModel.Parent then
		record.rootModel:Destroy()
	end
	record.handleModel = nil
	record.upperTorsoModel = nil
	record.rootModel = nil
end

function BossArenaMovePresentationController:_ensureCastFolder(record: ActiveRecord): Folder
	if record.castFolder and record.castFolder.Parent then
		return record.castFolder
	end

	local castFolder = Instance.new("Folder")
	castFolder.Name = record.castId
	castFolder.Parent = self:_ensureVisualFolder()
	record.castFolder = castFolder
	return castFolder
end

function BossArenaMovePresentationController:_cleanupStaleRecords()
	for _, record in pairs(self._recordsByCastId) do
		if record.bossModel == nil or record.bossModel.Parent == nil then
			self:_cleanupRecord(record)
		elseif resolveBossRootPart(record.bossModel) == nil then
			self:_cleanupRecord(record)
		elseif record.moduleId ~= OINAN_THICKHOOF_CHARGE_MODULE_ID
			and record.moduleId ~= OINAN_THICKHOOF_ROAR_MODULE_ID
			and record.moduleId ~= OINAN_THICKHOOF_STOMP_MODULE_ID
			and record.moduleId ~= BROCCOLI_GRAB_MODULE_ID
			and record.moduleId ~= BROCCOLI_SPROUT_MODULE_ID
			and record.moduleId ~= BROCCOLI_BRO_STOMP_MODULE_ID
			and record.moduleId ~= MAGMA_THROW_MODULE_ID
			and record.moduleId ~= MAGMA_STOMP_MODULE_ID
			and record.moduleId ~= MAGMA_ERUPTION_MODULE_ID
			and record.moduleId ~= MECHA_KICK_MODULE_ID
			and record.moduleId ~= DESTROYER_3000_MECHA_KICK_MODULE_ID
			and record.moduleId ~= DESTROYER_3000_MECHA_PUNCH_MODULE_ID
			and record.moduleId ~= DESTROYER_MISSILE_BARRAGE_MODULE_ID
			and resolveBossHandlePart(record.bossModel) == nil then
			self:_cleanupRecord(record)
		elseif record.moduleId == PROMETHEUS_SLASH_MODULE_ID then
			if record.handleModel and record.handleModel.Parent == nil then
				self:_cleanupRecord(record)
			elseif record.rootModel and record.rootModel.Parent == nil then
				self:_cleanupRecord(record)
			elseif record.slashModel and record.slashModel.Parent == nil then
				self:_cleanupRecord(record)
			end
		elseif record.moduleId == SQUID_CALL_MODULE_ID then
			if record.cannonModel and record.cannonModel.Parent == nil then
				self:_cleanupRecord(record)
			elseif record.projectileModel and record.projectileModel.Parent == nil then
				self:_cleanupRecord(record)
			end
		elseif record.moduleId == SHIP_CALL_MODULE_ID then
			if record.leftHandModel and record.leftHandModel.Parent == nil then
				self:_cleanupRecord(record)
			elseif record.shipModel and record.shipModel.Parent == nil then
				self:_cleanupRecord(record)
			end
		elseif record.moduleId == WAVE_CRASH_MODULE_ID then
			if record.leftHandModel and record.leftHandModel.Parent == nil then
				self:_cleanupRecord(record)
			elseif record.rightHandModel and record.rightHandModel.Parent == nil then
				self:_cleanupRecord(record)
			elseif record.waveModel and record.waveModel.Parent == nil then
				self:_cleanupRecord(record)
			end
		elseif record.moduleId == WATER_BOMB_MODULE_ID then
			if record.projectileModel and record.projectileModel.Parent == nil then
				self:_cleanupRecord(record)
			end
		elseif record.moduleId == BUBBLE_BLAST_MODULE_ID then
			if record.leftHandModel and record.leftHandModel.Parent == nil then
				self:_cleanupRecord(record)
			elseif record.rootModel and record.rootModel.Parent == nil then
				self:_cleanupRecord(record)
			end
		elseif record.moduleId == MAGMA_THROW_MODULE_ID then
			if record.projectileModel and record.projectileModel.Parent == nil then
				self:_cleanupRecord(record)
			end
		elseif record.moduleId == MAGMA_ERUPTION_MODULE_ID then
			if record.leftHandModel and record.leftHandModel.Parent == nil then
				self:_cleanupRecord(record)
			elseif record.rightHandModel and record.rightHandModel.Parent == nil then
				self:_cleanupRecord(record)
			end
		elseif record.moduleId == MECHA_KICK_MODULE_ID or record.moduleId == DESTROYER_3000_MECHA_KICK_MODULE_ID then
			if record.leftFootModel and record.leftFootModel.Parent == nil then
				self:_cleanupRecord(record)
			end
		elseif record.moduleId == DESTROYER_MISSILE_BARRAGE_MODULE_ID then
			if record.upperTorsoModel and record.upperTorsoModel.Parent == nil then
				self:_cleanupRecord(record)
			elseif record.rootModel and record.rootModel.Parent == nil then
				self:_cleanupRecord(record)
			end
		elseif record.moduleId == DESTROYER_3000_MECHA_PUNCH_MODULE_ID then
			if record.rootModel and record.rootModel.Parent == nil then
				self:_cleanupRecord(record)
			elseif record.rightHandModel and record.rightHandModel.Parent == nil then
				self:_cleanupRecord(record)
			end
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

function BossArenaMovePresentationController:_applySquidCallCannonPose(record: ActiveRecord, targetPosition: Vector3?, alpha: number)
	local cannonModel = record.cannonModel
	local cannonMiddle = record.cannonMiddle
	local aimData = record.squidCallAimData
	local bossRootPart = resolveBossRootPart(record.bossModel)
	if cannonModel == nil or cannonMiddle == nil or aimData == nil or bossRootPart == nil then
		return
	end

	local desiredBaseCFrame = resolveCannonBaseCFrame(
		bossRootPart.Position,
		targetPosition,
		aimData.initialBaseCFrame.RightVector
	)
	local baseCFrame = aimData.initialBaseCFrame:Lerp(desiredBaseCFrame, math.clamp(alpha, 0, 1))
	cannonModel:PivotTo(baseCFrame)

	local middleBaseCFrame = baseCFrame * aimData.middleLocalCFrame
	cannonMiddle.CFrame = middleBaseCFrame * CFrame.Angles(resolveSquidCallPitch(middleBaseCFrame, targetPosition), 0, 0)
end

function BossArenaMovePresentationController:_updateSquidCallMotion(record: ActiveRecord, nowServerTime: number)
	local aimData = record.squidCallAimData
	if aimData ~= nil then
		local targetRootPart = resolvePlayerRootPartByUserId(aimData.targetUserId)
		if targetRootPart then
			aimData.lastKnownTargetPosition = targetRootPart.Position
		end

		local elapsed = math.max(0, nowServerTime - aimData.startedAtServerTime)
		local alpha = math.clamp(elapsed / math.max(0.001, aimData.duration), 0, 1)
		self:_applySquidCallCannonPose(record, aimData.lastKnownTargetPosition, alpha)
	end

	local projectileModel = record.projectileModel
	local projectileMotion = record.projectileMotion
	if projectileModel == nil or projectileMotion == nil or projectileModel.Parent == nil then
		return
	end

	local alpha = math.clamp(
		(nowServerTime - projectileMotion.startedAtServerTime) / math.max(0.001, projectileMotion.travelDuration),
		0,
		1
	)
	local position = projectileMotion.startPosition:Lerp(projectileMotion.impactPosition, alpha)
	projectileModel:PivotTo(CFrame.new(position))
end

function BossArenaMovePresentationController:_updateShipCallMotion(record: ActiveRecord, nowServerTime: number)
	local shipModel = record.shipModel
	local shipMotion = record.shipMotion
	if shipModel == nil or shipMotion == nil or shipModel.Parent == nil then
		return
	end

	local elapsed = math.max(0, nowServerTime - shipMotion.startedAtServerTime)
	local currentPosition = shipMotion.startCFrame.Position + (shipMotion.direction * (shipMotion.speed * elapsed))
	shipModel:PivotTo(CFrame.new(currentPosition) * (shipMotion.startCFrame - shipMotion.startCFrame.Position))
end

function BossArenaMovePresentationController:_updateWaveCrashMotion(record: ActiveRecord, nowServerTime: number)
	local waveModel = record.waveModel
	local waveMotion = record.waveMotion
	if waveModel == nil or waveMotion == nil or waveModel.Parent == nil then
		return
	end

	local elapsed = math.max(0, nowServerTime - waveMotion.startedAtServerTime)
	if elapsed >= waveMotion.durationSeconds then
		self:_cleanupRecord(record)
		return
	end

	local currentPosition = waveMotion.startCFrame.Position + (waveMotion.direction * (waveMotion.speed * elapsed))
	waveModel:PivotTo(CFrame.new(currentPosition) * (waveMotion.startCFrame - waveMotion.startCFrame.Position))
end

function BossArenaMovePresentationController:_updateWaterBombMotion(record: ActiveRecord, nowServerTime: number)
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

function BossArenaMovePresentationController:_updateMagmaThrowMotion(record: ActiveRecord, nowServerTime: number)
	local projectileModel = record.projectileModel
	local projectileMotion = record.projectileMotion
	if projectileModel == nil or projectileMotion == nil or projectileModel.Parent == nil then
		return
	end

	local alpha = math.clamp(
		(nowServerTime - projectileMotion.startedAtServerTime) / math.max(0.001, projectileMotion.travelDuration),
		0,
		1
	)
	local position = projectileMotion.startPosition:Lerp(projectileMotion.impactPosition, alpha)
	local travelVector = projectileMotion.impactPosition - projectileMotion.startPosition
	if travelVector.Magnitude > 0.001 then
		projectileModel:PivotTo(CFrame.lookAt(position, position + travelVector.Unit))
	else
		projectileModel:PivotTo(CFrame.new(position))
	end
end

function BossArenaMovePresentationController:_updateBubbleBlastProjectiles(record: ActiveRecord, nowServerTime: number)
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
		local position = motion.startPosition:Lerp(motion.impactPosition, alpha)
		projectileModel:PivotTo(CFrame.new(position))
	end
end

function BossArenaMovePresentationController:_updateMissileBarrageProjectiles(record: ActiveRecord, nowServerTime: number)
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
		local position = resolveQuadraticBezierPosition(
			motion.startPosition,
			motion.controlPosition,
			motion.impactPosition,
			alpha
		)
		local lookAheadAlpha = math.clamp(alpha + 0.03, 0, 1)
		local lookAheadPosition = resolveQuadraticBezierPosition(
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

function BossArenaMovePresentationController:_updateActiveRecords()
	self:_cleanupStaleRecords()

	local nowServerTime = Workspace:GetServerTimeNow()
	for _, record in pairs(self._recordsByCastId) do
		if record.moduleId == PROMETHEUS_SLASH_MODULE_ID then
			self:_updatePrometheusSlashMotion(record, nowServerTime)
		elseif record.moduleId == SQUID_CALL_MODULE_ID then
			self:_updateSquidCallMotion(record, nowServerTime)
		elseif record.moduleId == SHIP_CALL_MODULE_ID then
			self:_updateShipCallMotion(record, nowServerTime)
		elseif record.moduleId == WAVE_CRASH_MODULE_ID then
			self:_updateWaveCrashMotion(record, nowServerTime)
		elseif record.moduleId == WATER_BOMB_MODULE_ID then
			self:_updateWaterBombMotion(record, nowServerTime)
		elseif record.moduleId == BUBBLE_BLAST_MODULE_ID then
			self:_updateBubbleBlastProjectiles(record, nowServerTime)
		elseif record.moduleId == MAGMA_THROW_MODULE_ID then
			self:_updateMagmaThrowMotion(record, nowServerTime)
		elseif record.moduleId == DESTROYER_MISSILE_BARRAGE_MODULE_ID then
			self:_updateMissileBarrageProjectiles(record, nowServerTime)
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

function BossArenaMovePresentationController:_startSquidCall(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local bossLeftHand = resolveBossLeftHandPart(bossModel)
	if bossLeftHand == nil then
		warnWithPrefix("Squid Call presentation could not resolve the live boss LeftHand.")
		self:_cleanupRecord(record)
		return
	end

	local leftHandSource = resolveBossVfxModel(
		CAPTAIN_SQUID_VFX_FOLDER_NAME,
		CAPTAIN_SQUID_SQUID_CALL_VFX_NAME,
		SQUID_CALL_LEFT_HAND_MODEL_NAME
	)
	if leftHandSource == nil then
		warnWithPrefix("Squid Call left-hand VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local castFolder = self:_ensureCastFolder(record)
	local leftHandModel = leftHandSource:Clone()
	local scaleMultiplier = math.max(0.1, tonumber(event.payload and event.payload.scaleMultiplier) or 1)
	leftHandModel:ScaleTo(scaleMultiplier)
	prepareAttachedEffectModel(leftHandModel)
	scaleAttachedSounds(leftHandModel, scaleMultiplier)
	leftHandModel.Parent = castFolder
	record.leftHandModel = leftHandModel

	if not attachEffectModel(leftHandModel, bossLeftHand) then
		warnWithPrefix("Squid Call left-hand VFX model is missing BasePart configuration.")
		self:_cleanupRecord(record)
		return
	end

	playAllSounds(leftHandModel)
	emitEffectInstance(leftHandModel, SQUID_CALL_LEFT_HAND_LIFETIME_SECONDS)
end

function BossArenaMovePresentationController:_summonSquidCall(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	local bossRootPart = resolveBossRootPart(bossModel)
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil then
		self:_cleanupRecord(record)
		return
	end

	local cannonSource = resolveBossVfxModel(
		CAPTAIN_SQUID_VFX_FOLDER_NAME,
		CAPTAIN_SQUID_SQUID_CALL_VFX_NAME,
		SQUID_CALL_CANNON_MODEL_NAME
	)
	if cannonSource == nil then
		warnWithPrefix("Squid Call cannon VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local payload = event.payload
	local scaleMultiplier = math.max(0.1, tonumber(payload and payload.scaleMultiplier) or 1)
	local aimDuration = math.max(0.05, tonumber(payload and payload.aimDuration) or 2)
	local targetUserId = tonumber(payload and payload.targetUserId)
	local castFolder = self:_ensureCastFolder(record)
	local cannonModel = cannonSource:Clone()
	cannonModel:ScaleTo(scaleMultiplier)
	prepareMovingEffectModel(cannonModel)

	local cannonMiddle = cannonModel:FindFirstChild(SQUID_CALL_CANNON_MIDDLE_NAME, true)
	if not (cannonMiddle and cannonMiddle:IsA("BasePart")) then
		warnWithPrefix("Squid Call cannon VFX model is missing the Middle part.")
		self:_cleanupRecord(record)
		return
	end

	local cannonMuzzleAttachment = cannonMiddle:FindFirstChild(SQUID_CALL_CANNON_MUZZLE_ATTACHMENT_NAME)
	if not (cannonMuzzleAttachment and cannonMuzzleAttachment:IsA("Attachment")) then
		warnWithPrefix("Squid Call cannon VFX model is missing Middle.CannonBall attachment.")
		self:_cleanupRecord(record)
		return
	end

	local initialBaseCFrame = resolveCannonBaseCFrame(bossRootPart.Position, nil, bossRootPart.CFrame.LookVector)
	cannonModel:PivotTo(initialBaseCFrame)
	local middleLocalCFrame = cannonModel:GetPivot():ToObjectSpace(cannonMiddle.CFrame)

	record.cannonModel = cannonModel
	record.cannonMiddle = cannonMiddle
	record.cannonMuzzleAttachment = cannonMuzzleAttachment
	record.rootModel = cannonModel
	record.squidCallAimData = {
		startedAtServerTime = if typeof(event.serverTime) == "number" then event.serverTime else Workspace:GetServerTimeNow(),
		duration = aimDuration,
		targetUserId = targetUserId,
		initialBaseCFrame = initialBaseCFrame,
		middleLocalCFrame = middleLocalCFrame,
		lastKnownTargetPosition = nil,
	}

	local targetRootPart = resolvePlayerRootPartByUserId(targetUserId)
	if targetRootPart then
		record.squidCallAimData.lastKnownTargetPosition = targetRootPart.Position
	end

	cannonModel.Parent = castFolder
	self:_applySquidCallCannonPose(record, record.squidCallAimData.lastKnownTargetPosition, 0)
end

function BossArenaMovePresentationController:_fireSquidCall(record: ActiveRecord, event: PresentationEvent)
	local castFolder = record.castFolder
	if castFolder == nil or castFolder.Parent == nil then
		return
	end

	local payload = event.payload
	if typeof(payload) ~= "table" then
		return
	end

	local startPosition = payload.startPosition
	local impactPosition = payload.impactPosition
	local travelDuration = tonumber(payload.travelDuration)
	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	if typeof(startPosition) ~= "Vector3" or typeof(impactPosition) ~= "Vector3" or travelDuration == nil then
		return
	end

	local storedAimData = record.squidCallAimData
	record.squidCallAimData = nil
	if record.cannonModel and record.cannonMiddle then
		local bossRootPart = resolveBossRootPart(record.bossModel)
		if bossRootPart then
			local baseCFrame = resolveCannonBaseCFrame(
				bossRootPart.Position,
				impactPosition,
				record.cannonModel:GetPivot().RightVector
			)
			record.cannonModel:PivotTo(baseCFrame)
			local middleLocalCFrame = if storedAimData then storedAimData.middleLocalCFrame else baseCFrame:ToObjectSpace(record.cannonMiddle.CFrame)
			local middleBaseCFrame = baseCFrame * middleLocalCFrame
			record.cannonMiddle.CFrame = middleBaseCFrame * CFrame.Angles(resolveSquidCallPitch(middleBaseCFrame, impactPosition), 0, 0)
		end
	end

	local cannonMuzzleAttachment = record.cannonMuzzleAttachment
	if cannonMuzzleAttachment then
		local muzzleSound = cannonMuzzleAttachment:FindFirstChild("Cannon Fire")
		playSound(if muzzleSound and muzzleSound:IsA("Sound") then muzzleSound else nil)
		emitVisuals(collectEmittableVisuals(cannonMuzzleAttachment))
	end

	local projectileSource = resolveBossVfxModel(
		CAPTAIN_SQUID_VFX_FOLDER_NAME,
		CAPTAIN_SQUID_SQUID_CALL_VFX_NAME,
		SQUID_CALL_CANNONBALL_MODEL_NAME
	)
	if projectileSource == nil then
		warnWithPrefix("Squid Call cannonball VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		return
	end

	local projectileModel = projectileSource:Clone()
	projectileModel:ScaleTo(scaleMultiplier)
	prepareMovingEffectModel(projectileModel)
	if resolveEffectModelPrimaryPart(projectileModel) == nil then
		warnWithPrefix("Squid Call cannonball VFX model is missing a BasePart for motion.")
		return
	end

	projectileModel.Parent = castFolder
	projectileModel:PivotTo(CFrame.new(startPosition))
	record.projectileModel = projectileModel
	record.projectileMotion = {
		startPosition = startPosition,
		impactPosition = impactPosition,
		travelDuration = math.max(0.001, travelDuration),
		startedAtServerTime = if typeof(event.serverTime) == "number" then event.serverTime else Workspace:GetServerTimeNow(),
	}

	local flyAttachment = projectileModel:FindFirstChild(SQUID_CALL_PROJECTILE_FLY_ATTACHMENT_NAME, true)
	if flyAttachment then
		emitVisuals(collectEmittableVisuals(flyAttachment))
	end
end

function BossArenaMovePresentationController:_impactSquidCall(record: ActiveRecord, event: PresentationEvent)
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

	local impactSource = nil
	if record.projectileModel and record.projectileModel.Parent then
		impactSource = record.projectileModel:FindFirstChild(SQUID_CALL_PROJECTILE_IMPACT_PART_NAME, true)
	end

	if impactSource and impactSource:IsA("BasePart") then
		local impactPart = impactSource:Clone()
		prepareMovingEffectPart(impactPart)
		impactPart.CFrame = CFrame.new(impactPosition)
		impactPart.Parent = self:_ensureVisualFolder()
		playAllSounds(impactPart)
		emitEffectInstance(impactPart, SQUID_CALL_IMPACT_LIFETIME_SECONDS)
	end

	self:_cleanupRecord(record)
end

function BossArenaMovePresentationController:_shipShipCall(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	local bossLeftHand = resolveBossLeftHandPart(bossModel)
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

	local leftHandSource = resolveBossVfxModel(
		CAPTAIN_SQUID_VFX_FOLDER_NAME,
		CAPTAIN_SQUID_SHIP_CALL_VFX_NAME,
		SHIP_CALL_LEFT_HAND_MODEL_NAME
	)
	local shipSource = resolveBossVfxModel(
		CAPTAIN_SQUID_VFX_FOLDER_NAME,
		CAPTAIN_SQUID_SHIP_CALL_VFX_NAME,
		SHIP_CALL_SHIP_MODEL_NAME
	)
	if leftHandSource == nil or shipSource == nil then
		warnWithPrefix("Ship Call VFX models are missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local castFolder = self:_ensureCastFolder(record)
	local leftHandModel = leftHandSource:Clone()
	local shipModel = shipSource:Clone()
	leftHandModel:ScaleTo(scaleMultiplier)
	shipModel:ScaleTo(scaleMultiplier)
	prepareAttachedEffectModel(leftHandModel)
	prepareMovingEffectModel(shipModel)
	scaleAttachedSounds(leftHandModel, scaleMultiplier)
	scaleAttachedSounds(shipModel, scaleMultiplier)

	if resolveEffectModelPrimaryPart(leftHandModel) == nil or resolveEffectModelPrimaryPart(shipModel) == nil then
		warnWithPrefix("Ship Call VFX models are missing BasePart configuration.")
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
		startedAtServerTime = if typeof(event.serverTime) == "number" then event.serverTime else Workspace:GetServerTimeNow(),
	}

	if not attachEffectModel(leftHandModel, bossLeftHand) then
		warnWithPrefix("Ship Call left-hand VFX model is missing BasePart configuration.")
		self:_cleanupRecord(record)
		return
	end

	shipModel:PivotTo(startCFrame)
	enableParticleEmitters(shipModel)
	playAllSounds(leftHandModel)
	playAllSounds(shipModel)
	emitVisuals(collectEmittableVisuals(leftHandModel))
	emitVisuals(collectEmittableVisuals(shipModel))
	self:_updateShipCallMotion(record, Workspace:GetServerTimeNow())
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
	local travelDuration = tonumber(payload.travelDuration)
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
		travelDistance = travelDistance,
		travelDuration = travelDuration,
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

function BossArenaMovePresentationController:_startWaveCrash(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local bossLeftHand = resolveBossLeftHandPart(bossModel)
	local bossRightHand = resolveBossRightHandPart(bossModel)
	if bossLeftHand == nil or bossRightHand == nil then
		warnWithPrefix("Wave Crash presentation could not resolve the live boss LeftHand/RightHand.")
		self:_cleanupRecord(record)
		return
	end

	local leftHandSource = resolveBossVfxModel(
		MERFIN_THE_GREAT_VFX_FOLDER_NAME,
		WAVE_CRASH_VFX_NAME,
		WAVE_CRASH_LEFT_HAND_MODEL_NAME
	)
	local rightHandSource = resolveBossVfxModel(
		MERFIN_THE_GREAT_VFX_FOLDER_NAME,
		WAVE_CRASH_VFX_NAME,
		WAVE_CRASH_RIGHT_HAND_MODEL_NAME
	)
	if leftHandSource == nil or rightHandSource == nil then
		warnWithPrefix("Wave Crash hand VFX models are missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local payload = event.payload
	local scaleMultiplier = math.max(0.1, tonumber(payload and payload.scaleMultiplier) or 1)
	local castFolder = self:_ensureCastFolder(record)
	local leftHandModel = leftHandSource:Clone()
	local rightHandModel = rightHandSource:Clone()
	leftHandModel:ScaleTo(scaleMultiplier)
	rightHandModel:ScaleTo(scaleMultiplier)
	prepareAttachedEffectModel(leftHandModel)
	prepareAttachedEffectModel(rightHandModel)
	enableVfxDescendants(leftHandModel)
	enableVfxDescendants(rightHandModel)
	scaleAttachedSounds(leftHandModel, scaleMultiplier)
	scaleAttachedSounds(rightHandModel, scaleMultiplier)

	leftHandModel.Parent = castFolder
	rightHandModel.Parent = castFolder
	record.leftHandModel = leftHandModel
	record.rightHandModel = rightHandModel

	if not attachEffectModel(leftHandModel, bossLeftHand) or not attachEffectModel(rightHandModel, bossRightHand) then
		warnWithPrefix("Wave Crash hand VFX models are missing BasePart configuration.")
		self:_cleanupRecord(record)
		return
	end

	playAllSounds(leftHandModel)
	playAllSounds(rightHandModel)
	emitVisuals(collectEmittableVisuals(leftHandModel))
	emitVisuals(collectEmittableVisuals(rightHandModel))
end

function BossArenaMovePresentationController:_sendWaveCrash(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" then
		return
	end

	local startCFrame = payload.startCFrame
	local direction = payload.direction
	local speed = tonumber(payload.speed)
	local durationSeconds = tonumber(payload.durationSeconds)
	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	if typeof(startCFrame) ~= "CFrame"
		or typeof(direction) ~= "Vector3"
		or direction.Magnitude <= 0.001
		or speed == nil
		or durationSeconds == nil then
		return
	end

	local waveSource = resolveBossVfxModel(
		MERFIN_THE_GREAT_VFX_FOLDER_NAME,
		WAVE_CRASH_VFX_NAME,
		WAVE_CRASH_WAVE_MODEL_NAME
	)
	if waveSource == nil then
		warnWithPrefix("Wave Crash wave VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local castFolder = self:_ensureCastFolder(record)
	local waveModel = waveSource:Clone()
	waveModel:ScaleTo(scaleMultiplier)
	prepareMovingEffectModel(waveModel)
	enableVfxDescendants(waveModel)
	if resolveEffectModelPrimaryPart(waveModel) == nil then
		warnWithPrefix("Wave Crash wave VFX model is missing a BasePart for motion.")
		self:_cleanupRecord(record)
		return
	end

	waveModel.Parent = castFolder
	waveModel:PivotTo(startCFrame)
	record.waveModel = waveModel
	record.waveMotion = {
		startCFrame = startCFrame,
		direction = direction.Unit,
		speed = math.max(0, speed),
		durationSeconds = math.max(0.05, durationSeconds),
		startedAtServerTime = if typeof(event.serverTime) == "number" then event.serverTime else Workspace:GetServerTimeNow(),
	}

	playAllSounds(waveModel)
	emitVisuals(collectEmittableVisuals(waveModel))
	self:_updateWaveCrashMotion(record, Workspace:GetServerTimeNow())
end

function BossArenaMovePresentationController:_startWaterBomb(record: ActiveRecord, event: PresentationEvent)
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

	local floorSource = resolveBossVfxModel(
		MERFIN_THE_GREAT_VFX_FOLDER_NAME,
		WATER_BOMB_VFX_NAME,
		WATER_BOMB_FLOOR_MODEL_NAME
	)
	local ballSource = resolveBossVfxModel(
		MERFIN_THE_GREAT_VFX_FOLDER_NAME,
		WATER_BOMB_VFX_NAME,
		WATER_BOMB_BALL_MODEL_NAME
	)
	if floorSource == nil or ballSource == nil then
		warnWithPrefix("Water Bomb floor/ball VFX models are missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local castFolder = self:_ensureCastFolder(record)
	local floorModel = floorSource:Clone()
	local ballModel = ballSource:Clone()
	floorModel:ScaleTo(scaleMultiplier)
	ballModel:ScaleTo(math.max(0.01, ballStartScale))
	prepareMovingEffectModel(floorModel)
	prepareMovingEffectModel(ballModel)
	enableVfxDescendants(ballModel)
	scaleAttachedSounds(floorModel, scaleMultiplier)
	scaleAttachedSounds(ballModel, math.max(0.1, ballEndScale))

	floorModel.Parent = castFolder
	ballModel.Parent = castFolder
	floorModel:PivotTo(CFrame.new(floorPosition))
	ballModel:PivotTo(CFrame.new(chargeStartPosition))

	playAllSounds(floorModel)
	playAllSounds(ballModel)
	emitEffectInstance(floorModel, WATER_BOMB_FLOOR_LIFETIME_SECONDS)

	record.rootModel = floorModel
	record.projectileModel = ballModel
	record.waterBombChargeData = {
		startPosition = chargeStartPosition,
		endPosition = chargeEndPosition,
		startScale = math.max(0.01, ballStartScale),
		endScale = math.max(0.01, ballEndScale),
		startedAtServerTime = if typeof(event.serverTime) == "number" then event.serverTime else Workspace:GetServerTimeNow(),
		duration = math.max(0.05, chargeDurationSeconds),
	}
	self:_updateWaterBombMotion(record, Workspace:GetServerTimeNow())
end

function BossArenaMovePresentationController:_throwWaterBomb(record: ActiveRecord, event: PresentationEvent)
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
		local ballSource = resolveBossVfxModel(
			MERFIN_THE_GREAT_VFX_FOLDER_NAME,
			WATER_BOMB_VFX_NAME,
			WATER_BOMB_BALL_MODEL_NAME
		)
		if ballSource == nil then
			warnWithPrefix("Water Bomb ball VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
			self:_cleanupRecord(record)
			return
		end

		ballModel = ballSource:Clone()
		prepareMovingEffectModel(ballModel)
		enableVfxDescendants(ballModel)
		ballModel.Parent = self:_ensureCastFolder(record)
		record.projectileModel = ballModel
		playAllSounds(ballModel)
	end

	record.waterBombChargeData = nil
	record.projectileMotion = {
		startPosition = startPosition,
		impactPosition = impactPosition,
		travelDuration = math.max(0.001, travelDuration),
		startedAtServerTime = if typeof(event.serverTime) == "number" then event.serverTime else Workspace:GetServerTimeNow(),
	}

	ballModel:ScaleTo(ballScale)
	ballModel:PivotTo(CFrame.new(startPosition))
	self:_updateWaterBombMotion(record, Workspace:GetServerTimeNow())
end

function BossArenaMovePresentationController:_impactWaterBomb(record: ActiveRecord, event: PresentationEvent)
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

	local explosionSource = resolveBossVfxModel(
		MERFIN_THE_GREAT_VFX_FOLDER_NAME,
		WATER_BOMB_VFX_NAME,
		WATER_BOMB_EXPLOSION_MODEL_NAME
	)
	if explosionSource == nil then
		warnWithPrefix("Water Bomb explosion VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
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
	prepareMovingEffectModel(explosionModel)
	explosionModel:PivotTo(CFrame.new(impactPosition))
	explosionModel.Parent = self:_ensureVisualFolder()
	playAllSounds(explosionModel)
	emitEffectInstance(explosionModel, WATER_BOMB_EXPLOSION_LIFETIME_SECONDS)

	self:_cleanupRecord(record)
end

function BossArenaMovePresentationController:_startBubbleBlast(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local bossLeftHand = resolveBossLeftHandPart(bossModel)
	local bossRootPart = resolveBossRootPart(bossModel)
	if bossLeftHand == nil or bossRootPart == nil then
		warnWithPrefix("Bubble Blast presentation could not resolve the live boss LeftHand/RootPart.")
		self:_cleanupRecord(record)
		return
	end

	local leftHandSource = resolveBossVfxModel(
		MERFIN_THE_GREAT_VFX_FOLDER_NAME,
		BUBBLE_BLAST_VFX_NAME,
		BUBBLE_BLAST_LEFT_HAND_MODEL_NAME
	)
	local rootPartSource = resolveBossVfxModel(
		MERFIN_THE_GREAT_VFX_FOLDER_NAME,
		BUBBLE_BLAST_VFX_NAME,
		BUBBLE_BLAST_ROOT_PART_MODEL_NAME
	)
	if leftHandSource == nil or rootPartSource == nil then
		warnWithPrefix("Bubble Blast LeftHand/RootPart VFX models are missing from ReplicatedStorage.GameAssets.VFX.")
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
	prepareAttachedEffectModel(leftHandModel)
	prepareAttachedEffectModel(rootPartModel)
	enableVfxDescendants(leftHandModel)
	enableVfxDescendants(rootPartModel)
	scaleAttachedSounds(leftHandModel, scaleMultiplier)
	scaleAttachedSounds(rootPartModel, scaleMultiplier)

	leftHandModel.Parent = castFolder
	rootPartModel.Parent = castFolder
	record.leftHandModel = leftHandModel
	record.rootModel = rootPartModel

	if not attachEffectModel(leftHandModel, bossLeftHand) or not attachEffectModel(rootPartModel, bossRootPart) then
		warnWithPrefix("Bubble Blast attached VFX models are missing BasePart configuration.")
		self:_cleanupRecord(record)
		return
	end

	playAllSounds(leftHandModel)
	playAllSounds(rootPartModel)
	emitEffectInstance(leftHandModel)
	emitEffectInstance(rootPartModel)
end

function BossArenaMovePresentationController:_launchBubbleBlastProjectiles(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.projectiles) ~= "table" then
		return
	end

	local projectileSource = resolveBossVfxModel(
		MERFIN_THE_GREAT_VFX_FOLDER_NAME,
		BUBBLE_BLAST_VFX_NAME,
		BUBBLE_BLAST_PROJECTILE_MODEL_NAME
	)
	if projectileSource == nil then
		warnWithPrefix("Bubble Blast projectile VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local castFolder = self:_ensureCastFolder(record)
	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	local startedAtServerTime = if typeof(event.serverTime) == "number" then event.serverTime else Workspace:GetServerTimeNow()
	record.bubbleBlastProjectileModels = {}
	record.bubbleBlastProjectileMotions = {}

	for _, projectileData in ipairs(payload.projectiles) do
		if typeof(projectileData) ~= "table" then
			continue
		end

		local index = math.floor(tonumber(projectileData.index) or 0)
		local startPosition = projectileData.startPosition
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
		prepareMovingEffectModel(projectileModel)
		enableVfxDescendants(projectileModel)
		scaleAttachedSounds(projectileModel, scaleMultiplier)
		if resolveEffectModelPrimaryPart(projectileModel) == nil then
			projectileModel:Destroy()
			warnWithPrefix("Bubble Blast projectile VFX model is missing a BasePart for motion.")
			continue
		end

		projectileModel.Parent = castFolder
		projectileModel:PivotTo(CFrame.new(startPosition))
		enableVfxDescendants(projectileModel)
		playAllSounds(projectileModel)

		record.bubbleBlastProjectileModels[index] = projectileModel
		record.bubbleBlastProjectileMotions[index] = {
			startPosition = startPosition,
			impactPosition = impactPosition,
			travelDuration = math.max(0.001, travelDuration),
			startedAtServerTime = startedAtServerTime,
		}
	end

	self:_updateBubbleBlastProjectiles(record, Workspace:GetServerTimeNow())
end

function BossArenaMovePresentationController:_impactBubbleBlast(record: ActiveRecord, event: PresentationEvent)
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

	local hitSource = resolveBossVfxModel(
		MERFIN_THE_GREAT_VFX_FOLDER_NAME,
		BUBBLE_BLAST_VFX_NAME,
		BUBBLE_BLAST_HIT_MODEL_NAME
	)
	if hitSource == nil then
		warnWithPrefix("Bubble Blast hit VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		return
	end

	local hitModel = hitSource:Clone()
	hitModel:ScaleTo(scaleMultiplier)
	prepareMovingEffectModel(hitModel)
	hitModel:PivotTo(CFrame.new(impactPosition))
	hitModel.Parent = self:_ensureVisualFolder()
	playAllSounds(hitModel)
	emitEffectInstance(hitModel, BUBBLE_BLAST_HIT_LIFETIME_SECONDS)
end

function BossArenaMovePresentationController:_startMagmaThrow(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local bossLeftHand = resolveBossLeftHandPart(bossModel)
	if bossLeftHand == nil then
		warnWithPrefix("Magma Throw presentation could not resolve the live boss LeftHand.")
		self:_cleanupRecord(record)
		return
	end

	local leftHandSource = resolveBossVfxModel(
		MAGMA_FIEND_VFX_FOLDER_NAME,
		MAGMA_THROW_VFX_NAME,
		MAGMA_THROW_LEFT_HAND_MODEL_NAME
	)
	if leftHandSource == nil then
		warnWithPrefix("Magma Throw left-hand VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local castFolder = self:_ensureCastFolder(record)
	local scaleMultiplier = math.max(0.1, tonumber(event.payload and event.payload.scaleMultiplier) or 1)
	local leftHandModel = leftHandSource:Clone()
	leftHandModel:ScaleTo(scaleMultiplier)
	prepareAttachedEffectModel(leftHandModel)
	scaleAttachedSounds(leftHandModel, scaleMultiplier)
	leftHandModel.Parent = castFolder
	record.leftHandModel = leftHandModel

	if not attachEffectModel(leftHandModel, bossLeftHand) then
		warnWithPrefix("Magma Throw left-hand VFX model is missing BasePart configuration.")
		self:_cleanupRecord(record)
	end
end

function BossArenaMovePresentationController:_emitMagmaThrowRoot(record: ActiveRecord, event: PresentationEvent)
	local bossRootPart = resolveBossRootPart(event.bossModel)
	if bossRootPart == nil then
		return
	end

	local rootSource = resolveBossVfxModel(
		MAGMA_FIEND_VFX_FOLDER_NAME,
		MAGMA_THROW_VFX_NAME,
		MAGMA_THROW_ROOT_PART_MODEL_NAME
	)
	if rootSource == nil then
		warnWithPrefix("Magma Throw RootPart VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		return
	end

	local payload = event.payload
	local scaleMultiplier = math.max(0.1, tonumber(payload and payload.scaleMultiplier) or 1)
	local rootModel = rootSource:Clone()
	rootModel:ScaleTo(scaleMultiplier)
	prepareMovingEffectModel(rootModel)
	rootModel:PivotTo(bossRootPart.CFrame)
	rootModel.Parent = self:_ensureCastFolder(record)
	record.rootModel = rootModel

	playAllSounds(rootModel)
	emitEffectInstance(rootModel, MAGMA_THROW_VFX_LIFETIME_SECONDS)
	destroyAfter(rootModel, MAGMA_THROW_VFX_LIFETIME_SECONDS)
end

function BossArenaMovePresentationController:_throwMagmaThrow(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" then
		return
	end

	local startPosition = payload.startPosition
	local impactPosition = payload.impactPosition
	local travelDuration = tonumber(payload.travelDuration)
	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	if typeof(startPosition) ~= "Vector3" or typeof(impactPosition) ~= "Vector3" or travelDuration == nil then
		return
	end

	local castFolder = self:_ensureCastFolder(record)
	local projectileSource = resolveBossVfxModel(
		MAGMA_FIEND_VFX_FOLDER_NAME,
		MAGMA_THROW_VFX_NAME,
		MAGMA_THROW_PROJECTILE_MODEL_NAME
	)
	if projectileSource == nil then
		warnWithPrefix("Magma Throw projectile VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local visualStartPosition = startPosition
	local leftHandModel = record.leftHandModel
	if leftHandModel and leftHandModel.Parent then
		visualStartPosition = leftHandModel:GetPivot().Position
		playAllSounds(leftHandModel)
		emitEffectInstance(leftHandModel, MAGMA_THROW_VFX_LIFETIME_SECONDS)
		setBasePartTransparency(leftHandModel, 1)
		destroyAfter(leftHandModel, MAGMA_THROW_VFX_LIFETIME_SECONDS)
	end

	self:_emitMagmaThrowRoot(record, event)

	local projectileModel = projectileSource:Clone()
	projectileModel:ScaleTo(scaleMultiplier)
	prepareMovingEffectModel(projectileModel)
	enableVfxDescendants(projectileModel)
	scaleAttachedSounds(projectileModel, scaleMultiplier)
	if resolveEffectModelPrimaryPart(projectileModel) == nil then
		projectileModel:Destroy()
		warnWithPrefix("Magma Throw projectile VFX model is missing a BasePart for motion.")
		self:_cleanupRecord(record)
		return
	end

	projectileModel.Parent = castFolder
	projectileModel:PivotTo(CFrame.new(visualStartPosition))
	record.projectileModel = projectileModel
	record.projectileMotion = {
		startPosition = visualStartPosition,
		impactPosition = impactPosition,
		travelDuration = math.max(0.001, travelDuration),
		startedAtServerTime = if typeof(event.serverTime) == "number" then event.serverTime else Workspace:GetServerTimeNow(),
	}

	playAllSounds(projectileModel)
	self:_updateMagmaThrowMotion(record, Workspace:GetServerTimeNow())
end

function BossArenaMovePresentationController:_impactMagmaThrow(record: ActiveRecord, event: PresentationEvent)
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

	if record.projectileModel and record.projectileModel.Parent then
		record.projectileModel:Destroy()
	end
	record.projectileModel = nil
	record.projectileMotion = nil

	local explosionSource = resolveBossVfxModel(
		MAGMA_FIEND_VFX_FOLDER_NAME,
		MAGMA_THROW_VFX_NAME,
		MAGMA_THROW_EXPLOSION_MODEL_NAME
	)
	if explosionSource == nil then
		warnWithPrefix("Magma Throw explosion VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	local explosionModel = explosionSource:Clone()
	explosionModel:ScaleTo(scaleMultiplier)
	prepareMovingEffectModel(explosionModel)
	explosionModel:PivotTo(CFrame.new(impactPosition))
	explosionModel.Parent = self:_ensureVisualFolder()

	playAllSounds(explosionModel)
	emitEffectInstance(explosionModel, MAGMA_THROW_VFX_LIFETIME_SECONDS)
	destroyAfter(explosionModel, MAGMA_THROW_VFX_LIFETIME_SECONDS)
	self:_cleanupRecord(record)
end

function BossArenaMovePresentationController:_stompMagmaStomp(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.impactCFrame) ~= "CFrame" then
		self:_cleanupRecord(record)
		return
	end

	local floorSource = resolveBossVfxModel(
		MAGMA_FIEND_VFX_FOLDER_NAME,
		MAGMA_STOMP_VFX_NAME,
		MAGMA_STOMP_FLOOR_MODEL_NAME
	)
	if floorSource == nil then
		warnWithPrefix("Magma Stomp floor VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	local floorModel = floorSource:Clone()
	floorModel:ScaleTo(scaleMultiplier)
	prepareMovingEffectModel(floorModel)
	floorModel:PivotTo(payload.impactCFrame)
	floorModel.Parent = self:_ensureVisualFolder()

	playAllSounds(floorModel)
	emitEffectInstance(floorModel, MAGMA_STOMP_VFX_LIFETIME_SECONDS)
	destroyAfter(floorModel, MAGMA_STOMP_VFX_LIFETIME_SECONDS)
end

function BossArenaMovePresentationController:_clearMagmaEruptionWarnings(record: ActiveRecord)
	if record.eruptionWarningHandles == nil then
		return
	end

	for _, warningHandle in pairs(record.eruptionWarningHandles) do
		warningHandle:Destroy()
	end

	record.eruptionWarningHandles = nil
end

function BossArenaMovePresentationController:_startMagmaEruption(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local bossLeftHand = resolveBossLeftHandPart(bossModel)
	local bossRightHand = resolveBossRightHandPart(bossModel)
	if bossLeftHand == nil or bossRightHand == nil then
		warnWithPrefix("Magma Eruption presentation could not resolve the live boss LeftHand/RightHand.")
		self:_cleanupRecord(record)
		return
	end

	local leftHandSource = resolveBossVfxModel(
		MAGMA_FIEND_VFX_FOLDER_NAME,
		MAGMA_ERUPTION_VFX_NAME,
		MAGMA_ERUPTION_LEFT_HAND_MODEL_NAME
	)
	local rightHandSource = resolveBossVfxModel(
		MAGMA_FIEND_VFX_FOLDER_NAME,
		MAGMA_ERUPTION_VFX_NAME,
		MAGMA_ERUPTION_RIGHT_HAND_MODEL_NAME
	)
	if leftHandSource == nil or rightHandSource == nil then
		warnWithPrefix("Magma Eruption hand VFX models are missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local castFolder = self:_ensureCastFolder(record)
	local scaleMultiplier = math.max(0.1, tonumber(event.payload and event.payload.scaleMultiplier) or 1)
	local leftHandModel = leftHandSource:Clone()
	local rightHandModel = rightHandSource:Clone()
	leftHandModel:ScaleTo(scaleMultiplier)
	rightHandModel:ScaleTo(scaleMultiplier)
	prepareAttachedEffectModel(leftHandModel)
	prepareAttachedEffectModel(rightHandModel)
	scaleAttachedSounds(leftHandModel, scaleMultiplier)
	scaleAttachedSounds(rightHandModel, scaleMultiplier)

	leftHandModel.Parent = castFolder
	rightHandModel.Parent = castFolder
	record.leftHandModel = leftHandModel
	record.rightHandModel = rightHandModel

	if not attachEffectModel(leftHandModel, bossLeftHand) or not attachEffectModel(rightHandModel, bossRightHand) then
		warnWithPrefix("Magma Eruption hand VFX models are missing BasePart configuration.")
		self:_cleanupRecord(record)
		return
	end

	playAllSounds(leftHandModel)
	playAllSounds(rightHandModel)
	emitVisuals(collectEmittableVisuals(leftHandModel))
	emitVisuals(collectEmittableVisuals(rightHandModel))
end

function BossArenaMovePresentationController:_warnMagmaEruption(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.points) ~= "table" then
		return
	end

	self:_clearMagmaEruptionWarnings(record)
	local castFolder = self:_ensureCastFolder(record)
	local warningSeconds = math.max(0.05, tonumber(payload.warningSeconds) or 1)
	record.eruptionWarningHandles = {}

	for _, pointData in ipairs(payload.points) do
		if typeof(pointData) ~= "table" then
			continue
		end

		local floorCFrame = pointData.floorCFrame
		local footprintSize = pointData.footprintSize
		if typeof(floorCFrame) ~= "CFrame" or typeof(footprintSize) ~= "Vector3" then
			continue
		end

		local index = math.max(1, math.floor(tonumber(pointData.index) or (#record.eruptionWarningHandles + 1)))
		record.eruptionWarningHandles[index] = Indication.CreateCircle({
			parent = castFolder,
			cframe = floorCFrame,
			diameter = math.max(footprintSize.X, footprintSize.Z),
			duration = warningSeconds,
		})
	end
end

function BossArenaMovePresentationController:_eruptMagmaEruption(record: ActiveRecord, event: PresentationEvent)
	self:_clearMagmaEruptionWarnings(record)
	self:_shakeImpact()

	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.points) ~= "table" then
		self:_cleanupRecord(record)
		return
	end

	local floorSource = resolveBossVfxModel(
		MAGMA_FIEND_VFX_FOLDER_NAME,
		MAGMA_ERUPTION_VFX_NAME,
		MAGMA_ERUPTION_FLOOR_MODEL_NAME
	)
	if floorSource == nil then
		warnWithPrefix("Magma Eruption floor VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	for _, pointData in ipairs(payload.points) do
		if typeof(pointData) ~= "table" or typeof(pointData.floorCFrame) ~= "CFrame" then
			continue
		end

		local floorModel = floorSource:Clone()
		prepareMovingEffectModel(floorModel)
		floorModel:PivotTo(pointData.floorCFrame)
		floorModel.Parent = self:_ensureVisualFolder()

		playAllSounds(floorModel)
		emitEffectInstance(floorModel, MAGMA_ERUPTION_VFX_LIFETIME_SECONDS)
		destroyAfter(floorModel, MAGMA_ERUPTION_VFX_LIFETIME_SECONDS)
	end

	self:_cleanupRecord(record)
end

function BossArenaMovePresentationController:_chargeOinanCharge(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local bossRootPart = resolveBossRootPart(bossModel)
	if bossRootPart == nil then
		warnWithPrefix("Bull Charge presentation could not resolve the live boss RootPart.")
		self:_cleanupRecord(record)
		return
	end

	local effectSource = resolveBossVfxInstance(
		OINAN_THICKHOOF_VFX_FOLDER_NAME,
		OINAN_THICKHOOF_CHARGE_VFX_NAME,
		OINAN_THICKHOOF_CHARGE_ROOT_VFX_NAME
	)
	if effectSource == nil then
		warnWithPrefix("Bull Charge RootPart VFX instance is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local payload = event.payload
	local scaleMultiplier = math.max(0.1, tonumber(payload and payload.scaleMultiplier) or 1)
	local durationSeconds = math.max(0.1, tonumber(payload and payload.durationSeconds) or 2)
	local startCFrame = if typeof(payload) == "table" and typeof(payload.startCFrame) == "CFrame"
		then payload.startCFrame
		else bossRootPart.CFrame
	local effectInstance = effectSource:Clone()
	if effectInstance:IsA("Model") then
		effectInstance:ScaleTo(scaleMultiplier)
		prepareMovingEffectModel(effectInstance)
		effectInstance:PivotTo(startCFrame)
	elseif effectInstance:IsA("BasePart") then
		effectInstance.Size *= scaleMultiplier
		prepareMovingEffectPart(effectInstance)
		effectInstance.CFrame = startCFrame
	elseif effectInstance:IsA("PVInstance") then
		effectInstance:PivotTo(startCFrame)
	else
		warnWithPrefix("Bull Charge RootPart VFX instance cannot be pivoted.")
		effectInstance:Destroy()
		self:_cleanupRecord(record)
		return
	end

	effectInstance.Parent = self:_ensureCastFolder(record)
	playAllSounds(effectInstance)
	emitEffectInstance(effectInstance, durationSeconds + 0.5)
end

function BossArenaMovePresentationController:_emitOinanRoarVfx(
	record: ActiveRecord,
	event: PresentationEvent,
	effectModelName: string
)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local bossRootPart = resolveBossRootPart(bossModel)
	if bossRootPart == nil then
		warnWithPrefix("Bull Roar presentation could not resolve the live boss RootPart.")
		self:_cleanupRecord(record)
		return
	end

	local effectSource = resolveBossVfxModel(
		OINAN_THICKHOOF_VFX_FOLDER_NAME,
		OINAN_THICKHOOF_ROAR_VFX_NAME,
		effectModelName
	)
	if effectSource == nil then
		warnWithPrefix("Bull Roar VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local payload = event.payload
	local scaleMultiplier = math.max(0.1, tonumber(payload and payload.scaleMultiplier) or 1)
	local effectModel = effectSource:Clone()
	effectModel:ScaleTo(scaleMultiplier)
	prepareMovingEffectModel(effectModel)
	effectModel:PivotTo(bossRootPart.CFrame)
	effectModel.Parent = self:_ensureVisualFolder()
	playAllSounds(effectModel)
	emitEffectInstance(effectModel, OINAN_THICKHOOF_ROAR_VFX_LIFETIME_SECONDS)
end

function BossArenaMovePresentationController:_startOinanRoar(record: ActiveRecord, event: PresentationEvent)
	self:_emitOinanRoarVfx(record, event, OINAN_THICKHOOF_ROAR_START_VFX_NAME)
end

function BossArenaMovePresentationController:_roarOinanRoar(record: ActiveRecord, event: PresentationEvent)
	self:_shakeImpact()
	self:_emitOinanRoarVfx(record, event, OINAN_THICKHOOF_ROAR_IMPACT_VFX_NAME)
end

function BossArenaMovePresentationController:_stompOinanStomp(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.impactCFrame) ~= "CFrame" then
		self:_cleanupRecord(record)
		return
	end

	local effectSource = resolveBossVfxInstance(
		OINAN_THICKHOOF_VFX_FOLDER_NAME,
		OINAN_THICKHOOF_STOMP_VFX_NAME,
		OINAN_THICKHOOF_STOMP_FLOOR_VFX_NAME
	)
	if effectSource == nil then
		warnWithPrefix("Oinan Stomp FloorFx VFX instance is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	local effectInstance = effectSource:Clone()
	if effectInstance:IsA("Model") then
		effectInstance:ScaleTo(scaleMultiplier)
		prepareMovingEffectModel(effectInstance)
		effectInstance:PivotTo(payload.impactCFrame)
	elseif effectInstance:IsA("BasePart") then
		effectInstance.Size *= scaleMultiplier
		prepareMovingEffectPart(effectInstance)
		effectInstance.CFrame = payload.impactCFrame
	elseif effectInstance:IsA("PVInstance") then
		effectInstance:PivotTo(payload.impactCFrame)
	else
		warnWithPrefix("Oinan Stomp FloorFx VFX instance cannot be pivoted.")
		effectInstance:Destroy()
		self:_cleanupRecord(record)
		return
	end

	effectInstance.Parent = self:_ensureCastFolder(record)
	playAllSounds(effectInstance)
	emitEffectInstance(effectInstance, OINAN_THICKHOOF_STOMP_VFX_LIFETIME_SECONDS)
	self:_shakeImpact()
end

function BossArenaMovePresentationController:_clearBroccoliSproutWarnings(record: ActiveRecord)
	if record.broccoliSproutWarningHandles == nil then
		return
	end

	for _, warningHandle in pairs(record.broccoliSproutWarningHandles) do
		warningHandle:Destroy()
	end

	record.broccoliSproutWarningHandles = nil
end

function BossArenaMovePresentationController:_warnBroccoliSprout(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.points) ~= "table" then
		return
	end

	self:_clearBroccoliSproutWarnings(record)
	local castFolder = self:_ensureCastFolder(record)
	local warningSeconds = math.max(0.05, tonumber(payload.warningSeconds) or 1)
	record.broccoliSproutWarningHandles = {}

	for _, pointData in ipairs(payload.points) do
		if typeof(pointData) ~= "table" then
			continue
		end

		local floorCFrame = pointData.floorCFrame
		local footprintSize = pointData.footprintSize
		if typeof(floorCFrame) ~= "CFrame" or typeof(footprintSize) ~= "Vector3" then
			continue
		end

		local index = math.max(1, math.floor(tonumber(pointData.index) or (#record.broccoliSproutWarningHandles + 1)))
		record.broccoliSproutWarningHandles[index] = Indication.CreateCircle({
			parent = castFolder,
			cframe = floorCFrame,
			diameter = math.max(footprintSize.X, footprintSize.Z),
			duration = warningSeconds,
		})
	end
end

local function pivotBroccoliSproutEffectInstance(effectInstance: Instance, cframe: CFrame, scaleMultiplier: number): boolean
	if effectInstance:IsA("Model") then
		effectInstance:ScaleTo(scaleMultiplier)
		prepareMovingEffectModel(effectInstance)
		effectInstance:PivotTo(cframe)
		local boundingCFrame, boundingSize = effectInstance:GetBoundingBox()
		local bottomY = boundingCFrame.Position.Y - (boundingSize.Y * 0.5)
		effectInstance:PivotTo(effectInstance:GetPivot() + Vector3.new(0, cframe.Position.Y - bottomY, 0))
		return true
	end
	if effectInstance:IsA("BasePart") then
		effectInstance.Size *= scaleMultiplier
		prepareMovingEffectPart(effectInstance)
		effectInstance.CFrame = cframe
		effectInstance.CFrame = effectInstance.CFrame
			+ Vector3.new(0, cframe.Position.Y - (effectInstance.Position.Y - (effectInstance.Size.Y * 0.5)), 0)
		return true
	end
	if effectInstance:IsA("PVInstance") then
		effectInstance:PivotTo(cframe)
		return true
	end

	return false
end

function BossArenaMovePresentationController:_tweenBroccoliSproutTree(
	record: ActiveRecord,
	treeModel: Model,
	startCFrame: CFrame,
	endCFrame: CFrame,
	riseDurationSeconds: number
)
	record.broccoliSproutTweens = record.broccoliSproutTweens or {}
	record.broccoliSproutTweenConnections = record.broccoliSproutTweenConnections or {}
	record.broccoliSproutTweenValues = record.broccoliSproutTweenValues or {}

	local cframeValue = Instance.new("CFrameValue")
	cframeValue.Name = "BroccoliSproutPivot"
	cframeValue.Value = startCFrame
	cframeValue.Parent = treeModel

	treeModel:PivotTo(startCFrame)

	local connection = cframeValue:GetPropertyChangedSignal("Value"):Connect(function()
		if treeModel.Parent ~= nil then
			treeModel:PivotTo(cframeValue.Value)
		end
	end)
	local tween = TweenService:Create(
		cframeValue,
		TweenInfo.new(riseDurationSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Value = endCFrame,
		}
	)

	table.insert(record.broccoliSproutTweens, tween)
	table.insert(record.broccoliSproutTweenConnections, connection)
	table.insert(record.broccoliSproutTweenValues, cframeValue)

	tween.Completed:Connect(function()
		if connection.Connected then
			connection:Disconnect()
		end
		if cframeValue.Parent ~= nil then
			cframeValue:Destroy()
		end
	end)
	tween:Play()
end

function BossArenaMovePresentationController:_sproutBroccoliSprout(record: ActiveRecord, event: PresentationEvent)
	self:_clearBroccoliSproutWarnings(record)
	self:_shakeImpact()

	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.points) ~= "table" then
		self:_cleanupRecord(record)
		return
	end

	local floorSource = resolveBossVfxInstance(
		BROCCOLI_BRO_VFX_FOLDER_NAME,
		BROCCOLI_SPROUT_VFX_NAME,
		BROCCOLI_SPROUT_FLOOR_VFX_NAME
	)
	if floorSource == nil then
		warnWithPrefix("Broccoli Sprout floor VFX instance is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local treeSource = resolveBossVfxModel(
		BROCCOLI_BRO_VFX_FOLDER_NAME,
		BROCCOLI_SPROUT_VFX_NAME,
		BROCCOLI_SPROUT_TREE_VFX_NAME
	)
	if treeSource == nil then
		warnWithPrefix("Broccoli Sprout tree VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local castFolder = self:_ensureCastFolder(record)
	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	local riseDurationSeconds = math.max(0.05, tonumber(payload.riseDurationSeconds) or 0.45)

	for _, pointData in ipairs(payload.points) do
		if typeof(pointData) ~= "table" or typeof(pointData.floorCFrame) ~= "CFrame" then
			continue
		end

		local floorInstance = floorSource:Clone()
		if not pivotBroccoliSproutEffectInstance(floorInstance, pointData.floorCFrame, scaleMultiplier) then
			warnWithPrefix("Broccoli Sprout floor VFX instance cannot be pivoted.")
			floorInstance:Destroy()
			continue
		end
		floorInstance.Parent = self:_ensureVisualFolder()
		playAllSounds(floorInstance)
		emitEffectInstance(floorInstance, BROCCOLI_SPROUT_VFX_LIFETIME_SECONDS)
		destroyAfter(floorInstance, BROCCOLI_SPROUT_VFX_LIFETIME_SECONDS)

		local treeStartCFrame = pointData.treeStartCFrame
		local treeEndCFrame = pointData.treeEndCFrame
		if typeof(treeStartCFrame) ~= "CFrame" or typeof(treeEndCFrame) ~= "CFrame" then
			continue
		end

		local treeModel = treeSource:Clone()
		treeModel:ScaleTo(scaleMultiplier)
		prepareMovingEffectModel(treeModel)
		if resolveEffectModelPrimaryPart(treeModel) == nil then
			treeModel:Destroy()
			warnWithPrefix("Broccoli Sprout tree VFX model is missing a BasePart for tweening.")
			continue
		end

		treeModel.Parent = castFolder
		playAllSounds(treeModel)
		enableVfxDescendants(treeModel)
		emitVisuals(collectEmittableVisuals(treeModel))
		self:_tweenBroccoliSproutTree(record, treeModel, treeStartCFrame, treeEndCFrame, riseDurationSeconds)
	end
end

function BossArenaMovePresentationController:_stompBroccoliStomp(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.impactCFrame) ~= "CFrame" then
		self:_cleanupRecord(record)
		return
	end

	local effectSource = resolveBossVfxInstance(
		BROCCOLI_BRO_VFX_FOLDER_NAME,
		BROCCOLI_BRO_STOMP_VFX_NAME,
		BROCCOLI_BRO_STOMP_FLOOR_VFX_NAME
	)
	if effectSource == nil then
		warnWithPrefix("Broccoli Bro Stomp FloorFx VFX instance is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	local effectInstance = effectSource:Clone()
	if effectInstance:IsA("Model") then
		effectInstance:ScaleTo(scaleMultiplier)
		prepareMovingEffectModel(effectInstance)
		effectInstance:PivotTo(payload.impactCFrame)
	elseif effectInstance:IsA("BasePart") then
		effectInstance.Size *= scaleMultiplier
		prepareMovingEffectPart(effectInstance)
		effectInstance.CFrame = payload.impactCFrame
	elseif effectInstance:IsA("PVInstance") then
		effectInstance:PivotTo(payload.impactCFrame)
	else
		warnWithPrefix("Broccoli Bro Stomp FloorFx VFX instance cannot be pivoted.")
		effectInstance:Destroy()
		self:_cleanupRecord(record)
		return
	end

	effectInstance.Parent = self:_ensureCastFolder(record)
	playAllSounds(effectInstance)
	emitEffectInstance(effectInstance, BROCCOLI_BRO_STOMP_VFX_LIFETIME_SECONDS)
	self:_shakeImpact()
end

function BossArenaMovePresentationController:_impactBroccoliGrab(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.floorCFrame) ~= "CFrame" then
		self:_cleanupRecord(record)
		return
	end

	local explosionSource = resolveBossVfxModel(
		BROCCOLI_BRO_VFX_FOLDER_NAME,
		BROCCOLI_GRAB_VFX_NAME,
		BROCCOLI_GRAB_EXPLOSION_MODEL_NAME
	)
	if explosionSource == nil then
		warnWithPrefix("Broccoli Grab ThrowExplosion VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	local explosionModel = explosionSource:Clone()
	explosionModel:ScaleTo(scaleMultiplier)
	prepareMovingEffectModel(explosionModel)

	local floorAttachment = resolveNamedAttachment(explosionModel, BROCCOLI_GRAB_EXPLOSION_FLOOR_ATTACHMENT_NAME)
	if floorAttachment == nil then
		warnWithPrefix("Broccoli Grab ThrowExplosion VFX model is missing a Floor attachment.")
		explosionModel:Destroy()
		self:_cleanupRecord(record)
		return
	end

	pivotModelAttachmentToCFrame(explosionModel, floorAttachment, payload.floorCFrame)
	explosionModel.Parent = self:_ensureVisualFolder()

	playAllSounds(explosionModel)
	emitEffectInstance(explosionModel, BROCCOLI_GRAB_EXPLOSION_LIFETIME_SECONDS)
	destroyAfter(explosionModel, BROCCOLI_GRAB_EXPLOSION_LIFETIME_SECONDS)
	self:_shakeImpact()
	self:_cleanupRecord(record)
end

function BossArenaMovePresentationController:_startMechaKick(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local bossLeftFoot = resolveBossLeftFootPart(bossModel)
	if bossLeftFoot == nil then
		warnWithPrefix("Mecha Kick presentation could not resolve the live boss LeftFoot.")
		self:_cleanupRecord(record)
		return
	end

	local leftFootSource = resolveBossVfxModel(
		DESTROYER_3000_VFX_FOLDER_NAME,
		MECHA_KICK_VFX_NAME,
		MECHA_KICK_LEFT_FOOT_VFX_NAME
	)
	if leftFootSource == nil then
		warnWithPrefix("Mecha Kick LeftFoot VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local payload = event.payload
	local scaleMultiplier = math.max(0.1, tonumber(payload and payload.scaleMultiplier) or 1)
	local leftFootModel = leftFootSource:Clone()
	leftFootModel:ScaleTo(scaleMultiplier)
	prepareAttachedEffectModel(leftFootModel)

	if not attachEffectModel(leftFootModel, bossLeftFoot) then
		warnWithPrefix("Mecha Kick LeftFoot VFX model is missing a BasePart for welding.")
		leftFootModel:Destroy()
		self:_cleanupRecord(record)
		return
	end

	leftFootModel.Parent = self:_ensureCastFolder(record)
	record.leftFootModel = leftFootModel
	scaleAttachedSounds(leftFootModel, scaleMultiplier)
	playAllSounds(leftFootModel)
	emitEffectInstance(leftFootModel, MECHA_KICK_LEFT_FOOT_VFX_LIFETIME_SECONDS)
end

function BossArenaMovePresentationController:_impactMechaKick(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.impactCFrame) ~= "CFrame" then
		return
	end

	local explosionSource = resolveBossVfxModel(
		DESTROYER_3000_VFX_FOLDER_NAME,
		MECHA_KICK_VFX_NAME,
		MECHA_KICK_EXPLOSION_VFX_NAME
	)
	if explosionSource == nil then
		warnWithPrefix("Mecha Kick Explosion VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		return
	end

	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	local explosionModel = explosionSource:Clone()
	explosionModel:ScaleTo(scaleMultiplier)
	prepareMovingEffectModel(explosionModel)
	explosionModel:PivotTo(payload.impactCFrame)
	explosionModel.Parent = self:_ensureVisualFolder()

	playAllSounds(explosionModel)
	emitEffectInstance(explosionModel, MECHA_KICK_EXPLOSION_VFX_LIFETIME_SECONDS)
	destroyAfter(explosionModel, MECHA_KICK_EXPLOSION_VFX_LIFETIME_SECONDS)
	self:_shakeImpact()
end

function BossArenaMovePresentationController:_startMechaPunch(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local bossRootPart = resolveBossRootPart(bossModel)
	local bossRightHand = resolveBossRightHandPart(bossModel)
	if bossRootPart == nil or bossRightHand == nil then
		warnWithPrefix("Mecha Punch presentation could not resolve the live boss RootPart/RightHand.")
		self:_cleanupRecord(record)
		return
	end

	local rootPartSource = resolveBossVfxModel(
		DESTROYER_3000_VFX_FOLDER_NAME,
		MECHA_PUNCH_VFX_NAME,
		MECHA_PUNCH_ROOT_PART_VFX_NAME
	)
	local rightHandSource = resolveBossVfxModel(
		DESTROYER_3000_VFX_FOLDER_NAME,
		MECHA_PUNCH_VFX_NAME,
		MECHA_PUNCH_RIGHT_HAND_VFX_NAME
	)
	if rootPartSource == nil or rightHandSource == nil then
		warnWithPrefix("Mecha Punch RootPart/RightHand VFX models are missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local payload = event.payload
	local scaleMultiplier = math.max(0.1, tonumber(payload and payload.scaleMultiplier) or 1)
	local castFolder = self:_ensureCastFolder(record)
	local rootPartModel = rootPartSource:Clone()
	local rightHandModel = rightHandSource:Clone()
	rootPartModel:ScaleTo(scaleMultiplier)
	rightHandModel:ScaleTo(scaleMultiplier)
	prepareAttachedEffectModel(rootPartModel)
	prepareAttachedEffectModel(rightHandModel)
	scaleAttachedSounds(rootPartModel, scaleMultiplier)
	scaleAttachedSounds(rightHandModel, scaleMultiplier)

	rootPartModel.Parent = castFolder
	rightHandModel.Parent = castFolder
	record.rootModel = rootPartModel
	record.rightHandModel = rightHandModel

	if not attachEffectModel(rootPartModel, bossRootPart) or not attachEffectModel(rightHandModel, bossRightHand) then
		warnWithPrefix("Mecha Punch attached VFX models are missing BasePart configuration.")
		self:_cleanupRecord(record)
		return
	end

	playAllSounds(rootPartModel)
	playAllSounds(rightHandModel)
	emitVisuals(collectEmittableVisuals(rootPartModel))
	emitVisuals(collectEmittableVisuals(rightHandModel))
end

function BossArenaMovePresentationController:_impactMechaPunch(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.impactCFrame) ~= "CFrame" then
		return
	end

	local explosionSource = resolveBossVfxInstance(
		DESTROYER_3000_VFX_FOLDER_NAME,
		MECHA_PUNCH_VFX_NAME,
		MECHA_PUNCH_EXPLOSION_VFX_NAME
	)
	if explosionSource == nil then
		warnWithPrefix("Mecha Punch Explosion VFX instance is missing from ReplicatedStorage.GameAssets.VFX.")
		return
	end

	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	local explosionInstance = explosionSource:Clone()
	if explosionInstance:IsA("Model") then
		explosionInstance:ScaleTo(scaleMultiplier)
		prepareMovingEffectModel(explosionInstance)
		explosionInstance:PivotTo(payload.impactCFrame)
	elseif explosionInstance:IsA("BasePart") then
		explosionInstance.Size *= scaleMultiplier
		prepareMovingEffectPart(explosionInstance)
		explosionInstance.CFrame = payload.impactCFrame
	elseif explosionInstance:IsA("PVInstance") then
		explosionInstance:PivotTo(payload.impactCFrame)
	else
		warnWithPrefix("Mecha Punch Explosion VFX instance cannot be pivoted.")
		explosionInstance:Destroy()
		return
	end

	explosionInstance.Parent = self:_ensureVisualFolder()
	playAllSounds(explosionInstance)
	emitEffectInstance(explosionInstance, MECHA_PUNCH_EXPLOSION_VFX_LIFETIME_SECONDS)
	destroyAfter(explosionInstance, MECHA_PUNCH_EXPLOSION_VFX_LIFETIME_SECONDS)
	self:_shakeImpact()
end

function BossArenaMovePresentationController:_startDestroyerMissileBarrage(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local bossUpperTorso = resolveBossUpperTorsoPart(bossModel)
	local bossRootPart = resolveBossRootPart(bossModel)
	if bossUpperTorso == nil or bossRootPart == nil then
		warnWithPrefix("Missile Barrage presentation could not resolve the live boss UpperTorso/RootPart.")
		self:_cleanupRecord(record)
		return
	end

	local upperTorsoSource = resolveBossVfxModel(
		DESTROYER_3000_VFX_FOLDER_NAME,
		DESTROYER_MISSILE_BARRAGE_VFX_NAME,
		DESTROYER_MISSILE_BARRAGE_UPPER_TORSO_VFX_NAME
	)
	local rootPartSource = resolveBossVfxModel(
		DESTROYER_3000_VFX_FOLDER_NAME,
		DESTROYER_MISSILE_BARRAGE_VFX_NAME,
		DESTROYER_MISSILE_BARRAGE_ROOT_PART_VFX_NAME
	)
	if upperTorsoSource == nil or rootPartSource == nil then
		warnWithPrefix("Missile Barrage UpperTorso/RootPart VFX models are missing from ReplicatedStorage.GameAssets.VFX.")
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
	prepareAttachedEffectModel(upperTorsoModel)
	prepareAttachedEffectModel(rootPartModel)
	enableVfxDescendants(upperTorsoModel)
	enableVfxDescendants(rootPartModel)
	scaleAttachedSounds(upperTorsoModel, scaleMultiplier)
	scaleAttachedSounds(rootPartModel, scaleMultiplier)

	upperTorsoModel.Parent = castFolder
	rootPartModel.Parent = castFolder
	record.upperTorsoModel = upperTorsoModel
	record.rootModel = rootPartModel
	record.missileBarrageProjectileModels = {}
	record.missileBarrageProjectileMotions = {}

	if not attachEffectModel(upperTorsoModel, bossUpperTorso) or not attachEffectModel(rootPartModel, bossRootPart) then
		warnWithPrefix("Missile Barrage attached VFX models are missing BasePart configuration.")
		self:_cleanupRecord(record)
		return
	end

	playAllSounds(upperTorsoModel)
	playAllSounds(rootPartModel)
	emitEffectInstance(upperTorsoModel)
	emitEffectInstance(rootPartModel)
end

function BossArenaMovePresentationController:_launchDestroyerMissile(record: ActiveRecord, event: PresentationEvent)
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

	local projectileSource = resolveBossVfxModel(
		DESTROYER_3000_VFX_FOLDER_NAME,
		DESTROYER_MISSILE_BARRAGE_VFX_NAME,
		DESTROYER_MISSILE_BARRAGE_PROJECTILE_VFX_NAME
	)
	if projectileSource == nil then
		warnWithPrefix("Missile Barrage projectile VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local castFolder = self:_ensureCastFolder(record)
	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	local projectileModel = projectileSource:Clone()
	projectileModel:ScaleTo(scaleMultiplier)
	prepareMovingEffectModel(projectileModel)
	enableVfxDescendants(projectileModel)
	scaleAttachedSounds(projectileModel, scaleMultiplier)
	if resolveEffectModelPrimaryPart(projectileModel) == nil then
		projectileModel:Destroy()
		warnWithPrefix("Missile Barrage projectile VFX model is missing a BasePart for motion.")
		return
	end

	projectileModel.Parent = castFolder
	if typeof(startCFrame) == "CFrame" then
		projectileModel:PivotTo(startCFrame)
	else
		projectileModel:PivotTo(CFrame.new(startPosition))
	end
	playAllSounds(projectileModel)

	record.missileBarrageProjectileModels = record.missileBarrageProjectileModels or {}
	record.missileBarrageProjectileMotions = record.missileBarrageProjectileMotions or {}
	record.missileBarrageProjectileModels[index] = projectileModel
	record.missileBarrageProjectileMotions[index] = {
		startPosition = startPosition,
		controlPosition = controlPosition,
		impactPosition = impactPosition,
		travelDuration = math.max(0.001, travelDuration),
		startedAtServerTime = if typeof(event.serverTime) == "number" then event.serverTime else Workspace:GetServerTimeNow(),
	}

	self:_updateMissileBarrageProjectiles(record, Workspace:GetServerTimeNow())
end

function BossArenaMovePresentationController:_impactDestroyerMissile(record: ActiveRecord, event: PresentationEvent)
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
	playAllSounds(projectileModel)
	emitEffectInstance(projectileModel, DESTROYER_MISSILE_BARRAGE_EXPLOSION_LIFETIME_SECONDS)
	destroyAfter(projectileModel, DESTROYER_MISSILE_BARRAGE_EXPLOSION_LIFETIME_SECONDS)
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
		and moduleId ~= FIRE_BURST_MODULE_ID
		and moduleId ~= SQUID_CALL_MODULE_ID
		and moduleId ~= SHIP_CALL_MODULE_ID
		and moduleId ~= WAVE_CRASH_MODULE_ID
		and moduleId ~= WATER_BOMB_MODULE_ID
		and moduleId ~= BUBBLE_BLAST_MODULE_ID
		and moduleId ~= BROCCOLI_GRAB_MODULE_ID
		and moduleId ~= BROCCOLI_SPROUT_MODULE_ID
		and moduleId ~= MAGMA_THROW_MODULE_ID
		and moduleId ~= MAGMA_STOMP_MODULE_ID
		and moduleId ~= MAGMA_ERUPTION_MODULE_ID
		and moduleId ~= OINAN_THICKHOOF_CHARGE_MODULE_ID
		and moduleId ~= OINAN_THICKHOOF_ROAR_MODULE_ID
		and moduleId ~= OINAN_THICKHOOF_STOMP_MODULE_ID
		and moduleId ~= BROCCOLI_BRO_STOMP_MODULE_ID
		and moduleId ~= MECHA_KICK_MODULE_ID
		and moduleId ~= DESTROYER_3000_MECHA_KICK_MODULE_ID
		and moduleId ~= DESTROYER_3000_MECHA_PUNCH_MODULE_ID
		and moduleId ~= DESTROYER_MISSILE_BARRAGE_MODULE_ID then
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
			upperTorsoModel = nil,
			rootModel = nil,
			slashModel = nil,
			slashMotion = nil,
			leftFootModel = nil,
			leftHandModel = nil,
			cannonModel = nil,
			cannonMiddle = nil,
			cannonMuzzleAttachment = nil,
			squidCallAimData = nil,
			projectileModel = nil,
			projectileMotion = nil,
			rightHandModel = nil,
			shipModel = nil,
			shipMotion = nil,
			waveModel = nil,
			waveMotion = nil,
			waterBombChargeData = nil,
			bubbleBlastProjectileModels = nil,
			bubbleBlastProjectileMotions = nil,
			missileBarrageProjectileModels = nil,
			missileBarrageProjectileMotions = nil,
			eruptionWarningHandles = nil,
			broccoliSproutWarningHandles = nil,
			broccoliSproutTweens = nil,
			broccoliSproutTweenConnections = nil,
			broccoliSproutTweenValues = nil,
			stopRequested = false,
		}
		self._recordsByCastId[castId] = record

		if moduleId == FLAME_SLASH_MODULE_ID then
			self:_startFlameSlash(record, event)
		elseif moduleId == PROMETHEUS_SLASH_MODULE_ID then
			self:_startPrometheusSlash(record, event)
		elseif moduleId == FIRE_BURST_MODULE_ID then
			self:_startFireBurst(record, event)
		elseif moduleId == SQUID_CALL_MODULE_ID then
			self:_startSquidCall(record, event)
		elseif moduleId == WAVE_CRASH_MODULE_ID then
			self:_startWaveCrash(record, event)
		elseif moduleId == WATER_BOMB_MODULE_ID then
			self:_startWaterBomb(record, event)
		elseif moduleId == BUBBLE_BLAST_MODULE_ID then
			self:_startBubbleBlast(record, event)
		elseif moduleId == BROCCOLI_GRAB_MODULE_ID then
			-- Grab VFX emits on landing impact.
		elseif moduleId == BROCCOLI_SPROUT_MODULE_ID then
			-- Sprout warnings and trees emit from explicit presentation actions.
		elseif moduleId == MAGMA_THROW_MODULE_ID then
			self:_startMagmaThrow(record, event)
		elseif moduleId == MAGMA_STOMP_MODULE_ID then
			-- Stomp VFX emits on the animation marker, not cast start.
		elseif moduleId == MAGMA_ERUPTION_MODULE_ID then
			self:_startMagmaEruption(record, event)
		elseif moduleId == OINAN_THICKHOOF_CHARGE_MODULE_ID then
			-- Charge VFX emits on the animation marker, not cast start.
		elseif moduleId == OINAN_THICKHOOF_ROAR_MODULE_ID then
			self:_startOinanRoar(record, event)
		elseif moduleId == OINAN_THICKHOOF_STOMP_MODULE_ID then
			-- Stomp VFX emits on the animation marker, not cast start.
		elseif moduleId == BROCCOLI_BRO_STOMP_MODULE_ID then
			-- Stomp VFX emits on the animation marker, not cast start.
		elseif moduleId == MECHA_KICK_MODULE_ID or moduleId == DESTROYER_3000_MECHA_KICK_MODULE_ID then
			self:_startMechaKick(record, event)
		elseif moduleId == DESTROYER_3000_MECHA_PUNCH_MODULE_ID then
			self:_startMechaPunch(record, event)
		elseif moduleId == DESTROYER_MISSILE_BARRAGE_MODULE_ID then
			self:_startDestroyerMissileBarrage(record, event)
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
		elseif moduleId == SQUID_CALL_MODULE_ID then
			self:_impactSquidCall(record, event)
		elseif moduleId == WATER_BOMB_MODULE_ID then
			self:_impactWaterBomb(record, event)
		elseif moduleId == BUBBLE_BLAST_MODULE_ID then
			self:_impactBubbleBlast(record, event)
		elseif moduleId == BROCCOLI_GRAB_MODULE_ID then
			self:_impactBroccoliGrab(record, event)
		elseif moduleId == MAGMA_THROW_MODULE_ID then
			self:_impactMagmaThrow(record, event)
		elseif moduleId == MECHA_KICK_MODULE_ID or moduleId == DESTROYER_3000_MECHA_KICK_MODULE_ID then
			self:_impactMechaKick(record, event)
		elseif moduleId == DESTROYER_3000_MECHA_PUNCH_MODULE_ID then
			self:_impactMechaPunch(record, event)
		elseif moduleId == DESTROYER_MISSILE_BARRAGE_MODULE_ID then
			self:_impactDestroyerMissile(record, event)
		end
	elseif action == "summon" then
		if moduleId == SQUID_CALL_MODULE_ID then
			self:_summonSquidCall(record, event)
		end
	elseif action == "fire" then
		if moduleId == SQUID_CALL_MODULE_ID then
			self:_fireSquidCall(record, event)
		end
	elseif action == "ship" then
		if moduleId == SHIP_CALL_MODULE_ID then
			self:_shipShipCall(record, event)
		end
	elseif action == "send" then
		if moduleId == WAVE_CRASH_MODULE_ID then
			self:_sendWaveCrash(record, event)
		end
	elseif action == "throw" then
		if moduleId == WATER_BOMB_MODULE_ID then
			self:_throwWaterBomb(record, event)
		elseif moduleId == MAGMA_THROW_MODULE_ID then
			self:_throwMagmaThrow(record, event)
		end
	elseif action == "projectiles" then
		if moduleId == BUBBLE_BLAST_MODULE_ID then
			self:_launchBubbleBlastProjectiles(record, event)
		end
	elseif action == "launch" then
		if moduleId == DESTROYER_MISSILE_BARRAGE_MODULE_ID then
			self:_launchDestroyerMissile(record, event)
		end
	elseif action == "warn" then
		if moduleId == MAGMA_ERUPTION_MODULE_ID then
			self:_warnMagmaEruption(record, event)
		elseif moduleId == BROCCOLI_SPROUT_MODULE_ID then
			self:_warnBroccoliSprout(record, event)
		end
	elseif action == "erupt" then
		if moduleId == MAGMA_ERUPTION_MODULE_ID then
			self:_eruptMagmaEruption(record, event)
		end
	elseif action == "sprout" then
		if moduleId == BROCCOLI_SPROUT_MODULE_ID then
			self:_sproutBroccoliSprout(record, event)
		end
	elseif action == "roar" then
		if moduleId == OINAN_THICKHOOF_ROAR_MODULE_ID then
			self:_roarOinanRoar(record, event)
		end
	elseif action == "charge" then
		if moduleId == OINAN_THICKHOOF_CHARGE_MODULE_ID then
			self:_chargeOinanCharge(record, event)
		end
	elseif action == "stomp" then
		if moduleId == OINAN_THICKHOOF_STOMP_MODULE_ID then
			self:_stompOinanStomp(record, event)
		elseif moduleId == BROCCOLI_BRO_STOMP_MODULE_ID then
			self:_stompBroccoliStomp(record, event)
		elseif moduleId == MAGMA_STOMP_MODULE_ID then
			self:_stompMagmaStomp(record, event)
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
	initializeEmitModule()
	self._remoteConnection = remote.OnClientEvent:Connect(function(payload)
		self:_handleEvent(payload)
	end)
	self._cleanupConnection = RunService.Heartbeat:Connect(function()
		self:_updateActiveRecords()
	end)
end

return BossArenaMovePresentationController
