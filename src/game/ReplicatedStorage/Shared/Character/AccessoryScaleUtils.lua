local AccessoryScaleUtils = {}

local function scaleVectorBySizeRatio(vector: Vector3, sourceSize: Vector3, targetSize: Vector3): Vector3
	return Vector3.new(
		sourceSize.X ~= 0 and vector.X * targetSize.X / sourceSize.X or vector.X,
		sourceSize.Y ~= 0 and vector.Y * targetSize.Y / sourceSize.Y or vector.Y,
		sourceSize.Z ~= 0 and vector.Z * targetSize.Z / sourceSize.Z or vector.Z
	)
end

function AccessoryScaleUtils.ScaleAccessoryToPartSize(
	accessory: Accessory,
	sourcePartSize: Vector3,
	targetPartSize: Vector3
): (boolean, string?)
	local handle = accessory:FindFirstChild("Handle")
	if not (handle and handle:IsA("BasePart")) then
		return false, string.format("Accessory %s is missing a Handle.", accessory.Name)
	end

	if sourcePartSize == targetPartSize then
		return true, nil
	end

	handle.Size = scaleVectorBySizeRatio(handle.Size, sourcePartSize, targetPartSize)

	for _, descendant in ipairs(handle:GetDescendants()) do
		if descendant:IsA("SpecialMesh") then
			descendant.Scale = scaleVectorBySizeRatio(descendant.Scale, sourcePartSize, targetPartSize)
		elseif descendant:IsA("Attachment") then
			descendant.Position = scaleVectorBySizeRatio(descendant.Position, sourcePartSize, targetPartSize)
		end
	end

	return true, nil
end

return AccessoryScaleUtils
