local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameAssetResolver = {}

type PathSegments = { string }

local GAME_ASSETS_FOLDER_NAME = "GameAssets"

local function normalizePath(path: string | PathSegments | nil): PathSegments
	if path == nil then
		return {}
	end

	if typeof(path) == "table" then
		return table.clone(path :: PathSegments)
	end

	local segments = {}
	for segment in string.gmatch(path :: string, "[^%.]+") do
		table.insert(segments, segment)
	end

	return segments
end

local function appendSegments(basePath: string | PathSegments | nil, extraSegments: { any }): PathSegments
	local segments = normalizePath(basePath)
	for _, segment in ipairs(extraSegments) do
		if typeof(segment) == "table" then
			for _, nestedSegment in ipairs(segment) do
				table.insert(segments, tostring(nestedSegment))
			end
		elseif segment ~= nil then
			table.insert(segments, tostring(segment))
		end
	end

	return segments
end

function GameAssetResolver.GetRoot(): Folder?
	local gameAssets = ReplicatedStorage:FindFirstChild(GAME_ASSETS_FOLDER_NAME)
	if gameAssets and gameAssets:IsA("Folder") then
		return gameAssets
	end

	return nil
end

function GameAssetResolver.WaitForRoot(timeout: number?): Folder?
	local gameAssets = ReplicatedStorage:WaitForChild(GAME_ASSETS_FOLDER_NAME, timeout or 10)
	if gameAssets and gameAssets:IsA("Folder") then
		return gameAssets
	end

	return nil
end

function GameAssetResolver.Find(path: string | PathSegments | nil, ...: any): Instance?
	local current: Instance? = GameAssetResolver.GetRoot()
	if current == nil then
		return nil
	end

	for _, segment in ipairs(appendSegments(path, { ... })) do
		current = current:FindFirstChild(segment)
		if current == nil then
			return nil
		end
	end

	return current
end

function GameAssetResolver.Wait(path: string | PathSegments | nil, timeout: number?, ...: any): Instance?
	local current: Instance? = GameAssetResolver.WaitForRoot(timeout)
	if current == nil then
		return nil
	end

	for _, segment in ipairs(appendSegments(path, { ... })) do
		current = current:WaitForChild(segment, timeout or 10)
		if current == nil then
			return nil
		end
	end

	return current
end

function GameAssetResolver.FindFirst(paths: { string | PathSegments }, ...: any): Instance?
	for _, path in ipairs(paths) do
		local result = GameAssetResolver.Find(path, ...)
		if result ~= nil then
			return result
		end
	end

	return nil
end

function GameAssetResolver.Format(path: string | PathSegments | nil, ...: any): string
	local segments = appendSegments(path, { ... })
	if #segments == 0 then
		return "ReplicatedStorage.GameAssets"
	end

	return "ReplicatedStorage.GameAssets." .. table.concat(segments, ".")
end

return GameAssetResolver
