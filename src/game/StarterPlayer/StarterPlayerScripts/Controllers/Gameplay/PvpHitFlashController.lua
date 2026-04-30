local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local ACTIVE_PROFILE_ID = "main"
local REMOTES_FOLDER_NAME = "Remotes"
local PVP_FOLDER_NAME = "PvP"
local PLAYER_HIT_CONFIRMED_REMOTE_NAME = "PlayerHitConfirmed"
local BODY_PARTS_FOLDER_NAME = "CharacterBodyParts"
local HIT_FLASH_HIGHLIGHT_NAME = "PvpHitFlashHighlight"
local FLASH_COLOR = Color3.fromRGB(255, 35, 35)
local FLASH_FADE_SECONDS = 0.18
local FLASH_FILL_TRANSPARENCY = 0.35
local FLASH_OUTLINE_TRANSPARENCY = 0.15

type PlayerHitConfirmedPayload = {
	attacker: Player?,
	attackerUserId: number?,
	target: Player?,
	targetUserId: number?,
	damage: number,
	serverTime: number?,
	position: Vector3?,
	targetPosition: Vector3?,
}

local PvpHitFlashController = {
	_started = false,
	_remote = nil :: RemoteEvent?,
	_hitConnection = nil :: RBXScriptConnection?,
	_activeTweens = {} :: { [Instance]: Tween },
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
end

local function warnWithPrefix(message: string)
	Logger.Warn(string.format("[PvpHitFlashController] %s", message))
end

local function resolveTargetPlayer(payload: PlayerHitConfirmedPayload): Player?
	local target = payload.target
	if typeof(target) == "Instance" and target:IsA("Player") then
		return target
	end

	local targetUserId = tonumber(payload.targetUserId)
	if targetUserId == nil then
		return nil
	end

	return Players:GetPlayerByUserId(targetUserId)
end

local function resolveFlashTargets(character: Model): { Instance }
	local targets = { character }
	local bodyPartsFolder = character:FindFirstChild(BODY_PARTS_FOLDER_NAME)
	if bodyPartsFolder == nil then
		return targets
	end

	for _, child in ipairs(bodyPartsFolder:GetChildren()) do
		if child:IsA("Model") then
			table.insert(targets, child)
		end
	end

	return targets
end

function PvpHitFlashController:_ensureRemote(): RemoteEvent?
	if self._remote then
		return self._remote
	end

	local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, 30)
	if not (remotesFolder and remotesFolder:IsA("Folder")) then
		warnWithPrefix("ReplicatedStorage.Remotes is missing.")
		return nil
	end

	local pvpFolder = remotesFolder:WaitForChild(PVP_FOLDER_NAME, 30)
	if not (pvpFolder and pvpFolder:IsA("Folder")) then
		warnWithPrefix("ReplicatedStorage.Remotes.PvP is missing.")
		return nil
	end

	local remote = pvpFolder:WaitForChild(PLAYER_HIT_CONFIRMED_REMOTE_NAME, 30)
	if not (remote and remote:IsA("RemoteEvent")) then
		warnWithPrefix("PvP.PlayerHitConfirmed is missing.")
		return nil
	end

	self._remote = remote
	return remote
end

function PvpHitFlashController:_ensureHighlight(target: Instance): Highlight
	local existing = target:FindFirstChild(HIT_FLASH_HIGHLIGHT_NAME)
	if existing and existing:IsA("Highlight") then
		existing.Adornee = target
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = HIT_FLASH_HIGHLIGHT_NAME
	highlight.Adornee = target
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = FLASH_COLOR
	highlight.OutlineColor = FLASH_COLOR
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.Enabled = false
	highlight.Parent = target
	return highlight
end

function PvpHitFlashController:_flashTarget(target: Instance?)
	if target == nil or target.Parent == nil then
		return
	end

	local activeTween = self._activeTweens[target]
	if activeTween then
		activeTween:Cancel()
		self._activeTweens[target] = nil
	end

	local highlight = self:_ensureHighlight(target)
	highlight.FillColor = FLASH_COLOR
	highlight.OutlineColor = FLASH_COLOR
	highlight.FillTransparency = FLASH_FILL_TRANSPARENCY
	highlight.OutlineTransparency = FLASH_OUTLINE_TRANSPARENCY
	highlight.Enabled = true

	local tween = TweenService:Create(highlight, TweenInfo.new(FLASH_FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FillTransparency = 1,
		OutlineTransparency = 1,
	})
	self._activeTweens[target] = tween
	tween.Completed:Connect(function()
		if self._activeTweens[target] ~= tween then
			return
		end

		self._activeTweens[target] = nil
		if highlight.Parent ~= nil then
			highlight.Enabled = false
		end
	end)
	tween:Play()
end

function PvpHitFlashController:_handlePlayerHitConfirmed(payload: PlayerHitConfirmedPayload)
	if typeof(payload) ~= "table" or typeof(payload.damage) ~= "number" or payload.damage <= 0 then
		return
	end

	local targetPlayer = resolveTargetPlayer(payload)
	if targetPlayer == nil then
		return
	end

	local character = targetPlayer.Character
	if character == nil then
		return
	end

	for _, target in ipairs(resolveFlashTargets(character)) do
		self:_flashTarget(target)
	end
end

function PvpHitFlashController:OnStart()
	if self._started then
		return
	end
	self._started = true

	if not isEnabledForPlace() then
		return
	end

	local remote = self:_ensureRemote()
	if remote == nil then
		return
	end

	if self._hitConnection then
		self._hitConnection:Disconnect()
	end

	self._hitConnection = remote.OnClientEvent:Connect(function(payload: PlayerHitConfirmedPayload)
		self:_handlePlayerHitConfirmed(payload)
	end)
end

return PvpHitFlashController
