local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ragdoll = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Ragdoll)

local MinionDeathPresentation = {}

local COLLIDER_NAME = "BossMinionHitboxCollider"
local DEFAULT_DESTROY_DELAY_SECONDS = 2

local function destroyHitboxCollider(minionModel: Model)
	local existingCollider = minionModel:FindFirstChild(COLLIDER_NAME)
	if existingCollider then
		existingCollider:Destroy()
	end
end

function MinionDeathPresentation.PlayAndDestroy(minionModel: Model?, delaySeconds: number?): number
	local resolvedDelay = if typeof(delaySeconds) == "number" and delaySeconds >= 0
		then delaySeconds
		else DEFAULT_DESTROY_DELAY_SECONDS

	if minionModel == nil or minionModel.Parent == nil then
		return resolvedDelay
	end

	minionModel:SetAttribute("Dead", true)
	minionModel:SetAttribute("Died", true)
	destroyHitboxCollider(minionModel)

	local humanoid = minionModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.BreakJointsOnDeath = false
		humanoid.AutoRotate = false
	end

	local ragdoll = Ragdoll.getOrCreate(minionModel)
	ragdoll:Enable(nil)

	task.delay(resolvedDelay, function()
		if minionModel.Parent ~= nil then
			minionModel:Destroy()
		end
	end)

	return resolvedDelay
end

return table.freeze(MinionDeathPresentation)
