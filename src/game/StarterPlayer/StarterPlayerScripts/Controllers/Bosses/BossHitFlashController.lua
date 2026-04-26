local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local REMOTES_FOLDER_NAME = "Remotes"
local BOSS_ARENA_FOLDER_NAME = "BossArena"
local BOSS_HIT_CONFIRMED_REMOTE_NAME = "BossHitConfirmed"
local ACTIVE_PROFILE_ID = "boss_arena"
local ACTIVE_BOSS_MODEL_NAME = "ActiveBoss"
local HIT_FLASH_HIGHLIGHT_NAME = "BossHitFlashHighlight"
local FLASH_COLOR = Color3.fromRGB(255, 35, 35)
local FLASH_FADE_SECONDS = 0.18
local FLASH_FILL_TRANSPARENCY = 0.35
local FLASH_OUTLINE_TRANSPARENCY = 0.15

type BossHitConfirmedPayload = {
	bossId: string,
	damage: number,
	attackerUserId: number,
	serverTime: number,
}

local BossHitFlashController = {
	_started = false,
	_remote = nil :: RemoteEvent?,
	_hitConnection = nil :: RBXScriptConnection?,
	_activeTween = nil :: Tween?,
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
end

local function warnWithPrefix(message: string)
	Logger.Warn(string.format("[BossHitFlashController] %s", message))
end

function BossHitFlashController:_ensureRemote(): RemoteEvent?
	if self._remote then
		return self._remote
	end

	local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, 30)
	if not (remotesFolder and remotesFolder:IsA("Folder")) then
		warnWithPrefix("ReplicatedStorage.Remotes is missing.")
		return nil
	end

	local bossArenaFolder = remotesFolder:WaitForChild(BOSS_ARENA_FOLDER_NAME, 30)
	if not (bossArenaFolder and bossArenaFolder:IsA("Folder")) then
		warnWithPrefix("ReplicatedStorage.Remotes.BossArena is missing.")
		return nil
	end

	local remote = bossArenaFolder:WaitForChild(BOSS_HIT_CONFIRMED_REMOTE_NAME, 30)
	if not (remote and remote:IsA("RemoteEvent")) then
		warnWithPrefix("BossArena.BossHitConfirmed is missing.")
		return nil
	end

	self._remote = remote
	return remote
end

function BossHitFlashController:_resolveActiveBoss(): Model?
	local activeBoss = Workspace:FindFirstChild(ACTIVE_BOSS_MODEL_NAME)
	if activeBoss and activeBoss:IsA("Model") then
		return activeBoss
	end

	return nil
end

function BossHitFlashController:_ensureHighlight(bossModel: Model): Highlight
	local existing = bossModel:FindFirstChild(HIT_FLASH_HIGHLIGHT_NAME)
	if existing and existing:IsA("Highlight") then
		existing.Adornee = bossModel
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = HIT_FLASH_HIGHLIGHT_NAME
	highlight.Adornee = bossModel
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = FLASH_COLOR
	highlight.OutlineColor = FLASH_COLOR
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.Enabled = false
	highlight.Parent = bossModel
	return highlight
end

function BossHitFlashController:_flashBoss()
	local bossModel = self:_resolveActiveBoss()
	if bossModel == nil then
		return
	end

	if self._activeTween then
		self._activeTween:Cancel()
		self._activeTween = nil
	end

	local highlight = self:_ensureHighlight(bossModel)
	highlight.FillColor = FLASH_COLOR
	highlight.OutlineColor = FLASH_COLOR
	highlight.FillTransparency = FLASH_FILL_TRANSPARENCY
	highlight.OutlineTransparency = FLASH_OUTLINE_TRANSPARENCY
	highlight.Enabled = true

	local tween = TweenService:Create(highlight, TweenInfo.new(FLASH_FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FillTransparency = 1,
		OutlineTransparency = 1,
	})
	self._activeTween = tween
	tween.Completed:Connect(function()
		if self._activeTween ~= tween then
			return
		end

		self._activeTween = nil
		if highlight.Parent ~= nil then
			highlight.Enabled = false
		end
	end)
	tween:Play()
end

function BossHitFlashController:_handleBossHitConfirmed(hitPayload: BossHitConfirmedPayload)
	if typeof(hitPayload) ~= "table" or typeof(hitPayload.damage) ~= "number" or hitPayload.damage <= 0 then
		return
	end

	self:_flashBoss()
end

function BossHitFlashController:OnStart()
	if self._started then
		return
	end
	self._started = true

	if RunService:IsClient() ~= true or not isEnabledForPlace() then
		return
	end

	local remote = self:_ensureRemote()
	if remote == nil then
		return
	end

	if self._hitConnection then
		self._hitConnection:Disconnect()
	end

	self._hitConnection = remote.OnClientEvent:Connect(function(hitPayload: BossHitConfirmedPayload)
		self:_handleBossHitConfirmed(hitPayload)
	end)
end

return BossHitFlashController
