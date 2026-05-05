local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")

local LOCAL_PLAYER = Players.LocalPlayer

local TELEPORT_GUI_NAME = "TeleportTransitionGui"
local ROOT_NAME = "Root"
local MESSAGE_LABEL_NAME = "MessageLabel"
local REMOTES_FOLDER_NAME = "Remotes"
local TELEPORT_TRANSITION_FOLDER_NAME = "TeleportTransition"
local PREPARE_REMOTE_NAME = "Prepare"
local DEFAULT_TRANSITION_TEXT = "Teleporting..."
local REMOTE_WAIT_TIMEOUT_SECONDS = 30
local FADE_IN_SECONDS = 0.18
local FADE_OUT_SECONDS = 0.2
local TELEPORT_GUI_DISPLAY_ORDER = 1000000

type TextGuiObject = TextLabel | TextButton | TextBox

type FadeTarget = {
	instance: Instance,
	property: string,
	visibleValue: number,
}

local TeleportTransitionController = {
	_started = false,
	_playerGui = nil :: PlayerGui?,
	_screenGui = nil :: ScreenGui?,
	_root = nil :: GuiObject?,
	_messageLabel = nil :: TextGuiObject?,
	_fadeTargets = {} :: { FadeTarget },
	_activeTweens = {} :: { Tween },
	_prepareConnection = nil :: RBXScriptConnection?,
	_failureConnection = nil :: RBXScriptConnection?,
	_transitionToken = 0,
}

local function isTextGuiObject(instance: Instance): boolean
	return instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")
end

local function addFadeTarget(targets: { FadeTarget }, instance: Instance, property: string, visibleValue: number?)
	if typeof(visibleValue) ~= "number" then
		return
	end

	table.insert(targets, {
		instance = instance,
		property = property,
		visibleValue = visibleValue,
	})
end

local function collectFadeTargets(root: Instance): { FadeTarget }
	local targets = {}

	local function capture(instance: Instance)
		if instance:IsA("GuiObject") then
			addFadeTarget(targets, instance, "BackgroundTransparency", instance.BackgroundTransparency)
		end

		if isTextGuiObject(instance) then
			local textGui = instance :: TextGuiObject
			addFadeTarget(targets, textGui, "TextTransparency", textGui.TextTransparency)
			addFadeTarget(targets, textGui, "TextStrokeTransparency", textGui.TextStrokeTransparency)
		elseif instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
			addFadeTarget(targets, instance, "ImageTransparency", instance.ImageTransparency)
		elseif instance:IsA("UIStroke") then
			addFadeTarget(targets, instance, "Transparency", instance.Transparency)
		end
	end

	capture(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		capture(descendant)
	end

	return targets
end

local function findRoot(screenGui: ScreenGui): GuiObject?
	local root = screenGui:FindFirstChild(ROOT_NAME, true)
	if root and root:IsA("GuiObject") then
		return root
	end

	for _, descendant in ipairs(screenGui:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			return descendant
		end
	end

	return nil
end

local function findMessageLabel(screenGui: ScreenGui): TextGuiObject?
	local label = screenGui:FindFirstChild(MESSAGE_LABEL_NAME, true)
	if label and isTextGuiObject(label) then
		return label :: TextGuiObject
	end

	for _, descendant in ipairs(screenGui:GetDescendants()) do
		if isTextGuiObject(descendant) then
			return descendant :: TextGuiObject
		end
	end

	return nil
end

local function createFallbackGui(): ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = TELEPORT_GUI_NAME
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = TELEPORT_GUI_DISPLAY_ORDER
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
	screenGui.Enabled = true

	local root = Instance.new("Frame")
	root.Name = ROOT_NAME
	root.BackgroundColor3 = Color3.new(0, 0, 0)
	root.BackgroundTransparency = 0
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Visible = true
	root.ZIndex = 1
	root.Parent = screenGui

	local label = Instance.new("TextLabel")
	label.Name = MESSAGE_LABEL_NAME
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.new(1, -48, 0, 64)
	label.Text = DEFAULT_TRANSITION_TEXT
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextSize = 42
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.45
	label.TextWrapped = true
	label.ZIndex = 2
	label.Parent = root

	return screenGui
end

local function normalizeTransitionText(payload: any): string
	if typeof(payload) == "table" and typeof(payload.text) == "string" and payload.text ~= "" then
		return payload.text
	end

	return DEFAULT_TRANSITION_TEXT
end

local function shouldHandleTeleportFailure(firstArg: any): boolean
	if typeof(firstArg) == "Instance" and firstArg:IsA("Player") then
		return firstArg == LOCAL_PLAYER
	end

	return true
end

function TeleportTransitionController:_getPlayerGui(): PlayerGui
	if self._playerGui and self._playerGui.Parent == LOCAL_PLAYER then
		return self._playerGui
	end

	self._playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	return self._playerGui
end

function TeleportTransitionController:_cancelTweens()
	for _, tween in ipairs(self._activeTweens) do
		pcall(function()
			tween:Cancel()
		end)
	end

	self._activeTweens = {}
end

function TeleportTransitionController:_setTargetsHidden(isHidden: boolean)
	for _, target in ipairs(self._fadeTargets) do
		pcall(function()
			(target.instance :: any)[target.property] = if isHidden then 1 else target.visibleValue
		end)
	end
end

function TeleportTransitionController:_playTargets(isHidden: boolean, duration: number)
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	for _, target in ipairs(self._fadeTargets) do
		local ok, tween = pcall(function()
			return TweenService:Create(target.instance, tweenInfo, {
				[target.property] = if isHidden then 1 else target.visibleValue,
			})
		end)

		if ok and tween then
			table.insert(self._activeTweens, tween)
			tween:Play()
		end
	end
end

function TeleportTransitionController:_applyScreenGuiSettings(screenGui: ScreenGui)
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = TELEPORT_GUI_DISPLAY_ORDER
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
	screenGui.Enabled = true
end

function TeleportTransitionController:_installTeleportGui()
	local playerGui = self:_getPlayerGui()
	if self._screenGui and self._screenGui.Parent == playerGui then
		pcall(function()
			TeleportService:SetTeleportGui(self._screenGui)
		end)
		return
	end

	local template = ReplicatedFirst:FindFirstChild(TELEPORT_GUI_NAME)
	local screenGui
	if template and template:IsA("ScreenGui") then
		screenGui = template:Clone()
	else
		Logger.Warn("[TeleportTransitionController] ReplicatedFirst.TeleportTransitionGui is missing; using runtime fallback.")
		screenGui = createFallbackGui()
	end

	self:_applyScreenGuiSettings(screenGui)
	screenGui.Name = TELEPORT_GUI_NAME
	screenGui.Parent = playerGui

	self._screenGui = screenGui
	self._root = findRoot(screenGui)
	self._messageLabel = findMessageLabel(screenGui)
	self._fadeTargets = collectFadeTargets(screenGui)
	self:_hide(true)

	local ok, err = pcall(function()
		TeleportService:SetTeleportGui(screenGui)
	end)
	if not ok then
		Logger.Warn(string.format("[TeleportTransitionController] Failed to set custom teleport GUI: %s", tostring(err)))
	end
end

function TeleportTransitionController:_hide(instant: boolean?)
	self._transitionToken += 1
	local token = self._transitionToken
	self:_cancelTweens()

	local root = self._root
	if instant then
		self:_setTargetsHidden(true)
		if root then
			root.Visible = false
			root.Active = false
		end
		return
	end

	self:_playTargets(true, FADE_OUT_SECONDS)
	task.delay(FADE_OUT_SECONDS, function()
		if token ~= self._transitionToken then
			return
		end

		self:_setTargetsHidden(true)
		if root then
			root.Visible = false
			root.Active = false
		end
	end)
end

function TeleportTransitionController:_show(message: string)
	self:_installTeleportGui()

	self._transitionToken += 1
	self:_cancelTweens()

	if self._messageLabel then
		self._messageLabel.Text = message
	end

	if self._root then
		self._root.Visible = true
		self._root.Active = true
	end

	if self._screenGui then
		self._screenGui.Enabled = true
		pcall(function()
			TeleportService:SetTeleportGui(self._screenGui)
		end)
	end

	self:_setTargetsHidden(true)
	self:_playTargets(false, FADE_IN_SECONDS)
end

function TeleportTransitionController:_connectPrepareRemote()
	task.spawn(function()
		local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, REMOTE_WAIT_TIMEOUT_SECONDS)
		if not (remotesFolder and remotesFolder:IsA("Folder")) then
			Logger.Warn("[TeleportTransitionController] ReplicatedStorage.Remotes is missing.")
			return
		end

		local transitionFolder = remotesFolder:WaitForChild(TELEPORT_TRANSITION_FOLDER_NAME, REMOTE_WAIT_TIMEOUT_SECONDS)
		if not (transitionFolder and transitionFolder:IsA("Folder")) then
			Logger.Warn("[TeleportTransitionController] ReplicatedStorage.Remotes.TeleportTransition is missing.")
			return
		end

		local prepare = transitionFolder:WaitForChild(PREPARE_REMOTE_NAME, REMOTE_WAIT_TIMEOUT_SECONDS)
		if not (prepare and prepare:IsA("RemoteEvent")) then
			Logger.Warn("[TeleportTransitionController] ReplicatedStorage.Remotes.TeleportTransition.Prepare is missing.")
			return
		end

		if self._prepareConnection then
			self._prepareConnection:Disconnect()
		end

		self._prepareConnection = prepare.OnClientEvent:Connect(function(payload)
			if typeof(payload) == "table" and payload.hide == true then
				self:_hide(false)
				return
			end

			self:_show(normalizeTransitionText(payload))
		end)
	end)
end

function TeleportTransitionController:_connectTeleportFailure()
	if self._failureConnection then
		self._failureConnection:Disconnect()
	end

	self._failureConnection = TeleportService.TeleportInitFailed:Connect(function(firstArg)
		if shouldHandleTeleportFailure(firstArg) then
			self:_hide(false)
		end
	end)
end

function TeleportTransitionController:OnStart()
	if self._started then
		return
	end

	self._started = true
	self:_installTeleportGui()
	self:_connectPrepareRemote()
	self:_connectTeleportFailure()
end

return TeleportTransitionController
