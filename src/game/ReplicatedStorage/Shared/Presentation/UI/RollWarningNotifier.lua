local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NotificationPresenter = require(ReplicatedStorage.Shared.UI.NotificationPresenter)

local SCREEN_GUI_NAME = "MainInterface"
local CONTAINER_NAME = "RollWarning"
local TEMPLATE_NAME = "TextLabel"
local FADE_IN_TIME = 0.18
local HOLD_TIME = 1.0
local FADE_OUT_TIME = 0.25

local RollWarningNotifier = {}

local function getWarningUi(): (Frame?, GuiObject?)
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return nil, nil
	end

	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil, nil
	end

	local screenGui = playerGui:FindFirstChild(SCREEN_GUI_NAME) or playerGui:WaitForChild(SCREEN_GUI_NAME, 5)
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

function RollWarningNotifier.ShowInsufficientFundsWarning(message: string?): boolean
	local container, template = getWarningUi()
	if not (container and template) then
		return false
	end

	return NotificationPresenter.Show(container, template, {
		message = if typeof(message) == "string" and message ~= "" then message else "You do not have enough money.",
		fadeInTime = FADE_IN_TIME,
		holdTime = HOLD_TIME,
		fadeOutTime = FADE_OUT_TIME,
		warnPrefix = "[RollWarning]",
	})
end

return RollWarningNotifier
