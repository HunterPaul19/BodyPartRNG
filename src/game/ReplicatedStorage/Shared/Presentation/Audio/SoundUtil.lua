local SoundService = game:GetService("SoundService")

local SoundUtil = {}
local cleanupBySound = setmetatable({}, { __mode = "k" })

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
		endedConnection = clone.Ended:Connect(function()
			if endedConnection then
				endedConnection:Disconnect()
				endedConnection = nil
			end

			cleanup()
		end)

		clone:Play()

		task.delay(math.max(1, tonumber(clone.TimeLength) or 0, (tonumber(clone.TimeLength) or 0) + 0.25), function()
			if endedConnection then
				endedConnection:Disconnect()
				endedConnection = nil
			end

			cleanup()
		end)

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
