local Players = game:GetService("Players")

local RateLimitTelemetry = require(script.Parent.RateLimitTelemetry)

type ActionConfig = {
	limit: number,
	windowSeconds: number,
}

type ActionState = {
	windowStartedAt: number,
	requestCount: number,
}

local ACTION_CONFIGS: { [string]: ActionConfig } = {
	default = {
		limit = 8,
		windowSeconds = 1,
	},
	["remote.admin"] = {
		limit = 2,
		windowSeconds = 1,
	},
	["remote.boss_arena.get_picker"] = {
		limit = 4,
		windowSeconds = 1,
	},
	["remote.boss_arena.select_picker"] = {
		limit = 2,
		windowSeconds = 1,
	},
	["remote.appraisal.get_state"] = {
		limit = 2,
		windowSeconds = 1,
	},
	["remote.appraisal.perform"] = {
		limit = 2,
		windowSeconds = 1,
	},
	["remote.aura.get_state"] = {
		limit = 2,
		windowSeconds = 1,
	},
	["remote.aura.equip"] = {
		limit = 3,
		windowSeconds = 1,
	},
	["remote.aura.favorite"] = {
		limit = 4,
		windowSeconds = 1,
	},
	["remote.aura.existence"] = {
		limit = 1,
		windowSeconds = 2,
	},
	["remote.body_parts.get_state"] = {
		limit = 2,
		windowSeconds = 1,
	},
	["remote.body_parts.existence"] = {
		limit = 1,
		windowSeconds = 2,
	},
	["remote.body_parts.inspect"] = {
		limit = 1,
		windowSeconds = 1,
	},
	["remote.body_parts.equip"] = {
		limit = 3,
		windowSeconds = 1,
	},
	["remote.body_parts.equip_best"] = {
		limit = 2,
		windowSeconds = 1,
	},
	["remote.body_parts.unequip"] = {
		limit = 3,
		windowSeconds = 1,
	},
	["remote.body_parts.auto_size"] = {
		limit = 2,
		windowSeconds = 1,
	},
	["remote.body_parts.clear"] = {
		limit = 2,
		windowSeconds = 1,
	},
	["remote.body_parts.favorite"] = {
		limit = 4,
		windowSeconds = 1,
	},
	["remote.body_parts.sell_one"] = {
		limit = 3,
		windowSeconds = 1,
	},
	["remote.body_parts.sell_all"] = {
		limit = 1,
		windowSeconds = 1,
	},
	["remote.marketplace.offer_info"] = {
		limit = 4,
		windowSeconds = 1,
	},
	["remote.marketplace.offer_presentations"] = {
		limit = 2,
		windowSeconds = 1,
	},
	["remote.marketplace.prompt_purchase"] = {
		limit = 2,
		windowSeconds = 2,
	},
	["remote.marketplace.prompt_gift"] = {
		limit = 1,
		windowSeconds = 2,
	},
	["remote.merchant.get_state"] = {
		limit = 2,
		windowSeconds = 1,
	},
	["remote.merchant.purchase"] = {
		limit = 2,
		windowSeconds = 1,
	},
	["remote.merchant.teleport"] = {
		limit = 1,
		windowSeconds = 1,
	},
	["remote.potions.get_state"] = {
		limit = 2,
		windowSeconds = 1,
	},
	["remote.potions.use"] = {
		limit = 2,
		windowSeconds = 1,
	},
	["remote.potions.favorite"] = {
		limit = 4,
		windowSeconds = 1,
	},
	["remote.potions.sell"] = {
		limit = 3,
		windowSeconds = 1,
	},
	["remote.roll.get_state"] = {
		limit = 2,
		windowSeconds = 1,
	},
	["remote.roll.select_type"] = {
		limit = 4,
		windowSeconds = 1,
	},
	["remote.roll.select_region"] = {
		limit = 4,
		windowSeconds = 1,
	},
	["remote.roll.quick_roll"] = {
		limit = 2,
		windowSeconds = 1,
	},
	["remote.roll.auto_sell"] = {
		limit = 4,
		windowSeconds = 1,
	},
	["remote.roll.cutscene"] = {
		limit = 4,
		windowSeconds = 1,
	},
	["remote.roll.finalize_auto_sell"] = {
		limit = 2,
		windowSeconds = 1,
	},
	["remote.roll.prompt_quick_roll"] = {
		limit = 1,
		windowSeconds = 2,
	},
	["remote.roll.perform"] = {
		limit = 12,
		windowSeconds = 1,
	},
	["remote.title.set_equipped"] = {
		limit = 3,
		windowSeconds = 1,
	},
}

local actionStateByPlayer: { [Player]: { [string]: ActionState } } = {}

local RequestLimiter = {}

local function getActionConfig(actionKey: string): ActionConfig
	return ACTION_CONFIGS[actionKey] or ACTION_CONFIGS.default
end

local function getPlayerActionStateMap(player: Player): { [string]: ActionState }
	local actionStateMap = actionStateByPlayer[player]
	if actionStateMap == nil then
		actionStateMap = {}
		actionStateByPlayer[player] = actionStateMap
	end

	return actionStateMap
end

function RequestLimiter:Allow(player: Player, actionKey: string): (boolean, number?)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, 1
	end

	local resolvedActionKey = if typeof(actionKey) == "string" and actionKey ~= "" then actionKey else "default"
	local config = getActionConfig(resolvedActionKey)
	local now = os.clock()
	local actionStateMap = getPlayerActionStateMap(player)
	local actionState = actionStateMap[resolvedActionKey]

	if actionState == nil or now - actionState.windowStartedAt >= config.windowSeconds then
		actionState = {
			windowStartedAt = now,
			requestCount = 0,
		}
		actionStateMap[resolvedActionKey] = actionState
	end

	if actionState.requestCount >= config.limit then
		local retryAfterSeconds = math.max(0, config.windowSeconds - (now - actionState.windowStartedAt))
		RateLimitTelemetry.Increment("remote_rejected", resolvedActionKey, 1)
		return false, retryAfterSeconds
	end

	actionState.requestCount += 1
	RateLimitTelemetry.Increment("remote_allowed", resolvedActionKey, 1)
	return true, nil
end

function RequestLimiter:GetSnapshot(): { [string]: { [string]: number } }
	return RateLimitTelemetry.GetSnapshot()
end

Players.PlayerRemoving:Connect(function(player: Player)
	actionStateByPlayer[player] = nil
end)

return RequestLimiter
