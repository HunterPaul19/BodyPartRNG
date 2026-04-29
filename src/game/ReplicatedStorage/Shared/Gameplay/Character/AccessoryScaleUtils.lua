local AccessoryScaleUtils = {}

local function scaleVectorBySizeRatio(vector: Vector3, sourceSize: Vector3, targetSize: Vector3): Vector3
	return Vector3.new(
		sourceSize.X ~= 0 and vector.X * targetSize.X / sourceSize.X or vector.X,
		sourceSize.Y ~= 0 and vector.Y * targetSize.Y / sourceSize.Y or vector.Y,
		sourceSize.Z ~= 0 and vector.Z * targetSize.Z / sourceSize.Z or vector.Z
	)
end

local function isFinitePositive(value: number): boolean
	return value == value and value > 0 and value < math.huge
end

local function addAxisRatio(total: number, count: number, sourceAxis: number, targetAxis: number): (number, number)
	if sourceAxis == 0 then
		return total, count
	end

	local ratio = targetAxis / sourceAxis
	if not isFinitePositive(ratio) then
		return total, count
	end

	return total + ratio, count + 1
end

function AccessoryScaleUtils.ScaleAttachmentLocalCFrame(
	sourceAttachmentCFrame: CFrame,
	sourcePartSize: Vector3,
	targetPartSize: Vector3
): CFrame
	return CFrame.new(scaleVectorBySizeRatio(sourceAttachmentCFrame.Position, sourcePartSize, targetPartSize))
		* sourceAttachmentCFrame.Rotation
end

function AccessoryScaleUtils.ComputeUniformScaleFactor(sourcePartSize: Vector3, targetPartSize: Vector3): number
	if sourcePartSize == targetPartSize then
		return 1
	end

	local total = 0
	local count = 0

	total, count = addAxisRatio(total, count, sourcePartSize.X, targetPartSize.X)
	total, count = addAxisRatio(total, count, sourcePartSize.Y, targetPartSize.Y)
	total, count = addAxisRatio(total, count, sourcePartSize.Z, targetPartSize.Z)

	if count == 0 then
		return 1
	end

	local factor = total / count
	return if isFinitePositive(factor) then factor else 1
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

function AccessoryScaleUtils.ScaleModelToPartSize(
	model: Model,
	sourcePartSize: Vector3,
	targetPartSize: Vector3
): (boolean, string?)
	local factor = AccessoryScaleUtils.ComputeUniformScaleFactor(sourcePartSize, targetPartSize)
	if factor == 1 then
		return true, nil
	end

	local currentScale = model:GetScale()
	local targetScale = currentScale * factor
	if not isFinitePositive(targetScale) then
		return false, string.format("Model %s resolved an invalid accessory scale.", model.Name)
	end

	local scaled, scaleError = pcall(function()
		model:ScaleTo(targetScale)
	end)
	if not scaled then
		return false, string.format("Failed to scale model %s: %s", model.Name, tostring(scaleError))
	end

	return true, nil
end

return AccessoryScaleUtils
