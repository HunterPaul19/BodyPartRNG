local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local TestService = {}

function TestService:OnStart()
	Logger.Print("TestService initialized!")
end

function TestService:OnPlayerAdded(player: Player)
	Logger.Print("TestService recognized new player", player)
end

function TestService:OnPlayerRemoving(player: Player)
	Logger.Print("TestService recognized player disconnect", player)
end

return TestService
