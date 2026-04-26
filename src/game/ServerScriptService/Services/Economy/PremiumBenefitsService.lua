local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PremiumBenefits = require(ReplicatedStorage.Shared.Premium.PremiumBenefits)
local DataService = require(script.Parent.DataService)
local PurchaseReceiptService = require(script.Parent.PurchaseReceiptService)

local VIP_ATTR = "VIP"
local VIP_PLUS_ATTR = "VIPPlus"
local PREMIUM_TAG_ATTR = "PremiumTag"
local MOVEMENT_MULTIPLIER_ATTR = "PremiumMovementSpeedMultiplier"

local PremiumBenefitsService = {}

local function disconnectConnections(connections: { RBXScriptConnection })
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function getPremiumState(player: Player): any
	return PremiumBenefits.GetState(DataService:GetVipOwned(player), DataService:GetVipPlusOwned(player))
end

function PremiumBenefitsService:_ensureState()
	if self._started then
		return
	end

	self._started = true
	self._playerConnections = {}
end

function PremiumBenefitsService:_applyAttributes(player: Player, premiumState: any)
	player:SetAttribute(VIP_ATTR, premiumState.hasVip == true)
	player:SetAttribute(VIP_PLUS_ATTR, premiumState.hasVipPlus == true)
	player:SetAttribute(PREMIUM_TAG_ATTR, premiumState.premiumTag ~= "" and premiumState.premiumTag or nil)
	player:SetAttribute(MOVEMENT_MULTIPLIER_ATTR, premiumState.movementSpeedMultiplier)
end

function PremiumBenefitsService:_applyMovementSpeed(player: Player, premiumState: any)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	humanoid:SetAttribute(MOVEMENT_MULTIPLIER_ATTR, premiumState.movementSpeedMultiplier)
end

function PremiumBenefitsService:_refreshPlayer(player: Player)
	if player.Parent ~= Players then
		return
	end

	local premiumState = getPremiumState(player)
	self:_applyAttributes(player, premiumState)
	self:_applyMovementSpeed(player, premiumState)
end

function PremiumBenefitsService:_trackPlayer(player: Player)
	local connections = self._playerConnections[player]
	if connections then
		disconnectConnections(connections)
	else
		connections = {}
		self._playerConnections[player] = connections
	end

	table.insert(connections, player.CharacterAdded:Connect(function()
		task.defer(function()
			self:_refreshPlayer(player)
		end)
	end))

	self:_refreshPlayer(player)
end

function PremiumBenefitsService:_untrackPlayer(player: Player)
	local connections = self._playerConnections[player]
	if not connections then
		return
	end

	disconnectConnections(connections)
	self._playerConnections[player] = nil
end

function PremiumBenefitsService:OnStart()
	self:_ensureState()

	PurchaseReceiptService.PurchaseProcessed:Connect(function(player: Player, offerKey: string)
		if offerKey == "vip" or offerKey == "vip_plus" then
			self:_refreshPlayer(player)
		end
	end)

	PurchaseReceiptService.OwnedEntitlementsReady:Connect(function(player: Player)
		self:_refreshPlayer(player)
	end)
end

function PremiumBenefitsService:OnPlayerAdded(player: Player)
	self:_ensureState()
	self:_trackPlayer(player)
end

function PremiumBenefitsService:OnPlayerRemoving(player: Player)
	self:_untrackPlayer(player)
end

return PremiumBenefitsService
