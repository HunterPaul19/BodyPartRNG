local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local DialogueController = require(script.Parent.DialogueController)

local LOCAL_PLAYER = Players.LocalPlayer
local DIALOGUE_ID_ATTRIBUTE = "DialogueId"
local SHOP_FRAME_ATTRIBUTE = "ShopFrameName"

local DialogueInteractionController = {
	_started = false,
	_clickConnections = {} :: { [ClickDetector]: RBXScriptConnection },
	_connections = {} :: { RBXScriptConnection },
}

local function readStringAttribute(instance: Instance?, attributeName: string): string?
	local current = instance
	while current do
		local value = current:GetAttribute(attributeName)
		if typeof(value) == "string" and value ~= "" then
			return value
		end
		current = current.Parent
	end

	return nil
end

local function buildContext(source: Instance, interactionType: string): { [string]: any }
	return {
		interactionType = interactionType,
		sourceInstance = source,
		shopFrameName = readStringAttribute(source, SHOP_FRAME_ATTRIBUTE),
	}
end

local function resolveDialogueId(source: Instance): string?
	return readStringAttribute(source, DIALOGUE_ID_ATTRIBUTE)
end

function DialogueInteractionController:_handleInteraction(source: Instance, interactionType: string)
	local dialogueId = resolveDialogueId(source)
	if not dialogueId then
		return
	end

	DialogueController.StartDialogue(dialogueId, buildContext(source, interactionType))
end

function DialogueInteractionController:_bindClickDetector(detector: ClickDetector)
	if self._clickConnections[detector] then
		return
	end

	self._clickConnections[detector] = detector.MouseClick:Connect(function(player: Player)
		if player ~= LOCAL_PLAYER then
			return
		end

		self:_handleInteraction(detector, "clickDetector")
	end)
end

function DialogueInteractionController:_refreshClickDetectors()
	for detector, connection in pairs(self._clickConnections) do
		if not detector.Parent then
			connection:Disconnect()
			self._clickConnections[detector] = nil
		end
	end

	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("ClickDetector") then
			self:_bindClickDetector(descendant)
		end
	end
end

function DialogueInteractionController:OnStart()
	if self._started then
		return
	end

	self._started = true

	table.insert(self._connections, ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player?)
		if player and player ~= LOCAL_PLAYER then
			return
		end

		self:_handleInteraction(prompt, "proximityPrompt")
	end))

	self:_refreshClickDetectors()

	table.insert(self._connections, Workspace.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("ClickDetector") then
			self:_bindClickDetector(descendant)
		end
	end))

	table.insert(self._connections, Workspace.DescendantRemoving:Connect(function(descendant: Instance)
		if not descendant:IsA("ClickDetector") then
			return
		end

		local connection = self._clickConnections[descendant]
		if connection then
			connection:Disconnect()
			self._clickConnections[descendant] = nil
		end
	end))
end

return DialogueInteractionController
