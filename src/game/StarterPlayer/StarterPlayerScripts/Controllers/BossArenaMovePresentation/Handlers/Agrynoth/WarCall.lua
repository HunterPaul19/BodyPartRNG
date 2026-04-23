type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		AGRYNOTH_WAR_CALL_MODULE_ID = "Moves.Agrynoth.WarCall",
	},
	Vfx = {
		AGRYNOTH_VFX_FOLDER_NAME = "Agrynoth",
		AGRYNOTH_WAR_CALL_HEAD_VFX_NAME = "Head",
		AGRYNOTH_WAR_CALL_SPAWN_VFX_NAME = "Spawn",
		AGRYNOTH_WAR_CALL_START_VFX_NAME = "Start",
		AGRYNOTH_WAR_CALL_VFX_NAME = "WarCall",
	},
	Timing = {
		AGRYNOTH_WAR_CALL_HEAD_EMIT_DELAY_SECONDS = 63 / 60,
		AGRYNOTH_WAR_CALL_HEAD_LIFETIME_SECONDS = 3,
		AGRYNOTH_WAR_CALL_SPAWN_LIFETIME_SECONDS = 3,
		AGRYNOTH_WAR_CALL_START_LIFETIME_SECONDS = 3,
	},
}

local AGRYNOTH_VFX_FOLDER_NAME = Constants.Vfx.AGRYNOTH_VFX_FOLDER_NAME
local AGRYNOTH_WAR_CALL_HEAD_EMIT_DELAY_SECONDS = Constants.Timing.AGRYNOTH_WAR_CALL_HEAD_EMIT_DELAY_SECONDS
local AGRYNOTH_WAR_CALL_HEAD_LIFETIME_SECONDS = Constants.Timing.AGRYNOTH_WAR_CALL_HEAD_LIFETIME_SECONDS
local AGRYNOTH_WAR_CALL_HEAD_VFX_NAME = Constants.Vfx.AGRYNOTH_WAR_CALL_HEAD_VFX_NAME
local AGRYNOTH_WAR_CALL_MODULE_ID = Constants.ModuleIds.AGRYNOTH_WAR_CALL_MODULE_ID
local AGRYNOTH_WAR_CALL_SPAWN_LIFETIME_SECONDS = Constants.Timing.AGRYNOTH_WAR_CALL_SPAWN_LIFETIME_SECONDS
local AGRYNOTH_WAR_CALL_SPAWN_VFX_NAME = Constants.Vfx.AGRYNOTH_WAR_CALL_SPAWN_VFX_NAME
local AGRYNOTH_WAR_CALL_START_LIFETIME_SECONDS = Constants.Timing.AGRYNOTH_WAR_CALL_START_LIFETIME_SECONDS
local AGRYNOTH_WAR_CALL_START_VFX_NAME = Constants.Vfx.AGRYNOTH_WAR_CALL_START_VFX_NAME
local AGRYNOTH_WAR_CALL_VFX_NAME = Constants.Vfx.AGRYNOTH_WAR_CALL_VFX_NAME

local Handler = {}

function Handler:_startAgrynothWarCall(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local bossRootPart = self:resolveBossRootPart(bossModel)
	local bossHead = self:resolveBossHeadPart(bossModel)
	if bossRootPart == nil then
		self:warnWithPrefix("Agrynoth War Call presentation could not resolve the live boss RootPart.")
		self:_cleanupRecord(record)
		return
	end

	local startSource = self:resolveBossVfxModel(
		AGRYNOTH_VFX_FOLDER_NAME,
		AGRYNOTH_WAR_CALL_VFX_NAME,
		AGRYNOTH_WAR_CALL_START_VFX_NAME
	)
	local headSource = self:resolveBossVfxModel(
		AGRYNOTH_VFX_FOLDER_NAME,
		AGRYNOTH_WAR_CALL_VFX_NAME,
		AGRYNOTH_WAR_CALL_HEAD_VFX_NAME
	)
	if startSource == nil then
		self:warnWithPrefix("Agrynoth War Call Start VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
	end
	if headSource == nil then
		self:warnWithPrefix("Agrynoth War Call Head VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
	end
	if bossHead == nil then
		self:warnWithPrefix("Agrynoth War Call presentation could not resolve the live boss Head.")
	end

	local payload = event.payload
	local bossScale = math.max(0.1, tonumber(payload and payload.bossScale) or tonumber(payload and payload.scaleMultiplier) or 1)
	local castFolder = self:_ensureCastFolder(record)

	if startSource ~= nil then
		local startModel = startSource:Clone()
		startModel:ScaleTo(bossScale)
		self:prepareMovingEffectModel(startModel)
		startModel:PivotTo(bossRootPart.CFrame)
		startModel.Parent = castFolder
		record.warCallStartModel = startModel
		self:playTimedSounds(startModel, bossScale)
		self:emitEffectInstance(startModel, AGRYNOTH_WAR_CALL_START_LIFETIME_SECONDS)
	end

	if headSource ~= nil and bossHead ~= nil then
		local headModel = headSource:Clone()
		headModel:ScaleTo(bossScale)
		self:prepareAttachedEffectModel(headModel)
		headModel.Parent = castFolder
		record.warCallHeadModel = headModel
		self:scaleAttachedSounds(headModel, bossScale)
		if self:attachEffectModel(headModel, bossHead) then
			self:playTimedSounds(headModel, bossScale)
			self:emitEffectInstanceAfter(
				headModel,
				AGRYNOTH_WAR_CALL_HEAD_LIFETIME_SECONDS,
				AGRYNOTH_WAR_CALL_HEAD_EMIT_DELAY_SECONDS
			)
		else
			self:warnWithPrefix("Agrynoth War Call Head VFX model is missing BasePart configuration.")
			headModel:Destroy()
			record.warCallHeadModel = nil
		end
	end
end

function Handler:_placeWarCallEffectInstance(
	effectInstance: Instance,
	cframe: CFrame,
	scaleMultiplier: number
): boolean
	if effectInstance:IsA("Model") then
		effectInstance:ScaleTo(scaleMultiplier)
		self:prepareMovingEffectModel(effectInstance)
		effectInstance:PivotTo(cframe)
		return true
	elseif effectInstance:IsA("BasePart") then
		effectInstance.Size *= scaleMultiplier
		self:prepareMovingEffectPart(effectInstance)
		effectInstance.CFrame = cframe
		return true
	elseif effectInstance:IsA("PVInstance") then
		effectInstance:PivotTo(cframe)
		return true
	end

	return false
end

function Handler:_spawnAgrynothWarCall(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" then
		return
	end

	local castFolder = self:_ensureCastFolder(record)
	local minionScale = math.max(0.1, tonumber(payload.minionScale) or 1)

	local spawnSource = self:resolveBossVfxInstance(
		AGRYNOTH_VFX_FOLDER_NAME,
		AGRYNOTH_WAR_CALL_VFX_NAME,
		AGRYNOTH_WAR_CALL_SPAWN_VFX_NAME
	)
	if spawnSource == nil then
		self:warnWithPrefix("Agrynoth War Call Spawn VFX instance is missing from ReplicatedStorage.GameAssets.VFX.")
	end

	local minionPayloads = if typeof(payload.minions) == "table" then payload.minions else {}
	for _, minionPayload in ipairs(minionPayloads) do
		if typeof(minionPayload) ~= "table" then
			continue
		end

		local spawnCFrame = minionPayload.spawnCFrame
		if spawnSource ~= nil and typeof(spawnCFrame) == "CFrame" then
			local spawnEffect = spawnSource:Clone()
			if self:_placeWarCallEffectInstance(spawnEffect, spawnCFrame, minionScale) then
				spawnEffect.Parent = castFolder
				self:playTimedSounds(spawnEffect, minionScale)
				self:emitEffectInstance(spawnEffect, AGRYNOTH_WAR_CALL_SPAWN_LIFETIME_SECONDS)
			else
				self:warnWithPrefix("Agrynoth War Call Spawn VFX instance cannot be pivoted.")
				spawnEffect:Destroy()
			end
		end
	end

	self:_shakeImpact()
end

Handler.moduleIds = {
	AGRYNOTH_WAR_CALL_MODULE_ID,
}
Handler.start = Handler._startAgrynothWarCall
Handler.actions = {
	spawn = Handler._spawnAgrynothWarCall,
}
Handler.requiresHandle = false

return Handler
