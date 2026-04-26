local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AccessoryConfig = require(ReplicatedStorage.Shared.Config.AccessoryConfig)
local CraftingRecipeConfig = require(ReplicatedStorage.Shared.Config.CraftingRecipeConfig)
local OwnedAccessories = require(ReplicatedStorage.Shared.Character.OwnedAccessories)
local OwnedBodyParts = require(ReplicatedStorage.Shared.Character.OwnedBodyParts)
local BodyPartLoadout = require(ReplicatedStorage.Shared.Character.BodyPartLoadout)
local BodyPartService = require(script.Parent.BodyPartService)
local DataService = require(script.Parent.DataService)
local RequestLimiter = require(script.Parent.Common.RequestLimiter)

local REMOTES_FOLDER_NAME = "Remotes"
local CRAFTING_REMOTES_FOLDER_NAME = "Crafting"
local GET_STATE_REMOTE_NAME = "GetCraftingState"
local CRAFT_RECIPE_REMOTE_NAME = "CraftRecipe"

local remotesFolder: Folder? = nil
local craftingRemotesFolder: Folder? = nil
local getStateRemote: RemoteFunction? = nil
local craftRecipeRemote: RemoteFunction? = nil
local craftLocksByPlayer: { [Player]: boolean } = {}

local CraftingService = {}

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

local function ensureCraftingRemotesFolder(): Folder
	local rootFolder = ensureRemotesFolder()
	if craftingRemotesFolder and craftingRemotesFolder.Parent == rootFolder then
		return craftingRemotesFolder
	end

	local existing = rootFolder:FindFirstChild(CRAFTING_REMOTES_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		craftingRemotesFolder = existing
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = CRAFTING_REMOTES_FOLDER_NAME
	folder.Parent = rootFolder
	craftingRemotesFolder = folder
	return folder
end

local function ensureRemoteFunction(cachedRemote: RemoteFunction?, remoteName: string): RemoteFunction
	local folder = ensureCraftingRemotesFolder()
	if cachedRemote and cachedRemote.Parent == folder then
		return cachedRemote
	end

	local existing = folder:FindFirstChild(remoteName)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = remoteName
	remote.Parent = folder
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

local function response(ok: boolean, message: string, state: any?, result: any?)
	return {
		ok = ok,
		message = message,
		state = state,
		result = result,
	}
end

local function acquireCraftLock(player: Player): boolean
	if craftLocksByPlayer[player] == true then
		return false
	end

	craftLocksByPlayer[player] = true
	return true
end

local function releaseCraftLock(player: Player)
	craftLocksByPlayer[player] = nil
end

local function normalizeOwnedIdList(value: any): ({ string }?, string?)
	if typeof(value) ~= "table" then
		return nil, "bodyPartOwnedIds must be a table."
	end

	local ownedIds = {}
	local seenOwnedIds = {}
	for _, ownedId in ipairs(value) do
		if typeof(ownedId) ~= "string" or ownedId == "" then
			return nil, "Each body part ingredient must include an ownedId."
		end
		if seenOwnedIds[ownedId] == true then
			return nil, "Duplicate body part ingredients are not allowed."
		end

		seenOwnedIds[ownedId] = true
		table.insert(ownedIds, ownedId)
	end

	return ownedIds, nil
end

local function buildRequiredPieceCounts(recipe: CraftingRecipeConfig.CraftingRecipeEntry): { [string]: number }
	local counts = {}
	for _, ingredient in ipairs(recipe.bodyParts) do
		counts[ingredient.pieceId] = (counts[ingredient.pieceId] or 0) + math.max(1, math.floor(tonumber(ingredient.amount) or 1))
	end
	return counts
end

local function hasEquippedOwnedId(equippedLoadout: BodyPartLoadout.EquippedState, ownedId: string): boolean
	for _, entry in pairs(equippedLoadout) do
		if typeof(entry) == "table" and entry.ownedId == ownedId then
			return true
		end
	end
	return false
end

function CraftingService:GetCraftingState(player: Player, message: string?)
	return {
		recipes = CraftingRecipeConfig.GetAll(),
		craftingMaterials = DataService:GetCraftingMaterialAmounts(player),
		ownedBodyParts = DataService:GetOwnedBodyParts(player),
		ownedAccessories = DataService:GetOwnedAccessories(player),
		equippedAccessories = DataService:GetEquippedAccessories(player),
		message = message,
	}
end

function CraftingService:GrantCraftingMaterial(player: Player, materialId: string, amount: number): (boolean, string)
	local _, errorMessage = DataService:AddCraftingMaterial(player, materialId, amount)
	if errorMessage then
		return false, errorMessage
	end
	return true, "Crafting material granted."
end

function CraftingService:CraftRecipe(player: Player, recipeId: string, bodyPartOwnedIds: { string }): (boolean, string, any?)
	if not waitForPlayerData(player, 10) then
		return false, "Player data is not ready yet.", nil
	end

	local recipe = CraftingRecipeConfig.Get(recipeId)
	if not recipe then
		return false, "That recipe does not exist.", nil
	end

	local normalizedOwnedIds, ownedIdError = normalizeOwnedIdList(bodyPartOwnedIds)
	if not normalizedOwnedIds then
		return false, ownedIdError or "Invalid body part ingredients.", nil
	end

	local requiredPieceCounts = buildRequiredPieceCounts(recipe)
	local requiredBodyPartCount = 0
	for _, amount in pairs(requiredPieceCounts) do
		requiredBodyPartCount += amount
	end
	if #normalizedOwnedIds ~= requiredBodyPartCount then
		return false, "Body part ingredient count does not match the recipe.", nil
	end

	local bodyPartsState = DataService:GetBodyPartsState(player)
	local ownedBodyParts = bodyPartsState.ownedById
	local equippedLoadout = BodyPartLoadout.NormalizeEquippedState(DataService:GetEquippedLoadout(player), ownedBodyParts)
	local selectedPieceCounts = {}
	for _, ownedId in ipairs(normalizedOwnedIds) do
		local ownedRecord = ownedBodyParts[ownedId]
		if not ownedRecord then
			return false, string.format("Owned body part '%s' was not found.", ownedId), nil
		end
		if ownedRecord.isFavorite == true then
			return false, "Favorited body parts cannot be used as ingredients.", nil
		end
		if hasEquippedOwnedId(equippedLoadout, ownedId) then
			return false, "Equipped body parts cannot be used as ingredients.", nil
		end

		selectedPieceCounts[ownedRecord.pieceId] = (selectedPieceCounts[ownedRecord.pieceId] or 0) + 1
	end

	for pieceId, amount in pairs(requiredPieceCounts) do
		if (selectedPieceCounts[pieceId] or 0) ~= amount then
			return false, "Selected body part ingredients do not match the recipe.", nil
		end
	end

	local materialAmounts = DataService:GetCraftingMaterialAmounts(player)
	for _, ingredient in ipairs(recipe.materials) do
		if math.max(0, tonumber(materialAmounts[ingredient.materialId]) or 0) < ingredient.amount then
			return false, "You do not have enough crafting materials.", nil
		end
	end

	local recipeYield = recipe.yield
	if recipeYield.kind == "accessory" then
		local accessoryConfig = AccessoryConfig.Get(recipeYield.accessoryId)
		if not accessoryConfig then
			return false, "Recipe yield is invalid.", nil
		end
		if OwnedAccessories.CountOwned(DataService:GetAccessoriesState(player)) >= OwnedAccessories.MAX_OWNED_COUNT then
			return false, string.format("Accessory inventory is full (%d/%d).", OwnedAccessories.MAX_OWNED_COUNT, OwnedAccessories.MAX_OWNED_COUNT), nil
		end
	elseif recipeYield.kind == "bodyPart" then
		local projectedBodyPartCount = OwnedBodyParts.CountOwned(bodyPartsState) - #normalizedOwnedIds + 1
		if projectedBodyPartCount > OwnedBodyParts.MAX_OWNED_COUNT then
			return false, string.format(
				"Inventory is full (%d/%d). Sell body parts to make room.",
				OwnedBodyParts.CountOwned(bodyPartsState),
				OwnedBodyParts.MAX_OWNED_COUNT
			), nil
		end
	else
		return false, "Recipe yield is invalid.", nil
	end

	local reservation = nil
	if recipeYield.kind == "bodyPart" then
		local _, reservedGrant, reserveError = DataService:ReserveBodyPartRollRecord(player, recipeYield.bodyPartGrant)
		if not reservedGrant then
			return false, reserveError or "Failed to reserve crafted body part.", nil
		end
		reservation = reservedGrant
	end

	local removedRecords, removeError = DataService:RemoveOwnedBodyParts(player, normalizedOwnedIds)
	if not removedRecords then
		return false, removeError or "Failed to consume body part ingredients.", nil
	end

	local updatedMaterialAmounts = table.clone(materialAmounts)
	for _, ingredient in ipairs(recipe.materials) do
		updatedMaterialAmounts[ingredient.materialId] = math.max(0, (tonumber(updatedMaterialAmounts[ingredient.materialId]) or 0) - ingredient.amount)
	end
	local materialsOk, materialsError = DataService:SetCraftingMaterialAmounts(player, updatedMaterialAmounts)
	if not materialsOk then
		return false, materialsError or "Failed to consume crafting materials.", nil
	end

	if recipeYield.kind == "accessory" then
		local createdAccessory, grantError = DataService:AddOwnedAccessory(player, {
			accessoryId = recipeYield.accessoryId,
		})
		if not createdAccessory then
			return false, grantError or "Failed to grant crafted accessory.", nil
		end

		BodyPartService.LoadoutChanged:Fire(player)
		return true, string.format('Crafted "%s".', recipe.label), {
			kind = "accessory",
			accessory = createdAccessory,
			consumedBodyParts = removedRecords,
		}
	end

	local createdBodyPart, grantError = DataService:AddOwnedBodyPart(player, recipeYield.bodyPartGrant, reservation)
	if not createdBodyPart then
		return false, grantError or "Failed to grant crafted body part.", nil
	end

	BodyPartService.LoadoutChanged:Fire(player)
	return true, string.format('Crafted "%s".', recipe.label), {
		kind = "bodyPart",
		bodyPart = createdBodyPart,
		consumedBodyParts = removedRecords,
	}
end

local function handleGetCraftingState(player: Player)
	return response(true, "Loaded crafting state.", CraftingService:GetCraftingState(player), nil)
end

local function handleCraftRecipe(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Craft payload must be a table.", CraftingService:GetCraftingState(player), nil)
	end

	if not acquireCraftLock(player) then
		return response(false, "A craft is already processing.", CraftingService:GetCraftingState(player), nil)
	end

	local ok, message, result = CraftingService:CraftRecipe(player, payload.recipeId, payload.bodyPartOwnedIds)
	releaseCraftLock(player)

	return response(ok, message, CraftingService:GetCraftingState(player), result)
end

function CraftingService:OnStart()
	getStateRemote = ensureRemoteFunction(getStateRemote, GET_STATE_REMOTE_NAME)
	craftRecipeRemote = ensureRemoteFunction(craftRecipeRemote, CRAFT_RECIPE_REMOTE_NAME)

	getStateRemote.OnServerInvoke = function(player: Player)
		if not RequestLimiter:Allow(player, "remote.crafting.get_state") then
			return response(false, "You're refreshing crafting state too quickly.", CraftingService:GetCraftingState(player), nil)
		end
		return handleGetCraftingState(player)
	end

	craftRecipeRemote.OnServerInvoke = function(player: Player, payload: any)
		if not RequestLimiter:Allow(player, "remote.crafting.craft") then
			return response(false, "You're crafting too quickly.", CraftingService:GetCraftingState(player), nil)
		end
		return handleCraftRecipe(player, payload)
	end
end

function CraftingService:OnPlayerRemoving(player: Player)
	craftLocksByPlayer[player] = nil
end

return CraftingService
