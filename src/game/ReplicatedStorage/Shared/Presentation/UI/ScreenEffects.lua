local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameAssetPaths = require(ReplicatedStorage.Shared.Assets.GameAssetPaths)
local GameAssetResolver = require(ReplicatedStorage.Shared.Assets.GameAssetResolver)

local ScreenEffects = {}

local GAME_ASSETS_FOLDER_NAME = "GameAssets"
local SCREEN_EFFECTS_FOLDER_NAME = "ScreenEffects"
local CLEANUP_DELAY = 1.5

local PRESET_CONFIGS = table.freeze({
	Corrupted = {
		frontOffset = CFrame.new(0, 0, -2),
	},
	Diamond = {
		frontOffset = CFrame.new(0, 0, -2),
	},
	Magma = {
		frontOffset = CFrame.new(0, 0, -1.8),
	},
	Prismatic = {
		frontOffset = CFrame.new(0, 0, -2),
	},
})

type PresetConfig = {
	frontOffset: CFrame,
}

type ActiveEffectState = {
	effectPart: BasePart,
	expireAt: number?,
	renderConnection: RBXScriptConnection?,
}

local activeEffects: { [string]: ActiveEffectState } = {}
local warnedMissingAssets: { [string]: boolean } = {}

local function getScreenEffectsFolder(): Folder?
	local screenEffects = GameAssetResolver.FindFirst({ GameAssetPaths.Effects.Screen, GameAssetPaths.Legacy.ScreenEffects })
	if screenEffects and screenEffects:IsA("Folder") then
		return screenEffects
	end

	return nil
end

local function warnMissingPresetAsset(presetName: string)
	if warnedMissingAssets[presetName] == true then
		return
	end

	warnedMissingAssets[presetName] = true
	Logger.Warn(
		string.format(
			"[ScreenEffects] Missing preset asset at ReplicatedStorage.%s.%s.%s.",
			GAME_ASSETS_FOLDER_NAME,
			SCREEN_EFFECTS_FOLDER_NAME,
			presetName
		)
	)
end

local function resolvePresetTemplate(presetName: string): BasePart?
	local screenEffectsFolder = getScreenEffectsFolder()
	if screenEffectsFolder == nil then
		warnMissingPresetAsset(presetName)
		return nil
	end

	local presetTemplate = screenEffectsFolder:FindFirstChild(presetName)
	if presetTemplate and presetTemplate:IsA("BasePart") then
		warnedMissingAssets[presetName] = nil
		return presetTemplate
	end

	warnMissingPresetAsset(presetName)
	return nil
end

local function setEmittersEnabled(root: Instance, enabled: boolean)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = enabled
		end
	end
end

local function syncEffectPartToCamera(
	effectPart: BasePart,
	originalSize: Vector3,
	presetConfig: PresetConfig,
	camera: Camera
)
	local viewport = camera.ViewportSize
	local viewportWidth = math.max(viewport.X, 1)
	local viewportHeight = math.max(viewport.Y, 1)
	local depth = math.max(math.abs(presetConfig.frontOffset.Position.Z), 0.001)
	local fov = math.rad(camera.FieldOfView)
	local visibleHeight = 2 * math.tan(fov / 2) * depth
	local visibleWidth = visibleHeight * (viewportWidth / viewportHeight)

	effectPart.Size = Vector3.new(
		visibleWidth,
		visibleHeight,
		originalSize.Z
	)
	effectPart.CFrame = camera.CFrame * presetConfig.frontOffset
end

local function disconnectEffect(state: ActiveEffectState)
	if state.renderConnection then
		state.renderConnection:Disconnect()
		state.renderConnection = nil
	end
end

local function hidePresetInternal(presetName: string)
	local activeState = activeEffects[presetName]
	if activeState == nil then
		return
	end

	activeEffects[presetName] = nil
	disconnectEffect(activeState)

	local effectPart = activeState.effectPart
	setEmittersEnabled(effectPart, false)
	task.delay(CLEANUP_DELAY, function()
		if effectPart.Parent then
			effectPart:Destroy()
		end
	end)
end

function ScreenEffects.Show(presetName: string): boolean
	if typeof(presetName) ~= "string" or presetName == "" then
		return false
	end

	local presetConfig = PRESET_CONFIGS[presetName]
	if presetConfig == nil then
		return false
	end

	local activeState = activeEffects[presetName]
	if activeState and activeState.effectPart.Parent then
		activeState.expireAt = nil
		return true
	end

	local template = resolvePresetTemplate(presetName)
	if template == nil then
		return false
	end

	local camera = Workspace.CurrentCamera
	if camera == nil then
		return false
	end

	local clonedTemplate = template:Clone()
	if not clonedTemplate:IsA("BasePart") then
		clonedTemplate:Destroy()
		return false
	end

	clonedTemplate.Name = string.format("%sScreenEffect", presetName)
	clonedTemplate.Anchored = true
	clonedTemplate.CanCollide = false
	clonedTemplate.CanQuery = false
	clonedTemplate.CanTouch = false
	clonedTemplate.CastShadow = false
	clonedTemplate.Parent = camera

	local originalSize = template.Size
	syncEffectPartToCamera(clonedTemplate, originalSize, presetConfig, camera)
	setEmittersEnabled(clonedTemplate, true)

	local nextState: ActiveEffectState = {
		effectPart = clonedTemplate,
		expireAt = nil,
		renderConnection = nil,
	}

	nextState.renderConnection = RunService.RenderStepped:Connect(function()
		local currentCamera = Workspace.CurrentCamera
		if currentCamera == nil or clonedTemplate.Parent == nil then
			return
		end

		if clonedTemplate.Parent ~= currentCamera then
			clonedTemplate.Parent = currentCamera
		end

		syncEffectPartToCamera(clonedTemplate, originalSize, presetConfig, currentCamera)
	end)

	activeEffects[presetName] = nextState
	return true
end

function ScreenEffects.Hide(presetName: string)
	if typeof(presetName) ~= "string" or presetName == "" then
		return
	end

	hidePresetInternal(presetName)
end

function ScreenEffects.HideAll()
	local presetNames = {}
	for presetName in pairs(activeEffects) do
		table.insert(presetNames, presetName)
	end

	for _, presetName in ipairs(presetNames) do
		hidePresetInternal(presetName)
	end
end

function ScreenEffects.Apply(presetName: string, duration: number): boolean
	if not ScreenEffects.Show(presetName) then
		return false
	end

	local activeState = activeEffects[presetName]
	if activeState and typeof(duration) == "number" and duration > 0 then
		local now = os.clock()
		activeState.expireAt = math.max(activeState.expireAt or now, now) + duration
	end

	return true
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	local expiredPresetNames = {}

	for presetName, activeState in pairs(activeEffects) do
		if typeof(activeState.expireAt) == "number" and now >= activeState.expireAt then
			table.insert(expiredPresetNames, presetName)
		end
	end

	for _, presetName in ipairs(expiredPresetNames) do
		hidePresetInternal(presetName)
	end
end)

return table.freeze(ScreenEffects)
