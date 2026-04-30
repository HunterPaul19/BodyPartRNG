local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)

local HUDWindowController = {}

HUDWindowController.PopScale = 0.9
HUDWindowController.OpenTween = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
HUDWindowController.CloseTween = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
HUDWindowController.EffectsTween = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
HUDWindowController.BlurName = "HUDWindowBlur"
HUDWindowController.BlurSize = 18
HUDWindowController.UseBlur = true
HUDWindowController.UseFOV = true
HUDWindowController.OpenFOV = 72
HUDWindowController.ClosedFOV = 70
HUDWindowController.AutoBindCloseButtons = false
HUDWindowController.CloseButtonName = "Close"

local MENU_OPEN_SOUND_NAME = "MenuOpen"
local MENU_CLOSE_SOUND_NAME = "MenuClose"

type TransparencySnapshot = {
	instance: Instance,
	property: string,
	value: number,
}

local function scaleUDim2(value: UDim2, factor: number): UDim2
	return UDim2.new(
		value.X.Scale * factor,
		value.X.Offset * factor,
		value.Y.Scale * factor,
		value.Y.Offset * factor
	)
end

local function addTransparencySnapshot(snapshots: { TransparencySnapshot }, instance: Instance, property: string)
	local ok, value = pcall(function()
		return (instance :: any)[property]
	end)

	if ok and typeof(value) == "number" then
		table.insert(snapshots, {
			instance = instance,
			property = property,
			value = value,
		})
	end
end

local function captureTransparencySnapshots(root: GuiObject): { TransparencySnapshot }
	local snapshots = {}

	local function visit(instance: Instance)
		if instance:IsA("GuiObject") then
			addTransparencySnapshot(snapshots, instance, "BackgroundTransparency")
		end
		if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
			addTransparencySnapshot(snapshots, instance, "TextTransparency")
			addTransparencySnapshot(snapshots, instance, "TextStrokeTransparency")
		end
		if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
			addTransparencySnapshot(snapshots, instance, "ImageTransparency")
		end
		if instance:IsA("ScrollingFrame") then
			addTransparencySnapshot(snapshots, instance, "ScrollBarImageTransparency")
		end
		if instance:IsA("UIStroke") then
			addTransparencySnapshot(snapshots, instance, "Transparency")
		end
	end

	visit(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		visit(descendant)
	end

	return snapshots
end

local function resolveTransparencyTarget(originalValue: number, visibleAlpha: number): number
	return 1 - ((1 - originalValue) * visibleAlpha)
end

function HUDWindowController:_ensureState()
	if self._started then
		return
	end

	self._windows = {}
	self._buttons = {}
	self._closeButtons = {}
	self._hudObjects = {}
	self._windowConnections = {}
	self._buttonConnections = {}
	self._closeButtonConnections = {}
	self._openSizes = {}
	self._fadeSnapshots = {}
	self._tweens = {}
	self._fadeTweens = {}
	self._hudVisibility = {}
	self._currentOpen = nil
	self._blur = nil
	self._blurTween = nil
	self._fovTween = nil
	self._started = true
end

function HUDWindowController:_getBlur(): BlurEffect
	if self._blur and self._blur.Parent == Lighting then
		return self._blur
	end

	local existing = Lighting:FindFirstChild(self.BlurName)
	if existing and existing:IsA("BlurEffect") then
		self._blur = existing
	else
		local blur = Instance.new("BlurEffect")
		blur.Name = self.BlurName
		blur.Size = 0
		blur.Enabled = true
		blur.Parent = Lighting
		self._blur = blur
	end

	return self._blur
end

function HUDWindowController:_cancelSceneTweens()
	if self._blurTween then
		self._blurTween:Cancel()
		self._blurTween = nil
	end

	if self._fovTween then
		self._fovTween:Cancel()
		self._fovTween = nil
	end
end

function HUDWindowController:_setSceneEffects(active: boolean, instant: boolean)
	local camera = workspace.CurrentCamera

	self:_cancelSceneTweens()

	if self.UseBlur then
		local blur = self:_getBlur()
		local blurTarget = active and self.BlurSize or 0

		if instant then
			blur.Size = blurTarget
		else
			self._blurTween = TweenService:Create(blur, self.EffectsTween, { Size = blurTarget })
			self._blurTween:Play()
		end
	end

	if self.UseFOV and camera then
		local fovTarget = active and self.OpenFOV or self.ClosedFOV

		if instant then
			camera.FieldOfView = fovTarget
		else
			self._fovTween = TweenService:Create(camera, self.EffectsTween, { FieldOfView = fovTarget })
			self._fovTween:Play()
		end
	end
end

function HUDWindowController:_cancelWindowTweens(name: string)
	if self._tweens[name] then
		self._tweens[name]:Cancel()
		self._tweens[name] = nil
	end

	if self._fadeTweens[name] then
		for _, tween in ipairs(self._fadeTweens[name]) do
			tween:Cancel()
		end
		self._fadeTweens[name] = nil
	end
end

function HUDWindowController:_captureWindowFade(name: string, window: GuiObject)
	self._fadeSnapshots[name] = captureTransparencySnapshots(window)
end

function HUDWindowController:_setWindowFade(name: string, visibleAlpha: number)
	local snapshots = self._fadeSnapshots[name]
	if not snapshots then
		return
	end

	for _, snapshot in ipairs(snapshots) do
		if snapshot.instance.Parent then
			pcall(function()
				(snapshot.instance :: any)[snapshot.property] = resolveTransparencyTarget(snapshot.value, visibleAlpha)
			end)
		end
	end
end

function HUDWindowController:_tweenWindowFade(name: string, visibleAlpha: number, tweenInfo: TweenInfo)
	local snapshots = self._fadeSnapshots[name]
	if not snapshots then
		return
	end

	self._fadeTweens[name] = {}
	for _, snapshot in ipairs(snapshots) do
		if snapshot.instance.Parent then
			local target = resolveTransparencyTarget(snapshot.value, visibleAlpha)
			local ok, tween = pcall(function()
				return TweenService:Create(snapshot.instance, tweenInfo, {
					[snapshot.property] = target,
				})
			end)

			if ok and tween then
				table.insert(self._fadeTweens[name], tween)
				tween:Play()
			end
		end
	end
end

function HUDWindowController:_setHudVisible(visible: boolean)
	for _, guiObject in ipairs(self._hudObjects) do
		if guiObject and guiObject.Parent then
			if self._hudVisibility[guiObject] == nil then
				self._hudVisibility[guiObject] = guiObject.Visible
			end

			if visible then
				guiObject.Visible = self._hudVisibility[guiObject] ~= false
			else
				guiObject.Visible = false
			end
		end
	end
end

function HUDWindowController:_prepareWindow(name: string)
	local window = self._windows[name]
	if not window then
		return
	end

	self._openSizes[name] = window.Size
	self:_captureWindowFade(name, window)
	self:_setWindowFade(name, 0)

	window.Visible = false

	if self.AutoBindCloseButtons then
		local closeButton = window:FindFirstChild(self.CloseButtonName, true)
		if closeButton and closeButton:IsA("GuiButton") then
			self:RegisterCloseButton(name, closeButton)
		end
	end
end

function HUDWindowController:RegisterWindow(name: string, window: GuiObject)
	self:_ensureState()
	if not window then
		return
	end

	self._windows[name] = window
	self:_prepareWindow(name)
end

function HUDWindowController:RegisterButton(name: string, button: GuiButton)
	self:_ensureState()

	self._buttons[name] = self._buttons[name] or {}
	table.insert(self._buttons[name], button)

	local connection = button.Activated:Connect(function()
		self:ToggleWindow(name)
	end)

	self._buttonConnections[name] = self._buttonConnections[name] or {}
	table.insert(self._buttonConnections[name], connection)
end

function HUDWindowController:RegisterCloseButton(name: string, button: GuiButton)
	self:_ensureState()

	self._closeButtons[name] = self._closeButtons[name] or {}
	table.insert(self._closeButtons[name], button)

	local connection = button.Activated:Connect(function()
		self:CloseWindow(name)
	end)

	self._closeButtonConnections[name] = self._closeButtonConnections[name] or {}
	table.insert(self._closeButtonConnections[name], connection)
end

function HUDWindowController:AddHudObject(guiObject: GuiObject)
	self:_ensureState()
	table.insert(self._hudObjects, guiObject)
end

function HUDWindowController:RemoveHudObject(guiObject: GuiObject)
	self:_ensureState()

	for index = #self._hudObjects, 1, -1 do
		if self._hudObjects[index] == guiObject then
			table.remove(self._hudObjects, index)
		end
	end

	self._hudVisibility[guiObject] = nil
end

function HUDWindowController:OpenWindow(name: string, forceOpen: boolean?)
	self:_ensureState()

	local window = self._windows[name]
	if not window then
		return
	end

	if self._currentOpen == name and window.Visible then
		if forceOpen then
			return
		end

		self:CloseWindow(name)
		return
	end

	if self._currentOpen and self._currentOpen ~= name then
		self:CloseWindow(self._currentOpen, false)
	end

	self:_cancelWindowTweens(name)

	local baseSize = self._openSizes[name] or window.Size
	self._openSizes[name] = baseSize

	local smallSize = scaleUDim2(baseSize, self.PopScale)

	SoundUtil.Play(MENU_OPEN_SOUND_NAME)
	window.Visible = true
	window.Size = smallSize
	self:_setWindowFade(name, 0)

	self._tweens[name] = TweenService:Create(window, self.OpenTween, { Size = baseSize })
	self._tweens[name]:Play()
	self:_tweenWindowFade(name, 1, self.OpenTween)

	self._currentOpen = name
	self:_setHudVisible(false)
	self:_setSceneEffects(true, false)
end

function HUDWindowController:CloseWindow(name: string, instant: boolean?)
	self:_ensureState()

	local window = self._windows[name]
	if not window then
		return
	end

	if not window.Visible and not instant then
		return
	end

	self:_cancelWindowTweens(name)

	local baseSize = self._openSizes[name] or window.Size
	self._openSizes[name] = baseSize
	local smallSize = scaleUDim2(baseSize, self.PopScale)

	if instant then
		self:_setWindowFade(name, 0)
		window.Visible = false
		window.Size = baseSize

		if self._currentOpen == name then
			self._currentOpen = nil
			self:_setHudVisible(true)
			self:_setSceneEffects(false, true)
		end

		return
	end

	SoundUtil.Play(MENU_CLOSE_SOUND_NAME)
	self._tweens[name] = TweenService:Create(window, self.CloseTween, { Size = smallSize })
	self._tweens[name]:Play()
	self:_tweenWindowFade(name, 0, self.CloseTween)

	local connection: RBXScriptConnection?
	connection = self._tweens[name].Completed:Connect(function()
		if connection then
			connection:Disconnect()
		end

		window.Visible = false
		window.Size = baseSize

		if self._currentOpen == name then
			self._currentOpen = nil
			self:_setHudVisible(true)
			self:_setSceneEffects(false, false)
		end
	end)
end

function HUDWindowController:ToggleWindow(name: string)
	self:_ensureState()

	local window = self._windows[name]
	if not window then
		return
	end

	if self._currentOpen == name and window.Visible then
		self:CloseWindow(name)
	else
		self:OpenWindow(name)
	end
end

function HUDWindowController:CloseCurrentWindow(instant: boolean?)
	self:_ensureState()
	if self._currentOpen then
		self:CloseWindow(self._currentOpen, instant)
	end
end

function HUDWindowController:OnStart()
	self:_ensureState()
	Logger.Print("HUDWindowController client initialized!")
end

return HUDWindowController
