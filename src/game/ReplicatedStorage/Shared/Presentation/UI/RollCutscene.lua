local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GameAssetPaths = require(ReplicatedStorage.Shared.Assets.GameAssetPaths)
local GameAssetResolver = require(ReplicatedStorage.Shared.Assets.GameAssetResolver)

local RollCutscene = {}

local GAME_ASSETS_FOLDER_NAME = "GameAssets"
local UI_FOLDER_NAME = "UI"
local CUTSCENE_FOLDER_NAME = "RollCutscene"
local TEMPLATE_NAME = "LoadingScreen"
local RUNTIME_GUI_NAME = "_RollCutsceneRuntime"
local TEMPLATE_PATH = string.format(
	"ReplicatedStorage.%s.%s.%s.%s",
	GAME_ASSETS_FOLDER_NAME,
	UI_FOLDER_NAME,
	CUTSCENE_FOLDER_NAME,
	TEMPLATE_NAME
)
local hasWarnedMissingTemplate = false

local function darken(color: Color3, amount: number): Color3
	return Color3.new(
		color.R * (1 - amount),
		color.G * (1 - amount),
		color.B * (1 - amount)
	)
end

local function getTemplate(): ScreenGui?
	local cutsceneFolder = GameAssetResolver.Find(GameAssetPaths.UI.RollCutscene)
		or GameAssetResolver.Find({ UI_FOLDER_NAME, CUTSCENE_FOLDER_NAME })
	if not (cutsceneFolder and cutsceneFolder:IsA("Folder")) then
		if not hasWarnedMissingTemplate then
			hasWarnedMissingTemplate = true
			Logger.Warn(string.format("[RollCutscene] Missing template at %s.", TEMPLATE_PATH))
		end
		return nil
	end

	local template = cutsceneFolder:FindFirstChild(TEMPLATE_NAME)
	if template and template:IsA("ScreenGui") then
		hasWarnedMissingTemplate = false
		return template
	end

	if not hasWarnedMissingTemplate then
		hasWarnedMissingTemplate = true
		Logger.Warn(string.format("[RollCutscene] Missing template at %s.", TEMPLATE_PATH))
	end

	return nil
end

local function cleanupExistingRuntime(playerGui: PlayerGui)
	local existing = playerGui:FindFirstChild(RUNTIME_GUI_NAME)
	if existing then
		existing:Destroy()
	end
end

function RollCutscene.Play(color: Color3, tier: number, length: number?, beforeReveal: (() -> ())?): boolean
	local player = Players.LocalPlayer
	if not player then
		return false
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return false
	end

	local template = getTemplate()
	if not template then
		return false
	end

	cleanupExistingRuntime(playerGui)

	local runtimeGui = template:Clone()
	runtimeGui.Name = RUNTIME_GUI_NAME
	runtimeGui.ResetOnSpawn = false
	runtimeGui.Enabled = true
	runtimeGui.Parent = playerGui

	local box = runtimeGui:FindFirstChild("Loader")
	local background = runtimeGui:FindFirstChild("Background")
	local transitionCover = runtimeGui:FindFirstChild("TransitionCover")
	local cover = runtimeGui:FindFirstChild("Cover")
	if not (box and box:IsA("Frame")) then
		runtimeGui:Destroy()
		return false
	end
	if not (background and background:IsA("ImageLabel")) then
		runtimeGui:Destroy()
		return false
	end
	if not (transitionCover and transitionCover:IsA("Frame")) then
		runtimeGui:Destroy()
		return false
	end
	if not (cover and cover:IsA("GuiObject")) then
		runtimeGui:Destroy()
		return false
	end

	local holder = box:FindFirstChild("Frame")
	if not (holder and holder:IsA("Frame")) then
		runtimeGui:Destroy()
		return false
	end

	local iconOrder = { "One", "Two", "Three", "Four", "Five", "Six", "Seven" }
	local icons = table.create(#iconOrder)
	local baseTransparencies = table.create(#iconOrder)

	for index, iconName in ipairs(iconOrder) do
		local icon = holder:FindFirstChild(iconName)
		if not (icon and icon:IsA("ImageLabel")) then
			runtimeGui:Destroy()
			return false
		end

		icons[index] = icon
		baseTransparencies[index] = icon.ImageTransparency
	end

	local resolvedLength = math.max(0.05, tonumber(length) or 1)
	local resolvedColor = if typeof(color) == "Color3" then color else Color3.new(1, 1, 1)
	local visibleCountByTier = { 1, 2, 3, 5, 7 }
	local clampedTier = math.clamp(math.floor(tonumber(tier) or 1), 1, #visibleCountByTier)
	local visibleCount = visibleCountByTier[clampedTier]
	local baseSize = holder.Size
	local flickerTime = resolvedLength * 0.25
	local startTime = os.clock()
	local firstIconPopped = false
	local finishedEvent = Instance.new("BindableEvent")
	local finishing = false
	local didRunBeforeReveal = false

	local function runBeforeReveal()
		if didRunBeforeReveal then
			return
		end

		didRunBeforeReveal = true
		if beforeReveal then
			local ok, err = pcall(beforeReveal)
			if not ok then
				Logger.Warn(string.format("[RollCutscene] beforeReveal callback failed: %s", tostring(err)))
			end
		end
	end

	background.ImageColor3 = Color3.new(0, 0, 0)
	background.Visible = true
	box.Visible = true
	cover.Visible = true
	transitionCover.BackgroundTransparency = 1
	transitionCover.BackgroundColor3 = resolvedColor
	transitionCover.Visible = true

	for index, icon in ipairs(icons) do
		icon.Visible = index <= visibleCount
		icon.ImageTransparency = 1
	end

	local connection: RBXScriptConnection?
	connection = RunService.Heartbeat:Connect(function(dt)
		if finishing then
			return
		end

		local elapsed = os.clock() - startTime
		local t = math.clamp(elapsed / resolvedLength, 0, 1)
		local targetColor = darken(resolvedColor, 0.6)
		background.ImageColor3 = background.ImageColor3:Lerp(targetColor, math.clamp(t * 0.08, 0, 1))

		local tierSlowdown = 1 - ((visibleCount - 1) / 6) * 0.5
		local growthT = t ^ 1.3
		local scale = 1 + (growthT * 1.5) * tierSlowdown
		holder.Size = UDim2.new(
			baseSize.X.Scale * scale,
			baseSize.X.Offset * scale,
			baseSize.Y.Scale * scale,
			baseSize.Y.Offset * scale
		)

		local speed = (t ^ 2) * 12

		for index = 1, visibleCount do
			local icon = icons[index]
			local appearStart
			local fadeDuration

			if index == 1 then
				appearStart = 0
				fadeDuration = 0.25
			else
				appearStart = 0.1 + (index - 2) * (0.25 / visibleCount)
				fadeDuration = 0.12
			end

			local appearEnd = appearStart + fadeDuration
			local alpha

			if t < appearStart then
				alpha = 1
			elseif t > appearEnd then
				alpha = 0
			else
				local progress = math.clamp((t - appearStart) / fadeDuration, 0, 1)
				progress = 1 - (1 - progress) ^ 3
				alpha = 1 - progress
			end

			if index == 1 and not firstIconPopped and alpha < 0.5 then
				firstIconPopped = true

				local originalSize = icon.Size
				icon.Size = UDim2.fromScale(icon.Size.X.Scale * 0.6, icon.Size.Y.Scale * 0.6)
				TweenService:Create(
					icon,
					TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Size = originalSize }
				):Play()
			end

			if elapsed < flickerTime then
				alpha += math.random() * 0.25
			end

			local targetTransparency = baseTransparencies[index]
			local finalTransparency = targetTransparency + (1 - targetTransparency) * alpha
			icon.ImageTransparency = math.clamp(finalTransparency, 0, 1)
			icon.ImageColor3 = icon.ImageColor3:Lerp(resolvedColor, 0.1)

			local factor = visibleCount - index + 1
			icon.Rotation += speed * (factor * 0.12) * dt * 60
		end

		if t > 0.8 then
			local fadeT = math.clamp((t - 0.8) / 0.2, 0, 1)
			transitionCover.BackgroundTransparency = 1 - fadeT

			if fadeT > 0.99 then
				box.Visible = false
				background.Visible = false
				cover.Visible = false
			end
		end

		if t >= 1 then
			finishing = true
			if connection then
				connection:Disconnect()
				connection = nil
			end

			task.spawn(function()
				runBeforeReveal()

				local tween = TweenService:Create(
					transitionCover,
					TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ BackgroundTransparency = 1 }
				)

				tween:Play()
				tween.Completed:Wait()

				if runtimeGui.Parent then
					runtimeGui:Destroy()
				end

				finishedEvent:Fire()
			end)
		end
	end)

	local ok = pcall(function()
		finishedEvent.Event:Wait()
	end)

	if connection then
		connection:Disconnect()
	end

	finishedEvent:Destroy()

	if runtimeGui.Parent then
		runtimeGui:Destroy()
	end

	return ok
end

return RollCutscene
