local TweenService = game:GetService("TweenService")

local TutorialTextGui = {}

local gui: ScreenGui? = nil
local frame: Frame? = nil
local label: TextLabel? = nil
local labelStroke: UIStroke? = nil
local DEFAULT_DISPLAY_ORDER = 1000
local DEFAULT_TEMPORARY_DURATION_SECONDS = 3
local FADE_DURATION_SECONDS = 0.2
local textToken = 0

TutorialTextGui.DefaultTemporaryDurationSeconds = DEFAULT_TEMPORARY_DURATION_SECONDS

local function nextTextToken(): number
	textToken += 1
	return textToken
end

local function showLabelText(text: string)
	if not label then
		return
	end

	label.Text = text

	if label.TextTransparency > 0 then
		TweenService:Create(label, TweenInfo.new(FADE_DURATION_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 0,
		}):Play()
	else
		label.TextTransparency = 0
	end

	if labelStroke then
		if labelStroke.Transparency > 0.2 then
			TweenService:Create(labelStroke, TweenInfo.new(FADE_DURATION_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 0.2,
			}):Play()
		else
			labelStroke.Transparency = 0.2
		end
	end
end

local function hideLabelText()
	if not label then
		return
	end

	TweenService:Create(label, TweenInfo.new(FADE_DURATION_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 1,
	}):Play()

	if labelStroke then
		TweenService:Create(labelStroke, TweenInfo.new(FADE_DURATION_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
		}):Play()
	end
end

function TutorialTextGui.Init(playerGui: PlayerGui)
	if gui then
		return
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "TutorialGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = DEFAULT_DISPLAY_ORDER
	gui:SetAttribute("KeepEnabledDuringHatch", true)
	gui.Parent = playerGui

	frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(0.7, 0.1)
	frame.Position = UDim2.fromScale(0.15, 0.08)
	frame.BackgroundTransparency = 1
	frame.ZIndex = 100
	frame.Parent = gui

	label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Text = ""
	label.TextTransparency = 1
	label.ZIndex = 101
	label.Parent = frame

	labelStroke = Instance.new("UIStroke")
	labelStroke.Name = "NOSCALE"
	labelStroke.Color = Color3.new(0, 0, 0)
	labelStroke.Thickness = 1.5
	labelStroke.Transparency = 1
	labelStroke.Parent = label
end

function TutorialTextGui.LayerAboveDisplayOrder(displayOrder: number?)
	if not gui then
		return
	end

	gui.DisplayOrder = math.max(DEFAULT_DISPLAY_ORDER, math.floor(tonumber(displayOrder) or DEFAULT_DISPLAY_ORDER) + 1)
end

function TutorialTextGui.SetText(text: string)
	nextTextToken()
	showLabelText(text)
end

function TutorialTextGui.HideText()
	nextTextToken()
	hideLabelText()
end

function TutorialTextGui.ShowTemporaryText(text: string, durationSeconds: number?): number
	if not label then
		return 0
	end

	local resolvedText = if typeof(text) == "string" then text else ""
	if resolvedText == "" then
		return 0
	end

	local duration = math.max(0, tonumber(durationSeconds) or DEFAULT_TEMPORARY_DURATION_SECONDS)
	local token = nextTextToken()
	showLabelText(resolvedText)

	task.delay(duration, function()
		if textToken == token then
			hideLabelText()
		end
	end)

	return duration
end

function TutorialTextGui.ShowTemporaryTextAsync(text: string, durationSeconds: number?): boolean
	local duration = TutorialTextGui.ShowTemporaryText(text, durationSeconds)
	if duration <= 0 then
		return false
	end

	task.wait(duration + FADE_DURATION_SECONDS)
	return true
end

return TutorialTextGui
