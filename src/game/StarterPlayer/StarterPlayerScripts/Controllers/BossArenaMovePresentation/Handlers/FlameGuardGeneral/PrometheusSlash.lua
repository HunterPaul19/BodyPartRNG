type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		PROMETHEUS_SLASH_MODULE_ID = "Moves.FlameGuardGeneral.PrometheusSlash",
	},
	Vfx = {
		PROMETHEUS_SLASH_VFX_NAME = "PrometheusSlash",
	},
}

local PROMETHEUS_SLASH_MODULE_ID = Constants.ModuleIds.PROMETHEUS_SLASH_MODULE_ID
local PROMETHEUS_SLASH_VFX_NAME = Constants.Vfx.PROMETHEUS_SLASH_VFX_NAME

local Handler = {}

function Handler:_updatePrometheusSlashMotion(record: ActiveRecord, nowServerTime: number)
	local slashModel = record.slashModel
	local slashMotion = record.slashMotion
	if slashModel == nil or slashMotion == nil or slashModel.Parent == nil then
		return
	end

	local elapsed = math.max(0, nowServerTime - slashMotion.startedAtServerTime)
	local alpha = math.clamp(elapsed / math.max(0.001, slashMotion.travelDuration), 0, 1)
	local center = slashMotion.startPosition + (slashMotion.direction * (slashMotion.travelDistance * alpha))
	slashModel:PivotTo(CFrame.lookAt(center, center + slashMotion.direction) * CFrame.Angles(0, slashMotion.yRotation, 0))

	if alpha >= 1 and record.stopRequested then
		self:_cleanupRecord(record)
	end
end

function Handler:_startPrometheusSlash(record: ActiveRecord, event: PresentationEvent)
	self:_prepareAttachedCastModels(record, event, "Prometheus Slash", PROMETHEUS_SLASH_VFX_NAME, {
		enableParticles = true,
		scaleRootSounds = true,
		playAllSounds = true,
	})
end

function Handler:_impactPrometheusSlash(record: ActiveRecord, event: PresentationEvent)
	local castFolder = record.castFolder
	if castFolder == nil or castFolder.Parent == nil then
		return
	end

	local payload = event.payload
	if typeof(payload) ~= "table" then
		return
	end

	local startPosition = payload.startPosition
	local direction = payload.direction
	local travelDistance = tonumber(payload.travelDistance)
	local travelDuration = tonumber(payload.travelDuration)
	local yRotation = tonumber(payload.yRotation)
	local slashScale = tonumber(payload.slashScale) or 12.5
	if typeof(startPosition) ~= "Vector3"
		or typeof(direction) ~= "Vector3"
		or travelDistance == nil
		or travelDuration == nil
		or yRotation == nil
		or direction.Magnitude <= 0.001 then
		return
	end

	local slashSource = self:resolveVfxModel(PROMETHEUS_SLASH_VFX_NAME, "Slash")
	if slashSource == nil then
		self:warnWithPrefix("Prometheus Slash slash VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		return
	end

	local slashModel = slashSource:Clone()
	slashModel:ScaleTo(slashScale)
	self:prepareMovingEffectModel(slashModel)
	self:enableParticleEmitters(slashModel)

	if self:resolveEffectModelPrimaryPart(slashModel) == nil then
		self:warnWithPrefix("Prometheus Slash slash VFX model is missing a BasePart for motion.")
		return
	end

	record.slashModel = slashModel
	record.slashMotion = {
		startPosition = startPosition,
		direction = direction.Unit,
		travelDistance = travelDistance,
		travelDuration = travelDuration,
		startedAtServerTime = if typeof(event.serverTime) == "number" then event.serverTime else self.Workspace:GetServerTimeNow(),
		yRotation = yRotation,
	}

	slashModel.Parent = castFolder
	self:playAllSounds(slashModel)
	self:emitVisuals(self:collectEmittableVisuals(slashModel))
	self:_updatePrometheusSlashMotion(record, self.Workspace:GetServerTimeNow())
end

Handler.moduleIds = {
	PROMETHEUS_SLASH_MODULE_ID,
}
Handler.start = Handler._startPrometheusSlash
Handler.update = Handler._updatePrometheusSlashMotion
Handler.actions = {
	impact = Handler._impactPrometheusSlash,
	stop = function(self, record)
		if record.slashModel and record.slashMotion and record.slashModel.Parent then
			record.stopRequested = true
			self:_removeAttachedCastModels(record)
			self:_updatePrometheusSlashMotion(record, self.Workspace:GetServerTimeNow())
			return
		end
		self:_cleanupRecord(record)
	end,
}
Handler.requiredParentFields = {
	"handleModel",
	"rootModel",
	"slashModel",
}

return Handler
