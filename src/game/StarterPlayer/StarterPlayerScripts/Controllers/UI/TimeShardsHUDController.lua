local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Schema = require(ReplicatedStorage.Lists.Schema)
local NumberFormatter = require(ReplicatedStorage.Shared.Formatting.NumberFormatter)
local TimeShardState = require(ReplicatedStorage.Shared.Character.TimeShardState)
local DataController = require(script.Parent.DataController)

local LOCAL_PLAYER = Players.LocalPlayer
local TIME_SHARDS_KEY = Schema.TimeShards and Schema.TimeShards.key or nil

local TimeShardsHUDController = {}

local function formatTimeShardsText(value: any): string
	local numericValue = tonumber(value) or 0
	return NumberFormatter.Format(math.max(0, math.round(numericValue)))
end

function TimeShardsHUDController:_getLabel(): TextLabel?
	if self._label and self._label.Parent then
		return self._label
	end

	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	local mainInterface = playerGui:WaitForChild("MainInterface", 30)
	if not (mainInterface and mainInterface:IsA("ScreenGui")) then
		return nil
	end

	local main = mainInterface:WaitForChild("Main", 30)
	if not (main and main:IsA("GuiObject")) then
		return nil
	end

	local timeShards = main:WaitForChild("TimeShards", 30)
	if not (timeShards and timeShards:IsA("GuiObject")) then
		return nil
	end

	local label = timeShards:WaitForChild("Quantity", 30)
	if label and label:IsA("TextLabel") then
		self._label = label
		return label
	end

	return nil
end

function TimeShardsHUDController:_renderTimeShards(stateValue: any)
	local label = self:_getLabel()
	if not label then
		return
	end

	local normalizedState = TimeShardState.Normalize(stateValue)
	label.Text = formatTimeShardsText(normalizedState.balance)
end

function TimeShardsHUDController:_refreshFromData()
	if not TIME_SHARDS_KEY then
		self:_renderTimeShards(nil)
		return
	end

	self:_renderTimeShards(DataController:Get(TIME_SHARDS_KEY))
end

function TimeShardsHUDController:OnStart()
	self:_refreshFromData()

	DataController.DataReceived:Connect(function()
		self:_refreshFromData()
	end)

	DataController.DataUpdated:Connect(function(key)
		if key == TIME_SHARDS_KEY then
			self:_refreshFromData()
		end
	end)
end

return TimeShardsHUDController
