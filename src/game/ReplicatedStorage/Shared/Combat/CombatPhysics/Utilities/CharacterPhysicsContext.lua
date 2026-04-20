local Players = game:GetService("Players")

local BodyMoverUtil = require(script.Parent.BodyMoverUtil)
local StateUtil = require(script.Parent.StateUtil)
local AnimationUtil = require(script.Parent.AnimationUtil)

local CharacterPhysicsContext = {}
CharacterPhysicsContext.__index = CharacterPhysicsContext

local function resolveRootPart(character)
	return character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
end

function CharacterPhysicsContext.fromCharacter(character)
	if not character or not character:IsA("Model") then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = resolveRootPart(character)
	if not humanoid or not rootPart then
		return nil
	end

	local self = {
		character = character,
		humanoid = humanoid,
		rootPart = rootPart,
		player = Players:GetPlayerFromCharacter(character),
	}

	return setmetatable(self, CharacterPhysicsContext)
end

function CharacterPhysicsContext:refresh()
	self.humanoid = self.character:FindFirstChildOfClass("Humanoid")
	self.rootPart = resolveRootPart(self.character)
	self.player = Players:GetPlayerFromCharacter(self.character)
	return self.humanoid ~= nil and self.rootPart ~= nil
end

function CharacterPhysicsContext:setCollisionGroup(groupName)
	if not groupName then
		return
	end
	for _, instance in ipairs(self.character:GetDescendants()) do
		if instance:IsA("BasePart") then
			pcall(function()
				instance.CollisionGroup = groupName
			end)
		end
	end
end

function CharacterPhysicsContext:setNetworkOwner(player)
	if not self.rootPart then
		return
	end
	pcall(function()
		self.rootPart:SetNetworkOwner(player)
	end)
end

function CharacterPhysicsContext:clearBodymovers()
	BodyMoverUtil.clear(self.character)
end

function CharacterPhysicsContext:createState(stateName, duration)
	StateUtil.createState(self.character, stateName, duration)
end

function CharacterPhysicsContext:removeState(stateName)
	StateUtil.removeState(self.character, stateName)
end

function CharacterPhysicsContext:createMovement(propertyName, propertyValue, duration)
	StateUtil.createMovement(self.character, propertyName, propertyValue, duration)
end

function CharacterPhysicsContext:getBuffMultiplier(buffName)
	return StateUtil.getBuffMultiplier(self.character, buffName)
end

function CharacterPhysicsContext:playAnimation(animation, fadeTime, speed)
	return AnimationUtil.play(self.character, self.humanoid, animation, fadeTime, speed)
end

function CharacterPhysicsContext:stopAnimation(animation)
	AnimationUtil.stop(self.character, animation)
end

return CharacterPhysicsContext
