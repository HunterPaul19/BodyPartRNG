local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameAssetPaths = require(ReplicatedStorage.Shared.Assets.GameAssetPaths)
local GameAssetResolver = require(ReplicatedStorage.Shared.Assets.GameAssetResolver)

local M1_FOLDER_NAME = "M1"
local SEARCH_PATHS = {
	GameAssetPaths.Animations.Bosses,
	GameAssetPaths.Legacy.Animations,
}

local folderCache: Folder? = nil
local animationsCache: { Animation }? = nil

local PlayerM1AnimationResolver = {}

function PlayerM1AnimationResolver.ResolveFolder(): Folder?
	if folderCache and folderCache.Parent ~= nil then
		return folderCache
	end

	local folder = GameAssetResolver.FindFirst(SEARCH_PATHS, M1_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		folderCache = folder
		return folder
	end

	folderCache = nil
	animationsCache = nil
	return nil
end

function PlayerM1AnimationResolver.GetAnimations(): { Animation }
	local cachedFolder = folderCache
	if animationsCache and cachedFolder and cachedFolder.Parent ~= nil then
		return animationsCache
	end

	local folder = PlayerM1AnimationResolver.ResolveFolder()
	local animations = {}
	if folder == nil then
		return animations
	end

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Animation") then
			table.insert(animations, child)
		end
	end

	if #animations > 0 then
		animationsCache = animations
	end

	return animations
end

function PlayerM1AnimationResolver.FindAnimation(name: any): Animation?
	if typeof(name) ~= "string" or name == "" then
		return nil
	end

	local folder = PlayerM1AnimationResolver.ResolveFolder()
	if folder == nil then
		return nil
	end

	local animation = folder:FindFirstChild(name)
	if animation and animation:IsA("Animation") then
		return animation
	end

	return nil
end

return PlayerM1AnimationResolver
