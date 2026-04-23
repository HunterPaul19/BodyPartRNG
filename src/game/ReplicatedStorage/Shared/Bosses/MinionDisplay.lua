local MinionDisplay = {}

local DEFAULT_DISPLAY_DISTANCE = 120

function MinionDisplay.ConfigureHumanoid(humanoid: Humanoid, displayName: string, displayDistance: number?)
	local resolvedDistance = if typeof(displayDistance) == "number" and displayDistance > 0
		then displayDistance
		else DEFAULT_DISPLAY_DISTANCE

	humanoid.DisplayName = displayName
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
	humanoid.NameDisplayDistance = resolvedDistance
	humanoid.HealthDisplayDistance = resolvedDistance
end

return table.freeze(MinionDisplay)
