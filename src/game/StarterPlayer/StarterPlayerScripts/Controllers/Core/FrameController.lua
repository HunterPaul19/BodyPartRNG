local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)
local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)
local FrameController = {}

FrameController.CloseTagName = "close"
FrameController.ModalRootName = "ModalRoot"
FrameController.SystemOverlaysName = "SystemOverlays"
FrameController.BackdropName = "ModalBackdrop"
FrameController.VignetteName = "ModalVignette"
FrameController.OpenTween = TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
FrameController.CloseTween = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
FrameController.OverlayTween = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
FrameController.BackdropTransparency = 0.5
FrameController.VignetteTransparency = 0.35
FrameController.ClosedBottomPadding = 32

local MENU_OPEN_SOUND_NAME = "MenuOpen"
local MENU_CLOSE_SOUND_NAME = "MenuClose"

local function warnf(message: string, ...)
	Logger.Warn(string.format("[FrameController] " .. message, ...))
end

local function isPointInsideGuiObject(guiObject: GuiObject, point: Vector2): boolean
	local absolutePosition = guiObject.AbsolutePosition
	local absoluteSize = guiObject.AbsoluteSize

	return point.X >= absolutePosition.X
		and point.X <= absolutePosition.X + absoluteSize.X
		and point.Y >= absolutePosition.Y
		and point.Y <= absolutePosition.Y + absoluteSize.Y
end

function FrameController:_ensureState()
	if self._started then
		return
	end

	self._player = Players.LocalPlayer
	self._playerGui = nil
	self._modalRoot = nil
	self._backdrop = nil
	self._vignette = nil
	self._backdropConnection = nil
	self._connections = {}
	self._closeButtonConnections = {}
	self._frameStates = {}
	self._framesByName = {}
	self._currentFrame = nil
	self._currentName = nil
	self._currentUsesOverlay = true
	self._pendingOpen = nil
	self._pendingOpenOptions = nil
	self._transitionMode = nil
	self._frameTween = nil
	self._frameTweenConnection = nil
	self._backdropTween = nil
	self._vignetteTween = nil
	self._warnedMissingModalRoot = false
	self._startupDiagnosticEmitted = false
	self._started = true
end

function FrameController:_getPlayerGui(): PlayerGui?
	self:_ensureState()

	if self._playerGui and self._playerGui.Parent then
		return self._playerGui
	end

	local player = self._player
	if not player then
		return nil
	end

	self._playerGui = player:WaitForChild("PlayerGui")
	return self._playerGui
end

function FrameController:_findVignetteAsset(): string?
	local playerGui = self:_getPlayerGui()
	if not playerGui then
		return nil
	end

	local screenEffects = playerGui:FindFirstChild("ScreenEffects")
	if not screenEffects then
		return nil
	end

	local vignette = screenEffects:FindFirstChild("Vignette", true)
	if vignette and vignette:IsA("ImageLabel") and vignette.Image ~= "" then
		return vignette.Image
	end

	return nil
end

function FrameController:_isClickInsideCurrentFrame(point: Vector2): boolean
	local frame = self._currentFrame
	if not frame or not frame.Visible then
		return false
	end

	if isPointInsideGuiObject(frame, point) then
		return true
	end

	local playerGui = self:_getPlayerGui()
	if not playerGui then
		return false
	end

	for _, guiObject in ipairs(playerGui:GetGuiObjectsAtPosition(point.X, point.Y)) do
		if guiObject == frame or guiObject:IsDescendantOf(frame) then
			return true
		end
	end

	return false
end

function FrameController:_shouldCloseFromBackdropClick(): boolean
	if not self._currentFrame or self._transitionMode == "closing" then
		return false
	end

	local mouseLocation = UserInputService:GetMouseLocation()
	local pointerPosition = Vector2.new(mouseLocation.X, mouseLocation.Y)

	return not self:_isClickInsideCurrentFrame(pointerPosition)
end

function FrameController:_getModalRoot(shouldWarn: boolean?): ScreenGui?
	self:_ensureState()

	if self._modalRoot and self._modalRoot.Parent then
		return self._modalRoot
	end

	local playerGui = self:_getPlayerGui()
	if not playerGui then
		return nil
	end

	local modalRoot = playerGui:FindFirstChild(self.ModalRootName)

	if modalRoot and modalRoot:IsA("ScreenGui") then
		modalRoot.IgnoreGuiInset = true
		modalRoot.Enabled = true
		modalRoot.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		self._modalRoot = modalRoot
		self._warnedMissingModalRoot = false
		return modalRoot
	end

	if shouldWarn ~= false and not self._warnedMissingModalRoot then
		self._warnedMissingModalRoot = true
		warnf("Expected PlayerGui.%s to exist as a ScreenGui.", self.ModalRootName)
	end

	return nil
end

function FrameController:_getSystemOverlays(): Folder?
	local modalRoot = self:_getModalRoot()
	if not modalRoot then
		return nil
	end

	local overlays = modalRoot:FindFirstChild(self.SystemOverlaysName)
	if overlays and not overlays:IsA("Folder") then
		overlays:Destroy()
		overlays = nil
	end

	if not overlays then
		overlays = Instance.new("Folder")
		overlays.Name = self.SystemOverlaysName
		overlays.Parent = modalRoot
	end

	return overlays
end

function FrameController:_registerCloseButton(instance: Instance)
	local playerGui = self:_getPlayerGui()
	if not playerGui or not instance:IsDescendantOf(playerGui) then
		return
	end

	if not instance:IsA("GuiButton") then
		warnf("Ignoring tagged close instance '%s' because it is not a GuiButton.", instance:GetFullName())
		return
	end

	if self._closeButtonConnections[instance] then
		return
	end

	self._closeButtonConnections[instance] = instance.Activated:Connect(function()
		self:CloseFrame()
	end)
end

function FrameController:_unregisterCloseButton(instance: Instance)
	local connection = self._closeButtonConnections[instance]
	if not connection then
		return
	end

	connection:Disconnect()
	self._closeButtonConnections[instance] = nil
end

function FrameController:_refreshCloseButtons()
	local playerGui = self:_getPlayerGui()
	if not playerGui then
		return
	end

	local activeButtons = {}

	for _, instance in ipairs(CollectionService:GetTagged(self.CloseTagName)) do
		if instance:IsDescendantOf(playerGui) then
			activeButtons[instance] = true
			self:_registerCloseButton(instance)
		end
	end

	for instance in pairs(self._closeButtonConnections) do
		if not activeButtons[instance] or not instance.Parent then
			self:_unregisterCloseButton(instance)
		end
	end
end

function FrameController:_ensureOverlay()
	local modalRoot = self:_getModalRoot()
	if not modalRoot then
		return nil, nil
	end
	local overlays = self:_getSystemOverlays()
	if not overlays then
		return nil, nil
	end

	local backdrop = overlays:FindFirstChild(self.BackdropName)
	local legacyBackdrop = modalRoot:FindFirstChild(self.BackdropName)
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
		backdrop.Name = self.BackdropName
		backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
		backdrop.BackgroundTransparency = 1
		backdrop.AutoButtonColor = false
		backdrop.BorderSizePixel = 0
		backdrop.Text = ""
		backdrop.Visible = false
		backdrop.Size = UDim2.fromScale(1, 1)
		backdrop.ZIndex = 0
		backdrop.Parent = overlays
	end

	local vignette = overlays:FindFirstChild(self.VignetteName)
	local legacyVignette = modalRoot:FindFirstChild(self.VignetteName)
	if legacyVignette and legacyVignette ~= vignette then
		if legacyVignette:IsA("ImageLabel") and not vignette then
			legacyVignette.Parent = overlays
			vignette = legacyVignette
		else
			legacyVignette:Destroy()
		end
	end
	if vignette and not vignette:IsA("ImageLabel") then
		vignette:Destroy()
		vignette = nil
	end

	if not vignette then
		vignette = Instance.new("ImageLabel")
		vignette.Name = self.VignetteName
		vignette.BackgroundTransparency = 1
		vignette.BorderSizePixel = 0
		vignette.ScaleType = Enum.ScaleType.Stretch
		vignette.Size = UDim2.fromScale(1, 1)
		vignette.Visible = false
		vignette.ZIndex = 1
		vignette.Parent = overlays
	end

	vignette.Image = self:_findVignetteAsset() or ""
	vignette.ImageColor3 = Color3.new(0, 0, 0)
	vignette.ImageTransparency = 1

	if self._backdrop ~= backdrop and self._backdropConnection then
		self._backdropConnection:Disconnect()
		self._backdropConnection = nil
	end

	self._backdrop = backdrop
	self._vignette = vignette

	if not self._backdropConnection then
		self._backdropConnection = backdrop.Activated:Connect(function()
			if self:_shouldCloseFromBackdropClick() then
				self:CloseFrame()
			end
		end)
	end

	return backdrop, vignette
end

function FrameController:_cancelFrameTween()
	if self._frameTween then
		self._frameTween:Cancel()
		self._frameTween = nil
	end

	if self._frameTweenConnection then
		self._frameTweenConnection:Disconnect()
		self._frameTweenConnection = nil
	end
end

function FrameController:_cancelOverlayTweens()
	if self._backdropTween then
		self._backdropTween:Cancel()
		self._backdropTween = nil
	end

	if self._vignetteTween then
		self._vignetteTween:Cancel()
		self._vignetteTween = nil
	end
end

function FrameController:_cancelTweens()
	self:_cancelFrameTween()
	self:_cancelOverlayTweens()
end

function FrameController:_setOverlayState(visible: boolean, instant: boolean?)
	local backdrop, vignette = self:_ensureOverlay()
	if not backdrop then
		return
	end

	self:_cancelOverlayTweens()

	local hasVignette = vignette ~= nil and vignette.Image ~= ""

	if visible then
		backdrop.Visible = true
		if hasVignette and vignette then
			vignette.Visible = true
		end
	end

	local backdropTransparency = visible and self.BackdropTransparency or 1
	local vignetteTransparency = visible and self.VignetteTransparency or 1

	if instant then
		backdrop.BackgroundTransparency = backdropTransparency

		if vignette then
			vignette.ImageTransparency = vignetteTransparency
			vignette.Visible = hasVignette and visible
		end

		if not visible then
			backdrop.Visible = false
		end

		return
	end

	self._backdropTween = TweenService:Create(backdrop, self.OverlayTween, {
		BackgroundTransparency = backdropTransparency,
	})
	self._backdropTween:Play()

	if vignette and hasVignette then
		self._vignetteTween = TweenService:Create(vignette, self.OverlayTween, {
			ImageTransparency = vignetteTransparency,
		})
		self._vignetteTween:Play()
	elseif vignette then
		vignette.Visible = false
	end
end

function FrameController:_getFrameState(frame: GuiObject)
	local state = self._frameStates[frame]
	if state then
		return state
	end

	state = {
		OpenPosition = frame.Position,
		OpenAnchorPoint = frame.AnchorPoint,
		OpenSize = frame.Size,
	}

	self._frameStates[frame] = state

	return state
end

function FrameController:_getClosedPosition(frame: GuiObject): UDim2
	local state = self:_getFrameState(frame)
	local modalRoot = self:_getModalRoot(false)
	local viewportHeight = if modalRoot and modalRoot.AbsoluteSize.Y > 0
		then modalRoot.AbsoluteSize.Y
		else if workspace.CurrentCamera then workspace.CurrentCamera.ViewportSize.Y else 720
	local frameTop = frame.AbsolutePosition.Y
	local shiftPixels = math.max(
		self.ClosedBottomPadding,
		viewportHeight + self.ClosedBottomPadding - frameTop
	)

	return UDim2.new(
		state.OpenPosition.X.Scale,
		state.OpenPosition.X.Offset,
		state.OpenPosition.Y.Scale,
		state.OpenPosition.Y.Offset + shiftPixels
	)
end

function FrameController:_getRegisteredFrameNames(): { string }
	local names = {}
	for name in pairs(self._framesByName) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function FrameController:_getActiveProfileId(): string
	return PlaceProfile.GetActiveProfile().id
end

function FrameController:_registerFrameCandidate(
	instance: Instance,
	modalRoot: ScreenGui,
	namesToInstances: { [string]: GuiObject },
	duplicateNames: { [string]: { GuiObject } },
	options: { sourceLabel: string }
)
	local sourceLabel = options.sourceLabel

	if not instance:IsA("GuiObject") then
		warnf("Ignoring %s '%s' because it is not a GuiObject.", sourceLabel, instance:GetFullName())
		return
	end

	if instance.Parent ~= modalRoot then
		warnf(
			"Ignoring %s '%s' because modal frames must be direct GuiObject children of PlayerGui.%s.",
			sourceLabel,
			instance:GetFullName(),
			self.ModalRootName
		)
		return
	end

	local existing = namesToInstances[instance.Name]
	if existing == instance then
		return
	end

	if existing then
		duplicateNames[instance.Name] = duplicateNames[instance.Name] or { existing }
		table.insert(duplicateNames[instance.Name], instance)
		namesToInstances[instance.Name] = nil
		return
	end

	if duplicateNames[instance.Name] then
		table.insert(duplicateNames[instance.Name], instance)
		return
	end

	namesToInstances[instance.Name] = instance
	self:_getFrameState(instance)
	instance.Active = true

	if instance ~= self._currentFrame then
		instance.Visible = false
		instance.AnchorPoint = self._frameStates[instance].OpenAnchorPoint
		instance.Position = self._frameStates[instance].OpenPosition
		instance.Size = self._frameStates[instance].OpenSize
	end
end

function FrameController:_refreshRegistry()
	local playerGui = self:_getPlayerGui()
	local modalRoot = self:_getModalRoot(false)
	if not playerGui or not modalRoot then
		self._framesByName = {}
		return
	end

	local namesToInstances = {}
	local duplicateNames = {}

	for _, child in ipairs(modalRoot:GetChildren()) do
		if not child:IsA("GuiObject") then
			continue
		end

		self:_registerFrameCandidate(child, modalRoot, namesToInstances, duplicateNames, {
			sourceLabel = "direct modal frame",
		})
	end

	for name, instances in pairs(duplicateNames) do
		local paths = {}
		for _, instance in ipairs(instances) do
			table.insert(paths, instance:GetFullName())
		end

		warnf("Duplicate modal frame name '%s' detected. Refusing to register: %s", name, table.concat(paths, ", "))
	end

	self._framesByName = namesToInstances

	if self._currentFrame and not self._currentFrame:IsDescendantOf(playerGui) then
		self:_forceCloseCurrent(true)
	end
end

function FrameController:_beginOpen(name: string, frame: GuiObject, options: { useOverlay: boolean? }?)
	local modalRoot = self:_getModalRoot()
	if not modalRoot then
		return false
	end

	self:_cancelTweens()
	self._pendingOpen = nil
	self._pendingOpenOptions = nil
	self._currentFrame = frame
	self._currentName = name
	self._currentUsesOverlay = not (options and options.useOverlay == false)
	self._transitionMode = "opening"
	SoundUtil.Play(MENU_OPEN_SOUND_NAME)

	local state = self:_getFrameState(frame)
	frame.AnchorPoint = state.OpenAnchorPoint
	frame.Position = state.OpenPosition
	frame.Size = state.OpenSize
	frame.Visible = true
	modalRoot.Enabled = true
	frame.Position = self:_getClosedPosition(frame)

	if self._currentUsesOverlay then
		self:_setOverlayState(true, false)
	end

	self._frameTween = TweenService:Create(frame, self.OpenTween, {
		Position = state.OpenPosition,
	})

	self._frameTweenConnection = self._frameTween.Completed:Connect(function()
		self:_cancelFrameTween()

		if self._currentFrame ~= frame or self._transitionMode ~= "opening" then
			return
		end

		frame.Position = state.OpenPosition
		frame.Size = state.OpenSize
		self._transitionMode = nil

		if self._pendingOpen and self._pendingOpen ~= name then
			local pendingName = self._pendingOpen
			local pendingOptions = self._pendingOpenOptions
			self._pendingOpen = nil
			self._pendingOpenOptions = nil
			self:OpenFrame(pendingName, pendingOptions)
			return
		end

		self._pendingOpen = nil
		self._pendingOpenOptions = nil
	end)

	self._frameTween:Play()
	return true
end

function FrameController:_forceCloseCurrent(instant: boolean?)
	local frame = self._currentFrame
	if frame then
		local state = self._frameStates[frame]
		if state then
			frame.AnchorPoint = state.OpenAnchorPoint
			frame.Position = state.OpenPosition
			frame.Size = state.OpenSize
		end
		frame.Visible = false
	end

	self:_cancelTweens()
	if self._currentUsesOverlay then
		self:_setOverlayState(false, instant == nil and true or instant)
	end
	self._currentFrame = nil
	self._currentName = nil
	self._currentUsesOverlay = true
	self._pendingOpen = nil
	self._pendingOpenOptions = nil
	self._transitionMode = nil
end

function FrameController:_beginClose()
	local frame = self._currentFrame
	if not frame then
		return false
	end

	self:_cancelTweens()
	self._transitionMode = "closing"
	SoundUtil.Play(MENU_CLOSE_SOUND_NAME)

	local name = self._currentName
	local usesOverlay = self._currentUsesOverlay
	local state = self:_getFrameState(frame)
	if usesOverlay then
		self:_setOverlayState(false, false)
	end

	self._frameTween = TweenService:Create(frame, self.CloseTween, {
		Position = self:_getClosedPosition(frame),
	})

	self._frameTweenConnection = self._frameTween.Completed:Connect(function()
		self:_cancelFrameTween()

		if self._currentFrame ~= frame or self._transitionMode ~= "closing" then
			return
		end

		frame.Visible = false
		frame.AnchorPoint = state.OpenAnchorPoint
		frame.Position = state.OpenPosition
		frame.Size = state.OpenSize
		self._currentFrame = nil
		self._currentName = nil
		self._currentUsesOverlay = true
		self._transitionMode = nil
		if usesOverlay then
			self:_setOverlayState(false, true)
		end

		if self._pendingOpen then
			local pendingName = self._pendingOpen
			local pendingOptions = self._pendingOpenOptions
			self._pendingOpen = nil
			self._pendingOpenOptions = nil
			self:OpenFrame(pendingName, pendingOptions)
			return
		end

		self._pendingOpen = nil
		self._pendingOpenOptions = nil
	end)

	self._frameTween:Play()

	if name then
		return true
	end

	return false
end

function FrameController:GetOpenFrame(): string?
	self:_ensureState()
	return self._currentName
end

function FrameController:IsOpen(name: string): boolean
	self:_ensureState()
	return self._currentName == name and self._currentFrame ~= nil and self._transitionMode ~= "closing"
end

function FrameController:OpenFrame(name: string, options: { useOverlay: boolean? }?): boolean
	self:_ensureState()

	self:_refreshRegistry()

	local frame = self._framesByName[name]
	if not frame then
		local modalRoot = self:_getModalRoot(false)
		local registeredNames = self:_getRegisteredFrameNames()
		warnf(
			"No registered modal frame named '%s' was found. profile='%s' modalRootExists=%s registered=[%s]",
			name,
			self:_getActiveProfileId(),
			tostring(modalRoot ~= nil),
			table.concat(registeredNames, ", ")
		)
		return false
	end

	if self._currentName == name and self._currentFrame == frame and self._transitionMode ~= "closing" then
		return true
	end

	if self._currentFrame then
		self._pendingOpen = name
		self._pendingOpenOptions = options

		if self._transitionMode ~= "closing" then
			self:_beginClose()
		end

		return true
	end

	return self:_beginOpen(name, frame, options)
end

function FrameController:CloseFrame(name: string?): boolean
	self:_ensureState()

	if not self._currentFrame then
		self._pendingOpen = nil
		self._pendingOpenOptions = nil
		return false
	end

	if name and name ~= self._currentName then
		return false
	end

	self._pendingOpen = nil
	self._pendingOpenOptions = nil

	if self._transitionMode == "closing" then
		return true
	end

	return self:_beginClose()
end

function FrameController:ToggleFrame(name: string): boolean
	self:_ensureState()

	if self._currentName == name and self._currentFrame then
		if self._transitionMode == "closing" then
			self._pendingOpen = name
			self._pendingOpenOptions = nil
			return true
		end

		return self:CloseFrame(name)
	end

	return self:OpenFrame(name)
end

function FrameController:OnStart()
	self:_ensureState()

	local playerGui = self:_getPlayerGui()
	if not playerGui then
		return
	end

	self:_getModalRoot()
	self:_ensureOverlay()
	self:_refreshRegistry()
	self:_refreshCloseButtons()
	if not self._startupDiagnosticEmitted then
		self._startupDiagnosticEmitted = true
		warnf(
			"Initialized for profile '%s' with registered frames: [%s]",
			self:_getActiveProfileId(),
			table.concat(self:_getRegisteredFrameNames(), ", ")
		)
	end

	table.insert(self._connections, CollectionService:GetInstanceAddedSignal(self.CloseTagName):Connect(function(instance)
		self:_registerCloseButton(instance)
	end))
	table.insert(self._connections, CollectionService:GetInstanceRemovedSignal(self.CloseTagName):Connect(function(instance)
		self:_unregisterCloseButton(instance)
	end))
	table.insert(self._connections, playerGui.DescendantAdded:Connect(function(instance)
		local modalRoot = self:_getModalRoot(false)
		if instance.Name == self.ModalRootName
			or (modalRoot ~= nil and instance.Parent == modalRoot and instance:IsA("GuiObject"))
		then
			self._modalRoot = nil
			self:_ensureOverlay()
			self:_refreshRegistry()
		end

		if CollectionService:HasTag(instance, self.CloseTagName) then
			self:_refreshCloseButtons()
		end
	end))
	table.insert(self._connections, playerGui.DescendantRemoving:Connect(function(instance)
		if CollectionService:HasTag(instance, self.CloseTagName) then
			self:_unregisterCloseButton(instance)
		end

		local modalRoot = self._modalRoot
		if instance == self._currentFrame
			or instance.Name == self.ModalRootName
			or (modalRoot ~= nil and instance.Parent == modalRoot and instance:IsA("GuiObject"))
		then
			task.defer(function()
				self._modalRoot = nil
				self:_ensureOverlay()
				self:_refreshRegistry()
			end)
		end
	end))
end

return FrameController
