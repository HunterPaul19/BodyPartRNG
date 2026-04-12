local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Schema = require(ReplicatedStorage.Lists.Schema)
local NumberFormatter = require(ReplicatedStorage.Shared.Formatting.NumberFormatter)
local DataController = require(script.Parent.DataController)

local LOCAL_PLAYER = Players.LocalPlayer
local MONEY_KEY = Schema.Money and Schema.Money.key or nil

local MoneyHUDController = {}

local function formatMoneyText(value: any): string
	local numericValue = tonumber(value) or 0
	local clampedValue = math.max(0, numericValue)

	return "$" .. NumberFormatter.Format(math.round(clampedValue))
end

function MoneyHUDController:_getLabel(): TextLabel?
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

	local coin = main:WaitForChild("Coin", 30)
	if not (coin and coin:IsA("GuiObject")) then
		return nil
	end

	local label = coin:WaitForChild("Cost", 30)
	if label and label:IsA("TextLabel") then
		self._label = label
		return label
	end

	return nil
end

function MoneyHUDController:_renderMoney(value: any)
	local label = self:_getLabel()
	if not label then
		return
	end

	label.Text = formatMoneyText(value)
end

function MoneyHUDController:_refreshFromData()
	if not MONEY_KEY then
		self:_renderMoney(0)
		return
	end

	self:_renderMoney(DataController:Get(MONEY_KEY))
end

function MoneyHUDController:OnStart()
	self:_refreshFromData()

	DataController.DataReceived:Connect(function()
		self:_refreshFromData()
	end)

	DataController.DataUpdated:Connect(function(key)
		if key == MONEY_KEY then
			self:_refreshFromData()
		end
	end)
end

return MoneyHUDController
