type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		CAPTAIN_SQUID_HOOK_MODULE_ID = "Moves.CaptainSquid.Hook",
	},
	Vfx = {
		CAPTAIN_SQUID_HOOK_EXPLOSION_FLOOR_ATTACHMENT_NAME = "Floor",
		CAPTAIN_SQUID_HOOK_EXPLOSION_MODEL_NAME = "ThrowExplosion",
		CAPTAIN_SQUID_HOOK_IMPACT_EXPLOSION_SCALE_MULTIPLIER = 2,
		CAPTAIN_SQUID_HOOK_ROOT_PART_SOUNDS_FOLDER_NAME = "RootPartSounds",
		CAPTAIN_SQUID_HOOK_START_SOUNDS_FOLDER_NAME = "GrabStartSounds",
		CAPTAIN_SQUID_HOOK_VFX_NAME = "Hook",
		CAPTAIN_SQUID_VFX_FOLDER_NAME = "CaptainSquid",
	},
	Timing = {
		CAPTAIN_SQUID_HOOK_EXPLOSION_LIFETIME_SECONDS = 3,
	},
}

local CAPTAIN_SQUID_HOOK_EXPLOSION_FLOOR_ATTACHMENT_NAME = Constants.Vfx.CAPTAIN_SQUID_HOOK_EXPLOSION_FLOOR_ATTACHMENT_NAME
local CAPTAIN_SQUID_HOOK_EXPLOSION_LIFETIME_SECONDS = Constants.Timing.CAPTAIN_SQUID_HOOK_EXPLOSION_LIFETIME_SECONDS
local CAPTAIN_SQUID_HOOK_EXPLOSION_MODEL_NAME = Constants.Vfx.CAPTAIN_SQUID_HOOK_EXPLOSION_MODEL_NAME
local CAPTAIN_SQUID_HOOK_IMPACT_EXPLOSION_SCALE_MULTIPLIER = Constants.Vfx.CAPTAIN_SQUID_HOOK_IMPACT_EXPLOSION_SCALE_MULTIPLIER
local CAPTAIN_SQUID_HOOK_MODULE_ID = Constants.ModuleIds.CAPTAIN_SQUID_HOOK_MODULE_ID
local CAPTAIN_SQUID_HOOK_ROOT_PART_SOUNDS_FOLDER_NAME = Constants.Vfx.CAPTAIN_SQUID_HOOK_ROOT_PART_SOUNDS_FOLDER_NAME
local CAPTAIN_SQUID_HOOK_START_SOUNDS_FOLDER_NAME = Constants.Vfx.CAPTAIN_SQUID_HOOK_START_SOUNDS_FOLDER_NAME
local CAPTAIN_SQUID_HOOK_VFX_NAME = Constants.Vfx.CAPTAIN_SQUID_HOOK_VFX_NAME
local CAPTAIN_SQUID_VFX_FOLDER_NAME = Constants.Vfx.CAPTAIN_SQUID_VFX_FOLDER_NAME

local Handler = {}

function Handler:_pivotCaptainSquidHookExplosion(effectInstance: Instance, floorCFrame: CFrame, scaleMultiplier: number): boolean
	local floorAttachment = self:resolveNamedAttachment(effectInstance, CAPTAIN_SQUID_HOOK_EXPLOSION_FLOOR_ATTACHMENT_NAME)
	if floorAttachment == nil then
		return false
	end

	if effectInstance:IsA("Model") then
		effectInstance:ScaleTo(scaleMultiplier)
		self:prepareMovingEffectModel(effectInstance)
		self:pivotModelAttachmentToCFrame(effectInstance, floorAttachment, floorCFrame)
		return true
	end
	if effectInstance:IsA("BasePart") then
		effectInstance.Size *= scaleMultiplier
		self:prepareMovingEffectPart(effectInstance)
		effectInstance.CFrame = floorCFrame * floorAttachment.CFrame:Inverse()
		return true
	end

	return false
end

function Handler:_startCaptainSquidHook(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	local bossSoundAnchor = self:resolveBossLeftHandPart(bossModel) or self:resolveBossRootPart(bossModel)
	local soundsSource = self:resolveBossVfxInstance(
		CAPTAIN_SQUID_VFX_FOLDER_NAME,
		CAPTAIN_SQUID_HOOK_VFX_NAME,
		CAPTAIN_SQUID_HOOK_START_SOUNDS_FOLDER_NAME
	)
	if soundsSource == nil then
		self:warnWithPrefix("Captain Squid Hook start sounds are missing from ReplicatedStorage.GameAssets.VFX.")
		return
	end

	local scaleMultiplier = math.max(0.1, tonumber(event.payload and event.payload.scaleMultiplier) or 1)
	if bossSoundAnchor ~= nil then
		self:playDelayedSoundClones(soundsSource, self:_ensureCastFolder(record), scaleMultiplier, bossSoundAnchor)
	end
end

function Handler:_impactCaptainSquidHook(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.floorCFrame) ~= "CFrame" then
		self:_cleanupRecord(record)
		return
	end

	local explosionSource = self:resolveBossVfxInstance(
		CAPTAIN_SQUID_VFX_FOLDER_NAME,
		CAPTAIN_SQUID_HOOK_VFX_NAME,
		CAPTAIN_SQUID_HOOK_EXPLOSION_MODEL_NAME
	)
	if explosionSource == nil then
		self:warnWithPrefix("Captain Squid Hook ThrowExplosion VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	local impactScaleMultiplier = math.max(0.1, CAPTAIN_SQUID_HOOK_IMPACT_EXPLOSION_SCALE_MULTIPLIER)
	local rootPartSoundsSource = self:resolveBossVfxInstance(
		CAPTAIN_SQUID_VFX_FOLDER_NAME,
		CAPTAIN_SQUID_HOOK_VFX_NAME,
		CAPTAIN_SQUID_HOOK_ROOT_PART_SOUNDS_FOLDER_NAME
	)
	if rootPartSoundsSource == nil then
		self:warnWithPrefix("Captain Squid Hook RootPartSounds are missing from ReplicatedStorage.GameAssets.VFX.")
	else
		self:playDelayedSoundClones(rootPartSoundsSource, self:_ensureCastFolder(record), scaleMultiplier, payload.floorCFrame)
	end

	local explosionModel = explosionSource:Clone()
	if not self:_pivotCaptainSquidHookExplosion(explosionModel, payload.floorCFrame, impactScaleMultiplier) then
		self:warnWithPrefix("Captain Squid Hook ThrowExplosion VFX model is missing a Floor attachment.")
		explosionModel:Destroy()
		self:_cleanupRecord(record)
		return
	end

	explosionModel.Parent = self:_ensureVisualFolder()

	self:playAllSounds(explosionModel, impactScaleMultiplier)
	self:emitEffectInstance(explosionModel, CAPTAIN_SQUID_HOOK_EXPLOSION_LIFETIME_SECONDS)

	local localPlayer = self.Players.LocalPlayer
	local targetUserId = math.floor(tonumber(payload.targetUserId) or 0)
	if localPlayer ~= nil and targetUserId ~= 0 and targetUserId == localPlayer.UserId then
		self:_shakeImpact()
	end

	self:_cleanupRecord(record)
end

Handler.moduleIds = {
	CAPTAIN_SQUID_HOOK_MODULE_ID,
}
Handler.start = Handler._startCaptainSquidHook
Handler.actions = {
	impact = Handler._impactCaptainSquidHook,
}
Handler.requiresHandle = false

return Handler
