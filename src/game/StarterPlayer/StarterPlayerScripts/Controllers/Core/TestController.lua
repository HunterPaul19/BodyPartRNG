local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local TestController = {}

function TestController:OnStart()
	Logger.Print("TestController client initialized!")
end

return TestController
