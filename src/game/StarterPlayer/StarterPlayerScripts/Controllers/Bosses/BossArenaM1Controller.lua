local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CameraShaker = require(ReplicatedStorage.Shared.Camera.CameraShaker)
local AnimationUtil = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Utilities.AnimationUtil)
local PlayerM1AnimationResolver = require(ReplicatedStorage.Shared.BossArena.PlayerM1AnimationResolver)
local PlayerM1Config = require(ReplicatedStorage.Shared.BossArena.PlayerM1Config)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local LOCAL_PLAYER = Players.LocalPlayer
local REMOTES_FOLDER_NAME = "Remotes"
local BOSS_ARENA_FOLDER_NAME = "BossArena"
local REQUEST_M1_REMOTE_NAME = "RequestPlayerM1"
local ACTIVE_PROFILE_ID = "boss_arena"
local M1_SEARCH_PATH_DESCRIPTION =
	"ReplicatedStorage.GameAssets.Animations.Bosses.M1 or ReplicatedStorage.GameAssets.Animations.M1"
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
	_predictedAnimationName = nil :: string?,
	_nextAnimationIndex = 0,
	_localCooldownEndsAt = nil :: number?,
	_activeTrackStoppedConnection = nil :: RBXScriptConnection?,
	_inputConnection = nil :: RBXScriptConnection?,
	_mobileAttackConnection = nil :: RBXScriptConnection?,
	_characterAddedConnection = nil :: RBXScriptConnection?,
	_remotes = nil :: RemoteFunction?,
	_cameraShaker = nil :: any,
	_warnedMissingMobileAttackButton = false,
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
end

local function warnWithPrefix(message: string)
	Logger.Warn(string.format("[BossArenaM1Controller] %s", message))
end

local function resolveHumanoid(character: Model?): Humanoid?
	if character == nil then
		return nil
	end

	return character:FindFirstChildOfClass("Humanoid")
end

local function normalizeAbilityName(value: string): string
	return string.lower(string.match(value, "^%s*(.-)%s*$") or "")
end

local function warnMissingM1FolderIfNeeded()
	if warnedMissingM1Folder ~= true then
		warnedMissingM1Folder = true
		warnWithPrefix(string.format("Could not resolve the M1 animation folder under %s.", M1_SEARCH_PATH_DESCRIPTION))
	end
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
	self._predictedAnimationName = nil
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

	local animationInstance = PlayerM1AnimationResolver.FindAnimation(animationName)
	if animationInstance then
		warnedMissingM1Folder = false
		return animationInstance
	end

	if PlayerM1AnimationResolver.ResolveFolder() == nil then
		warnMissingM1FolderIfNeeded()
		return nil
	end

	warnWithPrefix(string.format("Resolved M1 folder under %s, but animation '%s' was not found there.", M1_SEARCH_PATH_DESCRIPTION, animationName))

	return nil
end

local function getSortedM1Animations(): { Animation }
	local animations = {}
	for _, animation in ipairs(PlayerM1AnimationResolver.GetAnimations()) do
		table.insert(animations, animation)
	end

	if #animations <= 0 and PlayerM1AnimationResolver.ResolveFolder() == nil then
		warnMissingM1FolderIfNeeded()
		return animations
	end
	warnedMissingM1Folder = false

	table.sort(animations, function(left: Animation, right: Animation)
		return left.Name < right.Name
	end)

	return animations
end

function BossArenaM1Controller:_choosePredictedAnimation(): Animation?
	local animations = getSortedM1Animations()
	if #animations <= 0 then
		return nil
	end

	self._nextAnimationIndex += 1
	if self._nextAnimationIndex > #animations then
		self._nextAnimationIndex = 1
	end

	return animations[self._nextAnimationIndex]
end

function BossArenaM1Controller:_setActiveTrack(track: AnimationTrack, swingId: string?)
	self:_disconnectTrackStoppedConnection()

	self._activeTrack = track
	self._activeSwingId = swingId

	self._activeTrackStoppedConnection = track.Stopped:Connect(function()
		if self._activeTrack == track then
			self:_clearActiveSwing(false)
		end
	end)
end

function BossArenaM1Controller:_playSwingTrack(animationInstance: Animation, swingId: string?): AnimationTrack?
	local character = LOCAL_PLAYER.Character
	local humanoid = resolveHumanoid(character)
	if character == nil or humanoid == nil or humanoid.Health <= 0 then
		return nil
	end

	self:_clearActiveSwing(true)

	local track = AnimationUtil.play(character, humanoid, animationInstance, PlayerM1Config.AnimationFadeSeconds, 1)
	if track == nil then
		warnWithPrefix(string.format("Failed to play M1 animation '%s'.", animationInstance.Name))
		return nil
	end

	track.Looped = false
	self:_setActiveTrack(track, swingId)

	return track
end

function BossArenaM1Controller:_playPredictedSwing(): string?
	local animationInstance = self:_choosePredictedAnimation()
	if animationInstance == nil then
		return nil
	end

	local track = self:_playSwingTrack(animationInstance, nil)
	if track then
		self._predictedAnimationName = animationInstance.Name
	end

	return animationInstance.Name
end

function BossArenaM1Controller:_bindApprovedImpact(track: AnimationTrack, response: RequestPlayerM1Response)
	local impactTriggered = false
	local function handleImpact()
		if impactTriggered then
			return
		end

		impactTriggered = true
		self:_shakeImpact()
	end

	local character = LOCAL_PLAYER.Character
	if character == nil then
		return
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
end

function BossArenaM1Controller:_applyApprovedCooldown(response: RequestPlayerM1Response)
	local cooldownSeconds = if typeof(response.cooldownSeconds) == "number" then response.cooldownSeconds else nil
	if cooldownSeconds == nil then
		return
	end

	local serverStartedAt = if typeof(response.serverStartedAt) == "number" then response.serverStartedAt else nil
	if serverStartedAt ~= nil then
		self._localCooldownEndsAt = serverStartedAt + cooldownSeconds
	else
		self._localCooldownEndsAt = Workspace:GetServerTimeNow() + cooldownSeconds
	end
end

function BossArenaM1Controller:_applyFailureCooldown(response: any)
	if typeof(response) ~= "table" then
		return
	end

	local retryAfterSeconds = if typeof(response.retryAfterSeconds) == "number" then response.retryAfterSeconds else nil
	if retryAfterSeconds ~= nil and retryAfterSeconds > 0 then
		self._localCooldownEndsAt = Workspace:GetServerTimeNow() + retryAfterSeconds
	end
end

function BossArenaM1Controller:_playApprovedSwing(response: RequestPlayerM1Response)
	local animationInstance = self:_resolveAnimationInstance(response.animationName)
	if animationInstance == nil then
		warnWithPrefix(string.format("Missing local M1 animation '%s'.", tostring(response.animationName)))
		self:_clearActiveSwing(true)
		return
	end

	self:_applyApprovedCooldown(response)

	local track = nil :: AnimationTrack?
	if self._activeTrack and self._predictedAnimationName == animationInstance.Name then
		track = self._activeTrack
		self._activeSwingId = response.swingId
		self._predictedAnimationName = nil
	else
		track = self:_playSwingTrack(animationInstance, response.swingId)
	end

	if track == nil then
		return
	end

	self:_bindApprovedImpact(track, response)
end

function BossArenaM1Controller:_requestAttack()
	local now = Workspace:GetServerTimeNow()
	if self._localCooldownEndsAt ~= nil and now < self._localCooldownEndsAt then
		return
	end

	if self._requestInFlight or self._activeSwingId ~= nil or self._activeTrack ~= nil then
		return
	end

	self._requestInFlight = true
	local predictedAnimationName = self:_playPredictedSwing()

	local requestRemote = self:_ensureRemote()
	if not requestRemote then
		self._requestInFlight = false
		self:_clearActiveSwing(true)
		return
	end

	local ok, response = pcall(function()
		return requestRemote:InvokeServer(predictedAnimationName)
	end)
	self._requestInFlight = false

	if not ok then
		warnWithPrefix(string.format("RequestPlayerM1 failed: %s", tostring(response)))
		self:_clearActiveSwing(true)
		return
	end

	if typeof(response) ~= "table" or response.ok ~= true then
		self:_applyFailureCooldown(response)
		self:_clearActiveSwing(true)
		return
	end

	self:_playApprovedSwing(response)
end

function BossArenaM1Controller:RequestAttack()
	self:_requestAttack()
end

function BossArenaM1Controller:_bindCharacterLifecycle()
	if self._characterAddedConnection then
		self._characterAddedConnection:Disconnect()
	end

	self._characterAddedConnection = LOCAL_PLAYER.CharacterAdded:Connect(function()
		self:_clearActiveSwing(true)
	end)
end

function BossArenaM1Controller:_resolveMobileAttackButton(): GuiButton?
	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	local mainInterface = playerGui:WaitForChild("MainInterface", 30)
	if not (mainInterface and mainInterface:IsA("ScreenGui")) then
		return nil
	end

	local combatHud = mainInterface:WaitForChild("CombatHUD", 30)
	if not (combatHud and combatHud:IsA("Frame")) then
		return nil
	end

	local mobileControls = combatHud:WaitForChild("MobileControls", 30)
	if not (mobileControls and mobileControls:IsA("Frame")) then
		return nil
	end

	for _, descendant in ipairs(mobileControls:GetDescendants()) do
		if not descendant:IsA("GuiButton") then
			continue
		end

		local abilityName = descendant:FindFirstChild("AbilityName")
		if not (abilityName and abilityName:IsA("TextLabel")) then
			continue
		end

		if normalizeAbilityName(abilityName.Text) == "attack" then
			return descendant
		end
	end

	return nil
end

function BossArenaM1Controller:_bindMobileAttackButton()
	if self._mobileAttackConnection then
		self._mobileAttackConnection:Disconnect()
		self._mobileAttackConnection = nil
	end

	local attackButton = self:_resolveMobileAttackButton()
	if attackButton == nil then
		if self._warnedMissingMobileAttackButton ~= true then
			self._warnedMissingMobileAttackButton = true
			warnWithPrefix("CombatHUD.MobileControls attack button was not found; mobile attack input is unavailable.")
		end
		return
	end

	self._warnedMissingMobileAttackButton = false
	self._mobileAttackConnection = attackButton.Activated:Connect(function()
		self:RequestAttack()
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
	self:_bindMobileAttackButton()

	self._inputConnection = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
		if gameProcessedEvent then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		self:RequestAttack()
	end)
end

return BossArenaM1Controller
