local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BossArenas = require(ReplicatedStorage.Shared.BossArenas)
local Bosses = require(ReplicatedStorage.Shared.Bosses)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)

local ACTIVE_PROFILE_ID = "boss_arena"
local GAME_ASSETS_FOLDER_NAME = "GameAssets"
local BOSSES_FOLDER_NAME = "Bosses"
local BOSS_ARENAS_FOLDER_NAME = "BossArenas"

local BossArenaStudioValidationService = {
	_started = false,
}

local function isEnabled(): boolean
	return RunService:IsStudio() and PlaceProfile.GetActiveProfile().id == ACTIVE_PROFILE_ID
end

local function warnWithPrefix(message: string)
	Logger.Warn(string.format("[BossArenaStudioValidationService] %s", message))
end

local function getGameAssetsFolder(): Folder?
	local gameAssetsFolder = ReplicatedStorage:FindFirstChild(GAME_ASSETS_FOLDER_NAME)
	if gameAssetsFolder == nil or not gameAssetsFolder:IsA("Folder") then
		warnWithPrefix(string.format(
			"Missing ReplicatedStorage.%s; skipping boss arena asset validation.",
			GAME_ASSETS_FOLDER_NAME
		))
		return nil
	end

	return gameAssetsFolder
end

local function getBossesFolder(gameAssetsFolder: Folder): Folder?
	local bossesFolder = gameAssetsFolder:FindFirstChild(BOSSES_FOLDER_NAME)
	if bossesFolder == nil or not bossesFolder:IsA("Folder") then
		warnWithPrefix(string.format(
			"Missing ReplicatedStorage.%s.%s; skipping boss asset validation.",
			GAME_ASSETS_FOLDER_NAME,
			BOSSES_FOLDER_NAME
		))
		return nil
	end

	return bossesFolder
end

local function getBossArenasFolder(gameAssetsFolder: Folder): Folder?
	local bossArenasFolder = gameAssetsFolder:FindFirstChild(BOSS_ARENAS_FOLDER_NAME)
	if bossArenasFolder == nil or not bossArenasFolder:IsA("Folder") then
		warnWithPrefix(string.format(
			"Missing ReplicatedStorage.%s.%s; skipping arena asset validation.",
			GAME_ASSETS_FOLDER_NAME,
			BOSS_ARENAS_FOLDER_NAME
		))
		return nil
	end

	return bossArenasFolder
end

local function findFirstNamedBasePart(root: Instance, targetName: string): BasePart?
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == targetName then
			return descendant
		end
	end

	return nil
end

function BossArenaStudioValidationService:RunValidation(): number
	local warningCount = 0
	local gameAssetsFolder = getGameAssetsFolder()
	if gameAssetsFolder == nil then
		return 1
	end

	local bossesFolder = getBossesFolder(gameAssetsFolder)
	local bossArenasFolder = getBossArenasFolder(gameAssetsFolder)

	if bossesFolder ~= nil then
		for _, bossDefinition in ipairs(Bosses.GetAll()) do
			local bossModel = bossesFolder:FindFirstChild(bossDefinition.bossId)
			if bossModel == nil or not bossModel:IsA("Model") then
				warningCount += 1
				warnWithPrefix(string.format(
					"Boss asset '%s' is missing or is not a Model under ReplicatedStorage.%s.%s.",
					bossDefinition.bossId,
					GAME_ASSETS_FOLDER_NAME,
					BOSSES_FOLDER_NAME
				))
				continue
			end

			local humanoid = bossModel:FindFirstChildOfClass("Humanoid")
			if humanoid == nil then
				warningCount += 1
				warnWithPrefix(string.format(
					"Boss asset '%s' is missing a Humanoid.",
					bossDefinition.bossId
				))
			end

			local rootPart = bossModel:FindFirstChild("HumanoidRootPart")
			if rootPart == nil or not rootPart:IsA("BasePart") then
				warningCount += 1
				warnWithPrefix(string.format(
					"Boss asset '%s' is missing a HumanoidRootPart.",
					bossDefinition.bossId
				))
			elseif rootPart.Anchored == true then
				warningCount += 1
				warnWithPrefix(string.format(
					"Boss asset '%s' has an anchored HumanoidRootPart at %s.",
					bossDefinition.bossId,
					rootPart:GetFullName()
				))
			end
		end
	end

	if bossArenasFolder ~= nil then
		for _, arenaDefinition in ipairs(BossArenas.GetAll()) do
			local arenaModel = bossArenasFolder:FindFirstChild(arenaDefinition.assetName)
			if arenaModel == nil or not arenaModel:IsA("Model") then
				warningCount += 1
				warnWithPrefix(string.format(
					"Arena asset '%s' is missing or is not a Model under ReplicatedStorage.%s.%s.",
					arenaDefinition.assetName,
					GAME_ASSETS_FOLDER_NAME,
					BOSS_ARENAS_FOLDER_NAME
				))
				continue
			end

			local bossSpawn = findFirstNamedBasePart(arenaModel, arenaDefinition.bossSpawnName)
			if bossSpawn == nil then
				warningCount += 1
				warnWithPrefix(string.format(
					"Arena '%s' is missing a BasePart named '%s'.",
					arenaDefinition.arenaId,
					arenaDefinition.bossSpawnName
				))
			end
		end
	end

	if warningCount == 0 then
		Logger.Print("[BossArenaStudioValidationService] Boss assets and arena BossSpawn markers validated cleanly.")
	end

	return warningCount
end

function BossArenaStudioValidationService:OnStart()
	if self._started then
		return
	end
	self._started = true

	if not isEnabled() then
		return
	end

	self:RunValidation()
end

return BossArenaStudioValidationService
