local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DialogueDefinitions = require(ReplicatedStorage.Shared.Config.DialogueDefinitions)

local DefinitionUtil = {}

function DefinitionUtil.GetDefinition(dialogueId: string)
	if typeof(dialogueId) ~= "string" or dialogueId == "" then
		return nil
	end

	return DialogueDefinitions.Get(dialogueId)
end

function DefinitionUtil.GetNode(dialogueId: string, nodeId: string)
	local definition = DefinitionUtil.GetDefinition(dialogueId)
	if not definition then
		return nil
	end

	if typeof(nodeId) ~= "string" or nodeId == "" then
		return nil
	end

	return definition.nodesById[nodeId]
end

function DefinitionUtil.GetChoice(dialogueId: string, nodeId: string, choiceId: string)
	local node = DefinitionUtil.GetNode(dialogueId, nodeId)
	if not node then
		return nil, nil
	end

	if typeof(choiceId) ~= "string" or choiceId == "" then
		return node, nil
	end

	for _, choice in ipairs(node.choices) do
		if choice.id == choiceId then
			return node, choice
		end
	end

	return node, nil
end

return DefinitionUtil
