local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local ViewportModelRenderer = require(ReplicatedStorage.Shared.UI.ViewportModelRenderer)
local Spring = require(ReplicatedStorage.Common.Spring)

local AvatarViewportPreview = {}
AvatarViewportPreview.__index = AvatarViewportPreview

local IDLE_FADE_SECONDS = 0.2
local HEAD_LOOK_DAMPING_RATIO = 0.85
local HEAD_LOOK_FREQUENCY = 8
local HEAD_LOOK_MAX_YAW = math.rad(10)
local HEAD_LOOK_MAX_PITCH = math.rad(6)
local DEFAULT_IDLE_ANIMATION_IDS = table.freeze({
	"rbxassetid://507766388",
	"rbxassetid://507766666",
	"rbxassetid://507766951",
})

type AvatarViewportPreviewOptions = {
	viewportFrame: ViewportFrame?,
	applyRig: Model?,
	isActive: (() -> boolean)?,
	logPrefix: string?,
}

function AvatarViewportPreview.new(options: AvatarViewportPreviewOptions?)
	local self = setmetatable({}, AvatarViewportPreview)
	options = options or {}

	self._viewportFrame = nil :: ViewportFrame?
	self._rigTemplate = nil :: Model?
	self._isActive = options.isActive
	self._logPrefix = options.logPrefix or "[AvatarViewportPreview]"
	self._renderToken = 0
	self._resolvingUserId = nil :: number?
	self._cachedUserId = nil :: number?
	self._renderedUserId = nil :: number?
	self._cachedPreviewModel = nil :: Model?
	self._activePlayer = nil :: Player?
	self._idleTrack = nil :: AnimationTrack?
	self._idleAnimation = nil :: Animation?
	self._headLookConnection = nil :: RBXScriptConnection?
	self._neckMotor = nil :: Motor6D?
	self._neckBaseC0 = nil :: CFrame?
	self._lastHeadLookPitch = nil :: number?
	self._lastHeadLookYaw = nil :: number?

	self:SetViewport(options.viewportFrame, options.applyRig)

	return self
end

function AvatarViewportPreview:SetViewport(viewportFrame: ViewportFrame?, applyRig: Model?)
	if self._viewportFrame ~= viewportFrame then
		self:Clear()
	end

	self._viewportFrame = viewportFrame

	local previousRigTemplate = self._rigTemplate
	if previousRigTemplate then
		previousRigTemplate:Destroy()
		self._rigTemplate = nil
	end

	if applyRig and applyRig:IsA("Model") and applyRig:FindFirstChildOfClass("Humanoid") then
		self._rigTemplate = applyRig:Clone()
		self._rigTemplate.Name = "AvatarViewportApplyRigTemplate"
	elseif applyRig ~= nil then
		Logger.Warn(self._logPrefix .. " ApplyRig template is missing or invalid; using default base rig for avatar preview.")
	end
end

function AvatarViewportPreview:_getRigTemplate(): Model?
	local rigTemplate = self._rigTemplate
	if rigTemplate and rigTemplate:IsA("Model") and rigTemplate:FindFirstChildOfClass("Humanoid") then
		return rigTemplate
	end

	return BodyPartsCatalog.GetDefaultBaseRig()
end

function AvatarViewportPreview:_destroyCachedPreviewModel()
	local cachedModel = self._cachedPreviewModel
	if cachedModel and cachedModel.Parent == nil then
		cachedModel:Destroy()
	end

	self._cachedPreviewModel = nil
	self._cachedUserId = nil
	self._renderedUserId = nil
end

function AvatarViewportPreview:_stopPresentation()
	local headLookConnection = self._headLookConnection
	if headLookConnection then
		headLookConnection:Disconnect()
		self._headLookConnection = nil
	end

	local idleTrack = self._idleTrack
	if idleTrack then
		pcall(function()
			idleTrack:Stop(IDLE_FADE_SECONDS)
			idleTrack:Destroy()
		end)
		self._idleTrack = nil
	end

	local idleAnimation = self._idleAnimation
	if idleAnimation then
		idleAnimation:Destroy()
		self._idleAnimation = nil
	end

	local neckMotor = self._neckMotor
	if neckMotor then
		Spring.stop(neckMotor, "C0")
		if neckMotor.Parent ~= nil then
			neckMotor.C0 = self._neckBaseC0 or neckMotor.C0
		end
		self._neckMotor = nil
		self._neckBaseC0 = nil
		self._lastHeadLookPitch = nil
		self._lastHeadLookYaw = nil
	end
end

function AvatarViewportPreview:_isPresentationActive(): boolean
	local idleTrack = self._idleTrack
	if idleTrack and idleTrack.IsPlaying then
		return true
	end

	return self._headLookConnection ~= nil
end

function AvatarViewportPreview:_canPlayPresentation(): boolean
	return self._isActive == nil or self._isActive()
end

function AvatarViewportPreview:Clear()
	self._renderToken += 1
	self._resolvingUserId = nil
	self._activePlayer = nil
	self:_stopPresentation()
	self:_destroyCachedPreviewModel()

	local viewportFrame = self._viewportFrame
	if viewportFrame then
		ViewportModelRenderer.Clear(viewportFrame)
	end
end

function AvatarViewportPreview:Destroy()
	self:Clear()

	local rigTemplate = self._rigTemplate
	if rigTemplate then
		rigTemplate:Destroy()
		self._rigTemplate = nil
	end

	self._viewportFrame = nil
end

function AvatarViewportPreview:_getRenderedPreviewModel(): Model?
	local viewportFrame = self._viewportFrame
	if not (viewportFrame and viewportFrame:IsA("ViewportFrame")) then
		return nil
	end

	local worldModel = viewportFrame:FindFirstChild("PreviewWorld")
	if worldModel and worldModel:IsA("WorldModel") then
		local previewModel = worldModel:FindFirstChild("PreviewModel")
		if previewModel and previewModel:IsA("Model") then
			return previewModel
		end
	end

	return nil
end

function AvatarViewportPreview:_renderModel(sourceModel: Model?, shouldPlayPresentation: boolean)
	self:_stopPresentation()

	local viewportFrame = self._viewportFrame
	if not viewportFrame then
		return
	end

	local rendered = ViewportModelRenderer.RenderCharacterModelAtFramingBounds(viewportFrame, sourceModel, self:_getRigTemplate())
	if rendered and shouldPlayPresentation and self:_canPlayPresentation() then
		self:_startPresentation()
	end
end

function AvatarViewportPreview:_getCurrentHumanoidDescription(player: Player?): HumanoidDescription?
	local character = player and player.Character or nil
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	local ok, description = pcall(function()
		return humanoid:GetAppliedDescription()
	end)
	if not ok or not description or not description:IsA("HumanoidDescription") then
		return nil
	end

	return description
end

function AvatarViewportPreview:_alignPreviewModelToRigTemplate(previewModel: Model)
	local rigTemplate = self:_getRigTemplate()
	if not (rigTemplate and rigTemplate:IsA("Model")) then
		return
	end

	local rigPivot = rigTemplate:GetPivot()
	local previewPivot = previewModel:GetPivot()
	previewModel:PivotTo(CFrame.new(previewPivot.Position) * (rigPivot - rigPivot.Position))
end

function AvatarViewportPreview:_resolveAccessories(previewModel: Model)
	local originalParent = previewModel.Parent
	local originalPivot = previewModel:GetPivot()

	previewModel:PivotTo(CFrame.new(0, -10000, 0) * (originalPivot - originalPivot.Position))
	previewModel.Parent = Workspace
	task.wait()
	previewModel.Parent = originalParent
	previewModel:PivotTo(originalPivot)
end

function AvatarViewportPreview:_createPreviewModelFromDescription(description: HumanoidDescription?, renderToken: number): Model?
	if not description then
		return nil
	end

	local ok, previewModel = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not (previewModel and previewModel:IsA("Model")) then
		ok, previewModel = pcall(function()
			return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
		end)
	end
	if not ok or not (previewModel and previewModel:IsA("Model")) then
		return nil
	end

	previewModel.Name = string.format("AvatarViewportPreview_%d", renderToken)
	if not previewModel:FindFirstChildOfClass("Humanoid") then
		previewModel:Destroy()
		return nil
	end

	self:_resolveAccessories(previewModel)
	self:_alignPreviewModelToRigTemplate(previewModel)

	return previewModel
end

function AvatarViewportPreview:_buildPreviewModel(userId: number, player: Player?, renderToken: number): Model?
	local currentDescription = self:_getCurrentHumanoidDescription(player)
	local previewModel = self:_createPreviewModelFromDescription(currentDescription, renderToken)
	if currentDescription then
		currentDescription:Destroy()
	end
	if previewModel then
		return previewModel
	end

	local ok, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(userId)
	end)
	if not ok or not description or not description:IsA("HumanoidDescription") then
		return nil
	end

	previewModel = self:_createPreviewModelFromDescription(description, renderToken)
	description:Destroy()
	return previewModel
end

function AvatarViewportPreview:_getIdleAnimationIds(player: Player?): { string }
	local animationIds = {}
	local seenAnimationIds = {}

	local function appendAnimationId(animationId: any)
		if animationId == nil then
			return
		end

		local normalizedId = tostring(animationId)
		if normalizedId == "" or normalizedId == "0" then
			return
		end
		if not string.find(normalizedId, "rbxassetid://", 1, true) then
			local numericId = string.match(normalizedId, "[?&]id=(%d+)") or string.match(normalizedId, "^(%d+)$")
			if numericId == nil then
				return
			end
			normalizedId = "rbxassetid://" .. numericId
		end
		if seenAnimationIds[normalizedId] then
			return
		end

		seenAnimationIds[normalizedId] = true
		table.insert(animationIds, normalizedId)
	end

	local character = player and player.Character or nil
	local animateScript = character and character:FindFirstChild("Animate") or nil
	local idleFolder = animateScript and animateScript:FindFirstChild("idle") or nil
	if idleFolder then
		for _, animationName in ipairs({ "Animation1", "Animation2" }) do
			local animation = idleFolder:FindFirstChild(animationName)
			if animation and animation:IsA("Animation") and animation.AnimationId ~= "" then
				appendAnimationId(animation.AnimationId)
			end
		end

		local animation = idleFolder:FindFirstChildWhichIsA("Animation")
		if animation and animation.AnimationId ~= "" then
			appendAnimationId(animation.AnimationId)
		end
	end

	for _, animationId in ipairs(DEFAULT_IDLE_ANIMATION_IDS) do
		appendAnimationId(animationId)
	end

	return animationIds
end

function AvatarViewportPreview:_getOrCreateAnimator(humanoid: Humanoid): Animator
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end

	local createdAnimator = Instance.new("Animator")
	createdAnimator.Parent = humanoid
	return createdAnimator
end

function AvatarViewportPreview:_tryStartIdleTrack(
	animator: Animator,
	previewModel: Model,
	idleAnimationId: string
): (AnimationTrack?, Animation?, any?)
	local idleAnimation = Instance.new("Animation")
	idleAnimation.Name = "AvatarViewportPreviewIdle"
	idleAnimation.AnimationId = idleAnimationId
	idleAnimation.Parent = previewModel

	local ok, trackOrError = pcall(function()
		return animator:LoadAnimation(idleAnimation)
	end)
	if not ok or not trackOrError then
		idleAnimation:Destroy()
		return nil, nil, trackOrError
	end

	local idleTrack = trackOrError :: AnimationTrack
	idleTrack.Looped = true
	idleTrack.Priority = Enum.AnimationPriority.Idle
	idleTrack:Play(IDLE_FADE_SECONDS, 1, 1)
	task.wait()

	if not idleTrack.IsPlaying then
		pcall(function()
			idleTrack:Stop(0)
			idleTrack:Destroy()
		end)
		idleAnimation:Destroy()
		return nil, nil, "track did not remain playing after Play()"
	end

	return idleTrack, idleAnimation, nil
end

function AvatarViewportPreview:_prepareAnimatedModel(previewModel: Model)
	local rootPartInstance = previewModel:FindFirstChild("HumanoidRootPart", true)
	local rootPart = if rootPartInstance and rootPartInstance:IsA("BasePart") then rootPartInstance else nil
	for _, descendant in ipairs(previewModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = rootPart == nil or descendant == rootPart
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
		end
	end
end

function AvatarViewportPreview:_startIdle(previewModel: Model)
	local humanoid = previewModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		Logger.Warn(self._logPrefix .. " idle skipped; rendered preview model has no Humanoid.")
		return
	end

	local idleAnimationIds = self:_getIdleAnimationIds(self._activePlayer)
	if #idleAnimationIds == 0 then
		Logger.Warn(self._logPrefix .. " idle skipped; no idle animation IDs were available.")
		return
	end

	local animator = self:_getOrCreateAnimator(humanoid)
	local lastLoadError = nil
	local lastAttemptedAnimationId = nil

	for _, idleAnimationId in ipairs(idleAnimationIds) do
		lastAttemptedAnimationId = idleAnimationId
		local idleTrack, idleAnimation, loadError = self:_tryStartIdleTrack(animator, previewModel, idleAnimationId)
		if idleTrack and idleAnimation then
			self._idleTrack = idleTrack
			self._idleAnimation = idleAnimation
			return
		end

		lastLoadError = loadError
	end

	Logger.Warn(string.format(
		"%s failed to start idle after %d candidate(s). HasAnimator=%s AnimationId=%s Error=%s",
		self._logPrefix,
		#idleAnimationIds,
		tostring(animator ~= nil),
		tostring(lastAttemptedAnimationId),
		tostring(lastLoadError)
	))
end

function AvatarViewportPreview:_findNeckMotor(previewModel: Model): Motor6D?
	for _, descendant in ipairs(previewModel:GetDescendants()) do
		if descendant:IsA("Motor6D") and descendant.Name == "Neck" then
			return descendant
		end
	end

	return nil
end

function AvatarViewportPreview:_startHeadLook(previewModel: Model)
	local viewportFrame = self._viewportFrame
	if not (viewportFrame and viewportFrame:IsA("ViewportFrame")) then
		return
	end

	local neckMotor = self:_findNeckMotor(previewModel)
	if not neckMotor then
		return
	end

	self._neckMotor = neckMotor
	self._neckBaseC0 = neckMotor.C0
	self._headLookConnection = RunService.RenderStepped:Connect(function()
		if neckMotor.Parent == nil or not viewportFrame:IsDescendantOf(game) then
			self:_stopPresentation()
			return
		end
		if self._isActive and not self._isActive() then
			self:_stopPresentation()
			return
		end

		local absoluteSize = viewportFrame.AbsoluteSize
		if absoluteSize.X <= 0 or absoluteSize.Y <= 0 then
			return
		end

		local mousePosition = UserInputService:GetMouseLocation()
		local viewportCenter = viewportFrame.AbsolutePosition + (absoluteSize * 0.5)
		local normalizedX = math.clamp((mousePosition.X - viewportCenter.X) / (absoluteSize.X * 0.5), -1, 1)
		local normalizedY = math.clamp((mousePosition.Y - viewportCenter.Y) / (absoluteSize.Y * 0.5), -1, 1)
		local yaw = -normalizedX * HEAD_LOOK_MAX_YAW
		local pitch = normalizedY * HEAD_LOOK_MAX_PITCH
		if
			self._lastHeadLookPitch ~= nil
			and self._lastHeadLookYaw ~= nil
			and math.abs(pitch - self._lastHeadLookPitch) < 0.001
			and math.abs(yaw - self._lastHeadLookYaw) < 0.001
		then
			return
		end
		self._lastHeadLookPitch = pitch
		self._lastHeadLookYaw = yaw

		Spring.target(neckMotor, HEAD_LOOK_DAMPING_RATIO, HEAD_LOOK_FREQUENCY, {
			C0 = (self._neckBaseC0 or neckMotor.C0) * CFrame.Angles(pitch, yaw, 0),
		})
	end)
end

function AvatarViewportPreview:_startPresentation()
	local previewModel = self:_getRenderedPreviewModel()
	if not previewModel then
		return
	end

	self:_prepareAnimatedModel(previewModel)
	self:_startIdle(previewModel)
	self:_startHeadLook(previewModel)
end

function AvatarViewportPreview:RenderUser(userId: number?, player: Player?)
	if typeof(userId) ~= "number" then
		self:Clear()
		return
	end

	local viewportFrame = self._viewportFrame
	if not viewportFrame then
		return
	end

	self._activePlayer = player

	if self._cachedUserId == userId and self._cachedPreviewModel then
		if self._renderedUserId == userId and self:_getRenderedPreviewModel() then
			if not self:_isPresentationActive() and self:_canPlayPresentation() then
				self:_stopPresentation()
				self:_startPresentation()
			end
			return
		end
		self:_renderModel(self._cachedPreviewModel, true)
		self._renderedUserId = userId
		return
	end
	if self._resolvingUserId == userId then
		return
	end

	self._renderToken += 1
	local renderToken = self._renderToken
	self._resolvingUserId = userId
	self._renderedUserId = nil
	self:_destroyCachedPreviewModel()
	self:_renderModel(self:_getRigTemplate(), false)

	task.spawn(function()
		local previewModel = self:_buildPreviewModel(userId, player, renderToken)
		if renderToken ~= self._renderToken then
			if previewModel and previewModel.Parent == nil then
				previewModel:Destroy()
			end
			return
		end

		self._resolvingUserId = nil
		if not previewModel then
			return
		end

		self:_destroyCachedPreviewModel()
		self._cachedUserId = userId
		self._cachedPreviewModel = previewModel
		self:_renderModel(previewModel, true)
		self._renderedUserId = userId
	end)
end

return AvatarViewportPreview
