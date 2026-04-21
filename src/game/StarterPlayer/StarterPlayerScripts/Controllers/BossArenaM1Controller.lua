local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CameraShaker = require(ReplicatedStorage.Shared.Camera.CameraShaker)
local AnimationUtil = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Utilities.AnimationUtil)
local PlayerM1Config = require(ReplicatedStorage.Shared.BossArena.PlayerM1Config)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local LOCAL_PLAYER = Players.LocalPlayer
local REMOTES_FOLDER_NAME = "Remotes"
local BOSS_ARENA_FOLDER_NAME = "BossArena"
local REQUEST_M1_REMOTE_NAME = "RequestPlayerM1"
local ACTIVE_PROFILE_ID = "boss_arena"
local warnedMissingM1Folder = false

type RequestPlayerM1Response = {
	ok: boolean,
	swingId: string?,
	animationName: string?,
	serverStartedAt: number?,
	impactDelaySeconds: number?,
	cooldownSeconds: number?,
	code: string?,
	retryAfterSeconds: number?,
}

local BossArenaM1Controller = {
	_started = false,
	_requestInFlight = false,
	_activeSwingId = nil :: string?,
	_activeTrack = nil :: AnimationTrack?,
	_activeTrackStoppedConnection = nil :: RBXScriptConnection?,
	_inputConnection = nil :: RBXScriptConnection?,
	_characterAddedConnection = nil :: RBXScriptConnection?,
	_remotes = nil :: RemoteFunction?,
	_cameraShaker = nil :: any,
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
end

local function warnWithPrefix(message: string)
	warn(string.format("[BossArenaM1Controller] %s", message))
end

local function resolveHumanoid(character: Model?): Humanoid?
	if character == nil then
		return nil
	end

	return character:FindFirstChildOfClass("Humanoid")
end

local function resolveAnimationFolder(): Folder?
	local assetContainer = AnimationUtil.getPathingFolders()
	if not assetContainer then
		return nil
	end

	local candidateContainers = { assetContainer }
	local nestedAssets = assetContainer:FindFirstChild("Assets")
	if nestedAssets then
		table.insert(candidateContainers, nestedAssets)
	end

	for _, container in ipairs(candidateContainers) do
		local animationsFolder = nil
		if container:IsA("Folder") and container.Name == "Animations" then
			animationsFolder = container
		else
			local candidate = container:FindFirstChild("Animations")
			if candidate and candidate:IsA("Folder") then
				animationsFolder = candidate
			end
		end

		if animationsFolder then
			local folder = animationsFolder:FindFirstChild("M1")
			if folder and folder:IsA("Folder") then
				warnedMissingM1Folder = false
				return folder
			end
		end
	end

	if warnedMissingM1Folder ~= true then
		warnedMissingM1Folder = true
		warnWithPrefix("Could not resolve the M1 animation folder under the primary animation asset container.")
	end

	return nil
end

function BossArenaM1Controller:_disconnectTrackStoppedConnection()
	if self._activeTrackStoppedConnection and self._activeTrackStoppedConnection.Connected then
		self._activeTrackStoppedConnection:Disconnect()
	end

	self._activeTrackStoppedConnection = nil
end

function BossArenaM1Controller:_clearActiveSwing(stopTrack: boolean?)
	self:_disconnectTrackStoppedConnection()

	if stopTrack == true and self._activeTrack then
		pcall(function()
			self._activeTrack:Stop(PlayerM1Config.AnimationFadeSeconds)
		end)
	end

	self._activeTrack = nil
	self._activeSwingId = nil
end

function BossArenaM1Controller:_ensureCameraShaker()
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

function BossArenaM1Controller:_shakeImpact()
	self:_ensureCameraShaker():ShakeOnce(
		PlayerM1Config.ScreenShakeMagnitude,
		PlayerM1Config.ScreenShakeRoughness,
		PlayerM1Config.ScreenShakeFadeIn,
		PlayerM1Config.ScreenShakeFadeOut
	)
end

function BossArenaM1Controller:_ensureRemote(): RemoteFunction?
	if self._remotes then
		return self._remotes
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

	local requestRemote = bossArenaFolder:WaitForChild(REQUEST_M1_REMOTE_NAME, 30)
	if not (requestRemote and requestRemote:IsA("RemoteFunction")) then
		warnWithPrefix("BossArena.RequestPlayerM1 is missing.")
		return nil
	end

	self._remotes = requestRemote
	return requestRemote
end

function BossArenaM1Controller:_resolveAnimationInstance(animationName: string?): Animation?
	if typeof(animationName) ~= "string" or animationName == "" then
		return nil
	end

	local folder = resolveAnimationFolder()
	if not folder then
		return nil
	end

	local animationInstance = folder:FindFirstChild(animationName)
	if animationInstance and animationInstance:IsA("Animation") then
		return animationInstance
	end

	warnWithPrefix(string.format("Resolved M1 folder, but animation '%s' was not found there.", animationName))

	return nil
end

function BossArenaM1Controller:_playApprovedSwing(response: RequestPlayerM1Response)
	local animationInstance = self:_resolveAnimationInstance(response.animationName)
	if animationInstance == nil then
		warnWithPrefix(string.format("Missing local M1 animation '%s'.", tostring(response.animationName)))
		return
	end

	local character = LOCAL_PLAYER.Character
	local humanoid = resolveHumanoid(character)
	if character == nil or humanoid == nil or humanoid.Health <= 0 then
		return
	end

	self:_clearActiveSwing(true)

	local track = AnimationUtil.play(character, humanoid, animationInstance, PlayerM1Config.AnimationFadeSeconds, 1)
	if track == nil then
		warnWithPrefix(string.format("Failed to play M1 animation '%s'.", animationInstance.Name))
		return
	end

	track.Looped = false
	self._activeTrack = track
	self._activeSwingId = response.swingId

	local impactTriggered = false
	local function handleImpact()
		if impactTriggered then
			return
		end

		impactTriggered = true
		self:_shakeImpact()
	end

	local profile = Animation.GetProfile(character)
	if profile == nil then
		local ok, resolvedProfile = pcall(Animation.new, character)
		if ok then
			profile = resolvedProfile
		end
	end

	if profile then
		profile:BindEventMarkers(track, {
			Impact = handleImpact,
		})
	end

	local impactDelaySeconds = if typeof(response.impactDelaySeconds) == "number" then response.impactDelaySeconds else nil
	local serverStartedAt = if typeof(response.serverStartedAt) == "number" then response.serverStartedAt else nil
	if serverStartedAt ~= nil then
		local elapsed = math.max(0, Workspace:GetServerTimeNow() - serverStartedAt)
		if impactDelaySeconds ~= nil and elapsed >= impactDelaySeconds then
			handleImpact()
		end

		if elapsed > 0 then
			task.defer(function()
				if self._activeTrack ~= track then
					return
				end

				local targetTime = elapsed
				local safeTrackLength = math.max(0, track.Length - 0.03)
				if safeTrackLength > 0 then
					targetTime = math.clamp(targetTime, 0, safeTrackLength)
				end

				pcall(function()
					track.TimePosition = targetTime
				end)
			end)
		end
	end

	self._activeTrackStoppedConnection = track.Stopped:Connect(function()
		if self._activeTrack == track then
			self:_clearActiveSwing(false)
		end
	end)
end

function BossArenaM1Controller:_requestAttack()
	if self._requestInFlight or self._activeSwingId ~= nil then
		return
	end

	local requestRemote = self:_ensureRemote()
	if not requestRemote then
		return
	end

	self._requestInFlight = true
	local ok, response = pcall(function()
		return requestRemote:InvokeServer()
	end)
	self._requestInFlight = false

	if not ok then
		warnWithPrefix(string.format("RequestPlayerM1 failed: %s", tostring(response)))
		return
	end

	if typeof(response) ~= "table" or response.ok ~= true then
		return
	end

	self:_playApprovedSwing(response)
end

function BossArenaM1Controller:_bindCharacterLifecycle()
	if self._characterAddedConnection then
		self._characterAddedConnection:Disconnect()
	end

	self._characterAddedConnection = LOCAL_PLAYER.CharacterAdded:Connect(function()
		self:_clearActiveSwing(true)
	end)
end

function BossArenaM1Controller:OnStart()
	if self._started then
		return
	end
	self._started = true

	if not isEnabledForPlace() then
		return
	end

	self:_ensureCameraShaker()
	self:_bindCharacterLifecycle()

	self._inputConnection = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
		if gameProcessedEvent then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		self:_requestAttack()
	end)
end

return BossArenaM1Controller
