type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		CAT_MECH_ELITE_CAT_SUMMON_MODULE_ID = "Moves.CatMechElite.CatSummon",
	},
	Vfx = {
		CAT_MECH_ELITE_VFX_FOLDER_NAME = "CatMechElite",
		CAT_SUMMON_VFX_NAME = "CatSummon",
		CAT_SUMMON_RIGHT_HAND_MODEL_NAME = "RightHand",
		CAT_SUMMON_ROOT_PART_MODEL_NAME = "RootPart",
		CAT_SUMMON_IMPACT_MODEL_NAME = "Impact",
	},
	Timing = {
		CAT_SUMMON_ATTACHED_LIFETIME_SECONDS = 4.25,
		CAT_SUMMON_IMPACT_LIFETIME_SECONDS = 3,
	},
}

local CAT_MECH_ELITE_CAT_SUMMON_MODULE_ID = Constants.ModuleIds.CAT_MECH_ELITE_CAT_SUMMON_MODULE_ID
local CAT_MECH_ELITE_VFX_FOLDER_NAME = Constants.Vfx.CAT_MECH_ELITE_VFX_FOLDER_NAME
local CAT_SUMMON_ATTACHED_LIFETIME_SECONDS = Constants.Timing.CAT_SUMMON_ATTACHED_LIFETIME_SECONDS
local CAT_SUMMON_IMPACT_LIFETIME_SECONDS = Constants.Timing.CAT_SUMMON_IMPACT_LIFETIME_SECONDS
local CAT_SUMMON_IMPACT_MODEL_NAME = Constants.Vfx.CAT_SUMMON_IMPACT_MODEL_NAME
local CAT_SUMMON_RIGHT_HAND_MODEL_NAME = Constants.Vfx.CAT_SUMMON_RIGHT_HAND_MODEL_NAME
local CAT_SUMMON_ROOT_PART_MODEL_NAME = Constants.Vfx.CAT_SUMMON_ROOT_PART_MODEL_NAME
local CAT_SUMMON_VFX_NAME = Constants.Vfx.CAT_SUMMON_VFX_NAME

local Handler = {}

function Handler:_resolveCatSummonBossModel(record: ActiveRecord?, event: PresentationEvent): Model?
	local eventBossModel = event.bossModel
	if eventBossModel and eventBossModel.Parent ~= nil then
		return eventBossModel
	end

	local recordBossModel = record and record.bossModel
	if recordBossModel and recordBossModel.Parent ~= nil then
		return recordBossModel
	end

	local activeBoss = self.Workspace:FindFirstChild("ActiveBoss")
	if activeBoss and activeBoss:IsA("Model") then
		return activeBoss
	end

	return nil
end

function Handler:_resolveCatSummonLimbFallback(bossModel: Model, partName: string): BasePart?
	local part = bossModel:FindFirstChild(partName, true)
	if part and part:IsA("BasePart") then
		return part
	end

	return nil
end

function Handler:_resolveCatSummonRightHandTarget(bossModel: Model, bossRootPart: BasePart?): (BasePart?, string?)
	local bossRightHand = self:resolveBossRightHandPart(bossModel)
	if bossRightHand ~= nil then
		return bossRightHand, nil
	end

	local rightLowerArm = self:_resolveCatSummonLimbFallback(bossModel, "RightLowerArm")
	if rightLowerArm ~= nil then
		return rightLowerArm, "RightLowerArm"
	end

	local rightUpperArm = self:_resolveCatSummonLimbFallback(bossModel, "RightUpperArm")
	if rightUpperArm ~= nil then
		return rightUpperArm, "RightUpperArm"
	end

	if bossRootPart ~= nil then
		return bossRootPart, "RootPart"
	end

	return nil, nil
end

function Handler:_resolveCatSummonCastFolder(record: ActiveRecord?): Folder
	if record ~= nil then
		return self:_ensureCastFolder(record)
	end

	return self:_ensureVisualFolder()
end

function Handler:_startCatSummon(record: ActiveRecord, event: PresentationEvent)
	local bossModel = self:_resolveCatSummonBossModel(record, event)
	if bossModel == nil then
		self:warnWithPrefix("Cat Summon presentation could not resolve the live boss model.")
		return
	end

	local bossRootPart = self:resolveBossRootPart(bossModel)
	if bossRootPart == nil then
		self:warnWithPrefix("Cat Summon presentation could not resolve the live boss RootPart.")
		return
	end

	local rightHandSource = self:resolveBossVfxModel(
		CAT_MECH_ELITE_VFX_FOLDER_NAME,
		CAT_SUMMON_VFX_NAME,
		CAT_SUMMON_RIGHT_HAND_MODEL_NAME
	)
	local rootPartSource = self:resolveBossVfxModel(
		CAT_MECH_ELITE_VFX_FOLDER_NAME,
		CAT_SUMMON_VFX_NAME,
		CAT_SUMMON_ROOT_PART_MODEL_NAME
	)
	if rightHandSource == nil or rootPartSource == nil then
		self:warnWithPrefix("Cat Summon RightHand/RootPart VFX models are missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local bossRightHand, fallbackPartName = self:_resolveCatSummonRightHandTarget(bossModel, bossRootPart)
	if bossRightHand == nil then
		self:warnWithPrefix("Cat Summon presentation could not resolve the live boss RightHand.")
		return
	end
	if fallbackPartName ~= nil then
		self:warnWithPrefix(
			string.format(
				"Cat Summon presentation could not resolve the live boss RightHand; using %s fallback.",
				fallbackPartName
			)
		)
	end

	local payload = event.payload
	local scaleMultiplier = math.max(0.1, tonumber(payload and payload.scaleMultiplier) or 1)
	local castFolder = self:_ensureCastFolder(record)
	local rightHandModel = rightHandSource:Clone()
	rightHandModel:ScaleTo(scaleMultiplier)
	self:prepareAttachedEffectModel(rightHandModel)
	self:enableVfxDescendants(rightHandModel)
	self:scaleAttachedSounds(rightHandModel, scaleMultiplier)
	rightHandModel.Parent = castFolder
	record.rightHandModel = rightHandModel

	if not self:attachEffectModel(rightHandModel, bossRightHand) then
		self:warnWithPrefix("Cat Summon RightHand VFX model is missing BasePart configuration.")
		rightHandModel:Destroy()
		record.rightHandModel = nil
		return
	end

	self:playDelayedSoundClones(rootPartSource, castFolder, scaleMultiplier)
	self:emitEffectInstance(rightHandModel, CAT_SUMMON_ATTACHED_LIFETIME_SECONDS)
end

function Handler:_rootPartCatSummon(record: ActiveRecord?, event: PresentationEvent)
	local bossModel = self:_resolveCatSummonBossModel(record, event)
	if bossModel == nil then
		self:warnWithPrefix("Cat Summon presentation could not resolve the live boss model.")
		return
	end

	local bossRootPart = self:resolveBossRootPart(bossModel)
	if bossRootPart == nil then
		self:warnWithPrefix("Cat Summon presentation could not resolve the live boss RootPart.")
		return
	end

	local rootPartSource = self:resolveBossVfxModel(
		CAT_MECH_ELITE_VFX_FOLDER_NAME,
		CAT_SUMMON_VFX_NAME,
		CAT_SUMMON_ROOT_PART_MODEL_NAME
	)
	if rootPartSource == nil then
		self:warnWithPrefix("Cat Summon RootPart VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		return
	end

	local payload = event.payload
	local scaleMultiplier = math.max(0.1, tonumber(payload and payload.scaleMultiplier) or 1)
	local castFolder = self:_resolveCatSummonCastFolder(record)
	local rootModel = rootPartSource:Clone()
	rootModel:ScaleTo(scaleMultiplier)
	self:prepareAttachedEffectModel(rootModel)
	self:enableVfxDescendants(rootModel)
	self:scaleAttachedSounds(rootModel, scaleMultiplier)
	rootModel.Parent = castFolder
	if record ~= nil then
		record.rootModel = rootModel
	end

	if not self:attachEffectModel(rootModel, bossRootPart) then
		self:warnWithPrefix("Cat Summon RootPart VFX model is missing BasePart configuration.")
		rootModel:Destroy()
		if record ~= nil then
			record.rootModel = nil
		end
		return
	end

	self:emitEffectInstance(rootModel, CAT_SUMMON_ATTACHED_LIFETIME_SECONDS)
	if record == nil then
		self:destroyVfxAfter(rootModel, CAT_SUMMON_ATTACHED_LIFETIME_SECONDS)
	end
end

function Handler:_impactCatSummon(record: ActiveRecord?, event: PresentationEvent)
	local bossModel = self:_resolveCatSummonBossModel(record, event)
	if bossModel == nil then
		self:warnWithPrefix("Cat Summon presentation could not resolve the live boss model.")
		return
	end

	local bossRootPart = self:resolveBossRootPart(bossModel)
	if bossRootPart == nil then
		self:warnWithPrefix("Cat Summon presentation could not resolve the live boss RootPart.")
		return
	end

	local impactSource = self:resolveBossVfxModel(
		CAT_MECH_ELITE_VFX_FOLDER_NAME,
		CAT_SUMMON_VFX_NAME,
		CAT_SUMMON_IMPACT_MODEL_NAME
	)
	if impactSource == nil then
		self:warnWithPrefix("Cat Summon Impact VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		return
	end

	local payload = event.payload
	local scaleMultiplier = math.max(0.1, tonumber(payload and payload.scaleMultiplier) or 1)
	local impactModel = impactSource:Clone()
	impactModel:ScaleTo(scaleMultiplier)
	self:prepareMovingEffectModel(impactModel)
	self:enableVfxDescendants(impactModel)
	self:scaleAttachedSounds(impactModel, scaleMultiplier)
	impactModel.Parent = self:_ensureVisualFolder()
	impactModel:PivotTo(bossRootPart.CFrame)

	self:_shakeImpact()
	self:emitEffectInstance(impactModel, CAT_SUMMON_IMPACT_LIFETIME_SECONDS)
	self:destroyVfxAfter(impactModel, CAT_SUMMON_IMPACT_LIFETIME_SECONDS)
end

function Handler:_rootPartCatSummonWithoutRecord(event: PresentationEvent)
	self:_rootPartCatSummon(nil, event)
end

function Handler:_impactCatSummonWithoutRecord(event: PresentationEvent)
	self:_impactCatSummon(nil, event)
end

Handler.moduleIds = {
	CAT_MECH_ELITE_CAT_SUMMON_MODULE_ID,
}
Handler.start = Handler._startCatSummon
Handler.actions = {
	rootPart = Handler._rootPartCatSummon,
	impact = Handler._impactCatSummon,
}
Handler.actionsWithoutRecord = {
	rootPart = Handler._rootPartCatSummonWithoutRecord,
	impact = Handler._impactCatSummonWithoutRecord,
}
Handler.requiredParentFields = {
	"rightHandModel",
}
Handler.requiresHandle = false

return Handler
