type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		MASSIVE_GEEZER_BODY_SLAM_MODULE_ID = "Moves.MassiveGeezerRecolorable.BodySlam",
	},
	Vfx = {
		MASSIVE_GEEZER_BODY_SLAM_GROUND_SLAM_VFX_NAME = "GroundSlam",
		MASSIVE_GEEZER_BODY_SLAM_JUMP_VFX_NAME = "Jump",
		MASSIVE_GEEZER_BODY_SLAM_VFX_NAME = "BodySlam",
		MASSIVE_GEEZER_VFX_FOLDER_NAME = "MassiveGeezer",
	},
	Timing = {
		MASSIVE_GEEZER_BODY_SLAM_IMPACT_VFX_LIFETIME_SECONDS = 4,
		MASSIVE_GEEZER_BODY_SLAM_JUMP_VFX_LIFETIME_SECONDS = 2.5,
	},
	Shake = {
		MASSIVE_GEEZER_BODY_SLAM_SHAKE_FADE_IN = 0.04,
		MASSIVE_GEEZER_BODY_SLAM_SHAKE_FADE_OUT = 0.45,
		MASSIVE_GEEZER_BODY_SLAM_SHAKE_MAGNITUDE = 2.5,
		MASSIVE_GEEZER_BODY_SLAM_SHAKE_RADIUS = 220,
		MASSIVE_GEEZER_BODY_SLAM_SHAKE_ROUGHNESS = 13,
	},
}

local MASSIVE_GEEZER_BODY_SLAM_GROUND_SLAM_VFX_NAME = Constants.Vfx.MASSIVE_GEEZER_BODY_SLAM_GROUND_SLAM_VFX_NAME
local MASSIVE_GEEZER_BODY_SLAM_IMPACT_VFX_LIFETIME_SECONDS = Constants.Timing.MASSIVE_GEEZER_BODY_SLAM_IMPACT_VFX_LIFETIME_SECONDS
local MASSIVE_GEEZER_BODY_SLAM_JUMP_VFX_LIFETIME_SECONDS = Constants.Timing.MASSIVE_GEEZER_BODY_SLAM_JUMP_VFX_LIFETIME_SECONDS
local MASSIVE_GEEZER_BODY_SLAM_JUMP_VFX_NAME = Constants.Vfx.MASSIVE_GEEZER_BODY_SLAM_JUMP_VFX_NAME
local MASSIVE_GEEZER_BODY_SLAM_MODULE_ID = Constants.ModuleIds.MASSIVE_GEEZER_BODY_SLAM_MODULE_ID
local MASSIVE_GEEZER_BODY_SLAM_SHAKE_FADE_IN = Constants.Shake.MASSIVE_GEEZER_BODY_SLAM_SHAKE_FADE_IN
local MASSIVE_GEEZER_BODY_SLAM_SHAKE_FADE_OUT = Constants.Shake.MASSIVE_GEEZER_BODY_SLAM_SHAKE_FADE_OUT
local MASSIVE_GEEZER_BODY_SLAM_SHAKE_MAGNITUDE = Constants.Shake.MASSIVE_GEEZER_BODY_SLAM_SHAKE_MAGNITUDE
local MASSIVE_GEEZER_BODY_SLAM_SHAKE_RADIUS = Constants.Shake.MASSIVE_GEEZER_BODY_SLAM_SHAKE_RADIUS
local MASSIVE_GEEZER_BODY_SLAM_SHAKE_ROUGHNESS = Constants.Shake.MASSIVE_GEEZER_BODY_SLAM_SHAKE_ROUGHNESS
local MASSIVE_GEEZER_BODY_SLAM_VFX_NAME = Constants.Vfx.MASSIVE_GEEZER_BODY_SLAM_VFX_NAME
local MASSIVE_GEEZER_VFX_FOLDER_NAME = Constants.Vfx.MASSIVE_GEEZER_VFX_FOLDER_NAME

local Handler = {}

function Handler:_shakeBodySlamImpact(impactPosition: Vector3)
	local localPlayer = self.Players.LocalPlayer
	local character = localPlayer and localPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not (rootPart and rootPart:IsA("BasePart")) then
		return
	end

	local distance = (rootPart.Position - impactPosition).Magnitude
	local alpha = 1 - math.clamp(distance / MASSIVE_GEEZER_BODY_SLAM_SHAKE_RADIUS, 0, 1)
	if alpha <= 0 then
		return
	end

	self:_ensureCameraShaker():ShakeOnce(
		MASSIVE_GEEZER_BODY_SLAM_SHAKE_MAGNITUDE * alpha,
		MASSIVE_GEEZER_BODY_SLAM_SHAKE_ROUGHNESS,
		MASSIVE_GEEZER_BODY_SLAM_SHAKE_FADE_IN,
		MASSIVE_GEEZER_BODY_SLAM_SHAKE_FADE_OUT
	)
end

function Handler:_startMassiveGeezerBodySlam(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.floorCFrame) ~= "CFrame" then
		return
	end

	local jumpSource = self:resolveBossVfxModel(
		MASSIVE_GEEZER_VFX_FOLDER_NAME,
		MASSIVE_GEEZER_BODY_SLAM_VFX_NAME,
		MASSIVE_GEEZER_BODY_SLAM_JUMP_VFX_NAME
	)
	if jumpSource == nil then
		self:warnWithPrefix("Massive Geezer Body Slam Jump VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		return
	end

	local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
	local jumpModel = jumpSource:Clone()
	jumpModel:ScaleTo(scaleMultiplier)
	self:prepareMovingEffectModel(jumpModel)
	jumpModel:PivotTo(payload.floorCFrame)
	jumpModel.Parent = self:_ensureCastFolder(record)

	self:playAllSounds(jumpModel)
	self:emitEffectInstance(jumpModel, MASSIVE_GEEZER_BODY_SLAM_JUMP_VFX_LIFETIME_SECONDS)
	self:destroyAfter(jumpModel, MASSIVE_GEEZER_BODY_SLAM_JUMP_VFX_LIFETIME_SECONDS)
end

function Handler:_spawnBodySlamRockDebris(impactCFrame: CFrame, radius: number)
	local ok, err = pcall(function()
		self.RockDebris.Crater({
			Delay = 0.025,
		}, {
			{
				impactCFrame,
				{
					Count = 18,
					Distance = radius * 0.38,
					Full = true,
					LifeTime = 4,
					Size = Vector3.new(4.5, 3, 5.5),
					Smoke = true,
					SmokeSize = radius * 0.04,
					Top = true,
					Tween = {
						TweenUp = {
							Style = "Back",
							Direction = "Out",
							Time = 0.18,
						},
						TweenDown = {
							Style = "Sine",
							Direction = "In",
							Time = 1.1,
						},
					},
				},
			},
			{
				impactCFrame,
				{
					Count = 26,
					Distance = radius * 0.68,
					Full = true,
					LifeTime = 4.5,
					Size = Vector3.new(6.5, 3.5, 7.5),
					Smoke = false,
					Top = true,
					Tween = {
						TweenUp = {
							Style = "Back",
							Direction = "Out",
							Time = 0.24,
						},
						TweenDown = {
							Style = "Sine",
							Direction = "In",
							Time = 1.2,
						},
					},
				},
			},
		})
	end)
	if not ok then
		self:warnWithPrefix(string.format("Failed to spawn Body Slam rock debris: %s", tostring(err)))
	end
end

function Handler:_impactMassiveGeezerBodySlam(record: ActiveRecord, event: PresentationEvent)
	local payload = event.payload
	if typeof(payload) ~= "table" or typeof(payload.impactCFrame) ~= "CFrame" then
		return
	end

	local impactPosition = payload.impactPosition
	if typeof(impactPosition) ~= "Vector3" then
		impactPosition = payload.impactCFrame.Position
	end

	local groundSlamSource = self:resolveBossVfxModel(
		MASSIVE_GEEZER_VFX_FOLDER_NAME,
		MASSIVE_GEEZER_BODY_SLAM_VFX_NAME,
		MASSIVE_GEEZER_BODY_SLAM_GROUND_SLAM_VFX_NAME
	)
	if groundSlamSource == nil then
		self:warnWithPrefix("Massive Geezer Body Slam GroundSlam VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
	else
		local scaleMultiplier = math.max(0.1, tonumber(payload.scaleMultiplier) or 1)
		local groundSlamModel = groundSlamSource:Clone()
		groundSlamModel:ScaleTo(scaleMultiplier)
		self:prepareMovingEffectModel(groundSlamModel)
		groundSlamModel:PivotTo(payload.impactCFrame)
		groundSlamModel.Parent = self:_ensureVisualFolder()

		self:playAllSounds(groundSlamModel)
		self:emitEffectInstance(groundSlamModel, MASSIVE_GEEZER_BODY_SLAM_IMPACT_VFX_LIFETIME_SECONDS)
		self:destroyAfter(groundSlamModel, MASSIVE_GEEZER_BODY_SLAM_IMPACT_VFX_LIFETIME_SECONDS)
	end

	local radius = math.max(1, tonumber(payload.radius) or 55)
	self:_spawnBodySlamRockDebris(payload.impactCFrame, radius)
	self:_shakeBodySlamImpact(impactPosition)
end

Handler.moduleIds = {
	MASSIVE_GEEZER_BODY_SLAM_MODULE_ID,
}
Handler.start = Handler._startMassiveGeezerBodySlam
Handler.actions = {
	impact = Handler._impactMassiveGeezerBodySlam,
}
Handler.requiresHandle = false

return Handler
