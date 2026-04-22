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
		AGRYNOTH_WAR_CALL_HEAD_LIFETIME_SECONDS = 3,
		AGRYNOTH_WAR_CALL_SPAWN_LIFETIME_SECONDS = 3,
		AGRYNOTH_WAR_CALL_START_LIFETIME_SECONDS = 3,
	},
}

local AGRYNOTH_VFX_FOLDER_NAME = Constants.Vfx.AGRYNOTH_VFX_FOLDER_NAME
local AGRYNOTH_WAR_CALL_HEAD_LIFETIME_SECONDS = Constants.Timing.AGRYNOTH_WAR_CALL_HEAD_LIFETIME_SECONDS
local AGRYNOTH_WAR_CALL_HEAD_VFX_NAME = Constants.Vfx.AGRYNOTH_WAR_CALL_HEAD_VFX_NAME
local AGRYNOTH_WAR_CALL_MODULE_ID = Constants.ModuleIds.AGRYNOTH_WAR_CALL_MODULE_ID
local AGRYNOTH_WAR_CALL_SPAWN_LIFETIME_SECONDS = Constants.Timing.AGRYNOTH_WAR_CALL_SPAWN_LIFETIME_SECONDS
local AGRYNOTH_WAR_CALL_SPAWN_VFX_NAME = Constants.Vfx.AGRYNOTH_WAR_CALL_SPAWN_VFX_NAME
local AGRYNOTH_WAR_CALL_START_LIFETIME_SECONDS = Constants.Timing.AGRYNOTH_WAR_CALL_START_LIFETIME_SECONDS
local AGRYNOTH_WAR_CALL_START_VFX_NAME = Constants.Vfx.AGRYNOTH_WAR_CALL_START_VFX_NAME
local AGRYNOTH_WAR_CALL_VFX_NAME = Constants.Vfx.AGRYNOTH_WAR_CALL_VFX_NAME

local Handler = {}

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

	local bossModel = event.bossModel
	local bossHead = self:resolveBossHeadPart(bossModel)
	local castFolder = self:_ensureCastFolder(record)
	local bossScale = math.max(0.1, tonumber(payload.bossScale) or tonumber(payload.scaleMultiplier) or 1)
	local minionScale = math.max(0.1, tonumber(payload.minionScale) or 1)

	local headSource = self:resolveBossVfxModel(
		AGRYNOTH_VFX_FOLDER_NAME,
		AGRYNOTH_WAR_CALL_VFX_NAME,
		AGRYNOTH_WAR_CALL_HEAD_VFX_NAME
	)
	if headSource and bossHead then
		local headModel = headSource:Clone()
		headModel:ScaleTo(bossScale)
		self:prepareAttachedEffectModel(headModel)
		headModel.Parent = castFolder
		self:scaleAttachedSounds(headModel, bossScale)
		if self:attachEffectModel(headModel, bossHead) then
			self:playAllSounds(headModel, bossScale)
			self:emitEffectInstance(headModel, AGRYNOTH_WAR_CALL_HEAD_LIFETIME_SECONDS)
			self:destroyVfxAfter(headModel, AGRYNOTH_WAR_CALL_HEAD_LIFETIME_SECONDS)
		else
			self:warnWithPrefix("Agrynoth War Call Head VFX model is missing BasePart configuration.")
			headModel:Destroy()
		end
	elseif headSource == nil then
		self:warnWithPrefix("Agrynoth War Call Head VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
	elseif bossHead == nil then
		self:warnWithPrefix("Agrynoth War Call presentation could not resolve the live boss Head.")
	end

	local spawnSource = self:resolveBossVfxInstance(
		AGRYNOTH_VFX_FOLDER_NAME,
		AGRYNOTH_WAR_CALL_VFX_NAME,
		AGRYNOTH_WAR_CALL_SPAWN_VFX_NAME
	)
	local startSource = self:resolveBossVfxModel(
		AGRYNOTH_VFX_FOLDER_NAME,
		AGRYNOTH_WAR_CALL_VFX_NAME,
		AGRYNOTH_WAR_CALL_START_VFX_NAME
	)
	if spawnSource == nil then
		self:warnWithPrefix("Agrynoth War Call Spawn VFX instance is missing from ReplicatedStorage.GameAssets.VFX.")
	end
	if startSource == nil then
		self:warnWithPrefix("Agrynoth War Call Start VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
	end

	local minionPayloads = if typeof(payload.minions) == "table" then payload.minions else {}
	for _, minionPayload in ipairs(minionPayloads) do
		if typeof(minionPayload) ~= "table" then
			continue
		end

		local minionModel = minionPayload.minionModel
		local spawnCFrame = minionPayload.spawnCFrame
		if spawnSource ~= nil and typeof(spawnCFrame) == "CFrame" then
			local spawnEffect = spawnSource:Clone()
			if self:_placeWarCallEffectInstance(spawnEffect, spawnCFrame, minionScale) then
				spawnEffect.Parent = castFolder
				self:playAllSounds(spawnEffect, minionScale)
				self:emitEffectInstance(spawnEffect, AGRYNOTH_WAR_CALL_SPAWN_LIFETIME_SECONDS)
			self:destroyVfxAfter(spawnEffect, AGRYNOTH_WAR_CALL_SPAWN_LIFETIME_SECONDS)
			else
				self:warnWithPrefix("Agrynoth War Call Spawn VFX instance cannot be pivoted.")
				spawnEffect:Destroy()
			end
		end

		if startSource ~= nil and typeof(minionModel) == "Instance" and minionModel:IsA("Model") then
			local minionRootPart = self:resolveBossRootPart(minionModel)
			if minionRootPart == nil then
				continue
			end

			local startModel = startSource:Clone()
			startModel:ScaleTo(minionScale)
			self:prepareAttachedEffectModel(startModel)
			startModel.Parent = castFolder
			self:scaleAttachedSounds(startModel, minionScale)
			if self:attachEffectModel(startModel, minionRootPart) then
				self:playAllSounds(startModel, minionScale)
				self:emitEffectInstance(startModel, AGRYNOTH_WAR_CALL_START_LIFETIME_SECONDS)
			self:destroyVfxAfter(startModel, AGRYNOTH_WAR_CALL_START_LIFETIME_SECONDS)
			else
				self:warnWithPrefix("Agrynoth War Call Start VFX model is missing BasePart configuration.")
				startModel:Destroy()
			end
		end
	end

	self:_shakeImpact()
end

Handler.moduleIds = {
	AGRYNOTH_WAR_CALL_MODULE_ID,
}
Handler.actions = {
	spawn = Handler._spawnAgrynothWarCall,
}
Handler.requiresHandle = false

return Handler
