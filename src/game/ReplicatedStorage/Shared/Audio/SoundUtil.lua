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

function SoundUtil.Play(soundOrName, parent: Instance?): Sound?
	local baseSound = resolveBaseSound(soundOrName)
	if not baseSound then
		return nil
	end

	local clone = baseSound:Clone()
	clone.Looped = false
	clone.TimePosition = 0
	clone.Parent = parent or SoundService

	local cleanup = createCleanup(clone)

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

return SoundUtil
