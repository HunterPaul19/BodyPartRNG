local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local GameAssetPaths = require(ReplicatedStorage.Shared.Assets.GameAssetPaths)
local GameAssetResolver = require(ReplicatedStorage.Shared.Assets.GameAssetResolver)
local Logger = require(ReplicatedStorage.Shared.Diagnostics.Logger)
local SoundUtil = require(script.Parent.SoundUtil)

local CombatSoundUtil = {}

local rng = Random.new()
local warnedMissingGroups: { [string]: boolean } = {}

local GROUP_SWING = "Swing"
local GROUP_HIT = "Hit"
local GROUP_DASH = "Dash"

local DEFAULT_EMITTER_SIZE = 7
local DEFAULT_ROLL_OFF_MIN_DISTANCE = 7
local DEFAULT_ROLL_OFF_MAX_DISTANCE = 75
local FALLBACK_CLEANUP_SECONDS = 4

local DASH_SOUND_BY_DIRECTION = {
	Front = "Forward",
	Back = "Back",
	Left = "Left",
	Right = "Left",
}

local function warnMissingGroupOnce(groupName: string)
	if warnedMissingGroups[groupName] == true then
		return
	end

	warnedMissingGroups[groupName] = true
	Logger.Warn(string.format(
		"[CombatSoundUtil] Missing combat audio group '%s' under %s.",
		groupName,
		GameAssetResolver.Format(GameAssetPaths.Audio.Combat)
	))
end

local function resolveCombatGroup(groupName: string): Instance?
	local group = GameAssetResolver.Find(GameAssetPaths.Audio.Combat, groupName)
	if group == nil then
		warnMissingGroupOnce(groupName)
	end

	return group
end

local function isPlayableSound(instance: Instance): boolean
	return instance:IsA("Sound") and instance.SoundId ~= ""
end

local function collectPlayableSounds(root: Instance?): { Sound }
	local sounds = {}
	if root == nil then
		return sounds
	end

	if isPlayableSound(root) then
		table.insert(sounds, root :: Sound)
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if isPlayableSound(descendant) then
			table.insert(sounds, descendant :: Sound)
		end
	end

	return sounds
end

local function chooseRandomSound(groupName: string): Sound?
	local sounds = collectPlayableSounds(resolveCombatGroup(groupName))
	if #sounds <= 0 then
		return nil
	end

	return sounds[rng:NextInteger(1, #sounds)]
end

local function findDashSound(direction: string?): Sound?
	local group = resolveCombatGroup(GROUP_DASH)
	if group == nil then
		return nil
	end

	local soundName = DASH_SOUND_BY_DIRECTION[direction or ""] or DASH_SOUND_BY_DIRECTION.Front
	local sound = group:FindFirstChild(soundName)
	if sound and isPlayableSound(sound) then
		return sound :: Sound
	end

	return nil
end

local function resolveRootPart(model: Model?): BasePart?
	if model == nil then
		return nil
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.RootPart and humanoid.RootPart:IsA("BasePart") then
		return humanoid.RootPart
	end

	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function configureSpatialSound(sound: Sound)
	sound.EmitterSize = math.max(DEFAULT_EMITTER_SIZE, tonumber(sound.EmitterSize) or 0)
	sound.RollOffMinDistance = math.max(DEFAULT_ROLL_OFF_MIN_DISTANCE, tonumber(sound.RollOffMinDistance) or 0)
	sound.RollOffMaxDistance = math.max(DEFAULT_ROLL_OFF_MAX_DISTANCE, tonumber(sound.RollOffMaxDistance) or 0)
end

local function createEmitter(position: Vector3): BasePart
	local emitter = Instance.new("Part")
	emitter.Name = "CombatSfxEmitter"
	emitter.Anchored = true
	emitter.CanCollide = false
	emitter.CanTouch = false
	emitter.CanQuery = false
	emitter.CastShadow = false
	emitter.Massless = true
	emitter.Size = Vector3.new(0.2, 0.2, 0.2)
	emitter.Transparency = 1
	emitter.CFrame = CFrame.new(position)
	emitter.Parent = Workspace
	return emitter
end

local function resolveCleanupSeconds(sound: Sound): number
	local timeLength = math.max(0, tonumber(sound.TimeLength) or 0)
	local playbackSpeed = math.max(0.001, tonumber(sound.PlaybackSpeed) or 1)
	if timeLength <= 0 then
		return FALLBACK_CLEANUP_SECONDS
	end

	return (timeLength / playbackSpeed) + 0.5
end

local function playLocal(sound: Sound?): Sound?
	if sound == nil then
		return nil
	end

	return SoundUtil.Play(sound, SoundService)
end

local function playSpatial(sound: Sound?, parentOrPosition: Instance | Vector3 | nil): Sound?
	if sound == nil then
		return nil
	end

	local parent = nil :: Instance?
	local emitter = nil :: BasePart?
	if typeof(parentOrPosition) == "Instance" and parentOrPosition.Parent ~= nil then
		parent = parentOrPosition
	elseif typeof(parentOrPosition) == "Vector3" then
		emitter = createEmitter(parentOrPosition)
		parent = emitter
	else
		parent = Workspace
	end

	local clone = sound:Clone()
	clone.Looped = false
	clone.TimePosition = 0
	configureSpatialSound(clone)
	clone.Parent = parent
	clone:Play()

	local cleanupSeconds = resolveCleanupSeconds(clone)
	Debris:AddItem(clone, cleanupSeconds)
	if emitter ~= nil then
		Debris:AddItem(emitter, cleanupSeconds)
	end

	return clone
end

function CombatSoundUtil.PlayLocalSwing(): Sound?
	return playLocal(chooseRandomSound(GROUP_SWING))
end

function CombatSoundUtil.PlayLocalHit(): Sound?
	return playLocal(chooseRandomSound(GROUP_HIT))
end

function CombatSoundUtil.PlayLocalDash(direction: string?): Sound?
	return playLocal(findDashSound(direction))
end

function CombatSoundUtil.PlaySpatialSwing(character: Model?, fallbackPosition: Vector3?): Sound?
	return playSpatial(chooseRandomSound(GROUP_SWING), resolveRootPart(character) or fallbackPosition)
end

function CombatSoundUtil.PlaySpatialHit(targetModel: Model?, fallbackPosition: Vector3?): Sound?
	return playSpatial(chooseRandomSound(GROUP_HIT), resolveRootPart(targetModel) or fallbackPosition)
end

function CombatSoundUtil.PlaySpatialDash(character: Model?, direction: string?, fallbackPosition: Vector3?): Sound?
	return playSpatial(findDashSound(direction), resolveRootPart(character) or fallbackPosition)
end

return table.freeze(CombatSoundUtil)
