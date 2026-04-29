local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Schema = require(ReplicatedStorage.Lists.Schema)
local AccessoryConfig = require(ReplicatedStorage.Shared.Config.AccessoryConfig)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local CraftingMaterialConfig = require(ReplicatedStorage.Shared.Config.CraftingMaterialConfig)
local CraftingRecipeConfig = require(ReplicatedStorage.Shared.Config.CraftingRecipeConfig)
local BodyPartLoadout = require(ReplicatedStorage.Shared.Character.BodyPartLoadout)
local OwnedAccessories = require(ReplicatedStorage.Shared.Character.OwnedAccessories)
local OwnedBodyParts = require(ReplicatedStorage.Shared.Character.OwnedBodyParts)
local AccessoryPresentation = require(ReplicatedStorage.Shared.UI.AccessoryPresentation)
local BodyPartPresentation = require(ReplicatedStorage.Shared.UI.BodyPartPresentation)
local Notify = require(ReplicatedStorage.Shared.UI.Notify)
local ViewportModelRenderer = require(ReplicatedStorage.Shared.UI.ViewportModelRenderer)

local DataController = require(script.Parent.DataController)
local MerchantPresentationController = require(script.Parent.MerchantPresentationController)
local UIController = require(script.Parent.UIController)

local LOCAL_PLAYER = Players.LocalPlayer
local WINDOW_NAME = "CraftingMenu"
local REMOTES_FOLDER_NAME = "Remotes"
local CRAFTING_FOLDER_NAME = "Crafting"
local GET_STATE_REMOTE_NAME = "GetCraftingState"
local CRAFT_RECIPE_REMOTE_NAME = "CraftRecipe"
local BODY_PARTS_DATA_KEY = Schema.BodyParts and Schema.BodyParts.key or "bodyParts"
local EQUIPPED_LOADOUT_KEY = Schema.EquippedLoadout and Schema.EquippedLoadout.key or "equippedLoadout"
local ACCESSORIES_DATA_KEY = Schema.Accessories and Schema.Accessories.key or "accessories"
local EQUIPPED_ACCESSORIES_DATA_KEY = Schema.EquippedAccessories and Schema.EquippedAccessories.key or "equippedAccessories"
local CRAFTING_MATERIALS_DATA_KEY = Schema.CraftingMaterials and Schema.CraftingMaterials.key or "craftingMaterials"
local MONEY_DATA_KEY = Schema.Money and Schema.Money.key or "money"

local SELECTED_ROW_TRANSPARENCY = 0
local DEFAULT_ROW_TRANSPARENCY = 0.16
local DISABLED_ROW_TRANSPARENCY = 0.45
local ENABLED_BUTTON_TEXT_TRANSPARENCY = 0
local DISABLED_BUTTON_TEXT_TRANSPARENCY = 0.35
local VIEWPORT_ROTATION_SPEED_RADIANS = math.rad(24)
local ITEM_STAT_ROW_PREFIX = "CraftingItemStat_"
local ITEM_STAT_TEXT_SIZE_BOOST = 1

type CraftingRemotes = {
	getState: RemoteFunction,
	craftRecipe: RemoteFunction,
}

type CraftingUi = {
	root: GuiObject,
	searchBox: TextBox?,
	recipeList: ScrollingFrame,
	recipeTemplate: ImageButton,
	itemName: TextLabel,
	itemDescription: TextLabel?,
	viewportFrame: ViewportFrame?,
	requirementList: ScrollingFrame,
	requirementTemplate: GuiObject,
	craftButton: GuiButton,
	craftButtonLabel: TextLabel?,
	storeButton: GuiButton?,
}

local CraftingController = {
	_started = false,
	_isOpen = false,
	_requestInFlight = false,
	_promptConnection = nil :: RBXScriptConnection?,
	_searchConnection = nil :: RBXScriptConnection?,
	_viewportRotationConnection = nil :: RBXScriptConnection?,
	_ui = nil :: CraftingUi?,
	_remotes = nil :: CraftingRemotes?,
	_state = nil :: any,
	_selectedRecipeId = nil :: string?,
	_recipeRowsById = {} :: { [string]: ImageButton },
}

local function showNotification(text: string, tone: string?)
	Notify.Show(text, {
		channel = "inventory",
		duration = 4,
		tone = tone,
	})
end

local function formatWholeNumber(value: any): string
	return BodyPartPresentation.FormatNumberish(math.max(0, math.floor(tonumber(value) or 0)))
end

local function buildRecipeItemStatRows(recipe: any): { any }
	local recipeYield = if typeof(recipe) == "table" then recipe.yield else nil
	if typeof(recipeYield) ~= "table" or recipeYield.kind ~= "accessory" then
		return {}
	end

	return AccessoryPresentation.BuildStatRows(recipeYield.accessoryId)
end

local function countDictionary(dictionary: any): number
	if typeof(dictionary) ~= "table" then
		return 0
	end

	local count = 0
	for _ in pairs(dictionary) do
		count += 1
	end
	return count
end

local function normalizeMaterialAmounts(materials: any): { [string]: number }
	local source = materials
	if typeof(source) == "table" and typeof(source.amountByMaterialId) == "table" then
		source = source.amountByMaterialId
	end

	local amounts = {}
	if typeof(source) ~= "table" then
		return amounts
	end

	for materialId, amount in pairs(source) do
		local normalizedId = CraftingMaterialConfig.NormalizeId(materialId)
		if normalizedId then
			amounts[normalizedId] = math.max(0, math.floor(tonumber(amount) or 0))
		end
	end
	return amounts
end

local function getFirstTextLabel(root: Instance, name: string): TextLabel?
	local label = root:FindFirstChild(name, true)
	return if label and label:IsA("TextLabel") then label else nil
end

local function hideGeneratedChildren(container: Instance, prefix: string)
	for _, child in ipairs(container:GetChildren()) do
		if string.find(child.Name, prefix, 1, true) == 1 then
			child:Destroy()
		end
	end
end

local function hideNativeTemplates(container: Instance, template: GuiObject)
	for _, child in ipairs(container:GetChildren()) do
		if child.Name == template.Name and child:IsA("GuiObject") then
			child.Visible = false
			if child:IsA("GuiButton") then
				child.Active = false
				child.AutoButtonColor = false
			end
		end
	end
end

local function ensureItemStatLayout(container: TextLabel): UIListLayout
	local layout = container:FindFirstChild("CraftingItemStatLayout")
	if layout and layout:IsA("UIListLayout") then
		return layout
	end

	layout = Instance.new("UIListLayout")
	layout.Name = "CraftingItemStatLayout"
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = container
	return layout
end

local function applyItemStatLabelStyle(source: TextLabel, target: TextLabel, color: Color3)
	target.BackgroundTransparency = 1
	target.BorderSizePixel = 0
	target.FontFace = source.FontFace
	target.RichText = false
	target.TextColor3 = color
	target.TextSize = source.TextSize + ITEM_STAT_TEXT_SIZE_BOOST
	target.TextTransparency = source.TextTransparency
	target.TextTruncate = Enum.TextTruncate.AtEnd
	target.TextWrapped = false
	target.TextYAlignment = Enum.TextYAlignment.Center
end

local function clearRecipeItemStatRows(container: TextLabel)
	container.Text = ""
	hideGeneratedChildren(container, ITEM_STAT_ROW_PREFIX)
end

local function renderRecipeItemStatRows(container: TextLabel, rows: { any })
	clearRecipeItemStatRows(container)
	ensureItemStatLayout(container)

	local statTextSize = container.TextSize + ITEM_STAT_TEXT_SIZE_BOOST
	local rowHeight = math.max(18, math.ceil(statTextSize + 4))
	for index, rowData in ipairs(rows) do
		local row = Instance.new("Frame")
		row.Name = string.format("%s%03d", ITEM_STAT_ROW_PREFIX, index)
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		row.ClipsDescendants = true
		row.LayoutOrder = index
		row.Size = UDim2.new(1, 0, 0, rowHeight)
		row.Parent = container

		local statLabel = Instance.new("TextLabel")
		statLabel.Name = "Stat"
		statLabel.Position = UDim2.fromOffset(0, 0)
		statLabel.Size = UDim2.new(1, 0, 1, 0)
		statLabel.Text = string.format("%s %s", rowData.valueText, rowData.labelText)
		statLabel.TextXAlignment = Enum.TextXAlignment.Left
		applyItemStatLabelStyle(container, statLabel, rowData.color)
		statLabel.Parent = row
	end
end

local function cloneRecipeEntries(entries: any): { any }
	local results = {}
	if typeof(entries) == "table" then
		for _, entry in ipairs(entries) do
			if typeof(entry) == "table" and typeof(entry.id) == "string" then
				table.insert(results, entry)
			end
		end
	end

	if #results == 0 then
		for _, entry in ipairs(CraftingRecipeConfig.GetAll()) do
			table.insert(results, entry)
		end
	end

	table.sort(results, function(left, right)
		local leftOrder = math.floor(tonumber(left.sortOrder) or 0)
		local rightOrder = math.floor(tonumber(right.sortOrder) or 0)
		if leftOrder ~= rightOrder then
			return leftOrder < rightOrder
		end
		return tostring(left.id) < tostring(right.id)
	end)

	return results
end

local function getYieldInfo(recipe: any): (string, string, Model?)
	local recipeYield = if typeof(recipe) == "table" then recipe.yield else nil
	if typeof(recipeYield) ~= "table" then
		return tostring(recipe and recipe.label or "Recipe"), "[Recipe]", nil
	end

	if recipeYield.kind == "accessory" then
		local config = AccessoryConfig.Get(recipeYield.accessoryId)
		if not config then
			return tostring(recipe.label or recipe.id or "Accessory"), "[Accessory]", nil
		end

		local slotText = if config.slot == "HeadAccessory" then "[Head]" else "[Gear]"
		return config.label, slotText, AccessoryPresentation.GetPlaceholderModel(config)
	end

	if recipeYield.kind == "bodyPart" and typeof(recipeYield.bodyPartGrant) == "table" then
		local piece = BodyPartsCatalog.GetPiece(recipeYield.bodyPartGrant.pieceId)
		if not piece then
			return tostring(recipe.label or recipe.id or "Body Part"), "[Body Part]", nil
		end

		return piece.displayName, "[Body Part]", BodyPartsCatalog.ResolveBundleModel(piece.id)
	end

	return tostring(recipe.label or recipe.id or "Recipe"), "[Recipe]", nil
end

local function isBodyPartEquipped(equippedLoadout: any, ownedId: string): boolean
	if typeof(equippedLoadout) ~= "table" then
		return false
	end

	for _, entry in pairs(equippedLoadout) do
		if typeof(entry) == "table" and entry.ownedId == ownedId then
			return true
		end
	end
	return false
end

local function getBodyPartSortValue(record: any): (number, number, number, string)
	local rarity = math.max(1, tonumber(record and record.rarityDenominator) or math.huge)
	local income = math.max(0, tonumber(record and record.finalPassiveIncomePerSecond) or 0)
	local serial = math.max(0, tonumber(record and record.serialNumber) or 0)
	local ownedId = tostring(record and record.ownedId or "")
	return rarity, income, serial, ownedId
end

local function sortBodyPartIngredients(left: any, right: any): boolean
	local leftRarity, leftIncome, leftSerial, leftId = getBodyPartSortValue(left)
	local rightRarity, rightIncome, rightSerial, rightId = getBodyPartSortValue(right)
	if leftRarity ~= rightRarity then
		return leftRarity < rightRarity
	end
	if leftIncome ~= rightIncome then
		return leftIncome < rightIncome
	end
	if leftSerial ~= rightSerial then
		return leftSerial < rightSerial
	end
	return leftId < rightId
end

local function getBodyPartIngredientAmount(ingredient: any): number
	return math.max(1, math.floor(tonumber(ingredient and ingredient.amount) or 1))
end

local function getBodyPartIngredientKey(ingredient: any): string
	if typeof(ingredient) ~= "table" then
		return "unknown"
	end
	if typeof(ingredient.pieceId) == "string" and ingredient.pieceId ~= "" then
		return "piece:" .. ingredient.pieceId
	end
	if typeof(ingredient.setId) == "string" and ingredient.setId ~= "" then
		if typeof(ingredient.region) == "string" and ingredient.region ~= "" then
			return string.format("set:%s:%s", ingredient.setId, ingredient.region)
		end
		return "set:" .. ingredient.setId
	end
	return "unknown"
end

local function getBodyPartRequirementSpecificity(requirement: any): number
	if typeof(requirement) ~= "table" then
		return 0
	end
	if typeof(requirement.pieceId) == "string" and requirement.pieceId ~= "" then
		return 3
	end
	if typeof(requirement.setId) == "string" and requirement.setId ~= "" and typeof(requirement.region) == "string" and requirement.region ~= "" then
		return 2
	end
	if typeof(requirement.setId) == "string" and requirement.setId ~= "" then
		return 1
	end
	return 0
end

local function buildExpandedBodyPartRequirements(recipe: any): { any }
	local requirements = {}
	for _, ingredient in ipairs(if typeof(recipe) == "table" and typeof(recipe.bodyParts) == "table" then recipe.bodyParts else {}) do
		for _ = 1, getBodyPartIngredientAmount(ingredient) do
			table.insert(requirements, {
				pieceId = ingredient.pieceId,
				setId = ingredient.setId,
				region = ingredient.region,
				amount = 1,
			})
		end
	end

	table.sort(requirements, function(left, right)
		local leftSpecificity = getBodyPartRequirementSpecificity(left)
		local rightSpecificity = getBodyPartRequirementSpecificity(right)
		if leftSpecificity ~= rightSpecificity then
			return leftSpecificity > rightSpecificity
		end
		return getBodyPartIngredientKey(left) < getBodyPartIngredientKey(right)
	end)

	return requirements
end

local function bodyPartRecordMatchesIngredient(record: any, ingredient: any): boolean
	if typeof(record) ~= "table" or typeof(ingredient) ~= "table" then
		return false
	end

	if typeof(ingredient.pieceId) == "string" and ingredient.pieceId ~= "" then
		return record.pieceId == ingredient.pieceId
	end

	if typeof(ingredient.setId) ~= "string" or ingredient.setId == "" then
		return false
	end

	local piece = if typeof(record.pieceId) == "string" then BodyPartsCatalog.GetPiece(record.pieceId) else nil
	if not piece or piece.setId ~= ingredient.setId then
		return false
	end

	return typeof(ingredient.region) ~= "string" or ingredient.region == "" or piece.region == ingredient.region
end

local function getBodyPartIngredientLabel(ingredient: any): string
	if typeof(ingredient) ~= "table" then
		return "Body Part"
	end

	if typeof(ingredient.pieceId) == "string" and ingredient.pieceId ~= "" then
		local piece = BodyPartsCatalog.GetPiece(ingredient.pieceId)
		return if piece then piece.displayName else ingredient.pieceId
	end

	if typeof(ingredient.setId) == "string" and ingredient.setId ~= "" then
		local setConfig = BodyPartsCatalog.GetSet(ingredient.setId)
		local setDisplayName = if setConfig then setConfig.displayName else ingredient.setId
		if typeof(ingredient.region) == "string" and ingredient.region ~= "" then
			return string.format("%s %s", setDisplayName, BodyPartPresentation.GetLocalizedRegionLabel(ingredient.region))
		end
		return setDisplayName
	end

	return "Body Part"
end

local function getBodyPartIngredientSetConfig(ingredient: any): any?
	if typeof(ingredient) ~= "table" or typeof(ingredient.setId) ~= "string" or ingredient.setId == "" then
		return nil
	end

	return BodyPartsCatalog.GetSet(ingredient.setId)
end

local function applySetRollDisplayStyle(label: TextLabel, setConfig: any?)
	local rollDisplay = if typeof(setConfig) == "table" then setConfig.rollDisplay else nil
	if typeof(rollDisplay) ~= "table" then
		return
	end

	if typeof(rollDisplay.color) == "Color3" then
		label.TextColor3 = rollDisplay.color
	end

	local fontFace = rollDisplay.fontFace
	if typeof(fontFace) ~= "Font" then
		return
	end

	if typeof(rollDisplay.fontWeight) == "EnumItem" then
		label.FontFace = Font.new(fontFace.Family, rollDisplay.fontWeight, fontFace.Style)
	else
		label.FontFace = fontFace
	end
end

function CraftingController:_getPlayerGui(): PlayerGui
	return LOCAL_PLAYER:WaitForChild("PlayerGui")
end

function CraftingController:_getOwnedBodyParts(): { [string]: any }
	local state = self._state
	if typeof(state) == "table" and typeof(state.ownedBodyParts) == "table" then
		return state.ownedBodyParts
	end

	local bodyPartsState = DataController:Get(BODY_PARTS_DATA_KEY)
	if typeof(bodyPartsState) == "table" and typeof(bodyPartsState.ownedById) == "table" then
		return bodyPartsState.ownedById
	end

	return {}
end

function CraftingController:_getOwnedAccessories(): { [string]: any }
	local state = self._state
	if typeof(state) == "table" and typeof(state.ownedAccessories) == "table" then
		return state.ownedAccessories
	end

	local accessoryState = DataController:Get(ACCESSORIES_DATA_KEY)
	if typeof(accessoryState) == "table" and typeof(accessoryState.ownedById) == "table" then
		return accessoryState.ownedById
	end

	return {}
end

function CraftingController:_getMaterialAmounts(): { [string]: number }
	local state = self._state
	if typeof(state) == "table" and state.craftingMaterials ~= nil then
		return normalizeMaterialAmounts(state.craftingMaterials)
	end

	return normalizeMaterialAmounts(DataController:Get(CRAFTING_MATERIALS_DATA_KEY))
end

function CraftingController:_getMoney(): number
	local state = self._state
	if typeof(state) == "table" and state.money ~= nil then
		return math.max(0, math.floor(tonumber(state.money) or 0))
	end

	return math.max(0, math.floor(tonumber(DataController:Get(MONEY_DATA_KEY)) or 0))
end

function CraftingController:_getEquippedLoadout()
	return BodyPartLoadout.NormalizeEquippedState(DataController:Get(EQUIPPED_LOADOUT_KEY), self:_getOwnedBodyParts())
end

function CraftingController:_getRecipes(): { any }
	local state = self._state
	return cloneRecipeEntries(if typeof(state) == "table" then state.recipes else nil)
end

function CraftingController:_findRecipe(recipeId: string?): any?
	if typeof(recipeId) ~= "string" then
		return nil
	end

	for _, recipe in ipairs(self:_getRecipes()) do
		if recipe.id == recipeId then
			return recipe
		end
	end

	return nil
end

function CraftingController:_getEligibleBodyPartsForIngredient(ingredient: any): { any }
	local ownedBodyParts = self:_getOwnedBodyParts()
	local equippedLoadout = self:_getEquippedLoadout()
	local eligible = {}

	for ownedId, record in pairs(ownedBodyParts) do
		if typeof(record) == "table"
			and bodyPartRecordMatchesIngredient(record, ingredient)
			and record.isFavorite ~= true
			and not isBodyPartEquipped(equippedLoadout, ownedId)
		then
			table.insert(eligible, record)
		end
	end

	table.sort(eligible, sortBodyPartIngredients)
	return eligible
end

function CraftingController:_buildAutoPickedBodyPartIds(recipe: any): ({ string }, { [string]: number })
	local pickedIds = {}
	local availableCounts = {}
	local reservedByOwnedId = {}

	for _, ingredient in ipairs(if typeof(recipe.bodyParts) == "table" then recipe.bodyParts else {}) do
		availableCounts[getBodyPartIngredientKey(ingredient)] = #(self:_getEligibleBodyPartsForIngredient(ingredient))
	end

	for _, requirement in ipairs(buildExpandedBodyPartRequirements(recipe)) do
		for _, record in ipairs(self:_getEligibleBodyPartsForIngredient(requirement)) do
			local ownedId = record.ownedId
			if ownedId and not reservedByOwnedId[ownedId] then
				reservedByOwnedId[ownedId] = true
				table.insert(pickedIds, ownedId)
				break
			end
		end
	end

	return pickedIds, availableCounts
end

function CraftingController:_getCraftability(recipe: any): (boolean, string, { string }, { [string]: number })
	if typeof(recipe) ~= "table" then
		return false, "Select a recipe.", {}, {}
	end

	local pickedIds, bodyPartCounts = self:_buildAutoPickedBodyPartIds(recipe)
	local requiredBodyPartCount = #buildExpandedBodyPartRequirements(recipe)
	if #pickedIds < requiredBodyPartCount then
		return false, "Missing body part ingredients.", pickedIds, bodyPartCounts
	end

	local materialAmounts = self:_getMaterialAmounts()
	for _, ingredient in ipairs(if typeof(recipe.materials) == "table" then recipe.materials else {}) do
		local materialId = tostring(ingredient.materialId or "")
		local requiredAmount = math.max(1, math.floor(tonumber(ingredient.amount) or 1))
		if (materialAmounts[materialId] or 0) < requiredAmount then
			return false, "Missing crafting materials.", pickedIds, bodyPartCounts
		end
	end

	local moneyCost = math.max(0, math.floor(tonumber(recipe.moneyCost) or 0))
	if self:_getMoney() < moneyCost then
		return false, "Not enough money.", pickedIds, bodyPartCounts
	end

	local recipeYield = recipe.yield
	if typeof(recipeYield) ~= "table" then
		return false, "Recipe yield is invalid.", pickedIds, bodyPartCounts
	end

	if recipeYield.kind == "accessory" then
		if not AccessoryConfig.Get(recipeYield.accessoryId) then
			return false, "Recipe yield is invalid.", pickedIds, bodyPartCounts
		end
		if countDictionary(self:_getOwnedAccessories()) >= OwnedAccessories.MAX_OWNED_COUNT then
			return false, "Accessory inventory is full.", pickedIds, bodyPartCounts
		end
	elseif recipeYield.kind == "bodyPart" then
		local projectedCount = countDictionary(self:_getOwnedBodyParts()) - requiredBodyPartCount + 1
		if projectedCount > OwnedBodyParts.MAX_OWNED_COUNT then
			return false, "Body part inventory is full.", pickedIds, bodyPartCounts
		end
	else
		return false, "Recipe yield is invalid.", pickedIds, bodyPartCounts
	end

	return true, "Ready to craft.", pickedIds, bodyPartCounts
end

function CraftingController:_ensureUi(): CraftingUi
	if self._ui and self._ui.root.Parent then
		return self._ui
	end

	local modalRoot = self:_getPlayerGui():WaitForChild("ModalRoot", 30)
	assert(modalRoot and modalRoot:IsA("ScreenGui"), "PlayerGui.ModalRoot is missing.")

	local root = modalRoot:WaitForChild(WINDOW_NAME, 30)
	assert(root and root:IsA("GuiObject"), "PlayerGui.ModalRoot.CraftingMenu is missing.")

	local itemSelect = root:WaitForChild("ItemSelect", 30)
	assert(itemSelect and itemSelect:IsA("Frame"), "CraftingMenu.ItemSelect is missing.")

	local searchBar = itemSelect:FindFirstChild("SearchBar")
	local searchBox = if searchBar then searchBar:FindFirstChild("TextBox") else nil
	local recipeList = itemSelect:WaitForChild("ScrollingFrame", 30)
	assert(recipeList and recipeList:IsA("ScrollingFrame"), "CraftingMenu.ItemSelect.ScrollingFrame is missing.")

	local recipeTemplate = recipeList:FindFirstChild("Template")
	assert(recipeTemplate and recipeTemplate:IsA("ImageButton"), "CraftingMenu.ItemSelect.ScrollingFrame.Template is missing.")

	local recipeRoot = root:WaitForChild("Recipe", 30)
	assert(recipeRoot and recipeRoot:IsA("Frame"), "CraftingMenu.Recipe is missing.")

	local itemName = recipeRoot:WaitForChild("ItemName", 30)
	assert(itemName and itemName:IsA("TextLabel"), "CraftingMenu.Recipe.ItemName is missing.")

	local itemDescription = recipeRoot:FindFirstChild("ItemDescription")
	if itemDescription and not itemDescription:IsA("TextLabel") then
		itemDescription = nil
	end

	local viewportFrame = recipeRoot:FindFirstChild("AccessoryViewport")
	if viewportFrame and not viewportFrame:IsA("ViewportFrame") then
		viewportFrame = nil
	end

	local requirementFrame = recipeRoot:WaitForChild("Frame", 30)
	assert(requirementFrame and requirementFrame:IsA("Frame"), "CraftingMenu.Recipe.Frame is missing.")

	local requirementList = requirementFrame:WaitForChild("RecipeList", 30)
	assert(requirementList and requirementList:IsA("ScrollingFrame"), "CraftingMenu.Recipe.Frame.RecipeList is missing.")

	local requirementTemplate = requirementList:FindFirstChild("Template")
	assert(requirementTemplate and requirementTemplate:IsA("GuiObject"), "CraftingMenu.Recipe.Frame.RecipeList.Template is missing.")

	local craftButton = recipeRoot:WaitForChild("CraftButton", 30)
	assert(craftButton and craftButton:IsA("GuiButton"), "CraftingMenu.Recipe.CraftButton is missing.")

	local storeButton = recipeRoot:FindFirstChild("Store")

	self._ui = {
		root = root,
		searchBox = if searchBox and searchBox:IsA("TextBox") then searchBox else nil,
		recipeList = recipeList,
		recipeTemplate = recipeTemplate,
		itemName = itemName,
		itemDescription = itemDescription :: TextLabel?,
		viewportFrame = viewportFrame :: ViewportFrame?,
		requirementList = requirementList,
		requirementTemplate = requirementTemplate,
		craftButton = craftButton,
		craftButtonLabel = craftButton:FindFirstChildWhichIsA("TextLabel"),
		storeButton = if storeButton and storeButton:IsA("GuiButton") then storeButton else nil,
	}

	hideNativeTemplates(recipeList, recipeTemplate)
	hideNativeTemplates(requirementList, requirementTemplate)

	if self._ui.itemDescription then
		self._ui.itemDescription.RichText = false
		self._ui.itemDescription.TextXAlignment = Enum.TextXAlignment.Left
		self._ui.itemDescription.TextYAlignment = Enum.TextYAlignment.Top
		renderRecipeItemStatRows(self._ui.itemDescription, {})
	end

	if self._ui.storeButton then
		self._ui.storeButton.Visible = false
		self._ui.storeButton.Active = false
	end

	UIController:CreateButton(craftButton, function()
		self:_craftSelectedRecipe()
	end)

	if self._ui.searchBox then
		self._searchConnection = self._ui.searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			if self._isOpen then
				self:_syncRecipeRows()
			end
		end)
	end

	return self._ui
end

function CraftingController:_ensureRemotes(): boolean
	if self._remotes and self._remotes.getState and self._remotes.craftRecipe then
		return true
	end

	local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME) or ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, 10)
	if not (remotesFolder and remotesFolder:IsA("Folder")) then
		return false
	end

	local craftingFolder = remotesFolder:FindFirstChild(CRAFTING_FOLDER_NAME) or remotesFolder:WaitForChild(CRAFTING_FOLDER_NAME, 10)
	if not (craftingFolder and craftingFolder:IsA("Folder")) then
		return false
	end

	local getState = craftingFolder:FindFirstChild(GET_STATE_REMOTE_NAME)
	local craftRecipe = craftingFolder:FindFirstChild(CRAFT_RECIPE_REMOTE_NAME)
	if not (getState and getState:IsA("RemoteFunction")) then
		return false
	end
	if not (craftRecipe and craftRecipe:IsA("RemoteFunction")) then
		return false
	end

	self._remotes = {
		getState = getState,
		craftRecipe = craftRecipe,
	}
	return true
end

function CraftingController:_invokeRemote(remote: RemoteFunction, payload: any?): any?
	local ok, result = pcall(function()
		if payload ~= nil then
			return remote:InvokeServer(payload)
		end
		return remote:InvokeServer()
	end)

	if not ok then
		Logger.Warn(string.format("[CraftingController] Remote %s failed: %s", remote.Name, tostring(result)))
		return nil
	end

	return result
end

function CraftingController:_applyState(state: any)
	if typeof(state) == "table" then
		self._state = state
	end
end

function CraftingController:_hydrateStateFromData(key: string?)
	local state = if typeof(self._state) == "table" then self._state else {}

	if key == nil or key == BODY_PARTS_DATA_KEY then
		local bodyPartsState = DataController:Get(BODY_PARTS_DATA_KEY)
		if typeof(bodyPartsState) == "table" and typeof(bodyPartsState.ownedById) == "table" then
			state.ownedBodyParts = bodyPartsState.ownedById
		end
	end

	if key == nil or key == ACCESSORIES_DATA_KEY then
		local accessoryState = DataController:Get(ACCESSORIES_DATA_KEY)
		if typeof(accessoryState) == "table" and typeof(accessoryState.ownedById) == "table" then
			state.ownedAccessories = accessoryState.ownedById
		end
	end

	if key == nil or key == EQUIPPED_ACCESSORIES_DATA_KEY then
		local equippedAccessories = DataController:Get(EQUIPPED_ACCESSORIES_DATA_KEY)
		if typeof(equippedAccessories) == "table" then
			state.equippedAccessories = equippedAccessories
		end
	end

	if key == nil or key == CRAFTING_MATERIALS_DATA_KEY then
		local craftingMaterials = DataController:Get(CRAFTING_MATERIALS_DATA_KEY)
		if typeof(craftingMaterials) == "table" and typeof(craftingMaterials.amountByMaterialId) == "table" then
			state.craftingMaterials = craftingMaterials.amountByMaterialId
		end
	end

	if key == nil or key == MONEY_DATA_KEY then
		state.money = math.max(0, math.floor(tonumber(DataController:Get(MONEY_DATA_KEY)) or 0))
	end

	if state.recipes == nil then
		state.recipes = CraftingRecipeConfig.GetAll()
	end

	self._state = state
end

function CraftingController:_requestCraftingState(showFailureMessage: boolean?): boolean
	if not self:_ensureRemotes() then
		if showFailureMessage then
			showNotification("Crafting is not ready right now.")
		end
		return false
	end

	local result = self:_invokeRemote(self._remotes.getState)
	if typeof(result) ~= "table" then
		if showFailureMessage then
			showNotification("Crafting state could not be loaded.")
		end
		return false
	end

	self:_applyState(result.state)
	if result.ok ~= true and showFailureMessage then
		showNotification(tostring(result.message or "Crafting state could not be loaded."))
	end

	return result.ok == true
end

function CraftingController:_recipeMatchesSearch(recipe: any, query: string): boolean
	if query == "" then
		return true
	end

	local yieldLabel, typeLabel = getYieldInfo(recipe)
	local searchableParts = {
		tostring(recipe.label or ""),
		tostring(recipe.description or ""),
		yieldLabel,
		typeLabel,
	}

	for _, ingredient in ipairs(if typeof(recipe.bodyParts) == "table" then recipe.bodyParts else {}) do
		table.insert(searchableParts, getBodyPartIngredientLabel(ingredient))
	end

	for _, ingredient in ipairs(if typeof(recipe.materials) == "table" then recipe.materials else {}) do
		local material = CraftingMaterialConfig.Get(ingredient.materialId)
		table.insert(searchableParts, if material then material.label else tostring(ingredient.materialId or ""))
	end

	return string.find(string.lower(table.concat(searchableParts, " ")), query, 1, true) ~= nil
end

function CraftingController:_selectRecipe(recipeId: string?)
	self._selectedRecipeId = recipeId
	self:_syncDetail()
	self:_refreshRecipeRowStates()
end

function CraftingController:_setCraftButtonEnabled(enabled: boolean)
	local ui = self:_ensureUi()
	ui.craftButton.Active = enabled
	ui.craftButton.Selectable = enabled
	ui.craftButton.AutoButtonColor = false

	if ui.craftButtonLabel then
		ui.craftButtonLabel.TextTransparency = if enabled then ENABLED_BUTTON_TEXT_TRANSPARENCY else DISABLED_BUTTON_TEXT_TRANSPARENCY
	end

	for _, child in ipairs(ui.craftButton:GetChildren()) do
		if child:IsA("ImageLabel") then
			if child.Name == "Rays" then
				child.ImageTransparency = if enabled then 0 else 0.45
			else
				child.ImageTransparency = if enabled then 0 else 0.28
			end
		end
	end
end

function CraftingController:_setCraftButtonText(recipe: any?)
	local ui = self:_ensureUi()
	if not ui.craftButtonLabel then
		return
	end

	local moneyCost = if typeof(recipe) == "table" then math.max(0, math.floor(tonumber(recipe.moneyCost) or 0)) else 0
	ui.craftButtonLabel.Text = if moneyCost > 0 then string.format("Craft ($%s)", formatWholeNumber(moneyCost)) else "Craft"
end

function CraftingController:_refreshRecipeRowStates()
	for recipeId, row in pairs(self._recipeRowsById) do
		if row.Parent then
			local recipe = self:_findRecipe(recipeId)
			local canCraft = false
			if recipe then
				canCraft = self:_getCraftability(recipe)
			end

			if recipeId == self._selectedRecipeId then
				row.ImageTransparency = SELECTED_ROW_TRANSPARENCY
			elseif canCraft then
				row.ImageTransparency = DEFAULT_ROW_TRANSPARENCY
			else
				row.ImageTransparency = DISABLED_ROW_TRANSPARENCY
			end
		end
	end
end

function CraftingController:_syncRecipeRows()
	local ui = self:_ensureUi()
	hideGeneratedChildren(ui.recipeList, "CraftingRecipe_")
	hideNativeTemplates(ui.recipeList, ui.recipeTemplate)
	self._recipeRowsById = {}

	local query = ""
	if ui.searchBox then
		query = string.lower(string.match(ui.searchBox.Text or "", "^%s*(.-)%s*$") or "")
	end

	local visibleRecipes = {}
	for _, recipe in ipairs(self:_getRecipes()) do
		if self:_recipeMatchesSearch(recipe, query) then
			table.insert(visibleRecipes, recipe)
		end
	end

	local selectedStillVisible = false
	local firstCraftableRecipe = nil
	local firstVisibleRecipe = nil

	for index, recipe in ipairs(visibleRecipes) do
		local row = ui.recipeTemplate:Clone()
		row.Name = "CraftingRecipe_" .. recipe.id
		row.LayoutOrder = index
		row.Visible = true
		row.Active = true
		row.AutoButtonColor = false

		local yieldLabel, typeLabel = getYieldInfo(recipe)
		local nameLabel = getFirstTextLabel(row, "AccessoryName")
		local descriptionLabel = getFirstTextLabel(row, "AccessoryDescription")
		local typeLabelInstance = getFirstTextLabel(row, "AccessoryType")
		if nameLabel then
			nameLabel.Text = tostring(recipe.label or yieldLabel)
		end
		if descriptionLabel then
			descriptionLabel.Text = tostring(recipe.description or "")
		end
		if typeLabelInstance then
			typeLabelInstance.Text = typeLabel
		end

		row.Parent = ui.recipeList
		self._recipeRowsById[recipe.id] = row

		UIController:CreateButton(row, function()
			self:_selectRecipe(recipe.id)
		end)

		firstVisibleRecipe = firstVisibleRecipe or recipe
		if recipe.id == self._selectedRecipeId then
			selectedStillVisible = true
		end
		local canCraft = self:_getCraftability(recipe)
		if canCraft and firstCraftableRecipe == nil then
			firstCraftableRecipe = recipe
		end
	end

	if not selectedStillVisible then
		local nextRecipe = firstCraftableRecipe or firstVisibleRecipe
		self._selectedRecipeId = if nextRecipe then nextRecipe.id else nil
	end

	self:_refreshRecipeRowStates()
	self:_syncDetail()
end

function CraftingController:_stopViewportRotation()
	if self._viewportRotationConnection then
		self._viewportRotationConnection:Disconnect()
		self._viewportRotationConnection = nil
	end
end

function CraftingController:_startViewportRotation(viewportFrame: ViewportFrame)
	if self._viewportRotationConnection or not self._isOpen then
		return
	end

	self._viewportRotationConnection = RunService.RenderStepped:Connect(function(deltaTime: number)
		local ui = self._ui
		local activeViewportFrame = ui and ui.viewportFrame
		if not self._isOpen or activeViewportFrame ~= viewportFrame or not viewportFrame.Parent or not viewportFrame.Visible then
			self:_stopViewportRotation()
			return
		end

		local didRotate = ViewportModelRenderer.RotatePreview(viewportFrame, VIEWPORT_ROTATION_SPEED_RADIANS * deltaTime)
		if not didRotate then
			self:_stopViewportRotation()
		end
	end)
end

function CraftingController:_renderYieldViewport(recipe: any)
	local ui = self:_ensureUi()
	local viewportFrame = ui.viewportFrame
	if not viewportFrame then
		self:_stopViewportRotation()
		return
	end

	local _, _, model = getYieldInfo(recipe)
	if model and model:IsA("Model") then
		local rendered = ViewportModelRenderer.RenderCenteredBundle(viewportFrame, model)
		viewportFrame.Visible = rendered
		if rendered then
			self:_startViewportRotation(viewportFrame)
		else
			self:_stopViewportRotation()
		end
	else
		self:_stopViewportRotation()
		ViewportModelRenderer.Clear(viewportFrame)
		viewportFrame.Visible = false
	end
end

function CraftingController:_addRequirementRow(
	labelText: string,
	ownedAmount: number,
	requiredAmount: number,
	layoutOrder: number,
	setConfig: any?
)
	local ui = self:_ensureUi()
	local row = ui.requirementTemplate:Clone()
	row.Name = string.format("CraftingIngredient_%03d", layoutOrder)
	row.LayoutOrder = layoutOrder
	row.Visible = true

	local label = getFirstTextLabel(row, "MaterialName")
	if label then
		if setConfig then
			applySetRollDisplayStyle(label, setConfig)
		end
		label.Text = labelText
	end

	local countLabel = getFirstTextLabel(row, "MaterialCount")
	if countLabel then
		countLabel.Text = string.format("%s/%s", formatWholeNumber(ownedAmount), formatWholeNumber(requiredAmount))
	end

	row.Parent = ui.requirementList
end

function CraftingController:_syncRequirements(recipe: any, bodyPartCounts: { [string]: number })
	local ui = self:_ensureUi()
	hideGeneratedChildren(ui.requirementList, "CraftingIngredient_")
	hideNativeTemplates(ui.requirementList, ui.requirementTemplate)

	local layoutOrder = 1
	for _, ingredient in ipairs(if typeof(recipe.bodyParts) == "table" then recipe.bodyParts else {}) do
		local requiredAmount = math.max(1, math.floor(tonumber(ingredient.amount) or 1))
		self:_addRequirementRow(
			getBodyPartIngredientLabel(ingredient),
			bodyPartCounts[getBodyPartIngredientKey(ingredient)] or 0,
			requiredAmount,
			layoutOrder,
			getBodyPartIngredientSetConfig(ingredient)
		)
		layoutOrder += 1
	end

	local materialAmounts = self:_getMaterialAmounts()
	for _, ingredient in ipairs(if typeof(recipe.materials) == "table" then recipe.materials else {}) do
		local material = CraftingMaterialConfig.Get(ingredient.materialId)
		local requiredAmount = math.max(1, math.floor(tonumber(ingredient.amount) or 1))
		self:_addRequirementRow(
			if material then material.label else tostring(ingredient.materialId or "Material"),
			materialAmounts[ingredient.materialId] or 0,
			requiredAmount,
			layoutOrder,
			nil
		)
		layoutOrder += 1
	end
end

function CraftingController:_syncDetail()
	local ui = self:_ensureUi()
	local recipe = self:_findRecipe(self._selectedRecipeId)
	if not recipe then
		ui.itemName.Text = "Select a recipe"
		if ui.itemDescription then
			renderRecipeItemStatRows(ui.itemDescription, {})
		end
		self:_setCraftButtonText(nil)
		hideGeneratedChildren(ui.requirementList, "CraftingIngredient_")
		hideNativeTemplates(ui.requirementList, ui.requirementTemplate)
		if ui.viewportFrame then
			self:_stopViewportRotation()
			ViewportModelRenderer.Clear(ui.viewportFrame)
			ui.viewportFrame.Visible = false
		end
		self:_setCraftButtonEnabled(false)
		return
	end

	local yieldLabel = getYieldInfo(recipe)
	local canCraft, _, _, bodyPartCounts = self:_getCraftability(recipe)
	ui.itemName.Text = yieldLabel
	if ui.itemDescription then
		renderRecipeItemStatRows(ui.itemDescription, buildRecipeItemStatRows(recipe))
	end
	self:_setCraftButtonText(recipe)
	self:_syncRequirements(recipe, bodyPartCounts)
	self:_renderYieldViewport(recipe)
	self:_setCraftButtonEnabled(canCraft and not self._requestInFlight)
end

function CraftingController:_syncUi()
	self:_syncRecipeRows()
end

function CraftingController:_craftSelectedRecipe()
	if self._requestInFlight then
		return
	end
	if not self:_ensureRemotes() then
		showNotification("Crafting is not ready right now.")
		return
	end

	local recipe = self:_findRecipe(self._selectedRecipeId)
	local canCraft, reason, bodyPartOwnedIds = self:_getCraftability(recipe)
	if not canCraft then
		showNotification(reason)
		self:_syncDetail()
		return
	end

	self._requestInFlight = true
	self:_syncDetail()

	local result = self:_invokeRemote(self._remotes.craftRecipe, {
		recipeId = recipe.id,
		bodyPartOwnedIds = bodyPartOwnedIds,
	})

	self._requestInFlight = false

	if typeof(result) ~= "table" then
		showNotification("The craft could not be completed.")
		self:_requestCraftingState(false)
		self:_syncUi()
		return
	end

	self:_applyState(result.state)
	self._selectedRecipeId = recipe.id
	self:_syncUi()

	if result.ok == true then
		showNotification(tostring(result.message or "Crafted item."), "good")
	else
		showNotification(tostring(result.message or "The craft could not be completed."))
	end
end

function CraftingController:_openCraftingMenu(prompt: ProximityPrompt)
	local craftingModel = workspace:FindFirstChild("Crafting")
	if not craftingModel then
		showNotification("Crafting station is missing.")
		return
	end

	local cameraPart = craftingModel:FindFirstChild("CraftingCamera")
	if not (cameraPart and cameraPart:IsA("BasePart")) then
		cameraPart = nil
	end

	local craftsman = craftingModel:FindFirstChild("Craftsman")
	local speakerModel = if craftsman and craftsman:IsA("Model") then craftsman else nil

	MerchantPresentationController:Open(WINDOW_NAME, {
		cameraPart = cameraPart,
		sourceInstance = prompt,
		interactionType = "crafting",
		speakerModel = speakerModel,
		blurSize = 0,
		backdropTransparency = 0.9,
		crispContent = true,
	})
end

function CraftingController:_bindCraftingPrompt()
	if self._promptConnection then
		self._promptConnection:Disconnect()
		self._promptConnection = nil
	end

	task.spawn(function()
		local craftingModel = workspace:WaitForChild("Crafting", 30)
		if not craftingModel then
			Logger.Warn("[CraftingController] Workspace.Crafting was not found.")
			return
		end

		local craftsman = craftingModel:WaitForChild("Craftsman", 30)
		if not craftsman then
			Logger.Warn("[CraftingController] Workspace.Crafting.Craftsman was not found.")
			return
		end

		local prompt = craftsman:WaitForChild("Crafting", 30)
		if not (prompt and prompt:IsA("ProximityPrompt")) then
			Logger.Warn("[CraftingController] Workspace.Crafting.Craftsman.Crafting prompt was not found.")
			return
		end

		self._promptConnection = prompt.Triggered:Connect(function(triggeringPlayer: Player?)
			if triggeringPlayer ~= nil and triggeringPlayer ~= LOCAL_PLAYER then
				return
			end

			self:_openCraftingMenu(prompt)
		end)
	end)
end

function CraftingController:_handlePrepared(frameName: string)
	if frameName ~= WINDOW_NAME then
		return
	end

	self._isOpen = true
	self._requestInFlight = false
	self:_ensureUi()
	if not self:_requestCraftingState(true) then
		self._state = self._state or {
			recipes = CraftingRecipeConfig.GetAll(),
			craftingMaterials = {},
			ownedBodyParts = {},
			ownedAccessories = {},
			equippedAccessories = {},
			money = self:_getMoney(),
		}
	end
	self:_syncUi()
end

function CraftingController:_handleClosed(frameName: string)
	if frameName ~= WINDOW_NAME then
		return
	end

	self._isOpen = false
	self._requestInFlight = false
	self:_stopViewportRotation()
	if self._ui and self._ui.viewportFrame then
		ViewportModelRenderer.Clear(self._ui.viewportFrame)
		self._ui.viewportFrame.Visible = false
	end
end

function CraftingController:_refreshIfOpen(key: string?)
	if not self._isOpen then
		return
	end
	if key ~= nil
		and key ~= BODY_PARTS_DATA_KEY
		and key ~= EQUIPPED_LOADOUT_KEY
		and key ~= ACCESSORIES_DATA_KEY
		and key ~= EQUIPPED_ACCESSORIES_DATA_KEY
		and key ~= CRAFTING_MATERIALS_DATA_KEY
		and key ~= MONEY_DATA_KEY
	then
		return
	end

	self:_hydrateStateFromData(key)
	self:_syncUi()
end

function CraftingController:OnStart()
	if self._started then
		return
	end

	self._started = true
	self:_ensureUi()
	self:_ensureRemotes()
	self:_bindCraftingPrompt()

	MerchantPresentationController.FramePrepared:Connect(function(frameName: string)
		self:_handlePrepared(frameName)
	end)

	MerchantPresentationController.Closed:Connect(function(frameName: string)
		self:_handleClosed(frameName)
	end)

	DataController.DataReceived:Connect(function()
		self:_refreshIfOpen(nil)
	end)

	DataController.DataUpdated:Connect(function(key)
		self:_refreshIfOpen(key)
	end)

	self:_syncUi()
end

return CraftingController
