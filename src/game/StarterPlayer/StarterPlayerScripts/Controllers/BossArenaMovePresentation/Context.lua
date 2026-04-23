local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CameraShaker = require(ReplicatedStorage.Shared.Camera.CameraShaker)
local Indication = require(ReplicatedStorage.Shared.Bosses.Indication)
local EmitModule = require(ReplicatedStorage.Shared.Effects.EmitModule)
local RockDebris = require(ReplicatedStorage.Shared.Effects.RockDebris)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local Config = require(script.Parent.Config)

type ActiveRecord = any
type PresentationEvent = any

local CAT_MECH_ELITE_RAINBOW_BLAST_MODULE_ID = "Moves.CatMechElite.RainbowBlast"

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

local function isRainbowBlastRecord(record: ActiveRecord): boolean
	return record.moduleId == CAT_MECH_ELITE_RAINBOW_BLAST_MODULE_ID
		or record.rainbowBlastBeamModel ~= nil
		or record.rainbowBlastEndModel ~= nil
		or record.rainbowBlastTargetModel ~= nil
		or record.rainbowBlastPlayerGlintModel ~= nil
		or record.rainbowBlastBeamMotion ~= nil
		or record.rainbowBlastTorsoAim ~= nil
end

local Context = {}
Context.__index = Context

function Context.new(controller)
	local self = setmetatable({
		controller = controller,
		Players = Players,
		Lighting = Lighting,
		ReplicatedStorage = ReplicatedStorage,
		TweenService = TweenService,
		Workspace = Workspace,
		Indication = Indication,
		RockDebris = RockDebris,
		_cameraShaker = nil,
		_acidBreathPoisonToken = 0,
		_acidBreathPoisonTweens = {},
	}, Context)
	return self
end

function Context:isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == Config.Place.ActiveProfileId
end

function Context:warnWithPrefix(message: string)
	warn(string.format("[BossArenaMovePresentationController] %s", message))
end

function Context:initializeEmitModule()
	local ok, err = pcall(function()
		EmitModule.init()
	end)
	if not ok then
		self:warnWithPrefix(string.format("Failed to initialize EmitModule: %s", tostring(err)))
	end
end

function Context:emitEffectInstance(instance: Instance, duration: number?)
	local ok, err = pcall(function()
		EmitModule.emit(instance)
	end)
	if not ok then
		self:warnWithPrefix(string.format("Failed to emit boss move effect instance: %s", tostring(err)))
	end

	if duration ~= nil then
		self:destroyVfxAfter(instance, duration)
	end
end

function Context:emitEffectInstanceAfter(instance: Instance, duration: number?, delaySeconds: number?)
	local resolvedDelay = math.max(0, tonumber(delaySeconds) or 0)
	if resolvedDelay <= 0 then
		self:emitEffectInstance(instance, duration)
		return
	end

	task.delay(resolvedDelay, function()
		if instance.Parent == nil then
			return
		end

		self:emitEffectInstance(instance, duration)
	end)
end

function Context:resolveBossHandlePart(bossModel: Model?): BasePart?
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

function Context:resolveBossRootPart(bossModel: Model?): BasePart?
	if bossModel == nil then
		return nil
	end

	local rootPart = bossModel:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	local recursiveRootPart = bossModel:FindFirstChild("HumanoidRootPart", true)
	if recursiveRootPart and recursiveRootPart:IsA("BasePart") then
		return recursiveRootPart
	end

	local primaryPart = bossModel.PrimaryPart
	if primaryPart then
		return primaryPart
	end

	return bossModel:FindFirstChildWhichIsA("BasePart", true)
end

function Context:resolveBossHeadPart(bossModel: Model?): BasePart?
	if bossModel == nil then
		return nil
	end

	local head = bossModel:FindFirstChild("Head", true)
	if head and head:IsA("BasePart") then
		return head
	end

	return nil
end

function Context:resolveBossUpperTorsoPart(bossModel: Model?): BasePart?
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

function Context:resolveBossLeftHandPart(bossModel: Model?): BasePart?
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

function Context:resolveBossLeftFootPart(bossModel: Model?): BasePart?
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

function Context:resolveBossRightHandPart(bossModel: Model?): BasePart?
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

function Context:resolveBossVfxFolder(bossFolderName: string, effectFolderName: string): Folder?
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

function Context:resolveBossVfxModel(bossFolderName: string, effectFolderName: string, modelName: string): Model?
	local effectFolder = self:resolveBossVfxFolder(bossFolderName, effectFolderName)
	if not effectFolder then
		return nil
	end

	local effectModel = effectFolder:FindFirstChild(modelName)
	if effectModel and effectModel:IsA("Model") then
		return effectModel
	end

	return nil
end

function Context:resolveBossVfxInstance(bossFolderName: string, effectFolderName: string, instanceName: string): Instance?
	local effectFolder = self:resolveBossVfxFolder(bossFolderName, effectFolderName)
	if not effectFolder then
		return nil
	end
	return effectFolder:FindFirstChild(instanceName)
end

function Context:resolveVfxModel(effectFolderName: string, modelName: string): Model?
	return self:resolveBossVfxModel("FlameGuardGeneral", effectFolderName, modelName)
end

function Context:resolveVfxInstance(effectFolderName: string, instanceName: string): Instance?
	return self:resolveBossVfxInstance("FlameGuardGeneral", effectFolderName, instanceName)
end

function Context:prepareAttachedEffectModel(model: Model)
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

function Context:prepareMovingEffectModel(model: Model)
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

function Context:prepareMovingEffectPart(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
end

function Context:setBasePartTransparency(root: Instance, transparency: number)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Transparency = transparency
		end
	end
end

local function getNumberAttribute(instance: Instance, primaryName: string, fallbackName: string?): number?
	local primaryValue = tonumber(instance:GetAttribute(primaryName))
	if primaryValue ~= nil then
		return primaryValue
	end

	if fallbackName == nil then
		return nil
	end

	return tonumber(instance:GetAttribute(fallbackName))
end

local UNLOADED_SOUND_PLAYBACK_WINDOW_SECONDS = 8

local function resolveSoundPlaybackWindow(sound: Sound, includeConfiguredDelay: boolean): number
	local delaySeconds = if includeConfiguredDelay then math.max(0, getNumberAttribute(sound, "Delay", "Start") or 0) else 0
	if sound.Looped then
		return delaySeconds
	end

	local sourceStart = getNumberAttribute(sound, "SourceStart", "Offset")
	if sourceStart == nil and sound.TimePosition > 0 then
		sourceStart = sound.TimePosition
	end

	local startPosition = math.max(0, sourceStart or 0)
	local sourceEnd = getNumberAttribute(sound, "SourceEnd", "End")
	local timeLength = math.max(0, tonumber(sound.TimeLength) or 0)
	local endPosition = if sourceEnd ~= nil and sourceEnd > 0 then sourceEnd else timeLength
	local playbackSpeed = math.max(0.001, tonumber(sound.PlaybackSpeed) or 1)
	local remainingSeconds = if endPosition > startPosition then (endPosition - startPosition) / playbackSpeed else 0

	if remainingSeconds <= 0 and timeLength <= 0 then
		remainingSeconds = UNLOADED_SOUND_PLAYBACK_WINDOW_SECONDS
	end

	return delaySeconds + remainingSeconds
end

function Context:resolveSoundPlaybackWindow(root: Instance?, includeConfiguredDelay: boolean?): number
	if root == nil then
		return 0
	end

	local includeDelay = includeConfiguredDelay ~= false
	local longestWindow = 0
	if root:IsA("Sound") then
		longestWindow = math.max(longestWindow, resolveSoundPlaybackWindow(root, includeDelay))
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Sound") then
			longestWindow = math.max(longestWindow, resolveSoundPlaybackWindow(descendant, includeDelay))
		end
	end

	return longestWindow
end

function Context:destroyAfter(instance: Instance?, delaySeconds: number)
	if instance == nil then
		return
	end

	task.delay(math.max(0, tonumber(delaySeconds) or 0), function()
		if instance.Parent ~= nil then
			instance:Destroy()
		end
	end)
end

function Context:destroySoundAfter(instance: Instance?, activeSeconds: number?, includeConfiguredDelay: boolean?)
	if instance == nil then
		return
	end

	local activeDelay = math.max(0, tonumber(activeSeconds) or 0)
	local soundDelay = self:resolveSoundPlaybackWindow(instance, includeConfiguredDelay)
	self:destroyAfter(instance, math.max(activeDelay, soundDelay) + Config.Cleanup.SfxCleanupDelaySeconds)
end

function Context:destroyVfxAfter(instance: Instance?, activeSeconds: number?)
	if instance == nil then
		return
	end

	local visualDelay = math.max(0, tonumber(activeSeconds) or 0) + Config.Cleanup.VfxCleanupDelaySeconds
	local soundDelay = self:resolveSoundPlaybackWindow(instance, true) + Config.Cleanup.SfxCleanupDelaySeconds
	local delaySeconds = math.max(visualDelay, soundDelay)
	self:destroyAfter(instance, delaySeconds)
end

function Context:resolveFireBurstRingSize(outerRadius: number, templatePart: BasePart): Vector3
	local diameter = math.max(0, outerRadius * 2)
	local height = math.max(0.05, templatePart.Size.Y)
	local specialMesh = templatePart:FindFirstChildOfClass("SpecialMesh")
	if specialMesh then
		local mappedDiameter = diameter / Config.FireBurst.RingDiameterPerSizeStud
		return Vector3.new(mappedDiameter, height, mappedDiameter)
	end

	return Vector3.new(diameter, height, diameter)
end

function Context:resolveFireBurstRingCFrame(position: Vector3, size: Vector3): CFrame
	return CFrame.new(position + Vector3.new(0, size.Y * 0.5, 0))
end

function Context:enableParticleEmitters(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = true
		end
	end
end

function Context:enableVfxDescendants(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") or descendant:IsA("Trail") then
			descendant.Enabled = true
		end
	end
end

function Context:createWeld(part0: BasePart, part1: BasePart)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part0
	weld.Part1 = part1
	weld.Parent = part0
	return weld
end

function Context:resolveEffectModelPrimaryPart(effectModel: Model): BasePart?
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

function Context:resolveNamedAttachment(root: Instance, attachmentName: string): Attachment?
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Attachment") and string.lower(descendant.Name) == string.lower(attachmentName) then
			return descendant
		end
	end

	return nil
end

function Context:pivotModelAttachmentToCFrame(effectModel: Model, attachment: Attachment, targetCFrame: CFrame)
	local currentPivot = effectModel:GetPivot()
	local attachmentToPivot = attachment.WorldCFrame:ToObjectSpace(currentPivot)
	effectModel:PivotTo(targetCFrame * attachmentToPivot)
end

function Context:attachEffectModel(effectModel: Model, targetPart: BasePart)
	local primaryPart = self:resolveEffectModelPrimaryPart(effectModel)
	if primaryPart == nil then
		return false
	end

	effectModel:PivotTo(targetPart.CFrame)
	self:createWeld(primaryPart, targetPart)
	return true
end

local SOUND_BASE_EMITTER_SIZE_ATTRIBUTE = "BossAudioBaseEmitterSize"
local SOUND_BASE_ROLL_OFF_MIN_DISTANCE_ATTRIBUTE = "BossAudioBaseRollOffMinDistance"
local SOUND_BASE_ROLL_OFF_MAX_DISTANCE_ATTRIBUTE = "BossAudioBaseRollOffMaxDistance"

local function normalizeSoundScale(scaleMultiplier: number?): number
	return math.max(0.1, tonumber(scaleMultiplier) or 1)
end

local function resolveRootSoundScale(root: Instance, fallbackScale: number?): number
	if fallbackScale ~= nil then
		return normalizeSoundScale(fallbackScale)
	end

	if root:IsA("Model") then
		local ok, scale = pcall(function()
			return root:GetScale()
		end)
		if ok then
			return normalizeSoundScale(scale)
		end
	end

	return 1
end

function Context:scaleSound(sound: Sound, scaleMultiplier: number?)
	local resolvedScale = normalizeSoundScale(scaleMultiplier)
	local baseEmitterSize = tonumber(sound:GetAttribute(SOUND_BASE_EMITTER_SIZE_ATTRIBUTE))
	local baseRollOffMinDistance = tonumber(sound:GetAttribute(SOUND_BASE_ROLL_OFF_MIN_DISTANCE_ATTRIBUTE))
	local baseRollOffMaxDistance = tonumber(sound:GetAttribute(SOUND_BASE_ROLL_OFF_MAX_DISTANCE_ATTRIBUTE))

	if baseEmitterSize == nil then
		baseEmitterSize = sound.EmitterSize
		sound:SetAttribute(SOUND_BASE_EMITTER_SIZE_ATTRIBUTE, baseEmitterSize)
	end
	if baseRollOffMinDistance == nil then
		baseRollOffMinDistance = sound.RollOffMinDistance
		sound:SetAttribute(SOUND_BASE_ROLL_OFF_MIN_DISTANCE_ATTRIBUTE, baseRollOffMinDistance)
	end
	if baseRollOffMaxDistance == nil then
		baseRollOffMaxDistance = sound.RollOffMaxDistance
		sound:SetAttribute(SOUND_BASE_ROLL_OFF_MAX_DISTANCE_ATTRIBUTE, baseRollOffMaxDistance)
	end

	sound.EmitterSize = baseEmitterSize * resolvedScale
	sound.RollOffMinDistance = baseRollOffMinDistance * resolvedScale
	sound.RollOffMaxDistance = baseRollOffMaxDistance * resolvedScale
end

function Context:scaleAttachedSounds(root: Instance, scaleMultiplier: number?)
	local resolvedScale = resolveRootSoundScale(root, scaleMultiplier)
	if root:IsA("Sound") then
		self:scaleSound(root, resolvedScale)
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Sound") then
			self:scaleSound(descendant, resolvedScale)
		end
	end
end

function Context:collectEmittableVisuals(root: Instance): { Instance }
	local visuals = {}

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") or descendant:IsA("Beam") or descendant:IsA("RayValue") then
			table.insert(visuals, descendant)
		end
	end

	return visuals
end

function Context:emitVisuals(instances: { Instance })
	if #instances <= 0 then
		return
	end

	local ok, err = pcall(function()
		EmitModule.emit(table.unpack(instances))
	end)
	if not ok then
		self:warnWithPrefix(string.format("Failed to emit boss move visuals: %s", tostring(err)))
	end
end

function Context:emitVisualsAfter(instances: { Instance }, delaySeconds: number?)
	local resolvedDelay = math.max(0, tonumber(delaySeconds) or 0)
	if resolvedDelay <= 0 then
		self:emitVisuals(instances)
		return
	end

	task.delay(resolvedDelay, function()
		local liveInstances = {}
		for _, instance in ipairs(instances) do
			if instance.Parent ~= nil then
				table.insert(liveInstances, instance)
			end
		end

		self:emitVisuals(liveInstances)
	end)
end

function Context:playSound(sound: Sound?, scaleMultiplier: number?)
	if sound == nil then
		return
	end

	self:scaleSound(sound, scaleMultiplier)
	sound.TimePosition = 0
	sound:Play()
end

function Context:playSoundFromConfiguredPosition(sound: Sound?, scaleMultiplier: number?)
	if sound == nil then
		return
	end

	self:scaleSound(sound, scaleMultiplier)
	local sourceStart = getNumberAttribute(sound, "SourceStart", "Offset")
	if sourceStart == nil and sound.TimePosition > 0 then
		sourceStart = sound.TimePosition
	end

	sound.TimePosition = math.max(0, sourceStart or 0)
	sound:Play()
end

function Context:playTimedSound(sound: Sound?, scaleMultiplier: number?)
	if sound == nil then
		return
	end

	local resolvedScale = normalizeSoundScale(scaleMultiplier)
	local delaySeconds = math.max(0, getNumberAttribute(sound, "Delay", "Start") or 0)
	local sourceStart = getNumberAttribute(sound, "SourceStart", "Offset")
	local sourceEnd = getNumberAttribute(sound, "SourceEnd", "End")
	if sourceStart == nil and sound.TimePosition > 0 then
		sourceStart = sound.TimePosition
	end

	task.delay(delaySeconds, function()
		if sound.Parent == nil then
			return
		end

		self:scaleSound(sound, resolvedScale)
		if sourceStart ~= nil then
			sound.TimePosition = math.max(0, sourceStart)
		end

		sound:Play()

		if sourceEnd ~= nil and sourceEnd > 0 then
			local stopDelay = math.max(0, sourceEnd - sound.TimePosition)
			task.delay(stopDelay, function()
				if sound.Parent ~= nil and sound.IsPlaying then
					sound:Stop()
				end
			end)
		end
	end)
end

function Context:playAllSounds(root: Instance, scaleMultiplier: number?)
	local resolvedScale = resolveRootSoundScale(root, scaleMultiplier)
	if root:IsA("Sound") then
		self:playSound(root, resolvedScale)
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Sound") then
			self:playSound(descendant, resolvedScale)
		end
	end
end

function Context:playAllSoundsFromConfiguredPositions(root: Instance, scaleMultiplier: number?)
	local resolvedScale = resolveRootSoundScale(root, scaleMultiplier)
	if root:IsA("Sound") then
		self:playSoundFromConfiguredPosition(root, resolvedScale)
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Sound") then
			self:playSoundFromConfiguredPosition(descendant, resolvedScale)
		end
	end
end

function Context:playTimedSounds(root: Instance, scaleMultiplier: number?)
	local resolvedScale = resolveRootSoundScale(root, scaleMultiplier)
	if root:IsA("Sound") then
		self:playTimedSound(root, resolvedScale)
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Sound") then
			self:playTimedSound(descendant, resolvedScale)
		end
	end
end

function Context:playDelayedSoundClones(sourceRoot: Instance, parent: Instance, scaleMultiplier: number?)
	local resolvedScale = resolveRootSoundScale(sourceRoot, scaleMultiplier)
	if sourceRoot:IsA("Sound") then
		local soundClone = sourceRoot:Clone()
		soundClone.Parent = parent

		local delaySeconds = math.max(0, tonumber(sourceRoot:GetAttribute("Delay")) or 0)
		task.delay(delaySeconds, function()
			if soundClone.Parent == nil then
				return
			end

			self:playSound(soundClone, resolvedScale)
			self:destroySoundAfter(soundClone, 0, false)
		end)
	end
	for _, descendant in ipairs(sourceRoot:GetDescendants()) do
		if not descendant:IsA("Sound") then
			continue
		end

		local soundClone = descendant:Clone()
		soundClone.Parent = parent

		local delaySeconds = math.max(0, tonumber(descendant:GetAttribute("Delay")) or 0)
		task.delay(delaySeconds, function()
			if soundClone.Parent == nil then
				return
			end

			self:playSound(soundClone, resolvedScale)
			self:destroySoundAfter(soundClone, 0, false)
		end)
	end
end

function Context:resolveQuadraticBezierPosition(startPosition: Vector3, controlPosition: Vector3, endPosition: Vector3, alpha: number): Vector3
	local clampedAlpha = math.clamp(alpha, 0, 1)
	local first = startPosition:Lerp(controlPosition, clampedAlpha)
	local second = controlPosition:Lerp(endPosition, clampedAlpha)
	return first:Lerp(second, clampedAlpha)
end

function Context:resolvePlanarDirection(fromPosition: Vector3, toPosition: Vector3?, fallbackDirection: Vector3?): Vector3
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

function Context:resolveCannonBaseCFrame(originPosition: Vector3, targetPosition: Vector3?, fallbackDirection: Vector3?): CFrame
	local planarDirection = self:resolvePlanarDirection(originPosition, targetPosition, fallbackDirection)
	return CFrame.lookAt(originPosition, originPosition + planarDirection) * CFrame.Angles(0, Config.SquidCall.CannonAssetYawOffsetRadians, 0)
end

function Context:resolveSquidCallPitch(middleBaseCFrame: CFrame, targetPosition: Vector3?): number
	if typeof(targetPosition) ~= "Vector3" then
		return 0
	end

	local offset = targetPosition - middleBaseCFrame.Position
	local planarDistance = Vector3.new(offset.X, 0, offset.Z).Magnitude
	return math.atan2(offset.Y, math.max(planarDistance, 0.001))
end

function Context:resolvePlayerRootPartByUserId(userId: number?): BasePart?
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

function Context:destroyEatChickenMeat(chickenModel: Model)
	for _, descendant in ipairs(chickenModel:GetDescendants()) do
		if descendant.Name == "ChickenMeat" then
			descendant:Destroy()
		end
	end
end

function Context:destroyWeldConstraints(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("WeldConstraint") then
			descendant:Destroy()
		end
	end
end

function Context:resolveProjectileCFrame(startPosition: Vector3, endPosition: Vector3, alpha: number): CFrame
	local position = startPosition:Lerp(endPosition, alpha)
	local lookAheadPosition = startPosition:Lerp(endPosition, math.clamp(alpha + 0.03, 0, 1))
	local travelVector = lookAheadPosition - position
	if travelVector.Magnitude > 0.001 then
		return CFrame.lookAt(position, position + travelVector.Unit)
	end

	local fullTravelVector = endPosition - startPosition
	if fullTravelVector.Magnitude > 0.001 then
		return CFrame.lookAt(position, position + fullTravelVector.Unit)
	end

	return CFrame.new(position)
end

function Context:pivotBroccoliSproutEffectInstance(effectInstance: Instance, cframe: CFrame, scaleMultiplier: number): boolean
	return self:pivotFloorEffectInstance(effectInstance, cframe, scaleMultiplier)
end

function Context:pivotEffectInstanceAtAuthoredPivot(effectInstance: Instance, cframe: CFrame, scaleMultiplier: number): boolean
	if effectInstance:IsA("Model") then
		effectInstance:ScaleTo(scaleMultiplier)
		self:prepareMovingEffectModel(effectInstance)
		effectInstance:PivotTo(cframe)
		return true
	end
	if effectInstance:IsA("BasePart") then
		effectInstance.Size *= scaleMultiplier
		self:prepareMovingEffectPart(effectInstance)
		effectInstance.CFrame = cframe
		return true
	end
	if effectInstance:IsA("PVInstance") then
		effectInstance:PivotTo(cframe)
		return true
	end

	return false
end

function Context:pivotFloorEffectInstance(effectInstance: Instance, cframe: CFrame, scaleMultiplier: number): boolean
	if effectInstance:IsA("Model") then
		effectInstance:ScaleTo(scaleMultiplier)
		self:prepareMovingEffectModel(effectInstance)
		effectInstance:PivotTo(cframe)
		local boundingCFrame, boundingSize = effectInstance:GetBoundingBox()
		local bottomY = boundingCFrame.Position.Y - (boundingSize.Y * 0.5)
		effectInstance:PivotTo(effectInstance:GetPivot() + Vector3.new(0, cframe.Position.Y - bottomY, 0))
		return true
	end
	if effectInstance:IsA("BasePart") then
		effectInstance.Size *= scaleMultiplier
		self:prepareMovingEffectPart(effectInstance)
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

function Context:_ensureRemote(): RemoteEvent?
	if self._remote then
		return self._remote
	end

	local remotesFolder = ReplicatedStorage:WaitForChild(Config.Remotes.RootFolderName, 30)
	if not (remotesFolder and remotesFolder:IsA("Folder")) then
		self:warnWithPrefix("ReplicatedStorage.Remotes is missing.")
		return nil
	end

	local bossArenaFolder = remotesFolder:WaitForChild(Config.Remotes.BossArenaFolderName, 30)
	if not (bossArenaFolder and bossArenaFolder:IsA("Folder")) then
		self:warnWithPrefix("ReplicatedStorage.Remotes.BossArena is missing.")
		return nil
	end

	local remote = bossArenaFolder:WaitForChild(Config.Remotes.MovePresentationRemoteName, 30)
	if not (remote and remote:IsA("RemoteEvent")) then
		self:warnWithPrefix("BossArena.BossMovePresentation is missing.")
		return nil
	end

	self._remote = remote
	return remote
end

function Context:_ensureVisualFolder(): Folder
	local folder = Workspace:FindFirstChild(Config.Folders.VisualFolderName)
	if folder and folder:IsA("Folder") then
		return folder
	end

	local created = Instance.new("Folder")
	created.Name = Config.Folders.VisualFolderName
	created.Parent = Workspace
	return created
end

function Context:_ensureCameraShaker()
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

function Context:_shakeImpact()
	self:_ensureCameraShaker():ShakeOnce(
		Config.Shake.ImpactMagnitude,
		Config.Shake.ImpactRoughness,
		Config.Shake.ImpactFadeIn,
		Config.Shake.ImpactFadeOut
	)
end

function Context:_cleanupRecord(record: ActiveRecord?)
	if record == nil then
		return
	end

	self.controller._recordsByCastId[record.castId] = nil
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
	if record.rainbowBlastTorsoAim then
		local connection = record.rainbowBlastTorsoAim.connection
		if connection and connection.Connected then
			connection:Disconnect()
		end

		local waist = record.rainbowBlastTorsoAim.waist
		if waist and waist.Parent ~= nil then
			waist.Transform = CFrame.identity
		end
		record.rainbowBlastTorsoAim = nil
	end
	if isRainbowBlastRecord(record) then
		setVfxDescendantsEnabled(record.castFolder, false)
		setVfxDescendantsEnabled(record.rainbowBlastPlayerGlintModel, false)
	end
	self:destroyVfxAfter(record.castFolder, 0)
	self:destroyVfxAfter(record.rainbowBlastPlayerGlintModel, 0)
	record.missileBarrageProjectileModels = nil
	record.missileBarrageProjectileMotions = nil
	record.eatChickenBoneModels = nil
	record.eatChickenBoneMotions = nil
	record.rainbowBlastBeamModel = nil
	record.rainbowBlastEndModel = nil
	record.rainbowBlastTargetModel = nil
	record.rainbowBlastPlayerGlintModel = nil
	record.rainbowBlastBeamMotion = nil
	record.rainbowBlastTorsoAim = nil
end

function Context:_removeAttachedCastModels(record: ActiveRecord)
	self:destroyVfxAfter(record.handleModel, 0)
	self:destroyVfxAfter(record.upperTorsoModel, 0)
	self:destroyVfxAfter(record.rootModel, 0)
	record.handleModel = nil
	record.upperTorsoModel = nil
	record.rootModel = nil
end

function Context:_ensureCastFolder(record: ActiveRecord): Folder
	if record.castFolder and record.castFolder.Parent then
		return record.castFolder
	end

	local castFolder = Instance.new("Folder")
	castFolder.Name = record.castId
	castFolder.Parent = self:_ensureVisualFolder()
	record.castFolder = castFolder
	return castFolder
end

function Context:_prepareAttachedCastModels(
	record: ActiveRecord,
	event: PresentationEvent,
	moveLabel: string,
	effectFolderName: string,
	options: { enableParticles: boolean?, scaleRootSounds: boolean?, playAllSounds: boolean?, playTimedSounds: boolean? }?
): boolean
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return false
	end

	local bossHandle = self:resolveBossHandlePart(bossModel)
	local bossRootPart = self:resolveBossRootPart(bossModel)
	if bossHandle == nil or bossRootPart == nil then
		self:warnWithPrefix(string.format("%s presentation could not resolve the live boss Handle/RootPart.", moveLabel))
		self:_cleanupRecord(record)
		return false
	end

	local handleSource = self:resolveVfxModel(effectFolderName, "Handle")
	local rootSource = self:resolveVfxModel(effectFolderName, "RootPart")
	if handleSource == nil or rootSource == nil then
		self:warnWithPrefix(string.format("%s presentation VFX models are missing from ReplicatedStorage.GameAssets.VFX.", moveLabel))
		self:_cleanupRecord(record)
		return false
	end

	local handleModel = handleSource:Clone()
	local rootModel = rootSource:Clone()
	local scaleMultiplier = math.max(0.1, tonumber(event.payload and event.payload.scaleMultiplier) or 1)

	handleModel:ScaleTo(scaleMultiplier)
	rootModel:ScaleTo(scaleMultiplier)
	self:prepareAttachedEffectModel(handleModel)
	self:prepareAttachedEffectModel(rootModel)
	self:scaleAttachedSounds(handleModel, scaleMultiplier)
	if options and options.scaleRootSounds then
		self:scaleAttachedSounds(rootModel, scaleMultiplier)
	end
	if options and options.enableParticles then
		self:enableParticleEmitters(handleModel)
		self:enableParticleEmitters(rootModel)
	end

	local castFolder = Instance.new("Folder")
	castFolder.Name = record.castId
	castFolder.Parent = self:_ensureVisualFolder()
	record.castFolder = castFolder
	record.handleModel = handleModel
	record.rootModel = rootModel

	handleModel.Parent = castFolder
	rootModel.Parent = castFolder

	if not self:attachEffectModel(handleModel, bossHandle) or not self:attachEffectModel(rootModel, bossRootPart) then
		self:warnWithPrefix(string.format("%s presentation VFX models are missing BasePart configuration.", moveLabel))
		self:_cleanupRecord(record)
		return false
	end

	if options and options.playTimedSounds then
		self:playTimedSounds(handleModel, scaleMultiplier)
		self:playTimedSounds(rootModel, scaleMultiplier)
	elseif options and options.playAllSounds then
		self:playAllSounds(handleModel, scaleMultiplier)
		self:playAllSounds(rootModel, scaleMultiplier)
	end

	self:emitVisuals(self:collectEmittableVisuals(handleModel))
	self:emitVisuals(self:collectEmittableVisuals(rootModel))
	return true
end

return Context
