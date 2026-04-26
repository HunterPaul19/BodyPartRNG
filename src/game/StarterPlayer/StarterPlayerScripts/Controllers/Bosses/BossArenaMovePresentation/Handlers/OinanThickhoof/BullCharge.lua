type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		OINAN_THICKHOOF_CHARGE_MODULE_ID = "Moves.OinanThickhoof.BullCharge",
	},
	Vfx = {
		OINAN_THICKHOOF_CHARGE_ROOT_VFX_NAME = "RootPart",
		OINAN_THICKHOOF_CHARGE_VFX_NAME = "BullCharge",
		OINAN_THICKHOOF_VFX_FOLDER_NAME = "OinanThickhoof",
	},
	SoundTimingAttributes = {
		"Delay",
		"Start",
	},
}

local OINAN_THICKHOOF_CHARGE_MODULE_ID = Constants.ModuleIds.OINAN_THICKHOOF_CHARGE_MODULE_ID
local OINAN_THICKHOOF_CHARGE_ROOT_VFX_NAME = Constants.Vfx.OINAN_THICKHOOF_CHARGE_ROOT_VFX_NAME
local OINAN_THICKHOOF_CHARGE_VFX_NAME = Constants.Vfx.OINAN_THICKHOOF_CHARGE_VFX_NAME
local OINAN_THICKHOOF_VFX_FOLDER_NAME = Constants.Vfx.OINAN_THICKHOOF_VFX_FOLDER_NAME
local SOUND_TIMING_ATTRIBUTES = Constants.SoundTimingAttributes

local Handler = {}

local function clearChargeSoundDelays(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if not descendant:IsA("Sound") then
			continue
		end

		for _, attributeName in ipairs(SOUND_TIMING_ATTRIBUTES) do
			descendant:SetAttribute(attributeName, nil)
		end
	end
end

function Handler:_chargeOinanCharge(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local bossRootPart = self:resolveBossRootPart(bossModel)
	if bossRootPart == nil then
		self:warnWithPrefix("Bull Charge presentation could not resolve the live boss RootPart.")
		self:_cleanupRecord(record)
		return
	end

	local effectSource = self:resolveBossVfxInstance(
		OINAN_THICKHOOF_VFX_FOLDER_NAME,
		OINAN_THICKHOOF_CHARGE_VFX_NAME,
		OINAN_THICKHOOF_CHARGE_ROOT_VFX_NAME
	)
	if effectSource == nil then
		self:warnWithPrefix("Bull Charge RootPart VFX instance is missing from ReplicatedStorage.GameAssets.Effects.Bosses.")
		self:_cleanupRecord(record)
		return
	end

	local payload = event.payload
	local scaleMultiplier = math.max(0.1, tonumber(payload and payload.scaleMultiplier) or 1)
	local durationSeconds = math.max(0.1, tonumber(payload and payload.durationSeconds) or 2)
	local effectInstance = effectSource:Clone()
	if not effectInstance:IsA("Model") then
		self:warnWithPrefix("Bull Charge RootPart VFX instance must be a Model to attach to the boss RootPart.")
		effectInstance:Destroy()
		self:_cleanupRecord(record)
		return
	end

	local castFolder = self:_ensureCastFolder(record)
	effectInstance:ScaleTo(scaleMultiplier)
	self:prepareAttachedEffectModel(effectInstance)
	effectInstance.Parent = castFolder
	record.rootModel = effectInstance

	if not self:attachEffectModel(effectInstance, bossRootPart) then
		self:warnWithPrefix("Bull Charge RootPart VFX model is missing BasePart configuration.")
		self:_cleanupRecord(record)
		return
	end

	clearChargeSoundDelays(effectInstance)
	self:playAllSounds(effectInstance, scaleMultiplier)
	self:emitEffectInstance(effectInstance, durationSeconds + 0.5)
end

Handler.moduleIds = {
	OINAN_THICKHOOF_CHARGE_MODULE_ID,
}
Handler.actions = {
	charge = Handler._chargeOinanCharge,
}
Handler.requiredParentFields = {
	"rootModel",
}
Handler.requiresHandle = false

return Handler
