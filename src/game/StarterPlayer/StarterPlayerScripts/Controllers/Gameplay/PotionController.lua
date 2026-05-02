local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Signal = require(ReplicatedStorage.Common.Signal)
local PotionRuntimeBonuses = require(ReplicatedStorage.Shared.Character.PotionRuntimeBonuses)
local Schema = require(ReplicatedStorage.Lists.Schema)
local PotionConfig = require(ReplicatedStorage.Shared.Config.PotionConfig)
local Notify = require(ReplicatedStorage.Shared.UI.Notify)
local RemoteFunctionTimeout = require(ReplicatedStorage.Shared.Remotes.RemoteFunctionTimeout)
local ToggleSoundUtil = require(ReplicatedStorage.Shared.Audio.ToggleSoundUtil)
local PotionPresentation = require(ReplicatedStorage.Shared.UI.PotionPresentation)
local DataController = require(script.Parent.DataController)

local LOCAL_PLAYER = Players.LocalPlayer
local REMOTE_INVOKE_TIMEOUT_SECONDS = 8
local POTIONS_DATA_KEY = Schema.Potions and Schema.Potions.key or "potions"
local REMOTES_FOLDER_NAME = "Remotes"
local POTIONS_REMOTES_FOLDER_NAME = "Potions"
local GET_STATE_REMOTE_NAME = "GetPotionState"
local USE_POTION_REMOTE_NAME = "UsePotion"
local TOGGLE_FAVORITE_REMOTE_NAME = "ToggleFavoriteOwnedPotion"
local SELL_OWNED_REMOTE_NAME = "SellOwnedPotion"
local UPDATED_REMOTE_NAME = "PotionUpdated"
local OWNED_ID_PREFIX = "potion_"
local BUFFS_HOLDER_NAME = "BuffsHolder"
local HOVER_FRAME_NAME = "StatusEffectHover"
local TIMER_LABEL_NAME = "Time"
local STACK_LABEL_NAME = "Stack"
local HOVER_TITLE_LABEL_NAME = "BuffName"
local HOVER_BODY_LABEL_NAME = "Effect"
local HUD_TICK_INTERVAL = 0.2

local STUDIO_POTION_ID_BY_SLOT_NAME = table.freeze({
	Money1 = "money1",
	Money2 = "money2",
	Money3 = "money3",
	Money4 = "money4",
	Money5 = "money5",
	Luck1 = "luck1",
	Luck2 = "luck2",
	Luck3 = "luck3",
	Lucky4 = "luck4",
	Lucky5 = "luck5",
	Size1 = "size1",
	Size2 = "size2",
	Size3 = "size3",
	Size4 = "size4",
	Size5 = "size5",
	Speed1 = "rollSpeed1",
	Speed2 = "rollSpeed2",
	Speed3 = "rollSpeed3",
	Speed4 = "rollSpeed4",
	Speed5 = "rollSpeed5",
	Titanic = "titanic",
	Prismatic = "prismaticPotion",
	Magma = "magmaPotion",
	Corrupted = "corruptedPotion",
	Diamond = "diamondPotion",
})

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

local function showNotification(text: string)
	Notify.Show(text, {
		channel = "potions",
		duration = 4,
	})
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
				local existingRecord = ownedPotions[normalizedId]
				local amount = math.max(0, math.floor(tonumber(record.amount) or 0))
				if existingRecord then
					existingRecord.amount += amount
					existingRecord.isFavorite = existingRecord.isFavorite or (record.isFavorite == true)
				else
					ownedPotions[normalizedId] = {
						potionId = normalizedId,
						amount = amount,
						isFavorite = record.isFavorite == true,
					}
				end
			end
		end
	end

	return ownedPotions
end

local function normalizeActivePotions(activePotions: { [string]: ActivePotionEntry }): { [string]: ActivePotionEntry }
	local normalized = {}
	local now = Workspace:GetServerTimeNow()

	for potionId, entry in pairs(activePotions) do
		if typeof(entry) ~= "table" then
			continue
		end

		local config = PotionConfig.Get(entry.potionId or potionId)
		local expiresAt = tonumber(entry.expiresAt)
		if not config or not expiresAt or expiresAt <= now then
			continue
		end

		local currentEntry = normalized[config.id]
		if currentEntry == nil or expiresAt > currentEntry.expiresAt then
			normalized[config.id] = {
				potionId = config.id,
				expiresAt = expiresAt,
			}
		end
	end

	return normalized
end

local function areActivePotionMapsEqual(
	left: { [string]: ActivePotionEntry }?,
	right: { [string]: ActivePotionEntry }?
): boolean
	local leftMap = if typeof(left) == "table" then left else {}
	local rightMap = if typeof(right) == "table" then right else {}

	for potionId, entry in pairs(leftMap) do
		local rightEntry = rightMap[potionId]
		if typeof(entry) ~= "table" or typeof(rightEntry) ~= "table" then
			return false
		end
		if entry.potionId ~= rightEntry.potionId or entry.expiresAt ~= rightEntry.expiresAt then
			return false
		end
	end

	for potionId, entry in pairs(rightMap) do
		local leftEntry = leftMap[potionId]
		if typeof(entry) ~= "table" or typeof(leftEntry) ~= "table" then
			return false
		end
		if entry.potionId ~= leftEntry.potionId or entry.expiresAt ~= leftEntry.expiresAt then
			return false
		end
	end

	return true
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

	return normalizeActivePotions(activePotions)
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

	return normalizeActivePotions(activePotions)
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
		mainInterface = nil,
		root = nil,
		slotsByPotionId = {},
		slotOrder = {},
		hover = {
			root = nil,
			title = nil,
			body = nil,
		},
	}
	self._remotes = {}
	self._hasLiveServerState = false
	self._hudConnection = nil
	self._hudTickAccumulator = 0
	self._hoveredPotionId = nil
	self._hoverPositionConnection = nil
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

local function findNamedTextLabel(root: Instance, childName: string): TextLabel?
	local child = root:FindFirstChild(childName, true)
	if child and child:IsA("TextLabel") then
		return child
	end

	return nil
end

local function resolvePotionIdFromSlotName(slotName: string): string?
	return STUDIO_POTION_ID_BY_SLOT_NAME[slotName]
end

function PotionController:_hideHover()
	self._hoveredPotionId = nil

	local hover = self._ui.hover
	if hover and hover.root then
		hover.root.Visible = false
	end
end

function PotionController:_getHoverPresentation(potionId: string?)
	local normalizedId = PotionConfig.NormalizeId(potionId)
	if normalizedId == nil then
		return nil
	end

	local remainingSeconds = self:GetRemainingSeconds(normalizedId)
	if remainingSeconds <= 0 then
		return nil
	end

	return PotionPresentation.BuildStatusHoverPresentation({
		potionId = normalizedId,
		remainingSeconds = remainingSeconds,
	})
end

function PotionController:_updateHoverPosition()
	local hover = self._ui.hover
	local hoverRoot = hover and hover.root
	if not (hoverRoot and hoverRoot.Visible and hoverRoot.Parent) then
		return
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local insetTopLeft, insetBottomRight = GuiService:GetGuiInset()
	local viewportSize = camera.ViewportSize
	local availableWidth = math.max(0, viewportSize.X - insetTopLeft.X - insetBottomRight.X)
	local availableHeight = math.max(0, viewportSize.Y - insetTopLeft.Y - insetBottomRight.Y)
	local mouseLocation = UserInputService:GetMouseLocation()
	local adjustedMouseX = mouseLocation.X - insetTopLeft.X
	local adjustedMouseY = mouseLocation.Y - insetTopLeft.Y
	local hoverWidth = hoverRoot.AbsoluteSize.X
	local hoverHeight = hoverRoot.AbsoluteSize.Y
	local targetX = math.clamp(adjustedMouseX - hoverWidth, 0, math.max(0, availableWidth - hoverWidth))
	local targetY = math.clamp(
		adjustedMouseY - math.floor(hoverHeight * 0.5),
		0,
		math.max(0, availableHeight - hoverHeight)
	)

	hoverRoot.Position = UDim2.fromOffset(targetX, targetY)
end

function PotionController:_refreshHover()
	local hover = self._ui.hover
	local hoverRoot = hover and hover.root
	if not hoverRoot then
		return
	end

	local presentation = self:_getHoverPresentation(self._hoveredPotionId)
	if not presentation then
		self:_hideHover()
		return
	end

	if hover.title then
		hover.title.Text = presentation.titleText
	end
	if hover.body then
		hover.body.Text = presentation.bodyText
	end

	hoverRoot.Visible = true
	self:_updateHoverPosition()
end

function PotionController:_showHover(potionId: string?)
	local normalizedId = PotionConfig.NormalizeId(potionId)
	if normalizedId == nil then
		self:_hideHover()
		return
	end

	self._hoveredPotionId = normalizedId
	self:_refreshHover()
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

	local buffsHolder = mainInterface:FindFirstChild(BUFFS_HOLDER_NAME)
	if not (buffsHolder and buffsHolder:IsA("GuiObject")) then
		return
	end
	local hoverFrame = mainInterface:FindFirstChild(HOVER_FRAME_NAME)

	local slotsByPotionId = {}
	local slotOrder = {}
	for _, child in ipairs(buffsHolder:GetChildren()) do
		if not child:IsA("ImageButton") then
			continue
		end

		local potionId = resolvePotionIdFromSlotName(child.Name)
		local timerLabel = findNamedTextLabel(child, TIMER_LABEL_NAME)
		local stackLabel = findNamedTextLabel(child, STACK_LABEL_NAME)
		if potionId == nil or timerLabel == nil or slotsByPotionId[potionId] ~= nil then
			child.Visible = false
			continue
		end

		local slot = {
			potionId = potionId,
			root = child,
			timer = timerLabel,
			stack = stackLabel,
		}
		slotsByPotionId[potionId] = slot
		table.insert(slotOrder, slot)
	end

	for _, slot in ipairs(slotOrder) do
		local slotRoot = slot.root
		slotRoot.Visible = false

		slotRoot.MouseEnter:Connect(function()
			if not slotRoot.Visible then
				self:_hideHover()
				return
			end

			self:_showHover(slot.potionId)
		end)

		slotRoot.MouseLeave:Connect(function()
			if self._hoveredPotionId == slot.potionId then
				self:_hideHover()
			end
		end)
	end

	if hoverFrame and hoverFrame:IsA("GuiObject") then
		self._ui.hover = {
			root = hoverFrame,
			title = findNamedTextLabel(hoverFrame, HOVER_TITLE_LABEL_NAME),
			body = findNamedTextLabel(hoverFrame, HOVER_BODY_LABEL_NAME),
		}
		hoverFrame.Visible = false
	end

	self._ui.mainInterface = mainInterface
	self._ui.root = buffsHolder
	self._ui.slotsByPotionId = slotsByPotionId
	self._ui.slotOrder = slotOrder
	self._ui.root.Visible = false

	if self._hoverPositionConnection == nil then
		self._hoverPositionConnection = UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				self:_updateHoverPosition()
			end
		end)
	end
end

function PotionController:_emitStateUpdated()
	self.StateUpdated:Fire(self._state)
end

function PotionController:_pruneExpiredActives(): boolean
	local normalizedActives = normalizeActivePotions(self._state.activePotions)
	local didChange = not areActivePotionMapsEqual(self._state.activePotions, normalizedActives)
	self._state.activePotions = normalizedActives
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
	local ok, result, timedOut = RemoteFunctionTimeout.Invoke(remote, payload, REMOTE_INVOKE_TIMEOUT_SECONDS)
	if not ok then
		local reason = if timedOut then "timed out" else "failed"
		Logger.Warn(string.format("[PotionController] Remote %s %s: %s", remote.Name, reason, tostring(result)))
		return nil
	end

	return result
end

function PotionController:_refreshHud()
	self:_cacheUi()

	local root = self._ui.root
	local slotsByPotionId = self._ui.slotsByPotionId
	local slotOrder = self._ui.slotOrder
	if not root or typeof(slotsByPotionId) ~= "table" or typeof(slotOrder) ~= "table" then
		return
	end

	local now = Workspace:GetServerTimeNow()
	local hasVisibleSlots = false

	for _, slot in ipairs(slotOrder) do
		local slotRoot = slot.root
		if not (slotRoot and slotRoot:IsDescendantOf(root)) then
			continue
		end

		local potionId = slot.potionId
		local activeEntry = if potionId then self:GetActivePotions()[potionId] else nil
		local expiresAt = tonumber(activeEntry and activeEntry.expiresAt)
		local remainingSeconds = if expiresAt then math.max(0, math.ceil(expiresAt - now)) else 0
		local config = if potionId then PotionConfig.Get(potionId) else nil
		local isVisible = remainingSeconds > 0 and config ~= nil

		slotRoot.Visible = isVisible
		if isVisible then
			hasVisibleSlots = true
		end

		if slot.timer then
			slot.timer.Text = PotionPresentation.FormatDuration(remainingSeconds)
		end

		if slot.stack then
			slot.stack.Text = "x1"
		end
	end

	root.Visible = hasVisibleSlots
	if hasVisibleSlots then
		self:_refreshHover()
	else
		self:_hideHover()
	end
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
	local bonuses = PotionRuntimeBonuses.CreateEmpty()

	for potionId, activeEntry in pairs(self:GetActivePotions()) do
		local expiresAt = tonumber(activeEntry and activeEntry.expiresAt)
		local config = PotionConfig.Get(activeEntry and (activeEntry.potionId or potionId) or potionId)
		if config and expiresAt and expiresAt > Workspace:GetServerTimeNow() then
			PotionRuntimeBonuses.ApplyConfigBonuses(bonuses, config)
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
	if result.ok == true then
		ToggleSoundUtil.PlayToggle(isFavorite == true)
	end
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
