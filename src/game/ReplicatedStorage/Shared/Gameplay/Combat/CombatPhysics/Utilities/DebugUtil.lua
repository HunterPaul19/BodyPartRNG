local Debris = game:GetService("Debris")

local DebugUtil = {}

function DebugUtil.createDebugPart(position, size)
	if typeof(position) ~= "Vector3" then
		return nil
	end

	local resolvedSize
	if typeof(size) == "Vector3" then
		resolvedSize = size
	else
		local scalarSize = tonumber(size) or 1
		resolvedSize = Vector3.new(scalarSize, scalarSize, scalarSize)
	end

	local debugPart = Instance.new("Part")
	debugPart.Name = "CombatPhysicsDebug"
	debugPart.Anchored = true
	debugPart.CanCollide = false
	debugPart.Material = Enum.Material.Neon
	debugPart.Color = Color3.fromRGB(255, 98, 71)
	debugPart.Transparency = 0.35
	debugPart.Size = resolvedSize
	debugPart.Position = position
	debugPart.Parent = workspace:FindFirstChild("Visuals") or workspace

	Debris:AddItem(debugPart, 0.5)
	return debugPart
end

return DebugUtil
