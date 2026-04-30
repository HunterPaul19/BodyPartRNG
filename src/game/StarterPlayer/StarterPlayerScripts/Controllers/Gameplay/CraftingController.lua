local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Schema = require(ReplicatedStorage.Lists.Schema)
local AccessoryConfig = require(ReplicatedStorage.Shared.Config.AccessoryConfig)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local CraftingMaterialConfig = require(ReplicatedStorage.Shared.Config.CraftingMaterialConfig)
local CraftingRecipeConfig = require(ReplicatedStorage.Shared.Config.CraftingRecipeConfig)
local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
local BossRewards = require(ReplicatedStorage.Shared.BossArena.BossRewards)
local CraftingProgress = require(ReplicatedStorage.Shared.Character.CraftingProgress)
local BodyPartLoadout = require(ReplicatedStorage.Shared.Character.BodyPartLoadout)
local OwnedAccessories = require(ReplicatedStorage.Shared.Character.OwnedAccessories)
local OwnedBodyParts = require(ReplicatedStorage.Shared.Character.OwnedBodyParts)
local AccessoryPresentation = require(ReplicatedStorage.Shared.UI.AccessoryPresentation)
local BodyPartPresentation = require(ReplicatedStorage.Shared.UI.BodyPartPresentation)
local Notify = require(ReplicatedStorage.Shared.UI.Notify)
local ViewportModelRenderer = require(ReplicatedStorage.Shared.UI.ViewportModelRenderer)

local DataController = require(script.Parent.DataController)
local MerchantPresentationController = require(script.Parent.MerchantPresentationController)
local ObjectiveGuideController = require(script.Parent.ObjectiveGuideController)
local UIController = require(script.Parent.UIController)

local LOCAL_PLAYER = Players.LocalPlayer
local WINDOW_NAME = "CraftingMenu"
local REMOTES_FOLDER_NAME = "Remotes"
local CRAFTING_FOLDER_NAME = "Crafting"
local GET_STATE_REMOTE_NAME = "GetCraftingState"
local CRAFT_RECIPE_REMOTE_NAME = "CraftRecipe"
local SET_AUTO_CRAFT_RECIPE_REMOTE_NAME = "SetAutoCraftRecipe"
local ADD_BODY_PART_INGREDIENT_REMOTE_NAME = "AddBodyPartIngredient"
local ADD_MATERIAL_INGREDIENT_REMOTE_NAME = "AddMaterialIngredient"
local ADD_ALL_ELIGIBLE_INGREDIENTS_REMOTE_NAME = "AddAllEligibleIngredients"
local BODY_PARTS_DATA_KEY = Schema.BodyParts and Schema.BodyParts.key or "bodyParts"
local EQUIPPED_LOADOUT_KEY = Schema.EquippedLoadout and Schema.EquippedLoadout.key or "equippedLoadout"
local ACCESSORIES_DATA_KEY = Schema.Accessories and Schema.Accessories.key or "accessories"
local EQUIPPED_ACCESSORIES_DATA_KEY = Schema.EquippedAccessories and Schema.EquippedAccessories.key or "equippedAccessories"
local CRAFTING_MATERIALS_DATA_KEY = Schema.CraftingMaterials and Schema.CraftingMaterials.key or "craftingMaterials"
local CRAFTING_PROGRESS_DATA_KEY = Schema.CraftingProgress and Schema.CraftingProgress.key or "craftingProgress"
local TUTORIAL_DATA_KEY = Schema.Tutorial and Schema.Tutorial.key or "tutorial"
local MONEY_DATA_KEY = Schema.Money and Schema.Money.key or "money"

local HEAD_FILTER = "HeadAccessory"
local GEAR_FILTER = "GearAccessory"
local SELECTED_ROW_TRANSPARENCY = 0
local DEFAULT_ROW_TRANSPARENCY = 0.16
local DISABLED_ROW_TRANSPARENCY = 0.45
local ENABLED_BUTTON_TEXT_TRANSPARENCY = 0
local DISABLED_BUTTON_TEXT_TRANSPARENCY = 0.35
local VIEWPORT_ROTATION_SPEED_RADIANS = math.rad(24)
local ITEM_STAT_ROW_PREFIX = "CraftingItemStat_"
local SELECT_PART_PREFIX = "CraftingSelectPart_"
local INGREDIENT_ROW_PREFIX = "CraftingIngredient_"
local BOSS_LOOT_MARKER_TEXT = "REQUIRES BOSS LOOT"
local ITEM_STAT_TEXT_REFERENCE_PARENT_HEIGHT = 295
local ITEM_STAT_TEXT_REFERENCE_SIZE = 15
local ITEM_STAT_MIN_TEXT_SIZE = 6
local ITEM_STAT_MAX_TEXT_SIZE = 18
local ITEM_STAT_ROW_PADDING_SCALE = 0.3
local ITEM_STAT_LAYOUT_PADDING_SCALE = 0.13
local AUTO_ON_COLOR = Color3.fromRGB(86, 220, 116)
local AUTO_OFF_COLOR = Color3.fromRGB(255, 255, 255)
local SELECT_PART_SELECTED_OUTLINE_COLOR = Color3.fromRGB(116, 192, 255)
local SELECT_PART_DEFAULT_OUTLINE_COLOR = Color3.fromRGB(255, 255, 255)
local SELECT_PART_SELECTED_OUTLINE_TRANSPARENCY = 0
local SELECT_PART_DEFAULT_OUTLINE_TRANSPARENCY = 0.51
local SELECT_PART_FALLBACK_STROKE_NAME = "CraftingSelectedOutline"
local AUTO_CRAFT_BACKGROUND_NAMES = {
	Cover = true,
	Cover2 = true,
}
local HELP_MENU_CLOSE_INPUT_TYPES = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.Touch] = true,
}

type CraftingRemotes = {
	getState: RemoteFunction,
	craftRecipe: RemoteFunction,
	setAutoCraftRecipe: RemoteFunction,
	addBodyPartIngredient: RemoteFunction,
	addMaterialIngredient: RemoteFunction,
	addAllEligibleIngredients: RemoteFunction,
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
	openRecipeButton: GuiButton?,
	autoCraftButton: GuiButton?,
	autoCraftLabel: TextLabel?,
	autoCraftUsage: TextLabel?,
	accessoriesFilterButton: GuiButton?,
	gearsFilterButton: GuiButton?,
	ingredientSelect: GuiObject?,
	ingredientMain: GuiObject?,
	ingredientList: ScrollingFrame?,
	bodyPartIngredientTemplate: GuiObject?,
	materialIngredientTemplate: GuiObject?,
	ingredientCraftButton: GuiButton?,
	ingredientCraftButtonLabel: TextLabel?,
	addEverythingButton: GuiButton?,
	ingredientCloseButton: GuiButton?,
	confirmationFrame: GuiObject?,
	confirmationCancelButton: GuiButton?,
	confirmationConfirmButton: GuiButton?,
	selectPartsFrame: GuiObject?,
	selectPartsList: ScrollingFrame?,
	selectPartsTemplate: GuiObject?,
	selectPartsConfirmButton: GuiButton?,
	selectPartsCancelButton: GuiButton?,
	selectPartsCloseButton: GuiButton?,
	helpButton: GuiButton?,
	helpMenu: GuiObject?,
	helpCloseButton: GuiButton?,
	menuCloseButton: GuiButton?,
	storeButton: GuiButton?,
}

local CraftingController = {
	_started = false,
	_isOpen = false,
	_requestInFlight = false,
	_promptConnection = nil :: RBXScriptConnection?,
	_searchConnection = nil :: RBXScriptConnection?,
	_itemDescriptionSizeConnection = nil :: RBXScriptConnection?,
	_viewportRotationConnection = nil :: RBXScriptConnection?,
	_helpMenuCloseConnection = nil :: RBXScriptConnection?,
	_ui = nil :: CraftingUi?,
	_remotes = nil :: CraftingRemotes?,
	_state = nil :: any,
	_selectedRecipeId = nil :: string?,
	_selectedFilterSlot = HEAD_FILTER,
	_recipeRowsById = {} :: { [string]: ImageButton },
	_selectingIngredientKey = nil :: string?,
	_selectedPartIds = {} :: { [string]: boolean },
	_selectedPartOrder = {} :: { string },
	_maxSelectedParts = 0,
	_selectPartCardsByOwnedId = {} :: { [string]: any },
	_materialAmountDrafts = {} :: { [string]: string },
	_focusedMaterialAmountDraftKey = nil :: string?,
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

local function getFirstTextLabel(root: Instance, name: string): TextLabel?
	local label = root:FindFirstChild(name, true)
	return if label and label:IsA("TextLabel") then label else nil
end

local function getFirstTextBox(root: Instance, name: string): TextBox?
	local textBox = root:FindFirstChild(name, true)
	return if textBox and textBox:IsA("TextBox") then textBox else nil
end

local function hideGeneratedChildren(container: Instance, prefix: string)
	for _, child in ipairs(container:GetChildren()) do
		if string.find(child.Name, prefix, 1, true) == 1 then
			child:Destroy()
		end
	end
end

local function hideNativeTemplates(container: Instance, template: GuiObject?)
	if not template then
		return
	end

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

local function setGuiButtonEnabled(button: GuiButton?, enabled: boolean)
	if not button then
		return
	end

	button.Active = enabled
	button.Selectable = enabled
	button.AutoButtonColor = false

	local label = button:FindFirstChildWhichIsA("TextLabel")
	if label then
		label.TextTransparency = if enabled then ENABLED_BUTTON_TEXT_TRANSPARENCY else DISABLED_BUTTON_TEXT_TRANSPARENCY
	end

	for _, child in ipairs(button:GetChildren()) do
		if child:IsA("ImageLabel") then
			if child.Name == "Rays" then
				child.ImageTransparency = if enabled then 0 else 0.45
			else
				child.ImageTransparency = if enabled then 0 else 0.28
			end
		end
	end
end

local function setAutoCraftButtonColor(button: GuiButton?, enabled: boolean)
	if not button then
		return
	end

	local color = if enabled then AUTO_ON_COLOR else AUTO_OFF_COLOR
	if button:IsA("ImageButton") then
		button.ImageColor3 = color
	elseif button:IsA("TextButton") then
		button.BackgroundColor3 = color
	end

	for _, descendant in ipairs(button:GetDescendants()) do
		if AUTO_CRAFT_BACKGROUND_NAMES[descendant.Name] then
			if descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
				descendant.ImageColor3 = color
			elseif descendant:IsA("Frame") then
				descendant.BackgroundColor3 = color
			end
		end
	end
end

local function parsePositiveWholeAmount(text: string?): number
	local normalized = tostring(text or ""):match("^%s*(.-)%s*$")
	local parsed = tonumber(normalized)
	if not parsed or parsed < 1 then
		return 1
	end
	return math.max(1, math.floor(parsed))
end

local function clampMaterialAmountText(text: string?, maxAmount: number): string
	if maxAmount <= 0 then
		return "0"
	end

	return tostring(math.min(parsePositiveWholeAmount(text), maxAmount))
end

local function getMaterialAmountDraftKey(recipeId: string, materialId: string): string
	return string.format("%s:%s", recipeId, materialId)
end

local function removeFirstValue(values: { string }, value: string)
	for index, existingValue in ipairs(values) do
		if existingValue == value then
			table.remove(values, index)
			return
		end
	end
end

local function applySelectPartOutline(button: GuiButton, isSelected: boolean)
	local outline = button:FindFirstChild("Outline")
	if outline and outline:IsA("ImageLabel") then
		outline.Visible = true
		outline.ImageColor3 = if isSelected then SELECT_PART_SELECTED_OUTLINE_COLOR else SELECT_PART_DEFAULT_OUTLINE_COLOR
		outline.ImageTransparency = if isSelected
			then SELECT_PART_SELECTED_OUTLINE_TRANSPARENCY
			else SELECT_PART_DEFAULT_OUTLINE_TRANSPARENCY
		outline.ZIndex = math.max(outline.ZIndex, button.ZIndex + 3)
		return
	end

	local stroke = button:FindFirstChild(SELECT_PART_FALLBACK_STROKE_NAME)
	if not (stroke and stroke:IsA("UIStroke")) then
		stroke = Instance.new("UIStroke")
		stroke.Name = SELECT_PART_FALLBACK_STROKE_NAME
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = button
	end
	stroke.Color = SELECT_PART_SELECTED_OUTLINE_COLOR
	stroke.Thickness = 3
	stroke.Transparency = if isSelected then 0 else 1
	stroke.Enabled = isSelected
end

local cachedBossLootSetIds = nil :: { [string]: boolean }?
local cachedBossLootMaterialIds = nil :: { [string]: boolean }?

local function getBossLootLookups(): ({ [string]: boolean }, { [string]: boolean })
	if cachedBossLootSetIds and cachedBossLootMaterialIds then
		return cachedBossLootSetIds, cachedBossLootMaterialIds
	end

	local setIds = {}
	local materialIds = {}
	for _, profile in ipairs(BossRewards.GetAllBossRewardProfiles()) do
		if typeof(profile) == "table" then
			if typeof(profile.bossSetId) == "string" and profile.bossSetId ~= "" then
				setIds[profile.bossSetId] = true
			end

			if typeof(profile.bossId) == "string" and profile.bossId ~= "" then
				for _, drop in ipairs(BossRewards.GetBossMaterialDrops(profile.bossId)) do
					if typeof(drop) == "table" and typeof(drop.materialId) == "string" and drop.materialId ~= "" then
						materialIds[drop.materialId] = true
					end
				end
			end
		end
	end

	cachedBossLootSetIds = table.freeze(setIds)
	cachedBossLootMaterialIds = table.freeze(materialIds)
	return cachedBossLootSetIds, cachedBossLootMaterialIds
end

local function recipeRequiresBossLoot(recipe: any): boolean
	if typeof(recipe) ~= "table" then
		return false
	end

	local bossSetIds, bossMaterialIds = getBossLootLookups()
	for _, ingredient in ipairs(if typeof(recipe.bodyParts) == "table" then recipe.bodyParts else {}) do
		if typeof(ingredient) == "table" then
			if typeof(ingredient.setId) == "string" and bossSetIds[ingredient.setId] == true then
				return true
			end

			if typeof(ingredient.pieceId) == "string" then
				local piece = BodyPartsCatalog.GetPiece(ingredient.pieceId)
				if piece and bossSetIds[piece.setId] == true then
					return true
				end
			end
		end
	end

	for _, ingredient in ipairs(if typeof(recipe.materials) == "table" then recipe.materials else {}) do
		if
			typeof(ingredient) == "table"
			and typeof(ingredient.materialId) == "string"
			and bossMaterialIds[ingredient.materialId] == true
		then
			return true
		end
	end

	return false
end

local function escapeRichText(value: string): string
	return (string.gsub(string.gsub(string.gsub(value, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

local function formatRecipeDescription(recipe: any, richText: boolean?): string
	local description = tostring(if typeof(recipe) == "table" then recipe.description or "" else "")
	if not recipeRequiresBossLoot(recipe) then
		return if richText then escapeRichText(description) else description
	end

	local markerText = if richText then string.format("<i>%s</i>", BOSS_LOOT_MARKER_TEXT) else BOSS_LOOT_MARKER_TEXT
	if description == "" then
		return markerText
	end

	return string.format("%s\n%s", if richText then escapeRichText(description) else description, markerText)
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

local function clearRecipeItemStatRows(container: TextLabel)
	container.Text = ""
	hideGeneratedChildren(container, ITEM_STAT_ROW_PREFIX)
end

local function getGuiParentHeight(container: TextLabel): number
	local parent = container.Parent
	if parent and parent:IsA("GuiObject") and parent.AbsoluteSize.Y > 0 then
		return parent.AbsoluteSize.Y
	end

	if container.Size.Y.Scale > 0 and container.AbsoluteSize.Y > 0 then
		return container.AbsoluteSize.Y / container.Size.Y.Scale
	end

	return container.AbsoluteSize.Y
end

local function getRecipeItemStatContainerHeight(container: TextLabel): number
	if container.AbsoluteSize.Y > 0 then
		return container.AbsoluteSize.Y
	end

	return getGuiParentHeight(container) * math.max(container.Size.Y.Scale, 0)
end

local function getRecipeItemStatTextSize(container: TextLabel, rowHeight: number): number
	local parentHeight = getGuiParentHeight(container)
	local fallbackTextSize = math.clamp(container.TextSize + 1, ITEM_STAT_MIN_TEXT_SIZE, ITEM_STAT_MAX_TEXT_SIZE)
	if parentHeight <= 0 then
		return math.min(fallbackTextSize, math.max(rowHeight, 1))
	end

	local textSize = parentHeight * (ITEM_STAT_TEXT_REFERENCE_SIZE / ITEM_STAT_TEXT_REFERENCE_PARENT_HEIGHT)
	local fitTextSize = rowHeight / (1 + ITEM_STAT_ROW_PADDING_SCALE)
	local resolvedTextSize = math.min(textSize, fitTextSize)
	return math.clamp(math.floor(resolvedTextSize + 0.5), ITEM_STAT_MIN_TEXT_SIZE, ITEM_STAT_MAX_TEXT_SIZE)
end

local function renderRecipeItemStatRows(container: TextLabel, rows: { any })
	clearRecipeItemStatRows(container)
	container.ClipsDescendants = true
	local layout = ensureItemStatLayout(container)

	local rowCount = #rows
	if rowCount <= 0 then
		layout.Padding = UDim.new(0, 0)
		return
	end

	local containerHeight = getRecipeItemStatContainerHeight(container)
	local layoutPadding = if rowCount > 1
		then math.max(0, math.floor((math.min(containerHeight / rowCount, ITEM_STAT_TEXT_REFERENCE_SIZE) * ITEM_STAT_LAYOUT_PADDING_SCALE) + 0.5))
		else 0
	local totalPadding = layoutPadding * math.max(rowCount - 1, 0)
	local rowHeight = math.max(1, math.floor((math.max(containerHeight - totalPadding, rowCount)) / rowCount))
	local statTextSize = getRecipeItemStatTextSize(container, rowHeight)
	layout.Padding = UDim.new(0, layoutPadding)

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
		statLabel.BackgroundTransparency = 1
		statLabel.BorderSizePixel = 0
		statLabel.FontFace = container.FontFace
		statLabel.RichText = rowData.richText == true
		statLabel.Position = UDim2.fromOffset(0, 0)
		statLabel.Size = UDim2.new(1, 0, 1, 0)
		statLabel.Text = if typeof(rowData.text) == "string"
			then rowData.text
			else string.format("%s %s", rowData.valueText, rowData.labelText)
		statLabel.TextColor3 = rowData.color or container.TextColor3
		statLabel.TextSize = statTextSize
		statLabel.TextTransparency = container.TextTransparency
		statLabel.TextTruncate = Enum.TextTruncate.AtEnd
		statLabel.TextWrapped = false
		statLabel.TextXAlignment = Enum.TextXAlignment.Left
		statLabel.TextYAlignment = Enum.TextYAlignment.Center
		statLabel.Parent = row
	end
end

local function buildRecipeItemStatRows(recipe: any): { any }
	local recipeYield = if typeof(recipe) == "table" then recipe.yield else nil
	if typeof(recipeYield) ~= "table" or recipeYield.kind ~= "accessory" then
		return {}
	end

	return AccessoryPresentation.BuildStatRows(recipeYield.accessoryId)
end

local function getRecipeCardColor(recipe: any): Color3?
	local recipeYield = if typeof(recipe) == "table" then recipe.yield else nil
	if typeof(recipeYield) ~= "table" or recipeYield.kind ~= "accessory" then
		return nil
	end

	local config = AccessoryConfig.Get(recipeYield.accessoryId)
	if not config then
		return nil
	end

	return config.recipeCardColor or config.displayColor
end

local function applyRecipeRowColor(row: ImageButton, color: Color3?)
	if not color then
		return
	end

	row.ImageColor3 = color
	for _, descendant in ipairs(row:GetDescendants()) do
		if descendant.Name == "Cover" or descendant.Name == "Cover2" or descendant.Name == "Rays" then
			if descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
				descendant.ImageColor3 = color
			elseif descendant:IsA("GuiObject") then
				descendant.BackgroundColor3 = color
			end
		end
	end
end

local PERCENT_DELTA_BONUS_KEYS = table.freeze({
	"luckBonus",
	"rollSpeedBonus",
})

local PERCENT_MULTIPLIER_BONUS_KEYS = table.freeze({
	"luckMultiplier",
	"passiveIncomeMultiplier",
	"damageMultiplier",
	"healthMultiplier",
	"speedMultiplier",
})

local function getRecipeAccessoryConfig(recipe: any): AccessoryConfig.AccessoryConfigEntry?
	local recipeYield = if typeof(recipe) == "table" then recipe.yield else nil
	if typeof(recipeYield) ~= "table" or recipeYield.kind ~= "accessory" then
		return nil
	end

	return AccessoryConfig.Get(recipeYield.accessoryId)
end

local function addPositiveScore(score: number, value: any): number
	local numericValue = tonumber(value)
	if not numericValue or numericValue <= 0 then
		return score
	end

	return score + numericValue
end

local function getAccessoryStatScore(config: AccessoryConfig.AccessoryConfigEntry?): number?
	local bonuses = if config and typeof(config.bonuses) == "table" then config.bonuses else nil
	if not bonuses then
		return nil
	end

	local score = 0
	for _, key in ipairs(PERCENT_DELTA_BONUS_KEYS) do
		score = addPositiveScore(score, (tonumber(bonuses[key]) or 0) * 100)
	end
	for _, key in ipairs(PERCENT_MULTIPLIER_BONUS_KEYS) do
		local value = tonumber(bonuses[key])
		if value and value > 1 then
			score += (value - 1) * 100
		end
	end

	return score
end

local function getRecipeAccessoryStatScore(recipe: any): number?
	return getAccessoryStatScore(getRecipeAccessoryConfig(recipe))
end

local function getRecipeAccessorySellPrice(recipe: any): number
	local config = getRecipeAccessoryConfig(recipe)
	return math.max(0, math.floor(tonumber(config and config.sellPrice) or 0))
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
		local leftScore = getRecipeAccessoryStatScore(left)
		local rightScore = getRecipeAccessoryStatScore(right)
		if leftScore ~= nil and rightScore ~= nil then
			if leftScore ~= rightScore then
				return leftScore < rightScore
			end

			local leftSellPrice = getRecipeAccessorySellPrice(left)
			local rightSellPrice = getRecipeAccessorySellPrice(right)
			if leftSellPrice ~= rightSellPrice then
				return leftSellPrice < rightSellPrice
			end
		end

		local leftOrder = math.floor(tonumber(left.sortOrder) or 0)
		local rightOrder = math.floor(tonumber(right.sortOrder) or 0)
		if leftOrder ~= rightOrder then
			return leftOrder < rightOrder
		end
		return tostring(left.id) < tostring(right.id)
	end)

	return results
end

local function getYieldInfo(recipe: any): (string, string, Model?, string?)
	local recipeYield = if typeof(recipe) == "table" then recipe.yield else nil
	if typeof(recipeYield) ~= "table" then
		return tostring(recipe and recipe.label or "Recipe"), "[Recipe]", nil, nil
	end

	if recipeYield.kind == "accessory" then
		local config = AccessoryConfig.Get(recipeYield.accessoryId)
		if not config then
			return tostring(recipe.label or recipe.id or "Accessory"), "[Accessory]", nil, nil
		end

		local slotText = if config.slot == HEAD_FILTER then "[Head]" else "[Gear]"
		return config.label, slotText, AccessoryPresentation.GetPlaceholderModel(config), config.slot
	end

	if recipeYield.kind == "bodyPart" and typeof(recipeYield.bodyPartGrant) == "table" then
		local piece = BodyPartsCatalog.GetPiece(recipeYield.bodyPartGrant.pieceId)
		if not piece then
			return tostring(recipe.label or recipe.id or "Body Part"), "[Body Part]", nil, nil
		end

		return piece.displayName, "[Body Part]", BodyPartsCatalog.ResolveBundleModel(piece.id), nil
	end

	return tostring(recipe.label or recipe.id or "Recipe"), "[Recipe]", nil, nil
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

local function sortBodyPartIngredients(left: any, right: any): boolean
	local leftRarity = math.max(1, tonumber(left and left.rarityDenominator) or math.huge)
	local rightRarity = math.max(1, tonumber(right and right.rarityDenominator) or math.huge)
	if leftRarity ~= rightRarity then
		return leftRarity < rightRarity
	end
	local leftIncome = math.max(0, tonumber(left and left.finalPassiveIncomePerSecond) or 0)
	local rightIncome = math.max(0, tonumber(right and right.finalPassiveIncomePerSecond) or 0)
	if leftIncome ~= rightIncome then
		return leftIncome < rightIncome
	end
	return tostring(left and left.ownedId or "") < tostring(right and right.ownedId or "")
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

local function getRecordPassiveIncome(record: any, piece: any): number
	return math.max(0, tonumber(record and record.finalPassiveIncomePerSecond) or tonumber(piece and piece.passiveIncomePerSecond) or 0)
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

function CraftingController:_getCraftingProgress()
	local state = self._state
	if typeof(state) == "table" and typeof(state.craftingProgress) == "table" then
		return CraftingProgress.NormalizeState(state.craftingProgress)
	end

	return CraftingProgress.NormalizeState(DataController:Get(CRAFTING_PROGRESS_DATA_KEY))
end

function CraftingController:_getRecipeProgress(recipeId: string)
	return CraftingProgress.GetRecipeProgress(self:_getCraftingProgress(), recipeId)
end

function CraftingController:_shouldWaiveTutorialCraftCost(recipe: any): boolean
	if typeof(recipe) ~= "table" or recipe.id ~= TutorialConfig.TargetRecipeId then
		return false
	end

	local tutorialState = DataController:Get(TUTORIAL_DATA_KEY)
	return typeof(tutorialState) == "table"
		and tutorialState.completed ~= true
		and tutorialState.stepId == TutorialConfig.Steps.CraftHolidayCrown
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

function CraftingController:_findBodyPartIngredient(recipe: any, ingredientKey: string?): any?
	if typeof(recipe) ~= "table" or typeof(ingredientKey) ~= "string" then
		return nil
	end

	for _, ingredient in ipairs(if typeof(recipe.bodyParts) == "table" then recipe.bodyParts else {}) do
		if CraftingProgress.GetBodyPartIngredientKey(ingredient) == ingredientKey then
			return ingredient
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

function CraftingController:_getCraftability(recipe: any): (boolean, string)
	if typeof(recipe) ~= "table" then
		return false, "Select a recipe."
	end

	local recipeProgress = self:_getRecipeProgress(recipe.id)
	for _, ingredient in ipairs(if typeof(recipe.bodyParts) == "table" then recipe.bodyParts else {}) do
		local ingredientKey = CraftingProgress.GetBodyPartIngredientKey(ingredient)
		local requiredAmount = math.max(1, math.floor(tonumber(ingredient.amount) or 1))
		if (recipeProgress.bodyPartsByIngredientKey[ingredientKey] or 0) < requiredAmount then
			return false, "Missing body part ingredients."
		end
	end

	for _, ingredient in ipairs(if typeof(recipe.materials) == "table" then recipe.materials else {}) do
		local materialId = tostring(ingredient.materialId or "")
		local requiredAmount = math.max(1, math.floor(tonumber(ingredient.amount) or 1))
		if (recipeProgress.materialsByMaterialId[materialId] or 0) < requiredAmount then
			return false, "Missing crafting materials."
		end
	end

	local moneyCost = if self:_shouldWaiveTutorialCraftCost(recipe)
		then 0
		else math.max(0, math.floor(tonumber(recipe.moneyCost) or 0))
	if self:_getMoney() < moneyCost then
		return false, "Not enough money."
	end

	local recipeYield = recipe.yield
	if typeof(recipeYield) ~= "table" then
		return false, "Recipe yield is invalid."
	end

	if recipeYield.kind == "accessory" then
		if not AccessoryConfig.Get(recipeYield.accessoryId) then
			return false, "Recipe yield is invalid."
		end
		if countDictionary(self:_getOwnedAccessories()) >= OwnedAccessories.MAX_OWNED_COUNT then
			return false, "Accessory inventory is full."
		end
	elseif recipeYield.kind == "bodyPart" then
		if countDictionary(self:_getOwnedBodyParts()) + 1 > OwnedBodyParts.MAX_OWNED_COUNT then
			return false, "Body part inventory is full."
		end
	else
		return false, "Recipe yield is invalid."
	end

	return true, "Ready to craft."
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
	local itemSelectTopbar = itemSelect:FindFirstChild("Topbar")
	local menuCloseButton = if itemSelectTopbar then itemSelectTopbar:FindFirstChild("CloseButton") else nil

	local searchBar = itemSelect:FindFirstChild("SearchBar")
	local searchBox = if searchBar then searchBar:FindFirstChild("TextBox") else nil
	local recipeList = itemSelect:WaitForChild("ScrollingFrame", 30)
	assert(recipeList and recipeList:IsA("ScrollingFrame"), "CraftingMenu.ItemSelect.ScrollingFrame is missing.")

	local recipeTemplate = recipeList:FindFirstChild("Template")
	assert(recipeTemplate and recipeTemplate:IsA("ImageButton"), "CraftingMenu.ItemSelect.ScrollingFrame.Template is missing.")

	local sortButtons = itemSelect:FindFirstChild("SortButtons")
	local accessoriesFilterButton = sortButtons and sortButtons:FindFirstChild("Accessories")
	local gearsFilterButton = sortButtons and sortButtons:FindFirstChild("Gears")

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

	local ingredientSelect = root:FindFirstChild("IngredientSelect")
	local ingredientMain = ingredientSelect and ingredientSelect:FindFirstChild("Main")
	local ingredientList = ingredientMain and ingredientMain:FindFirstChild("ScrollingFrame")
	local bodyPartIngredientTemplate = ingredientList and ingredientList:FindFirstChild("Basic")
	local materialIngredientTemplate = ingredientList and ingredientList:FindFirstChild("Clean")
	local ingredientCraftButton = ingredientMain and ingredientMain:FindFirstChild("CraftButton")
	local addEverythingButton = ingredientMain and ingredientMain:FindFirstChild("AddEverythingButton")
	local ingredientTopbar = ingredientMain and ingredientMain:FindFirstChild("Topbar")
	local ingredientCloseButton = ingredientTopbar and ingredientTopbar:FindFirstChild("CloseButton")
	local confirmationFrame = ingredientSelect and ingredientSelect:FindFirstChild("Confirmation")
	local confirmationCancelButton = confirmationFrame and confirmationFrame:FindFirstChild("AddEverythingButton")
	local confirmationConfirmButton = confirmationFrame and confirmationFrame:FindFirstChild("CraftButton")
	local selectPartsFrame = ingredientSelect and ingredientSelect:FindFirstChild("SelectParts")
	local selectPartsList = selectPartsFrame and selectPartsFrame:FindFirstChild("ScrollingFrame")
	local selectPartsTemplate = selectPartsList and selectPartsList:FindFirstChild("Template")
	local selectPartsConfirmButton = selectPartsFrame and selectPartsFrame:FindFirstChild("ConfirmButton")
	local selectPartsCancelButton = selectPartsFrame and selectPartsFrame:FindFirstChild("CancelButton")
	local selectPartsTopbar = selectPartsFrame and selectPartsFrame:FindFirstChild("Topbar")
	local selectPartsCloseButton = selectPartsTopbar and selectPartsTopbar:FindFirstChild("CloseButton")
	local helpButton = root:FindFirstChild("HelpButton") or root:FindFirstChild("HelpButton", true)
	local helpMenu = root:FindFirstChild("HelpMenu")
	local helpTopbar = helpMenu and helpMenu:FindFirstChild("Topbar")
	local helpCloseButton = if helpTopbar then helpTopbar:FindFirstChild("CloseButton") else nil
	if not helpCloseButton and helpMenu then
		helpCloseButton = helpMenu:FindFirstChild("CloseButton", true)
	end

	local openRecipeButton = recipeRoot:FindFirstChild("OpenRecipe")
	local autoCraftButton = recipeRoot:FindFirstChild("AutoCraft")
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
		openRecipeButton = if openRecipeButton and openRecipeButton:IsA("GuiButton") then openRecipeButton else nil,
		autoCraftButton = if autoCraftButton and autoCraftButton:IsA("GuiButton") then autoCraftButton else nil,
		autoCraftLabel = if autoCraftButton then autoCraftButton:FindFirstChildWhichIsA("TextLabel") else nil,
		autoCraftUsage = if autoCraftButton then getFirstTextLabel(autoCraftButton, "Usage") else nil,
		accessoriesFilterButton = if accessoriesFilterButton and accessoriesFilterButton:IsA("GuiButton")
			then accessoriesFilterButton
			else nil,
		gearsFilterButton = if gearsFilterButton and gearsFilterButton:IsA("GuiButton") then gearsFilterButton else nil,
		ingredientSelect = if ingredientSelect and ingredientSelect:IsA("GuiObject") then ingredientSelect else nil,
		ingredientMain = if ingredientMain and ingredientMain:IsA("GuiObject") then ingredientMain else nil,
		ingredientList = if ingredientList and ingredientList:IsA("ScrollingFrame") then ingredientList else nil,
		bodyPartIngredientTemplate = if bodyPartIngredientTemplate and bodyPartIngredientTemplate:IsA("GuiObject")
			then bodyPartIngredientTemplate
			else nil,
		materialIngredientTemplate = if materialIngredientTemplate and materialIngredientTemplate:IsA("GuiObject")
			then materialIngredientTemplate
			else nil,
		ingredientCraftButton = if ingredientCraftButton and ingredientCraftButton:IsA("GuiButton") then ingredientCraftButton else nil,
		ingredientCraftButtonLabel = if ingredientCraftButton then ingredientCraftButton:FindFirstChildWhichIsA("TextLabel") else nil,
		addEverythingButton = if addEverythingButton and addEverythingButton:IsA("GuiButton") then addEverythingButton else nil,
		ingredientCloseButton = if ingredientCloseButton and ingredientCloseButton:IsA("GuiButton") then ingredientCloseButton else nil,
		confirmationFrame = if confirmationFrame and confirmationFrame:IsA("GuiObject") then confirmationFrame else nil,
		confirmationCancelButton = if confirmationCancelButton and confirmationCancelButton:IsA("GuiButton")
			then confirmationCancelButton
			else nil,
		confirmationConfirmButton = if confirmationConfirmButton and confirmationConfirmButton:IsA("GuiButton")
			then confirmationConfirmButton
			else nil,
		selectPartsFrame = if selectPartsFrame and selectPartsFrame:IsA("GuiObject") then selectPartsFrame else nil,
		selectPartsList = if selectPartsList and selectPartsList:IsA("ScrollingFrame") then selectPartsList else nil,
		selectPartsTemplate = if selectPartsTemplate and selectPartsTemplate:IsA("GuiObject") then selectPartsTemplate else nil,
		selectPartsConfirmButton = if selectPartsConfirmButton and selectPartsConfirmButton:IsA("GuiButton")
			then selectPartsConfirmButton
			else nil,
		selectPartsCancelButton = if selectPartsCancelButton and selectPartsCancelButton:IsA("GuiButton")
			then selectPartsCancelButton
			else nil,
		selectPartsCloseButton = if selectPartsCloseButton and selectPartsCloseButton:IsA("GuiButton")
			then selectPartsCloseButton
			else nil,
		helpButton = if helpButton and helpButton:IsA("GuiButton") then helpButton else nil,
		helpMenu = if helpMenu and helpMenu:IsA("GuiObject") then helpMenu else nil,
		helpCloseButton = if helpCloseButton and helpCloseButton:IsA("GuiButton") then helpCloseButton else nil,
		menuCloseButton = if menuCloseButton and menuCloseButton:IsA("GuiButton") then menuCloseButton else nil,
		storeButton = if storeButton and storeButton:IsA("GuiButton") then storeButton else nil,
	}

	hideNativeTemplates(recipeList, recipeTemplate)
	hideNativeTemplates(requirementList, requirementTemplate)
	hideNativeTemplates(self._ui.ingredientList or recipeList, self._ui.bodyPartIngredientTemplate)
	hideNativeTemplates(self._ui.ingredientList or recipeList, self._ui.materialIngredientTemplate)
	hideNativeTemplates(self._ui.selectPartsList or recipeList, self._ui.selectPartsTemplate)
	self:_hideIngredientPanels()

	if self._ui.itemDescription then
		self._ui.itemDescription.RichText = false
		self._ui.itemDescription.TextXAlignment = Enum.TextXAlignment.Left
		self._ui.itemDescription.TextYAlignment = Enum.TextYAlignment.Top
		renderRecipeItemStatRows(self._ui.itemDescription, {})
	end
	self:_bindItemDescriptionSizeRefresh()

	if self._ui.storeButton then
		self._ui.storeButton.Visible = false
		self._ui.storeButton.Active = false
	end

	if self._ui.openRecipeButton then
		UIController:CreateButton(self._ui.openRecipeButton, function()
			self:_openIngredientSelect()
		end)
	end
	if self._ui.autoCraftButton then
		UIController:CreateButton(self._ui.autoCraftButton, function()
			self:_toggleAutoCraftSelectedRecipe()
		end)
	end
	if self._ui.ingredientCraftButton then
		UIController:CreateButton(self._ui.ingredientCraftButton, function()
			self:_craftSelectedRecipe()
		end)
	end
	if self._ui.addEverythingButton then
		UIController:CreateButton(self._ui.addEverythingButton, function()
			self:_showAddEverythingConfirmation()
		end)
	end
	if self._ui.helpButton then
		UIController:CreateButton(self._ui.helpButton, function()
			self:_showHelpMenu()
		end)
	end
	if self._ui.helpCloseButton then
		UIController:CreateButton(self._ui.helpCloseButton, function()
			self:_hideHelpMenu()
		end)
	end
	if self._ui.ingredientCloseButton then
		UIController:CreateButton(self._ui.ingredientCloseButton, function()
			self:_hideIngredientPanels()
		end)
	end
	if self._ui.confirmationCancelButton then
		UIController:CreateButton(self._ui.confirmationCancelButton, function()
			self:_hideConfirmation()
		end)
	end
	if self._ui.confirmationConfirmButton then
		UIController:CreateButton(self._ui.confirmationConfirmButton, function()
			self:_confirmAddEverything()
		end)
	end
	if self._ui.selectPartsCancelButton then
		UIController:CreateButton(self._ui.selectPartsCancelButton, function()
			self:_hideSelectParts()
		end)
	end
	if self._ui.selectPartsCloseButton then
		UIController:CreateButton(self._ui.selectPartsCloseButton, function()
			self:_hideSelectParts()
		end)
	end
	if self._ui.selectPartsConfirmButton then
		UIController:CreateButton(self._ui.selectPartsConfirmButton, function()
			self:_confirmSelectedParts()
		end)
	end
	if self._ui.accessoriesFilterButton then
		UIController:CreateButton(self._ui.accessoriesFilterButton, function()
			self:_setRecipeFilter(HEAD_FILTER)
		end)
	end
	if self._ui.gearsFilterButton then
		UIController:CreateButton(self._ui.gearsFilterButton, function()
			self:_setRecipeFilter(GEAR_FILTER)
		end)
	end

	if self._ui.searchBox then
		self._searchConnection = self._ui.searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			if self._isOpen then
				self:_syncRecipeRows()
			end
		end)
	end

	return self._ui
end

function CraftingController:_bindItemDescriptionSizeRefresh()
	if self._itemDescriptionSizeConnection then
		self._itemDescriptionSizeConnection:Disconnect()
		self._itemDescriptionSizeConnection = nil
	end

	local ui = self._ui
	local itemDescription = ui and ui.itemDescription
	if not itemDescription then
		return
	end

	self._itemDescriptionSizeConnection = itemDescription:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if self._isOpen then
			self:_syncDetail()
		end
	end)
end

function CraftingController:_ensureRemotes(): boolean
	if self._remotes
		and self._remotes.getState
		and self._remotes.craftRecipe
		and self._remotes.setAutoCraftRecipe
		and self._remotes.addBodyPartIngredient
		and self._remotes.addMaterialIngredient
		and self._remotes.addAllEligibleIngredients
	then
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
	local setAutoCraftRecipe = craftingFolder:FindFirstChild(SET_AUTO_CRAFT_RECIPE_REMOTE_NAME)
	local addBodyPartIngredient = craftingFolder:FindFirstChild(ADD_BODY_PART_INGREDIENT_REMOTE_NAME)
	local addMaterialIngredient = craftingFolder:FindFirstChild(ADD_MATERIAL_INGREDIENT_REMOTE_NAME)
	local addAllEligibleIngredients = craftingFolder:FindFirstChild(ADD_ALL_ELIGIBLE_INGREDIENTS_REMOTE_NAME)
	if not (getState and getState:IsA("RemoteFunction")) then
		return false
	end
	if not (craftRecipe and craftRecipe:IsA("RemoteFunction")) then
		return false
	end
	if not (setAutoCraftRecipe and setAutoCraftRecipe:IsA("RemoteFunction")) then
		return false
	end
	if not (addBodyPartIngredient and addBodyPartIngredient:IsA("RemoteFunction")) then
		return false
	end
	if not (addMaterialIngredient and addMaterialIngredient:IsA("RemoteFunction")) then
		return false
	end
	if not (addAllEligibleIngredients and addAllEligibleIngredients:IsA("RemoteFunction")) then
		return false
	end

	self._remotes = {
		getState = getState,
		craftRecipe = craftRecipe,
		setAutoCraftRecipe = setAutoCraftRecipe,
		addBodyPartIngredient = addBodyPartIngredient,
		addMaterialIngredient = addMaterialIngredient,
		addAllEligibleIngredients = addAllEligibleIngredients,
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
	if key == nil or key == CRAFTING_PROGRESS_DATA_KEY then
		state.craftingProgress = CraftingProgress.NormalizeState(DataController:Get(CRAFTING_PROGRESS_DATA_KEY))
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

function CraftingController:_setRecipeFilter(slot: string?)
	self._selectedFilterSlot = slot
	self:_hideIngredientPanels()
	self:_syncFilterButtons()
	self:_syncRecipeRows()
end

function CraftingController:_syncFilterButtons()
	-- Filter button colors are authored in Studio. Keep this hook so filter
	-- sync call sites stay simple without tinting the configured visuals.
end

function CraftingController:_recipeMatchesSearch(recipe: any, query: string): boolean
	if query == "" then
		return true
	end

	local yieldLabel, typeLabel = getYieldInfo(recipe)
	local searchableParts = {
		tostring(recipe.label or ""),
		formatRecipeDescription(recipe, false),
		yieldLabel,
		typeLabel,
	}
	if recipeRequiresBossLoot(recipe) then
		table.insert(searchableParts, BOSS_LOOT_MARKER_TEXT)
	end

	for _, ingredient in ipairs(if typeof(recipe.bodyParts) == "table" then recipe.bodyParts else {}) do
		table.insert(searchableParts, getBodyPartIngredientLabel(ingredient))
	end

	for _, ingredient in ipairs(if typeof(recipe.materials) == "table" then recipe.materials else {}) do
		local material = CraftingMaterialConfig.Get(ingredient.materialId)
		table.insert(searchableParts, if material then material.label else tostring(ingredient.materialId or ""))
	end

	return string.find(string.lower(table.concat(searchableParts, " ")), query, 1, true) ~= nil
end

function CraftingController:_recipeMatchesFilter(recipe: any): boolean
	if self._selectedFilterSlot == nil then
		return true
	end

	local recipeYield = typeof(recipe) == "table" and recipe.yield or nil
	if typeof(recipeYield) ~= "table" or recipeYield.kind ~= "accessory" then
		return false
	end

	local config = AccessoryConfig.Get(recipeYield.accessoryId)
	return config ~= nil and config.slot == self._selectedFilterSlot
end

function CraftingController:_selectRecipe(recipeId: string?)
	local changed = self._selectedRecipeId ~= recipeId
	self._selectedRecipeId = recipeId
	if changed then
		self:_hideIngredientPanels()
	end
	self:_syncDetail()
	self:_refreshRecipeRowStates()
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
		if self:_recipeMatchesFilter(recipe) and self:_recipeMatchesSearch(recipe, query) then
			table.insert(visibleRecipes, recipe)
		end
	end

	local selectedStillVisible = false
	local firstVisibleRecipe = nil
	for index, recipe in ipairs(visibleRecipes) do
		local row = ui.recipeTemplate:Clone()
		row.Name = "CraftingRecipe_" .. recipe.id
		row.LayoutOrder = index
		row.Visible = true
		row.Active = true
		row.AutoButtonColor = false
		applyRecipeRowColor(row, getRecipeCardColor(recipe))

		local yieldLabel, typeLabel = getYieldInfo(recipe)
		local nameLabel = getFirstTextLabel(row, "AccessoryName")
		local descriptionLabel = getFirstTextLabel(row, "AccessoryDescription")
		local typeLabelInstance = getFirstTextLabel(row, "AccessoryType")
		if nameLabel then
			nameLabel.Text = tostring(recipe.label or yieldLabel)
		end
		if descriptionLabel then
			descriptionLabel.RichText = true
			descriptionLabel.Text = formatRecipeDescription(recipe, true)
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
	end

	if not selectedStillVisible then
		self._selectedRecipeId = if firstVisibleRecipe then firstVisibleRecipe.id else nil
		self:_hideIngredientPanels()
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

function CraftingController:_addRequirementRow(labelText: string, ownedAmount: number, requiredAmount: number, layoutOrder: number)
	local ui = self:_ensureUi()
	local row = ui.requirementTemplate:Clone()
	row.Name = string.format("%s%03d", INGREDIENT_ROW_PREFIX, layoutOrder)
	row.LayoutOrder = layoutOrder
	row.Visible = true

	local label = getFirstTextLabel(row, "MaterialName")
	if label then
		label.Text = labelText
	end

	local countLabel = getFirstTextLabel(row, "MaterialCount")
	if countLabel then
		countLabel.Text = string.format("%s/%s", formatWholeNumber(ownedAmount), formatWholeNumber(requiredAmount))
	end

	row.Parent = ui.requirementList
end

function CraftingController:_syncRequirements(recipe: any)
	local ui = self:_ensureUi()
	hideGeneratedChildren(ui.requirementList, INGREDIENT_ROW_PREFIX)
	hideNativeTemplates(ui.requirementList, ui.requirementTemplate)

	if typeof(recipe) ~= "table" then
		return
	end

	local recipeProgress = self:_getRecipeProgress(recipe.id)
	local layoutOrder = 1
	for _, ingredient in ipairs(if typeof(recipe.bodyParts) == "table" then recipe.bodyParts else {}) do
		local requiredAmount = math.max(1, math.floor(tonumber(ingredient.amount) or 1))
		local ingredientKey = CraftingProgress.GetBodyPartIngredientKey(ingredient)
		self:_addRequirementRow(
			getBodyPartIngredientLabel(ingredient),
			recipeProgress.bodyPartsByIngredientKey[ingredientKey] or 0,
			requiredAmount,
			layoutOrder
		)
		layoutOrder += 1
	end

	for _, ingredient in ipairs(if typeof(recipe.materials) == "table" then recipe.materials else {}) do
		local material = CraftingMaterialConfig.Get(ingredient.materialId)
		local requiredAmount = math.max(1, math.floor(tonumber(ingredient.amount) or 1))
		self:_addRequirementRow(
			if material then material.label else tostring(ingredient.materialId or "Material"),
			recipeProgress.materialsByMaterialId[ingredient.materialId] or 0,
			requiredAmount,
			layoutOrder
		)
		layoutOrder += 1
	end
end

function CraftingController:_setCraftButtonText(recipe: any?)
	local ui = self:_ensureUi()
	local label = ui.ingredientCraftButtonLabel
	if not label then
		return
	end

	local moneyCost = if typeof(recipe) == "table" and not self:_shouldWaiveTutorialCraftCost(recipe)
		then math.max(0, math.floor(tonumber(recipe.moneyCost) or 0))
		else 0
	label.Text = if moneyCost > 0 then string.format("Craft ($%s)", formatWholeNumber(moneyCost)) else "Craft"
end

function CraftingController:_syncAutoCraftButton(recipe: any?)
	local ui = self:_ensureUi()
	local enabled = false
	if typeof(recipe) == "table" then
		enabled = self:_getCraftingProgress().autoRecipeIds[recipe.id] == true
	end

	setAutoCraftButtonColor(ui.autoCraftButton, enabled)
	if ui.autoCraftUsage then
		ui.autoCraftUsage.Text = string.format(
			"<b>Auto Craft [%s]</b> <br /> This item will automatically take matching rolled body parts before auto sell. When it is ready, visit Crafting and press Craft.",
			if enabled then "ON" else "OFF"
		)
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
		self:_syncRequirements(nil)
		self:_syncAutoCraftButton(nil)
		if ui.viewportFrame then
			self:_stopViewportRotation()
			ViewportModelRenderer.Clear(ui.viewportFrame)
			ui.viewportFrame.Visible = false
		end
		setGuiButtonEnabled(ui.ingredientCraftButton, false)
		return
	end

	local yieldLabel = getYieldInfo(recipe)
	local canCraft = self:_getCraftability(recipe)
	ui.itemName.Text = yieldLabel
	if ui.itemDescription then
		local itemStatRows = buildRecipeItemStatRows(recipe)
		if recipeRequiresBossLoot(recipe) then
			table.insert(itemStatRows, {
				text = string.format("<i>%s</i>", BOSS_LOOT_MARKER_TEXT),
				richText = true,
				color = ui.itemDescription.TextColor3,
			})
		end
		renderRecipeItemStatRows(ui.itemDescription, itemStatRows)
	end
	self:_setCraftButtonText(recipe)
	self:_syncRequirements(recipe)
	self:_renderYieldViewport(recipe)
	self:_syncAutoCraftButton(recipe)
	setGuiButtonEnabled(ui.ingredientCraftButton, canCraft and not self._requestInFlight)
	if ui.ingredientSelect and ui.ingredientSelect.Visible then
		self:_syncIngredientSelect()
	end
end

function CraftingController:GetTutorialTarget(targetId: string): GuiObject?
	local ok = pcall(function()
		self:_ensureUi()
	end)
	if not ok or not self._ui or self._ui.root.Visible ~= true then
		return nil
	end

	local isHolidayCrownSelected = self._selectedRecipeId == "holiday_crown"
	local isIngredientPanelOpen = self._ui.ingredientSelect ~= nil
		and self._ui.ingredientSelect.Visible == true
		and self._ui.ingredientMain ~= nil
		and self._ui.ingredientMain.Visible == true

	if targetId == "closeButton" then
		local button = self._ui.menuCloseButton
		return if button and button.Visible == true and button.Active == true then button else nil
	end
	if targetId == "accessoriesFilter" then
		local button = self._ui.accessoriesFilterButton
		return if button and button.Visible == true and button.Active == true then button else nil
	end
	if targetId == "holidayCrownRecipe" then
		if isHolidayCrownSelected then
			return nil
		end
		self:_syncRecipeRows()
		local row = self._recipeRowsById["holiday_crown"]
		if row and row:IsA("GuiButton") and row.Visible == true and row.Active == true then
			self:_scrollTutorialRecipeIntoView(row)
			return row
		end
		return nil
	end
	if targetId == "autoCraft" then
		if not isHolidayCrownSelected then
			return nil
		end
		local button = self._ui.autoCraftButton
		return if button and button.Visible == true and button.Active == true then button else nil
	end
	if targetId == "openRecipe" then
		if not isHolidayCrownSelected or isIngredientPanelOpen then
			return nil
		end
		local button = self._ui.openRecipeButton
		return if button and button.Visible == true and button.Active == true then button else nil
	end
	if targetId == "craftButton" then
		if not isHolidayCrownSelected or not isIngredientPanelOpen then
			return nil
		end
		local button = self._ui.ingredientCraftButton
		return if button and button.Visible == true and button.Active == true then button else nil
	end

	return nil
end

function CraftingController:_scrollTutorialRecipeIntoView(row: GuiObject)
	local ui = self._ui
	local recipeList = ui and ui.recipeList
	if not (recipeList and row:IsDescendantOf(recipeList)) then
		return
	end

	local viewTop = recipeList.AbsolutePosition.Y
	local viewBottom = viewTop + recipeList.AbsoluteSize.Y
	local rowTop = row.AbsolutePosition.Y
	local rowBottom = rowTop + row.AbsoluteSize.Y
	local deltaY = 0
	if rowTop < viewTop then
		deltaY = rowTop - viewTop
	elseif rowBottom > viewBottom then
		deltaY = rowBottom - viewBottom
	end

	if math.abs(deltaY) < 1 then
		return
	end

	local current = recipeList.CanvasPosition
	recipeList.CanvasPosition = Vector2.new(current.X, math.max(0, current.Y + deltaY))
end

function CraftingController:_hideConfirmation()
	local ui = self:_ensureUi()
	if ui.confirmationFrame then
		ui.confirmationFrame.Visible = false
	end
	if
		ui.ingredientSelect
		and ui.ingredientSelect.Visible
		and ui.ingredientMain
		and not (ui.selectPartsFrame and ui.selectPartsFrame.Visible)
		and not (ui.helpMenu and ui.helpMenu.Visible)
	then
		ui.ingredientMain.Visible = true
	end
end

function CraftingController:_disconnectHelpMenuCloseListener()
	if self._helpMenuCloseConnection then
		self._helpMenuCloseConnection:Disconnect()
		self._helpMenuCloseConnection = nil
	end
end

function CraftingController:_bindHelpMenuCloseListener()
	self:_disconnectHelpMenuCloseListener()
	self._helpMenuCloseConnection = UserInputService.InputBegan:Connect(function(input: InputObject)
		if not HELP_MENU_CLOSE_INPUT_TYPES[input.UserInputType] then
			return
		end

		local ui = self._ui
		if not self._isOpen or not ui or not ui.helpMenu or not ui.helpMenu.Visible then
			self:_disconnectHelpMenuCloseListener()
			return
		end

		self:_hideHelpMenu()
	end)
end

function CraftingController:_hideHelpMenu()
	self:_disconnectHelpMenuCloseListener()
	local ui = self:_ensureUi()
	if ui.helpMenu then
		ui.helpMenu.Visible = false
	end
end

function CraftingController:_showHelpMenu()
	local ui = self:_ensureUi()
	if not ui.helpMenu then
		showNotification("Crafting help is not ready right now.")
		return
	end

	if ui.ingredientSelect then
		ui.ingredientSelect.Visible = false
	end
	if ui.ingredientMain then
		ui.ingredientMain.Visible = false
	end
	if ui.confirmationFrame then
		ui.confirmationFrame.Visible = false
	end
	if ui.selectPartsFrame then
		ui.selectPartsFrame.Visible = false
	end
	if ui.selectPartsList then
		hideGeneratedChildren(ui.selectPartsList, SELECT_PART_PREFIX)
		hideNativeTemplates(ui.selectPartsList, ui.selectPartsTemplate)
	end
	self._selectingIngredientKey = nil
	self._selectedPartIds = {}
	self._selectedPartOrder = {}
	self._maxSelectedParts = 0
	self._selectPartCardsByOwnedId = {}
	self._materialAmountDrafts = {}
	self._focusedMaterialAmountDraftKey = nil
	ui.helpMenu.Visible = true
	self:_bindHelpMenuCloseListener()
end

function CraftingController:_hideSelectParts()
	local ui = self:_ensureUi()
	if ui.selectPartsFrame then
		ui.selectPartsFrame.Visible = false
	end
	if ui.helpMenu then
		ui.helpMenu.Visible = false
	end
	if ui.selectPartsList then
		hideGeneratedChildren(ui.selectPartsList, SELECT_PART_PREFIX)
		hideNativeTemplates(ui.selectPartsList, ui.selectPartsTemplate)
	end
	self._selectingIngredientKey = nil
	self._selectedPartIds = {}
	self._selectedPartOrder = {}
	self._maxSelectedParts = 0
	self._selectPartCardsByOwnedId = {}
	if ui.ingredientSelect and ui.ingredientSelect.Visible and ui.ingredientMain then
		ui.ingredientMain.Visible = true
		self:_syncIngredientSelect()
	end
end

function CraftingController:_hideIngredientPanels()
	local ui = self._ui
	if not ui then
		self._materialAmountDrafts = {}
		self._focusedMaterialAmountDraftKey = nil
		return
	end
	if ui.ingredientSelect then
		ui.ingredientSelect.Visible = false
	end
	if ui.helpMenu then
		ui.helpMenu.Visible = false
	end
	if ui.ingredientMain then
		ui.ingredientMain.Visible = false
	end
	if ui.confirmationFrame then
		ui.confirmationFrame.Visible = false
	end
	if ui.selectPartsFrame then
		ui.selectPartsFrame.Visible = false
	end
	if ui.selectPartsList then
		hideGeneratedChildren(ui.selectPartsList, SELECT_PART_PREFIX)
		hideNativeTemplates(ui.selectPartsList, ui.selectPartsTemplate)
	end
	self._selectingIngredientKey = nil
	self._selectedPartIds = {}
	self._selectedPartOrder = {}
	self._maxSelectedParts = 0
	self._selectPartCardsByOwnedId = {}
	self._materialAmountDrafts = {}
	self._focusedMaterialAmountDraftKey = nil
end

function CraftingController:_openIngredientSelect()
	local ui = self:_ensureUi()
	if not self:_findRecipe(self._selectedRecipeId) then
		showNotification("Select a recipe first.")
		return
	end
	if ui.ingredientSelect then
		ui.ingredientSelect.Visible = true
	end
	if ui.ingredientMain then
		ui.ingredientMain.Visible = true
	end
	self:_hideHelpMenu()
	self:_hideConfirmation()
	self:_hideSelectParts()
	self:_syncIngredientSelect()
end

function CraftingController:_addBodyPartIngredientRow(recipe: any, ingredient: any, layoutOrder: number)
	local ui = self:_ensureUi()
	if not ui.ingredientList or not ui.bodyPartIngredientTemplate then
		return
	end

	local row = ui.bodyPartIngredientTemplate:Clone()
	row.Name = string.format("%sBody_%03d", INGREDIENT_ROW_PREFIX, layoutOrder)
	row.LayoutOrder = layoutOrder
	row.Visible = true

	local ingredientKey = CraftingProgress.GetBodyPartIngredientKey(ingredient)
	local requiredAmount = math.max(1, math.floor(tonumber(ingredient.amount) or 1))
	local currentAmount = self:_getRecipeProgress(recipe.id).bodyPartsByIngredientKey[ingredientKey] or 0
	local label = getFirstTextLabel(row, "AuraName") or getFirstTextLabel(row, "MaterialName")
	if label then
		label.Text = getBodyPartIngredientLabel(ingredient)
	end
	local countLabel = getFirstTextLabel(row, "Content") or getFirstTextLabel(row, "MaterialCount")
	if countLabel then
		countLabel.Text = string.format("%s/%s", formatWholeNumber(currentAmount), formatWholeNumber(requiredAmount))
	end

	local selectButton = row:FindFirstChild("Disabled", true)
	if selectButton and selectButton:IsA("GuiButton") then
		local missingAmount = math.max(0, requiredAmount - currentAmount)
		selectButton.Visible = true
		selectButton.Active = missingAmount > 0
		UIController:CreateButton(selectButton, function()
			self:_openSelectParts(ingredientKey)
		end)
	end
	local enabledButton = row:FindFirstChild("Enabled", true)
	if enabledButton and enabledButton:IsA("GuiObject") then
		enabledButton.Visible = false
	end
	row.Parent = ui.ingredientList
end

function CraftingController:_addMaterialIngredientRow(recipe: any, ingredient: any, layoutOrder: number)
	local ui = self:_ensureUi()
	if not ui.ingredientList or not ui.materialIngredientTemplate then
		return
	end

	local row = ui.materialIngredientTemplate:Clone()
	row.Name = string.format("%sMaterial_%03d", INGREDIENT_ROW_PREFIX, layoutOrder)
	row.LayoutOrder = layoutOrder
	row.Visible = true

	local material = CraftingMaterialConfig.Get(ingredient.materialId)
	local materialId = tostring(ingredient.materialId or "")
	local requiredAmount = math.max(1, math.floor(tonumber(ingredient.amount) or 1))
	local currentAmount = self:_getRecipeProgress(recipe.id).materialsByMaterialId[materialId] or 0
	local missingAmount = math.max(0, requiredAmount - currentAmount)
	local ownedAmount = self:_getMaterialAmounts()[materialId] or 0
	local materialLabel = if material then material.label else tostring(ingredient.materialId or "Material")
	local label = getFirstTextLabel(row, "AuraName") or getFirstTextLabel(row, "MaterialName")
	if label then
		label.Text = string.format("%s - %s owned", materialLabel, formatWholeNumber(ownedAmount))
	end
	local countLabel = getFirstTextLabel(row, "Content") or getFirstTextLabel(row, "MaterialCount")
	if countLabel then
		countLabel.Text = string.format("%s/%s", formatWholeNumber(currentAmount), formatWholeNumber(requiredAmount))
	end

	local amountBox = getFirstTextBox(row, "AmountBox")
	local draftKey = getMaterialAmountDraftKey(tostring(recipe.id), materialId)
	if amountBox then
		local draftText = self._materialAmountDrafts[draftKey]
		if draftText == nil then
			draftText = if missingAmount > 0 then "1" else "0"
			self._materialAmountDrafts[draftKey] = draftText
		end
		amountBox.Text = draftText
		amountBox:GetPropertyChangedSignal("Text"):Connect(function()
			self._materialAmountDrafts[draftKey] = amountBox.Text
		end)
		amountBox.Focused:Connect(function()
			self._focusedMaterialAmountDraftKey = draftKey
		end)
		amountBox.FocusLost:Connect(function()
			local normalizedText = clampMaterialAmountText(amountBox.Text, missingAmount)
			self._materialAmountDrafts[draftKey] = normalizedText
			amountBox.Text = normalizedText
			if self._focusedMaterialAmountDraftKey == draftKey then
				self._focusedMaterialAmountDraftKey = nil
			end
		end)
	end

	local addButton = row:FindFirstChild("AddButton", true)
	if addButton and addButton:IsA("GuiButton") then
		UIController:CreateButton(addButton, function()
			if missingAmount <= 0 then
				showNotification("This material is already filled.")
				return
			end

			if amountBox then
				amountBox:ReleaseFocus()
			end
			if self._focusedMaterialAmountDraftKey == draftKey then
				self._focusedMaterialAmountDraftKey = nil
			end

			local normalizedText = clampMaterialAmountText(if amountBox then amountBox.Text else self._materialAmountDrafts[draftKey], missingAmount)
			local commitAmount = math.max(0, tonumber(normalizedText) or 0)
			if amountBox then
				amountBox.Text = normalizedText
			end
			self._materialAmountDrafts[draftKey] = normalizedText
			self:_addMaterialIngredient(materialId, commitAmount)
		end)
	end
	row.Parent = ui.ingredientList
end

function CraftingController:_syncIngredientSelect()
	local ui = self:_ensureUi()
	local recipe = self:_findRecipe(self._selectedRecipeId)
	if not recipe or not ui.ingredientList then
		return
	end

	if self._focusedMaterialAmountDraftKey ~= nil then
		local canCraft = self:_getCraftability(recipe)
		setGuiButtonEnabled(ui.ingredientCraftButton, canCraft and not self._requestInFlight)
		return
	end

	hideGeneratedChildren(ui.ingredientList, INGREDIENT_ROW_PREFIX)
	hideNativeTemplates(ui.ingredientList, ui.bodyPartIngredientTemplate)
	hideNativeTemplates(ui.ingredientList, ui.materialIngredientTemplate)

	local layoutOrder = 1
	for _, ingredient in ipairs(if typeof(recipe.bodyParts) == "table" then recipe.bodyParts else {}) do
		self:_addBodyPartIngredientRow(recipe, ingredient, layoutOrder)
		layoutOrder += 1
	end
	for _, ingredient in ipairs(if typeof(recipe.materials) == "table" then recipe.materials else {}) do
		self:_addMaterialIngredientRow(recipe, ingredient, layoutOrder)
		layoutOrder += 1
	end

	local canCraft = self:_getCraftability(recipe)
	setGuiButtonEnabled(ui.ingredientCraftButton, canCraft and not self._requestInFlight)
end

function CraftingController:_buildBodyPartCardPayload(record: any): any?
	local piece = record and record.pieceId and BodyPartsCatalog.GetPiece(record.pieceId)
	if not piece then
		return nil
	end

	local setConfig = BodyPartsCatalog.GetSetForPiece(piece.id)
	local rarityStyle = BodyPartPresentation.ResolveBodyPartRarityStyle({
		record = record,
		piece = piece,
		setConfig = setConfig,
	}) or {}

	return {
		nameText = BodyPartPresentation.FormatInventoryNameText(piece.displayName, record),
		usageText = string.format("$%s/s", formatWholeNumber(getRecordPassiveIncome(record, piece))),
		bundleModel = BodyPartsCatalog.ResolveBundleModel(piece.id),
		region = piece.region,
		previewScale = record.sizeMultiplier or 1,
		appearanceUserId = LOCAL_PLAYER and LOCAL_PLAYER.UserId or nil,
		applyPlayerClothing = setConfig == nil or setConfig.applyPlayerClothing ~= false,
		applyPlayerBodyColors = setConfig == nil or setConfig.applyPlayerBodyColors ~= false,
		favoriteVisible = record.isFavorite == true,
		equippedVisible = isBodyPartEquipped(self:_getEquippedLoadout(), record.ownedId),
		cardAccentColor = rarityStyle.accentColor,
		baseFillColor = rarityStyle.baseFillColor,
		selectedFillColor = rarityStyle.selectedFillColor,
	}
end

function CraftingController:_populateSelectPartCard(frame: GuiObject, record: any)
	local button = frame:FindFirstChild("Base")
	if not (button and button:IsA("ImageButton")) then
		return
	end

	local payload = self:_buildBodyPartCardPayload(record)
	if not payload then
		return
	end
	local isSelected = self._selectedPartIds[record.ownedId] == true
	payload.isSelected = isSelected
	BodyPartPresentation.PopulateBundleCard(button, payload)
	applySelectPartOutline(button, isSelected)
end

function CraftingController:_refreshSelectPartCard(ownedId: string)
	local card = self._selectPartCardsByOwnedId[ownedId]
	if typeof(card) ~= "table" then
		return
	end
	if card.frame and card.frame.Parent and card.record then
		self:_populateSelectPartCard(card.frame, card.record)
	end
end

function CraftingController:_setSelectedPart(ownedId: string, isSelected: boolean)
	if isSelected then
		if self._selectedPartIds[ownedId] == true then
			return
		end

		while self._maxSelectedParts > 0 and #self._selectedPartOrder >= self._maxSelectedParts do
			local removedOwnedId = table.remove(self._selectedPartOrder, 1)
			if removedOwnedId then
				self._selectedPartIds[removedOwnedId] = nil
				self:_refreshSelectPartCard(removedOwnedId)
			else
				break
			end
		end

		self._selectedPartIds[ownedId] = true
		table.insert(self._selectedPartOrder, ownedId)
	else
		self._selectedPartIds[ownedId] = nil
		removeFirstValue(self._selectedPartOrder, ownedId)
	end

	self:_refreshSelectPartCard(ownedId)
end

function CraftingController:_openSelectParts(ingredientKey: string)
	local ui = self:_ensureUi()
	local recipe = self:_findRecipe(self._selectedRecipeId)
	local ingredient = self:_findBodyPartIngredient(recipe, ingredientKey)
	if not recipe or not ingredient or not ui.selectPartsFrame or not ui.selectPartsList or not ui.selectPartsTemplate then
		return
	end

	local eligible = self:_getEligibleBodyPartsForIngredient(ingredient)
	if #eligible == 0 then
		showNotification("No eligible parts for this ingredient.")
		return
	end

	local requiredAmount = math.max(1, math.floor(tonumber(ingredient.amount) or 1))
	local currentAmount = self:_getRecipeProgress(recipe.id).bodyPartsByIngredientKey[ingredientKey] or 0
	local maxSelectedParts = math.max(0, requiredAmount - currentAmount)
	if maxSelectedParts <= 0 then
		showNotification("That ingredient is already full.")
		return
	end

	self._selectingIngredientKey = ingredientKey
	self._selectedPartIds = {}
	self._selectedPartOrder = {}
	self._maxSelectedParts = maxSelectedParts
	self._selectPartCardsByOwnedId = {}
	if ui.ingredientMain then
		ui.ingredientMain.Visible = false
	end
	ui.selectPartsFrame.Visible = true
	self:_hideConfirmation()

	hideGeneratedChildren(ui.selectPartsList, SELECT_PART_PREFIX)
	hideNativeTemplates(ui.selectPartsList, ui.selectPartsTemplate)

	for index, record in ipairs(eligible) do
		local frame = ui.selectPartsTemplate:Clone()
		frame.Name = string.format("%s%03d", SELECT_PART_PREFIX, index)
		frame.LayoutOrder = index
		frame.Visible = true
		frame.Parent = ui.selectPartsList
		self._selectPartCardsByOwnedId[record.ownedId] = {
			frame = frame,
			record = record,
		}
		self:_populateSelectPartCard(frame, record)

		local button = frame:FindFirstChild("Base")
		if button and button:IsA("GuiButton") then
			UIController:CreateButton(button, function()
				self:_setSelectedPart(record.ownedId, self._selectedPartIds[record.ownedId] ~= true)
			end)
		end
	end
end

function CraftingController:_collectSelectedPartIds(): { string }
	local selectedIds = {}
	for _, ownedId in ipairs(self._selectedPartOrder) do
		if self._selectedPartIds[ownedId] == true then
			table.insert(selectedIds, ownedId)
		end
	end
	return selectedIds
end

function CraftingController:_handleMutationResult(result: any, fallbackFailure: string)
	self._requestInFlight = false
	if typeof(result) ~= "table" then
		showNotification(fallbackFailure)
		self:_requestCraftingState(false)
		self:_syncUi()
		return
	end

	self:_applyState(result.state)
	self:_syncUi()
	if result.ok == true then
		showNotification(tostring(result.message or "Updated crafting."), "good")
	else
		showNotification(tostring(result.message or fallbackFailure))
	end
end

function CraftingController:_confirmSelectedParts()
	if self._requestInFlight then
		return
	end
	if not self:_ensureRemotes() then
		showNotification("Crafting is not ready right now.")
		return
	end

	local recipe = self:_findRecipe(self._selectedRecipeId)
	if not recipe or not self._selectingIngredientKey then
		showNotification("Select an ingredient first.")
		return
	end

	local selectedIds = self:_collectSelectedPartIds()
	if #selectedIds == 0 then
		showNotification("Select at least one body part.")
		return
	end

	self._requestInFlight = true
	local result = self:_invokeRemote(self._remotes.addBodyPartIngredient, {
		recipeId = recipe.id,
		ingredientKey = self._selectingIngredientKey,
		bodyPartOwnedIds = selectedIds,
	})
	self:_hideSelectParts()
	self:_handleMutationResult(result, "Could not add body parts.")
end

function CraftingController:_addMaterialIngredient(materialId: string, amount: number)
	if self._requestInFlight then
		return
	end
	if not self:_ensureRemotes() then
		showNotification("Crafting is not ready right now.")
		return
	end

	local recipe = self:_findRecipe(self._selectedRecipeId)
	if not recipe then
		showNotification("Select a recipe first.")
		return
	end

	local draftKey = getMaterialAmountDraftKey(tostring(recipe.id), tostring(materialId))
	self._requestInFlight = true
	local result = self:_invokeRemote(self._remotes.addMaterialIngredient, {
		recipeId = recipe.id,
		materialId = materialId,
		amount = amount,
	})
	if typeof(result) == "table" and result.ok == true then
		self._materialAmountDrafts[draftKey] = nil
	end
	self:_handleMutationResult(result, "Could not add material.")
end

function CraftingController:_showAddEverythingConfirmation()
	local ui = self:_ensureUi()
	if not self:_findRecipe(self._selectedRecipeId) then
		showNotification("Select a recipe first.")
		return
	end
	if ui.ingredientMain then
		ui.ingredientMain.Visible = false
	end
	if ui.helpMenu then
		ui.helpMenu.Visible = false
	end
	if ui.confirmationFrame then
		ui.confirmationFrame.Visible = true
	end
	if ui.selectPartsFrame then
		ui.selectPartsFrame.Visible = false
	end
end

function CraftingController:_confirmAddEverything()
	if self._requestInFlight then
		return
	end
	if not self:_ensureRemotes() then
		showNotification("Crafting is not ready right now.")
		return
	end

	local recipe = self:_findRecipe(self._selectedRecipeId)
	if not recipe then
		showNotification("Select a recipe first.")
		return
	end

	self._requestInFlight = true
	local result = self:_invokeRemote(self._remotes.addAllEligibleIngredients, {
		recipeId = recipe.id,
	})
	self:_hideConfirmation()
	self:_handleMutationResult(result, "Could not add ingredients.")
end

function CraftingController:_toggleAutoCraftSelectedRecipe()
	if self._requestInFlight then
		return
	end
	if not self:_ensureRemotes() then
		showNotification("Crafting is not ready right now.")
		return
	end

	local recipe = self:_findRecipe(self._selectedRecipeId)
	if not recipe then
		showNotification("Select a recipe first.")
		return
	end

	local enabled = self:_getCraftingProgress().autoRecipeIds[recipe.id] ~= true
	self._requestInFlight = true
	local result = self:_invokeRemote(self._remotes.setAutoCraftRecipe, {
		recipeId = recipe.id,
		enabled = enabled,
	})
	self:_handleMutationResult(result, "Could not update auto craft.")
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
	local canCraft, reason = self:_getCraftability(recipe)
	if not canCraft then
		showNotification(reason)
		self:_syncDetail()
		return
	end

	self._requestInFlight = true
	self:_syncDetail()

	local result = self:_invokeRemote(self._remotes.craftRecipe, {
		recipeId = recipe.id,
	})

	self:_handleMutationResult(result, "The craft could not be completed.")
end

function CraftingController:_syncUi()
	self:_syncFilterButtons()
	self:_syncRecipeRows()
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
		preserveRootLayout = true,
	})
	ObjectiveGuideController.ClearObjective("crafting")
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
	self._selectedFilterSlot = HEAD_FILTER
	self:_ensureUi()
	self:_hideIngredientPanels()
	if not self:_requestCraftingState(true) then
		self._state = self._state or {
			recipes = CraftingRecipeConfig.GetAll(),
			craftingMaterials = {},
			craftingProgress = CraftingProgress.CreateEmptyState(),
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
	self:_disconnectHelpMenuCloseListener()
	self:_hideIngredientPanels()
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
		and key ~= CRAFTING_PROGRESS_DATA_KEY
		and key ~= MONEY_DATA_KEY
	then
		return
	end

	self:_hydrateStateFromData(key)
	self:_syncUi()
end

function CraftingController:IsOpen(): boolean
	return self._isOpen == true
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
