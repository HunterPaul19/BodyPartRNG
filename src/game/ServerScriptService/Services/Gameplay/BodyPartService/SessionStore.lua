local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BodyPartLoadout = require(ReplicatedStorage.Shared.Character.BodyPartLoadout)

local SessionStore = {}

local stateByPlayer: { [Player]: BodyPartLoadout.EquippedState } = {}

function SessionStore.LoadPlayer(player: Player, initialState: BodyPartLoadout.EquippedState?)
	stateByPlayer[player] = BodyPartLoadout.CloneEquippedState(initialState)
end

function SessionStore.CleanupPlayer(player: Player)
	stateByPlayer[player] = nil
end

function SessionStore.GetEquipped(player: Player): BodyPartLoadout.EquippedState
	local state = stateByPlayer[player]
	if not state then
		state = BodyPartLoadout.CreateEmptyEquippedState()
		stateByPlayer[player] = state
	end

	return BodyPartLoadout.CloneEquippedState(state)
end

function SessionStore.SetEquipped(player: Player, entry: BodyPartLoadout.LoadoutEntry)
	local state = SessionStore.GetEquipped(player)
	state[entry.region] = BodyPartLoadout.CloneLoadoutEntry(entry)
	stateByPlayer[player] = state
	return BodyPartLoadout.CloneEquippedState(state)
end

function SessionStore.ClearRegion(player: Player, region: string)
	local state = SessionStore.GetEquipped(player)
	state[region] = nil
	stateByPlayer[player] = state
	return BodyPartLoadout.CloneEquippedState(state)
end

function SessionStore.ClearAll(player: Player)
	local state = BodyPartLoadout.CreateEmptyEquippedState()
	stateByPlayer[player] = state
	return BodyPartLoadout.CloneEquippedState(state)
end

function SessionStore.Restore(player: Player, equippedState: BodyPartLoadout.EquippedState)
	stateByPlayer[player] = BodyPartLoadout.CloneEquippedState(equippedState)
end

return SessionStore
