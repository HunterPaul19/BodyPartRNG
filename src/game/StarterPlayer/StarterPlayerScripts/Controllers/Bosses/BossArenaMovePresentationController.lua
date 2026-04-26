local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Context = require(script.Parent.BossArenaMovePresentation.Context)
local Registry = require(script.Parent.BossArenaMovePresentation.Registry)

type PresentationEvent = {
	castId: string,
	bossModel: Model?,
	bossId: string?,
	moveId: string?,
	moduleId: string?,
	action: string?,
	payload: { [string]: any }?,
	serverTime: number?,
	source: string?,
}

type ActiveRecord = {
	castId: string,
	moduleId: string,
	bossModel: Model?,
	castFolder: Folder?,
	handleModel: Model?,
	upperTorsoModel: Model?,
	rootModel: Model?,
	slashModel: Model?,
	slashMotion: any?,
	leftFootModel: Model?,
	leftHandModel: Model?,
	cannonModel: Model?,
	cannonMiddle: BasePart?,
	cannonMuzzleAttachment: Attachment?,
	squidCallAimData: any?,
	projectileModel: Model?,
	projectileMotion: any?,
	rightHandModel: Model?,
	shipModel: Model?,
	shipMotion: any?,
	waveModel: Model?,
	waveMotion: any?,
	waterBombChargeData: any?,
	bubbleBlastProjectileModels: { [number]: Model }?,
	bubbleBlastProjectileMotions: { [number]: any }?,
	missileBarrageProjectileModels: { [number]: Model }?,
	missileBarrageProjectileMotions: { [number]: any }?,
	acidBreathHeadModel: Model?,
	eatChickenBoneModels: { [number]: Model }?,
	eatChickenBoneMotions: { [number]: any }?,
	broccoliSproutWarningHandles: { [number]: any }?,
	broccoliSproutTweens: { Tween }?,
	broccoliSproutTweenConnections: { RBXScriptConnection }?,
	broccoliSproutTweenValues: { CFrameValue }?,
	rainbowBlastBeamModel: Model?,
	rainbowBlastEndModel: Model?,
	rainbowBlastTargetModel: Model?,
	rainbowBlastPlayerGlintModel: Model?,
	rainbowBlastBeamMotion: any?,
	rainbowBlastTorsoAim: any?,
	stopRequested: boolean?,
}

local BossArenaMovePresentationController = {
	_started = false,
	_remote = nil :: RemoteEvent?,
	_remoteConnection = nil :: RBXScriptConnection?,
	_cleanupConnection = nil :: RBXScriptConnection?,
	_recordsByCastId = {} :: { [string]: ActiveRecord },
	_context = nil :: any,
	_handlersByModuleId = nil :: { [string]: any }?,
	_missingHandlerWarnings = {} :: { [string]: boolean },
}

function BossArenaMovePresentationController:_getContext()
	if self._context == nil then
		self._context = Context.new(self)
	end
	return self._context
end

function BossArenaMovePresentationController:_getHandlersByModuleId()
	if self._handlersByModuleId == nil then
		self._handlersByModuleId = Registry.new(self:_getContext())
	end
	return self._handlersByModuleId
end

function BossArenaMovePresentationController:_createRecord(event: PresentationEvent): ActiveRecord
	return {
		castId = event.castId,
		moduleId = event.moduleId :: string,
		bossModel = event.bossModel,
		castFolder = nil,
		handleModel = nil,
		upperTorsoModel = nil,
		rootModel = nil,
		slashModel = nil,
		slashMotion = nil,
		leftFootModel = nil,
		leftHandModel = nil,
		cannonModel = nil,
		cannonMiddle = nil,
		cannonMuzzleAttachment = nil,
		squidCallAimData = nil,
		projectileModel = nil,
		projectileMotion = nil,
		rightHandModel = nil,
		shipModel = nil,
		shipMotion = nil,
		waveModel = nil,
		waveMotion = nil,
		waterBombChargeData = nil,
		bubbleBlastProjectileModels = nil,
		bubbleBlastProjectileMotions = nil,
		missileBarrageProjectileModels = nil,
		missileBarrageProjectileMotions = nil,
		acidBreathHeadModel = nil,
		eatChickenBoneModels = nil,
		eatChickenBoneMotions = nil,
		broccoliSproutWarningHandles = nil,
		broccoliSproutTweens = nil,
		broccoliSproutTweenConnections = nil,
		broccoliSproutTweenValues = nil,
		rainbowBlastBeamModel = nil,
		rainbowBlastEndModel = nil,
		rainbowBlastTargetModel = nil,
		rainbowBlastPlayerGlintModel = nil,
		rainbowBlastBeamMotion = nil,
		rainbowBlastTorsoAim = nil,
		stopRequested = false,
	}
end

function BossArenaMovePresentationController:_cleanupStaleRecords()
	local ctx = self:_getContext()
	for _, record in pairs(self._recordsByCastId) do
		local handler = self:_getHandlersByModuleId()[record.moduleId]
		if record.bossModel == nil or record.bossModel.Parent == nil then
			ctx:_cleanupRecord(record)
		elseif ctx:resolveBossRootPart(record.bossModel) == nil then
			ctx:_cleanupRecord(record)
		elseif handler and handler.requiresHandle ~= false and ctx:resolveBossHandlePart(record.bossModel) == nil then
			ctx:_cleanupRecord(record)
		elseif handler and handler.requiredParentFields then
			for _, fieldName in ipairs(handler.requiredParentFields) do
				local instance = record[fieldName]
				if instance and instance.Parent == nil then
					ctx:_cleanupRecord(record)
					break
				end
			end
		end
	end
end

function BossArenaMovePresentationController:_updateActiveRecords()
	self:_cleanupStaleRecords()

	local nowServerTime = Workspace:GetServerTimeNow()
	local handlersByModuleId = self:_getHandlersByModuleId()
	for _, record in pairs(self._recordsByCastId) do
		local handler = handlersByModuleId[record.moduleId]
		if handler and handler.update then
			handler:update(record, nowServerTime)
		end
	end
end

function BossArenaMovePresentationController:_handleEvent(payload: any)
	if typeof(payload) ~= "table" then
		return
	end

	local event = payload :: PresentationEvent
	local castId = event.castId
	local moduleId = event.moduleId
	local action = event.action
	if type(castId) ~= "string" or castId == "" or type(moduleId) ~= "string" or type(action) ~= "string" then
		return
	end

	local handler = self:_getHandlersByModuleId()[moduleId]
	if handler == nil then
		if self._missingHandlerWarnings[moduleId] ~= true then
			self._missingHandlerWarnings[moduleId] = true
			self:_getContext():warnWithPrefix(string.format(
				"No boss move presentation handler is registered for moduleId '%s' from %s.",
				moduleId,
				if type(event.source) == "string" and event.source ~= "" then event.source else "boss arena"
			))
		end
		return
	end

	local ctx = self:_getContext()
	if action == "start" then
		ctx:_cleanupRecord(self._recordsByCastId[castId])

		local record = self:_createRecord(event)
		self._recordsByCastId[castId] = record
		if handler.start then
			handler:start(record, event)
		end
		return
	end

	local record = self._recordsByCastId[castId]
	if record == nil then
		local actionsWithoutRecord = handler.actionsWithoutRecord
		local actionWithoutRecord = actionsWithoutRecord and actionsWithoutRecord[action]
		if actionWithoutRecord then
			actionWithoutRecord(handler, event)
		end
		return
	end

	local actions = handler.actions
	local actionHandler = actions and actions[action]
	if actionHandler then
		actionHandler(handler, record, event)
	elseif action == "stop" then
		ctx:_cleanupRecord(record)
	end
end

function BossArenaMovePresentationController:OnStart()
	if self._started then
		return
	end
	self._started = true

	local ctx = self:_getContext()
	if not ctx:isEnabledForPlace() then
		return
	end

	local remote = ctx:_ensureRemote()
	if remote == nil then
		return
	end

	ctx:_ensureCameraShaker()
	ctx:initializeEmitModule()
	self._remoteConnection = remote.OnClientEvent:Connect(function(payload)
		self:_handleEvent(payload)
	end)
	self._cleanupConnection = RunService.Heartbeat:Connect(function()
		self:_updateActiveRecords()
	end)
end

return BossArenaMovePresentationController
