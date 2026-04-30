local SoundService = game:GetService("SoundService")

local SoundUtil = {}
local cleanupBySound = setmetatable({}, { __mode = "k" })
local ONE_SHOT_FALLBACK_CLEANUP_DELAY = 30
local DEFAULT_SOUND_DURATION_LOAD_TIMEOUT = 2

local function resolveBaseSound(soundOrName)
	if typeof(soundOrName) == "Instance" and soundOrName:IsA("Sound") then
		return soundOrName
	end

	if typeof(soundOrName) ~= "string" or soundOrName == "" then
		return nil
	end

	local direct = SoundService:FindFirstChild(soundOrName)
	if direct and direct:IsA("Sound") then
		return direct
	end

	local nested = SoundService:FindFirstChild(soundOrName, true)
	if nested and nested:IsA("Sound") then
		return nested
	end

	return nil
end

local function resolvePlaybackParent(baseSound: Sound, parent: Instance?): Instance
	if parent then
		return parent
	end

	local baseParent = baseSound.Parent
	if baseParent and baseParent:IsA("SoundGroup") then
		return baseParent
	end

	return SoundService
end

local function readPositiveTimeLength(sound: Sound): number?
	local timeLength = tonumber(sound.TimeLength) or 0
	if timeLength > 0 then
		return timeLength
	end

	return nil
end

local function waitForSoundLoaded(sound: Sound, timeoutSeconds: number)
	if sound.IsLoaded then
		return
	end

	local finishedEvent = Instance.new("BindableEvent")
	local finished = false
	local loadedConnection: RBXScriptConnection? = nil

	local function finish()
		if finished then
			return
		end

		finished = true
		finishedEvent:Fire()
	end

	loadedConnection = sound.Loaded:Connect(finish)
	task.delay(timeoutSeconds, finish)
	if not finished then
		finishedEvent.Event:Wait()
	end

	if loadedConnection then
		loadedConnection:Disconnect()
	end
	finishedEvent:Destroy()
end

local function createCleanup(sound: Sound)
	local cleanedUp = false

	local function cleanup()
		if cleanedUp then
			return
		end

		cleanedUp = true
		cleanupBySound[sound] = nil

		if sound.Parent then
			sound:Destroy()
		end
	end

	cleanupBySound[sound] = cleanup
	return cleanup
end

local function playClone(soundOrName, parent: Instance?, looped: boolean): Sound?
	local baseSound = resolveBaseSound(soundOrName)
	if not baseSound then
		return nil
	end

	local clone = baseSound:Clone()
	clone.Looped = looped == true
	clone.TimePosition = 0
	clone.Parent = resolvePlaybackParent(baseSound, parent)

	local cleanup = createCleanup(clone)

	if not looped then
		local endedConnection: RBXScriptConnection? = nil
		local loadedConnection: RBXScriptConnection? = nil
		local cleanupToken = 0

		local function disconnectCleanupSignals()
			if endedConnection then
				endedConnection:Disconnect()
				endedConnection = nil
			end
			if loadedConnection then
				loadedConnection:Disconnect()
				loadedConnection = nil
			end
		end

		local function scheduleCleanup(delaySeconds: number)
			cleanupToken += 1
			local token = cleanupToken

			task.delay(delaySeconds, function()
				if token ~= cleanupToken then
					return
				end

				disconnectCleanupSignals()
				cleanup()
			end)
		end

		endedConnection = clone.Ended:Connect(function()
			disconnectCleanupSignals()
			cleanup()
		end)

		clone:Play()

		local timeLength = tonumber(clone.TimeLength) or 0
		if timeLength > 0 then
			scheduleCleanup(timeLength + 0.25)
		elseif clone.IsLoaded then
			scheduleCleanup(ONE_SHOT_FALLBACK_CLEANUP_DELAY)
		else
			loadedConnection = clone.Loaded:Connect(function()
				local loadedTimeLength = tonumber(clone.TimeLength) or 0
				if loadedTimeLength > 0 then
					scheduleCleanup(loadedTimeLength + 0.25)
				end
			end)
			scheduleCleanup(ONE_SHOT_FALLBACK_CLEANUP_DELAY)
		end

		return clone
	end

	clone:Play()

	return clone
end

function SoundUtil.Play(soundOrName, parent: Instance?): Sound?
	return playClone(soundOrName, parent, false)
end

function SoundUtil.PlayLooped(soundOrName, parent: Instance?): Sound?
	return playClone(soundOrName, parent, true)
end

function SoundUtil.GetDuration(soundOrName, loadTimeoutSeconds: number?): number?
	local baseSound = resolveBaseSound(soundOrName)
	if not baseSound then
		return nil
	end

	local duration = readPositiveTimeLength(baseSound)
	if duration then
		return duration
	end

	local resolvedTimeout = math.max(0, tonumber(loadTimeoutSeconds) or DEFAULT_SOUND_DURATION_LOAD_TIMEOUT)
	if resolvedTimeout > 0 then
		waitForSoundLoaded(baseSound, resolvedTimeout)
		return readPositiveTimeLength(baseSound)
	end

	return nil
end

function SoundUtil.Stop(sound: Sound?)
	if not (sound and sound:IsA("Sound")) then
		return
	end

	local cleanup = cleanupBySound[sound]
	sound:Stop()

	if cleanup then
		cleanup()
	elseif sound.Parent then
		sound:Destroy()
	end
end

return SoundUtil
