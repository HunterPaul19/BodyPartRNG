local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Schema = require(ReplicatedStorage.Lists.Schema)
local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)
local TitleUtil = require(ReplicatedStorage.Shared.Titles.TitleUtil)
local DataService = require(script.Parent.DataService)

local REMOTES_FOLDER_NAME = "Remotes"
local TITLES_REMOTES_FOLDER_NAME = "Titles"
local SET_EQUIPPED_TITLE_REMOTE_NAME = "SetEquippedTitle"

local EQUIPPED_TITLE_ID_KEY = Schema.EquippedTitleId and Schema.EquippedTitleId.key or "equippedTitleId"
local ACHIEVEMENTS_KEY = Schema.Achievements and Schema.Achievements.key or "achievements"

local remotesFolder: Folder? = nil
local titlesRemotesFolder: Folder? = nil
local setEquippedTitleRemote: RemoteFunction? = nil

local function ensureRemotesFolder(): Folder
	if remotesFolder and remotesFolder.Parent == ReplicatedStorage then
		return remotesFolder
	end

	local existing = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		remotesFolder = existing
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = REMOTES_FOLDER_NAME
	folder.Parent = ReplicatedStorage
	remotesFolder = folder
	return folder
end

local function ensureTitlesRemotesFolder(): Folder
	local rootFolder = ensureRemotesFolder()
	if titlesRemotesFolder and titlesRemotesFolder.Parent == rootFolder then
		return titlesRemotesFolder
	end

	local existing = rootFolder:FindFirstChild(TITLES_REMOTES_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		titlesRemotesFolder = existing
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = TITLES_REMOTES_FOLDER_NAME
	folder.Parent = rootFolder
	titlesRemotesFolder = folder
	return folder
end

local function ensureSetEquippedTitleRemote(): RemoteFunction
	local folder = ensureTitlesRemotesFolder()
	if setEquippedTitleRemote and setEquippedTitleRemote.Parent == folder then
		return setEquippedTitleRemote
	end

	local existing = folder:FindFirstChild(SET_EQUIPPED_TITLE_REMOTE_NAME)
	if existing and existing:IsA("RemoteFunction") then
		setEquippedTitleRemote = existing
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = SET_EQUIPPED_TITLE_REMOTE_NAME
	remote.Parent = folder
	setEquippedTitleRemote = remote
	return remote
end

local function waitForPlayerData(player: Player, timeoutSeconds: number?): boolean
	local timeoutAt = os.clock() + (timeoutSeconds or 20)

	while os.clock() < timeoutAt do
		if player.Parent ~= Players then
			return false
		end

		if DataService:Get(player) ~= nil then
			return true
		end

		task.wait(0.25)
	end

	return false
end

local function buildResponse(ok: boolean, message: string)
	return {
		ok = ok,
		message = message,
	}
end

local function getNormalizedEquippedTitleId(player: Player): string?
	local data = DataService:Get(player)
	if typeof(data) ~= "table" then
		return nil
	end

	return TitleUtil.NormalizeEquippedTitleId(data[EQUIPPED_TITLE_ID_KEY])
end

local function hasUnlockedTitle(player: Player, titleId: string): boolean
	local data = DataService:Get(player)
	if typeof(data) ~= "table" then
		return false
	end

	return TitleUtil.IsTitleUnlocked(titleId, data[ACHIEVEMENTS_KEY])
end

local function sanitizeEquippedTitle(player: Player)
	if not waitForPlayerData(player, 20) then
		return
	end

	local equippedTitleId = getNormalizedEquippedTitleId(player)
	if not equippedTitleId then
		return
	end

	if not TitleConfig.Get(equippedTitleId) or not hasUnlockedTitle(player, equippedTitleId) then
		DataService:SetEquippedTitleId(player, nil)
	end
end

local TitleService = {}

function TitleService:OnStart()
	local remote = ensureSetEquippedTitleRemote()
	remote.OnServerInvoke = function(player: Player, payload: any)
		if not waitForPlayerData(player, 10) then
			return buildResponse(false, "Player data is not ready yet.")
		end

		local requestedTitleId = nil
		if typeof(payload) == "table" then
			requestedTitleId = TitleUtil.NormalizeEquippedTitleId(payload.titleId)
		else
			requestedTitleId = TitleUtil.NormalizeEquippedTitleId(payload)
		end

		if requestedTitleId == nil then
			local ok, message = DataService:SetEquippedTitleId(player, nil)
			return buildResponse(ok, if ok then "Cleared equipped title." else (message or "Could not clear title."))
		end

		local title = TitleConfig.Get(requestedTitleId)
		if not title then
			return buildResponse(false, "That title does not exist.")
		end
		if not hasUnlockedTitle(player, requestedTitleId) then
			return buildResponse(false, "You have not unlocked that title yet.")
		end
		if getNormalizedEquippedTitleId(player) == requestedTitleId then
			return buildResponse(true, string.format('"%s" is already equipped.', title.label))
		end

		local ok, message = DataService:SetEquippedTitleId(player, requestedTitleId)
		return buildResponse(ok, if ok then string.format('Equipped "%s".', title.label) else (message or "Could not equip title."))
	end
end

function TitleService:OnPlayerAdded(player: Player)
	task.defer(function()
		sanitizeEquippedTitle(player)
	end)
end

return TitleService
