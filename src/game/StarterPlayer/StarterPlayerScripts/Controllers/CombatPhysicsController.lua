local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatPhysicsController = {}

function CombatPhysicsController:OnStart()
	require(ReplicatedStorage.Shared.Combat.CombatPhysics.ClientController)
end

return CombatPhysicsController
