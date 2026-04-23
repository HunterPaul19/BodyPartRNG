type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		BROCCOLI_BRO_STOMP_MODULE_ID = "Moves.BroccoliBro.Stomp",
	},
	Vfx = {
		BROCCOLI_BRO_STOMP_START_SOUNDS_FOLDER_NAME = "StartSounds",
		BROCCOLI_BRO_STOMP_FLOOR_VFX_NAME = "FloorFx",
		BROCCOLI_BRO_STOMP_VFX_NAME = "Stomp",
		BROCCOLI_BRO_VFX_FOLDER_NAME = "BroccoliBro",
	},
	Timing = {
		BROCCOLI_BRO_STOMP_VFX_LIFETIME_SECONDS = 3,
	},
}

local BROCCOLI_BRO_STOMP_FLOOR_VFX_NAME = Constants.Vfx.BROCCOLI_BRO_STOMP_FLOOR_VFX_NAME
local BROCCOLI_BRO_STOMP_MODULE_ID = Constants.ModuleIds.BROCCOLI_BRO_STOMP_MODULE_ID
local BROCCOLI_BRO_STOMP_START_SOUNDS_FOLDER_NAME = Constants.Vfx.BROCCOLI_BRO_STOMP_START_SOUNDS_FOLDER_NAME
local BROCCOLI_BRO_STOMP_VFX_LIFETIME_SECONDS = Constants.Timing.BROCCOLI_BRO_STOMP_VFX_LIFETIME_SECONDS
local BROCCOLI_BRO_STOMP_VFX_NAME = Constants.Vfx.BROCCOLI_BRO_STOMP_VFX_NAME
local BROCCOLI_BRO_VFX_FOLDER_NAME = Constants.Vfx.BROCCOLI_BRO_VFX_FOLDER_NAME

local Handler = {}

function Handler:_startBroccoliStomp(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	local bossLeftFoot = self:resolveBossLeftFootPart(bossModel)
	local bossRootPart = self:resolveBossRootPart(bossModel)
	local soundsSource = self:resolveBossVfxInstance(
		BROCCOLI_BRO_VFX_FOLDER_NAME,
		BROCCOLI_BRO_STOMP_VFX_NAME,
		BROCCOLI_BRO_STOMP_START_SOUNDS_FOLDER_NAME
	)
	if soundsSource == nil then
		self:warnWithPrefix("Broccoli Bro Stomp start sounds are missing from ReplicatedStorage.GameAssets.VFX.")
		return
	end

	local scaleMultiplier = math.max(0.1, tonumber(event.payload and event.payload.scaleMultiplier) or 1)
	self:playDelayedSoundClones(
		soundsSource,
		self:_ensureCastFolder(record),
		scaleMultiplier,
		bossLeftFoot or bossRootPart
	)
end

function Handler:_stompBroccoliStomp(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.impactCFrame) ~= "CFrame" then
		self:_cleanupRecord(record)
		return
	end

	local effectSource = self:resolveBossVfxInstance(
		BROCCOLI_BRO_VFX_FOLDER_NAME,
		BROCCOLI_BRO_STOMP_VFX_NAME,
		BROCCOLI_BRO_STOMP_FLOOR_VFX_NAME
	)
	if effectSource == nil then
		self:warnWithPrefix("Broccoli Bro Stomp FloorFx VFX instance is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	local effectInstance = effectSource:Clone()
	if not self:pivotEffectInstanceAtAuthoredPivot(effectInstance, payload.impactCFrame, scaleMultiplier) then
		self:warnWithPrefix("Broccoli Bro Stomp FloorFx VFX instance cannot be pivoted.")
		effectInstance:Destroy()
		self:_cleanupRecord(record)
		return
	end

	effectInstance.Parent = self:_ensureCastFolder(record)
	self:playAllSounds(effectInstance, scaleMultiplier)
	self:emitEffectInstance(effectInstance, BROCCOLI_BRO_STOMP_VFX_LIFETIME_SECONDS)
	self:_shakeImpact()
end

Handler.moduleIds = {
	BROCCOLI_BRO_STOMP_MODULE_ID,
}
Handler.start = Handler._startBroccoliStomp
Handler.actions = {
	stomp = Handler._stompBroccoliStomp,
}
Handler.requiresHandle = false

return Handler
