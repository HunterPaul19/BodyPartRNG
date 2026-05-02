local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CombatSoundUtil = require(ReplicatedStorage.Shared.Audio.CombatSoundUtil)
local GameAssetPaths = require(ReplicatedStorage.Shared.Assets.GameAssetPaths)
local GameAssetResolver = require(ReplicatedStorage.Shared.Assets.GameAssetResolver)
local DashStateRules = require(ReplicatedStorage.Shared.Combat.DashStateRules)
local RemoteFunctionTimeout = require(ReplicatedStorage.Shared.Remotes.RemoteFunctionTimeout)

local LOCAL_PLAYER = Players.LocalPlayer
local REMOTE_INVOKE_TIMEOUT_SECONDS = 4
local DASH_ANIMATION_NAME = "Dash"
local DASH_ANIMATION_ID = "rbxassetid://80201492192726"
local DASH_START_SPEED = 165
local DASH_END_SPEED = 45
local SIDE_DASH_PEAK_SPEED = 90
local SIDE_DASH_ACCEL_SECONDS = 0.045
local BASE_DASH_MAX_FORCE = 8e4
local BASE_DASH_ASSEMBLY_MASS = 15
local REMOTES_FOLDER_NAME = "Remotes"
local DASH_FOLDER_NAME = "Dash"
local REQUEST_DASH_REMOTE_NAME = "RequestDash"

local KEYBOARD_DASH_KEYS = {
	{ keyCode = Enum.KeyCode.W, direction = "Front" },
	{ keyCode = Enum.KeyCode.A, direction = "Left" },
	{ keyCode = Enum.KeyCode.D, direction = "Right" },
	{ keyCode = Enum.KeyCode.S, direction = "Back" },
}

type CharacterParts = {
	character: Model,
	humanoid: Humanoid,
	rootPart: BasePart,
}

type RequestDashResponse = {
	ok: boolean,
	direction: string?,
	durationSeconds: number?,
	code: string?,
	retryAfterSeconds: number?,
}

local DashController = {
	_started = false,
	_requestInFlight = false,
	_inputConnection = nil :: RBXScriptConnection?,
	_characterAddedConnection = nil :: RBXScriptConnection?,
	_heartbeatConnection = nil :: RBXScriptConnection?,
	_mobileDashConnection = nil :: RBXScriptConnection?,
	_mobileDashButton = nil :: GuiButton?,
	_mobileBindingStarted = false,
	_activeBodyVelocity = nil :: BodyVelocity?,
	_activeVelocityValue = nil :: NumberValue?,
	_activeTween = nil :: Tween?,
	_activeTrack = nil :: AnimationTrack?,
	_activeHumanoid = nil :: Humanoid?,
	_previousAutoRotate = nil :: boolean?,
	_dashToken = 0,
	_nextDashAllowedAt = 0,
	_requestRemote = nil :: RemoteFunction?,
	_controlModule = nil :: any,
	_warnedMissingAnimation = false,
	_warnedMissingRemote = false,
}

local function warnWithPrefix(message: string)
	Logger.Warn(string.format("[DashController] %s", message))
end

local function normalizeAbilityName(value: string): string
	return string.lower(string.match(value, "^%s*(.-)%s*$") or "")
end

local function getCharacterParts(): CharacterParts?
	local character = LOCAL_PLAYER.Character
	if character == nil or character.Parent == nil then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return nil
	end
	if not (rootPart and rootPart:IsA("BasePart")) then
		return nil
	end
	if humanoid.Health <= 0 then
		return nil
	end

	return {
		character = character,
		humanoid = humanoid,
		rootPart = rootPart,
	}
end

local function isBlockedByCharacterState(character: Model): boolean
	return DashStateRules.IsDashBlocked(character)
end

local function resolveDashAnimation(): Animation?
	local animation = GameAssetResolver.Find(GameAssetPaths.Animations.Combat, DASH_ANIMATION_NAME)
	if animation and animation:IsA("Animation") then
		return animation
	end

	return nil
end

local function normalizeApprovedDirection(direction: string?): string
	if direction == "Back" or direction == "Left" or direction == "Right" then
		return direction
	end

	return "Front"
end

local function isDirectionalKeyboardDashEnabled(): boolean
	return UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
end

local function toHorizontalUnit(vector: Vector3): Vector3?
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	if horizontal.Magnitude <= 1e-4 then
		return nil
	end

	return horizontal.Unit
end

local function resolveDashVector(rootPart: BasePart, direction: string): Vector3
	local rootCFrame = rootPart.CFrame
	local lookDirection = toHorizontalUnit(rootCFrame.LookVector) or Vector3.new(0, 0, -1)
	local rightDirection = toHorizontalUnit(rootCFrame.RightVector) or Vector3.new(1, 0, 0)

	if direction == "Back" then
		return -lookDirection
	end
	if direction == "Left" then
		return -rightDirection
	end
	if direction == "Right" then
		return rightDirection
	end

	return lookDirection
end

local function isFinitePositiveNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value > 0 and value < math.huge
end

local function getCharacterPartMass(character: Model): number
	local totalMass = 0

	for _, descendant in ipairs(character:GetDescendants()) do
		if not descendant:IsA("BasePart") or descendant.Massless == true then
			continue
		end

		local ok, mass = pcall(function()
			return descendant:GetMass()
		end)
		if ok and isFinitePositiveNumber(mass) then
			totalMass += mass
		end
	end

	return totalMass
end

local function resolveDashAssemblyMass(character: Model, rootPart: BasePart): number
	local assemblyMass = rootPart.AssemblyMass
	if isFinitePositiveNumber(assemblyMass) then
		return assemblyMass
	end

	local fallbackMass = getCharacterPartMass(character)
	if isFinitePositiveNumber(fallbackMass) then
		return fallbackMass
	end

	return BASE_DASH_ASSEMBLY_MASS
end

local function resolveDashMaxForce(character: Model, rootPart: BasePart): Vector3
	local assemblyMass = resolveDashAssemblyMass(character, rootPart)
	local force = BASE_DASH_MAX_FORCE * math.max(1, assemblyMass / BASE_DASH_ASSEMBLY_MASS)
	return Vector3.new(force, 0, force)
end

function DashController:_ensureRemote(): RemoteFunction?
	if self._requestRemote and self._requestRemote.Parent ~= nil then
		return self._requestRemote
	end

	local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	local dashFolder = remotesFolder and remotesFolder:FindFirstChild(DASH_FOLDER_NAME)
	local requestRemote = dashFolder and dashFolder:FindFirstChild(REQUEST_DASH_REMOTE_NAME)
	if requestRemote and requestRemote:IsA("RemoteFunction") then
		self._requestRemote = requestRemote
		self._warnedMissingRemote = false
		return requestRemote
	end

	if self._warnedMissingRemote ~= true then
		self._warnedMissingRemote = true
		warnWithPrefix("ReplicatedStorage.Remotes.Dash.RequestDash is missing.")
	end

	return nil
end

function DashController:_getControlModule(): any?
	if self._controlModule ~= nil then
		return self._controlModule
	end

	local playerScripts = LOCAL_PLAYER:FindFirstChild("PlayerScripts")
	local playerModule = playerScripts and playerScripts:FindFirstChild("PlayerModule")
	local controlModule = playerModule and playerModule:FindFirstChild("ControlModule")
	if controlModule == nil then
		return nil
	end

	local ok, result = pcall(require, controlModule)
	if not ok then
		warnWithPrefix(string.format("Failed to require PlayerModule.ControlModule: %s", tostring(result)))
		return nil
	end

	self._controlModule = result
	return result
end

function DashController:_resolveControllerDirection(): string
	local controlModule = self:_getControlModule()
	if controlModule == nil or type(controlModule.GetMoveVector) ~= "function" then
		return "Front"
	end

	local moveVector = controlModule:GetMoveVector()
	if typeof(moveVector) ~= "Vector3" then
		return "Front"
	end

	if math.abs(moveVector.X) > math.abs(moveVector.Z) then
		return if moveVector.X > 0 then "Right" else "Left"
	end

	return if moveVector.Z > 0 then "Back" else "Front"
end

function DashController:_resolveKeyboardDirection(): string
	if not isDirectionalKeyboardDashEnabled() then
		return "Front"
	end

	for _, dashKey in ipairs(KEYBOARD_DASH_KEYS) do
		if UserInputService:IsKeyDown(dashKey.keyCode) then
			return dashKey.direction
		end
	end

	return "Front"
end

function DashController:_resolveDashDirection(input: InputObject?): string
	if input and input.UserInputType == Enum.UserInputType.Keyboard then
		return self:_resolveKeyboardDirection()
	end
	if input and string.find(input.UserInputType.Name, "Gamepad") ~= nil then
		return self:_resolveControllerDirection()
	end

	return self:_resolveControllerDirection()
end

function DashController:_disconnectHeartbeat()
	if self._heartbeatConnection and self._heartbeatConnection.Connected then
		self._heartbeatConnection:Disconnect()
	end
	self._heartbeatConnection = nil
end

function DashController:_stopActiveTrack()
	local track = self._activeTrack
	self._activeTrack = nil
	if track then
		pcall(function()
			track:Stop(0.1)
		end)
	end
end

function DashController:_destroyActiveMover()
	if self._activeTween then
		self._activeTween:Cancel()
		self._activeTween = nil
	end

	if self._activeBodyVelocity then
		self._activeBodyVelocity:Destroy()
		self._activeBodyVelocity = nil
	end

	if self._activeVelocityValue then
		self._activeVelocityValue:Destroy()
		self._activeVelocityValue = nil
	end
end

function DashController:_restoreAutoRotate()
	local humanoid = self._activeHumanoid
	local previousAutoRotate = self._previousAutoRotate
	self._activeHumanoid = nil
	self._previousAutoRotate = nil

	if humanoid and humanoid.Parent ~= nil and previousAutoRotate ~= nil then
		humanoid.AutoRotate = previousAutoRotate
	end
end

function DashController:_clearActiveDash()
	self._dashToken += 1
	self:_disconnectHeartbeat()
	self:_stopActiveTrack()
	self:_destroyActiveMover()
	self:_restoreAutoRotate()
end

function DashController:_endDash(dashToken: number)
	if self._dashToken ~= dashToken then
		return
	end

	self:_disconnectHeartbeat()
	self:_stopActiveTrack()
	self:_destroyActiveMover()
	self:_restoreAutoRotate()
end

function DashController:_faceDashDirection(humanoid: Humanoid, rootPart: BasePart, dashDirection: Vector3)
	self:_restoreAutoRotate()
	self._activeHumanoid = humanoid
	self._previousAutoRotate = humanoid.AutoRotate
	humanoid.AutoRotate = false
	rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + dashDirection)
end

function DashController:_playDashAnimation(character: Model)
	local animation = resolveDashAnimation()
	if animation == nil then
		if self._warnedMissingAnimation ~= true then
			self._warnedMissingAnimation = true
			warnWithPrefix(string.format(
				"Missing %s animation under %s.",
				DASH_ANIMATION_NAME,
				GameAssetResolver.Format(GameAssetPaths.Animations.Combat)
			))
		end
		return
	end
	self._warnedMissingAnimation = false

	if animation.AnimationId ~= DASH_ANIMATION_ID then
		warnWithPrefix(string.format("Dash animation id is '%s'; expected '%s'.", animation.AnimationId, DASH_ANIMATION_ID))
	end

	local ok, profile = pcall(Animation.new, character)
	if not ok or profile == nil then
		warnWithPrefix("Failed to create animation profile for dash.")
		return
	end

	local track = profile:PlayAnimation(animation, Enum.AnimationPriority.Action2, 1, nil, 0.05)
	if track == nil then
		warnWithPrefix("Failed to play dash animation.")
		return
	end

	track.Looped = false
	self._activeTrack = track
end

function DashController:_createBodyVelocity(character: Model, rootPart: BasePart): BodyVelocity
	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.Name = "DashBodyVelocity"
	bodyVelocity.MaxForce = resolveDashMaxForce(character, rootPart)
	bodyVelocity.Parent = rootPart
	self._activeBodyVelocity = bodyVelocity
	return bodyVelocity
end

function DashController:_createVelocityValue(initialValue: number): NumberValue
	local velocityValue = Instance.new("NumberValue")
	velocityValue.Name = "DashVelocityValue"
	velocityValue.Value = initialValue
	self._activeVelocityValue = velocityValue
	return velocityValue
end

function DashController:_startForwardOrBackMovement(
	character: Model,
	rootPart: BasePart,
	direction: string,
	dashDirection: Vector3,
	durationSeconds: number,
	dashToken: number
)
	local velocityValue = self:_createVelocityValue(DASH_START_SPEED)
	local bodyVelocity = self:_createBodyVelocity(character, rootPart)
	local easingStyle = if direction == "Back" then Enum.EasingStyle.Exponential else Enum.EasingStyle.Sine

	local tween = TweenService:Create(
		velocityValue,
		TweenInfo.new(durationSeconds, easingStyle, Enum.EasingDirection.Out),
		{ Value = DASH_END_SPEED }
	)
	self._activeTween = tween
	tween:Play()

	self._heartbeatConnection = RunService.Heartbeat:Connect(function()
		if self._dashToken ~= dashToken or bodyVelocity.Parent == nil or rootPart.Parent == nil then
			self:_disconnectHeartbeat()
			return
		end

		bodyVelocity.Velocity = dashDirection * velocityValue.Value
	end)
end

function DashController:_startSideMovement(
	character: Model,
	rootPart: BasePart,
	dashDirection: Vector3,
	durationSeconds: number,
	dashToken: number
)
	local velocityValue = self:_createVelocityValue(0)
	local bodyVelocity = self:_createBodyVelocity(character, rootPart)

	local tween = TweenService:Create(
		velocityValue,
		TweenInfo.new(math.min(SIDE_DASH_ACCEL_SECONDS, durationSeconds), Enum.EasingStyle.Sine, Enum.EasingDirection.In),
		{ Value = SIDE_DASH_PEAK_SPEED }
	)
	self._activeTween = tween
	tween:Play()

	self._heartbeatConnection = RunService.Heartbeat:Connect(function()
		if self._dashToken ~= dashToken or bodyVelocity.Parent == nil or rootPart.Parent == nil then
			self:_disconnectHeartbeat()
			return
		end

		bodyVelocity.Velocity = dashDirection * velocityValue.Value
	end)
end

function DashController:_startMovement(
	character: Model,
	rootPart: BasePart,
	direction: string,
	dashDirection: Vector3,
	durationSeconds: number,
	dashToken: number
)
	if direction == "Left" or direction == "Right" then
		self:_startSideMovement(character, rootPart, dashDirection, durationSeconds, dashToken)
		return
	end

	self:_startForwardOrBackMovement(character, rootPart, direction, dashDirection, durationSeconds, dashToken)
end

function DashController:RequestDash(input: InputObject?)
	local now = os.clock()
	if now < self._nextDashAllowedAt or self._requestInFlight then
		return
	end
	if self._activeBodyVelocity ~= nil then
		return
	end

	local parts = getCharacterParts()
	if parts == nil then
		return
	end
	if isBlockedByCharacterState(parts.character) then
		return
	end

	local requestRemote = self:_ensureRemote()
	if requestRemote == nil then
		return
	end

	local requestedDirection = self:_resolveDashDirection(input)
	self._requestInFlight = true
	local ok, response, timedOut = RemoteFunctionTimeout.Invoke(requestRemote, requestedDirection, REMOTE_INVOKE_TIMEOUT_SECONDS)
	self._requestInFlight = false

	if not ok then
		local reason = if timedOut then "timed out" else "failed"
		warnWithPrefix(string.format("RequestDash %s: %s", reason, tostring(response)))
		return
	end
	if typeof(response) ~= "table" or response.ok ~= true then
		local retryAfterSeconds = if typeof(response) == "table" then tonumber(response.retryAfterSeconds) else nil
		if retryAfterSeconds ~= nil and retryAfterSeconds > 0 then
			self._nextDashAllowedAt = os.clock() + retryAfterSeconds
		end
		return
	end

	parts = getCharacterParts()
	if parts == nil then
		return
	end

	local approvedResponse = response :: RequestDashResponse
	local direction = normalizeApprovedDirection(approvedResponse.direction)
	local durationSeconds = math.max(0.05, tonumber(approvedResponse.durationSeconds) or 0.5)

	self._nextDashAllowedAt = os.clock() + 0.1
	self:_clearActiveDash()

	self._dashToken += 1
	local dashToken = self._dashToken
	local dashDirection = resolveDashVector(parts.rootPart, direction)
	self:_faceDashDirection(parts.humanoid, parts.rootPart, dashDirection)
	CombatSoundUtil.PlayLocalDash(direction)
	self:_playDashAnimation(parts.character)
	self:_startMovement(parts.character, parts.rootPart, direction, dashDirection, durationSeconds, dashToken)

	task.delay(durationSeconds, function()
		self:_endDash(dashToken)
	end)
end

function DashController:_resolveMobileDashButton(): GuiButton?
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

		if normalizeAbilityName(abilityName.Text) == "dash" then
			return descendant
		end
	end

	return nil
end

function DashController:_bindMobileDashButton(): boolean
	local dashButton = self:_resolveMobileDashButton()
	if dashButton == nil then
		return false
	end

	if self._mobileDashButton == dashButton and self._mobileDashConnection then
		return true
	end

	if self._mobileDashConnection then
		self._mobileDashConnection:Disconnect()
		self._mobileDashConnection = nil
	end

	self._mobileDashButton = dashButton
	self._mobileDashConnection = dashButton.Activated:Connect(function()
		self:RequestDash()
	end)

	return true
end

function DashController:_startMobileBinding()
	if self._mobileBindingStarted then
		return
	end

	self._mobileBindingStarted = true
	task.spawn(function()
		while self._started == true do
			if self._mobileDashButton == nil or self._mobileDashButton.Parent == nil or self._mobileDashConnection == nil then
				self:_bindMobileDashButton()
			end

			task.wait(0.25)
		end
	end)
end

function DashController:_bindCharacterLifecycle()
	if self._characterAddedConnection then
		self._characterAddedConnection:Disconnect()
	end

	self._characterAddedConnection = LOCAL_PLAYER.CharacterAdded:Connect(function()
		self:_clearActiveDash()
	end)
end

function DashController:OnStart()
	if self._started then
		return
	end
	self._started = true

	self:_bindCharacterLifecycle()
	self:_startMobileBinding()

	self._inputConnection = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
		if gameProcessedEvent then
			return
		end
		if input.KeyCode ~= Enum.KeyCode.Q and input.KeyCode ~= Enum.KeyCode.ButtonY then
			return
		end

		self:RequestDash(input)
	end)
end

return DashController
