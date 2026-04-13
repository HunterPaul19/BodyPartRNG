local RunService = game:GetService("RunService")

local BodyPartService = require(script.Parent.BodyPartService)
local DataService = require(script.Parent.DataService)

local UPDATE_INTERVAL = 0.25
local REPLICA_WARMUP_DURATION = 2

type PassiveIncomePlayerState = {
	elapsedTime: number,
	remainder: number,
	readyAt: number,
}

local playerStateByPlayer: { [Player]: PassiveIncomePlayerState } = {}

local PassiveIncomeService = {}

local function getOrCreatePlayerState(player: Player): PassiveIncomePlayerState
	local state = playerStateByPlayer[player]
	if state then
		return state
	end

	state = {
		elapsedTime = 0,
		remainder = 0,
		readyAt = os.clock() + REPLICA_WARMUP_DURATION,
	}
	playerStateByPlayer[player] = state
	return state
end

local function processPlayer(player: Player, state: PassiveIncomePlayerState)
	local bonuses = BodyPartService:GetComputedLoadoutBonuses(player)
	local passiveIncomePerSecond = math.max(0, tonumber(bonuses.passiveIncomePerSecond) or 0)
	if passiveIncomePerSecond <= 0 then
		return
	end

	local generatedIncome = (passiveIncomePerSecond * state.elapsedTime) + state.remainder
	local wholeMoneyToAward = math.floor(generatedIncome)
	state.remainder = generatedIncome - wholeMoneyToAward

	if wholeMoneyToAward > 0 then
		DataService:AddMoney(player, wholeMoneyToAward)
	end
end

function PassiveIncomeService:OnStart()
	if self._heartbeatConnection then
		return
	end

	self._heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
		for player, state in pairs(playerStateByPlayer) do
			if os.clock() < state.readyAt then
				continue
			end

			state.elapsedTime += math.max(0, deltaTime)
			if state.elapsedTime >= UPDATE_INTERVAL then
				processPlayer(player, state)
				state.elapsedTime = 0
			end
		end
	end)
end

function PassiveIncomeService:OnPlayerAdded(player: Player)
	getOrCreatePlayerState(player)
end

function PassiveIncomeService:OnPlayerRemoving(player: Player)
	playerStateByPlayer[player] = nil
end

return PassiveIncomeService
