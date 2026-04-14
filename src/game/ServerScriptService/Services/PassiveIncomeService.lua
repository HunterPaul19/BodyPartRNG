local BodyPartService = require(script.Parent.BodyPartService)
local DataService = require(script.Parent.DataService)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PerfStats = require(ReplicatedStorage.Shared.Diagnostics.PerfStats)

local UPDATE_INTERVAL = 1
local REPLICA_WARMUP_DURATION = 2

type PassiveIncomePlayerState = {
	remainder: number,
	readyAt: number,
	passiveIncomePerSecond: number,
}

local playerStateByPlayer: { [Player]: PassiveIncomePlayerState } = {}

local PassiveIncomeService = {}

local function getOrCreatePlayerState(player: Player): PassiveIncomePlayerState
	local state = playerStateByPlayer[player]
	if state then
		return state
	end

	state = {
		remainder = 0,
		readyAt = os.clock() + REPLICA_WARMUP_DURATION,
		passiveIncomePerSecond = 0,
	}
	playerStateByPlayer[player] = state
	return state
end

local function refreshPassiveIncomeRate(player: Player, state: PassiveIncomePlayerState?)
	local resolvedState = state or getOrCreatePlayerState(player)
	local bonuses = BodyPartService:GetComputedLoadoutBonuses(player)
	resolvedState.passiveIncomePerSecond = math.max(0, tonumber(bonuses.passiveIncomePerSecond) or 0)
end

local function processPlayer(player: Player, state: PassiveIncomePlayerState)
	local passiveIncomePerSecond = state.passiveIncomePerSecond
	if passiveIncomePerSecond <= 0 then
		return
	end

	local startedAt = PerfStats.Begin()
	local generatedIncome = (passiveIncomePerSecond * UPDATE_INTERVAL) + state.remainder
	local wholeMoneyToAward = math.floor(generatedIncome)
	state.remainder = generatedIncome - wholeMoneyToAward

	if wholeMoneyToAward > 0 then
		DataService:AddMoney(player, wholeMoneyToAward, "passive_income")
	end

	PerfStats.Measure("PassiveIncomeTick", startedAt, {
		awarded = wholeMoneyToAward,
		rate = passiveIncomePerSecond,
	})
end

function PassiveIncomeService:OnStart()
	if self._loopActive then
		return
	end

	self._loopActive = true
	BodyPartService.LoadoutChanged:Connect(function(player: Player)
		refreshPassiveIncomeRate(player)
	end)
	DataService.EquippedAuraChanged:Connect(function(player: Player)
		refreshPassiveIncomeRate(player)
	end)

	task.spawn(function()
		while self._loopActive do
			task.wait(UPDATE_INTERVAL)
			local now = os.clock()
			for player, state in pairs(playerStateByPlayer) do
				if now < state.readyAt then
					continue
				end

				processPlayer(player, state)
			end
		end
	end)
end

function PassiveIncomeService:OnPlayerAdded(player: Player)
	local state = getOrCreatePlayerState(player)
	refreshPassiveIncomeRate(player, state)
end

function PassiveIncomeService:OnPlayerRemoving(player: Player)
	playerStateByPlayer[player] = nil
end

return PassiveIncomeService
