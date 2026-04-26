local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossArenaRuntimeService = require(script.Parent.BossArenaRuntimeService)
local BossArenaMovePresentationRelay = require(script.Parent.Common.BossArenaMovePresentationRelay)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local ACTIVE_PROFILE_ID = "boss_arena"

local BossArenaMovePresentationService = {
	_started = false,
	_disconnectPresentationListener = nil :: (() -> ())?,
}

local function isEnabledForPlace(): boolean
	return PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
end

function BossArenaMovePresentationService:OnStart()
	if self._started then
		return
	end
	self._started = true

	if not isEnabledForPlace() then
		return
	end

	BossArenaMovePresentationRelay.EnsureRemote()
	self._disconnectPresentationListener = BossArenaRuntimeService:ConnectMovePresentation(function(payload: any)
		BossArenaMovePresentationRelay.FireAllClients(payload)
	end)

	Logger.Print("[BossArenaMovePresentationService] Ready for boss move presentation replication.")
end

return BossArenaMovePresentationService
