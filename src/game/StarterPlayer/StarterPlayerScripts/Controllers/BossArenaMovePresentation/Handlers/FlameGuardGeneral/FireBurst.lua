type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		FIRE_BURST_MODULE_ID = "Moves.FlameGuardGeneral.FireBurst",
	},
	Vfx = {
		FIRE_BURST_RING_VFX_NAME = "MapRing",
		FIRE_BURST_VFX_NAME = "FlameBurst",
	},
}

local FIRE_BURST_MODULE_ID = Constants.ModuleIds.FIRE_BURST_MODULE_ID
local FIRE_BURST_RING_VFX_NAME = Constants.Vfx.FIRE_BURST_RING_VFX_NAME
local FIRE_BURST_VFX_NAME = Constants.Vfx.FIRE_BURST_VFX_NAME

local Handler = {}

function Handler:_startFireBurst(record: ActiveRecord, event: PresentationEvent)
	self:_prepareAttachedCastModels(record, event, "Fire Burst", FIRE_BURST_VFX_NAME, {
		enableParticles = true,
		scaleRootSounds = true,
		playAllSounds = true,
	})
end

function Handler:_impactFireBurst(_record: ActiveRecord, event: PresentationEvent)
	self:_shakeImpact()

	local record = self._recordsByCastId[event.castId]
	if record == nil or record.castFolder == nil or record.castFolder.Parent == nil then
		return
	end

	local payload = event.payload
	if typeof(payload) ~= "table" then
		return
	end

	local impactPosition = payload.impactPosition
	local startRadius = tonumber(payload.startRadius)
	local endRadius = tonumber(payload.endRadius) or startRadius
	local ringThickness = tonumber(payload.ringThickness) or 0
	local durationSeconds = math.max(0, tonumber(payload.durationSeconds) or 0)
	if typeof(impactPosition) ~= "Vector3" or startRadius == nil then
		return
	end

	local ringSource = self:resolveVfxInstance(FIRE_BURST_VFX_NAME, FIRE_BURST_RING_VFX_NAME)
	if not (ringSource and ringSource:IsA("BasePart")) then
		self:warnWithPrefix("Fire Burst MapRing VFX part is missing from ReplicatedStorage.GameAssets.VFX.")
		return
	end

	local ringPart = ringSource:Clone()
	self:prepareMovingEffectPart(ringPart)
	ringPart.Parent = record.castFolder

	local startOuterRadius = math.max(0, startRadius + (ringThickness * 0.5))
	local endOuterRadius = math.max(0, (endRadius or startRadius) + (ringThickness * 0.5))
	local startSize = self:resolveFireBurstRingSize(startOuterRadius, ringPart)
	local endSize = self:resolveFireBurstRingSize(endOuterRadius, ringPart)
	ringPart.Size = startSize
	ringPart.CFrame = self:resolveFireBurstRingCFrame(impactPosition, startSize)

	if durationSeconds <= 0 then
		ringPart.Size = endSize
		ringPart.CFrame = self:resolveFireBurstRingCFrame(impactPosition, endSize)
		return
	end

	local tween = self.TweenService:Create(
		ringPart,
		TweenInfo.new(durationSeconds, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
		{ Size = endSize }
	)
	tween:Play()

	task.delay(durationSeconds, function()
		if ringPart.Parent ~= nil then
			ringPart.CFrame = self:resolveFireBurstRingCFrame(impactPosition, ringPart.Size)
		end
	end)
end

Handler.moduleIds = {
	FIRE_BURST_MODULE_ID,
}
Handler.start = Handler._startFireBurst
Handler.actions = {
	impact = Handler._impactFireBurst,
}

return Handler
