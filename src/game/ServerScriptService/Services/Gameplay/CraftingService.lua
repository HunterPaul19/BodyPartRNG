local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AccessoryConfig = require(ReplicatedStorage.Shared.Config.AccessoryConfig)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local CraftingMaterialConfig = require(ReplicatedStorage.Shared.Config.CraftingMaterialConfig)
local CraftingRecipeConfig = require(ReplicatedStorage.Shared.Config.CraftingRecipeConfig)
local CraftingProgress = require(ReplicatedStorage.Shared.Character.CraftingProgress)
local OwnedAccessories = require(ReplicatedStorage.Shared.Character.OwnedAccessories)
local OwnedBodyParts = require(ReplicatedStorage.Shared.Character.OwnedBodyParts)
local BodyPartLoadout = require(ReplicatedStorage.Shared.Character.BodyPartLoadout)
local Notify = require(ReplicatedStorage.Shared.UI.Notify)
local BodyPartService = require(script.Parent.BodyPartService)
local DataService = require(script.Parent.DataService)
local RequestLimiter = require(script.Parent.Common.RequestLimiter)

local REMOTES_FOLDER_NAME = "Remotes"
local CRAFTING_REMOTES_FOLDER_NAME = "Crafting"
local GET_STATE_REMOTE_NAME = "GetCraftingState"
local CRAFT_RECIPE_REMOTE_NAME = "CraftRecipe"
local SET_AUTO_CRAFT_RECIPE_REMOTE_NAME = "SetAutoCraftRecipe"
local ADD_BODY_PART_INGREDIENT_REMOTE_NAME = "AddBodyPartIngredient"
local ADD_MATERIAL_INGREDIENT_REMOTE_NAME = "AddMaterialIngredient"
local ADD_ALL_ELIGIBLE_INGREDIENTS_REMOTE_NAME = "AddAllEligibleIngredients"
local SELL_MATERIAL_STACK_REMOTE_NAME = "SellCraftingMaterialStack"

local remotesFolder: Folder? = nil
local craftingRemotesFolder: Folder? = nil
local getStateRemote: RemoteFunction? = nil
local craftRecipeRemote: RemoteFunction? = nil
local setAutoCraftRecipeRemote: RemoteFunction? = nil
local addBodyPartIngredientRemote: RemoteFunction? = nil
local addMaterialIngredientRemote: RemoteFunction? = nil
local addAllEligibleIngredientsRemote: RemoteFunction? = nil
local sellMaterialStackRemote: RemoteFunction? = nil
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

local function getRequirementSpecificity(requirement: CraftingRecipeConfig.BodyPartIngredientConfig): number
	if requirement.pieceId then
		return 3
	end
	if requirement.setId and requirement.region then
		return 2
	end
	if requirement.setId then
		return 1
	end
	return 0
end

local function getBodyPartIngredientAmount(ingredient: any): number
	return math.max(1, math.floor(tonumber(ingredient and ingredient.amount) or 1))
end

local function bodyPartMatchesRequirement(record: any, requirement: CraftingRecipeConfig.BodyPartIngredientConfig): boolean
	if typeof(record) ~= "table" then
		return false
	end

	if requirement.pieceId then
		return record.pieceId == requirement.pieceId
	end

	if not requirement.setId then
		return false
	end

	local piece = if typeof(record.pieceId) == "string" then BodyPartsCatalog.GetPiece(record.pieceId) else nil
	if not piece or piece.setId ~= requirement.setId then
		return false
	end

	return requirement.region == nil or piece.region == requirement.region
end

local function findBodyPartIngredient(recipe: CraftingRecipeConfig.CraftingRecipeEntry, ingredientKey: string)
	for _, ingredient in ipairs(recipe.bodyParts) do
		if CraftingProgress.GetBodyPartIngredientKey(ingredient) == ingredientKey then
			return ingredient
		end
	end

	return nil
end

local function getRequiredBodyPartAmount(recipe: CraftingRecipeConfig.CraftingRecipeEntry, ingredientKey: string): number
	local ingredient = findBodyPartIngredient(recipe, ingredientKey)
	return if ingredient then getBodyPartIngredientAmount(ingredient) else 0
end

local function getRequiredMaterialAmount(recipe: CraftingRecipeConfig.CraftingRecipeEntry, materialId: string): number
	for _, ingredient in ipairs(recipe.materials) do
		if ingredient.materialId == materialId then
			return math.max(1, math.floor(tonumber(ingredient.amount) or 1))
		end
	end

	return 0
end

local function getRecipeMoneyCost(recipe: CraftingRecipeConfig.CraftingRecipeEntry): number
	return math.max(0, math.floor(tonumber(recipe.moneyCost) or 0))
end

local function hasEquippedOwnedId(equippedLoadout: BodyPartLoadout.EquippedState, ownedId: string): boolean
	for _, entry in pairs(equippedLoadout) do
		if typeof(entry) == "table" and entry.ownedId == ownedId then
			return true
		end
	end
	return false
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

local function hasRequiredProgress(recipe: CraftingRecipeConfig.CraftingRecipeEntry, progress: CraftingProgress.RecipeProgress): (boolean, string)
	for _, ingredient in ipairs(recipe.bodyParts) do
		local key = CraftingProgress.GetBodyPartIngredientKey(ingredient)
		local requiredAmount = getBodyPartIngredientAmount(ingredient)
		if (progress.bodyPartsByIngredientKey[key] or 0) < requiredAmount then
			return false, "Missing body part ingredients."
		end
	end

	for _, ingredient in ipairs(recipe.materials) do
		local requiredAmount = math.max(1, math.floor(tonumber(ingredient.amount) or 1))
		if (progress.materialsByMaterialId[ingredient.materialId] or 0) < requiredAmount then
			return false, "Missing crafting materials."
		end
	end

	return true, "Ready to craft."
end

local function validateYieldCapacity(player: Player, recipe: CraftingRecipeConfig.CraftingRecipeEntry): (boolean, string)
	local recipeYield = recipe.yield
	if recipeYield.kind == "accessory" then
		local accessoryConfig = AccessoryConfig.Get(recipeYield.accessoryId)
		if not accessoryConfig then
			return false, "Recipe yield is invalid."
		end
		if OwnedAccessories.CountOwned(DataService:GetAccessoriesState(player)) >= OwnedAccessories.MAX_OWNED_COUNT then
			return false, string.format(
				"Accessory inventory is full (%d/%d).",
				OwnedAccessories.MAX_OWNED_COUNT,
				OwnedAccessories.MAX_OWNED_COUNT
			)
		end
	elseif recipeYield.kind == "bodyPart" then
		if OwnedBodyParts.CountOwned(DataService:GetBodyPartsState(player)) + 1 > OwnedBodyParts.MAX_OWNED_COUNT then
			return false, string.format(
				"Inventory is full (%d/%d). Sell body parts to make room.",
				OwnedBodyParts.CountOwned(DataService:GetBodyPartsState(player)),
				OwnedBodyParts.MAX_OWNED_COUNT
			)
		end
	else
		return false, "Recipe yield is invalid."
	end

	return true, "OK"
end

local function saveProgress(player: Player, progressState: CraftingProgress.CraftingProgressState): (boolean, string?)
	return DataService:SetCraftingProgress(player, progressState)
end

local function buildAutoCraftReadyMessage(recipe: CraftingRecipeConfig.CraftingRecipeEntry): string
	return string.format("%s is ready! Go to Crafting and press Craft.", recipe.label)
end

local function sendAutoCraftReadyNotification(player: Player, message: string)
	Notify.Send(player, message, {
		title = "Crafting",
		channel = "inventory",
		tone = "good",
		duration = 5,
	})
end

local function markAutoCraftReadyIfNeeded(
	progressState: CraftingProgress.CraftingProgressState,
	recipe: CraftingRecipeConfig.CraftingRecipeEntry
): string?
	if progressState.autoRecipeIds[recipe.id] ~= true then
		return nil
	end

	local progress = CraftingProgress.GetRecipeProgress(progressState, recipe.id)
	local readyToCraft = hasRequiredProgress(recipe, progress)
	if not readyToCraft or progressState.autoReadyNotifiedRecipeIds[recipe.id] == true then
		return nil
	end

	progressState.autoReadyNotifiedRecipeIds[recipe.id] = true
	return buildAutoCraftReadyMessage(recipe)
end

function CraftingService:GetCraftingState(player: Player, message: string?)
	return {
		recipes = CraftingRecipeConfig.GetAll(),
		craftingMaterials = DataService:GetCraftingMaterialAmounts(player),
		craftingProgress = DataService:GetCraftingProgress(player),
		ownedBodyParts = DataService:GetOwnedBodyParts(player),
		ownedAccessories = DataService:GetOwnedAccessories(player),
		equippedAccessories = DataService:GetEquippedAccessories(player),
		money = DataService:GetMoney(player),
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

function CraftingService:SetAutoCraftRecipe(player: Player, recipeId: string, enabled: boolean): (boolean, string)
	if not waitForPlayerData(player, 10) then
		return false, "Player data is not ready yet."
	end

	local recipe = CraftingRecipeConfig.Get(recipeId)
	if not recipe then
		return false, "That recipe does not exist."
	end

	local progressState = DataService:GetCraftingProgress(player)
	progressState.autoRecipeIds[recipe.id] = if enabled == true then true else nil
	if enabled ~= true then
		progressState.autoReadyNotifiedRecipeIds[recipe.id] = nil
	end
	local readyMessage = if enabled == true then markAutoCraftReadyIfNeeded(progressState, recipe) else nil

	local saved, saveError = saveProgress(player, progressState)
	if not saved then
		return false, saveError or "Failed to update auto craft."
	end
	if readyMessage then
		sendAutoCraftReadyNotification(player, readyMessage)
	end

	return true, if enabled == true then "Auto craft enabled." else "Auto craft disabled."
end

function CraftingService:AddBodyPartIngredient(
	player: Player,
	recipeId: string,
	ingredientKey: string,
	bodyPartOwnedIds: { string }
): (boolean, string, any?)
	if not waitForPlayerData(player, 10) then
		return false, "Player data is not ready yet.", nil
	end

	local recipe = CraftingRecipeConfig.Get(recipeId)
	if not recipe then
		return false, "That recipe does not exist.", nil
	end
	if typeof(ingredientKey) ~= "string" or ingredientKey == "" then
		return false, "ingredientKey is required.", nil
	end

	local ingredient = findBodyPartIngredient(recipe, ingredientKey)
	if not ingredient then
		return false, "That recipe does not use this body part ingredient.", nil
	end

	local ownedIds, ownedIdError = normalizeOwnedIdList(bodyPartOwnedIds)
	if not ownedIds then
		return false, ownedIdError or "Invalid body part ingredients.", nil
	end
	if #ownedIds == 0 then
		return false, "Select at least one body part.", nil
	end

	local progressState = DataService:GetCraftingProgress(player)
	local recipeProgress = CraftingProgress.GetRecipeProgress(progressState, recipe.id)
	local requiredAmount = getRequiredBodyPartAmount(recipe, ingredientKey)
	local currentAmount = recipeProgress.bodyPartsByIngredientKey[ingredientKey] or 0
	local missingAmount = math.max(0, requiredAmount - currentAmount)
	if missingAmount <= 0 then
		return false, "That ingredient is already full.", nil
	end
	if #ownedIds > missingAmount then
		return false, "That would add too many body parts to this ingredient.", nil
	end

	local bodyPartsState = DataService:GetBodyPartsState(player)
	local equippedLoadout = BodyPartLoadout.NormalizeEquippedState(DataService:GetEquippedLoadout(player), bodyPartsState.ownedById)
	for _, ownedId in ipairs(ownedIds) do
		local ownedRecord = bodyPartsState.ownedById[ownedId]
		if not ownedRecord then
			return false, string.format("Owned body part '%s' was not found.", ownedId), nil
		end
		if ownedRecord.isFavorite == true then
			return false, "Favorited body parts cannot be used as ingredients.", nil
		end
		if hasEquippedOwnedId(equippedLoadout, ownedId) then
			return false, "Equipped body parts cannot be used as ingredients.", nil
		end
		if not bodyPartMatchesRequirement(ownedRecord, ingredient) then
			return false, "Selected body part ingredients do not match the recipe.", nil
		end
	end

	local removedRecords, removeError = DataService:RemoveOwnedBodyParts(player, ownedIds)
	if not removedRecords then
		return false, removeError or "Failed to consume body part ingredients.", nil
	end

	recipeProgress.bodyPartsByIngredientKey[ingredientKey] = currentAmount + #ownedIds
	CraftingProgress.SetRecipeProgress(progressState, recipe.id, recipeProgress)
	local readyMessage = markAutoCraftReadyIfNeeded(progressState, recipe)

	local saved, saveError = saveProgress(player, progressState)
	if not saved then
		return false, saveError or "Failed to save crafting progress.", nil
	end
	if readyMessage then
		sendAutoCraftReadyNotification(player, readyMessage)
	end

	return true, string.format("Added %d body part ingredient%s.", #ownedIds, if #ownedIds == 1 then "" else "s"), {
		consumedBodyParts = removedRecords,
	}
end

function CraftingService:AddMaterialIngredient(
	player: Player,
	recipeId: string,
	materialId: string,
	amount: number
): (boolean, string, any?)
	if not waitForPlayerData(player, 10) then
		return false, "Player data is not ready yet.", nil
	end

	local recipe = CraftingRecipeConfig.Get(recipeId)
	if not recipe then
		return false, "That recipe does not exist.", nil
	end

	local normalizedMaterialId = CraftingMaterialConfig.NormalizeId(materialId) or ""
	local requiredAmount = getRequiredMaterialAmount(recipe, normalizedMaterialId)
	if requiredAmount <= 0 then
		return false, "That recipe does not use this material.", nil
	end

	local requestedAmount = math.max(1, math.floor(tonumber(amount) or 1))
	local progressState = DataService:GetCraftingProgress(player)
	local recipeProgress = CraftingProgress.GetRecipeProgress(progressState, recipe.id)
	local currentAmount = recipeProgress.materialsByMaterialId[normalizedMaterialId] or 0
	local missingAmount = math.max(0, requiredAmount - currentAmount)
	if missingAmount <= 0 then
		return false, "That material is already full.", nil
	end

	local commitAmount = math.min(requestedAmount, missingAmount)
	local materialAmounts = DataService:GetCraftingMaterialAmounts(player)
	if (materialAmounts[normalizedMaterialId] or 0) < commitAmount then
		return false, "You do not have enough crafting materials.", nil
	end

	local updatedMaterialAmounts = table.clone(materialAmounts)
	updatedMaterialAmounts[normalizedMaterialId] = math.max(0, (updatedMaterialAmounts[normalizedMaterialId] or 0) - commitAmount)
	local materialsOk, materialsError = DataService:SetCraftingMaterialAmounts(player, updatedMaterialAmounts)
	if not materialsOk then
		return false, materialsError or "Failed to consume crafting materials.", nil
	end

	recipeProgress.materialsByMaterialId[normalizedMaterialId] = currentAmount + commitAmount
	CraftingProgress.SetRecipeProgress(progressState, recipe.id, recipeProgress)
	local readyMessage = markAutoCraftReadyIfNeeded(progressState, recipe)

	local saved, saveError = saveProgress(player, progressState)
	if not saved then
		return false, saveError or "Failed to save crafting progress.", nil
	end
	if readyMessage then
		sendAutoCraftReadyNotification(player, readyMessage)
	end

	return true, string.format("Added %d material%s.", commitAmount, if commitAmount == 1 then "" else "s"), {
		materialId = normalizedMaterialId,
		amount = commitAmount,
	}
end

function CraftingService:AddAllEligibleIngredients(player: Player, recipeId: string): (boolean, string, any?)
	if not waitForPlayerData(player, 10) then
		return false, "Player data is not ready yet.", nil
	end

	local recipe = CraftingRecipeConfig.Get(recipeId)
	if not recipe then
		return false, "That recipe does not exist.", nil
	end

	local progressState = DataService:GetCraftingProgress(player)
	local recipeProgress = CraftingProgress.GetRecipeProgress(progressState, recipe.id)
	local bodyPartsState = DataService:GetBodyPartsState(player)
	local equippedLoadout = BodyPartLoadout.NormalizeEquippedState(DataService:GetEquippedLoadout(player), bodyPartsState.ownedById)
	local reservedOwnedIds = {}
	local pickedOwnedIds = {}

	for _, ingredient in ipairs(recipe.bodyParts) do
		local ingredientKey = CraftingProgress.GetBodyPartIngredientKey(ingredient)
		local requiredAmount = getBodyPartIngredientAmount(ingredient)
		local currentAmount = recipeProgress.bodyPartsByIngredientKey[ingredientKey] or 0
		local missingAmount = math.max(0, requiredAmount - currentAmount)
		if missingAmount <= 0 then
			continue
		end

		local eligible = {}
		for ownedId, ownedRecord in pairs(bodyPartsState.ownedById) do
			if reservedOwnedIds[ownedId] ~= true
				and ownedRecord.isFavorite ~= true
				and not hasEquippedOwnedId(equippedLoadout, ownedId)
				and bodyPartMatchesRequirement(ownedRecord, ingredient)
			then
				table.insert(eligible, ownedRecord)
			end
		end

		table.sort(eligible, function(left, right)
			local leftRarity = math.max(1, tonumber(left.rarityDenominator) or math.huge)
			local rightRarity = math.max(1, tonumber(right.rarityDenominator) or math.huge)
			if leftRarity ~= rightRarity then
				return leftRarity < rightRarity
			end
			return tostring(left.ownedId) < tostring(right.ownedId)
		end)

		local addedAmount = 0
		for _, ownedRecord in ipairs(eligible) do
			if addedAmount >= missingAmount then
				break
			end
			reservedOwnedIds[ownedRecord.ownedId] = true
			table.insert(pickedOwnedIds, ownedRecord.ownedId)
			addedAmount += 1
		end

		if addedAmount > 0 then
			recipeProgress.bodyPartsByIngredientKey[ingredientKey] = currentAmount + addedAmount
		end
	end

	local materialAmounts = DataService:GetCraftingMaterialAmounts(player)
	local updatedMaterialAmounts = table.clone(materialAmounts)
	local materialCommitCount = 0
	for _, ingredient in ipairs(recipe.materials) do
		local materialId = ingredient.materialId
		local requiredAmount = math.max(1, math.floor(tonumber(ingredient.amount) or 1))
		local currentAmount = recipeProgress.materialsByMaterialId[materialId] or 0
		local missingAmount = math.max(0, requiredAmount - currentAmount)
		local availableAmount = math.max(0, tonumber(updatedMaterialAmounts[materialId]) or 0)
		local commitAmount = math.min(missingAmount, availableAmount)
		if commitAmount > 0 then
			updatedMaterialAmounts[materialId] = availableAmount - commitAmount
			recipeProgress.materialsByMaterialId[materialId] = currentAmount + commitAmount
			materialCommitCount += commitAmount
		end
	end

	if #pickedOwnedIds == 0 and materialCommitCount == 0 then
		return false, "No eligible ingredients were available.", nil
	end

	local removedRecords = nil
	if #pickedOwnedIds > 0 then
		local removeError
		removedRecords, removeError = DataService:RemoveOwnedBodyParts(player, pickedOwnedIds)
		if not removedRecords then
			return false, removeError or "Failed to consume body part ingredients.", nil
		end
	end

	if materialCommitCount > 0 then
		local materialsOk, materialsError = DataService:SetCraftingMaterialAmounts(player, updatedMaterialAmounts)
		if not materialsOk then
			return false, materialsError or "Failed to consume crafting materials.", nil
		end
	end

	CraftingProgress.SetRecipeProgress(progressState, recipe.id, recipeProgress)
	local readyMessage = markAutoCraftReadyIfNeeded(progressState, recipe)
	local saved, saveError = saveProgress(player, progressState)
	if not saved then
		return false, saveError or "Failed to save crafting progress.", nil
	end
	if readyMessage then
		sendAutoCraftReadyNotification(player, readyMessage)
	end

	return true, "Added eligible ingredients.", {
		consumedBodyParts = removedRecords or {},
		materialCount = materialCommitCount,
	}
end

function CraftingService:CraftRecipe(player: Player, recipeId: string, options: any?): (boolean, string, any?)
	if not waitForPlayerData(player, 10) then
		return false, "Player data is not ready yet.", nil
	end

	local recipe = CraftingRecipeConfig.Get(recipeId)
	if not recipe then
		return false, "That recipe does not exist.", nil
	end

	local progressState = DataService:GetCraftingProgress(player)
	local recipeProgress = CraftingProgress.GetRecipeProgress(progressState, recipe.id)
	local hasProgress, progressMessage = hasRequiredProgress(recipe, recipeProgress)
	if not hasProgress then
		return false, progressMessage, nil
	end

	local yieldOk, yieldMessage = validateYieldCapacity(player, recipe)
	if not yieldOk then
		return false, yieldMessage, nil
	end

	local waiveMoneyCost = typeof(options) == "table" and options.waiveMoneyCost == true
	local moneyCost = if waiveMoneyCost then 0 else getRecipeMoneyCost(recipe)
	if moneyCost > 0 and DataService:GetMoney(player) < moneyCost then
		return false, "You do not have enough money.", nil
	end

	local moneyCharged = false
	local function refundMoney()
		if moneyCharged and moneyCost > 0 then
			moneyCharged = false
			DataService:AddMoney(player, moneyCost, "other")
		end
	end

	if moneyCost > 0 then
		local previousMoney = DataService:GetMoney(player)
		if previousMoney < moneyCost then
			return false, "You do not have enough money.", nil
		end

		local updatedMoney = DataService:AddMoney(player, -moneyCost, "crafting_cost")
		if updatedMoney > previousMoney then
			return false, "Could not process the crafting payment.", nil
		end
		moneyCharged = true
	end

	local recipeYield = recipe.yield
	local result = nil
	if recipeYield.kind == "accessory" then
		local createdAccessory, grantError = DataService:AddOwnedAccessory(player, {
			accessoryId = recipeYield.accessoryId,
		})
		if not createdAccessory then
			refundMoney()
			return false, grantError or "Failed to grant crafted accessory.", nil
		end

		result = {
			kind = "accessory",
			accessory = createdAccessory,
		}
	elseif recipeYield.kind == "bodyPart" then
		local _, reservedGrant, reserveError = DataService:ReserveBodyPartRollRecord(player, recipeYield.bodyPartGrant)
		if not reservedGrant then
			refundMoney()
			return false, reserveError or "Failed to reserve crafted body part.", nil
		end

		local createdBodyPart, grantError = DataService:AddOwnedBodyPart(player, recipeYield.bodyPartGrant, reservedGrant)
		if not createdBodyPart then
			refundMoney()
			return false, grantError or "Failed to grant crafted body part.", nil
		end

		result = {
			kind = "bodyPart",
			bodyPart = createdBodyPart,
		}
	else
		refundMoney()
		return false, "Recipe yield is invalid.", nil
	end

	CraftingProgress.SetRecipeProgress(progressState, recipe.id, nil)
	progressState.autoReadyNotifiedRecipeIds[recipe.id] = nil
	if recipeYield.kind == "accessory" then
		progressState.autoRecipeIds[recipe.id] = nil
	end
	local saved, saveError = saveProgress(player, progressState)
	if not saved then
		return false, saveError or "Failed to clear crafting progress.", nil
	end

	BodyPartService.LoadoutChanged:Fire(player)
	return true, string.format('Crafted "%s".', recipe.label), result
end

function CraftingService:TryAutoCommitRolledBodyPart(player: Player, grantPayload: any, options: any?): any
	if not waitForPlayerData(player, 10) then
		return {
			committed = false,
			message = "Player data is not ready yet.",
		}
	end

	local recordLike = if typeof(grantPayload) == "table" then grantPayload else nil
	if not recordLike or typeof(recordLike.pieceId) ~= "string" then
		return {
			committed = false,
			message = "Roll payload is invalid.",
		}
	end

	if not acquireCraftLock(player) then
		return {
			committed = false,
			message = "A craft is already processing.",
		}
	end

	local function finish(result: any): any
		releaseCraftLock(player)
		return result
	end

	local progressState = DataService:GetCraftingProgress(player)
	local hasTargetRecipe = typeof(options) == "table" and typeof(options.targetRecipeId) == "string"
	local targetRecipeId = if hasTargetRecipe then CraftingRecipeConfig.NormalizeId(options.targetRecipeId) else nil
	local hasTargetIngredient = typeof(options) == "table" and options.targetIngredientKey ~= nil
	local targetIngredientKey = if hasTargetIngredient and typeof(options.targetIngredientKey) == "string" and options.targetIngredientKey ~= ""
		then options.targetIngredientKey
		else nil
	local candidates = {}
	for _, recipe in ipairs(CraftingRecipeConfig.GetAll()) do
		if (not hasTargetRecipe or recipe.id == targetRecipeId) and progressState.autoRecipeIds[recipe.id] == true then
			local recipeProgress = CraftingProgress.GetRecipeProgress(progressState, recipe.id)
			for _, ingredient in ipairs(recipe.bodyParts) do
				local ingredientKey = CraftingProgress.GetBodyPartIngredientKey(ingredient)
				local requiredAmount = getBodyPartIngredientAmount(ingredient)
				local currentAmount = recipeProgress.bodyPartsByIngredientKey[ingredientKey] or 0
				if (not hasTargetIngredient or ingredientKey == targetIngredientKey)
					and currentAmount < requiredAmount
					and bodyPartMatchesRequirement(recordLike, ingredient)
				then
					table.insert(candidates, {
						recipe = recipe,
						ingredient = ingredient,
						ingredientKey = ingredientKey,
						specificity = getRequirementSpecificity(ingredient),
					})
				end
			end
		end
	end

	table.sort(candidates, function(left, right)
		if left.recipe.sortOrder ~= right.recipe.sortOrder then
			return left.recipe.sortOrder < right.recipe.sortOrder
		end
		if left.specificity ~= right.specificity then
			return left.specificity > right.specificity
		end
		return left.recipe.id < right.recipe.id
	end)

	local candidate = candidates[1]
	if not candidate then
		local targetRecipe = if targetRecipeId then CraftingRecipeConfig.Get(targetRecipeId) else nil
		if targetRecipe and progressState.autoRecipeIds[targetRecipe.id] == true then
			local targetProgress = CraftingProgress.GetRecipeProgress(progressState, targetRecipe.id)
			local readyToCraft = hasRequiredProgress(targetRecipe, targetProgress)
			if readyToCraft then
				local readyMessage = markAutoCraftReadyIfNeeded(progressState, targetRecipe)
				if readyMessage then
					local saved, saveError = saveProgress(player, progressState)
					if not saved then
						return finish({
							committed = false,
							message = saveError or "Failed to save crafting progress.",
						})
					end
					sendAutoCraftReadyNotification(player, readyMessage)
				end

				return finish({
					committed = false,
					crafted = false,
					recipeId = targetRecipe.id,
					message = buildAutoCraftReadyMessage(targetRecipe),
				})
			end
		end
		return finish({
			committed = false,
			message = "No auto craft recipe needs this body part.",
		})
	end

	local recipe = candidate.recipe
	local recipeProgress = CraftingProgress.GetRecipeProgress(progressState, recipe.id)
	recipeProgress.bodyPartsByIngredientKey[candidate.ingredientKey] =
		(recipeProgress.bodyPartsByIngredientKey[candidate.ingredientKey] or 0) + 1
	CraftingProgress.SetRecipeProgress(progressState, recipe.id, recipeProgress)
	local readyMessage = markAutoCraftReadyIfNeeded(progressState, recipe)

	local saved, saveError = saveProgress(player, progressState)
	if not saved then
		return finish({
			committed = false,
			message = saveError or "Failed to save crafting progress.",
		})
	end
	if readyMessage then
		sendAutoCraftReadyNotification(player, readyMessage)
	end

	return finish({
		committed = true,
		crafted = false,
		recipeId = recipe.id,
		message = readyMessage or string.format('Added roll to "%s".', recipe.label),
	})
end

function CraftingService:SellCraftingMaterialStack(player: Player, materialId: string): (boolean, string, any?)
	if not waitForPlayerData(player, 10) then
		return false, "Player data is not ready yet.", nil
	end

	local config = CraftingMaterialConfig.Get(materialId)
	if not config then
		return false, "That crafting material does not exist.", nil
	end

	local sellPrice = CraftingMaterialConfig.GetSellPrice(config.id)
	if sellPrice <= 0 then
		return false, "That crafting material cannot be sold.", nil
	end

	local removedAmount, removeError = DataService:RemoveCraftingMaterialStack(player, config.id)
	if not removedAmount then
		return false, removeError or "Failed to remove crafting material.", nil
	end

	local payout = sellPrice * removedAmount
	if payout > 0 then
		DataService:AddMoney(player, payout, "material_sell")
	end

	return true, string.format('Sold %d %s for $%s.', removedAmount, config.label, tostring(payout)), {
		materialId = config.id,
		amount = removedAmount,
		payout = payout,
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

	local ok, message, result = CraftingService:CraftRecipe(player, payload.recipeId)
	releaseCraftLock(player)

	return response(ok, message, CraftingService:GetCraftingState(player), result)
end

local function handleSetAutoCraftRecipe(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Auto craft payload must be a table.", CraftingService:GetCraftingState(player), nil)
	end

	local ok, message = CraftingService:SetAutoCraftRecipe(player, payload.recipeId, payload.enabled == true)
	return response(ok, message, CraftingService:GetCraftingState(player), nil)
end

local function handleAddBodyPartIngredient(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Body part ingredient payload must be a table.", CraftingService:GetCraftingState(player), nil)
	end

	if not acquireCraftLock(player) then
		return response(false, "A craft is already processing.", CraftingService:GetCraftingState(player), nil)
	end

	local ok, message, result =
		CraftingService:AddBodyPartIngredient(player, payload.recipeId, payload.ingredientKey, payload.bodyPartOwnedIds)
	releaseCraftLock(player)
	return response(ok, message, CraftingService:GetCraftingState(player), result)
end

local function handleAddMaterialIngredient(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Material ingredient payload must be a table.", CraftingService:GetCraftingState(player), nil)
	end

	if not acquireCraftLock(player) then
		return response(false, "A craft is already processing.", CraftingService:GetCraftingState(player), nil)
	end

	local ok, message, result =
		CraftingService:AddMaterialIngredient(player, payload.recipeId, payload.materialId, payload.amount)
	releaseCraftLock(player)
	return response(ok, message, CraftingService:GetCraftingState(player), result)
end

local function handleAddAllEligibleIngredients(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Add everything payload must be a table.", CraftingService:GetCraftingState(player), nil)
	end

	if not acquireCraftLock(player) then
		return response(false, "A craft is already processing.", CraftingService:GetCraftingState(player), nil)
	end

	local ok, message, result = CraftingService:AddAllEligibleIngredients(player, payload.recipeId)
	releaseCraftLock(player)
	return response(ok, message, CraftingService:GetCraftingState(player), result)
end

local function handleSellMaterialStack(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return response(false, "Sell material payload must be a table.", CraftingService:GetCraftingState(player), nil)
	end

	if not acquireCraftLock(player) then
		return response(false, "A craft is already processing.", CraftingService:GetCraftingState(player), nil)
	end

	local ok, message, result = CraftingService:SellCraftingMaterialStack(player, payload.materialId)
	releaseCraftLock(player)
	return response(ok, message, CraftingService:GetCraftingState(player), result)
end

function CraftingService:OnStart()
	getStateRemote = ensureRemoteFunction(getStateRemote, GET_STATE_REMOTE_NAME)
	craftRecipeRemote = ensureRemoteFunction(craftRecipeRemote, CRAFT_RECIPE_REMOTE_NAME)
	setAutoCraftRecipeRemote = ensureRemoteFunction(setAutoCraftRecipeRemote, SET_AUTO_CRAFT_RECIPE_REMOTE_NAME)
	addBodyPartIngredientRemote = ensureRemoteFunction(addBodyPartIngredientRemote, ADD_BODY_PART_INGREDIENT_REMOTE_NAME)
	addMaterialIngredientRemote = ensureRemoteFunction(addMaterialIngredientRemote, ADD_MATERIAL_INGREDIENT_REMOTE_NAME)
	addAllEligibleIngredientsRemote =
		ensureRemoteFunction(addAllEligibleIngredientsRemote, ADD_ALL_ELIGIBLE_INGREDIENTS_REMOTE_NAME)
	sellMaterialStackRemote = ensureRemoteFunction(sellMaterialStackRemote, SELL_MATERIAL_STACK_REMOTE_NAME)

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

	setAutoCraftRecipeRemote.OnServerInvoke = function(player: Player, payload: any)
		if not RequestLimiter:Allow(player, "remote.crafting.craft") then
			return response(false, "You're crafting too quickly.", CraftingService:GetCraftingState(player), nil)
		end
		return handleSetAutoCraftRecipe(player, payload)
	end

	addBodyPartIngredientRemote.OnServerInvoke = function(player: Player, payload: any)
		if not RequestLimiter:Allow(player, "remote.crafting.craft") then
			return response(false, "You're crafting too quickly.", CraftingService:GetCraftingState(player), nil)
		end
		return handleAddBodyPartIngredient(player, payload)
	end

	addMaterialIngredientRemote.OnServerInvoke = function(player: Player, payload: any)
		if not RequestLimiter:Allow(player, "remote.crafting.craft") then
			return response(false, "You're crafting too quickly.", CraftingService:GetCraftingState(player), nil)
		end
		return handleAddMaterialIngredient(player, payload)
	end

	addAllEligibleIngredientsRemote.OnServerInvoke = function(player: Player, payload: any)
		if not RequestLimiter:Allow(player, "remote.crafting.craft") then
			return response(false, "You're crafting too quickly.", CraftingService:GetCraftingState(player), nil)
		end
		return handleAddAllEligibleIngredients(player, payload)
	end

	sellMaterialStackRemote.OnServerInvoke = function(player: Player, payload: any)
		if not RequestLimiter:Allow(player, "remote.crafting.sell_material") then
			return response(false, "You're selling materials too quickly.", CraftingService:GetCraftingState(player), nil)
		end
		return handleSellMaterialStack(player, payload)
	end
end

function CraftingService:OnPlayerRemoving(player: Player)
	craftLocksByPlayer[player] = nil
end

return CraftingService
