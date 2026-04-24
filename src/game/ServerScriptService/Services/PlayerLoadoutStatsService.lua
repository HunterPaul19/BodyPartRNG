local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BodyPartService = require(script.Parent.BodyPartService)
local DataService = require(script.Parent.DataService)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)

local STAT_ATTRIBUTE_NAMES = table.freeze({
	speed = "BodyPartSpeed",
	damage = "BodyPartDamage",
	strength = "BodyPartStrength",
	health = "BodyPartHealth",
})
local PREMIUM_MOVEMENT_MULTIPLIER_ATTR = "PremiumMovementSpeedMultiplier"

local PlayerLoadoutStatsService = {}

local characterAddedConnections: { [Player]: RBXScriptConnection } = {}
local premiumMultiplierConnections: { [Player]: RBXScriptConnection } = {}
local dataReadyByPlayer: { [Player]: boolean } = {}

type FinalStats = {
	speed: number,
	damage: number,
	strength: number,
	health: number,
	baseSpeed: number,
	movementSpeedMultiplier: number,
}

local function calculateCombatScore(stats: FinalStats): number
	return stats.damage + (stats.health * 8) + (stats.speed * 25)
end

local function resolveHumanoid(character: Model?): Humanoid?
	if character == nil then
		return nil
	end

	return character:FindFirstChildOfClass("Humanoid")
end

local function resolvePremiumMovementSpeedMultiplier(player: Player): number
	local multiplier = tonumber(player:GetAttribute(PREMIUM_MOVEMENT_MULTIPLIER_ATTR))
	if multiplier == nil or multiplier <= 0 then
		return 1
	end

	return multiplier
end

local function resolveFinalStats(player: Player): FinalStats
	local basePlayerStats = BodyPartsCatalog.GetBasePlayerStats()
	local bonuses = BodyPartService:GetComputedLoadoutBonuses(player)
	local baseSpeed = math.max(0, tonumber(bonuses and bonuses.speed) or tonumber(basePlayerStats.speed) or 16)
	local damage = math.max(0, tonumber(bonuses and bonuses.damage) or tonumber(basePlayerStats.damage) or 20)
	local movementSpeedMultiplier = resolvePremiumMovementSpeedMultiplier(player)

	return {
		speed = baseSpeed * movementSpeedMultiplier,
		damage = damage,
		strength = damage,
		health = math.max(1, tonumber(bonuses and bonuses.health) or tonumber(basePlayerStats.health) or 100),
		baseSpeed = baseSpeed,
		movementSpeedMultiplier = movementSpeedMultiplier,
	}
end

local function updatePlayerAttributes(player: Player, stats: FinalStats)
	for statName, attributeName in pairs(STAT_ATTRIBUTE_NAMES) do
		player:SetAttribute(attributeName, stats[statName])
	end
end

local function applyStatsToHumanoid(player: Player, humanoid: Humanoid)
	local stats = resolveFinalStats(player)
	updatePlayerAttributes(player, stats)

	if humanoid.Parent == nil then
		return
	end

	humanoid:SetAttribute(PREMIUM_MOVEMENT_MULTIPLIER_ATTR, stats.movementSpeedMultiplier)
	humanoid.WalkSpeed = stats.speed

	local previousMaxHealth = math.max(1, tonumber(humanoid.MaxHealth) or stats.health)
	local previousHealth = tonumber(humanoid.Health) or previousMaxHealth
	local wasAlive = previousHealth > 0
	local healthRatio = math.clamp(previousHealth / previousMaxHealth, 0, 1)

	humanoid.MaxHealth = stats.health
	if wasAlive then
		humanoid.Health = math.clamp(stats.health * healthRatio, 1, stats.health)
	end
end

local function applyStatsToCharacter(player: Player, character: Model?)
	if player.Parent ~= Players or character == nil or character.Parent == nil then
		return
	end
	if dataReadyByPlayer[player] ~= true then
		return
	end

	local humanoid = resolveHumanoid(character)
	if humanoid == nil then
		humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	end
	if humanoid == nil or not humanoid:IsA("Humanoid") then
		return
	end

	applyStatsToHumanoid(player, humanoid)
end

local function scheduleApply(player: Player)
	local character = player.Character
	if character == nil then
		return
	end

	task.defer(function()
		if player.Character == character then
			applyStatsToCharacter(player, character)
		end
	end)
end

function PlayerLoadoutStatsService:GetFinalStats(player: Player): FinalStats
	return resolveFinalStats(player)
end

function PlayerLoadoutStatsService:GetCombatScore(player: Player): number
	return calculateCombatScore(resolveFinalStats(player))
end

function PlayerLoadoutStatsService:OnStart()
	BodyPartService.LoadoutChanged:Connect(function(player: Player)
		scheduleApply(player)
	end)

	DataService.PlayerDataLoaded:Connect(function(player: Player)
		dataReadyByPlayer[player] = true
		scheduleApply(player)
	end)

	DataService.PlayerDataRemoving:Connect(function(player: Player)
		dataReadyByPlayer[player] = nil
	end)
end

function PlayerLoadoutStatsService:OnPlayerAdded(player: Player)
	if characterAddedConnections[player] then
		characterAddedConnections[player]:Disconnect()
	end
	if premiumMultiplierConnections[player] then
		premiumMultiplierConnections[player]:Disconnect()
	end

	characterAddedConnections[player] = player.CharacterAdded:Connect(function(character: Model)
		task.defer(function()
			applyStatsToCharacter(player, character)
		end)
	end)
	premiumMultiplierConnections[player] = player:GetAttributeChangedSignal(PREMIUM_MOVEMENT_MULTIPLIER_ATTR):Connect(function()
		scheduleApply(player)
	end)

	scheduleApply(player)
end

function PlayerLoadoutStatsService:OnPlayerRemoving(player: Player)
	dataReadyByPlayer[player] = nil
	if characterAddedConnections[player] then
		characterAddedConnections[player]:Disconnect()
		characterAddedConnections[player] = nil
	end
	if premiumMultiplierConnections[player] then
		premiumMultiplierConnections[player]:Disconnect()
		premiumMultiplierConnections[player] = nil
	end
end

return PlayerLoadoutStatsService
