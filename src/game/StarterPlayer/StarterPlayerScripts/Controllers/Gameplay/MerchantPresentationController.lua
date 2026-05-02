local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Common.Signal)

local FrameController = require(script.Parent.FrameController)

local LOCAL_PLAYER = Players.LocalPlayer

local SYSTEM_OVERLAYS_NAME = "SystemOverlays"
local OVERLAY_NAME = "MerchantTransitionOverlay"
local BACKDROP_NAME = "MerchantShopBackdrop"
local BLUR_NAME = "MerchantShopBlur"

local OPEN_BLACKOUT_TWEEN = TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local OPEN_REVEAL_TWEEN = TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CLOSE_BLACKOUT_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CLOSE_REVEAL_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BLUR_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local BACKDROP_TRANSPARENCY = 0.45
local BLUR_SIZE = 18
local TRANSITION_OVERLAY_MIN_Z_INDEX = 100
local CAMERA_OFFSET_X = 0.35
local CAMERA_OFFSET_Y = 0.18
local CAMERA_RESPONSE = 11
local TWEEN_WAIT_BUFFER_SECONDS = 0.35
local FRAME_CLOSE_WAIT_BUFFER_SECONDS = 0.25

type OpenOptions = {
	cameraPart: BasePart?,
	sourceInstance: Instance?,
	interactionType: string?,
	speakerModel: Model?,
	blurSize: number?,
	backdropTransparency: number?,
	crispContent: boolean?,
	preserveRootLayout: boolean?,
}

type CameraSnapshot = {
	cameraType: Enum.CameraType,
	cameraSubject: Instance?,
	cframe: CFrame,
	fieldOfView: number,
}

local MerchantPresentationController = {
	FramePrepared = Signal.new(),
	Closed = Signal.new(),
	_started = false,
	_playerGui = nil :: PlayerGui?,
	_modalRoot = nil :: ScreenGui?,
	_mainInterface = nil :: ScreenGui?,
	_systemOverlays = nil :: Folder?,
	_overlay = nil :: Frame?,
	_backdrop = nil :: TextButton?,
	_blur = nil :: BlurEffect?,
	_blurTween = nil :: Tween?,
	_controls = nil,
	_controlsWereDisabled = false,
	_closeConnectionsByName = {} :: { [string]: RBXScriptConnection },
	_renderConnection = nil :: RBXScriptConnection?,
	_isOpen = false,
	_transitioning = false,
	_activeFrameName = nil :: string?,
	_activeRoot = nil :: GuiObject?,
	_activeCameraPart = nil :: BasePart?,
	_cameraSnapshot = nil :: CameraSnapshot?,
	_mainInterfaceDisabledBySession = false,
	_autoRotateSnapshot = nil :: boolean?,
	_parallaxCurrent = Vector2.zero,
	_parallaxGoal = Vector2.zero,
	_warnedMissingCameraForFrame = {} :: { [string]: boolean },
}

local function getCurrentCamera(): Camera?
	return workspace.CurrentCamera
end

local function findPlayerModuleControls()
	local playerScripts = LOCAL_PLAYER:FindFirstChild("PlayerScripts")
	if not playerScripts then
		return nil
	end

	local playerModule = playerScripts:FindFirstChild("PlayerModule")
	if not (playerModule and playerModule:IsA("ModuleScript")) then
		return nil
	end

	local ok, module = pcall(require, playerModule)
	if not ok or typeof(module) ~= "table" then
		return nil
	end

	local getControls = module.GetControls
	if typeof(getControls) ~= "function" then
		return nil
	end

	local success, controls = pcall(getControls, module)
	if not success then
		return nil
	end

	return controls
end

local function tweenAsync(instance: Instance, tweenInfo: TweenInfo, goal: { [string]: any }): Tween
	local tween = TweenService:Create(instance, tweenInfo, goal)
	local completed = false
	local connection: RBXScriptConnection?
	connection = tween.Completed:Connect(function()
		completed = true
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end)

	tween:Play()
	local deadline = os.clock() + tweenInfo.Time + TWEEN_WAIT_BUFFER_SECONDS
	while not completed and os.clock() < deadline do
		task.wait()
	end

	if connection then
		connection:Disconnect()
	end

	if not completed then
		tween:Cancel()
		for property, value in pairs(goal) do
			pcall(function()
				(instance :: any)[property] = value
			end)
		end
	end

	return tween
end

local function getHumanoid(): Humanoid?
	local character = LOCAL_PLAYER.Character
	if not character then
		return nil
	end

	return character:FindFirstChildWhichIsA("Humanoid")
end

local function isControlsDisabled(controls): boolean
	if typeof(controls) ~= "table" then
		return false
	end

	if typeof(controls.IsEnabled) == "function" then
		local ok, enabled = pcall(function()
			return controls:IsEnabled()
		end)
		if ok then
			return enabled ~= true
		end
	end

	local rawEnabled = controls.enabled
	if typeof(rawEnabled) == "boolean" then
		return rawEnabled == false
	end

	return false
end

local function isPointInsideGuiObject(guiObject: GuiObject, point: Vector2): boolean
	local absolutePosition = guiObject.AbsolutePosition
	local absoluteSize = guiObject.AbsoluteSize

	return point.X >= absolutePosition.X
		and point.X <= absolutePosition.X + absoluteSize.X
		and point.Y >= absolutePosition.Y
		and point.Y <= absolutePosition.Y + absoluteSize.Y
end

local function collectHighestZIndex(root: GuiObject): number
	local highest = root.ZIndex
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			highest = math.max(highest, descendant.ZIndex)
		end
	end
	return highest
end

function MerchantPresentationController:_ensureState()
	if self._started then
		return
	end

	self._started = true
end

function MerchantPresentationController:_getPlayerGui(): PlayerGui
	if self._playerGui and self._playerGui.Parent then
		return self._playerGui
	end

	self._playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	return self._playerGui
end

function MerchantPresentationController:_getModalRoot(): ScreenGui
	if self._modalRoot and self._modalRoot.Parent then
		return self._modalRoot
	end

	local modalRoot = self:_getPlayerGui():WaitForChild("ModalRoot", 30)
	assert(modalRoot and modalRoot:IsA("ScreenGui"), "PlayerGui.ModalRoot is missing.")
	self._modalRoot = modalRoot
	return modalRoot
end

function MerchantPresentationController:_getSystemOverlays(): Folder
	if self._systemOverlays and self._systemOverlays.Parent then
		return self._systemOverlays
	end

	local modalRoot = self:_getModalRoot()
	local overlays = modalRoot:FindFirstChild(SYSTEM_OVERLAYS_NAME)
	if overlays and not overlays:IsA("Folder") then
		overlays:Destroy()
		overlays = nil
	end

	if not overlays then
		overlays = Instance.new("Folder")
		overlays.Name = SYSTEM_OVERLAYS_NAME
		overlays.Parent = modalRoot
	end

	self._systemOverlays = overlays
	return overlays
end

function MerchantPresentationController:_getMainInterface(): ScreenGui
	if self._mainInterface and self._mainInterface.Parent then
		return self._mainInterface
	end

	local mainInterface = self:_getPlayerGui():WaitForChild("MainInterface", 30)
	assert(mainInterface and mainInterface:IsA("ScreenGui"), "PlayerGui.MainInterface is missing.")
	self._mainInterface = mainInterface
	return mainInterface
end

function MerchantPresentationController:_isPointInsideActiveShop(point: Vector2): boolean
	local root = self._activeRoot
	if not (root and root.Visible and root.Parent) then
		return false
	end

	if isPointInsideGuiObject(root, point) then
		return true
	end

	local playerGui = self:_getPlayerGui()
	for _, guiObject in ipairs(playerGui:GetGuiObjectsAtPosition(point.X, point.Y)) do
		if guiObject == root or guiObject:IsDescendantOf(root) then
			return true
		end
	end

	return false
end

function MerchantPresentationController:_shouldCloseFromBackdropClick(): boolean
	if not self._isOpen or self._transitioning then
		return false
	end

	local mouseLocation = UserInputService:GetMouseLocation()
	local pointerPosition = Vector2.new(mouseLocation.X, mouseLocation.Y)
	return not self:_isPointInsideActiveShop(pointerPosition)
end

function MerchantPresentationController:_getBlur(): BlurEffect
	if self._blur and self._blur.Parent == Lighting then
		return self._blur
	end

	local existing = Lighting:FindFirstChild(BLUR_NAME)
	if existing and existing:IsA("BlurEffect") then
		self._blur = existing
		return existing
	end

	local blur = Instance.new("BlurEffect")
	blur.Name = BLUR_NAME
	blur.Size = 0
	blur.Enabled = false
	blur.Parent = Lighting
	self._blur = blur
	return blur
end

function MerchantPresentationController:_ensureOverlay(): Frame
	if self._overlay and self._overlay.Parent then
		return self._overlay
	end

	local overlays = self:_getSystemOverlays()
	local modalRoot = self:_getModalRoot()
	local overlay = overlays:FindFirstChild(OVERLAY_NAME)
	local legacyOverlay = modalRoot:FindFirstChild(OVERLAY_NAME)
	if legacyOverlay and legacyOverlay ~= overlay then
		if legacyOverlay:IsA("Frame") and not overlay then
			legacyOverlay.Parent = overlays
			overlay = legacyOverlay
		else
			legacyOverlay:Destroy()
		end
	end

	if overlay and not overlay:IsA("Frame") then
		overlay:Destroy()
		overlay = nil
	end

	if not overlay then
		overlay = Instance.new("Frame")
		overlay.Name = OVERLAY_NAME
		overlay.BackgroundColor3 = Color3.new(0, 0, 0)
		overlay.BackgroundTransparency = 1
		overlay.BorderSizePixel = 0
		overlay.Size = UDim2.fromScale(1, 1)
		overlay.Position = UDim2.fromScale(0, 0)
		overlay.ZIndex = TRANSITION_OVERLAY_MIN_Z_INDEX
		overlay.Visible = false
		overlay.Parent = overlays
	end

	self._overlay = overlay
	return overlay
end

function MerchantPresentationController:_ensureBackdrop(): TextButton
	if self._backdrop and self._backdrop.Parent then
		return self._backdrop
	end

	local overlays = self:_getSystemOverlays()
	local modalRoot = self:_getModalRoot()
	local backdrop = overlays:FindFirstChild(BACKDROP_NAME)
	local legacyBackdrop = modalRoot:FindFirstChild(BACKDROP_NAME)
	if legacyBackdrop and legacyBackdrop ~= backdrop then
		if legacyBackdrop:IsA("TextButton") and not backdrop then
			legacyBackdrop.Parent = overlays
			backdrop = legacyBackdrop
		else
			legacyBackdrop:Destroy()
		end
	end

	if backdrop and not backdrop:IsA("TextButton") then
		backdrop:Destroy()
		backdrop = nil
	end

	if not backdrop then
		backdrop = Instance.new("TextButton")
		backdrop.Name = BACKDROP_NAME
		backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
		backdrop.BackgroundTransparency = 1
		backdrop.AutoButtonColor = false
		backdrop.BorderSizePixel = 0
		backdrop.Text = ""
		backdrop.Size = UDim2.fromScale(1, 1)
		backdrop.Position = UDim2.fromScale(0, 0)
		backdrop.ZIndex = 0
		backdrop.Visible = false
		backdrop.Parent = overlays
		backdrop.Activated:Connect(function()
			if MerchantPresentationController:_shouldCloseFromBackdropClick() then
				MerchantPresentationController:Close()
			end
		end)
	end

	self._backdrop = backdrop
	return backdrop
end

function MerchantPresentationController:_getShopRoot(frameName: string): GuiObject?
	local modalRoot = self:_getModalRoot()
	local root = modalRoot:FindFirstChild(frameName)
	if not root then
		root = modalRoot:WaitForChild(frameName, 2)
	end
	if root and root:IsA("GuiObject") then
		return root
	end

	return nil
end

function MerchantPresentationController:_raiseTransitionOverlayAbove(root: GuiObject?)
	local overlay = self:_ensureOverlay()
	local highestZIndex = TRANSITION_OVERLAY_MIN_Z_INDEX - 1

	if root then
		highestZIndex = math.max(highestZIndex, collectHighestZIndex(root))
	end

	local backdrop = self._backdrop
	if backdrop then
		highestZIndex = math.max(highestZIndex, backdrop.ZIndex)
	end

	overlay.ZIndex = highestZIndex + 1
end

function MerchantPresentationController:_bindCloseButton(frameName: string, root: GuiObject)
	if self._closeConnectionsByName[frameName] then
		return
	end

	local closeButton = root:FindFirstChild("CloseButton", true)
	if not (closeButton and closeButton:IsA("GuiButton")) then
		return
	end

	self._closeConnectionsByName[frameName] = closeButton.Activated:Connect(function()
		MerchantPresentationController:Close()
	end)
end

function MerchantPresentationController:_snapshotCamera()
	local camera = getCurrentCamera()
	if not camera then
		self._cameraSnapshot = nil
		return
	end

	self._cameraSnapshot = {
		cameraType = camera.CameraType,
		cameraSubject = camera.CameraSubject,
		cframe = camera.CFrame,
		fieldOfView = camera.FieldOfView,
	}
end

function MerchantPresentationController:_restoreCamera()
	local camera = getCurrentCamera()
	local snapshot = self._cameraSnapshot
	self._cameraSnapshot = nil

	if not (camera and snapshot) then
		return
	end

	camera.FieldOfView = snapshot.fieldOfView
	camera.CFrame = snapshot.cframe
	camera.CameraSubject = snapshot.cameraSubject
	camera.CameraType = snapshot.cameraType
end

function MerchantPresentationController:_setMainInterfaceEnabled(enabled: boolean)
	local mainInterface = self:_getMainInterface()
	mainInterface.Enabled = enabled
end

function MerchantPresentationController:_beginMainInterfaceSession()
	if self._mainInterfaceDisabledBySession then
		return
	end

	local mainInterface = self:_getMainInterface()
	if mainInterface.Enabled then
		mainInterface.Enabled = false
		self._mainInterfaceDisabledBySession = true
	end
end

function MerchantPresentationController:_restoreMainInterfaceSession()
	if self._mainInterfaceDisabledBySession then
		self:_setMainInterfaceEnabled(true)
	end

	self._mainInterfaceDisabledBySession = false
end

function MerchantPresentationController:_freezePlayer()
	local controls = self._controls
	if not controls then
		controls = findPlayerModuleControls()
		self._controls = controls
	end

	self._controlsWereDisabled = isControlsDisabled(controls)
	if controls and typeof(controls.Disable) == "function" and not self._controlsWereDisabled then
		pcall(function()
			controls:Disable()
		end)
	end

	local humanoid = getHumanoid()
	self._autoRotateSnapshot = if humanoid then humanoid.AutoRotate else nil
	if humanoid then
		humanoid.AutoRotate = false
	end
end

function MerchantPresentationController:_restorePlayer()
	local controls = self._controls
	if controls and typeof(controls.Enable) == "function" and not self._controlsWereDisabled then
		pcall(function()
			controls:Enable()
		end)
	end

	self._controlsWereDisabled = false

	local humanoid = getHumanoid()
	if humanoid and self._autoRotateSnapshot ~= nil then
		humanoid.AutoRotate = self._autoRotateSnapshot
	end
	self._autoRotateSnapshot = nil
end

function MerchantPresentationController:_setBlurSize(targetSize: number, tweenInfo: TweenInfo?, enabled: boolean?)
	local blur = self:_getBlur()

	if self._blurTween then
		self._blurTween:Cancel()
		self._blurTween = nil
	end

	if targetSize <= 0 then
		blur.Size = 0
		blur.Enabled = false
		return
	end

	blur.Enabled = if enabled == nil then true else enabled

	if tweenInfo then
		self._blurTween = TweenService:Create(blur, tweenInfo, {
			Size = targetSize,
		})
		self._blurTween:Play()
	else
		blur.Size = targetSize
	end
end

function MerchantPresentationController:_setCameraBase(cameraPart: BasePart?, frameName: string)
	self._activeCameraPart = cameraPart
	if not cameraPart then
		if not self._warnedMissingCameraForFrame[frameName] then
			self._warnedMissingCameraForFrame[frameName] = true
			Logger.Warn(string.format("[MerchantPresentationController] No camera part was resolved for '%s'.", frameName))
		end
		return
	end

	local camera = getCurrentCamera()
	if not camera then
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = cameraPart.CFrame
end

function MerchantPresentationController:_stopCameraParallax()
	if self._renderConnection then
		self._renderConnection:Disconnect()
		self._renderConnection = nil
	end

	self._parallaxCurrent = Vector2.zero
	self._parallaxGoal = Vector2.zero
	self._activeCameraPart = nil
end

function MerchantPresentationController:_startCameraParallax(cameraPart: BasePart?)
	self:_stopCameraParallax()

	if not cameraPart then
		return
	end

	local camera = getCurrentCamera()
	if not camera then
		return
	end

	self._activeCameraPart = cameraPart
	self._renderConnection = RunService.RenderStepped:Connect(function(dt: number)
		local activeCamera = getCurrentCamera()
		local activePart = self._activeCameraPart
		if not (self._isOpen and activeCamera and activePart and activePart.Parent) then
			return
		end

		local inset = GuiService:GetGuiInset()
		local viewportSize = activeCamera.ViewportSize
		local mousePosition = UserInputService:GetMouseLocation()
		local viewportX = math.clamp(mousePosition.X - inset.X, 0, viewportSize.X)
		local viewportY = math.clamp(mousePosition.Y - inset.Y, 0, viewportSize.Y)

		local normalizedX = 0
		local normalizedY = 0
		if viewportSize.X > 0 then
			normalizedX = math.clamp((viewportX / viewportSize.X) * 2 - 1, -1, 1)
		end
		if viewportSize.Y > 0 then
			normalizedY = math.clamp(1 - (viewportY / viewportSize.Y) * 2, -1, 1)
		end

		self._parallaxGoal = Vector2.new(normalizedX, normalizedY)
		local alpha = 1 - math.exp(-CAMERA_RESPONSE * dt)
		self._parallaxCurrent = self._parallaxCurrent:Lerp(self._parallaxGoal, alpha)

		local offset = Vector3.new(
			self._parallaxCurrent.X * CAMERA_OFFSET_X,
			self._parallaxCurrent.Y * CAMERA_OFFSET_Y,
			0
		)
		activeCamera.CFrame = activePart.CFrame * CFrame.new(offset)
	end)
end

function MerchantPresentationController:_playOpenReveal()
	local overlay = self:_ensureOverlay()
	tweenAsync(overlay, OPEN_REVEAL_TWEEN, {
		BackgroundTransparency = 1,
	})
	self:_hideOverlay()
end

function MerchantPresentationController:_playCloseBlackout()
	local overlay = self:_ensureOverlay()
	self:_raiseTransitionOverlayAbove(self._activeRoot)
	overlay.Visible = true
	overlay.BackgroundTransparency = 1
	tweenAsync(overlay, CLOSE_BLACKOUT_TWEEN, {
		BackgroundTransparency = 0,
	})
end

function MerchantPresentationController:_playOpenBlackout()
	local overlay = self:_ensureOverlay()
	self:_raiseTransitionOverlayAbove(nil)
	overlay.Visible = true
	overlay.BackgroundTransparency = 1
	tweenAsync(overlay, OPEN_BLACKOUT_TWEEN, {
		BackgroundTransparency = 0,
	})
end

function MerchantPresentationController:_hideOverlay()
	local overlay = self:_ensureOverlay()
	overlay.Visible = false
	overlay.BackgroundTransparency = 1
end

function MerchantPresentationController:_restorePresentationStep(stepName: string, callback: () -> ())
	local ok, err = xpcall(callback, debug.traceback)
	if ok then
		return
	end

	Logger.Warn(string.format("[MerchantPresentationController] Restore step '%s' failed: %s", stepName, tostring(err)))
end

function MerchantPresentationController:_restorePresentationState()
	self:_restorePresentationStep("mainInterface", function()
		self:_restoreMainInterfaceSession()
	end)

	self:_restorePresentationStep("backdrop", function()
		local backdrop = self:_ensureBackdrop()
		backdrop.Visible = false
		backdrop.Active = false
		backdrop.BackgroundTransparency = 1
	end)

	self:_restorePresentationStep("cameraParallax", function()
		self:_stopCameraParallax()
	end)

	self:_restorePresentationStep("camera", function()
		self:_restoreCamera()
	end)

	self:_restorePresentationStep("player", function()
		self:_restorePlayer()
	end)

	self:_restorePresentationStep("blur", function()
		self:_setBlurSize(0, nil, false)
	end)
end

function MerchantPresentationController:_resetTransitionState()
	self._activeFrameName = nil
	self._activeRoot = nil
	self._isOpen = false
	self._transitioning = false
	self._mainInterfaceDisabledBySession = false
end

function MerchantPresentationController:_recoverTransition(transitionName: string, err: any, closedFrameName: string?)
	Logger.Warn(string.format("[MerchantPresentationController] %s transition failed: %s", transitionName, tostring(err)))
	if self._activeFrameName then
		FrameController:CloseFrame(self._activeFrameName)
	end
	self:_restorePresentationState()
	self:_restorePresentationStep("overlay", function()
		self:_hideOverlay()
	end)
	self:_resetTransitionState()

	if closedFrameName then
		self.Closed:Fire(closedFrameName)
	end
end

function MerchantPresentationController:_midpointOpen(frameName: string, root: GuiObject, options: OpenOptions?)
	self:_beginMainInterfaceSession()
	self:_freezePlayer()

	local backdrop = self:_ensureBackdrop()
	local backdropTransparency = if options and typeof(options.backdropTransparency) == "number"
		then math.clamp(options.backdropTransparency, 0, 1)
		else BACKDROP_TRANSPARENCY
	local blurSize = if options and typeof(options.blurSize) == "number"
		then math.max(0, options.blurSize)
		else BLUR_SIZE

	backdrop.Visible = true
	backdrop.Active = true
	backdrop.ZIndex = math.max(0, root.ZIndex - 1)
	backdrop.BackgroundTransparency = backdropTransparency

	self:_setBlurSize(blurSize, BLUR_TWEEN, true)
	self:_snapshotCamera()
	self:_setCameraBase(if options then options.cameraPart else nil, frameName)

	local opened = FrameController:OpenFrame(frameName, {
		useOverlay = false,
	})
	if not opened then
		error(string.format("FrameController could not open ModalRoot.%s.", frameName), 2)
	end

	self._isOpen = true
	self.FramePrepared:Fire(frameName, root, options)
	self:_bindCloseButton(frameName, root)
	self:_raiseTransitionOverlayAbove(root)
end

function MerchantPresentationController:_midpointClose(frameName: string?)
	if frameName then
		FrameController:CloseFrame(frameName)
		local deadline = os.clock() + FrameController.CloseTween.Time + FRAME_CLOSE_WAIT_BUFFER_SECONDS
		while FrameController:IsOpen(frameName) and os.clock() < deadline do
			task.wait()
		end
	end
	self:_restorePresentationState()
end

function MerchantPresentationController:OnStart()
	self:_ensureState()
	self:_ensureOverlay()
	self:_ensureBackdrop()
	self:_getBlur()
end

function MerchantPresentationController:IsOpen(): boolean
	return self._isOpen
end

function MerchantPresentationController:IsGameplayBlocking(): boolean
	return self._isOpen == true or self._transitioning == true
end

function MerchantPresentationController:Open(frameName: string, options: OpenOptions?): boolean
	self:OnStart()

	if self._transitioning then
		return false
	end

	if self._isOpen and self._activeFrameName == frameName then
		return true
	end

	if self._isOpen then
		local closed = self:Close()
		if not closed then
			self:_recoverTransition("pre-open close", "Existing presentation did not close.", self._activeFrameName)
		end
	end

	local root = self:_getShopRoot(frameName)
	if not root then
		Logger.Warn(string.format("[MerchantPresentationController] ModalRoot.%s was not found.", frameName))
		return false
	end

	self._transitioning = true
	self._activeFrameName = frameName
	self._activeRoot = root

	local ok, err = xpcall(function()
		self:_playOpenBlackout()
		self:_midpointOpen(frameName, root, options)
		self:_playOpenReveal()
		self:_hideOverlay()
		self:_startCameraParallax(if options then options.cameraPart else nil)
	end, debug.traceback)

	if not ok then
		self:_recoverTransition("open", err, nil)
		return false
	end

	self._transitioning = false
	return true
end

function MerchantPresentationController:Close(): boolean
	self:OnStart()

	if not self._isOpen or self._transitioning then
		return false
	end

	local closingFrameName = self._activeFrameName
	self._transitioning = true

	local ok, err = xpcall(function()
		self:_playCloseBlackout()
		self:_midpointClose(closingFrameName)
		tweenAsync(self:_ensureOverlay(), CLOSE_REVEAL_TWEEN, {
			BackgroundTransparency = 1,
		})
		self:_hideOverlay()
	end, debug.traceback)

	if not ok then
		self:_recoverTransition("close", err, closingFrameName)
		return false
	end

	self:_resetTransitionState()

	if closingFrameName then
		self.Closed:Fire(closingFrameName)
	end

	return true
end

return MerchantPresentationController
