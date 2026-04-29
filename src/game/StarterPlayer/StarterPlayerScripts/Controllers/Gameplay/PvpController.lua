local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CombatSoundUtil = require(ReplicatedStorage.Shared.Audio.CombatSoundUtil)
local AnimationUtil = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Utilities.AnimationUtil)
local CameraShaker = require(ReplicatedStorage.Shared.Camera.CameraShaker)
local PlayerM1AnimationResolver = require(ReplicatedStorage.Shared.BossArena.PlayerM1AnimationResolver)
local PlayerM1Config = require(ReplicatedStorage.Shared.BossArena.PlayerM1Config)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)
local Signal = require(ReplicatedStorage.Common.Signal)
local ToggleSoundUtil = require(ReplicatedStorage.Shared.Audio.ToggleSoundUtil)

local LOCAL_PLAYER = Players.LocalPlayer
local ACTIVE_PROFILE_ID = "main"
local REMOTES_FOLDER_NAME = "Remotes"
local PVP_FOLDER_NAME = "PvP"
local GET_PVP_STATE_REMOTE_NAME = "GetPvpState"
local SET_PVP_ENABLED_REMOTE_NAME = "SetPvpEnabled"
local REQUEST_M1_REMOTE_NAME = "RequestPlayerM1"
local PVP_STATE_CHANGED_REMOTE_NAME = "PvpStateChanged"
local M1_SEARCH_PATH_DESCRIPTION =
	"ReplicatedStorage.GameAssets.Animations.Bosses.M1 or ReplicatedStorage.GameAssets.Animations.M1"
local warnedMissingM1Folder = false

type PvpRemotes = {
	getState: RemoteFunction,
	setEnabled: RemoteFunction,
	requestM1: RemoteFunction,
	stateChanged: RemoteEvent,
}

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

local PvpController = {
	EnabledChanged = Signal.new(),
	_started = false,
	_enabled = false,
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
	_stateChangedConnection = nil :: RBXScriptConnection?,
	_toggleConnection = nil :: RBXScriptConnection?,
	_remotes = nil :: PvpRemotes?,
	_button = nil :: GuiButton?,
	_mobileAttackButton = nil :: GuiButton?,
	_usageLabel = nil :: TextLabel?,
	_cameraShaker = nil :: any,
	_warnedMissingMobileAttackButton = false,
	_remoteBindingStarted = false,
	_uiBindingStarted = false,
	_mobileAttackBindingStarted = false,
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
end

local function warnWithPrefix(message: string)
	Logger.Warn(string.format("[PvpController] %s", message))
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

function PvpController:_ensureUi(): boolean
	if self._button and self._button.Parent ~= nil then
		return true
	end

	local playerGui = LOCAL_PLAYER:FindFirstChild("PlayerGui")
	if not (playerGui and playerGui:IsA("PlayerGui")) then
		return false
	end

	local mainInterface = playerGui:FindFirstChild("MainInterface")
	if not (mainInterface and mainInterface:IsA("ScreenGui")) then
		return false
	end

	local main = mainInterface:FindFirstChild("Main")
	if not (main and main:IsA("Frame")) then
		return false
	end

	local button = main:FindFirstChild("PVP")
	if not (button and button:IsA("GuiButton")) then
		return false
	end

	local usageLabel = button:FindFirstChild("Usage")
	self._button = button
	self._usageLabel = if usageLabel and usageLabel:IsA("TextLabel") then usageLabel else nil
	ToggleSoundUtil.MarkToggleButton(button)
	self:_renderButtonState()
	return true
end

function PvpController:_renderButtonState()
	if self._usageLabel then
		self._usageLabel.Text = if self._enabled then "PVP: ON" else "PVP: OFF"
	end
end

function PvpController:IsPvpEnabled(): boolean
	return self._enabled == true
end

function PvpController:_ensureRemotes(): PvpRemotes?
	if self._remotes then
		return self._remotes
	end

	local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if not (remotesFolder and remotesFolder:IsA("Folder")) then
		return nil
	end

	local pvpFolder = remotesFolder:FindFirstChild(PVP_FOLDER_NAME)
	if not (pvpFolder and pvpFolder:IsA("Folder")) then
		return nil
	end

	local getState = pvpFolder:FindFirstChild(GET_PVP_STATE_REMOTE_NAME)
	local setEnabled = pvpFolder:FindFirstChild(SET_PVP_ENABLED_REMOTE_NAME)
	local requestM1 = pvpFolder:FindFirstChild(REQUEST_M1_REMOTE_NAME)
	local stateChanged = pvpFolder:FindFirstChild(PVP_STATE_CHANGED_REMOTE_NAME)

	if not (getState and getState:IsA("RemoteFunction")) then
		warnWithPrefix("PvP.GetPvpState is missing.")
		return nil
	end
	if not (setEnabled and setEnabled:IsA("RemoteFunction")) then
		warnWithPrefix("PvP.SetPvpEnabled is missing.")
		return nil
	end
	if not (requestM1 and requestM1:IsA("RemoteFunction")) then
		warnWithPrefix("PvP.RequestPlayerM1 is missing.")
		return nil
	end
	if not (stateChanged and stateChanged:IsA("RemoteEvent")) then
		warnWithPrefix("PvP.PvpStateChanged is missing.")
		return nil
	end

	self._remotes = {
		getState = getState,
		setEnabled = setEnabled,
		requestM1 = requestM1,
		stateChanged = stateChanged,
	}

	return self._remotes
end

function PvpController:_disconnectTrackStoppedConnection()
	if self._activeTrackStoppedConnection and self._activeTrackStoppedConnection.Connected then
		self._activeTrackStoppedConnection:Disconnect()
	end

	self._activeTrackStoppedConnection = nil
end

function PvpController:_clearActiveSwing(stopTrack: boolean?)
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

function PvpController:_applyState(state: any)
	local enabled = typeof(state) == "table" and state.enabled == true
	local previousEnabled = self._enabled == true
	self._enabled = enabled
	if not enabled then
		self:_clearActiveSwing(true)
	end

	self:_renderButtonState()
	self:_updateMobileAttackButtonState()
	if enabled ~= previousEnabled then
		self.EnabledChanged:Fire(enabled)
	end
end

function PvpController:_refreshState()
	local remotes = self:_ensureRemotes()
	if not remotes then
		return
	end

	local ok, result = pcall(function()
		return remotes.getState:InvokeServer()
	end)
	if not ok then
		warnWithPrefix(string.format("GetPvpState failed: %s", tostring(result)))
		return
	end

	self:_applyState(result)
end

function PvpController:_ensureCameraShaker()
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

function PvpController:_shakeImpact()
	self:_ensureCameraShaker():ShakeOnce(
		PlayerM1Config.ScreenShakeMagnitude,
		PlayerM1Config.ScreenShakeRoughness,
		PlayerM1Config.ScreenShakeFadeIn,
		PlayerM1Config.ScreenShakeFadeOut
	)
end

function PvpController:_choosePredictedAnimation(): Animation?
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

function PvpController:_resolveAnimationInstance(animationName: string?): Animation?
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

function PvpController:_setActiveTrack(track: AnimationTrack, swingId: string?)
	self:_disconnectTrackStoppedConnection()

	self._activeTrack = track
	self._activeSwingId = swingId

	self._activeTrackStoppedConnection = track.Stopped:Connect(function()
		if self._activeTrack == track then
			self:_clearActiveSwing(false)
		end
	end)
end

function PvpController:_playSwingTrack(animationInstance: Animation, swingId: string?): AnimationTrack?
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

function PvpController:_playPredictedSwing(): string?
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

function PvpController:_bindApprovedImpact(track: AnimationTrack, response: RequestPlayerM1Response)
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

function PvpController:_applyApprovedCooldown(response: RequestPlayerM1Response)
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

function PvpController:_applyFailureCooldown(response: any)
	if typeof(response) ~= "table" then
		return
	end

	local retryAfterSeconds = if typeof(response.retryAfterSeconds) == "number" then response.retryAfterSeconds else nil
	if retryAfterSeconds ~= nil and retryAfterSeconds > 0 then
		self._localCooldownEndsAt = Workspace:GetServerTimeNow() + retryAfterSeconds
	end
end

function PvpController:_playApprovedSwing(response: RequestPlayerM1Response)
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

	CombatSoundUtil.PlayLocalSwing()
	self:_bindApprovedImpact(track, response)
end

function PvpController:_requestAttack()
	if self._enabled ~= true then
		return
	end

	local now = Workspace:GetServerTimeNow()
	if self._localCooldownEndsAt ~= nil and now < self._localCooldownEndsAt then
		return
	end

	if self._requestInFlight or self._activeSwingId ~= nil or self._activeTrack ~= nil then
		return
	end

	self._requestInFlight = true
	local predictedAnimationName = self:_playPredictedSwing()

	local remotes = self:_ensureRemotes()
	if not remotes then
		self._requestInFlight = false
		self:_clearActiveSwing(true)
		return
	end

	local ok, response = pcall(function()
		return remotes.requestM1:InvokeServer(predictedAnimationName)
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

function PvpController:RequestAttack()
	self:_requestAttack()
end

function PvpController:_resolveMobileAttackButton(): GuiButton?
	local playerGui = LOCAL_PLAYER:FindFirstChild("PlayerGui")
	if not (playerGui and playerGui:IsA("PlayerGui")) then
		return nil
	end

	local mainInterface = playerGui:FindFirstChild("MainInterface")
	if not (mainInterface and mainInterface:IsA("ScreenGui")) then
		return nil
	end

	local combatHud = mainInterface:FindFirstChild("CombatHUD")
	if not (combatHud and combatHud:IsA("Frame")) then
		return nil
	end

	local mobileControls = combatHud:FindFirstChild("MobileControls")
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

function PvpController:_bindMobileAttackButton()
	local attackButton = self:_resolveMobileAttackButton()
	if attackButton == nil then
		if self._warnedMissingMobileAttackButton ~= true then
			self._warnedMissingMobileAttackButton = true
			warnWithPrefix("CombatHUD.MobileControls attack button was not found; mobile attack input is unavailable.")
		end
		return false
	end

	if self._mobileAttackButton == attackButton and self._mobileAttackConnection then
		self:_updateMobileAttackButtonState()
		return true
	end

	if self._mobileAttackConnection then
		self._mobileAttackConnection:Disconnect()
		self._mobileAttackConnection = nil
	end

	self._warnedMissingMobileAttackButton = false
	self._mobileAttackButton = attackButton
	self:_updateMobileAttackButtonState()
	self._mobileAttackConnection = attackButton.Activated:Connect(function()
		self:RequestAttack()
	end)

	return true
end

function PvpController:_updateMobileAttackButtonState()
	local attackButton = self._mobileAttackButton
	if attackButton == nil or attackButton.Parent == nil then
		self._mobileAttackButton = nil
		return
	end

	local enabled = self._enabled == true
	attackButton.Active = enabled
	attackButton.Selectable = enabled
	attackButton.AutoButtonColor = enabled
end

function PvpController:_startMobileAttackBinding()
	if self._mobileAttackBindingStarted then
		return
	end

	self._mobileAttackBindingStarted = true
	task.spawn(function()
		while self._started == true do
			if not self._mobileAttackButton or self._mobileAttackButton.Parent == nil or self._mobileAttackConnection == nil then
				self:_bindMobileAttackButton()
			else
				self:_updateMobileAttackButtonState()
			end

			task.wait(0.25)
		end
	end)
end

function PvpController:_bindToggleButton()
	if not self:_ensureUi() then
		return false
	end

	if self._toggleConnection then
		self._toggleConnection:Disconnect()
		self._toggleConnection = nil
	end
	if self._button == nil then
		return false
	end

	self._toggleConnection = self._button.Activated:Connect(function()
		local remotes = self:_ensureRemotes()
		if not remotes then
			return
		end

		local previousEnabled = self._enabled == true
		local ok, response = pcall(function()
			return remotes.setEnabled:InvokeServer({
				enabled = not previousEnabled,
			})
		end)

		if not ok then
			warnWithPrefix(string.format("SetPvpEnabled failed: %s", tostring(response)))
			return
		end

		if typeof(response) == "table" and typeof(response.state) == "table" then
			self:_applyState(response.state)
		else
			self:_refreshState()
		end

		if typeof(response) == "table" and response.ok == true and self._enabled ~= previousEnabled then
			ToggleSoundUtil.PlayToggle(self._enabled == true)
		end
	end)

	return true
end

function PvpController:_bindStateRemote()
	local remotes = self:_ensureRemotes()
	if not remotes then
		return
	end

	if self._stateChangedConnection then
		self._stateChangedConnection:Disconnect()
	end

	self._stateChangedConnection = remotes.stateChanged.OnClientEvent:Connect(function(state: any)
		self:_applyState(state)
	end)
end

function PvpController:_startRemoteBinding()
	if self._remoteBindingStarted then
		return
	end

	self._remoteBindingStarted = true
	task.spawn(function()
		while self._started == true and self._remotes == nil do
			self:_bindStateRemote()
			if self._remotes then
				self:_refreshState()
				return
			end

			task.wait(0.25)
		end
	end)
end

function PvpController:_startUiBinding()
	if self._uiBindingStarted then
		return
	end

	self._uiBindingStarted = true
	task.spawn(function()
		while self._started == true do
			if self:_bindToggleButton() then
				return
			end

			task.wait(0.25)
		end
	end)
end

function PvpController:_bindCharacterLifecycle()
	if self._characterAddedConnection then
		self._characterAddedConnection:Disconnect()
	end

	self._characterAddedConnection = LOCAL_PLAYER.CharacterAdded:Connect(function()
		self:_clearActiveSwing(true)
		self:_refreshState()
	end)
end

function PvpController:OnStart()
	if self._started then
		return
	end
	self._started = true

	if not isEnabledForPlace() then
		return
	end

	self:_ensureCameraShaker()
	self:_startUiBinding()
	self:_startMobileAttackBinding()
	self:_startRemoteBinding()
	self:_bindCharacterLifecycle()

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

return PvpController
