local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local ACTIVE_PROFILE_ID = "boss_arena"
local DEFAULT_HEALTH_SCRIPT_NAME = "Health"

type PlayerState = {
	characterConnection: RBXScriptConnection?,
	characterChildConnection: RBXScriptConnection?,
}

local BossArenaPlayerHealthService = {
	_started = false,
	_playerStates = {} :: { [Player]: PlayerState },
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
end

local function disableDefaultHealthScript(instance: Instance)
	if instance.Name ~= DEFAULT_HEALTH_SCRIPT_NAME or not instance:IsA("Script") then
		return
	end

	instance.Disabled = true
	instance:Destroy()
end

function BossArenaPlayerHealthService:_getPlayerState(player: Player): PlayerState
	local state = self._playerStates[player]
	if state then
		return state
	end

	state = {
		characterConnection = nil,
		characterChildConnection = nil,
	}
	self._playerStates[player] = state
	return state
end

function BossArenaPlayerHealthService:_bindCharacter(player: Player, character: Model)
	local state = self:_getPlayerState(player)
	if state.characterChildConnection then
		state.characterChildConnection:Disconnect()
		state.characterChildConnection = nil
	end

	for _, child in ipairs(character:GetChildren()) do
		disableDefaultHealthScript(child)
	end

	state.characterChildConnection = character.ChildAdded:Connect(function(child)
		disableDefaultHealthScript(child)
	end)
end

function BossArenaPlayerHealthService:OnStart()
	if self._started then
		return
	end
	self._started = true

	if not isEnabledForPlace() then
		return
	end
end

function BossArenaPlayerHealthService:OnPlayerAdded(player: Player)
	if not isEnabledForPlace() then
		return
	end

	local state = self:_getPlayerState(player)
	if state.characterConnection then
		state.characterConnection:Disconnect()
	end

	state.characterConnection = player.CharacterAdded:Connect(function(character)
		self:_bindCharacter(player, character)
	end)

	if player.Character then
		self:_bindCharacter(player, player.Character)
	end
end

function BossArenaPlayerHealthService:OnPlayerRemoving(player: Player)
	local state = self._playerStates[player]
	if not state then
		return
	end

	if state.characterConnection then
		state.characterConnection:Disconnect()
	end
	if state.characterChildConnection then
		state.characterChildConnection:Disconnect()
	end
	self._playerStates[player] = nil
end

return BossArenaPlayerHealthService
