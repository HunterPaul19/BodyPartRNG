local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PreviewAppearanceSnapshot = require(ReplicatedStorage.Shared.Character.PreviewAppearanceSnapshot)

local PreviewAppearanceService = {}

local snapshotsFolder: Folder? = nil
local characterAppearanceLoadedConnections: { [Player]: RBXScriptConnection } = {}
local characterAddedConnections: { [Player]: RBXScriptConnection } = {}
local snapshotPublishedByUserId: { [number]: boolean } = {}

local function ensureSnapshotsFolder(): Folder
	if snapshotsFolder and snapshotsFolder.Parent == ReplicatedStorage then
		return snapshotsFolder
	end

	local existing = ReplicatedStorage:FindFirstChild(PreviewAppearanceSnapshot.FolderName)
	if existing and existing:IsA("Folder") then
		snapshotsFolder = existing
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = PreviewAppearanceSnapshot.FolderName
	folder.Parent = ReplicatedStorage
	snapshotsFolder = folder
	return folder
end

local function ensureSnapshotFolder(userId: number): Folder
	local folderName = tostring(math.max(0, math.floor(tonumber(userId) or 0)))
	local root = ensureSnapshotsFolder()
	local existing = root:FindFirstChild(folderName)
	if existing and existing:IsA("Folder") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = folderName
	folder.Parent = root
	return folder
end

local function clearSnapshot(userId: number)
	local root = ensureSnapshotsFolder()
	local resolvedUserId = math.max(0, math.floor(tonumber(userId) or 0))
	local existing = root:FindFirstChild(tostring(resolvedUserId))
	if existing then
		existing:Destroy()
	end
	snapshotPublishedByUserId[resolvedUserId] = nil
end

local function isSnapshotPublished(player: Player): boolean
	return snapshotPublishedByUserId[player.UserId] == true
end

local function hasAppearanceReady(character: Model?): boolean
	if not (character and character:IsA("Model")) then
		return false
	end

	if character:FindFirstChildOfClass("BodyColors") then
		return true
	end

	return character:FindFirstChildOfClass("Shirt") ~= nil
		or character:FindFirstChildOfClass("Pants") ~= nil
		or character:FindFirstChildOfClass("ShirtGraphic") ~= nil
end

local function waitForAppearanceReady(character: Model?, timeoutSeconds: number?): boolean
	local resolvedTimeout = math.max(0, tonumber(timeoutSeconds) or 0)
	local deadline = os.clock() + resolvedTimeout

	while character and character.Parent ~= nil do
		if hasAppearanceReady(character) then
			return true
		end

		if resolvedTimeout > 0 and os.clock() >= deadline then
			break
		end

		task.wait(0.1)
	end

	return hasAppearanceReady(character)
end

local function buildSnapshot(player: Player, character: Model?): any
	if not waitForAppearanceReady(character, 10) then
		return nil
	end

	return PreviewAppearanceSnapshot.FromCharacterAppearance(character, player.UserId)
end

local function publishSnapshot(player: Player, snapshot: any)
	if not snapshot then
		return false
	end

	local folder = ensureSnapshotFolder(player.UserId)
	folder:SetAttribute("Payload", PreviewAppearanceSnapshot.Encode(snapshot))
	folder:SetAttribute("CacheKey", snapshot.cacheKey)
	folder:SetAttribute("SourceUserId", snapshot.sourceUserId)
	snapshotPublishedByUserId[player.UserId] = true
	return true
end

local function tryPublishCharacterSnapshot(player: Player, character: Model?): boolean
	if isSnapshotPublished(player) then
		return true
	end

	local snapshot = buildSnapshot(player, character)
	return publishSnapshot(player, snapshot)
end

local function disconnectConnection(connection: RBXScriptConnection?)
	if connection then
		connection:Disconnect()
	end
end

local function bindCharacterSnapshotListeners(player: Player)
	disconnectConnection(characterAppearanceLoadedConnections[player])
	disconnectConnection(characterAddedConnections[player])

	characterAppearanceLoadedConnections[player] = player.CharacterAppearanceLoaded:Connect(function(character)
		if isSnapshotPublished(player) then
			return
		end

		task.defer(function()
			tryPublishCharacterSnapshot(player, character)
		end)
	end)

	characterAddedConnections[player] = player.CharacterAdded:Connect(function(character)
		if isSnapshotPublished(player) then
			return
		end

		task.defer(function()
			tryPublishCharacterSnapshot(player, character)
		end)
	end)
end

function PreviewAppearanceService:OnStart()
	ensureSnapshotsFolder()
end

function PreviewAppearanceService:OnPlayerAdded(player: Player)
	bindCharacterSnapshotListeners(player)

	if player.Character then
		task.defer(function()
			tryPublishCharacterSnapshot(player, player.Character)
		end)
	end
end

function PreviewAppearanceService:OnPlayerRemoving(player: Player)
	disconnectConnection(characterAppearanceLoadedConnections[player])
	disconnectConnection(characterAddedConnections[player])
	characterAppearanceLoadedConnections[player] = nil
	characterAddedConnections[player] = nil
	clearSnapshot(player.UserId)
end

return PreviewAppearanceService
