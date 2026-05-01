local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

export type DialogueAction = {
	type: string,
	nextNodeId: string?,
	frameName: string?,
	payload: { [string]: any }?,
}

export type DialogueChoice = {
	id: string,
	text: string,
	nextNodeId: string?,
	action: DialogueAction?,
	conditionIds: { string }?,
	conditionBehavior: "hide" | "disable"?,
	disabledText: string?,
}

export type DialogueSession = {
	dialogueId: string?,
	nodeId: string?,
	context: { [string]: any }?,
	setCurrentNode: ((nodeId: string) -> boolean)?,
	closeDialogue: ((afterClose: (() -> ())?) -> ())?,
	runServerAction: ((choice: DialogueChoice, action: DialogueAction) -> boolean)?,
}

export type ActionHandler = (session: DialogueSession, choice: DialogueChoice, action: DialogueAction) -> boolean
export type ConditionPredicate = (session: DialogueSession, conditionId: string) -> boolean

local actionHandlers: { [string]: ActionHandler } = {}
local conditionPredicates: { [string]: ConditionPredicate } = {}

local Registry = {}

function Registry.RegisterAction(actionType: string, handler: ActionHandler)
	if typeof(actionType) ~= "string" or actionType == "" then
		error("Dialogue action type must be a non-empty string.", 2)
	end
	if type(handler) ~= "function" then
		error(string.format("Dialogue action '%s' handler must be a function.", actionType), 2)
	end

	actionHandlers[actionType] = handler
end

function Registry.HasAction(actionType: string): boolean
	return typeof(actionType) == "string" and actionHandlers[actionType] ~= nil
end

function Registry.RunAction(session: DialogueSession, choice: DialogueChoice, action: DialogueAction): boolean
	if typeof(action) ~= "table" or typeof(action.type) ~= "string" or action.type == "" then
		Logger.Warn("[DialogueRegistry] Choice is missing a valid dialogue action type.")
		return false
	end

	local handler = actionHandlers[action.type]
	if handler then
		local ok, result = pcall(handler, session, choice, action)
		if not ok then
			Logger.Warn(string.format("[DialogueRegistry] Action '%s' failed: %s", action.type, tostring(result)))
			return false
		end

		return result == true
	end

	if session and type(session.runServerAction) == "function" then
		return session.runServerAction(choice, action) == true
	end

	Logger.Warn(string.format("[DialogueRegistry] Unsupported action type '%s'.", tostring(action.type)))
	return false
end

function Registry.RegisterCondition(conditionId: string, predicate: ConditionPredicate)
	if typeof(conditionId) ~= "string" or conditionId == "" then
		error("Dialogue condition id must be a non-empty string.", 2)
	end
	if type(predicate) ~= "function" then
		error(string.format("Dialogue condition '%s' predicate must be a function.", conditionId), 2)
	end

	conditionPredicates[conditionId] = predicate
end

function Registry.EvaluateConditions(session: DialogueSession, conditionIds: { string }?): boolean
	if not conditionIds or #conditionIds == 0 then
		return true
	end

	for _, conditionId in ipairs(conditionIds) do
		local predicate = conditionPredicates[conditionId]
		if not predicate then
			Logger.Warn(string.format("[DialogueRegistry] Unknown condition '%s'.", tostring(conditionId)))
			return false
		end

		local ok, result = pcall(predicate, session, conditionId)
		if not ok then
			Logger.Warn(string.format("[DialogueRegistry] Condition '%s' failed: %s", tostring(conditionId), tostring(result)))
			return false
		end

		if result ~= true then
			return false
		end
	end

	return true
end

return Registry
