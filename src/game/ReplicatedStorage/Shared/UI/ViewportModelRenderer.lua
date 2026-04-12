local ViewportModelRenderer = {}

local MINIMUM_EXTENT = 2
local DEFAULT_FIELD_OF_VIEW = 35
local VIEWPORT_AMBIENT = Color3.fromRGB(255, 255, 255)
local VIEWPORT_LIGHT_COLOR = Color3.fromRGB(255, 255, 255)
local VIEWPORT_LIGHT_DIRECTION = Vector3.new(-1, -0.6, -0.8)

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

local function renderModel(viewportFrame: ViewportFrame, sourceModel: Model?): boolean
	clearViewport(viewportFrame)

	if not (viewportFrame and viewportFrame:IsA("ViewportFrame")) then
		return false
	end
	if not (sourceModel and sourceModel:IsA("Model")) then
		return false
	end

	local worldModel = Instance.new("WorldModel")
	worldModel.Name = "PreviewWorld"
	worldModel.Parent = viewportFrame

	local previewModel = sourceModel:Clone()
	previewModel.Name = "PreviewModel"

	if not sanitizePreviewModel(previewModel) then
		previewModel:Destroy()
		worldModel:Destroy()
		return false
	end

	previewModel.Parent = worldModel
	facePreviewModel(previewModel)

	local boundingBoxCFrame, boundingBoxSize = previewModel:GetBoundingBox()
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

	return true
end

function ViewportModelRenderer.Clear(viewportFrame: ViewportFrame)
	clearViewport(viewportFrame)
end

function ViewportModelRenderer.RenderBundle(viewportFrame: ViewportFrame, bundleModel: Model?): boolean
	return renderModel(viewportFrame, bundleModel)
end

function ViewportModelRenderer.RenderBaseRig(viewportFrame: ViewportFrame, baseRigModel: Model?): boolean
	return renderModel(viewportFrame, baseRigModel)
end

return table.freeze(ViewportModelRenderer)
