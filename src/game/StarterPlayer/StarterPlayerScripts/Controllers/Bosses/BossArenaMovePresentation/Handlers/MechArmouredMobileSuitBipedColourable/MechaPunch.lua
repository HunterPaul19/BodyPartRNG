type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		DESTROYER_3000_MECHA_PUNCH_MODULE_ID = "Moves.Destroyer3000.MechaPunch",
		MECHA_PUNCH_MODULE_ID = "Moves.MechArmouredMobileSuitBipedColourable.MechaPunch",
	},
	Vfx = {
		DESTROYER_3000_VFX_FOLDER_NAME = "Destroyer3000",
		MECHA_PUNCH_EXPLOSION_VFX_NAME = "Explosion",
		MECHA_PUNCH_RIGHT_HAND_VFX_NAME = "RightHand",
		MECHA_PUNCH_ROOT_PART_VFX_NAME = "RootPart",
		MECHA_PUNCH_VFX_NAME = "MechaPunch",
	},
	Timing = {
		MECHA_PUNCH_EXPLOSION_VFX_LIFETIME_SECONDS = 3,
	},
}

local DESTROYER_3000_MECHA_PUNCH_MODULE_ID = Constants.ModuleIds.DESTROYER_3000_MECHA_PUNCH_MODULE_ID
local DESTROYER_3000_VFX_FOLDER_NAME = Constants.Vfx.DESTROYER_3000_VFX_FOLDER_NAME
local MECHA_PUNCH_EXPLOSION_VFX_LIFETIME_SECONDS = Constants.Timing.MECHA_PUNCH_EXPLOSION_VFX_LIFETIME_SECONDS
local MECHA_PUNCH_EXPLOSION_VFX_NAME = Constants.Vfx.MECHA_PUNCH_EXPLOSION_VFX_NAME
local MECHA_PUNCH_MODULE_ID = Constants.ModuleIds.MECHA_PUNCH_MODULE_ID
local MECHA_PUNCH_RIGHT_HAND_VFX_NAME = Constants.Vfx.MECHA_PUNCH_RIGHT_HAND_VFX_NAME
local MECHA_PUNCH_ROOT_PART_VFX_NAME = Constants.Vfx.MECHA_PUNCH_ROOT_PART_VFX_NAME
local MECHA_PUNCH_VFX_NAME = Constants.Vfx.MECHA_PUNCH_VFX_NAME
local RIGHT_HAND_PART_NAME = "Right Hand"

local Handler = {}

local function resolveVisibleEffectPart(effectModel: Model, preferredName: string?): BasePart?
	if preferredName ~= nil then
		local preferred = effectModel:FindFirstChild(preferredName, true)
		if preferred and preferred:IsA("BasePart") and preferred ~= effectModel.PrimaryPart then
			return preferred
		end
	end

	for _, descendant in ipairs(effectModel:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= effectModel.PrimaryPart then
			return descendant
		end
	end

	return nil
end

local function alignVisibleEffectPart(effectModel: Model, targetCFrame: CFrame, preferredName: string?): boolean
	local visiblePart = resolveVisibleEffectPart(effectModel, preferredName)
	if visiblePart == nil then
		return false
	end

	local visiblePartToPivot = visiblePart.CFrame:ToObjectSpace(effectModel:GetPivot())
	effectModel:PivotTo(targetCFrame * visiblePartToPivot)
	return true
end

function Handler:_startMechaPunch(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local bossRootPart = self:resolveBossRootPart(bossModel)
	local bossRightHand = self:resolveBossRightHandPart(bossModel)
	if bossRootPart == nil or bossRightHand == nil then
		self:warnWithPrefix("Mecha Punch presentation could not resolve the live boss RootPart/RightHand.")
		self:_cleanupRecord(record)
		return
	end

	local rootPartSource = self:resolveBossVfxModel(
		DESTROYER_3000_VFX_FOLDER_NAME,
		MECHA_PUNCH_VFX_NAME,
		MECHA_PUNCH_ROOT_PART_VFX_NAME
	)
	local rightHandSource = self:resolveBossVfxModel(
		DESTROYER_3000_VFX_FOLDER_NAME,
		MECHA_PUNCH_VFX_NAME,
		MECHA_PUNCH_RIGHT_HAND_VFX_NAME
	)
	if rootPartSource == nil or rightHandSource == nil then
		self:warnWithPrefix("Mecha Punch RootPart/RightHand VFX models are missing from ReplicatedStorage.GameAssets.Effects.Bosses.")
		self:_cleanupRecord(record)
		return
	end

	local payload = event.payload
	local scaleMultiplier = math.max(0.1, tonumber(payload and payload.scaleMultiplier) or 1)
	local castFolder = self:_ensureCastFolder(record)
	local rootPartModel = rootPartSource:Clone()
	local rightHandModel = rightHandSource:Clone()
	rootPartModel:ScaleTo(scaleMultiplier)
	rightHandModel:ScaleTo(scaleMultiplier)
	self:prepareAttachedEffectModel(rootPartModel)
	self:prepareAttachedEffectModel(rightHandModel)
	self:scaleAttachedSounds(rootPartModel, scaleMultiplier)
	self:scaleAttachedSounds(rightHandModel, scaleMultiplier)

	rootPartModel.Parent = castFolder
	rightHandModel.Parent = castFolder
	record.rootModel = rootPartModel
	record.rightHandModel = rightHandModel

	if not self:attachEffectModel(rootPartModel, bossRootPart) then
		self:warnWithPrefix("Mecha Punch attached VFX models are missing BasePart configuration.")
		self:_cleanupRecord(record)
		return
	end

	if not alignVisibleEffectPart(rightHandModel, bossRightHand.CFrame, RIGHT_HAND_PART_NAME) then
		self:warnWithPrefix("Mecha Punch RightHand VFX model is missing the visible hand part configuration.")
		self:_cleanupRecord(record)
		return
	end

	local rightHandPrimaryPart = self:resolveEffectModelPrimaryPart(rightHandModel)
	if rightHandPrimaryPart == nil then
		self:warnWithPrefix("Mecha Punch attached VFX models are missing BasePart configuration.")
		self:_cleanupRecord(record)
		return
	end
	self:createWeld(rightHandPrimaryPart, bossRightHand)

	self:playTimedSounds(rootPartModel, scaleMultiplier)
	self:playTimedSounds(rightHandModel, scaleMultiplier)
	self:emitVisuals(rootPartModel)
	self:emitVisuals(rightHandModel)
end

function Handler:_impactMechaPunch(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.impactCFrame) ~= "CFrame" then
		return
	end

	local explosionSource = self:resolveBossVfxModel(
		DESTROYER_3000_VFX_FOLDER_NAME,
		MECHA_PUNCH_VFX_NAME,
		MECHA_PUNCH_EXPLOSION_VFX_NAME
	)
	if explosionSource == nil then
		self:warnWithPrefix("Mecha Punch Explosion VFX model is missing from ReplicatedStorage.GameAssets.Effects.Bosses.")
		return
	end

	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	local explosionInstance = explosionSource:Clone()
	explosionInstance:ScaleTo(scaleMultiplier)
	self:prepareMovingEffectModel(explosionInstance)
	self:scaleAttachedSounds(explosionInstance, scaleMultiplier)
	explosionInstance.Parent = self:_ensureVisualFolder()

	if not alignVisibleEffectPart(explosionInstance, payload.impactCFrame, MECHA_PUNCH_EXPLOSION_VFX_NAME) then
		self:warnWithPrefix("Mecha Punch Explosion VFX model is missing the visible explosion part configuration.")
		explosionInstance:Destroy()
		return
	end

	self:emitEffectInstance(explosionInstance, MECHA_PUNCH_EXPLOSION_VFX_LIFETIME_SECONDS)
	self:_shakeImpact()
end

Handler.moduleIds = {
	MECHA_PUNCH_MODULE_ID,
	DESTROYER_3000_MECHA_PUNCH_MODULE_ID,
}
Handler.start = Handler._startMechaPunch
Handler.actions = {
	impact = Handler._impactMechaPunch,
}
Handler.requiredParentFields = {
	"rootModel",
	"rightHandModel",
}
Handler.requiresHandle = false

return Handler
