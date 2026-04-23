local Workspace = game:GetService("Workspace")

local BossFightSfxUtil = {}

local ACTIVE_ARENA_MODEL_NAME = "ActiveBossArena"
local SFX_EMITTER_NAME = "BossArenaSfxEmitter"
local DEFAULT_CLEANUP_PADDING_SECONDS = 3
local UNLOADED_SOUND_PLAYBACK_WINDOW_SECONDS = 8

local SOUND_BASE_EMITTER_SIZE_ATTRIBUTE = "BossAudioBaseEmitterSize"
local SOUND_BASE_ROLL_OFF_MIN_DISTANCE_ATTRIBUTE = "BossAudioBaseRollOffMinDistance"
local SOUND_BASE_ROLL_OFF_MAX_DISTANCE_ATTRIBUTE = "BossAudioBaseRollOffMaxDistance"

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

local function normalizeSoundScale(scaleMultiplier: number?): number
	return math.max(0.1, tonumber(scaleMultiplier) or 1)
end

local function resolveArenaModel(arenaModel: Model?): Model?
	if arenaModel ~= nil and arenaModel.Parent ~= nil then
		return arenaModel
	end

	local activeArena = Workspace:FindFirstChild(ACTIVE_ARENA_MODEL_NAME)
	if activeArena and activeArena:IsA("Model") and activeArena.Parent ~= nil then
		return activeArena
	end

	return nil
end

local function resolveArenaBoundingSize(arenaModel: Model): Vector3?
	local ok, _, boundingSize = pcall(function()
		return arenaModel:GetBoundingBox()
	end)
	if not ok then
		return nil
	end

	return boundingSize
end

local function resolveBaseProperty(sound: Sound, attributeName: string, propertyName: string): number
	local attributeValue = tonumber(sound:GetAttribute(attributeName))
	if attributeValue ~= nil then
		return attributeValue
	end

	local propertyValue = tonumber(sound[propertyName]) or 0
	sound:SetAttribute(attributeName, propertyValue)
	return propertyValue
end

local function collectSounds(root: Instance, soundFilter: ((Sound) -> boolean)?): { Sound }
	local sounds = {}
	local function shouldInclude(sound: Sound): boolean
		if soundFilter == nil then
			return true
		end

		return soundFilter(sound) == true
	end

	if root:IsA("Sound") and shouldInclude(root) then
		table.insert(sounds, root)
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Sound") and shouldInclude(descendant) then
			table.insert(sounds, descendant)
		end
	end

	return sounds
end

local function coerceWorldCFrame(worldCFrameOrPosition: CFrame | Vector3): CFrame?
	if typeof(worldCFrameOrPosition) == "CFrame" then
		return worldCFrameOrPosition
	end
	if typeof(worldCFrameOrPosition) == "Vector3" then
		return CFrame.new(worldCFrameOrPosition)
	end

	return nil
end

local function resolvePlaybackOptions(options)
	local resolvedOptions = options or {}
	return {
		activeSeconds = tonumber(resolvedOptions.activeSeconds),
		arenaModel = resolvedOptions.arenaModel,
		cleanupPaddingSeconds = tonumber(resolvedOptions.cleanupPaddingSeconds),
		delayOffsetSeconds = tonumber(resolvedOptions.delayOffsetSeconds),
		includeDelay = if resolvedOptions.includeDelay == nil then true else resolvedOptions.includeDelay == true,
		parent = resolvedOptions.parent,
		scaleMultiplier = tonumber(resolvedOptions.scaleMultiplier),
		soundFilter = resolvedOptions.soundFilter,
		useConfiguredEndPosition = if resolvedOptions.useConfiguredEndPosition == nil
			then true
			else resolvedOptions.useConfiguredEndPosition == true,
		useConfiguredStartPosition = if resolvedOptions.useConfiguredStartPosition == nil
			then true
			else resolvedOptions.useConfiguredStartPosition == true,
	}
end

local function resolveSourceStart(sound: Sound, useConfiguredStartPosition: boolean): number
	if not useConfiguredStartPosition then
		return 0
	end

	local sourceStart = getNumberAttribute(sound, "SourceStart", "Offset")
	if sourceStart == nil and sound.TimePosition > 0 then
		sourceStart = sound.TimePosition
	end

	return math.max(0, sourceStart or 0)
end

local function resolvePlaybackWindow(sound: Sound, playbackOptions): number
	local delaySeconds = 0
	if playbackOptions.includeDelay then
		delaySeconds = math.max(0, getNumberAttribute(sound, "Delay", "Start") or 0)
	end
	delaySeconds = math.max(0, delaySeconds + (playbackOptions.delayOffsetSeconds or 0))

	if sound.Looped then
		return delaySeconds + math.max(0, playbackOptions.activeSeconds or 0)
	end

	local startPosition = resolveSourceStart(sound, playbackOptions.useConfiguredStartPosition)
	local sourceEnd = if playbackOptions.useConfiguredEndPosition then getNumberAttribute(sound, "SourceEnd", "End") else nil
	local timeLength = math.max(0, tonumber(sound.TimeLength) or 0)
	local endPosition = if sourceEnd ~= nil and sourceEnd > 0 then sourceEnd else timeLength
	local playbackSpeed = math.max(0.001, tonumber(sound.PlaybackSpeed) or 1)
	local remainingSeconds = if endPosition > startPosition then (endPosition - startPosition) / playbackSpeed else 0

	if remainingSeconds <= 0 and timeLength <= 0 then
		remainingSeconds = UNLOADED_SOUND_PLAYBACK_WINDOW_SECONDS
	end

	return delaySeconds + remainingSeconds
end

local function createEmitterPart(worldCFrame: CFrame, parent: Instance?): BasePart
	local emitterPart = Instance.new("Part")
	emitterPart.Name = SFX_EMITTER_NAME
	emitterPart.Anchored = true
	emitterPart.CanCollide = false
	emitterPart.CanTouch = false
	emitterPart.CanQuery = false
	emitterPart.CastShadow = false
	emitterPart.Massless = true
	emitterPart.Size = Vector3.new(0.2, 0.2, 0.2)
	emitterPart.Transparency = 1
	emitterPart.CFrame = worldCFrame
	emitterPart.Parent = parent or Workspace
	return emitterPart
end

local function scheduleConfiguredPlayback(soundClone: Sound, sourceSound: Sound, playbackOptions)
	local delaySeconds = 0
	if playbackOptions.includeDelay then
		delaySeconds = math.max(0, getNumberAttribute(sourceSound, "Delay", "Start") or 0)
	end
	delaySeconds = math.max(0, delaySeconds + (playbackOptions.delayOffsetSeconds or 0))

	local function playNow()
		if soundClone.Parent == nil then
			return
		end

		BossFightSfxUtil.ApplyArenaBroadcast(soundClone, playbackOptions)
		soundClone.TimePosition = resolveSourceStart(sourceSound, playbackOptions.useConfiguredStartPosition)
		soundClone:Play()

		if playbackOptions.useConfiguredEndPosition then
			local sourceEnd = getNumberAttribute(sourceSound, "SourceEnd", "End")
			if sourceEnd ~= nil and sourceEnd > 0 then
				local stopDelay = math.max(0, sourceEnd - soundClone.TimePosition)
					/ math.max(0.001, tonumber(soundClone.PlaybackSpeed) or 1)
				task.delay(stopDelay, function()
					if soundClone.Parent ~= nil and soundClone.IsPlaying then
						soundClone:Stop()
					end
				end)
			end
		end
	end

	if delaySeconds > 0 then
		task.delay(delaySeconds, playNow)
	else
		playNow()
	end
end

function BossFightSfxUtil.ResolveArenaBroadcastSettings(arenaModel: Model?)
	local resolvedArenaModel = resolveArenaModel(arenaModel)
	if resolvedArenaModel == nil then
		return nil
	end

	local boundingSize = resolveArenaBoundingSize(resolvedArenaModel)
	if boundingSize == nil then
		return nil
	end

	local horizontalSpan = math.max(tonumber(boundingSize.X) or 0, tonumber(boundingSize.Z) or 0)
	if horizontalSpan <= 0.001 then
		return nil
	end

	local arenaRadius = horizontalSpan * 0.5
	return {
		arenaModel = resolvedArenaModel,
		arenaRadius = arenaRadius,
		emitterSize = arenaRadius,
		rollOffMinDistance = arenaRadius * 0.75,
		rollOffMaxDistance = arenaRadius * 1.35,
	}
end

function BossFightSfxUtil.ApplyArenaBroadcast(sound: Sound, options)
	if sound == nil then
		return nil
	end

	local resolvedScale = normalizeSoundScale(options and options.scaleMultiplier)
	local authoredEmitterSize = resolveBaseProperty(sound, SOUND_BASE_EMITTER_SIZE_ATTRIBUTE, "EmitterSize") * resolvedScale
	local authoredRollOffMinDistance =
		resolveBaseProperty(sound, SOUND_BASE_ROLL_OFF_MIN_DISTANCE_ATTRIBUTE, "RollOffMinDistance") * resolvedScale
	local authoredRollOffMaxDistance =
		resolveBaseProperty(sound, SOUND_BASE_ROLL_OFF_MAX_DISTANCE_ATTRIBUTE, "RollOffMaxDistance") * resolvedScale

	local arenaSettings = BossFightSfxUtil.ResolveArenaBroadcastSettings(options and options.arenaModel)
	if arenaSettings == nil then
		sound.EmitterSize = authoredEmitterSize
		sound.RollOffMinDistance = authoredRollOffMinDistance
		sound.RollOffMaxDistance = authoredRollOffMaxDistance
		return nil
	end

	sound.EmitterSize = math.max(authoredEmitterSize, arenaSettings.emitterSize)
	sound.RollOffMinDistance = math.max(authoredRollOffMinDistance, arenaSettings.rollOffMinDistance)
	sound.RollOffMaxDistance = math.max(authoredRollOffMaxDistance, arenaSettings.rollOffMaxDistance)
	return arenaSettings
end

function BossFightSfxUtil.PlayAtPosition(source: Instance, worldCFrameOrPosition: CFrame | Vector3, options)
	if source == nil then
		return nil
	end

	local worldCFrame = coerceWorldCFrame(worldCFrameOrPosition)
	if worldCFrame == nil then
		return nil
	end

	local playbackOptions = resolvePlaybackOptions(options)
	local sounds = collectSounds(source, playbackOptions.soundFilter)
	if #sounds <= 0 then
		return nil
	end

	local emitterPart = createEmitterPart(worldCFrame, playbackOptions.parent)
	local cleanupAfterSeconds = 0
	for _, sourceSound in ipairs(sounds) do
		local soundClone = sourceSound:Clone()
		soundClone.Parent = emitterPart
		cleanupAfterSeconds = math.max(cleanupAfterSeconds, resolvePlaybackWindow(sourceSound, playbackOptions))
		scheduleConfiguredPlayback(soundClone, sourceSound, playbackOptions)
	end

	task.delay(
		cleanupAfterSeconds + math.max(0, playbackOptions.cleanupPaddingSeconds or DEFAULT_CLEANUP_PADDING_SECONDS),
		function()
			if emitterPart.Parent ~= nil then
				emitterPart:Destroy()
			end
		end
	)

	return emitterPart
end

return table.freeze(BossFightSfxUtil)
