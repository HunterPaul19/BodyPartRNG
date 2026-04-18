local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Schema = require(ReplicatedStorage.Lists.Schema)
local Notify = require(ReplicatedStorage.Shared.UI.Notify)

local DataController = require(script.Parent.DataController)
local MarketplaceController = require(script.Parent.MarketplaceController)
local UIController = require(script.Parent.UIController)

local LOCAL_PLAYER = Players.LocalPlayer
local REMOTES_FOLDER_NAME = "Remotes"
local MERCHANT_SHOP_FOLDER_NAME = "MerchantShop"
local GET_SHOP_STATE_REMOTE_NAME = "GetShopState"
local AVAILABILITY_CHANGED_REMOTE_NAME = "AvailabilityChanged"
local TELEPORT_TO_MERCHANT_REMOTE_NAME = "TeleportToMerchant"
local MODAL_ROOT_NAME = "ModalRoot"
local WINDOW_NAME = "MerchantTeleportFrame"
local OFFER_KEY = "merchant_teleporter"
local MARKETPLACE_KEY = Schema.Marketplace and Schema.Marketplace.key or "marketplace"

type MerchantShopState = {
	windowId: number,
	isActive: boolean,
	appearsAt: number,
	departsAt: number,
	nextAppearsAt: number,
}

type MerchantAvailabilityPayload = {
	isActive: boolean,
	windowId: number,
	appearsAt: number?,
	departsAt: number?,
	nextAppearsAt: number?,
}

type MerchantTeleportUi = {
	root: GuiObject,
	confirmButton: GuiButton,
	nevermindButton: GuiButton,
}

local MerchantTeleportController = {
	_started = false,
	_ui = nil :: MerchantTeleportUi?,
	_remotes = nil,
	_activeWindowToken = nil :: string?,
	_lastShownWindowToken = nil :: string?,
	_pendingAutoTeleportWindowToken = nil :: string?,
}

local function toWholeNumber(value: any, fallback: number): number
	local parsed = tonumber(value)
	if parsed == nil then
		return fallback
	end

	return math.floor(parsed)
end

local function buildWindowToken(isActive: boolean, windowId: any, departsAt: any): string?
	if isActive ~= true then
		return nil
	end

	local resolvedWindowId = toWholeNumber(windowId, -1)
	local resolvedDepartsAt = toWholeNumber(departsAt, 0)
	if resolvedWindowId < 0 then
		return nil
	end

	return string.format("%d:%d", resolvedWindowId, math.max(0, resolvedDepartsAt))
end

function MerchantTeleportController:_getPlayerGui(): PlayerGui
	return LOCAL_PLAYER:WaitForChild("PlayerGui")
end

function MerchantTeleportController:_ensureUi(): MerchantTeleportUi
	if self._ui and self._ui.root.Parent then
		return self._ui
	end

	local modalRoot = self:_getPlayerGui():WaitForChild(MODAL_ROOT_NAME, 30)
	assert(modalRoot and modalRoot:IsA("ScreenGui"), "PlayerGui.ModalRoot is missing.")

	local root = modalRoot:WaitForChild(WINDOW_NAME, 30)
	assert(root and root:IsA("GuiObject"), "PlayerGui.ModalRoot.MerchantTeleportFrame is missing.")

	local confirmButton = root:FindFirstChild("Confirm", true)
	assert(confirmButton and confirmButton:IsA("GuiButton"), "MerchantTeleportFrame.Confirm is missing.")

	local nevermindButton = root:FindFirstChild("Nevermind", true)
	assert(nevermindButton and nevermindButton:IsA("GuiButton"), "MerchantTeleportFrame.Nevermind is missing.")

	root.Visible = false

	self._ui = {
		root = root,
		confirmButton = confirmButton,
		nevermindButton = nevermindButton,
	}

	return self._ui
end

function MerchantTeleportController:_ensureRemotes()
	if self._remotes then
		return self._remotes
	end

	local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, 30)
	assert(remotesFolder and remotesFolder:IsA("Folder"), "ReplicatedStorage.Remotes is missing.")

	local merchantShopFolder = remotesFolder:WaitForChild(MERCHANT_SHOP_FOLDER_NAME, 30)
	assert(
		merchantShopFolder and merchantShopFolder:IsA("Folder"),
		"ReplicatedStorage.Remotes.MerchantShop is missing."
	)

	local getShopState = merchantShopFolder:WaitForChild(GET_SHOP_STATE_REMOTE_NAME, 30)
	local availabilityChanged = merchantShopFolder:WaitForChild(AVAILABILITY_CHANGED_REMOTE_NAME, 30)
	local teleportToMerchant = merchantShopFolder:WaitForChild(TELEPORT_TO_MERCHANT_REMOTE_NAME, 30)

	assert(getShopState and getShopState:IsA("RemoteFunction"), "MerchantShop.GetShopState remote is missing.")
	assert(
		availabilityChanged and availabilityChanged:IsA("RemoteEvent"),
		"MerchantShop.AvailabilityChanged remote is missing."
	)
	assert(
		teleportToMerchant and teleportToMerchant:IsA("RemoteFunction"),
		"MerchantShop.TeleportToMerchant remote is missing."
	)

	self._remotes = {
		getShopState = getShopState,
		availabilityChanged = availabilityChanged,
		teleportToMerchant = teleportToMerchant,
	}

	return self._remotes
end

function MerchantTeleportController:_invokeRemote(remote: RemoteFunction, payload: any?): any?
	local ok, result = pcall(function()
		if payload ~= nil then
			return remote:InvokeServer(payload)
		end

		return remote:InvokeServer()
	end)

	if not ok then
		warn(string.format("[MerchantTeleportController] Remote %s failed: %s", remote.Name, tostring(result)))
		return nil
	end

	return result
end

function MerchantTeleportController:_showToast(message: string)
	if typeof(message) ~= "string" or message == "" then
		return
	end

	Notify.Show(message, {
		channel = "merchant",
		duration = 4,
	})
end

function MerchantTeleportController:_getMarketplaceState(): any?
	return DataController:Get(MARKETPLACE_KEY)
end

function MerchantTeleportController:_isTeleporterOwned(): boolean
	local marketplaceState = self:_getMarketplaceState()
	if typeof(marketplaceState) ~= "table" then
		return false
	end

	local entitlementsByKey = marketplaceState.entitlementsByKey
	return typeof(entitlementsByKey) == "table" and entitlementsByKey[OFFER_KEY] ~= nil
end

function MerchantTeleportController:_setPopupVisible(isVisible: boolean)
	local ui = self:_ensureUi()
	ui.root.Visible = isVisible
end

function MerchantTeleportController:_clearPendingAutoTeleport()
	self._pendingAutoTeleportWindowToken = nil
end

function MerchantTeleportController:_showForWindow(windowToken: string?)
	if windowToken == nil then
		self:_setPopupVisible(false)
		return
	end
	if self._lastShownWindowToken == windowToken then
		return
	end

	self._lastShownWindowToken = windowToken
	self:_setPopupVisible(true)
end

function MerchantTeleportController:_dismissPopup()
	self:_clearPendingAutoTeleport()
	self:_setPopupVisible(false)
end

function MerchantTeleportController:_attemptTeleport(showFailureToast: boolean): boolean
	local activeWindowToken = self._activeWindowToken
	if activeWindowToken == nil then
		if showFailureToast then
			self:_showToast("The merchant isn't here right now.")
		end
		self:_dismissPopup()
		return false
	end

	local remotes = self:_ensureRemotes()
	local result = self:_invokeRemote(remotes.teleportToMerchant)
	if typeof(result) ~= "table" then
		if showFailureToast then
			self:_showToast("The merchant could not be reached right now.")
		end
		return false
	end

	if result.ok == true then
		self:_dismissPopup()
		return true
	end

	local shopState = result.shopState
	if typeof(shopState) == "table" and shopState.isActive ~= true then
		self._activeWindowToken = nil
		self:_dismissPopup()
	end

	if showFailureToast then
		self:_showToast(tostring(result.message or "The merchant could not be reached right now."))
	end

	return false
end

function MerchantTeleportController:_handleCurrentWindowState(shopState: MerchantShopState?)
	local nextWindowToken = nil
	if typeof(shopState) == "table" then
		nextWindowToken = buildWindowToken(shopState.isActive == true, shopState.windowId, shopState.departsAt)
	end

	self._activeWindowToken = nextWindowToken
	if nextWindowToken == nil then
		self:_dismissPopup()
		return
	end

	self:_showForWindow(nextWindowToken)
end

function MerchantTeleportController:_handleAvailabilityChanged(payload: MerchantAvailabilityPayload)
	local previousWindowToken = self._activeWindowToken
	local nextWindowToken = nil
	if typeof(payload) == "table" then
		nextWindowToken = buildWindowToken(payload.isActive == true, payload.windowId, payload.departsAt)
	end

	self._activeWindowToken = nextWindowToken

	if nextWindowToken ~= nil then
		self:_showForWindow(nextWindowToken)
		return
	end

	local hadPendingAutoTeleport = previousWindowToken ~= nil
		and self._pendingAutoTeleportWindowToken == previousWindowToken
	self:_dismissPopup()

	if hadPendingAutoTeleport then
		self:_showToast("The merchant left before the teleport could finish.")
	end
end

function MerchantTeleportController:_requestInitialState()
	local remotes = self:_ensureRemotes()
	local result = self:_invokeRemote(remotes.getShopState)
	if typeof(result) ~= "table" or typeof(result.shopState) ~= "table" then
		return
	end

	self:_handleCurrentWindowState(result.shopState)
end

function MerchantTeleportController:_handleConfirm()
	if self._activeWindowToken == nil then
		self:_showToast("The merchant isn't here right now.")
		self:_dismissPopup()
		return
	end

	if self:_isTeleporterOwned() then
		self:_attemptTeleport(true)
		return
	end

	self._pendingAutoTeleportWindowToken = self._activeWindowToken
	local ok, message, promptOpened = MarketplaceController:PromptOfferPurchase(OFFER_KEY)
	if not ok then
		self:_clearPendingAutoTeleport()
		self:_showToast(tostring(message or "The Merchant Teleporter prompt could not be opened."))
		return
	end

	if promptOpened == true then
		return
	end

	self:_attemptTeleport(true)
end

function MerchantTeleportController:_handleMarketplaceStateChanged()
	local pendingAutoTeleportWindowToken = self._pendingAutoTeleportWindowToken
	if pendingAutoTeleportWindowToken == nil then
		return
	end
	if pendingAutoTeleportWindowToken ~= self._activeWindowToken then
		self:_clearPendingAutoTeleport()
		return
	end
	if not self:_isTeleporterOwned() then
		return
	end

	self:_attemptTeleport(true)
end

function MerchantTeleportController:_bindUi()
	local ui = self:_ensureUi()

	UIController:CreateButton(ui.confirmButton, function()
		MerchantTeleportController:_handleConfirm()
	end)

	UIController:CreateButton(ui.nevermindButton, function()
		MerchantTeleportController:_dismissPopup()
	end)
end

function MerchantTeleportController:OnStart()
	if self._started then
		return
	end

	self._started = true
	self:_ensureUi()
	self:_bindUi()

	local remotes = self:_ensureRemotes()
	remotes.availabilityChanged.OnClientEvent:Connect(function(payload: MerchantAvailabilityPayload)
		self:_handleAvailabilityChanged(payload)
	end)

	DataController.DataReceived:Connect(function()
		self:_handleMarketplaceStateChanged()
	end)
	DataController.DataUpdated:Connect(function(key: string)
		if key == MARKETPLACE_KEY then
			self:_handleMarketplaceStateChanged()
		end
	end)

	self:_requestInitialState()
	self:_handleMarketplaceStateChanged()
end

return MerchantTeleportController
