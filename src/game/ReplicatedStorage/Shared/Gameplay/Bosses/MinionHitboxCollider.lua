local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConstants = require(ReplicatedStorage.Shared.Combat.Constants)

local MinionHitboxCollider = {}

local COLLIDER_NAME = "BossMinionHitboxCollider"
local WELD_NAME = "BossMinionHitboxColliderWeld"
local HORIZONTAL_SIZE_MULTIPLIER = 2
local VERTICAL_PADDING_STUDS = 0

function MinionHitboxCollider.Destroy(minionModel: Model?)
	if minionModel == nil then
		return
	end

	local existingCollider = minionModel:FindFirstChild(COLLIDER_NAME)
	if existingCollider then
		existingCollider:Destroy()
	end
end

function MinionHitboxCollider.Attach(minionModel: Model?, rootPart: BasePart?): BasePart?
	if minionModel == nil or rootPart == nil then
		return nil
	end
	if minionModel.Parent == nil or rootPart.Parent == nil or not rootPart:IsDescendantOf(minionModel) then
		return nil
	end

	MinionHitboxCollider.Destroy(minionModel)

	local boundingCFrame, boundingSize = minionModel:GetBoundingBox()
	local collider = Instance.new("Part")
	collider.Name = COLLIDER_NAME
	collider.Size = Vector3.new(
		math.max(0.1, boundingSize.X * HORIZONTAL_SIZE_MULTIPLIER),
		math.max(0.1, boundingSize.Y + VERTICAL_PADDING_STUDS),
		math.max(0.1, boundingSize.Z * HORIZONTAL_SIZE_MULTIPLIER)
	)
	collider.CFrame = boundingCFrame
	collider.Transparency = 1
	collider.Anchored = false
	collider.CanCollide = false
	collider.CanTouch = false
	collider.CanQuery = true
	collider.Massless = true
	collider.CollisionGroup = CombatConstants.COLLISION_GROUPS.BossBody
	collider.Parent = minionModel

	local weld = Instance.new("WeldConstraint")
	weld.Name = WELD_NAME
	weld.Part0 = rootPart
	weld.Part1 = collider
	weld.Parent = collider

	return collider
end

return table.freeze(MinionHitboxCollider)
