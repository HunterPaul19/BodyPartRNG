local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local DialogueController = require(script.Parent.DialogueController)
local MerchantPresentationController = require(script.Parent.MerchantPresentationController)

local LOCAL_PLAYER = Players.LocalPlayer
local DIALOGUE_ID_ATTRIBUTE = "DialogueId"
local DIALOGUE_FRAME_ATTRIBUTE = "DialogueFrameName"
local DIALOGUE_CAMERA_PART_ATTRIBUTE = "DialogueCameraPartName"
local SHOP_FRAME_ATTRIBUTE = "ShopFrameName"
local SHOP_CAMERA_PART_ATTRIBUTE = "ShopCameraPartName"

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

local function findNamedBasePart(root: Instance, targetName: string): BasePart?
	local current = root
	if current:IsA("BasePart") and current.Name == targetName then
		return current
	end

	local found = root:FindFirstChild(targetName, true)
	if found and found:IsA("BasePart") then
		return found
	end

	return nil
end

local function resolveDialogueCameraPart(source: Instance): BasePart?
	local targetName = readStringAttribute(source, DIALOGUE_CAMERA_PART_ATTRIBUTE)
		or readStringAttribute(source, SHOP_CAMERA_PART_ATTRIBUTE)
	if not targetName then
		return nil
	end

	local current: Instance? = source
	while current do
		local resolved = findNamedBasePart(current, targetName)
		if resolved then
			return resolved
		end
		current = current.Parent
	end

	return nil
end

local function resolveSpeakerModel(source: Instance): Model?
	local current: Instance? = source
	while current do
		if current:IsA("Model") then
			local humanoid = current:FindFirstChildWhichIsA("Humanoid")
			if humanoid then
				return current
			end
		end
		current = current.Parent
	end

	return nil
end

local function buildContext(source: Instance, interactionType: string): { [string]: any }
	return {
		interactionType = interactionType,
		sourceInstance = source,
		speakerModel = resolveSpeakerModel(source),
		dialogueFrameName = readStringAttribute(source, DIALOGUE_FRAME_ATTRIBUTE)
			or readStringAttribute(source, SHOP_FRAME_ATTRIBUTE),
		dialogueCameraPart = resolveDialogueCameraPart(source),
	}
end

local function resolveDialogueId(source: Instance): string?
	return readStringAttribute(source, DIALOGUE_ID_ATTRIBUTE)
end

function DialogueInteractionController:_handleInteraction(source: Instance, interactionType: string)
	if MerchantPresentationController:IsOpen() then
		return
	end

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
