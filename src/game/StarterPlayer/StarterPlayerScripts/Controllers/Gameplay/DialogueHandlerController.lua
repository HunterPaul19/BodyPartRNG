local DialogueClientHandlers = require(script.Parent.DialogueClientHandlers)

local DialogueHandlerController = {
	_started = false,
}

function DialogueHandlerController:OnStart()
	if self._started then
		return
	end

	self._started = true
	DialogueClientHandlers.Register()
end

return DialogueHandlerController
