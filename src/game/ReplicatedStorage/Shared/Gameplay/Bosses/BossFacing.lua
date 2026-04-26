local BossFacing = {}

local PLANAR_EPSILON = 0.001
local DEFAULT_FORWARD = Vector3.new(0, 0, -1)

local function resolvePlanarUnitDirection(vector: Vector3): Vector3?
	local planarDirection = Vector3.new(vector.X, 0, vector.Z)
	if planarDirection.Magnitude <= PLANAR_EPSILON then
		return nil
	end

	return planarDirection.Unit
end

function BossFacing.ResolvePlanarDirection(
	fromPosition: Vector3,
	targetRootPart: BasePart?,
	fallbackPart: BasePart?
): Vector3
	if targetRootPart ~= nil and targetRootPart.Parent ~= nil then
		local targetDirection = resolvePlanarUnitDirection(targetRootPart.Position - fromPosition)
		if targetDirection ~= nil then
			return targetDirection
		end
	end

	if fallbackPart ~= nil and fallbackPart.Parent ~= nil then
		local fallbackDirection = resolvePlanarUnitDirection(fallbackPart.CFrame.LookVector)
		if fallbackDirection ~= nil then
			return fallbackDirection
		end
	end

	return DEFAULT_FORWARD
end

function BossFacing.BuildRootFacingCFrame(bossRootPart: BasePart, targetRootPart: BasePart?): CFrame
	local direction = BossFacing.ResolvePlanarDirection(bossRootPart.Position, targetRootPart, bossRootPart)
	return CFrame.lookAt(bossRootPart.Position, bossRootPart.Position + direction)
end

function BossFacing.FaceModelTowardTarget(
	bossModel: Model,
	bossRootPart: BasePart,
	targetRootPart: BasePart?
): Vector3?
	if bossModel.Parent == nil or bossRootPart.Parent == nil then
		return nil
	end

	local currentRootCFrame = bossRootPart.CFrame
	local currentPivot = bossModel:GetPivot()
	local rootToPivot = currentRootCFrame:ToObjectSpace(currentPivot)
	local targetRootCFrame = BossFacing.BuildRootFacingCFrame(bossRootPart, targetRootPart)

	bossModel:PivotTo(targetRootCFrame * rootToPivot)
	return targetRootCFrame.LookVector
end

return table.freeze(BossFacing)
