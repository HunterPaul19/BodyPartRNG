local BossPhysicsStabilizer = {}

local UNSTABLE_HUMANOID_STATES = {
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.PlatformStanding,
}

local MAX_ROOT_PRIORITY = 127

local function setStateEnabled(humanoid: Humanoid, state: Enum.HumanoidStateType, isEnabled: boolean)
	pcall(function()
		humanoid:SetStateEnabled(state, isEnabled)
	end)
end

local function changeState(humanoid: Humanoid, state: Enum.HumanoidStateType)
	pcall(function()
		humanoid:ChangeState(state)
	end)
end

function BossPhysicsStabilizer.ResetMotion(bossModel: Model)
	for _, descendant in ipairs(bossModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

function BossPhysicsStabilizer.RecoverHumanoid(humanoid: Humanoid)
	for _, state in ipairs(UNSTABLE_HUMANOID_STATES) do
		setStateEnabled(humanoid, state, false)
	end

	humanoid.PlatformStand = false
	humanoid.Sit = false
	changeState(humanoid, Enum.HumanoidStateType.GettingUp)
	changeState(humanoid, Enum.HumanoidStateType.Running)
end

function BossPhysicsStabilizer.Apply(bossModel: Model, humanoid: Humanoid, rootPart: BasePart)
	rootPart.RootPriority = MAX_ROOT_PRIORITY

	for _, descendant in ipairs(bossModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if descendant ~= rootPart then
				descendant.Massless = true
				descendant.CanCollide = false
			end

			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end

	BossPhysicsStabilizer.RecoverHumanoid(humanoid)
end

function BossPhysicsStabilizer.Recover(bossModel: Model, humanoid: Humanoid)
	BossPhysicsStabilizer.ResetMotion(bossModel)
	BossPhysicsStabilizer.RecoverHumanoid(humanoid)
end

return table.freeze(BossPhysicsStabilizer)
