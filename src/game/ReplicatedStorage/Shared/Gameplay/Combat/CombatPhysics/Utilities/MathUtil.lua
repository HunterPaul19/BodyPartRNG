local MathUtil = {}

function MathUtil.curve(t, p0, p1, p2)
	local inv = 1 - t
	return inv * inv * p0 + 2 * inv * t * p1 + t * t * p2
end

function MathUtil.calculateSpreadDirection(origin, target, minAngle, maxAngle)
	if not origin or not target then
		return Vector3.new(0, 0, 1)
	end

	local baseDirection = target - origin
	if baseDirection.Magnitude <= 0.001 then
		return Vector3.new(0, 0, 1)
	end

	local xSpread = math.random() * ((maxAngle or 0) - (minAngle or 0)) + (minAngle or 0)
	local ySpread = math.random() * ((maxAngle or 0) - (minAngle or 0)) + (minAngle or 0)

	local cf = CFrame.lookAt(origin, target) * CFrame.Angles(math.rad(xSpread), math.rad(ySpread), 0)
	return cf.LookVector
end

return MathUtil
