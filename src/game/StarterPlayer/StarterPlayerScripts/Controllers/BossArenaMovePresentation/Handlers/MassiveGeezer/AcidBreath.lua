type ActiveRecord = any
type PresentationEvent = any

local Constants = {
	ModuleIds = {
		MASSIVE_GEEZER_ACID_BREATH_MODULE_ID = "Moves.MassiveGeezer.AcidBreath",
	},
	Vfx = {
		MASSIVE_GEEZER_ACID_BREATH_HEAD_VFX_NAME = "Head",
		MASSIVE_GEEZER_ACID_BREATH_VFX_NAME = "AcidBreath",
		MASSIVE_GEEZER_VFX_FOLDER_NAME = "MassiveGeezer",
	},
	Timing = {
		ACID_BREATH_POISON_FADE_IN_SECONDS = 0.2,
		ACID_BREATH_POISON_FADE_OUT_SECONDS = 0.45,
		MASSIVE_GEEZER_ACID_BREATH_HEAD_LIFETIME_SECONDS = 3,
	},
	Gui = {
		ACID_BREATH_POISON_BLUR_NAME = "AcidBreathPoisonBlur",
		ACID_BREATH_POISON_BLUR_SIZE = 15,
		ACID_BREATH_POISON_GUI_NAME = "AcidBreathPoisonScreenEffect",
	},
	Values = {
		ACID_BREATH_POISON_OVERLAY_TRANSPARENCY = 0.35,
	},
}

local ACID_BREATH_POISON_BLUR_NAME = Constants.Gui.ACID_BREATH_POISON_BLUR_NAME
local ACID_BREATH_POISON_BLUR_SIZE = Constants.Gui.ACID_BREATH_POISON_BLUR_SIZE
local ACID_BREATH_POISON_FADE_IN_SECONDS = Constants.Timing.ACID_BREATH_POISON_FADE_IN_SECONDS
local ACID_BREATH_POISON_FADE_OUT_SECONDS = Constants.Timing.ACID_BREATH_POISON_FADE_OUT_SECONDS
local ACID_BREATH_POISON_GUI_NAME = Constants.Gui.ACID_BREATH_POISON_GUI_NAME
local ACID_BREATH_POISON_OVERLAY_TRANSPARENCY = Constants.Values.ACID_BREATH_POISON_OVERLAY_TRANSPARENCY
local MASSIVE_GEEZER_ACID_BREATH_HEAD_LIFETIME_SECONDS = Constants.Timing.MASSIVE_GEEZER_ACID_BREATH_HEAD_LIFETIME_SECONDS
local MASSIVE_GEEZER_ACID_BREATH_HEAD_VFX_NAME = Constants.Vfx.MASSIVE_GEEZER_ACID_BREATH_HEAD_VFX_NAME
local MASSIVE_GEEZER_ACID_BREATH_MODULE_ID = Constants.ModuleIds.MASSIVE_GEEZER_ACID_BREATH_MODULE_ID
local MASSIVE_GEEZER_ACID_BREATH_VFX_NAME = Constants.Vfx.MASSIVE_GEEZER_ACID_BREATH_VFX_NAME
local MASSIVE_GEEZER_VFX_FOLDER_NAME = Constants.Vfx.MASSIVE_GEEZER_VFX_FOLDER_NAME

local Handler = {}

function Handler:_cancelAcidBreathPoisonTweens()
	for _, tween in ipairs(self._acidBreathPoisonTweens) do
		tween:Cancel()
	end
	table.clear(self._acidBreathPoisonTweens)
end

function Handler:_getAcidBreathPoisonGui()
	local localPlayer = self.Players.LocalPlayer
	if localPlayer == nil then
		return nil, nil
	end

	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return nil, nil
	end

	local gui = playerGui:FindFirstChild(ACID_BREATH_POISON_GUI_NAME)
	if gui and not gui:IsA("ScreenGui") then
		gui:Destroy()
		gui = nil
	end
	if gui == nil then
		local createdGui = Instance.new("ScreenGui")
		createdGui.Name = ACID_BREATH_POISON_GUI_NAME
		createdGui.IgnoreGuiInset = true
		createdGui.ResetOnSpawn = false
		createdGui.DisplayOrder = 1000
		createdGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		createdGui.Parent = playerGui
		gui = createdGui
	end

	local overlay = gui:FindFirstChild("Overlay")
	if overlay and not overlay:IsA("Frame") then
		overlay:Destroy()
		overlay = nil
	end
	if overlay == nil then
		local createdOverlay = Instance.new("Frame")
		createdOverlay.Name = "Overlay"
		createdOverlay.AnchorPoint = Vector2.new(0.5, 0.5)
		createdOverlay.Position = UDim2.fromScale(0.5, 0.5)
		createdOverlay.Size = UDim2.fromScale(1, 1)
		createdOverlay.BorderSizePixel = 0
		createdOverlay.BackgroundColor3 = Color3.fromRGB(87, 190, 90)
		createdOverlay.BackgroundTransparency = 1
		createdOverlay.Parent = gui
		overlay = createdOverlay
	end

	return gui, overlay :: Frame
end

function Handler:_getAcidBreathPoisonBlur()
	local existing = self.Lighting:FindFirstChild(ACID_BREATH_POISON_BLUR_NAME)
	if existing and existing:IsA("BlurEffect") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local blur = Instance.new("BlurEffect")
	blur.Name = ACID_BREATH_POISON_BLUR_NAME
	blur.Size = 0
	blur.Enabled = false
	blur.Parent = self.Lighting
	return blur
end

function Handler:_applyAcidBreathPoisonScreen(durationSeconds: number)
	local _, overlay = self:_getAcidBreathPoisonGui()
	if overlay == nil then
		return
	end

	local blur = self:_getAcidBreathPoisonBlur()
	self._acidBreathPoisonToken += 1
	local token = self._acidBreathPoisonToken
	self:_cancelAcidBreathPoisonTweens()

	overlay.Visible = true
	blur.Enabled = true

	local fadeInInfo = TweenInfo.new(ACID_BREATH_POISON_FADE_IN_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	local overlayIn = self.TweenService:Create(overlay, fadeInInfo, {
		BackgroundTransparency = ACID_BREATH_POISON_OVERLAY_TRANSPARENCY,
	})
	local blurIn = self.TweenService:Create(blur, fadeInInfo, {
		Size = ACID_BREATH_POISON_BLUR_SIZE,
	})
	table.insert(self._acidBreathPoisonTweens, overlayIn)
	table.insert(self._acidBreathPoisonTweens, blurIn)
	overlayIn:Play()
	blurIn:Play()

	task.delay(math.max(0.1, durationSeconds), function()
		if self._acidBreathPoisonToken ~= token then
			return
		end

		self:_cancelAcidBreathPoisonTweens()
		local fadeOutInfo = TweenInfo.new(
			ACID_BREATH_POISON_FADE_OUT_SECONDS,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.Out
		)
		local overlayOut = self.TweenService:Create(overlay, fadeOutInfo, {
			BackgroundTransparency = 1,
		})
		local blurOut = self.TweenService:Create(blur, fadeOutInfo, {
			Size = 0,
		})
		table.insert(self._acidBreathPoisonTweens, overlayOut)
		table.insert(self._acidBreathPoisonTweens, blurOut)
		overlayOut:Play()
		blurOut:Play()

		overlayOut.Completed:Once(function()
			if self._acidBreathPoisonToken ~= token then
				return
			end

			overlay.Visible = false
			blur.Enabled = false
			table.clear(self._acidBreathPoisonTweens)
		end)
	end)
end

function Handler:_startAcidBreath(record: ActiveRecord, event: PresentationEvent)
	local bossModel = event.bossModel
	if bossModel == nil or bossModel.Parent == nil then
		self:_cleanupRecord(record)
		return
	end

	local bossHead = self:resolveBossHeadPart(bossModel)
	if bossHead == nil then
		self:warnWithPrefix("Acid Breath presentation could not resolve the live boss Head.")
		self:_cleanupRecord(record)
		return
	end

	local headSource = self:resolveBossVfxModel(
		MASSIVE_GEEZER_VFX_FOLDER_NAME,
		MASSIVE_GEEZER_ACID_BREATH_VFX_NAME,
		MASSIVE_GEEZER_ACID_BREATH_HEAD_VFX_NAME
	)
	if headSource == nil then
		self:warnWithPrefix("Acid Breath Head VFX model is missing from ReplicatedStorage.GameAssets.VFX.")
		self:_cleanupRecord(record)
		return
	end

	local payload = event.payload
	local scaleMultiplier = math.max(0.1, tonumber(payload and payload.scaleMultiplier) or 1)
	local castFolder = self:_ensureCastFolder(record)
	local headModel = headSource:Clone()
	headModel:ScaleTo(scaleMultiplier)
	self:prepareAttachedEffectModel(headModel)
	self:scaleAttachedSounds(headModel, scaleMultiplier)
	headModel.Parent = castFolder
	record.acidBreathHeadModel = headModel

	if not self:attachEffectModel(headModel, bossHead) then
		self:warnWithPrefix("Acid Breath Head VFX model is missing BasePart configuration.")
		self:_cleanupRecord(record)
		return
	end

	self:playTimedSounds(headModel, scaleMultiplier)
end

function Handler:_shootAcidBreath(record: ActiveRecord)
	local headModel = record.acidBreathHeadModel
	if headModel == nil or headModel.Parent == nil then
		return
	end

	self:emitEffectInstance(headModel, MASSIVE_GEEZER_ACID_BREATH_HEAD_LIFETIME_SECONDS)
end

function Handler:_poisonAcidBreath(event: PresentationEvent)
	local localPlayer = self.Players.LocalPlayer
	local payload = event.payload
	if localPlayer == nil or typeof(payload) ~= "table" then
		return
	end
	if math.floor(tonumber(payload.targetUserId) or 0) ~= localPlayer.UserId then
		return
	end

	self:_applyAcidBreathPoisonScreen(math.max(0.1, tonumber(payload.durationSeconds) or 2.5))
end

Handler.moduleIds = {
	MASSIVE_GEEZER_ACID_BREATH_MODULE_ID,
}
Handler.start = Handler._startAcidBreath
Handler.actions = {
	shoot = Handler._shootAcidBreath,
	poison = function(self, _record, event)
		self:_poisonAcidBreath(event)
	end,
}
Handler.actionsWithoutRecord = {
	poison = function(self, event)
		self:_poisonAcidBreath(event)
	end,
}
Handler.requiredParentFields = {
	"acidBreathHeadModel",
}
Handler.requiresHandle = false

return Handler
