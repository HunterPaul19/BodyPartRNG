local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AppearanceRegionRules = require(ReplicatedStorage.Shared.Character.AppearanceRegionRules)
local PreviewAppearanceSnapshot = require(ReplicatedStorage.Shared.Character.PreviewAppearanceSnapshot)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)

local ViewportModelRenderer = {}

local MINIMUM_EXTENT = 2
local DEFAULT_FIELD_OF_VIEW = 35
local POTION_MARGIN_SCALE = 1.5
local POTION_FOCUS_Y_SCALE = -0.02
local POTION_CAMERA_BACK_OFFSET = 2
local POTION_CAMERA_UP_OFFSET = 2
local DIALOGUE_PORTRAIT_MIN_HEIGHT = 2.6
local DIALOGUE_PORTRAIT_MARGIN_SCALE = 1.08
local VIEWPORT_AMBIENT = Color3.fromRGB(255, 255, 255)
local VIEWPORT_LIGHT_COLOR = Color3.fromRGB(255, 255, 255)
local VIEWPORT_LIGHT_DIRECTION = Vector3.new(-1, -0.6, -0.8)
local CACHE_KEY_ATTRIBUTE = "ViewportModelRenderer_CacheKey"
local rollPreviewSessions = setmetatable({}, { __mode = "k" })
local bodyPartPreviewSourceModels: { [string]: Model } = {}

local BODY_COLOR3_PROPERTY_BY_REGION = table.freeze({
	Head = "HeadColor3",
	Torso = "TorsoColor3",
	LeftArm = "LeftArmColor3",
	RightArm = "RightArmColor3",
	LeftLeg = "LeftLegColor3",
	RightLeg = "RightLegColor3",
})

local function isAppearancePolicy(value: any): boolean
	return typeof(value) == "table"
		and (value.applyPlayerClothing ~= nil or value.applyPlayerBodyColors ~= nil)
end

local function normalizeAppearancePolicy(value: any): { applyPlayerClothing: boolean, applyPlayerBodyColors: boolean }
	local policy = if isAppearancePolicy(value) then value else {}
	return {
		applyPlayerClothing = policy.applyPlayerClothing ~= false,
		applyPlayerBodyColors = policy.applyPlayerBodyColors ~= false,
	}
end

local function applyViewportLighting(viewportFrame: ViewportFrame, camera: Camera)
	viewportFrame.CurrentCamera = camera
	viewportFrame.Ambient = VIEWPORT_AMBIENT
	viewportFrame.LightColor = VIEWPORT_LIGHT_COLOR
	viewportFrame.LightDirection = VIEWPORT_LIGHT_DIRECTION
end

local function destroyRollPreviewSession(viewportFrame: ViewportFrame)
	local sessionState = rollPreviewSessions[viewportFrame]
	if not sessionState then
		return
	end

	for _, cachedModel in pairs(sessionState.cachedModels) do
		if cachedModel and cachedModel.Parent ~= nil then
			cachedModel.Parent = nil
		end
		if cachedModel then
			cachedModel:Destroy()
		end
	end

	rollPreviewSessions[viewportFrame] = nil
end

local function clearViewport(viewportFrame: ViewportFrame)
	if not (viewportFrame and viewportFrame:IsA("ViewportFrame")) then
		return
	end

	destroyRollPreviewSession(viewportFrame)

	for _, child in ipairs(viewportFrame:GetChildren()) do
		if child:IsA("WorldModel") or child:IsA("Camera") or child:IsA("Model") then
			child:Destroy()
		end
	end

	viewportFrame.CurrentCamera = nil
	viewportFrame:SetAttribute(CACHE_KEY_ATTRIBUTE, nil)
end

local function sanitizePreviewModel(previewModel: Model): boolean
	local hasRenderablePart = false

	for _, descendant in ipairs(previewModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			hasRenderablePart = true
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end

	return hasRenderablePart
end

local function facePreviewModel(previewModel: Model)
	local boundingBoxCFrame = previewModel:GetBoundingBox()
	local center = boundingBoxCFrame.Position
	local currentPivot = previewModel:GetPivot()
	local rotatedPivot = CFrame.new(center) * CFrame.Angles(0, math.rad(180), 0) * CFrame.new(-center) * currentPivot

	previewModel:PivotTo(rotatedPivot)
end

local function createPreviewClone(sourceModel: Model, name: string, shouldFaceViewport: boolean?): Model?
	local ok, previewModel = pcall(function()
		return sourceModel:Clone()
	end)
	if not ok or not previewModel then
		return nil
	end
	previewModel.Name = name

	if not sanitizePreviewModel(previewModel) then
		previewModel:Destroy()
		return nil
	end
	if shouldFaceViewport ~= false then
		facePreviewModel(previewModel)
	end

	return previewModel
end

local function cloneSourceModel(sourceModel: Model, name: string): Model?
	local ok, previewModel = pcall(function()
		return sourceModel:Clone()
	end)
	if not ok or not previewModel then
		return nil
	end

	previewModel.Name = name
	return previewModel
end

local function buildShortCacheToken(value: string): string
	local hash = 2166136261
	for index = 1, #value do
		hash = bit32.bxor(hash, string.byte(value, index))
		hash = (hash * 16777619) % 4294967296
	end

	return string.format("%08x", hash)
end

local function getModelCacheToken(model: Model?): string
	if not (model and model:IsA("Model")) then
		return "nil"
	end

	local ok, fullName = pcall(function()
		return model:GetFullName()
	end)
	if ok and typeof(fullName) == "string" then
		return fullName
	end

	return model.Name
end

local function createPreviewHumanoid(): Humanoid
	local baseRig = BodyPartsCatalog.GetDefaultBaseRig()
	local sourceHumanoid = baseRig and baseRig:FindFirstChildOfClass("Humanoid")
	local humanoid = if sourceHumanoid then sourceHumanoid:Clone() else Instance.new("Humanoid")

	pcall(function()
		humanoid.EvaluateStateMachine = false
	end)

	return humanoid
end

local function applyPreviewBodyColors(previewModel: Model, snapshot: any)
	local bodyColors = Instance.new("BodyColors")
	bodyColors.Name = "PreviewBodyColors"

	for region, propertyName in pairs(BODY_COLOR3_PROPERTY_BY_REGION) do
		bodyColors[propertyName] = PreviewAppearanceSnapshot.DecodeColor(snapshot.bodyColors, region)
	end

	bodyColors.Parent = previewModel
end

local function addPreviewClothing(previewModel: Model, snapshot: any, region: string, appearancePolicy: any)
	local relevantClasses = AppearanceRegionRules.GetRelevantClasses(region)
	local policy = normalizeAppearancePolicy(appearancePolicy)

	if relevantClasses.BodyColors and policy.applyPlayerBodyColors then
		applyPreviewBodyColors(previewModel, snapshot)
	end

	if policy.applyPlayerClothing
		and relevantClasses.Shirt
		and typeof(snapshot.shirtTemplate) == "string"
		and snapshot.shirtTemplate ~= ""
	then
		local shirt = Instance.new("Shirt")
		shirt.Name = "PreviewShirt"
		shirt.ShirtTemplate = snapshot.shirtTemplate
		shirt.Parent = previewModel
	end

	if policy.applyPlayerClothing
		and relevantClasses.Pants
		and typeof(snapshot.pantsTemplate) == "string"
		and snapshot.pantsTemplate ~= ""
	then
		local pants = Instance.new("Pants")
		pants.Name = "PreviewPants"
		pants.PantsTemplate = snapshot.pantsTemplate
		pants.Parent = previewModel
	end

	if policy.applyPlayerClothing
		and relevantClasses.ShirtGraphic
		and typeof(snapshot.shirtGraphic) == "string"
		and snapshot.shirtGraphic ~= ""
	then
		local shirtGraphic = Instance.new("ShirtGraphic")
		shirtGraphic.Name = "PreviewShirtGraphic"
		shirtGraphic.Graphic = snapshot.shirtGraphic
		shirtGraphic.Parent = previewModel
	end
end

local function buildBodyPartPreviewCacheKey(
	bundleModel: Model,
	region: string,
	snapshot: any,
	scale: number?,
	appearancePolicy: any
): string
	local normalizedScale = tonumber(scale) or 1
	local policy = normalizeAppearancePolicy(appearancePolicy)
	return table.concat({
		"bodyPartPreview",
		getModelCacheToken(bundleModel),
		tostring(region),
		snapshot.cacheKey,
		string.format("%.4f", normalizedScale),
		if policy.applyPlayerClothing then "clothing:on" else "clothing:off",
		if policy.applyPlayerBodyColors then "colors:on" else "colors:off",
	}, "|")
end

local function buildBodyPartPreviewSourceModel(
	bundleModel: Model,
	region: string,
	snapshot: any,
	scale: number?,
	appearancePolicy: any
): Model?
	local cacheKey = buildBodyPartPreviewCacheKey(bundleModel, region, snapshot, scale, appearancePolicy)
	local cachedModel = bodyPartPreviewSourceModels[cacheKey]
	if cachedModel then
		return cachedModel
	end

	local previewModel = cloneSourceModel(bundleModel, cacheKey)
	if not previewModel then
		return nil
	end
	previewModel.Name = string.format("BodyPartPreview_%s", buildShortCacheToken(cacheKey))

	local humanoid = createPreviewHumanoid()
	humanoid.Name = "PreviewHumanoid"
	humanoid.Parent = previewModel
	addPreviewClothing(previewModel, snapshot, region, appearancePolicy)

	bodyPartPreviewSourceModels[cacheKey] = previewModel
	return previewModel
end

local function getBundleCameraCFrame(previewModel: Model, framingPreviewModel: Model?): CFrame
	local boundingBoxCFrame, boundingBoxSize
	if framingPreviewModel then
		boundingBoxCFrame, boundingBoxSize = framingPreviewModel:GetBoundingBox()
	else
		boundingBoxCFrame, boundingBoxSize = previewModel:GetBoundingBox()
	end
	local extent = math.max(boundingBoxSize.X, boundingBoxSize.Y, boundingBoxSize.Z, MINIMUM_EXTENT)

	return CFrame.lookAt(
		boundingBoxCFrame.Position + Vector3.new(extent * 0.65, extent * 0.2, extent * 1.85),
		boundingBoxCFrame.Position
	)
end

local function getPreviewFrontVector(previewModel: Model): Vector3
	local lookVector = Vector3.new(previewModel:GetPivot().LookVector.X, 0, previewModel:GetPivot().LookVector.Z)
	if lookVector.Magnitude > 0.001 then
		return lookVector.Unit
	end

	return Vector3.new(0, 0, -1)
end

local function getPotionCameraCFrame(viewportFrame: ViewportFrame, previewModel: Model): CFrame
	local boundingBoxCFrame, boundingBoxSize = previewModel:GetBoundingBox()
	local focusPoint = boundingBoxCFrame.Position + Vector3.new(0, boundingBoxSize.Y * POTION_FOCUS_Y_SCALE, 0)
	local frontVector = getPreviewFrontVector(previewModel)
	local verticalHalfExtent = math.max(boundingBoxSize.Y * 0.5, MINIMUM_EXTENT * 0.5) * POTION_MARGIN_SCALE
	local viewportSize = viewportFrame.AbsoluteSize
	local aspectRatio = if viewportSize.Y > 0 then viewportSize.X / viewportSize.Y else 1
	local verticalFov = math.rad(DEFAULT_FIELD_OF_VIEW)
	local horizontalFov = 2 * math.atan(math.tan(verticalFov * 0.5) * math.max(aspectRatio, 0.01))
	local horizontalHalfExtent = math.max(boundingBoxSize.X, boundingBoxSize.Z, MINIMUM_EXTENT) * 0.5 * POTION_MARGIN_SCALE
	local verticalDistance = verticalHalfExtent / math.tan(verticalFov * 0.5)
	local horizontalDistance = horizontalHalfExtent / math.tan(horizontalFov * 0.5)
	local distance = math.max(verticalDistance, horizontalDistance)
	local baseCameraPosition = focusPoint + frontVector * distance
	local cameraPosition = baseCameraPosition
		+ frontVector * POTION_CAMERA_BACK_OFFSET
		+ Vector3.yAxis * POTION_CAMERA_UP_OFFSET

	return CFrame.lookAt(cameraPosition, focusPoint, Vector3.yAxis)
end

local function optimizePotionPreview(previewModel: Model)
	for _, descendant in ipairs(previewModel:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Transparency > 0 and descendant.Transparency < 1 then
			descendant.Transparency = math.min(descendant.Transparency, 0.28)
		end
	end
end

local function createRollPreviewSession(viewportFrame: ViewportFrame, sessionToken: any)
	clearViewport(viewportFrame)

	local worldModel = Instance.new("WorldModel")
	worldModel.Name = "PreviewWorld"
	worldModel.Parent = viewportFrame

	local camera = Instance.new("Camera")
	camera.Name = "PreviewCamera"
	camera.FieldOfView = DEFAULT_FIELD_OF_VIEW
	camera.Parent = viewportFrame

	applyViewportLighting(viewportFrame, camera)

	local sessionState = {
		sessionToken = sessionToken,
		worldModel = worldModel,
		camera = camera,
		cachedModels = {},
		activeModel = nil,
		activeCacheKey = nil,
	}
	rollPreviewSessions[viewportFrame] = sessionState

	return sessionState
end

local function ensureRollPreviewSession(viewportFrame: ViewportFrame, sessionToken: any)
	local sessionState = rollPreviewSessions[viewportFrame]
	if sessionState
		and sessionState.sessionToken == sessionToken
		and sessionState.worldModel
		and sessionState.worldModel.Parent == viewportFrame
		and sessionState.camera
		and sessionState.camera.Parent == viewportFrame
	then
		return sessionState
	end

	return createRollPreviewSession(viewportFrame, sessionToken)
end

local function deactivateActiveRollPreview(sessionState)
	local activeModel = sessionState.activeModel
	if activeModel and activeModel.Parent == sessionState.worldModel then
		activeModel.Parent = nil
	end

	sessionState.activeModel = nil
	sessionState.activeCacheKey = nil
end

local function renderModel(viewportFrame: ViewportFrame, sourceModel: Model?, framingModel: Model?): boolean
	if not (viewportFrame and viewportFrame:IsA("ViewportFrame")) then
		return false
	end
	if not (sourceModel and sourceModel:IsA("Model")) then
		clearViewport(viewportFrame)
		return false
	end

	local cacheKey = table.concat({
		"model",
		getModelCacheToken(sourceModel),
		getModelCacheToken(framingModel),
	}, "|")
	if viewportFrame:GetAttribute(CACHE_KEY_ATTRIBUTE) == cacheKey
		and viewportFrame.CurrentCamera ~= nil
		and viewportFrame:FindFirstChild("PreviewWorld") ~= nil
	then
		return true
	end

	clearViewport(viewportFrame)

	local worldModel = Instance.new("WorldModel")
	worldModel.Name = "PreviewWorld"
	worldModel.Parent = viewportFrame

	local previewModel = createPreviewClone(sourceModel, "PreviewModel")
	if not previewModel then
		worldModel:Destroy()
		return false
	end

	previewModel.Parent = worldModel

	local framingPreviewModel = nil
	if framingModel and framingModel:IsA("Model") then
		framingPreviewModel = createPreviewClone(framingModel, "FramingModel")
	end

	if framingPreviewModel then
		previewModel:PivotTo(framingPreviewModel:GetPivot())
	end

	local boundingBoxCFrame, boundingBoxSize
	if framingPreviewModel then
		boundingBoxCFrame, boundingBoxSize = framingPreviewModel:GetBoundingBox()
	else
		boundingBoxCFrame, boundingBoxSize = previewModel:GetBoundingBox()
	end

	local camera = Instance.new("Camera")
	camera.Name = "PreviewCamera"
	camera.FieldOfView = DEFAULT_FIELD_OF_VIEW
	camera.Parent = viewportFrame
	camera.CFrame = getBundleCameraCFrame(previewModel, framingPreviewModel)

	if framingPreviewModel then
		framingPreviewModel:Destroy()
	end

	applyViewportLighting(viewportFrame, camera)
	viewportFrame:SetAttribute(CACHE_KEY_ATTRIBUTE, cacheKey)

	return true
end

local function renderModelAtFramingPivot(viewportFrame: ViewportFrame, sourceModel: Model?, framingModel: Model?): boolean
	if not (viewportFrame and viewportFrame:IsA("ViewportFrame")) then
		return false
	end
	if not (sourceModel and sourceModel:IsA("Model")) then
		clearViewport(viewportFrame)
		return false
	end

	local cacheKey = table.concat({
		"modelAtFramingPivot",
		getModelCacheToken(sourceModel),
		getModelCacheToken(framingModel),
	}, "|")
	if viewportFrame:GetAttribute(CACHE_KEY_ATTRIBUTE) == cacheKey
		and viewportFrame.CurrentCamera ~= nil
		and viewportFrame:FindFirstChild("PreviewWorld") ~= nil
	then
		return true
	end

	clearViewport(viewportFrame)

	local worldModel = Instance.new("WorldModel")
	worldModel.Name = "PreviewWorld"
	worldModel.Parent = viewportFrame

	local previewModel = createPreviewClone(sourceModel, "PreviewModel", false)
	if not previewModel then
		worldModel:Destroy()
		return false
	end

	local framingPreviewModel = nil
	if framingModel and framingModel:IsA("Model") then
		framingPreviewModel = createPreviewClone(framingModel, "FramingModel", false)
	end

	if framingPreviewModel then
		local sourcePivot = previewModel:GetPivot()
		local targetPosition = framingPreviewModel:GetPivot().Position
		previewModel:PivotTo(CFrame.new(targetPosition) * (sourcePivot - sourcePivot.Position))
	end
	previewModel.Parent = worldModel

	local camera = Instance.new("Camera")
	camera.Name = "PreviewCamera"
	camera.FieldOfView = DEFAULT_FIELD_OF_VIEW
	camera.Parent = viewportFrame
	camera.CFrame = getBundleCameraCFrame(previewModel, nil)

	if framingPreviewModel then
		framingPreviewModel:Destroy()
	end

	applyViewportLighting(viewportFrame, camera)
	viewportFrame:SetAttribute(CACHE_KEY_ATTRIBUTE, cacheKey)

	return true
end

local function getPortraitFrontVector(previewModel: Model, head: BasePart?, torso: BasePart?): Vector3
	local frontSource = head or torso or previewModel.PrimaryPart
	if frontSource then
		local flattenedLook = Vector3.new(frontSource.CFrame.LookVector.X, 0, frontSource.CFrame.LookVector.Z)
		if flattenedLook.Magnitude > 0.001 then
			return flattenedLook.Unit
		end
	end

	local pivotLook = Vector3.new(previewModel:GetPivot().LookVector.X, 0, previewModel:GetPivot().LookVector.Z)
	if pivotLook.Magnitude > 0.001 then
		return pivotLook.Unit
	end

	return Vector3.new(0, 0, -1)
end

local function getDialoguePortraitFocus(previewModel: Model): (Vector3, number)
	local head = previewModel:FindFirstChild("Head", true)
	local upperTorso = previewModel:FindFirstChild("UpperTorso", true)
	local torso = upperTorso or previewModel:FindFirstChild("Torso", true)

	local headPart = if head and head:IsA("BasePart") then head else nil
	local torsoPart = if torso and torso:IsA("BasePart") then torso else nil

	if headPart and torsoPart then
		local headTop = headPart.Position.Y + headPart.Size.Y * 0.5
		local torsoBottom = torsoPart.Position.Y - torsoPart.Size.Y * 0.35
		local portraitHeight = math.max(headTop - torsoBottom, DIALOGUE_PORTRAIT_MIN_HEIGHT)
		return headPart.Position:Lerp(torsoPart.Position, 0.32), portraitHeight
	end

	if headPart then
		local portraitHeight = math.max(headPart.Size.Y * 3.0, DIALOGUE_PORTRAIT_MIN_HEIGHT)
		return headPart.Position - Vector3.new(0, headPart.Size.Y * 0.22, 0), portraitHeight
	end

	if torsoPart then
		local portraitHeight = math.max(torsoPart.Size.Y * 2.1, DIALOGUE_PORTRAIT_MIN_HEIGHT)
		return torsoPart.Position + Vector3.new(0, torsoPart.Size.Y * 0.18, 0), portraitHeight
	end

	local boundingBoxCFrame, boundingBoxSize = previewModel:GetBoundingBox()
	local portraitHeight = math.max(boundingBoxSize.Y * 0.6, DIALOGUE_PORTRAIT_MIN_HEIGHT)
	return boundingBoxCFrame.Position + Vector3.new(0, boundingBoxSize.Y * 0.18, 0), portraitHeight
end

local function renderDialoguePortrait(viewportFrame: ViewportFrame, sourceModel: Model?): boolean
	if not (viewportFrame and viewportFrame:IsA("ViewportFrame")) then
		return false
	end
	if not (sourceModel and sourceModel:IsA("Model")) then
		clearViewport(viewportFrame)
		return false
	end

	local cacheKey = table.concat({
		"dialogue",
		getModelCacheToken(sourceModel),
	}, "|")
	if viewportFrame:GetAttribute(CACHE_KEY_ATTRIBUTE) == cacheKey
		and viewportFrame.CurrentCamera ~= nil
		and viewportFrame:FindFirstChild("PreviewWorld") ~= nil
	then
		return true
	end

	clearViewport(viewportFrame)

	local worldModel = Instance.new("WorldModel")
	worldModel.Name = "PreviewWorld"
	worldModel.Parent = viewportFrame

	local previewModel = createPreviewClone(sourceModel, "DialoguePortraitModel", false)
	if not previewModel then
		worldModel:Destroy()
		return false
	end

	optimizePotionPreview(previewModel)
	previewModel.Parent = worldModel

	local head = previewModel:FindFirstChild("Head", true)
	local upperTorso = previewModel:FindFirstChild("UpperTorso", true)
	local torso = upperTorso or previewModel:FindFirstChild("Torso", true)
	local headPart = if head and head:IsA("BasePart") then head else nil
	local torsoPart = if torso and torso:IsA("BasePart") then torso else nil

	local focusPoint, portraitHeight = getDialoguePortraitFocus(previewModel)
	local frontVector = getPortraitFrontVector(previewModel, headPart, torsoPart)
	local camera = Instance.new("Camera")
	camera.Name = "PreviewCamera"
	camera.FieldOfView = DEFAULT_FIELD_OF_VIEW
	camera.Parent = viewportFrame

	local distance = ((portraitHeight * 0.5) / math.tan(math.rad(camera.FieldOfView * 0.5))) * DIALOGUE_PORTRAIT_MARGIN_SCALE
	local cameraPosition = focusPoint + frontVector * distance
	camera.CFrame = CFrame.lookAt(cameraPosition, focusPoint, Vector3.yAxis)

	viewportFrame.CurrentCamera = camera
	viewportFrame.Ambient = VIEWPORT_AMBIENT
	viewportFrame.LightColor = VIEWPORT_LIGHT_COLOR
	viewportFrame.LightDirection = VIEWPORT_LIGHT_DIRECTION
	viewportFrame:SetAttribute(CACHE_KEY_ATTRIBUTE, cacheKey)

	return true
end

local function renderPotion(viewportFrame: ViewportFrame, sourceModel: Model?): boolean
	if not (viewportFrame and viewportFrame:IsA("ViewportFrame")) then
		return false
	end
	if not (sourceModel and sourceModel:IsA("Model")) then
		clearViewport(viewportFrame)
		return false
	end

	local cacheKey = table.concat({
		"potion",
		getModelCacheToken(sourceModel),
	}, "|")
	if viewportFrame:GetAttribute(CACHE_KEY_ATTRIBUTE) == cacheKey
		and viewportFrame.CurrentCamera ~= nil
		and viewportFrame:FindFirstChild("PreviewWorld") ~= nil
	then
		return true
	end

	clearViewport(viewportFrame)

	local worldModel = Instance.new("WorldModel")
	worldModel.Name = "PreviewWorld"
	worldModel.Parent = viewportFrame

	local previewModel = createPreviewClone(sourceModel, "PotionPreviewModel")
	if not previewModel then
		worldModel:Destroy()
		return false
	end

	previewModel.Parent = worldModel

	local camera = Instance.new("Camera")
	camera.Name = "PreviewCamera"
	camera.FieldOfView = DEFAULT_FIELD_OF_VIEW
	camera.Parent = viewportFrame
	camera.CFrame = getPotionCameraCFrame(viewportFrame, previewModel)

	applyViewportLighting(viewportFrame, camera)
	viewportFrame:SetAttribute(CACHE_KEY_ATTRIBUTE, cacheKey)

	return true
end

function ViewportModelRenderer.Clear(viewportFrame: ViewportFrame)
	clearViewport(viewportFrame)
end

function ViewportModelRenderer.ClearRollPreview(viewportFrame: ViewportFrame)
	clearViewport(viewportFrame)
end

function ViewportModelRenderer.RenderRollPreview(viewportFrame: ViewportFrame, sourceModel: Model?, sessionToken: any): boolean
	if not (viewportFrame and viewportFrame:IsA("ViewportFrame")) then
		return false
	end
	if sessionToken == nil then
		clearViewport(viewportFrame)
		return false
	end

	local sessionState = ensureRollPreviewSession(viewportFrame, sessionToken)
	if not (sourceModel and sourceModel:IsA("Model")) then
		deactivateActiveRollPreview(sessionState)
		viewportFrame:SetAttribute(CACHE_KEY_ATTRIBUTE, nil)
		return false
	end

	local cacheKey = table.concat({
		"roll",
		getModelCacheToken(sourceModel),
	}, "|")
	if sessionState.activeCacheKey == cacheKey
		and sessionState.activeModel ~= nil
		and sessionState.activeModel.Parent == sessionState.worldModel
	then
		return true
	end

	local previewModel = sessionState.cachedModels[cacheKey]
	if not previewModel then
		previewModel = createPreviewClone(sourceModel, "RollPreviewModel")
		if not previewModel then
			deactivateActiveRollPreview(sessionState)
			viewportFrame:SetAttribute(CACHE_KEY_ATTRIBUTE, nil)
			return false
		end
		sessionState.cachedModels[cacheKey] = previewModel
	end

	deactivateActiveRollPreview(sessionState)

	previewModel.Parent = sessionState.worldModel
	sessionState.camera.CFrame = getBundleCameraCFrame(previewModel, nil)
	applyViewportLighting(viewportFrame, sessionState.camera)
	viewportFrame:SetAttribute(CACHE_KEY_ATTRIBUTE, cacheKey)
	sessionState.activeModel = previewModel
	sessionState.activeCacheKey = cacheKey

	return true
end

function ViewportModelRenderer.RenderBodyPartPreview(
	viewportFrame: ViewportFrame,
	bundleModel: Model?,
	region: string?,
	appearanceSnapshot: any,
	scale: number?,
	appearancePolicyOrSessionToken: any,
	sessionToken: any
): boolean
	local hasAppearancePolicy = isAppearancePolicy(appearancePolicyOrSessionToken)
	local appearancePolicy = if hasAppearancePolicy then appearancePolicyOrSessionToken else nil
	local resolvedSessionToken = if sessionToken ~= nil
		then sessionToken
		elseif hasAppearancePolicy then nil
		else appearancePolicyOrSessionToken

	if not (bundleModel and bundleModel:IsA("Model") and typeof(region) == "string" and region ~= "") then
		if resolvedSessionToken ~= nil then
			return ViewportModelRenderer.RenderRollPreview(viewportFrame, bundleModel, resolvedSessionToken)
		end

		return renderModel(viewportFrame, bundleModel, nil)
	end

	if appearanceSnapshot == nil then
		if resolvedSessionToken ~= nil then
			return ViewportModelRenderer.RenderRollPreview(viewportFrame, bundleModel, resolvedSessionToken)
		end

		return renderModel(viewportFrame, bundleModel, nil)
	end

	local snapshot = PreviewAppearanceSnapshot.Normalize(appearanceSnapshot)
	local previewModel = buildBodyPartPreviewSourceModel(bundleModel, region, snapshot, scale, appearancePolicy)
	if not previewModel then
		if resolvedSessionToken ~= nil then
			return ViewportModelRenderer.RenderRollPreview(viewportFrame, bundleModel, resolvedSessionToken)
		end

		return renderModel(viewportFrame, bundleModel, nil)
	end

	if resolvedSessionToken ~= nil then
		return ViewportModelRenderer.RenderRollPreview(viewportFrame, previewModel, resolvedSessionToken)
	end

	return renderModel(viewportFrame, previewModel, nil)
end

function ViewportModelRenderer.RenderBundle(viewportFrame: ViewportFrame, bundleModel: Model?): boolean
	return renderModel(viewportFrame, bundleModel, nil)
end

function ViewportModelRenderer.RenderPotion(viewportFrame: ViewportFrame, potionModel: Model?): boolean
	return renderPotion(viewportFrame, potionModel)
end

function ViewportModelRenderer.RenderCharacterModel(viewportFrame: ViewportFrame, characterModel: Model?, framingModel: Model?): boolean
	return renderModel(viewportFrame, characterModel, framingModel)
end

function ViewportModelRenderer.RenderCharacterModelAtFramingPivot(
	viewportFrame: ViewportFrame,
	characterModel: Model?,
	framingModel: Model?
): boolean
	return renderModelAtFramingPivot(viewportFrame, characterModel, framingModel)
end

function ViewportModelRenderer.RenderBaseRig(viewportFrame: ViewportFrame, baseRigModel: Model?): boolean
	return ViewportModelRenderer.RenderCharacterModel(viewportFrame, baseRigModel, baseRigModel)
end

function ViewportModelRenderer.RenderDialoguePortrait(viewportFrame: ViewportFrame, characterModel: Model?): boolean
	return renderDialoguePortrait(viewportFrame, characterModel)
end

return table.freeze(ViewportModelRenderer)
