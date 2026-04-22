type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		BROCCOLI_SPROUT_MODULE_ID = "Moves.BroccoliBro.BroccoliSprout",
	},
	Vfx = {
		BROCCOLI_BRO_VFX_FOLDER_NAME = "BroccoliBro",
		BROCCOLI_SPROUT_FLOOR_VFX_NAME = "Floor",
		BROCCOLI_SPROUT_TREE_VFX_NAME = "Broccoli",
		BROCCOLI_SPROUT_VFX_NAME = "BroccoliSprout",
	},
	Timing = {
		BROCCOLI_SPROUT_VFX_LIFETIME_SECONDS = 3,
	},
}

local BROCCOLI_BRO_VFX_FOLDER_NAME = Constants.Vfx.BROCCOLI_BRO_VFX_FOLDER_NAME
local BROCCOLI_SPROUT_FLOOR_VFX_NAME = Constants.Vfx.BROCCOLI_SPROUT_FLOOR_VFX_NAME
local BROCCOLI_SPROUT_MODULE_ID = Constants.ModuleIds.BROCCOLI_SPROUT_MODULE_ID
local BROCCOLI_SPROUT_TREE_VFX_NAME = Constants.Vfx.BROCCOLI_SPROUT_TREE_VFX_NAME
local BROCCOLI_SPROUT_VFX_LIFETIME_SECONDS = Constants.Timing.BROCCOLI_SPROUT_VFX_LIFETIME_SECONDS
local BROCCOLI_SPROUT_VFX_NAME = Constants.Vfx.BROCCOLI_SPROUT_VFX_NAME

local Handler = {}

function Handler:_clearBroccoliSproutWarnings(record: ActiveRecord)
	if record.broccoliSproutWarningHandles == nil then
		return
	end

	for _, warningHandle in pairs(record.broccoliSproutWarningHandles) do
		warningHandle:Destroy()
	end

	record.broccoliSproutWarningHandles = nil
end

function Handler:_tweenBroccoliSproutTree(
	record: ActiveRecord,
	treeModel: Model,
	startCFrame: CFrame,
	endCFrame: CFrame,
	riseDurationSeconds: number
)
	record.broccoliSproutTweens = record.broccoliSproutTweens or {}
	record.broccoliSproutTweenConnections = record.broccoliSproutTweenConnections or {}
	record.broccoliSproutTweenValues = record.broccoliSproutTweenValues or {}

	local cframeValue = Instance.new("CFrameValue")
	cframeValue.Name = "BroccoliSproutPivot"
	cframeValue.Value = startCFrame
	cframeValue.Parent = treeModel

	treeModel:PivotTo(startCFrame)

	local connection = cframeValue:GetPropertyChangedSignal("Value"):Connect(function()
		if treeModel.Parent ~= nil then
			treeModel:PivotTo(cframeValue.Value)
		end
	end)
	local tween = self.TweenService:Create(
		cframeValue,
		TweenInfo.new(riseDurationSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Value = endCFrame,
		}
	)

	table.insert(record.broccoliSproutTweens, tween)
	table.insert(record.broccoliSproutTweenConnections, connection)
	table.insert(record.broccoliSproutTweenValues, cframeValue)

	tween.Completed:Connect(function()
		if connection.Connected then
			connection:Disconnect()
		end
		if cframeValue.Parent ~= nil then
			cframeValue:Destroy()
		end
	end)
	tween:Play()
end

function Handler:_sproutBroccoliSprout(record: ActiveRecord, event: PresentationEvent)
	self:_clearBroccoliSproutWarnings(record)
	self:_shakeImpact()

	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.points) ~= "table" then
		self:_cleanupRecord(record)
		return
	end

	local floorSource = self:resolveBossVfxInstance(
		BROCCOLI_BRO_VFX_FOLDER_NAME,
		BROCCOLI_SPROUT_VFX_NAME,
		BROCCOLI_SPROUT_FLOOR_VFX_NAME
	)
	if floorSource == nil then
		self:warnWithPrefix("Broccoli Sprout floor VFX instance is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local treeSource = self:resolveBossVfxModel(
		BROCCOLI_BRO_VFX_FOLDER_NAME,
		BROCCOLI_SPROUT_VFX_NAME,
		BROCCOLI_SPROUT_TREE_VFX_NAME
	)
	if treeSource == nil then
		self:warnWithPrefix("Broccoli Sprout tree VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local castFolder = self:_ensureCastFolder(record)
	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	local riseDurationSeconds = math.max(0.05, tonumber(payload.riseDurationSeconds) or 0.45)

	for _, pointData in ipairs(payload.points) do
		if typeof(pointData) ~= "table" or typeof(pointData.floorCFrame) ~= "CFrame" then
			continue
		end

		local floorInstance = floorSource:Clone()
		if not self:pivotBroccoliSproutEffectInstance(floorInstance, pointData.floorCFrame, scaleMultiplier) then
			self:warnWithPrefix("Broccoli Sprout floor VFX instance cannot be pivoted.")
			floorInstance:Destroy()
			continue
		end
		floorInstance.Parent = self:_ensureVisualFolder()
		self:playAllSounds(floorInstance)
		self:emitEffectInstance(floorInstance, BROCCOLI_SPROUT_VFX_LIFETIME_SECONDS)
		self:destroyAfter(floorInstance, BROCCOLI_SPROUT_VFX_LIFETIME_SECONDS)

		local treeStartCFrame = pointData.treeStartCFrame
		local treeEndCFrame = pointData.treeEndCFrame
		if typeof(treeStartCFrame) ~= "CFrame" or typeof(treeEndCFrame) ~= "CFrame" then
			continue
		end

		local treeModel = treeSource:Clone()
		treeModel:ScaleTo(scaleMultiplier)
		self:prepareMovingEffectModel(treeModel)
		if self:resolveEffectModelPrimaryPart(treeModel) == nil then
			treeModel:Destroy()
			self:warnWithPrefix("Broccoli Sprout tree VFX model is missing a BasePart for tweening.")
			continue
		end

		treeModel.Parent = castFolder
		self:playAllSounds(treeModel)
		self:enableVfxDescendants(treeModel)
		self:emitVisuals(self:collectEmittableVisuals(treeModel))
		self:_tweenBroccoliSproutTree(record, treeModel, treeStartCFrame, treeEndCFrame, riseDurationSeconds)
	end
end

function Handler:_warnBroccoliSprout(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.points) ~= "table" then
		return
	end

	self:_clearBroccoliSproutWarnings(record)
	local castFolder = self:_ensureCastFolder(record)
	local warningSeconds = math.max(0.05, tonumber(payload.warningSeconds) or 1)
	record.broccoliSproutWarningHandles = {}

	for _, pointData in ipairs(payload.points) do
		if typeof(pointData) ~= "table" then
			continue
		end

		local floorCFrame = pointData.floorCFrame
		local footprintSize = pointData.footprintSize
		if typeof(floorCFrame) ~= "CFrame" or typeof(footprintSize) ~= "Vector3" then
			continue
		end

		local index = math.max(1, math.floor(tonumber(pointData.index) or (#record.broccoliSproutWarningHandles + 1)))
		record.broccoliSproutWarningHandles[index] = self.Indication.CreateCircle({
			parent = castFolder,
			cframe = floorCFrame,
			diameter = math.max(footprintSize.X, footprintSize.Z),
			duration = warningSeconds,
		})
	end
end

Handler.moduleIds = {
	BROCCOLI_SPROUT_MODULE_ID,
}
Handler.actions = {
	warn = Handler._warnBroccoliSprout,
	sprout = Handler._sproutBroccoliSprout,
}
Handler.requiresHandle = false

return Handler
