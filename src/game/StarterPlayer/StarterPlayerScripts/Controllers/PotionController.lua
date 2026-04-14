local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local Signal = require(ReplicatedStorage.Common.Signal)
local Schema = require(ReplicatedStorage.Lists.Schema)
local PotionConfig = require(ReplicatedStorage.Shared.Config.PotionConfig)
local PotionPresentation = require(ReplicatedStorage.Shared.UI.PotionPresentation)
local ViewportModelRenderer = require(ReplicatedStorage.Shared.UI.ViewportModelRenderer)
local DataController = require(script.Parent.DataController)

local LOCAL_PLAYER = Players.LocalPlayer
local POTIONS_DATA_KEY = Schema.Potions and Schema.Potions.key or "potions"
local REMOTES_FOLDER_NAME = "Remotes"
local POTIONS_REMOTES_FOLDER_NAME = "Potions"
local GET_STATE_REMOTE_NAME = "GetPotionState"
local USE_POTION_REMOTE_NAME = "UsePotion"
local TOGGLE_FAVORITE_REMOTE_NAME = "ToggleFavoriteOwnedPotion"
local SELL_OWNED_REMOTE_NAME = "SellOwnedPotion"
local UPDATED_REMOTE_NAME = "PotionUpdated"
local OWNED_ID_PREFIX = "potion_"
local HUD_FRAME_NAME = "PotionHud"
local HUD_TICK_INTERVAL = 0.2

type ActivePotionEntry = {
	potionId: string,
	expiresAt: number,
}

type PotionClientState = {
	ownedPotions: { [string]: any },
	activePotions: { [string]: ActivePotionEntry },
	message: string?,
}

local PotionController = {}

PotionController.StateUpdated = Signal.new()

local function showNotification(text: string, title: string?)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = title or "Potions",
			Text = tostring(text),
			Duration = 4,
		})
	end)
end

local function cloneOwnedPotions(source: any): { [string]: any }
	local ownedPotions = {}
	if typeof(source) ~= "table" then
		return ownedPotions
	end

	for potionId, record in pairs(source) do
		if typeof(record) == "table" then
			local normalizedId = PotionConfig.NormalizeId(record.potionId or potionId)
			if normalizedId ~= nil then
				ownedPotions[normalizedId] = {
					potionId = normalizedId,
					amount = math.max(0, math.floor(tonumber(record.amount) or 0)),
					isFavorite = record.isFavorite == true,
				}
			end
		end
	end

	return ownedPotions
end

local function cloneActivePotionsFromPayload(source: any): { [string]: ActivePotionEntry }
	local activePotions = {}
	if typeof(source) ~= "table" then
		return activePotions
	end

	for potionId, entry in pairs(source) do
		if typeof(entry) == "table" then
			local normalizedId = PotionConfig.NormalizeId(entry.potionId or potionId)
			local expiresAt = tonumber(entry.expiresAt)
			if normalizedId ~= nil and expiresAt ~= nil and expiresAt > Workspace:GetServerTimeNow() then
				activePotions[normalizedId] = {
					potionId = normalizedId,
					expiresAt = expiresAt,
				}
			end
		end
	end

	return activePotions
end

local function cloneActivePotionsFromRemaining(source: any): { [string]: ActivePotionEntry }
	local activePotions = {}
	if typeof(source) ~= "table" then
		return activePotions
	end

	local now = Workspace:GetServerTimeNow()
	for potionId, remainingSeconds in pairs(source) do
		local normalizedId = PotionConfig.NormalizeId(potionId)
		local resolvedRemainingSeconds = math.max(0, math.floor(tonumber(remainingSeconds) or 0))
		if normalizedId ~= nil and resolvedRemainingSeconds > 0 then
			activePotions[normalizedId] = {
				potionId = normalizedId,
				expiresAt = now + resolvedRemainingSeconds,
			}
		end
	end

	return activePotions
end

function PotionController:_ensureState()
	if self._started then
		return
	end

	self._started = true
	self._state = {
		ownedPotions = {},
		activePotions = {},
		message = nil,
	} :: PotionClientState
	self._ui = {
		root = nil,
		slots = {},
	}
	self._remotes = {}
	self._hudRenderKeys = {}
	self._hasLiveServerState = false
	self._hudConnection = nil
	self._hudTickAccumulator = 0
end

function PotionController:_getState(): PotionClientState
	self:_ensureState()
	return self._state
end

function PotionController:_getPotionsRemotesFolder(): Folder?
	local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if not (remotesFolder and remotesFolder:IsA("Folder")) then
		return nil
	end

	local potionsFolder = remotesFolder:FindFirstChild(POTIONS_REMOTES_FOLDER_NAME)
	if potionsFolder and potionsFolder:IsA("Folder") then
		return potionsFolder
	end

	return nil
end

function PotionController:_ensureRemotes(): boolean
	if self._remotes.getState
		and self._remotes.usePotion
		and self._remotes.toggleFavorite
		and self._remotes.sellOwned
		and self._remotes.updated
	then
		return true
	end

	local potionsFolder = self:_getPotionsRemotesFolder()
	if not potionsFolder then
		return false
	end

	local getStateRemote = potionsFolder:FindFirstChild(GET_STATE_REMOTE_NAME)
	local usePotionRemote = potionsFolder:FindFirstChild(USE_POTION_REMOTE_NAME)
	local toggleFavoriteRemote = potionsFolder:FindFirstChild(TOGGLE_FAVORITE_REMOTE_NAME)
	local sellOwnedRemote = potionsFolder:FindFirstChild(SELL_OWNED_REMOTE_NAME)
	local updatedRemote = potionsFolder:FindFirstChild(UPDATED_REMOTE_NAME)

	if not (getStateRemote and getStateRemote:IsA("RemoteFunction")) then
		return false
	end
	if not (usePotionRemote and usePotionRemote:IsA("RemoteFunction")) then
		return false
	end
	if not (toggleFavoriteRemote and toggleFavoriteRemote:IsA("RemoteFunction")) then
		return false
	end
	if not (sellOwnedRemote and sellOwnedRemote:IsA("RemoteFunction")) then
		return false
	end
	if not (updatedRemote and updatedRemote:IsA("RemoteEvent")) then
		return false
	end

	self._remotes.getState = getStateRemote
	self._remotes.usePotion = usePotionRemote
	self._remotes.toggleFavorite = toggleFavoriteRemote
	self._remotes.sellOwned = sellOwnedRemote
	self._remotes.updated = updatedRemote
	return true
end

function PotionController:_cacheUi()
	if self._ui.root and self._ui.root.Parent then
		return
	end

	local playerGui = LOCAL_PLAYER:FindFirstChild("PlayerGui")
	if not playerGui then
		return
	end

	local mainInterface = playerGui:FindFirstChild("MainInterface")
	if not (mainInterface and mainInterface:IsA("ScreenGui")) then
		return
	end

	local hud = mainInterface:FindFirstChild(HUD_FRAME_NAME)
	if not (hud and hud:IsA("GuiObject")) then
		return
	end

	self._ui.root = hud
	self._ui.slots = {}

	for _, config in ipairs(PotionConfig.GetAll()) do
		local slot = hud:FindFirstChild(config.id)
		if slot and slot:IsA("GuiObject") then
			self._ui.slots[config.id] = {
				root = slot,
				timer = slot:FindFirstChild("Timer"),
				nameLabel = slot:FindFirstChild("Label"),
				viewport = slot:FindFirstChild("Viewport"),
				icon = slot:FindFirstChild("Icon"),
			}
		end
	end

	self:_renderHudAssets()
end

function PotionController:_renderHudAssets()
	for _, config in ipairs(PotionConfig.GetAll()) do
		local slot = self._ui.slots[config.id]
		if not slot then
			continue
		end

		if slot.nameLabel and slot.nameLabel:IsA("TextLabel") then
			slot.nameLabel.Text = config.label
		end

		local preview = PotionPresentation.BuildPreviewPresentation({
			potionId = config.id,
		})
		local bundleModel = preview and preview.bundleModel or nil
		local renderKey = config.id

		if slot.viewport and slot.viewport:IsA("ViewportFrame") and self._hudRenderKeys[config.id] ~= renderKey then
			ViewportModelRenderer.RenderBundle(slot.viewport, bundleModel)
			self._hudRenderKeys[config.id] = renderKey
		end
	end
end

function PotionController:_emitStateUpdated()
	self.StateUpdated:Fire(self._state)
end

function PotionController:_refreshHud()
	self:_cacheUi()

	local root = self._ui.root
	if not root then
		return
	end

	local anyVisible = false

	for _, config in ipairs(PotionConfig.GetAll()) do
		local slot = self._ui.slots[config.id]
		if not slot then
			continue
		end

		local remainingSeconds = self:GetRemainingSeconds(config.id)
		local isActive = remainingSeconds > 0
		slot.root.Visible = isActive
		anyVisible = anyVisible or isActive

		if slot.timer and slot.timer:IsA("TextLabel") then
			slot.timer.Text = if isActive
				then PotionPresentation.FormatDuration(remainingSeconds)
				else "00:00"
		end
	end

	root.Visible = anyVisible
end

function PotionController:_pruneExpiredActives(): boolean
	local activePotions = self._state.activePotions
	local now = Workspace:GetServerTimeNow()
	local didChange = false

	for potionId, entry in pairs(activePotions) do
		if typeof(entry) ~= "table" or (tonumber(entry.expiresAt) or 0) <= now then
			activePotions[potionId] = nil
			didChange = true
		end
	end

	return didChange
end

function PotionController:_applyDataState(rawPotionsState: any)
	self:_ensureState()

	local ownedPotions = if typeof(rawPotionsState) == "table"
		then cloneOwnedPotions(rawPotionsState.ownedByPotionId)
		else {}
	self._state.ownedPotions = ownedPotions

	if not self._hasLiveServerState then
		self._state.activePotions = if typeof(rawPotionsState) == "table"
			then cloneActivePotionsFromRemaining(rawPotionsState.activeByPotionId)
			else {}
	end

	if self:_pruneExpiredActives() then
		self._hasLiveServerState = self._hasLiveServerState and next(self._state.activePotions) ~= nil
	end

	self:_refreshHud()
	self:_emitStateUpdated()
end

function PotionController:_applyServerState(state: any)
	if typeof(state) ~= "table" then
		return
	end

	self:_ensureState()
	self._state = {
		ownedPotions = cloneOwnedPotions(state.ownedPotions),
		activePotions = cloneActivePotionsFromPayload(state.activePotions),
		message = if typeof(state.message) == "string" and state.message ~= "" then state.message else nil,
	}
	self._hasLiveServerState = true
	self:_refreshHud()
	self:_emitStateUpdated()
end

function PotionController:_invokeRemote(remote: RemoteFunction, payload: any?): any?
	local ok, result = pcall(function()
		if payload ~= nil then
			return remote:InvokeServer(payload)
		end

		return remote:InvokeServer()
	end)
	if not ok then
		warn(string.format("[PotionController] Remote %s failed: %s", remote.Name, tostring(result)))
		return nil
	end

	return result
end

function PotionController:RequestState()
	self:_ensureState()
	if not self:_ensureRemotes() then
		return
	end

	local result = self:_invokeRemote(self._remotes.getState)
	if typeof(result) ~= "table" or result.ok ~= true then
		return
	end

	self:_applyServerState(result.state)
end

function PotionController:GetState(): PotionClientState
	return self:_getState()
end

function PotionController:GetOwnedPotions(): { [string]: any }
	return self:_getState().ownedPotions
end

function PotionController:GetActivePotions(): { [string]: ActivePotionEntry }
	return self:_getState().activePotions
end

function PotionController.BuildOwnedId(potionId: string?): string?
	local normalizedId = PotionConfig.NormalizeId(potionId)
	if normalizedId == nil then
		return nil
	end

	return OWNED_ID_PREFIX .. normalizedId
end

function PotionController.IsPotionOwnedId(ownedId: string?): boolean
	return typeof(ownedId) == "string" and string.find(ownedId, OWNED_ID_PREFIX, 1, true) == 1
end

function PotionController.GetPotionIdFromOwnedId(ownedId: string?): string?
	if not PotionController.IsPotionOwnedId(ownedId) then
		return nil
	end

	return PotionConfig.NormalizeId(string.sub(ownedId, string.len(OWNED_ID_PREFIX) + 1))
end

function PotionController:GetOwnedRecordByOwnedId(ownedId: string?): any?
	local potionId = PotionController.GetPotionIdFromOwnedId(ownedId)
	if potionId == nil then
		return nil
	end

	return self:GetOwnedPotions()[potionId]
end

function PotionController:GetRemainingSeconds(potionId: string?): number
	local normalizedId = PotionConfig.NormalizeId(potionId)
	if normalizedId == nil then
		return 0
	end

	local entry = self:GetActivePotions()[normalizedId]
	local expiresAt = tonumber(entry and entry.expiresAt)
	if expiresAt == nil then
		return 0
	end

	return math.max(0, math.ceil(expiresAt - Workspace:GetServerTimeNow()))
end

function PotionController:IsActive(potionId: string?): boolean
	return self:GetRemainingSeconds(potionId) > 0
end

function PotionController:GetRuntimeBonuses()
	local bonuses = {
		passiveIncomeMultiplier = 1,
		luckBonus = 0,
		rollSpeedBonus = 0,
	}

	for _, config in ipairs(PotionConfig.GetAll()) do
		if self:IsActive(config.id) then
			if tonumber(config.passiveIncomeMultiplier) and config.passiveIncomeMultiplier > 1 then
				bonuses.passiveIncomeMultiplier *= config.passiveIncomeMultiplier
			end
			bonuses.luckBonus += tonumber(config.luckBonus) or 0
			bonuses.rollSpeedBonus += tonumber(config.rollSpeedBonus) or 0
		end
	end

	return bonuses
end

function PotionController:UsePotion(potionId: string): boolean
	self:_ensureState()
	if not self:_ensureRemotes() then
		return false
	end

	local normalizedId = PotionConfig.NormalizeId(potionId)
	if normalizedId == nil then
		return false
	end

	local result = self:_invokeRemote(self._remotes.usePotion, {
		potionId = normalizedId,
	})
	if typeof(result) ~= "table" then
		showNotification("Potion use returned an invalid response.")
		return false
	end

	if typeof(result.state) == "table" then
		self:_applyServerState(result.state)
	end

	showNotification(tostring(result.message or (result.ok and "Potion used." or "Could not use that potion.")))
	return result.ok == true
end

function PotionController:ToggleFavorite(potionId: string, isFavorite: boolean?): boolean
	self:_ensureState()
	if not self:_ensureRemotes() then
		return false
	end

	local normalizedId = PotionConfig.NormalizeId(potionId)
	if normalizedId == nil then
		return false
	end

	local result = self:_invokeRemote(self._remotes.toggleFavorite, {
		potionId = normalizedId,
		isFavorite = isFavorite,
	})
	if typeof(result) ~= "table" then
		showNotification("Potion favorite returned an invalid response.")
		return false
	end

	if typeof(result.state) == "table" then
		self:_applyServerState(result.state)
	end

	showNotification(tostring(result.message or (result.ok and "Potion favorite updated." or "Could not update potion favorite state.")))
	return result.ok == true
end

function PotionController:SellPotion(potionId: string, quantity: number): boolean
	self:_ensureState()
	if not self:_ensureRemotes() then
		return false
	end

	local normalizedId = PotionConfig.NormalizeId(potionId)
	if normalizedId == nil then
		return false
	end

	local result = self:_invokeRemote(self._remotes.sellOwned, {
		potionId = normalizedId,
		quantity = quantity,
	})
	if typeof(result) ~= "table" then
		showNotification("Potion sell returned an invalid response.")
		return false
	end

	if typeof(result.state) == "table" then
		self:_applyServerState(result.state)
	end

	showNotification(tostring(result.message or (result.ok and "Sold potion uses." or "Could not sell that potion.")))
	return result.ok == true
end

function PotionController:OnStart()
	self:_ensureState()
	self:_cacheUi()

	DataController.DataReceived:Connect(function(data)
		self:_applyDataState(if typeof(data) == "table" then data[POTIONS_DATA_KEY] else nil)
	end)

	DataController.DataUpdated:Connect(function(key)
		if key == POTIONS_DATA_KEY then
			self:_applyDataState(DataController:Get(POTIONS_DATA_KEY))
		end
	end)

	task.spawn(function()
		while not self:_ensureRemotes() do
			task.wait(0.25)
		end

		self._remotes.updated.OnClientEvent:Connect(function(state)
			self:_applyServerState(state)
		end)

		self:RequestState()
	end)

	self._hudConnection = RunService.Heartbeat:Connect(function(deltaTime)
		self._hudTickAccumulator += deltaTime
		if self._hudTickAccumulator < HUD_TICK_INTERVAL then
			return
		end

		self._hudTickAccumulator = 0
		if self:_pruneExpiredActives() then
			self:_emitStateUpdated()
		end

		self:_refreshHud()
	end)
end

return PotionController
