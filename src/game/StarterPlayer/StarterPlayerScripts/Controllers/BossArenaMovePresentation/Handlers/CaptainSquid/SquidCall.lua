type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		SQUID_CALL_MODULE_ID = "Moves.CaptainSquid.SquidCall",
	},
	Vfx = {
		CAPTAIN_SQUID_SQUID_CALL_VFX_NAME = "SquidCall",
		CAPTAIN_SQUID_VFX_FOLDER_NAME = "CaptainSquid",
		SQUID_CALL_CANNONBALL_MODEL_NAME = "CannonBall",
		SQUID_CALL_CANNON_MODEL_NAME = "Cannon",
		SQUID_CALL_CANNON_MUZZLE_ATTACHMENT_NAME = "CannonBall",
		SQUID_CALL_LEFT_HAND_MODEL_NAME = "LeftHand",
		SQUID_CALL_PROJECTILE_FLY_ATTACHMENT_NAME = "FlyAtt",
	},
	Timing = {
		SQUID_CALL_IMPACT_LIFETIME_SECONDS = 2,
		SQUID_CALL_LEFT_HAND_LIFETIME_SECONDS = 2.5,
	},
	Values = {
		SQUID_CALL_CANNON_MIDDLE_NAME = "Middle",
		SQUID_CALL_PROJECTILE_IMPACT_PART_NAME = "BallHit",
	},
}

local CAPTAIN_SQUID_SQUID_CALL_VFX_NAME = Constants.Vfx.CAPTAIN_SQUID_SQUID_CALL_VFX_NAME
local CAPTAIN_SQUID_VFX_FOLDER_NAME = Constants.Vfx.CAPTAIN_SQUID_VFX_FOLDER_NAME
local SQUID_CALL_CANNONBALL_MODEL_NAME = Constants.Vfx.SQUID_CALL_CANNONBALL_MODEL_NAME
local SQUID_CALL_CANNON_MIDDLE_NAME = Constants.Values.SQUID_CALL_CANNON_MIDDLE_NAME
local SQUID_CALL_CANNON_MODEL_NAME = Constants.Vfx.SQUID_CALL_CANNON_MODEL_NAME
local SQUID_CALL_CANNON_MUZZLE_ATTACHMENT_NAME = Constants.Vfx.SQUID_CALL_CANNON_MUZZLE_ATTACHMENT_NAME
local SQUID_CALL_IMPACT_LIFETIME_SECONDS = Constants.Timing.SQUID_CALL_IMPACT_LIFETIME_SECONDS
local SQUID_CALL_LEFT_HAND_LIFETIME_SECONDS = Constants.Timing.SQUID_CALL_LEFT_HAND_LIFETIME_SECONDS
local SQUID_CALL_LEFT_HAND_MODEL_NAME = Constants.Vfx.SQUID_CALL_LEFT_HAND_MODEL_NAME
local SQUID_CALL_MODULE_ID = Constants.ModuleIds.SQUID_CALL_MODULE_ID
local SQUID_CALL_PROJECTILE_FLY_ATTACHMENT_NAME = Constants.Vfx.SQUID_CALL_PROJECTILE_FLY_ATTACHMENT_NAME
local SQUID_CALL_PROJECTILE_IMPACT_PART_NAME = Constants.Values.SQUID_CALL_PROJECTILE_IMPACT_PART_NAME
local DEFAULT_SQUID_CALL_FADE_SECONDS = 1.0

local Handler = {}

local function buildAimBasis(aimVector: Vector3, upReference: Vector3): (Vector3, Vector3)
	local rightVector = upReference:Cross(aimVector)
	if rightVector.Magnitude <= 0.001 then
		rightVector = Vector3.xAxis:Cross(aimVector)
	end
	rightVector = rightVector.Unit

	local upVector = aimVector:Cross(rightVector)
	if upVector.Magnitude <= 0.001 then
		upVector = Vector3.yAxis
	else
		upVector = upVector.Unit
	end

	return rightVector, upVector
end

local function resolveAlignedCannonCFrame(originPosition: Vector3, aimDirection: Vector3, localAimVector: Vector3): CFrame
	local worldRightVector, worldUpVector = buildAimBasis(aimDirection, Vector3.yAxis)
	local localRightVector, localUpVector = buildAimBasis(localAimVector, Vector3.yAxis)
	local worldFrame = CFrame.fromMatrix(originPosition, worldRightVector, worldUpVector, -aimDirection)
	local localFrame = CFrame.fromMatrix(Vector3.zero, localRightVector, localUpVector, -localAimVector)
	return worldFrame * localFrame:Inverse()
end

local function resolveSquidCallModelCFrame(baseCFrame: CFrame, middleLocalCFrame: CFrame, targetPosition: Vector3?): CFrame
	if typeof(targetPosition) ~= "Vector3" then
		return baseCFrame
	end

	local localAimVector = -middleLocalCFrame.RightVector
	if localAimVector.Magnitude <= 0.001 then
		return baseCFrame
	end

	local modelCFrame = baseCFrame
	for _ = 1, 3 do
		local middlePosition = (modelCFrame * middleLocalCFrame).Position
		local aimOffset = targetPosition - middlePosition
		if aimOffset.Magnitude <= 0.001 then
			break
		end

		modelCFrame = resolveAlignedCannonCFrame(baseCFrame.Position, aimOffset.Unit, localAimVector.Unit)
	end

	return modelCFrame
end

local function setVisualsEnabled(root: Instance?, enabled: boolean)
	if root == nil then
		return
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") or descendant:IsA("Beam") then
			descendant.Enabled = enabled
		end
	end
end

function Handler:_fadeSquidCallPart(part: BasePart, fadeSeconds: number)
	local tween = self.TweenService:Create(
		part,
		TweenInfo.new(fadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = 1 }
	)
	tween:Play()
end

function Handler:_beginSquidCallFade(record: ActiveRecord, fadeSeconds: number)
	local modelsToFade = {
		record.cannonModel,
		record.projectileModel,
	}
	local hasActiveModel = false

	for _, model in ipairs(modelsToFade) do
		if model and model.Parent ~= nil then
			hasActiveModel = true
			setVisualsEnabled(model, false)
			for _, descendant in ipairs(model:GetDescendants()) do
				if descendant:IsA("BasePart") then
					self:_fadeSquidCallPart(descendant, fadeSeconds)
				end
			end
		end
	end

	if not hasActiveModel then
		self:_cleanupRecord(record)
		return
	end

	task.delay(fadeSeconds, function()
		self:_cleanupRecord(record)
	end)
end

function Handler:_applySquidCallCannonPose(record: ActiveRecord, targetPosition: Vector3?, alpha: number)
	local cannonModel = record.cannonModel
	local cannonMiddle = record.cannonMiddle
	local aimData = record.squidCallAimData
	local bossRootPart = self:resolveBossRootPart(record.bossModel)
	if cannonModel == nil or cannonMiddle == nil or aimData == nil or bossRootPart == nil then
		return
	end

	local desiredBaseCFrame = self:resolveCannonBaseCFrame(
		bossRootPart.Position,
		targetPosition,
		aimData.initialBaseCFrame.RightVector
	)
	local desiredModelCFrame = resolveSquidCallModelCFrame(desiredBaseCFrame, aimData.middleLocalCFrame, targetPosition)
	local modelCFrame = aimData.initialBaseCFrame:Lerp(desiredModelCFrame, math.clamp(alpha, 0, 1))
	cannonModel:PivotTo(modelCFrame)
end

function Handler:_updateSquidCallMotion(record: ActiveRecord, nowServerTime: number)
	local aimData = record.squidCallAimData
	if aimData ~= nil then
		local targetRootPart = self:resolvePlayerRootPartByUserId(aimData.targetUserId)
		if targetRootPart then
			aimData.lastKnownTargetPosition = targetRootPart.Position
		end

		local elapsed = math.max(0, nowServerTime - aimData.startedAtServerTime)
		local alpha = math.clamp(elapsed / math.max(0.001, aimData.duration), 0, 1)
		self:_applySquidCallCannonPose(record, aimData.lastKnownTargetPosition, alpha)
	end

	local projectileModel = record.projectileModel
	local projectileMotion = record.projectileMotion
	if projectileModel == nil or projectileMotion == nil or projectileModel.Parent == nil then
		return
	end

	local alpha = math.clamp(
		(nowServerTime - projectileMotion.startedAtServerTime) / math.max(0.001, projectileMotion.travelDuration),
		0,
		1
	)
	local position = projectileMotion.startPosition:Lerp(projectileMotion.impactPosition, alpha)
	projectileModel:PivotTo(CFrame.new(position))
end

function Handler:_startSquidCall(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local bossLeftHand = self:resolveBossLeftHandPart(bossModel)
	if bossLeftHand == nil then
		self:warnWithPrefix("Squid Call presentation could not resolve the live boss LeftHand.")
		self:_cleanupRecord(record)
		return
	end

	local leftHandSource = self:resolveBossVfxModel(
		CAPTAIN_SQUID_VFX_FOLDER_NAME,
		CAPTAIN_SQUID_SQUID_CALL_VFX_NAME,
		SQUID_CALL_LEFT_HAND_MODEL_NAME
	)
	if leftHandSource == nil then
		self:warnWithPrefix("Squid Call left-hand VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local castFolder = self:_ensureCastFolder(record)
	local leftHandModel = leftHandSource:Clone()
	local scaleMultiplier = math.max(0.1, tonumber(event.payload and event.payload.scaleMultiplier) or 1)
	leftHandModel:ScaleTo(scaleMultiplier)
	self:prepareAttachedEffectModel(leftHandModel)
	self:scaleAttachedSounds(leftHandModel, scaleMultiplier)
	leftHandModel.Parent = castFolder
	record.leftHandModel = leftHandModel

	if not self:attachEffectModel(leftHandModel, bossLeftHand) then
		self:warnWithPrefix("Squid Call left-hand VFX model is missing BasePart configuration.")
		self:_cleanupRecord(record)
		return
	end

	self:playAllSounds(leftHandModel, scaleMultiplier)
	self:emitEffectInstance(leftHandModel, SQUID_CALL_LEFT_HAND_LIFETIME_SECONDS)
end

function Handler:_summonSquidCall(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	local bossRootPart = self:resolveBossRootPart(bossModel)
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil then
		self:_cleanupRecord(record)
		return
	end

	local cannonSource = self:resolveBossVfxModel(
		CAPTAIN_SQUID_VFX_FOLDER_NAME,
		CAPTAIN_SQUID_SQUID_CALL_VFX_NAME,
		SQUID_CALL_CANNON_MODEL_NAME
	)
	if cannonSource == nil then
		self:warnWithPrefix("Squid Call cannon VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local payload = event.payload
	local scaleMultiplier = math.max(0.1, tonumber(payload and payload.scaleMultiplier) or 1)
	local aimDuration = math.max(0.05, tonumber(payload and payload.aimDuration) or 2)
	local targetUserId = tonumber(payload and payload.targetUserId)
	local castFolder = self:_ensureCastFolder(record)
	local cannonModel = cannonSource:Clone()
	cannonModel:ScaleTo(scaleMultiplier)
	self:prepareMovingEffectModel(cannonModel)

	local cannonMiddle = cannonModel:FindFirstChild(SQUID_CALL_CANNON_MIDDLE_NAME, true)
	if not (cannonMiddle and cannonMiddle:IsA("BasePart")) then
		self:warnWithPrefix("Squid Call cannon VFX model is missing the Middle part.")
		self:_cleanupRecord(record)
		return
	end

	local cannonMuzzleAttachment = cannonMiddle:FindFirstChild(SQUID_CALL_CANNON_MUZZLE_ATTACHMENT_NAME)
	if not (cannonMuzzleAttachment and cannonMuzzleAttachment:IsA("Attachment")) then
		self:warnWithPrefix("Squid Call cannon VFX model is missing Middle.CannonBall attachment.")
		self:_cleanupRecord(record)
		return
	end

	local initialBaseCFrame = self:resolveCannonBaseCFrame(bossRootPart.Position, nil, bossRootPart.CFrame.LookVector)
	cannonModel:PivotTo(initialBaseCFrame)
	local middleLocalCFrame = cannonModel:GetPivot():ToObjectSpace(cannonMiddle.CFrame)

	record.cannonModel = cannonModel
	record.cannonMiddle = cannonMiddle
	record.cannonMuzzleAttachment = cannonMuzzleAttachment
	record.rootModel = cannonModel
	record.squidCallAimData = {
		startedAtServerTime = if typeof(event.serverTime) == "number" then event.serverTime else self.Workspace:GetServerTimeNow(),
		duration = aimDuration,
		targetUserId = targetUserId,
		initialBaseCFrame = initialBaseCFrame,
		middleLocalCFrame = middleLocalCFrame,
		lastKnownTargetPosition = nil,
	}

	local targetRootPart = self:resolvePlayerRootPartByUserId(targetUserId)
	if targetRootPart then
		record.squidCallAimData.lastKnownTargetPosition = targetRootPart.Position
	end

	cannonModel.Parent = castFolder
	self:_applySquidCallCannonPose(record, record.squidCallAimData.lastKnownTargetPosition, 0)

	local cannonEmitDelaySeconds = math.max(0, tonumber(payload and payload.cannonEmitDelaySeconds) or 0)
	task.delay(cannonEmitDelaySeconds, function()
		if cannonModel.Parent == nil then
			return
		end

		self:emitVisuals(cannonModel)
	end)
end

function Handler:_fireSquidCall(record: ActiveRecord, event: PresentationEvent)
	local castFolder = record.castFolder
	if castFolder == nil or castFolder.Parent == nil then
		return
	end

	local payload = event.payload
	if typeof(payload) ~= "table" then
		return
	end

	local startPosition = payload.startPosition
	local impactPosition = payload.impactPosition
	local travelDuration = tonumber(payload.travelDuration)
	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	if typeof(startPosition) ~= "Vector3" or typeof(impactPosition) ~= "Vector3" or travelDuration == nil then
		return
	end

	local storedAimData = record.squidCallAimData
	record.squidCallAimData = nil
	if record.cannonModel and record.cannonMiddle then
		local bossRootPart = self:resolveBossRootPart(record.bossModel)
		if bossRootPart then
			local baseCFrame = self:resolveCannonBaseCFrame(
				bossRootPart.Position,
				impactPosition,
				record.cannonModel:GetPivot().RightVector
			)
			local middleLocalCFrame = if storedAimData then storedAimData.middleLocalCFrame else record.cannonModel:GetPivot():ToObjectSpace(record.cannonMiddle.CFrame)
			record.cannonModel:PivotTo(resolveSquidCallModelCFrame(baseCFrame, middleLocalCFrame, impactPosition))
		end
	end

	local cannonMuzzleAttachment = record.cannonMuzzleAttachment
	if cannonMuzzleAttachment then
		local muzzleSound = cannonMuzzleAttachment:FindFirstChild("Cannon Fire")
		self:playSound(if muzzleSound and muzzleSound:IsA("Sound") then muzzleSound else nil, scaleMultiplier)
		self:emitVisuals(cannonMuzzleAttachment)
	end

	local projectileSource = self:resolveBossVfxModel(
		CAPTAIN_SQUID_VFX_FOLDER_NAME,
		CAPTAIN_SQUID_SQUID_CALL_VFX_NAME,
		SQUID_CALL_CANNONBALL_MODEL_NAME
	)
	if projectileSource == nil then
		self:warnWithPrefix("Squid Call cannonball VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		return
	end

	local projectileModel = projectileSource:Clone()
	projectileModel:ScaleTo(scaleMultiplier)
	self:prepareMovingEffectModel(projectileModel)
	if self:resolveEffectModelPrimaryPart(projectileModel) == nil then
		self:warnWithPrefix("Squid Call cannonball VFX model is missing a BasePart for motion.")
		return
	end

	projectileModel.Parent = castFolder
	projectileModel:PivotTo(CFrame.new(startPosition))
	record.projectileModel = projectileModel
	record.projectileMotion = {
		startPosition = startPosition,
		impactPosition = impactPosition,
		travelDuration = math.max(0.001, travelDuration),
		startedAtServerTime = if typeof(event.serverTime) == "number" then event.serverTime else self.Workspace:GetServerTimeNow(),
	}

	local flyAttachment = projectileModel:FindFirstChild(SQUID_CALL_PROJECTILE_FLY_ATTACHMENT_NAME, true)
	if flyAttachment then
		local flyDelaySeconds = math.max(0, tonumber(payload.flyDelaySeconds) or 0)
		task.delay(flyDelaySeconds, function()
			if projectileModel.Parent == nil then
				return
			end

			self:emitVisuals(flyAttachment)
		end)
	end
end

function Handler:_impactSquidCall(record: ActiveRecord, event: PresentationEvent)
	self:_shakeImpact()

	local payload = event.payload
	local fadeSeconds = if typeof(payload) == "table" then tonumber(payload.fadeSeconds) else nil
	fadeSeconds = math.max(0, fadeSeconds or DEFAULT_SQUID_CALL_FADE_SECONDS)
	if typeof(payload) ~= "table" then
		self:_cleanupRecord(record)
		return
	end

	local impactPosition = payload.impactPosition
	if typeof(impactPosition) ~= "Vector3" then
		self:_cleanupRecord(record)
		return
	end

	local impactSource = nil
	if record.projectileModel and record.projectileModel.Parent then
		impactSource = record.projectileModel:FindFirstChild(SQUID_CALL_PROJECTILE_IMPACT_PART_NAME, true)
	end

	if impactSource and impactSource:IsA("BasePart") then
		local impactPart = impactSource:Clone()
		self:prepareMovingEffectPart(impactPart)
		impactPart.CFrame = CFrame.new(impactPosition)
		impactPart.Parent = self:_ensureVisualFolder()
		self:playAllSounds(impactPart, math.max(0.1, tonumber(payload.scaleMultiplier) or 1))
		self:emitEffectInstance(impactPart, SQUID_CALL_IMPACT_LIFETIME_SECONDS)
	end

	self:_beginSquidCallFade(record, fadeSeconds)
end

Handler.moduleIds = {
	SQUID_CALL_MODULE_ID,
}
Handler.start = Handler._startSquidCall
Handler.update = Handler._updateSquidCallMotion
Handler.actions = {
	summon = Handler._summonSquidCall,
	fire = Handler._fireSquidCall,
	impact = Handler._impactSquidCall,
}
Handler.requiredParentFields = {
	"cannonModel",
	"projectileModel",
}

return Handler
