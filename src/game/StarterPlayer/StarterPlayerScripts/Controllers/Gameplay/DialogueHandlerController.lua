local DialogueClientHandlers = require(script.Parent.DialogueClientHandlers)

local DialogueHandlerController = {
	_started = false,
}

function DialogueHandlerController:OnStart()
	if self._started then
		return
	end

	DialogueClientHandlers.Register()
	self._started = true
end

return DialogueHandlerController
