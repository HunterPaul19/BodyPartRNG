local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BodyPartPresentation = require(ReplicatedStorage.Shared.UI.BodyPartPresentation)
local UIController = require(script.Parent.UIController)

local LOCAL_PLAYER = Players.LocalPlayer

local SlotCardRenderer = {}
SlotCardRenderer.__index = SlotCardRenderer

local function clonePayload(payload: any, isSelected: boolean?): any
	local cloned = {}
	if typeof(payload) == "table" then
		for key, value in pairs(payload) do
			cloned[key] = value
		end
	end

	cloned.isSelected = isSelected == true
	return cloned
end

function SlotCardRenderer.new(playerGui: PlayerGui?)
	return setmetatable({
		_playerGui = playerGui,
		_template = nil :: Frame?,
		_entriesByKey = {},
	}, SlotCardRenderer)
end

function SlotCardRenderer:_getPlayerGui(): PlayerGui
	if self._playerGui and self._playerGui.Parent then
		return self._playerGui
	end

	self._playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	return self._playerGui
end

function SlotCardRenderer:_getTemplate(): Frame
	local template = self._template
	if template and template.Parent then
		return template
	end

	local playerGui = self:_getPlayerGui()
	local modalRoot = playerGui:WaitForChild("ModalRoot", 30)
	assert(modalRoot and modalRoot:IsA("ScreenGui"), "PlayerGui.ModalRoot is missing.")

	local inventoryRoot = modalRoot:WaitForChild("Inventory", 30)
	assert(inventoryRoot and inventoryRoot:IsA("GuiObject"), "PlayerGui.ModalRoot.Inventory is missing.")

	local scrollingFrame = inventoryRoot:WaitForChild("ScrollingFrame", 30)
	assert(scrollingFrame and scrollingFrame:IsA("ScrollingFrame"), "Inventory.ScrollingFrame is missing.")

	template = scrollingFrame:WaitForChild("Template", 30)
	assert(template and template:IsA("Frame"), "Inventory template is missing.")

	self._template = template
	return template
end

function SlotCardRenderer:_ensureEntry(slotKey: string, callback: () -> ())
	local entry = self._entriesByKey[slotKey]
	if entry and entry.frame and entry.button then
		entry.callback = callback
		return entry
	end

	local frame = self:_getTemplate():Clone()
	frame.Name = string.format("Mounted_%s", slotKey)
	frame.Visible = true

	local button = frame:FindFirstChild("Base")
	if not (button and button:IsA("ImageButton")) then
		error(string.format("Mounted slot card template is missing Base for '%s'.", slotKey))
	end

	entry = {
		frame = frame,
		button = button,
		callback = callback,
	}
	self._entriesByKey[slotKey] = entry

	UIController:CreateButton(button, function()
		local currentEntry = self._entriesByKey[slotKey]
		if currentEntry and currentEntry.callback then
			currentEntry.callback()
		end
	end)

	return entry
end

function SlotCardRenderer:_mountFrame(frame: Frame, slotHost: GuiObject)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(1.2, 1.2)
	frame.LayoutOrder = 0
	frame.Visible = true
	frame.Parent = slotHost
end

function SlotCardRenderer:Render(slotKey: string, slotHost: GuiObject, callback: () -> (), payload: any, isSelected: boolean?): ImageButton?
	local entry = self:_ensureEntry(slotKey, callback)
	self:_mountFrame(entry.frame, slotHost)
	BodyPartPresentation.PopulateBundleCard(entry.button, clonePayload(payload, isSelected))
	return entry.button
end

function SlotCardRenderer:Hide(slotKey: string)
	local entry = self._entriesByKey[slotKey]
	if not entry then
		return
	end

	entry.frame.Visible = false
	entry.frame.Parent = nil
end

return SlotCardRenderer
