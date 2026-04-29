local PotionConfig = require(game:GetService("ReplicatedStorage").Shared.Config.PotionConfig)

local PotionHandler = {}
local potionService = nil

local function getPotionService()
	if potionService == nil then
		potionService = require(script.Parent.Parent.PotionService)
	end

	return potionService
end

function PotionHandler.grant(player: Player, context: any): (boolean, string?)
	local potionId = if typeof(context) == "table" then context.potionId else nil
	local config = PotionConfig.Get(potionId)
	if not config then
		return false, "Marketplace potion purchase is missing a valid potionId."
	end

	local amount = if typeof(context) == "table" then tonumber(context.amount) else nil
	amount = if amount ~= nil then math.floor(amount) else 0
	if amount <= 0 then
		return false, "Marketplace potion purchase amount is invalid."
	end

	local ok, message = getPotionService():GrantPotionUses(player, config.id, amount)
	return ok, message
end

return PotionHandler
