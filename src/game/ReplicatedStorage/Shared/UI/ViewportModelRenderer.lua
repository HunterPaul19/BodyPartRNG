local ViewportModelRenderer = {}

local MINIMUM_EXTENT = 2
local DEFAULT_FIELD_OF_VIEW = 35
local DIALOGUE_PORTRAIT_MIN_HEIGHT = 2.6
local DIALOGUE_PORTRAIT_MARGIN_SCALE = 1.08
local VIEWPORT_AMBIENT = Color3.fromRGB(255, 255, 255)
local VIEWPORT_LIGHT_COLOR = Color3.fromRGB(255, 255, 255)
local VIEWPORT_LIGHT_DIRECTION = Vector3.new(-1, -0.6, -0.8)
local CACHE_KEY_ATTRIBUTE = "ViewportModelRenderer_CacheKey"

local function clearViewport(viewportFrame: ViewportFrame)
	if not (viewportFrame and viewportFrame:IsA("ViewportFrame")) then
		return
	end

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
		framingPreviewModel:Destroy()
	else
		boundingBoxCFrame, boundingBoxSize = previewModel:GetBoundingBox()
	end
	local extent = math.max(boundingBoxSize.X, boundingBoxSize.Y, boundingBoxSize.Z, MINIMUM_EXTENT)

	local camera = Instance.new("Camera")
	camera.Name = "PreviewCamera"
	camera.FieldOfView = DEFAULT_FIELD_OF_VIEW
	camera.Parent = viewportFrame
	camera.CFrame = CFrame.lookAt(
		boundingBoxCFrame.Position + Vector3.new(extent * 0.65, extent * 0.2, extent * 1.85),
		boundingBoxCFrame.Position
	)

	viewportFrame.CurrentCamera = camera
	viewportFrame.Ambient = VIEWPORT_AMBIENT
	viewportFrame.LightColor = VIEWPORT_LIGHT_COLOR
	viewportFrame.LightDirection = VIEWPORT_LIGHT_DIRECTION
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

function ViewportModelRenderer.Clear(viewportFrame: ViewportFrame)
	clearViewport(viewportFrame)
end

function ViewportModelRenderer.RenderBundle(viewportFrame: ViewportFrame, bundleModel: Model?): boolean
	return renderModel(viewportFrame, bundleModel, nil)
end

function ViewportModelRenderer.RenderCharacterModel(viewportFrame: ViewportFrame, characterModel: Model?, framingModel: Model?): boolean
	return renderModel(viewportFrame, characterModel, framingModel)
end

function ViewportModelRenderer.RenderBaseRig(viewportFrame: ViewportFrame, baseRigModel: Model?): boolean
	return ViewportModelRenderer.RenderCharacterModel(viewportFrame, baseRigModel, baseRigModel)
end

function ViewportModelRenderer.RenderDialoguePortrait(viewportFrame: ViewportFrame, characterModel: Model?): boolean
	return renderDialoguePortrait(viewportFrame, characterModel)
end

return table.freeze(ViewportModelRenderer)
