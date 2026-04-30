local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChestOpeningSequence = require(ReplicatedStorage.Shared.UI.ChestOpeningSequence)
local DailyChestConfig = require(ReplicatedStorage.Shared.Config.DailyChestConfig)
local DataController = require(script.Parent.DataController)
local PlaceProfile = require(ReplicatedStorage.Shared.PlaceProfiles.PlaceProfile)
local TutorialTextGui = require(ReplicatedStorage.Shared.UI.TutorialTextGui)
local TutorialState = require(ReplicatedStorage.Shared.Character.TutorialState)

local LOCAL_PLAYER = Players.LocalPlayer
local CLAIM_REMOTE_TIMEOUT = 30

local DailyChestController = {}

local function getLocalUtcOffsetMinutes(): number
	local now = os.time()
	local localDate = os.date("*t", now)
	local utcDate = os.date("!*t", now)
	if typeof(localDate) ~= "table" or typeof(utcDate) ~= "table" then
		return 0
	end

	localDate.isdst = false
	utcDate.isdst = false

	local ok, diffSeconds = pcall(function()
		return os.difftime(os.time(localDate), os.time(utcDate))
	end)
	if not ok then
		return 0
	end

	return math.clamp(math.floor((tonumber(diffSeconds) or 0) / 60), -14 * 60, 14 * 60)
end

local function waitForLoadingScreenDismissed()
	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	local loadingScreen = playerGui:FindFirstChild("LoadingScreen")
	while loadingScreen and loadingScreen.Parent do
		loadingScreen.AncestryChanged:Wait()
	end
end

local function waitForPlayerData()
	if DataController.Loaded == true then
		return
	end

	DataController.DataReceived:Wait()
end

local function resolveClaimRemote(): RemoteFunction?
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", CLAIM_REMOTE_TIMEOUT)
	local chestsFolder = remotesFolder and remotesFolder:WaitForChild("Chests", CLAIM_REMOTE_TIMEOUT)
	local claimRemote = chestsFolder and chestsFolder:WaitForChild("ClaimDailyChests", CLAIM_REMOTE_TIMEOUT)
	if claimRemote and claimRemote:IsA("RemoteFunction") then
		return claimRemote
	end

	return nil
end

local function openChestPackagesSequentially(chests: { any })
	for _, package in ipairs(chests) do
		if typeof(package) ~= "table" then
			continue
		end

		local visualChestId = if typeof(package.visualChestId) == "string" and package.visualChestId ~= ""
			then package.visualChestId
			else package.chestId
		local rewards = if typeof(package.rewards) == "table" then package.rewards else {}
		if typeof(visualChestId) == "string" and #rewards > 0 then
			local opened = ChestOpeningSequence.OpenChestAsync(visualChestId, rewards)
			if opened == true then
				TutorialTextGui.ShowTemporaryTextAsync(DailyChestConfig.GetReturnMessage(package.chestId))
			end
		end
	end
end

function DailyChestController:OnStart()
	if self._started == true then
		return
	end
	self._started = true

	local activeProfile = PlaceProfile.GetActiveProfile()
	if activeProfile.id ~= "main" then
		return
	end

	task.spawn(function()
		waitForPlayerData()
		waitForLoadingScreenDismissed()
		local tutorialState = TutorialState.Normalize(DataController:Get("tutorial"))
		if tutorialState.completed ~= true then
			return
		end

		TutorialTextGui.Init(LOCAL_PLAYER:WaitForChild("PlayerGui"))

		local claimRemote = resolveClaimRemote()
		if not claimRemote then
			Logger.Warn("[DailyChestController] ReplicatedStorage.Remotes.Chests.ClaimDailyChests is missing.")
			return
		end

		local ok, result = pcall(function()
			return claimRemote:InvokeServer({
				localUtcOffsetMinutes = getLocalUtcOffsetMinutes(),
			})
		end)
		if not ok then
			Logger.Warn("[DailyChestController] Daily chest claim failed: " .. tostring(result))
			return
		end
		if typeof(result) ~= "table" or result.ok ~= true then
			return
		end

		local chests = if typeof(result.chests) == "table" then result.chests else {}
		openChestPackagesSequentially(chests)
	end)
end

return DailyChestController
