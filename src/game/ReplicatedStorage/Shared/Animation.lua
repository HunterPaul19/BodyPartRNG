local ContentProvider = game:GetService("ContentProvider")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

type AnimationEvents = {
	[string]: (...any) -> (),
}

type MarkerCacheEntry = {
	name: string,
	thread: thread,
}

type MarkerBindingHandle = {
	Cancel: () -> (),
	MarkerCache: { MarkerCacheEntry },
}

type TrackBindingState = {
	connections: { RBXScriptConnection },
	cleanups: { () -> () },
}

export type Profile = typeof(setmetatable({} :: {
	_character: Model,
	_humanoid: Humanoid,
	_animator: Animator,
	_loadedAnimationTracks: { [Animation]: AnimationTrack },
	_trackBindings: { [AnimationTrack]: TrackBindingState },
	_trackStopConnections: { [AnimationTrack]: RBXScriptConnection },
	_lifetimeConnections: { RBXScriptConnection },
	_lastPlayedAnimation: Animation?,
	_animateOverridesFolder: Folder?,
	_destroyed: boolean,
}, {}))

local Animation = {}
Animation.__index = Animation
Animation._profiles = setmetatable({}, { __mode = "k" })

local resolvedAnimationRootsCache = nil :: { Instance }?
local replicatedAnimationsCache = nil :: { Animation }?

local function addUniqueInstance(list: { Instance }, seen: { [Instance]: boolean }, instance: Instance?)
	if not instance or seen[instance] == true then
		return
	end

	seen[instance] = true
	table.insert(list, instance)
end

local function addUniqueAnimation(list: { Animation }, seen: { [Animation]: boolean }, animation: Animation?)
	if not animation or seen[animation] == true then
		return
	end

	seen[animation] = true
	table.insert(list, animation)
end

local function getAnimatorFromHumanoid(humanoid: Humanoid): Animator
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end

	local createdAnimator = Instance.new("Animator")
	createdAnimator.Parent = humanoid
	return createdAnimator
end

local function getHumanoidFromCharacter(character: Model): Humanoid?
	return character:FindFirstChildOfClass("Humanoid")
end

local function isAnimationEventsTable(value: any): boolean
	return typeof(value) == "table"
end

local function warnWithPrefix(message: string, detail: any?)
	if detail == nil then
		warn(string.format("[Shared.Animation] %s", message))
		return
	end

	warn(string.format("[Shared.Animation] %s", message), detail)
end

function Animation.GetAnimationRoots(refresh: boolean?): { Instance }
	if refresh ~= true and resolvedAnimationRootsCache then
		return resolvedAnimationRootsCache
	end

	local roots = {}
	local seen = {}

	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	if gameAssets then
		local assets = gameAssets:FindFirstChild("Assets")
		local animations = assets and assets:FindFirstChild("Animations")
		local bosses = gameAssets:FindFirstChild("Bosses")

		addUniqueInstance(roots, seen, animations)
		addUniqueInstance(roots, seen, assets)
		addUniqueInstance(roots, seen, bosses)
		addUniqueInstance(roots, seen, gameAssets)
	end

	local packageFolder = ReplicatedStorage:FindFirstChild("Package")
	local storage = packageFolder and packageFolder:FindFirstChild("Storage")
	local packageAnimations = storage and storage:FindFirstChild("Animations")
	addUniqueInstance(roots, seen, packageAnimations)
	addUniqueInstance(roots, seen, storage)

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local replicatedAnimations = assets and assets:FindFirstChild("Animations")
	addUniqueInstance(roots, seen, replicatedAnimations)
	addUniqueInstance(roots, seen, assets)

	if #roots == 0 then
		addUniqueInstance(roots, seen, ReplicatedStorage)
	end

	resolvedAnimationRootsCache = roots
	replicatedAnimationsCache = nil
	return roots
end

function Animation.GetPrimaryAssetContainer(): Instance?
	for _, root in ipairs(Animation.GetAnimationRoots()) do
		if root.Name == "Animations" then
			return root.Parent
		end
		if root:FindFirstChild("Animations") then
			return root
		end
	end

	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	if gameAssets then
		return gameAssets
	end

	return nil
end

function Animation.GetReplicatedAnimations(refresh: boolean?): { Animation }
	if refresh ~= true and replicatedAnimationsCache then
		return replicatedAnimationsCache
	end

	local foundAnimations = {}
	local seen = {}

	for _, root in ipairs(Animation.GetAnimationRoots(refresh)) do
		if root:IsA("Animation") then
			addUniqueAnimation(foundAnimations, seen, root)
		end

		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant:IsA("Animation") then
				addUniqueAnimation(foundAnimations, seen, descendant)
			end
		end
	end

	replicatedAnimationsCache = foundAnimations
	return foundAnimations
end

function Animation.PreloadContent(animationInstances: { Animation }?): boolean
	local resolvedAnimations = animationInstances or Animation.GetReplicatedAnimations()
	if #resolvedAnimations == 0 then
		return true
	end

	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(resolvedAnimations)
	end)
	if not ok then
		warnWithPrefix("Content preload failed.", err)
		return false
	end

	return true
end

function Animation.GetProfile(character: Model?): Profile?
	if not character then
		return nil
	end

	return Animation._profiles[character]
end

function Animation.new(character: Model): Profile
	assert(typeof(character) == "Instance" and character:IsA("Model"), "Animation.new requires a character Model.")

	local existingProfile = Animation._profiles[character]
	if existingProfile then
		return existingProfile
	end

	local humanoid = getHumanoidFromCharacter(character)
	assert(humanoid ~= nil, "Animation.new requires the character to have a Humanoid.")

	local self = setmetatable({
		_character = character,
		_humanoid = humanoid,
		_animator = getAnimatorFromHumanoid(humanoid),
		_loadedAnimationTracks = {},
		_trackBindings = {},
		_trackStopConnections = {},
		_lifetimeConnections = {},
		_lastPlayedAnimation = nil,
		_animateOverridesFolder = nil,
		_destroyed = false,
	}, Animation)

	local function cleanupIfRemoved()
		if self._destroyed then
			return
		end

		if character.Parent == nil or character:IsDescendantOf(game) ~= true then
			self:Destroy()
		end
	end

	table.insert(self._lifetimeConnections, character.AncestryChanged:Connect(cleanupIfRemoved))
	table.insert(self._lifetimeConnections, humanoid.AncestryChanged:Connect(cleanupIfRemoved))

	Animation._profiles[character] = self
	return self
end

function Animation:_getTrackBindingState(track: AnimationTrack): TrackBindingState
	local state = self._trackBindings[track]
	if state then
		return state
	end

	state = {
		connections = {},
		cleanups = {},
	}
	self._trackBindings[track] = state
	return state
end

function Animation:_clearTrackBindings(track: AnimationTrack)
	local state = self._trackBindings[track]
	if not state then
		return
	end

	self._trackBindings[track] = nil

	for index = #state.connections, 1, -1 do
		local connection = state.connections[index]
		state.connections[index] = nil
		if connection.Connected then
			connection:Disconnect()
		end
	end

	for index = #state.cleanups, 1, -1 do
		local cleanup = state.cleanups[index]
		state.cleanups[index] = nil
		local ok, err = pcall(cleanup)
		if not ok then
			warnWithPrefix("Track cleanup failed.", err)
		end
	end
end

function Animation:_trackConnection(track: AnimationTrack, connection: RBXScriptConnection)
	table.insert(self:_getTrackBindingState(track).connections, connection)
	return connection
end

function Animation:_trackCleanup(track: AnimationTrack, cleanup: () -> ())
	table.insert(self:_getTrackBindingState(track).cleanups, cleanup)
	return cleanup
end

function Animation:_loadAnimationTrack(animationInstance: Animation): AnimationTrack?
	local loadedTrack = self._loadedAnimationTracks[animationInstance]
	if loadedTrack then
		return loadedTrack
	end

	local ok, result = pcall(function()
		return self._animator:LoadAnimation(animationInstance)
	end)
	if not ok or result == nil then
		warnWithPrefix(string.format("Failed to load animation track for '%s'.", animationInstance.Name), result)
		return nil
	end

	loadedTrack = result
	self._loadedAnimationTracks[animationInstance] = loadedTrack
	self._trackStopConnections[loadedTrack] = loadedTrack.Stopped:Connect(function()
		self:_clearTrackBindings(loadedTrack)
	end)
	return loadedTrack
end

function Animation:PreloadAnimations(animationInstances: { Animation }?): number
	local resolvedAnimations = animationInstances or Animation.GetReplicatedAnimations()
	local loadedCount = 0

	for _, animationInstance in ipairs(resolvedAnimations) do
		if self:_loadAnimationTrack(animationInstance) then
			loadedCount += 1
		end
	end

	return loadedCount
end

function Animation:BindEventMarkersOnDelay(animationTrack: AnimationTrack, animationEvents: AnimationEvents, timeOffset: number?): MarkerBindingHandle?
	if typeof(animationTrack) ~= "Instance" or not animationTrack:IsA("AnimationTrack") then
		return nil
	end
	if not isAnimationEventsTable(animationEvents) then
		return nil
	end

	local animation = animationTrack.Animation
	if not animation or animation.AnimationId == "" then
		warnWithPrefix("Cannot bind delayed markers for a track without an AnimationId.", animationTrack.Name)
		return nil
	end

	local ok, keyframeSequence = pcall(function()
		return KeyframeSequenceProvider:GetKeyframeSequenceAsync(animation.AnimationId)
	end)
	if not ok or keyframeSequence == nil then
		warnWithPrefix(string.format("Failed to fetch keyframes for '%s'.", animation.Name), keyframeSequence)
		return nil
	end

	local markerCache = {}
	local resolvedTimeOffset = tonumber(timeOffset) or 0
	for _, keyframe in ipairs(keyframeSequence:GetKeyframes()) do
		for _, marker in ipairs(keyframe:GetMarkers()) do
			local callback = animationEvents[marker.Name]
			if typeof(callback) == "function" then
				local delayedThread = task.delay(keyframe.Time + resolvedTimeOffset, callback)
				table.insert(markerCache, {
					name = marker.Name,
					thread = delayedThread,
				})
			end
		end
	end

	local didCancel = false
	local handle = {
		Cancel = function()
			if didCancel then
				return
			end
			didCancel = true

			for _, markerEntry in ipairs(markerCache) do
				task.cancel(markerEntry.thread)
			end
		end,
		MarkerCache = markerCache,
	}

	self:_trackCleanup(animationTrack, handle.Cancel)
	return handle
end

function Animation:BindEventMarkers(animationTrack: AnimationTrack, animationEvents: AnimationEvents)
	if typeof(animationTrack) ~= "Instance" or not animationTrack:IsA("AnimationTrack") then
		return nil
	end
	if not isAnimationEventsTable(animationEvents) then
		return nil
	end

	local connections = {}
	for eventName, callback in pairs(animationEvents) do
		if typeof(eventName) == "string" and typeof(callback) == "function" then
			local connection = animationTrack:GetMarkerReachedSignal(eventName):Connect(callback)
			table.insert(connections, connection)
			self:_trackConnection(animationTrack, connection)
		end
	end

	return connections
end

function Animation:PlayAnimation(
	animationInstance: Animation,
	priority: Enum.AnimationPriority?,
	speed: number?,
	animationEvents: AnimationEvents?,
	fade: number?
): AnimationTrack?
	assert(animationInstance and animationInstance:IsA("Animation"), "PlayAnimation requires an Animation instance.")

	local loadedTrack = self:_loadAnimationTrack(animationInstance)
	if not loadedTrack then
		return nil
	end

	self:_clearTrackBindings(loadedTrack)

	if animationEvents then
		self:BindEventMarkers(loadedTrack, animationEvents)
	end

	if priority ~= nil then
		loadedTrack.Priority = priority
	end

	loadedTrack:Play(fade or 0.1)
	loadedTrack:AdjustSpeed(tonumber(speed) or 1)
	self._lastPlayedAnimation = animationInstance

	return loadedTrack
end

function Animation:GetAnimationTrack(animationInstance: Animation): AnimationTrack?
	assert(animationInstance and animationInstance:IsA("Animation"), "GetAnimationTrack requires an Animation instance.")
	return self:_loadAnimationTrack(animationInstance)
end

function Animation:StopAnimation(animationInstance: Animation, fade: number?)
	assert(animationInstance and animationInstance:IsA("Animation"), "StopAnimation requires an Animation instance.")

	local loadedTrack = self._loadedAnimationTracks[animationInstance]
	if not loadedTrack then
		return
	end

	self:_clearTrackBindings(loadedTrack)
	loadedTrack:Stop(fade or 0.1)
end

function Animation:AdjustSpeed(animationInstance: Animation, speed: number)
	assert(animationInstance and animationInstance:IsA("Animation"), "AdjustSpeed requires an Animation instance.")
	assert(typeof(speed) == "number", "AdjustSpeed requires a numeric speed.")

	local loadedTrack = self:_loadAnimationTrack(animationInstance)
	if not loadedTrack then
		return
	end

	loadedTrack:AdjustSpeed(speed)
end

function Animation:StopLastAnimation()
	if not self._lastPlayedAnimation then
		return
	end

	self:StopAnimation(self._lastPlayedAnimation)
end

function Animation:_GetAnimateOverridesFolder(): Folder?
	if self._animateOverridesFolder and self._animateOverridesFolder.Parent then
		return self._animateOverridesFolder
	end

	local animateScript = self._character:FindFirstChild("Animate")
	if not animateScript then
		for _, descendant in ipairs(self._character:GetDescendants()) do
			if descendant.Name == "Animate" and descendant:IsA("LuaSourceContainer") then
				animateScript = descendant
				break
			end
		end
	end
	if not animateScript then
		return nil
	end

	local animationsFolder = animateScript:FindFirstChild("Animations")
	if not animationsFolder then
		animationsFolder = animateScript:WaitForChild("Animations", 5)
	end
	if not animationsFolder or not animationsFolder:IsA("Folder") then
		return nil
	end

	local overridesFolder = animationsFolder:FindFirstChild("Overrides")
	if not overridesFolder then
		overridesFolder = animationsFolder:WaitForChild("Overrides", 5)
	end
	if not overridesFolder or not overridesFolder:IsA("Folder") then
		return nil
	end

	self._animateOverridesFolder = overridesFolder
	return overridesFolder
end

function Animation:ApplyOverride(name: string, animationInstance: Animation): Animation?
	assert(typeof(name) == "string" and name ~= "", "ApplyOverride requires a non-empty override name.")
	assert(animationInstance and animationInstance:IsA("Animation"), "ApplyOverride requires an Animation instance.")

	local overridesFolder = self:_GetAnimateOverridesFolder()
	if not overridesFolder then
		warnWithPrefix("ApplyOverride could not find Animate/Animations/Overrides on the target character.")
		return nil
	end

	local existing = overridesFolder:FindFirstChild(name)
	if existing and existing:IsA("Animation") then
		existing.AnimationId = animationInstance.AnimationId
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local overrideAnimation = Instance.new("Animation")
	overrideAnimation.Name = name
	overrideAnimation.AnimationId = animationInstance.AnimationId
	overrideAnimation.Parent = overridesFolder
	return overrideAnimation
end

function Animation:RemoveOverride(name: string): boolean
	assert(typeof(name) == "string" and name ~= "", "RemoveOverride requires a non-empty override name.")

	local overridesFolder = self:_GetAnimateOverridesFolder()
	if not overridesFolder then
		warnWithPrefix("RemoveOverride could not find Animate/Animations/Overrides on the target character.")
		return false
	end

	local existing = overridesFolder:FindFirstChild(name)
	if existing and existing:IsA("Animation") then
		existing:Destroy()
		return true
	end

	return false
end

function Animation:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true

	for animationInstance, loadedTrack in pairs(self._loadedAnimationTracks) do
		self:_clearTrackBindings(loadedTrack)

		local stopConnection = self._trackStopConnections[loadedTrack]
		if stopConnection and stopConnection.Connected then
			stopConnection:Disconnect()
		end
		self._trackStopConnections[loadedTrack] = nil
		self._loadedAnimationTracks[animationInstance] = nil
	end

	for index = #self._lifetimeConnections, 1, -1 do
		local connection = self._lifetimeConnections[index]
		self._lifetimeConnections[index] = nil
		if connection.Connected then
			connection:Disconnect()
		end
	end

	Animation._profiles[self._character] = nil
end

return Animation
