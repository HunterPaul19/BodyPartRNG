local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)
local NotificationPresenter = require(ReplicatedStorage.Shared.UI.NotificationPresenter)

local REMOTES_FOLDER_NAME = "Remotes"
local REMOTE_NAME = "Notify"
local SCREEN_GUI_NAME = "Main"
local CONTAINER_NAME = "Notifs"
local TEMPLATE_NAME = "NotificationTemplate"
local DEFAULT_CHANNEL = "system"
local QUEUE_TIMEOUT_SECONDS = 10
local QUEUE_RETRY_INTERVAL = 0.25

local CHANNEL_COLORS = {
	inventory = Color3.fromRGB(96, 165, 250),
	potions = Color3.fromRGB(74, 222, 128),
	marketplace = Color3.fromRGB(251, 191, 36),
	titles = Color3.fromRGB(129, 140, 248),
	auras = Color3.fromRGB(103, 232, 249),
	admin = Color3.fromRGB(100, 116, 139),
	system = Color3.fromRGB(148, 163, 184),
}

type NotificationTone = "neutral" | "good"

local DEFAULT_TONE: NotificationTone = "neutral"

local TONE_SOUNDS: { [NotificationTone]: string } = {
	neutral = "NeutralNotificationSound",
	good = "GoodNotificationSound",
}

type NotificationPayload = {
	title: string,
	text: string,
	duration: number,
	channel: string,
	tone: NotificationTone,
	textColor3: Color3?,
}

type QueuedNotification = {
	payload: NotificationPayload,
	expiresAt: number,
}

local Notify = {}
local clientRemoteConnection: RBXScriptConnection? = nil
local pendingNotifications: { QueuedNotification } = {}
local queueWorkerActive = false
local activeHolds: { [string]: boolean } = {}
local activeHoldCount = 0
local activeHoldStartedAt: number? = nil
Notify.Defaults = {
	title = "Notice",
	duration = 4,
	channel = DEFAULT_CHANNEL,
	tone = DEFAULT_TONE,
}

local function ensureServerRemote(): RemoteEvent
	local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if remotesFolder and not remotesFolder:IsA("Folder") then
		remotesFolder:Destroy()
		remotesFolder = nil
	end
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = REMOTES_FOLDER_NAME
		remotesFolder.Parent = ReplicatedStorage
	end

	local remote = remotesFolder:FindFirstChild(REMOTE_NAME)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	if remote then
		remote:Destroy()
	end

	remote = Instance.new("RemoteEvent")
	remote.Name = REMOTE_NAME
	remote.Parent = remotesFolder
	return remote
end

local function findClientRemote(): RemoteEvent?
	local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if not (remotesFolder and remotesFolder:IsA("Folder")) then
		return nil
	end

	local remote = remotesFolder:FindFirstChild(REMOTE_NAME)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end

	return nil
end

local function ensureRemote(): RemoteEvent?
	if RunService:IsServer() then
		return ensureServerRemote()
	end

	return findClientRemote()
end

local function resolveChannel(opts): string
	if typeof(opts) == "table" then
		local channel = opts.channel
		if typeof(channel) == "string" then
			channel = string.lower(channel)
			if CHANNEL_COLORS[channel] ~= nil then
				return channel
			end
		end

		local colorName = opts.color
		if typeof(colorName) == "string" and string.lower(colorName) == "green" then
			return "marketplace"
		end
	end

	return DEFAULT_CHANNEL
end

local function resolveTone(opts): NotificationTone
	if typeof(opts) == "table" then
		local tone = opts.tone
		if typeof(tone) == "string" then
			tone = string.lower(tone)
			if TONE_SOUNDS[tone] ~= nil then
				return tone :: NotificationTone
			end
		end
	end

	return DEFAULT_TONE
end

local function resolveTextColor(opts): Color3?
	if typeof(opts) == "table" and typeof(opts.textColor3) == "Color3" then
		return opts.textColor3
	end

	return nil
end

local function normalizePayload(text: any, opts): NotificationPayload
	opts = opts or {}

	local duration = tonumber(opts.duration)
	if duration == nil or duration ~= duration or duration <= 0 then
		duration = Notify.Defaults.duration
	end

	return {
		title = tostring(opts.title or Notify.Defaults.title),
		text = tostring(text),
		duration = duration,
		channel = resolveChannel(opts),
		tone = resolveTone(opts),
		textColor3 = resolveTextColor(opts),
	}
end

local function getNotificationUi(): (Frame?, GuiObject?)
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return nil, nil
	end

	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil, nil
	end

	local screenGui = playerGui:FindFirstChild(SCREEN_GUI_NAME)
	if not (screenGui and screenGui:IsA("ScreenGui")) then
		return nil, nil
	end

	local container = screenGui:FindFirstChild(CONTAINER_NAME)
	if not (container and container:IsA("Frame")) then
		return nil, nil
	end

	local template = container:FindFirstChild(TEMPLATE_NAME)
	if not (template and template:IsA("GuiObject")) then
		return nil, nil
	end

	return container, template
end

local function brightenColor(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), math.clamp(amount, 0, 1))
end

local function applyChannelStyling(toast: GuiObject, payload: NotificationPayload)
	local channelColor = CHANNEL_COLORS[payload.channel] or CHANNEL_COLORS[DEFAULT_CHANNEL]
	if toast:IsA("GuiObject") then
		toast.BackgroundColor3 = channelColor
	end

	local frameGradient = toast:FindFirstChildOfClass("UIGradient")
	if frameGradient then
		frameGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, brightenColor(channelColor, 0.3)),
			ColorSequenceKeypoint.new(1, channelColor:Lerp(Color3.new(0, 0, 0), 0.08)),
		})
	end

	local frameStroke = toast:FindFirstChildOfClass("UIStroke")
	if frameStroke then
		frameStroke.Color = brightenColor(channelColor, 0.18)
	end
end

local function applyMessageLabelStyling(messageLabel: TextLabel | TextButton | TextBox, payload: NotificationPayload)
	local channelColor = CHANNEL_COLORS[payload.channel] or CHANNEL_COLORS[DEFAULT_CHANNEL]
	local textColor = payload.textColor3 or brightenColor(channelColor, 0.32)
	messageLabel.TextColor3 = textColor

	local textStroke = messageLabel:FindFirstChildOfClass("UIStroke")
	if textStroke then
		textStroke.Color = Color3.fromRGB(20, 20, 20)

		local strokeGradient = textStroke:FindFirstChildOfClass("UIGradient")
		if strokeGradient then
			strokeGradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, brightenColor(textColor, 0.18)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(105, 105, 105)),
			})
		end
	end
end

local function renderToast(container: Frame, template: GuiObject, payload: NotificationPayload)
	return NotificationPresenter.Show(container, template, {
		message = payload.text,
		messageLabelName = "TextLabel",
		holdTime = payload.duration,
		warnPrefix = "[Notify]",
		onCreated = function(toast, messageLabel)
			applyChannelStyling(toast, payload)
			if messageLabel then
				applyMessageLabelStyling(messageLabel, payload)
			end
		end,
	})
end

local function playNotificationTone(tone: NotificationTone)
	local soundName = TONE_SOUNDS[tone]
	if soundName == nil then
		return
	end

	SoundUtil.Play(soundName)
end

local function warnDroppedNotification(payload: NotificationPayload)
	Logger.Warn(string.format("[Notify] Dropped notification after waiting for %s UI: %s", SCREEN_GUI_NAME, payload.text))
end

local function normalizeHoldKey(key: any): string
	if typeof(key) == "string" and key ~= "" then
		return key
	end

	return "default"
end

local function isQueueHeld(): boolean
	return RunService:IsClient() and activeHoldCount > 0
end

local function extendQueuedNotificationExpirations(heldSeconds: number)
	if heldSeconds <= 0 then
		return
	end

	for _, entry in ipairs(pendingNotifications) do
		entry.expiresAt += heldSeconds
	end
end

local function processQueue()
	if queueWorkerActive then
		return
	end

	queueWorkerActive = true

	task.spawn(function()
		while true do
			if #pendingNotifications == 0 then
				queueWorkerActive = false
				if #pendingNotifications == 0 then
					return
				end
				queueWorkerActive = true
			end

			if isQueueHeld() then
				task.wait(QUEUE_RETRY_INTERVAL)
				continue
			end

			local container, template = getNotificationUi()
			local now = os.clock()

			if not (container and template) then
				local index = 1
				while index <= #pendingNotifications do
					local entry = pendingNotifications[index]
					if entry.expiresAt <= now then
						warnDroppedNotification(entry.payload)
						table.remove(pendingNotifications, index)
					else
						index += 1
					end
				end

				if #pendingNotifications > 0 then
					task.wait(QUEUE_RETRY_INTERVAL)
				end
			else
				local readyNotifications = pendingNotifications
				pendingNotifications = {}

				for _, entry in ipairs(readyNotifications) do
					if entry.expiresAt <= now then
						warnDroppedNotification(entry.payload)
					else
						local didRender = renderToast(container, template, entry.payload)
						if didRender then
							playNotificationTone(entry.payload.tone)
						end
					end
				end
			end
		end
	end)
end

function Notify.BeginHold(key)
	if not RunService:IsClient() then
		return false
	end

	local holdKey = normalizeHoldKey(key)
	if activeHolds[holdKey] == true then
		return true
	end

	activeHolds[holdKey] = true
	activeHoldCount += 1
	if activeHoldCount == 1 then
		activeHoldStartedAt = os.clock()
	end

	return true
end

function Notify.EndHold(key)
	if not RunService:IsClient() then
		return false
	end

	local holdKey = normalizeHoldKey(key)
	if activeHolds[holdKey] ~= true then
		return false
	end

	activeHolds[holdKey] = nil
	activeHoldCount = math.max(0, activeHoldCount - 1)
	if activeHoldCount == 0 then
		local heldSeconds = os.clock() - (activeHoldStartedAt or os.clock())
		activeHoldStartedAt = nil
		extendQueuedNotificationExpirations(heldSeconds)
		processQueue()
	end

	return true
end

function Notify.Show(text, opts)
	local payload = normalizePayload(text, opts)
	table.insert(pendingNotifications, {
		payload = payload,
		expiresAt = os.clock() + QUEUE_TIMEOUT_SECONDS,
	})
	processQueue()
	return true
end

function Notify.Send(target, text, opts)
	if RunService:IsServer() then
		local payload = normalizePayload(text, opts)
		local remote = ensureRemote()

		if target == nil or target == "all" then
			remote:FireAllClients(payload)
		elseif typeof(target) == "Instance" and target:IsA("Player") then
			remote:FireClient(target, payload)
		elseif typeof(target) == "table" then
			for _, player in ipairs(target) do
				if typeof(player) == "Instance" and player:IsA("Player") then
					remote:FireClient(player, payload)
				end
			end
		end
	else
		return Notify.Show(text, opts)
	end
end

if RunService:IsClient() then
	task.spawn(function()
		while clientRemoteConnection == nil do
			local remote = ensureRemote()
			if remote then
				clientRemoteConnection = remote.OnClientEvent:Connect(function(payload)
					Notify.Show(payload.text, payload)
				end)
				return
			end

			task.wait(QUEUE_RETRY_INTERVAL)
		end
	end)
end

return Notify
