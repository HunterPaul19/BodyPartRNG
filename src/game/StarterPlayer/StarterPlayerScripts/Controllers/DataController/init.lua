local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Globals = require(ReplicatedStorage.Lists.Globals)
local Signal = require(ReplicatedStorage.Common.Signal)
local ReplicaController = require(ReplicatedStorage.Packages.ReplicaController)
local sharedFolder = ReplicatedStorage:WaitForChild("Shared", 10)
local placeProfilesFolder = if sharedFolder then sharedFolder:WaitForChild("PlaceProfiles", 10) else nil
local placeProfileModule = if placeProfilesFolder then placeProfilesFolder:WaitForChild("PlaceProfile", 10) else nil

if not (placeProfileModule and placeProfileModule:IsA("ModuleScript")) then
	error(
		"[DataController] ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile is missing or did not replicate in time.",
		0
	)
end

local PlaceProfile = require(placeProfileModule)

local PLAYER = Players.LocalPlayer
local SCOPE = Globals.SCOPE
local REPLICA_REMOTE_EVENTS_TIMEOUT = 10

local DATA = nil
local DataReceived = Signal.new()
local DataUpdated = Signal.new()

local DataController = {}

DataController.DataReceived = DataReceived
DataController.DataUpdated = DataUpdated
DataController.Loaded = false

local function bindReplica(replica)
	if replica.Tags.Player ~= PLAYER then
		return
	end

	DATA = replica.Data
	DataController.Loaded = true
	DataReceived:Fire(DATA)

	replica:ListenToRaw(function(action, path, ...)
		if action == "SetValue" then
			local key = path[1]
			if key ~= nil then
				DataUpdated:Fire(key, action, path, ...)
			end
		elseif action == "SetValues" then
			local key = path[1]
			if key ~= nil then
				DataUpdated:Fire(key, action, path, ...)
			end
		elseif action == "ArrayInsert" or action == "ArraySet" or action == "ArrayRemove" then
			local key = path[1]
			if key ~= nil then
				DataUpdated:Fire(key, action, path, ...)
			end
		end
	end)
end

function DataController:OnStart()
	if not PlaceProfile.RequiresPlayerDataReplica() then
		return
	end

	local activeProfile = PlaceProfile.GetActiveProfile()
	local placeId = math.max(0, math.floor(tonumber(game.PlaceId) or 0))
	local replicaRemoteEvents = ReplicatedStorage:WaitForChild("ReplicaRemoteEvents", REPLICA_REMOTE_EVENTS_TIMEOUT)
	if not (replicaRemoteEvents and replicaRemoteEvents:IsA("Folder")) then
		error(
			string.format(
				"[DataController][Profile:%s][PlaceId:%d] Required ReplicatedStorage.ReplicaRemoteEvents is missing after %d seconds. Expected server-side data replication to be initialized for this place.",
				activeProfile.id,
				placeId,
				REPLICA_REMOTE_EVENTS_TIMEOUT
			),
			0
		)
	end

	ReplicaController.ReplicaOfClassCreated(SCOPE, bindReplica)
	ReplicaController.RequestData()
end

function DataController:Get(key: string?)
	if key and DATA then
		return DATA[key]
	end

	return DATA
end

return DataController
