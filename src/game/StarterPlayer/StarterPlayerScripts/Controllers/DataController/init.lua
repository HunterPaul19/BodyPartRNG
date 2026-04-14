local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Globals = require(ReplicatedStorage.Lists.Globals)
local Signal = require(ReplicatedStorage.Common.Signal)
local ReplicaController = require(ReplicatedStorage.Packages.ReplicaController)

local PLAYER = Players.LocalPlayer
local SCOPE = Globals.SCOPE

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
