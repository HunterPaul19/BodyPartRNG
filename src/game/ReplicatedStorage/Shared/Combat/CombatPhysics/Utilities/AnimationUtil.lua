local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animation = require(ReplicatedStorage.Shared.Animation)

local AnimationUtil = {}

function AnimationUtil.getPathingFolders()
	return Animation.GetPrimaryAssetContainer()
end

function AnimationUtil.play(character, humanoid, animation, fadeTime, speed)
	if not character or not humanoid or not animation or not animation:IsA("Animation") then
		return nil
	end

	local ok, profile = pcall(Animation.new, character)
	if not ok or not profile then
		return nil
	end

	return profile:PlayAnimation(animation, nil, speed, nil, fadeTime)
end

function AnimationUtil.stop(character, animation)
	if not character or not animation then
		return
	end

	local profile = Animation.GetProfile(character)
	if not profile then
		return
	end

	profile:StopAnimation(animation, 0.1)
end

return AnimationUtil
