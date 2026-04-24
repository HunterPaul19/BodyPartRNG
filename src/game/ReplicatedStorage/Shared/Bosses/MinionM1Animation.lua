local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animation = require(ReplicatedStorage.Shared.Animation)

local M1_FOLDER_NAME = "M1"
local ANIMATION_FADE_SECONDS = 0.08

local MinionM1Animation = {}

local cachedAnimations = nil :: { Animation }?
local warnedKeys = {}
local activeTrackByMinion = setmetatable({}, { __mode = "kv" }) :: { [Model]: AnimationTrack }

local function warnOnce(warningPrefix: string?, key: string, message: string, detail: any?)
	local resolvedKey = string.format("%s:%s", tostring(warningPrefix), key)
	if warnedKeys[resolvedKey] == true then
		return
	end

	warnedKeys[resolvedKey] = true
	local prefix = if typeof(warningPrefix) == "string" and warningPrefix ~= "" then warningPrefix else "MinionM1Animation"
	if detail ~= nil then
		warn(string.format("[%s] %s", prefix, message), detail)
	else
		warn(string.format("[%s] %s", prefix, message))
	end
end

local function collectM1Animations(): { Animation }
	if cachedAnimations ~= nil then
		return cachedAnimations
	end

	local animations = {}
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	local animationRoot = gameAssets and gameAssets:FindFirstChild("Animations")
	local m1Folder = animationRoot and animationRoot:FindFirstChild(M1_FOLDER_NAME)
	if m1Folder and m1Folder:IsA("Folder") then
		for _, child in ipairs(m1Folder:GetChildren()) do
			if child:IsA("Animation") then
				table.insert(animations, child)
			end
		end
	end

	table.sort(animations, function(left: Animation, right: Animation)
		return left.Name < right.Name
	end)

	if #animations > 0 then
		cachedAnimations = animations
	end

	return animations
end

local function chooseM1Animation(): Animation?
	local animations = collectM1Animations()
	if #animations <= 0 then
		return nil
	end

	return animations[math.random(1, #animations)]
end

function MinionM1Animation.PlayAttack(minionModel: Model, warningPrefix: string?): AnimationTrack?
	if minionModel == nil or minionModel.Parent == nil then
		return nil
	end

	local animationInstance = chooseM1Animation()
	if animationInstance == nil then
		warnOnce(
			warningPrefix,
			"missing_m1_animations",
			"Missing or empty animation folder ReplicatedStorage.GameAssets.Animations.M1."
		)
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, minionModel)
	if not profileOk or profileOrError == nil then
		warnOnce(warningPrefix, "profile", "Failed to create minion animation profile:", profileOrError)
		return nil
	end

	local previousTrack = activeTrackByMinion[minionModel]
	if previousTrack ~= nil and previousTrack.IsPlaying then
		pcall(function()
			previousTrack:Stop(ANIMATION_FADE_SECONDS)
		end)
	end

	local profile = profileOrError
	local track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, nil, ANIMATION_FADE_SECONDS)
	if track == nil then
		warnOnce(
			warningPrefix,
			string.format("play_%s", animationInstance.Name),
			string.format("Failed to play minion M1 animation '%s'.", animationInstance.Name)
		)
		return nil
	end

	track.Looped = false
	activeTrackByMinion[minionModel] = track
	return track
end

return table.freeze(MinionM1Animation)
