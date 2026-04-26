local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LOCAL_PLAYER = Players.LocalPlayer
local BUILD_LOCK_ATTRIBUTE = "BodyPartBuildLocked"

local BodyPartBuildLockController = {}

local function getPlayingAnimationTracks(humanoid: Humanoid?, animator: Animator?): { AnimationTrack }
	local tracks = {}
	local seen = {}

	local function addTrack(track: AnimationTrack)
		if track and seen[track] ~= true then
			seen[track] = true
			table.insert(tracks, track)
		end
	end

	if animator then
		local success, animatorTracks = pcall(function()
			return animator:GetPlayingAnimationTracks()
		end)
		if success and animatorTracks then
			for _, track in ipairs(animatorTracks) do
				addTrack(track)
			end
		end
	end

	if humanoid then
		local success, humanoidTracks = pcall(function()
			return humanoid:GetPlayingAnimationTracks()
		end)
		if success and humanoidTracks then
			for _, track in ipairs(humanoidTracks) do
				addTrack(track)
			end
		end
	end

	return tracks
end

local function stopPlayingAnimationTracks(humanoid: Humanoid?, animator: Animator?)
	for _, track in ipairs(getPlayingAnimationTracks(humanoid, animator)) do
		pcall(function()
			track:Stop(0)
		end)
	end
end

local function resetMotorTransforms(character: Model)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("Motor6D") then
			descendant.Transform = CFrame.new()
		end
	end
end

local function neutralizeCharacterPose(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator") or nil
	stopPlayingAnimationTracks(humanoid, animator)
	resetMotorTransforms(character)
end

function BodyPartBuildLockController:_disconnectLockHeartbeat()
	if self._lockHeartbeatConnection then
		self._lockHeartbeatConnection:Disconnect()
		self._lockHeartbeatConnection = nil
	end
end

function BodyPartBuildLockController:_restoreAnimateScript(character: Model)
	local animateScript = character:FindFirstChild("Animate")
	if animateScript and animateScript:IsA("LocalScript") and self._animateWasEnabled ~= nil then
		animateScript.Enabled = self._animateWasEnabled
	end

	self._animateWasEnabled = nil
end

function BodyPartBuildLockController:_disableAnimateScript(character: Model)
	local animateScript = character:FindFirstChild("Animate")
	if animateScript and animateScript:IsA("LocalScript") then
		if self._animateWasEnabled == nil then
			self._animateWasEnabled = animateScript.Enabled
		end

		animateScript.Enabled = false
	end
end

function BodyPartBuildLockController:_applyCharacterLockState(character: Model)
	local isLocked = character:GetAttribute(BUILD_LOCK_ATTRIBUTE) == true
	if isLocked then
		self:_disableAnimateScript(character)
		neutralizeCharacterPose(character)

		if self._lockHeartbeatConnection == nil then
			self._lockHeartbeatConnection = RunService.Heartbeat:Connect(function()
				if self._character ~= character or character.Parent == nil then
					self:_disconnectLockHeartbeat()
					return
				end

				if character:GetAttribute(BUILD_LOCK_ATTRIBUTE) == true then
					self:_disableAnimateScript(character)
					neutralizeCharacterPose(character)
				else
					self:_disconnectLockHeartbeat()
					self:_restoreAnimateScript(character)
				end
			end)
		end
		return
	end

	self:_disconnectLockHeartbeat()
	self:_restoreAnimateScript(character)
end

function BodyPartBuildLockController:_bindCharacter(character: Model)
	if self._characterAttributeConnection then
		self._characterAttributeConnection:Disconnect()
		self._characterAttributeConnection = nil
	end

	self:_disconnectLockHeartbeat()

	if self._character and self._character.Parent then
		self:_restoreAnimateScript(self._character)
	end

	self._character = character
	self._animateWasEnabled = nil

	self._characterAttributeConnection = character:GetAttributeChangedSignal(BUILD_LOCK_ATTRIBUTE):Connect(function()
		self:_applyCharacterLockState(character)
	end)

	self:_applyCharacterLockState(character)
end

function BodyPartBuildLockController:OnStart()
	self._character = nil
	self._characterAttributeConnection = nil
	self._lockHeartbeatConnection = nil
	self._animateWasEnabled = nil

	LOCAL_PLAYER.CharacterAdded:Connect(function(character)
		self:_bindCharacter(character)
	end)

	local character = LOCAL_PLAYER.Character
	if character then
		self:_bindCharacter(character)
	end
end

return BodyPartBuildLockController
