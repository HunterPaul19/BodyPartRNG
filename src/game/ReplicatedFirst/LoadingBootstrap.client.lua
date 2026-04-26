local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared", 10)
local placeProfilesFolder = if sharedFolder then sharedFolder:WaitForChild("PlaceProfiles", 10) else nil
local placeProfileModule = if placeProfilesFolder then placeProfilesFolder:WaitForChild("PlaceProfile", 10) else nil

if not (placeProfileModule and placeProfileModule:IsA("ModuleScript")) then
	Logger.Error(
		"[LoadingBootstrap] ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile is missing or did not replicate in time.",
		0
	)
end

local PlaceProfile = require(placeProfileModule)

local MIN_DISPLAY_SECONDS = 1.5
local GUI_ROOT_TIMEOUT = 10
local PRELOAD_ROOT_TIMEOUT = 5
local FADE_DURATION = 0.35
local OPTIONAL_PRELOAD_TIMEOUT = 5

local player = Players.LocalPlayer
if not player then
	return
end

local playerGui = player:WaitForChild("PlayerGui")
local activeProfile = PlaceProfile.GetActiveProfile()
local activePlaceId = math.max(0, math.floor(tonumber(game.PlaceId) or 0))

local function formatContextPrefix(): string
	return string.format(
		"[LoadingBootstrap][Profile:%s][PlaceId:%d]",
		activeProfile.id,
		activePlaceId
	)
end

pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

local loadingScreen = ReplicatedFirst:WaitForChild("LoadingScreen", 5)
if not (loadingScreen and loadingScreen:IsA("ScreenGui")) then
	Logger.Warn("[LoadingBootstrap] ReplicatedFirst.LoadingScreen is missing or invalid.")
	return
end

loadingScreen.IgnoreGuiInset = true
loadingScreen.ResetOnSpawn = false
loadingScreen.Enabled = true
loadingScreen.Parent = playerGui

local loadingBar = loadingScreen:FindFirstChild("LoadingBar")
local loadingBarFrame = if loadingBar then loadingBar:FindFirstChild("Frame") else nil
local loadingBarFill = if loadingBarFrame then loadingBarFrame:FindFirstChild("Fill") else nil
local assetsLoadedLabel = if loadingBar then loadingBar:FindFirstChild("AssetsLoaded") else nil
local loaderFrame = loadingScreen:FindFirstChild("Loader")
local loaderFill = if loaderFrame then loaderFrame:FindFirstChild("Fill") else nil
local skipButton = loadingScreen:FindFirstChild("SkipButton")
local transitionCover = loadingScreen:FindFirstChild("TransitionCover")

local baseLoaderFillSize = if loaderFill and loaderFill:IsA("GuiObject") then loaderFill.Size else nil
local shownAt = os.clock()
local canSkip = false
local skipRequested = false
local totalAssets = 0
local loadedAssets = 0
local preloadCompleted = false
local preloadFailureMessage = nil
local isDismissing = false
local skipConnection: RBXScriptConnection? = nil

local PRELOADABLE_CLASSES = {
	ImageLabel = true,
	ImageButton = true,
	Decal = true,
	Texture = true,
	MeshPart = true,
	Sound = true,
	Animation = true,
	VideoFrame = true,
	Shirt = true,
	Pants = true,
	Sky = true,
	SurfaceAppearance = true,
	ParticleEmitter = true,
	Beam = true,
	Trail = true,
}

local function updateProgress()
	if isDismissing then
		return
	end

	if assetsLoadedLabel and assetsLoadedLabel:IsA("TextLabel") then
		if totalAssets > 0 then
			assetsLoadedLabel.Text = string.format("%d/%d Assets Loaded", loadedAssets, totalAssets)
		else
			assetsLoadedLabel.Text = "Loading..."
		end
	end

	local progress = 0
	if totalAssets > 0 then
		progress = math.clamp(loadedAssets / totalAssets, 0, 1)
	end

	if loadingBarFill and loadingBarFill:IsA("Frame") then
		loadingBarFill.Size = UDim2.fromScale(progress, 1)
	end

	if baseLoaderFillSize and loaderFill and loaderFill:IsA("GuiObject") then
		local scale = 0.2 + 0.8 * progress
		loaderFill.Size = UDim2.new(
			baseLoaderFillSize.X.Scale * scale,
			baseLoaderFillSize.X.Offset,
			baseLoaderFillSize.Y.Scale * scale,
			baseLoaderFillSize.Y.Offset
		)
	end
end

local function isPreloadCandidate(instance: Instance): boolean
	return PRELOADABLE_CLASSES[instance.ClassName] == true
end

local function collectPreloadInstances(root: Instance): { Instance }
	local instances = {}
	local seen = {}

	local function add(instance: Instance)
		if seen[instance] then
			return
		end

		seen[instance] = true
		table.insert(instances, instance)
	end

	if isPreloadCandidate(root) then
		add(root)
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if isPreloadCandidate(descendant) then
			add(descendant)
		end
	end

	return instances
end

local function formatPreloadRootNames(rootSpecs): string
	local rootNames = {}
	for _, rootSpec in ipairs(rootSpecs) do
		if typeof(rootSpec) == "table" and typeof(rootSpec.name) == "string" then
			table.insert(rootNames, rootSpec.name)
		end
	end

	return table.concat(rootNames, ", ")
end

local function resolveGuiRoot(playerGuiRoot: PlayerGui, rootName: string, timeout: number): GuiBase2d?
	local root = playerGuiRoot:FindFirstChild(rootName)
	if root == nil and timeout > 0 then
		root = playerGuiRoot:WaitForChild(rootName, timeout)
	end

	if root and root:IsA("GuiBase2d") then
		return root
	end

	return nil
end

local function collectProfileGuiInstances(
	rootName: string,
	container: Instance,
	rootSpecs,
	allowMissingRoots: boolean
): { Instance }
	local instances = {}

	for _, rootSpec in ipairs(rootSpecs) do
		local childName = if typeof(rootSpec) == "table" then rootSpec.name else nil
		local isRequired = typeof(rootSpec) == "table" and rootSpec.required == true
		if typeof(childName) ~= "string" or childName == "" then
			continue
		end

		local child = container:FindFirstChild(childName)
		if child == nil then
			child = container:WaitForChild(childName, PRELOAD_ROOT_TIMEOUT)
		end

		if child == nil then
			if isRequired then
				Logger.Error(
					string.format(
						"%s Required PlayerGui.%s.%s did not appear within %d seconds.",
						formatContextPrefix(),
						rootName,
						childName,
						PRELOAD_ROOT_TIMEOUT
					),
					0
				)
			end

			if allowMissingRoots then
				Logger.Warn(string.format(
					"%s Optional PlayerGui.%s.%s was not found; skipping preload for that root.",
					formatContextPrefix(),
					rootName,
					childName
				))
			end
		else
			for _, instance in ipairs(collectPreloadInstances(child)) do
				table.insert(instances, instance)
			end
		end
	end

	return instances
end

local function resolveGameAssetInstance(relativePath: string): Instance?
	if typeof(relativePath) ~= "string" or relativePath == "" then
		return nil
	end

	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	if not (gameAssets and gameAssets:IsA("Folder")) then
		return nil
	end

	local current: Instance? = gameAssets
	for segment in string.gmatch(relativePath, "[^/]+") do
		if current == nil then
			return nil
		end

		current = current:FindFirstChild(segment)
		if current == nil then
			return nil
		end
	end

	return current
end

local function collectProfileGameAssetInstances(relativePaths): { Instance }
	local instances = {}

	for _, relativePath in ipairs(relativePaths) do
		local resolved = resolveGameAssetInstance(relativePath)
		if resolved == nil then
			Logger.Warn(string.format(
				"%s Optional ReplicatedStorage.GameAssets.%s was not found; skipping preload for that asset path.",
				formatContextPrefix(),
				string.gsub(relativePath, "/", ".")
			))
		else
			for _, instance in ipairs(collectPreloadInstances(resolved)) do
				table.insert(instances, instance)
			end
		end
	end

	return instances
end

local function preloadInstances(instances: { Instance }, allowSkip: boolean)
	if #instances == 0 then
		return
	end

	totalAssets += #instances
	updateProgress()

	for _, instance in ipairs(instances) do
		if isDismissing then
			break
		end

		if allowSkip and skipRequested and canSkip then
			break
		end

		local ok, err = pcall(function()
			ContentProvider:PreloadAsync({ instance })
		end)

		if not ok then
			Logger.Warn(string.format("[LoadingBootstrap] Failed to preload %s: %s", instance:GetFullName(), tostring(err)))
		end

		loadedAssets += 1
		updateProgress()
	end
end

local function waitForMinimumDisplay()
	local elapsed = os.clock() - shownAt
	local remaining = MIN_DISPLAY_SECONDS - elapsed
	if remaining > 0 then
		task.wait(remaining)
	end
end

local function waitForGameLoaded()
	if game:IsLoaded() then
		return
	end

	game.Loaded:Wait()
end

local function tweenTransparency(instance: Instance, transparency: number): Tween?
	if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
		return TweenService:Create(instance, TweenInfo.new(FADE_DURATION), {
			BackgroundTransparency = 1,
			ImageTransparency = transparency,
		})
	end

	if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
		return TweenService:Create(instance, TweenInfo.new(FADE_DURATION), {
			BackgroundTransparency = 1,
			TextTransparency = transparency,
			TextStrokeTransparency = transparency,
		})
	end

	if instance:IsA("Frame") or instance:IsA("ScrollingFrame") or instance:IsA("ViewportFrame") then
		return TweenService:Create(instance, TweenInfo.new(FADE_DURATION), {
			BackgroundTransparency = 1,
		})
	end

	if instance:IsA("UIStroke") then
		return TweenService:Create(instance, TweenInfo.new(FADE_DURATION), {
			Transparency = transparency,
		})
	end

	return nil
end

local function fadeOutAndDestroy()
	isDismissing = true

	local tweens = {}

	if transitionCover and transitionCover:IsA("Frame") then
		transitionCover.BackgroundColor3 = Color3.new(0, 0, 0)
		transitionCover.BackgroundTransparency = 1
		transitionCover.Visible = true
		table.insert(tweens, TweenService:Create(transitionCover, TweenInfo.new(FADE_DURATION), {
			BackgroundTransparency = 0,
		}))
	end

	for _, descendant in ipairs(loadingScreen:GetDescendants()) do
		if descendant == transitionCover then
			continue
		end

		local tween = tweenTransparency(descendant, 1)
		if tween then
			table.insert(tweens, tween)
		end
	end

	for _, tween in ipairs(tweens) do
		tween:Play()
	end

	task.wait(FADE_DURATION)
	loadingScreen:Destroy()
end

updateProgress()

if skipButton and skipButton:IsA("GuiButton") then
	skipButton.Visible = false
	skipConnection = skipButton.Activated:Connect(function()
		if not canSkip then
			return
		end

		skipRequested = true
	end)
end

task.delay(MIN_DISPLAY_SECONDS, function()
	canSkip = true
	if skipButton and skipButton:IsA("GuiButton") then
		skipButton.Visible = true
	end
end)

preloadInstances(collectPreloadInstances(loadingScreen), false)
waitForGameLoaded()

local preloadSpec = PlaceProfile.GetPreloadSpec()
Logger.Print(string.format(
	"%s PreloadSpec MainInterface=[%s] ModalRoot=[%s] GameAssets=[%s]",
	formatContextPrefix(),
	formatPreloadRootNames(preloadSpec.mainInterfaceRoots),
	formatPreloadRootNames(preloadSpec.modalRootRoots),
	table.concat(preloadSpec.gameAssetPaths, ", ")
))

task.spawn(function()
	local ok, err = pcall(function()
		local instancesToPreload = {}

		if #preloadSpec.mainInterfaceRoots > 0 then
			local mainInterface = resolveGuiRoot(playerGui, "MainInterface", GUI_ROOT_TIMEOUT)
			if not (mainInterface and mainInterface:IsA("ScreenGui")) then
				Logger.Error(
					string.format(
						"%s Required PlayerGui.MainInterface did not appear within %d seconds. This place should include the shared MainInterface content.",
						formatContextPrefix(),
						GUI_ROOT_TIMEOUT
					),
					0
				)
			end

			for _, instance in ipairs(collectProfileGuiInstances(
				"MainInterface",
				mainInterface,
				preloadSpec.mainInterfaceRoots,
				true
			)) do
				table.insert(instancesToPreload, instance)
			end
		end

		if #preloadSpec.modalRootRoots > 0 then
			local modalRoot = resolveGuiRoot(playerGui, "ModalRoot", GUI_ROOT_TIMEOUT)
			if not (modalRoot and modalRoot:IsA("ScreenGui")) then
				Logger.Error(
					string.format(
						"%s Required PlayerGui.ModalRoot did not appear within %d seconds. This place should include the shared ModalRoot content.",
						formatContextPrefix(),
						GUI_ROOT_TIMEOUT
					),
					0
				)
			end

			for _, instance in ipairs(collectProfileGuiInstances(
				"ModalRoot",
				modalRoot,
				preloadSpec.modalRootRoots,
				true
			)) do
				table.insert(instancesToPreload, instance)
			end
		end

		for _, instance in ipairs(collectProfileGameAssetInstances(preloadSpec.gameAssetPaths)) do
			table.insert(instancesToPreload, instance)
		end

		preloadInstances(instancesToPreload, true)
	end)

	if not ok then
		preloadFailureMessage = tostring(err)
	end

	preloadCompleted = true
end)

waitForMinimumDisplay()

local preloadDeadline = os.clock() + OPTIONAL_PRELOAD_TIMEOUT
while not preloadCompleted and not skipRequested and os.clock() < preloadDeadline do
	task.wait(0.05)
end

if preloadFailureMessage ~= nil then
	Logger.Error(preloadFailureMessage, 0)
end

if not preloadCompleted and not skipRequested then
	Logger.Warn("[LoadingBootstrap] Optional preload timed out; dismissing loading screen.")
end

if skipConnection then
	skipConnection:Disconnect()
	skipConnection = nil
end

fadeOutAndDestroy()
