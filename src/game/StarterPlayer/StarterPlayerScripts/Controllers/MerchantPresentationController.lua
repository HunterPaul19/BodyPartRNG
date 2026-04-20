local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Common.Signal)

local LOCAL_PLAYER = Players.LocalPlayer

local OVERLAY_NAME = "MerchantTransitionOverlay"
local BACKDROP_NAME = "MerchantShopBackdrop"
local BLUR_NAME = "MerchantShopBlur"
local TRANSITION_WRAPPER_NAME = "MerchantShopTransitionWrapper"
local CONTENT_GROUP_NAME = "MerchantRuntimeCanvasGroup"
local SCALE_NAME = "MerchantRuntimeScale"

local OPEN_BLACKOUT_TWEEN = TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local OPEN_REVEAL_TWEEN = TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local OPEN_SCALE_TWEEN = TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local CLOSE_BLACKOUT_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CLOSE_REVEAL_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BLUR_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local BACKDROP_TRANSPARENCY = 0.45
local BLUR_SIZE = 18
local INITIAL_SCALE = 0.9
local CAMERA_OFFSET_X = 0.35
local CAMERA_OFFSET_Y = 0.18
local CAMERA_RESPONSE = 11

type OpenOptions = {
	cameraPart: BasePart?,
	sourceInstance: Instance?,
	interactionType: string?,
	speakerModel: Model?,
}

type CameraSnapshot = {
	cameraType: Enum.CameraType,
	cameraSubject: Instance?,
	cframe: CFrame,
	fieldOfView: number,
}

type RootLayoutSnapshot = {
	parent: Instance,
	position: UDim2,
	size: UDim2,
	anchorPoint: Vector2,
	zIndex: number,
	visible: boolean,
	backgroundTransparency: number,
}

type TransitionWrapperState = {
	wrapper: Frame,
	content: CanvasGroup,
	scale: UIScale,
}

local MerchantPresentationController = {
	FramePrepared = Signal.new(),
	Closed = Signal.new(),
	_started = false,
	_playerGui = nil :: PlayerGui?,
	_modalRoot = nil :: ScreenGui?,
	_mainInterface = nil :: ScreenGui?,
	_overlay = nil :: Frame?,
	_backdrop = nil :: TextButton?,
	_blur = nil :: BlurEffect?,
	_blurTween = nil :: Tween?,
	_controls = nil,
	_controlsWereDisabled = false,
	_closeConnectionsByName = {} :: { [string]: RBXScriptConnection },
	_runtimeWrapperByRoot = {} :: { [GuiObject]: Frame },
	_runtimeContentByRoot = {} :: { [GuiObject]: CanvasGroup },
	_runtimeScaleByRoot = {} :: { [GuiObject]: UIScale },
	_rootLayoutSnapshotsByRoot = {} :: { [GuiObject]: RootLayoutSnapshot },
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
	tween:Play()
	tween.Completed:Wait()
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

function MerchantPresentationController:_getMainInterface(): ScreenGui
	if self._mainInterface and self._mainInterface.Parent then
		return self._mainInterface
	end

	local mainInterface = self:_getPlayerGui():WaitForChild("MainInterface", 30)
	assert(mainInterface and mainInterface:IsA("ScreenGui"), "PlayerGui.MainInterface is missing.")
	self._mainInterface = mainInterface
	return mainInterface
end

function MerchantPresentationController:_getInteractiveTarget(): GuiObject?
	local root = self._activeRoot
	if not (root and root.Visible and root.Parent) then
		return nil
	end

	local runtimeWrapper = self._runtimeWrapperByRoot[root]
	if runtimeWrapper and runtimeWrapper.Visible and runtimeWrapper.Parent then
		return runtimeWrapper
	end

	return root
end

function MerchantPresentationController:_isPointInsideActiveShop(point: Vector2): boolean
	local interactiveTarget = self:_getInteractiveTarget()
	if not interactiveTarget then
		return false
	end

	if isPointInsideGuiObject(interactiveTarget, point) then
		return true
	end

	local playerGui = self:_getPlayerGui()
	for _, guiObject in ipairs(playerGui:GetGuiObjectsAtPosition(point.X, point.Y)) do
		if guiObject == interactiveTarget or guiObject:IsDescendantOf(interactiveTarget) then
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

	local overlay = self:_getModalRoot():FindFirstChild(OVERLAY_NAME)
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
		overlay.ZIndex = 100
		overlay.Visible = false
		overlay.Parent = self:_getModalRoot()
	end

	self._overlay = overlay
	return overlay
end

function MerchantPresentationController:_ensureBackdrop(): TextButton
	if self._backdrop and self._backdrop.Parent then
		return self._backdrop
	end

	local backdrop = self:_getModalRoot():FindFirstChild(BACKDROP_NAME)
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
		backdrop.ZIndex = 10
		backdrop.Visible = false
		backdrop.Parent = self:_getModalRoot()
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

function MerchantPresentationController:_cleanupLegacyRuntimeContent(root: GuiObject)
	local content = root:FindFirstChild(CONTENT_GROUP_NAME)
	if content and content:IsA("CanvasGroup") then
		for _, child in ipairs(content:GetChildren()) do
			child.Parent = root
		end
		content:Destroy()
	end

	local scale = root:FindFirstChild(SCALE_NAME)
	if scale and scale:IsA("UIScale") then
		scale:Destroy()
	end
end

function MerchantPresentationController:_ensureRuntimeContent(root: GuiObject): TransitionWrapperState
	local runtimeWrapper = self._runtimeWrapperByRoot[root]
	local runtimeContent = self._runtimeContentByRoot[root]
	local runtimeScale = self._runtimeScaleByRoot[root]
	local modalRoot = self:_getModalRoot()

	if runtimeWrapper and runtimeContent and runtimeScale then
		if runtimeWrapper.Parent == modalRoot and runtimeContent.Parent == runtimeWrapper and runtimeScale.Parent == runtimeWrapper then
			runtimeWrapper.ClipsDescendants = false
			runtimeContent.ClipsDescendants = false
			return {
				wrapper = runtimeWrapper,
				content = runtimeContent,
				scale = runtimeScale,
			}
		end
	end

	local wrapper = modalRoot:FindFirstChild(TRANSITION_WRAPPER_NAME)
	if wrapper and not wrapper:IsA("Frame") then
		wrapper:Destroy()
		wrapper = nil
	end

	if not wrapper then
		wrapper = Instance.new("Frame")
		wrapper.Name = TRANSITION_WRAPPER_NAME
		wrapper.BackgroundTransparency = 1
		wrapper.BorderSizePixel = 0
		wrapper.ClipsDescendants = false
		wrapper.Visible = false
		wrapper.Parent = modalRoot
	end

	local content = wrapper:FindFirstChild(CONTENT_GROUP_NAME)
	if content and not content:IsA("CanvasGroup") then
		content:Destroy()
		content = nil
	end

	if not content then
		content = Instance.new("CanvasGroup")
		content.Name = CONTENT_GROUP_NAME
		content.BackgroundTransparency = 1
		content.ClipsDescendants = false
		content.Size = UDim2.fromScale(1, 1)
		content.Position = UDim2.fromScale(0, 0)
		content.Parent = wrapper
	end

	local scale = wrapper:FindFirstChild(SCALE_NAME)
	if scale and not scale:IsA("UIScale") then
		scale:Destroy()
		scale = nil
	end

	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = SCALE_NAME
		scale.Parent = wrapper
	end

	wrapper.ClipsDescendants = false
	content.ClipsDescendants = false
	self._runtimeWrapperByRoot[root] = wrapper
	self._runtimeContentByRoot[root] = content
	self._runtimeScaleByRoot[root] = scale

	return {
		wrapper = wrapper,
		content = content,
		scale = scale,
	}
end

function MerchantPresentationController:_computeRootBounds(root: GuiObject): (Vector2, Vector2)
	local rootPosition = root.AbsolutePosition
	local rootSize = root.AbsoluteSize
	local minX = rootPosition.X
	local minY = rootPosition.Y
	local maxX = rootPosition.X + rootSize.X
	local maxY = rootPosition.Y + rootSize.Y

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			local descendantPosition = descendant.AbsolutePosition
			local descendantSize = descendant.AbsoluteSize
			minX = math.min(minX, descendantPosition.X)
			minY = math.min(minY, descendantPosition.Y)
			maxX = math.max(maxX, descendantPosition.X + descendantSize.X)
			maxY = math.max(maxY, descendantPosition.Y + descendantSize.Y)
		end
	end

	local flooredMin = Vector2.new(math.floor(minX), math.floor(minY))
	local ceiledMax = Vector2.new(math.ceil(maxX), math.ceil(maxY))
	return flooredMin, Vector2.new(math.max(1, ceiledMax.X - flooredMin.X), math.max(1, ceiledMax.Y - flooredMin.Y))
end

function MerchantPresentationController:_restoreShopRoot(root: GuiObject)
	local snapshot = self._rootLayoutSnapshotsByRoot[root]
	local runtimeWrapper = self._runtimeWrapperByRoot[root]
	local runtimeContent = self._runtimeContentByRoot[root]
	local runtimeScale = self._runtimeScaleByRoot[root]

	if runtimeContent and root.Parent == runtimeContent and snapshot then
		root.Parent = snapshot.parent
	end

	if snapshot then
		root.AnchorPoint = snapshot.anchorPoint
		root.Position = snapshot.position
		root.Size = snapshot.size
		root.ZIndex = snapshot.zIndex
		root.BackgroundTransparency = snapshot.backgroundTransparency
		root.Visible = snapshot.visible
		self._rootLayoutSnapshotsByRoot[root] = nil
	end

	if runtimeScale and runtimeScale.Parent then
		runtimeScale.Scale = 1
	end

	if runtimeContent and runtimeContent.Parent then
		runtimeContent.GroupTransparency = 1
	end

	if runtimeWrapper and runtimeWrapper.Parent then
		runtimeWrapper.Visible = false
	end
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
	blur.Enabled = if enabled == nil then targetSize > 0 else enabled

	if self._blurTween then
		self._blurTween:Cancel()
		self._blurTween = nil
	end

	if tweenInfo then
		self._blurTween = TweenService:Create(blur, tweenInfo, {
			Size = targetSize,
		})
		self._blurTween:Play()
	else
		blur.Size = targetSize
	end

	if targetSize <= 0 then
		if tweenInfo then
			task.delay(tweenInfo.Time, function()
				if blur.Size <= 0.01 then
					blur.Enabled = false
				end
			end)
		else
			blur.Enabled = false
		end
	end
end

function MerchantPresentationController:_setCameraBase(cameraPart: BasePart?, frameName: string)
	self._activeCameraPart = cameraPart
	if not cameraPart then
		if not self._warnedMissingCameraForFrame[frameName] then
			self._warnedMissingCameraForFrame[frameName] = true
			warn(string.format("[MerchantPresentationController] No camera part was resolved for '%s'.", frameName))
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

function MerchantPresentationController:_prepareShopRoot(root: GuiObject)
	self:_cleanupLegacyRuntimeContent(root)
	self:_restoreShopRoot(root)

	local originalParent = root.Parent or self:_getModalRoot()
	local originalPosition = root.Position
	local originalSize = root.Size
	local originalAnchorPoint = root.AnchorPoint
	local originalZIndex = root.ZIndex
	local originalVisibility = root.Visible
	local originalBackgroundTransparency = root.BackgroundTransparency

	root.Visible = true
	local rootAbsolutePosition = root.AbsolutePosition
	local rootAbsoluteSize = root.AbsoluteSize

	local runtimeState = self:_ensureRuntimeContent(root)
	local wrapperPosition, wrapperSize = self:_computeRootBounds(root)
	local rootOffset = rootAbsolutePosition - wrapperPosition

	self._rootLayoutSnapshotsByRoot[root] = {
		parent = originalParent,
		position = originalPosition,
		size = originalSize,
		anchorPoint = originalAnchorPoint,
		zIndex = originalZIndex,
		visible = originalVisibility,
		backgroundTransparency = originalBackgroundTransparency,
	}

	runtimeState.wrapper.Position = UDim2.fromOffset(wrapperPosition.X, wrapperPosition.Y)
	runtimeState.wrapper.Size = UDim2.fromOffset(wrapperSize.X, wrapperSize.Y)
	runtimeState.wrapper.ZIndex = 20
	runtimeState.wrapper.Visible = true
	runtimeState.content.ZIndex = runtimeState.wrapper.ZIndex + 1
	runtimeState.content.GroupTransparency = 1
	runtimeState.scale.Scale = INITIAL_SCALE

	root.Parent = runtimeState.content
	root.AnchorPoint = Vector2.zero
	root.Position = UDim2.fromOffset(rootOffset.X, rootOffset.Y)
	root.Size = UDim2.fromOffset(rootAbsoluteSize.X, rootAbsoluteSize.Y)
	root.ZIndex = runtimeState.content.ZIndex + 1
	root.Visible = true
end

function MerchantPresentationController:_playOpenReveal(root: GuiObject)
	local runtimeState = self:_ensureRuntimeContent(root)
	local overlay = self:_ensureOverlay()

	local fadeTween = TweenService:Create(overlay, OPEN_REVEAL_TWEEN, {
		BackgroundTransparency = 1,
	})
	local groupTween = TweenService:Create(runtimeState.content, OPEN_REVEAL_TWEEN, {
		GroupTransparency = 0,
	})
	local scaleTween = TweenService:Create(runtimeState.scale, OPEN_SCALE_TWEEN, {
		Scale = 1,
	})

	fadeTween:Play()
	groupTween:Play()
	scaleTween:Play()

	fadeTween.Completed:Wait()
end

function MerchantPresentationController:_playCloseBlackout()
	local overlay = self:_ensureOverlay()
	overlay.Visible = true
	overlay.BackgroundTransparency = 1
	tweenAsync(overlay, CLOSE_BLACKOUT_TWEEN, {
		BackgroundTransparency = 0,
	})
end

function MerchantPresentationController:_playOpenBlackout()
	local overlay = self:_ensureOverlay()
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

function MerchantPresentationController:_restorePresentationState()
	local root = self._activeRoot
	if root then
		self:_restoreShopRoot(root)
	end

	local backdrop = self:_ensureBackdrop()
	backdrop.Visible = false
	backdrop.Active = false
	backdrop.BackgroundTransparency = 1

	self:_stopCameraParallax()
	self:_restoreCamera()
	self:_restorePlayer()
	self:_setBlurSize(0, nil, false)
	self:_restoreMainInterfaceSession()
end

function MerchantPresentationController:_resetTransitionState()
	self._activeFrameName = nil
	self._activeRoot = nil
	self._isOpen = false
	self._transitioning = false
	self._mainInterfaceDisabledBySession = false
end

function MerchantPresentationController:_recoverTransition(transitionName: string, err: any, closedFrameName: string?)
	warn(string.format("[MerchantPresentationController] %s transition failed: %s", transitionName, tostring(err)))
	self:_restorePresentationState()
	self:_hideOverlay()
	self:_resetTransitionState()

	if closedFrameName then
		self.Closed:Fire(closedFrameName)
	end
end

function MerchantPresentationController:_midpointOpen(frameName: string, root: GuiObject, options: OpenOptions?)
	self:_beginMainInterfaceSession()
	self:_freezePlayer()

	local backdrop = self:_ensureBackdrop()
	self:_prepareShopRoot(root)
	local runtimeWrapper = self._runtimeWrapperByRoot[root]
	backdrop.Visible = true
	backdrop.Active = true
	backdrop.ZIndex = math.max(0, (if runtimeWrapper then runtimeWrapper.ZIndex else root.ZIndex) - 1)
	backdrop.BackgroundTransparency = BACKDROP_TRANSPARENCY

	self:_setBlurSize(BLUR_SIZE, BLUR_TWEEN, true)
	self:_snapshotCamera()
	self:_setCameraBase(if options then options.cameraPart else nil, frameName)
	self.FramePrepared:Fire(frameName, root, options)
	self:_bindCloseButton(frameName, root)
end

function MerchantPresentationController:_midpointClose()
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

function MerchantPresentationController:Open(frameName: string, options: OpenOptions?): boolean
	self:OnStart()

	if self._transitioning then
		return false
	end

	if self._isOpen and self._activeFrameName == frameName then
		return true
	end

	local root = self:_getShopRoot(frameName)
	if not root then
		warn(string.format("[MerchantPresentationController] ModalRoot.%s was not found.", frameName))
		return false
	end

	self._transitioning = true
	self._activeFrameName = frameName
	self._activeRoot = root

	local ok, err = xpcall(function()
		self:_playOpenBlackout()
		self:_midpointOpen(frameName, root, options)
		self:_playOpenReveal(root)
		self:_hideOverlay()
		self:_startCameraParallax(if options then options.cameraPart else nil)
	end, debug.traceback)

	if not ok then
		self:_recoverTransition("open", err, nil)
		return false
	end

	self._isOpen = true
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
		self:_midpointClose()
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
