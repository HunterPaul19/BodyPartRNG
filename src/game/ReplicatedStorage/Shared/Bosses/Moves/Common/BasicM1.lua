local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animation = require(ReplicatedStorage.Shared.Animation)
local CombatMoveUtil = require(ReplicatedStorage.Shared.Combat.CombatMoveUtil)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local createBossStubMove = require(ReplicatedStorage.Shared.Bosses.Moves.Common.CreateBossStubMove)

local DAMAGE = 20
local HITBOX_DURATION_SECONDS = 0.12
local ANIMATION_FADE_SECONDS = 0.08
local HITBOX_WIDTH_SCALE = 1.9
local HITBOX_HEIGHT_SCALE = 1.6
local HITBOX_DEPTH_SCALE = 5.5
local HITBOX_FORWARD_OFFSET_SCALE = 2.5
local DEFAULT_M1_FOLDER_NAME = "M1"
local IMPACT_MARKER_NAME = "Impact"

local stub = createBossStubMove({
	moveLabel = "Boss M1",
	targetMode = "single",
	summaryTemplate = "{moveLabel} -> {target}",
})

local warnedMissingFolders = {}
local animationHasImpactCache = {}

local BasicM1 = {
	CanUse = stub.CanUse,
	GetTargeting = stub.GetTargeting,
	ExecuteStub = stub.ExecuteStub,
}

local function warnMissingFolderOnce(folderPath: string)
	if warnedMissingFolders[folderPath] == true then
		return
	end

	warnedMissingFolders[folderPath] = true
	warn(string.format("[BasicM1] Missing or empty animation folder '%s'. Falling back to default M1 folder.", folderPath))
end

local function resolveHumanoid(model: Model?): Humanoid?
	if model == nil then
		return nil
	end

	return model:FindFirstChildOfClass("Humanoid")
end

local function collectAnimations(folder: Folder?): { Animation }
	local animations = {}
	if folder == nil then
		return animations
	end

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Animation") then
			table.insert(animations, child)
		end
	end

	return animations
end

local function resolveAnimationsRoot(): Folder?
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	if not (gameAssets and gameAssets:IsA("Folder")) then
		return nil
	end

	local animations = gameAssets:FindFirstChild("Animations")
	if animations and animations:IsA("Folder") then
		return animations
	end

	return nil
end

local function resolveAnimationChoices(context): { Animation }
	local animationsRoot = resolveAnimationsRoot()
	if animationsRoot == nil then
		return {}
	end

	local folderName = context.move.animationFolderName
	if typeof(folderName) == "string" and folderName ~= "" then
		local customFolderPath = string.format("ReplicatedStorage.GameAssets.Animations.%s.%s", folderName, DEFAULT_M1_FOLDER_NAME)
		local parentFolder = animationsRoot:FindFirstChild(folderName)
		local customFolder = parentFolder and parentFolder:FindFirstChild(DEFAULT_M1_FOLDER_NAME)
		if customFolder and customFolder:IsA("Folder") then
			local customAnimations = collectAnimations(customFolder)
			if #customAnimations > 0 then
				return customAnimations
			end
		end

		warnMissingFolderOnce(customFolderPath)
	end

	local defaultFolder = animationsRoot:FindFirstChild(DEFAULT_M1_FOLDER_NAME)
	if defaultFolder and defaultFolder:IsA("Folder") then
		return collectAnimations(defaultFolder)
	end

	return {}
end

local function chooseAnimation(context): Animation?
	local animations = resolveAnimationChoices(context)
	if #animations <= 0 then
		warn("[BasicM1] Missing default animation folder 'ReplicatedStorage.GameAssets.Animations.M1'.")
		return nil
	end

	return animations[math.random(1, #animations)]
end

local function animationHasImpactMarker(animationInstance: Animation): boolean
	local cacheKey = animationInstance.AnimationId
	local cached = animationHasImpactCache[cacheKey]
	if cached ~= nil then
		return cached
	end

	local ok, keyframeSequence = pcall(function()
		return KeyframeSequenceProvider:GetKeyframeSequenceAsync(animationInstance.AnimationId)
	end)
	if not ok or keyframeSequence == nil then
		warn(string.format("[BasicM1] Failed to fetch keyframes for '%s': %s", animationInstance.Name, tostring(keyframeSequence)))
		animationHasImpactCache[cacheKey] = false
		return false
	end

	for _, keyframe in ipairs(keyframeSequence:GetKeyframes()) do
		for _, marker in ipairs(keyframe:GetMarkers()) do
			if marker.Name == IMPACT_MARKER_NAME then
				animationHasImpactCache[cacheKey] = true
				return true
			end
		end
	end

	animationHasImpactCache[cacheKey] = false
	return false
end

local function resolvePlanarDirection(bossRootPart: BasePart, targetRootPart: BasePart?): Vector3
	local direction = Vector3.new(bossRootPart.CFrame.LookVector.X, 0, bossRootPart.CFrame.LookVector.Z)

	if targetRootPart and targetRootPart.Parent ~= nil then
		local offset = targetRootPart.Position - bossRootPart.Position
		local planarOffset = Vector3.new(offset.X, 0, offset.Z)
		if planarOffset.Magnitude > 0.001 then
			direction = planarOffset
		end
	end

	if direction.Magnitude <= 0.001 then
		return Vector3.new(0, 0, -1)
	end

	return direction.Unit
end

local function resolveHitboxSizeAndOffset(bossRootPart: BasePart): (Vector3, number)
	local rootSize = bossRootPart.Size
	return Vector3.new(
		rootSize.X * HITBOX_WIDTH_SCALE,
		rootSize.Y * HITBOX_HEIGHT_SCALE,
		rootSize.Z * HITBOX_DEPTH_SCALE
	), rootSize.Z * HITBOX_FORWARD_OFFSET_SCALE
end

function BasicM1.StartCast(context)
	local bossModel = context.bossModel
	local bossRootPart = context.bossRootPart
	if bossModel == nil or bossModel.Parent == nil or bossRootPart == nil or bossRootPart.Parent == nil then
		return nil
	end

	local animationInstance = chooseAnimation(context)
	if animationInstance == nil then
		return nil
	end

	if animationHasImpactMarker(animationInstance) ~= true then
		warn(string.format("[BasicM1] Animation '%s' is missing the '%s' marker.", animationInstance.Name, IMPACT_MARKER_NAME))
		return nil
	end

	local profileOk, profileOrError = pcall(Animation.new, bossModel)
	if not profileOk or profileOrError == nil then
		warn("[BasicM1] Failed to create animation profile:", profileOrError)
		return nil
	end

	local profile = profileOrError
	local activeHitbox = nil
	local impactTriggered = false
	local completed = false
	local cancelled = false
	local cleanedUp = false
	local hitTargets = {}
	local stoppedConnection = nil
	local hitboxSize, hitboxForwardOffset = resolveHitboxSizeAndOffset(bossRootPart)

	local function disconnectStoppedConnection()
		if stoppedConnection and stoppedConnection.Connected then
			stoppedConnection:Disconnect()
		end
		stoppedConnection = nil
	end

	local function destroyHitbox()
		if activeHitbox == nil then
			return
		end

		activeHitbox:Destroy()
		activeHitbox = nil
	end

	local function markComplete()
		if completed then
			return
		end

		completed = true
		destroyHitbox()
	end

	local function cleanup(stopAnimation: boolean)
		if cleanedUp then
			return
		end

		cleanedUp = true
		destroyHitbox()
		disconnectStoppedConnection()

		if stopAnimation then
			profile:StopAnimation(animationInstance, ANIMATION_FADE_SECONDS)
		end
	end

	local function handleImpact()
		if cancelled or impactTriggered or bossModel.Parent == nil or bossRootPart.Parent == nil then
			return
		end

		impactTriggered = true
		destroyHitbox()

		local hitbox
		hitbox = Hitbox.new({
			DebugVisibilityAttribute = "BossHitboxesVisible",
			Character = bossModel,
			HitboxCFrame = function()
				if bossRootPart.Parent == nil then
					return nil
				end

				local planarDirection = resolvePlanarDirection(bossRootPart, context.targetRootPart)
				return CFrame.lookAt(bossRootPart.Position, bossRootPart.Position + planarDirection)
			end,
			HitboxOffset = CFrame.new(0, 0, -hitboxForwardOffset),
			HitboxSize = hitboxSize,
			HitboxType = "SpacialQuery",
			Time = HITBOX_DURATION_SECONDS,
			MaxParts = 48,
		}, {
			HitTarget = function(targetModel: Model)
				if cleanedUp or hitTargets[targetModel] == true then
					return
				end

				local player = Players:GetPlayerFromCharacter(targetModel)
				if player == nil then
					return
				end

				local humanoid = resolveHumanoid(targetModel)
				if humanoid == nil or humanoid.Health <= 0 then
					return
				end

				hitTargets[targetModel] = true
				humanoid:TakeDamage(CombatMoveUtil.ResolveScaledBossDamage(context, DAMAGE))
			end,
			HitboxDestroy = function()
				if activeHitbox == hitbox then
					activeHitbox = nil
				end
			end,
		})

		activeHitbox = hitbox
	end

	local track = profile:PlayAnimation(animationInstance, Enum.AnimationPriority.Action, 1, {
		Impact = handleImpact,
		End = markComplete,
	}, ANIMATION_FADE_SECONDS)
	if track == nil then
		warn(string.format("[BasicM1] Failed to play animation '%s'.", animationInstance.Name))
		return nil
	end

	track.Looped = false
	stoppedConnection = track.Stopped:Connect(function()
		disconnectStoppedConnection()
		destroyHitbox()
		if not impactTriggered then
			warn(string.format("[BasicM1] Animation '%s' completed without firing '%s'.", animationInstance.Name, IMPACT_MARKER_NAME))
		end
		markComplete()
	end)

	return {
		Cancel = function()
			if cancelled then
				return
			end

			cancelled = true
			completed = true
			cleanup(true)
		end,
		IsComplete = function()
			return completed
		end,
	}
end

return table.freeze(BasicM1)
