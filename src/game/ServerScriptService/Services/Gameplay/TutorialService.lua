local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AccessoryConfig = require(ReplicatedStorage.Shared.Config.AccessoryConfig)
local BodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
local CraftingProgress = require(ReplicatedStorage.Shared.Character.CraftingProgress)
local CraftingRecipeConfig = require(ReplicatedStorage.Shared.Config.CraftingRecipeConfig)
local DailyChestConfig = require(ReplicatedStorage.Shared.Config.DailyChestConfig)
local DailyChestState = require(ReplicatedStorage.Shared.Character.DailyChestState)
local SizeConfig = require(ReplicatedStorage.Shared.Config.SizeConfig)
local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
local TutorialState = require(ReplicatedStorage.Shared.Character.TutorialState)
local DataService = require(script.Parent.DataService)
local RequestLimiter = require(script.Parent.Common.RequestLimiter)
local TutorialAnalyticsService = require(script.Parent.TutorialAnalyticsService)

local REMOTES_FOLDER_NAME = "Remotes"
local TUTORIAL_FOLDER_NAME = "Tutorial"
local GET_STATE_REMOTE_NAME = "GetTutorialState"
local ADVANCE_REMOTE_NAME = "AdvanceTutorialStep"
local CLAIM_CHEST_REMOTE_NAME = "ClaimTutorialChest"
local UPDATED_REMOTE_NAME = "TutorialUpdated"

local TutorialService = {}

local remotesFolder: Folder? = nil
local tutorialFolder: Folder? = nil
local getStateRemote: RemoteFunction? = nil
local advanceRemote: RemoteFunction? = nil
local claimChestRemote: RemoteFunction? = nil
local updatedRemote: RemoteEvent? = nil

local function createOrGetFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = parent
	return created
end

local function createOrGetRemoteFunction(parent: Instance, name: string): RemoteFunction
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local created = Instance.new("RemoteFunction")
	created.Name = name
	created.Parent = parent
	return created
end

local function createOrGetRemoteEvent(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local created = Instance.new("RemoteEvent")
	created.Name = name
	created.Parent = parent
	return created
end

local function ensureTutorialFolder(): Folder
	if tutorialFolder and tutorialFolder.Parent then
		return tutorialFolder
	end

	remotesFolder = createOrGetFolder(ReplicatedStorage, REMOTES_FOLDER_NAME)
	tutorialFolder = createOrGetFolder(remotesFolder, TUTORIAL_FOLDER_NAME)
	return tutorialFolder
end

local function response(ok: boolean, message: string, state: any?, extra: any?)
	local result = {
		ok = ok,
		message = message,
		state = TutorialState.CloneState(state),
	}
	if typeof(extra) == "table" then
		for key, value in pairs(extra) do
			result[key] = value
		end
	end
	return result
end

local function isActive(player: Player): boolean
	return player.Parent == Players and DataService:IsPlayerDataLoaded(player)
end

local function getStepIndex(stepId: string): number
	return TutorialConfig.GetStepIndex(stepId)
end

local function getState(player: Player): TutorialState.TutorialStateValue
	return DataService:GetTutorialState(player)
end

local function applyStepEntryRewards(player: Player, state: TutorialState.TutorialStateValue)
	if state.completed == true or state.roll2MoneyGranted == true then
		return
	end

	local stepIndex = TutorialConfig.GetStepIndex(state.stepId)
	local roll2StepIndex = TutorialConfig.GetStepIndex(TutorialConfig.Steps.SelectRoll2)
	local appraiseStepIndex = TutorialConfig.GetStepIndex(TutorialConfig.Steps.GoAppraise)
	if stepIndex >= roll2StepIndex and stepIndex < appraiseStepIndex then
		DataService:AddMoney(player, TutorialConfig.Roll2MoneyGrantAmount, "tutorial_roll2")
		state.roll2MoneyGranted = true
	end
end

local function setState(player: Player, state: any): TutorialState.TutorialStateValue
	local normalizedState = TutorialState.Normalize(state)
	applyStepEntryRewards(player, normalizedState)
	local normalized = DataService:SetTutorialState(player, normalizedState)
	if updatedRemote then
		updatedRemote:FireClient(player, TutorialState.CloneState(normalized))
	end
	return normalized
end

local function hasAnyEquippedBodyPart(player: Player): boolean
	local equippedState = DataService:GetEquippedLoadout(player)
	for _, entry in pairs(equippedState) do
		if typeof(entry) == "table" and typeof(entry.ownedId) == "string" and entry.ownedId ~= "" then
			return true
		end
	end
	return false
end

local function getOwnedAccessoryByAccessoryId(player: Player, accessoryId: string): any?
	for _, ownedRecord in pairs(DataService:GetOwnedAccessories(player)) do
		if typeof(ownedRecord) == "table" and ownedRecord.accessoryId == accessoryId then
			return ownedRecord
		end
	end
	return nil
end

local function ownsTargetAccessory(player: Player): boolean
	return getOwnedAccessoryByAccessoryId(player, TutorialConfig.TargetAccessoryId) ~= nil
end

local function hasEquippedTargetAccessory(player: Player): boolean
	local equipped = DataService:GetEquippedAccessories(player)
	local ownedId = equipped[TutorialConfig.TargetAccessorySlot]
	if typeof(ownedId) ~= "string" or ownedId == "" then
		return false
	end

	local ownedRecord = DataService:GetOwnedAccessories(player)[ownedId]
	return typeof(ownedRecord) == "table" and ownedRecord.accessoryId == TutorialConfig.TargetAccessoryId
end

local function isTargetAutoCraftEnabled(player: Player): boolean
	return DataService:GetCraftingProgress(player).autoRecipeIds[TutorialConfig.TargetRecipeId] == true
end

local function getPieceIdForCraftIngredient(ingredient: any): string?
	if typeof(ingredient) ~= "table" then
		return nil
	end

	if typeof(ingredient.pieceId) == "string" and ingredient.pieceId ~= "" then
		return if BodyPartsCatalog.GetPiece(ingredient.pieceId) then ingredient.pieceId else nil
	end

	if typeof(ingredient.setId) ~= "string" or ingredient.setId == "" then
		return nil
	end

	local bestPieceId = nil
	local pieces = BodyPartsCatalog.GetPiecesForSet(ingredient.setId)
	if not pieces then
		return nil
	end

	for _, piece in ipairs(pieces) do
		local pieceId = if typeof(piece) == "table" then piece.id else nil
		local pieceRegion = if typeof(piece) == "table" then piece.region else nil
		local matchesRegion = ingredient.region == nil or pieceRegion == ingredient.region
		if typeof(pieceId) == "string" and pieceId ~= "" and matchesRegion then
			if bestPieceId == nil or pieceId < bestPieceId then
				bestPieceId = pieceId
			end
		end
	end

	return bestPieceId
end

local function resolveTargetCraftGoal(player: Player): any?
	local recipe = CraftingRecipeConfig.Get(TutorialConfig.TargetRecipeId)
	if not recipe then
		return nil
	end

	local progressState = DataService:GetCraftingProgress(player)
	local progress = CraftingProgress.GetRecipeProgress(progressState, recipe.id)
	for _, ingredient in ipairs(recipe.bodyParts) do
		local key = CraftingProgress.GetBodyPartIngredientKey(ingredient)
		local required = math.max(1, math.floor(tonumber(ingredient.amount) or 1))
		local current = math.max(0, math.floor(tonumber(progress.bodyPartsByIngredientKey[key]) or 0))
		if current < required then
			local forcedPieceId = getPieceIdForCraftIngredient(ingredient)
			local forcedSetId = if typeof(ingredient.setId) == "string" then ingredient.setId else nil
			if forcedPieceId ~= nil then
				local piece = BodyPartsCatalog.GetPiece(forcedPieceId)
				return {
					recipe = recipe,
					recipeId = recipe.id,
					ready = false,
					ingredientKey = key,
					forcedPieceId = forcedPieceId,
					forcedSetId = if piece then piece.setId else forcedSetId,
				}
			end
			return {
				recipe = recipe,
				recipeId = recipe.id,
				ready = false,
				ingredientKey = key,
				forcedSetId = forcedSetId,
			}
		end
	end

	for _, ingredient in ipairs(recipe.materials) do
		local required = math.max(1, math.floor(tonumber(ingredient.amount) or 1))
		if (progress.materialsByMaterialId[ingredient.materialId] or 0) < required then
			return {
				recipe = recipe,
				recipeId = recipe.id,
				ready = false,
			}
		end
	end

	return {
		recipe = recipe,
		recipeId = recipe.id,
		ready = true,
	}
end

local function advanceTo(player: Player, nextStepId: string): TutorialState.TutorialStateValue
	local state = getState(player)
	if state.completed == true then
		return state
	end

	local normalizedNextStepId = TutorialConfig.NormalizeStepId(nextStepId)
	if getStepIndex(normalizedNextStepId) <= getStepIndex(state.stepId) then
		return state
	end

	state.stepId = normalizedNextStepId
	if normalizedNextStepId == TutorialConfig.Steps.Completed then
		state.completed = true
	end
	return setState(player, state)
end

function TutorialService:IsTutorialIncomplete(player: Player): boolean
	if not isActive(player) then
		return false
	end
	return getState(player).completed ~= true
end

function TutorialService:GetState(player: Player): TutorialState.TutorialStateValue
	if not isActive(player) then
		return TutorialState.CreateCompletedState()
	end

	self:RefreshProgress(player)
	return getState(player)
end

function TutorialService:RefreshProgress(player: Player): TutorialState.TutorialStateValue
	if not isActive(player) then
		return TutorialState.CreateCompletedState()
	end

	local state = getState(player)
	if state.completed == true then
		return state
	end

	local changed = true
	while changed do
		changed = false
		local stepId = state.stepId
		if state.adminReplay == true then
			break
		end

		if (stepId == TutorialConfig.Steps.Welcome or stepId == TutorialConfig.Steps.RollFree)
			and DataService:GetSuccessfulRollCount(player) > 0
		then
			state.stepId = TutorialConfig.Steps.EquipBodyPart
			changed = true
		elseif stepId == TutorialConfig.Steps.EquipBodyPart and hasAnyEquippedBodyPart(player) then
			state.stepId = TutorialConfig.Steps.SelectRoll2
			changed = true
		elseif stepId == TutorialConfig.Steps.SelectRoll2 and DataService:GetSelectedRollType(player) == TutorialConfig.TargetRollTypeId then
			state.stepId = TutorialConfig.Steps.PaidRolls
			changed = true
		elseif stepId == TutorialConfig.Steps.PaidRolls and state.paidRollCount >= TutorialConfig.PaidRollGoal then
			state.stepId = TutorialConfig.Steps.GoAppraise
			changed = true
		elseif stepId == TutorialConfig.Steps.GoCrafting and isTargetAutoCraftEnabled(player) then
			state.stepId = TutorialConfig.Steps.CraftHolidayCrown
			changed = true
		elseif stepId == TutorialConfig.Steps.CraftHolidayCrown and ownsTargetAccessory(player) then
			state.stepId = TutorialConfig.Steps.EquipHolidayCrown
			changed = true
		elseif stepId == TutorialConfig.Steps.EquipHolidayCrown and hasEquippedTargetAccessory(player) then
			state.stepId = TutorialConfig.Steps.ClaimDailyChest
			changed = true
		elseif stepId == TutorialConfig.Steps.ClaimDailyChest and state.tutorialChestClaimed == true then
			state.stepId = TutorialConfig.Steps.UseLuckPotion
			changed = true
		end
	end

	return setState(player, state)
end

function TutorialService:GetRollOverride(player: Player, context: any): any?
	if not isActive(player) then
		return nil
	end

	local state = getState(player)
	if state.completed == true then
		return nil
	end

	local rollTypeId = if typeof(context) == "table" then context.rollTypeId else nil
	local override = {}
	if state.stepId == TutorialConfig.Steps.PaidRolls
		and rollTypeId == TutorialConfig.TargetRollTypeId
		and state.luckBoostConsumed ~= true
	then
		override.rawLuckBonus = TutorialConfig.LuckBoostRawBonus
		override.luckBoostPercent = TutorialConfig.LuckBoostPercent
	end

	if state.stepId == TutorialConfig.Steps.CraftHolidayCrown
		and isTargetAutoCraftEnabled(player)
		and ownsTargetAccessory(player) ~= true
	then
		local craftGoal = resolveTargetCraftGoal(player)
		if typeof(craftGoal) == "table" and craftGoal.ready ~= true and typeof(craftGoal.ingredientKey) == "string" then
			if typeof(craftGoal.forcedPieceId) == "string" then
				override.forcedPieceId = craftGoal.forcedPieceId
			end
			if typeof(craftGoal.forcedSetId) == "string" then
				override.forcedSetId = craftGoal.forcedSetId
			end
			override.forceAutoCraftRecipeId = craftGoal.recipeId or TutorialConfig.TargetRecipeId
			override.targetIngredientKey = craftGoal.ingredientKey
		end
	end

	return if next(override) ~= nil then override else nil
end

function TutorialService:ShouldWaiveCraftCost(player: Player, recipeId: string): boolean
	if not isActive(player) then
		return false
	end

	local state = getState(player)
	local craftGoal = resolveTargetCraftGoal(player)
	return state.completed ~= true
		and state.stepId == TutorialConfig.Steps.CraftHolidayCrown
		and CraftingRecipeConfig.NormalizeId(recipeId) == TutorialConfig.TargetRecipeId
		and typeof(craftGoal) == "table"
		and craftGoal.ready == true
end

function TutorialService:RecordRollResult(player: Player, result: any)
	if not isActive(player) or typeof(result) ~= "table" then
		return
	end

	local state = getState(player)
	if state.completed == true then
		return
	end

	if state.stepId == TutorialConfig.Steps.Welcome or state.stepId == TutorialConfig.Steps.RollFree then
		advanceTo(player, TutorialConfig.Steps.EquipBodyPart)
		TutorialAnalyticsService:LogOnboardingStep(player, 3, state)
		return
	end

	if state.stepId == TutorialConfig.Steps.PaidRolls and result.rollTypeId == TutorialConfig.TargetRollTypeId then
		if state.luckBoostConsumed ~= true then
			state.luckBoostConsumed = true
		end
		state.paidRollCount = math.min(TutorialConfig.PaidRollGoal, state.paidRollCount + 1)
		if state.paidRollCount >= TutorialConfig.PaidRollGoal then
			state.stepId = TutorialConfig.Steps.GoAppraise
			TutorialAnalyticsService:LogOnboardingStep(player, 6, state)
		end
		setState(player, state)
		return
	end

	if state.stepId == TutorialConfig.Steps.CraftHolidayCrown then
		if isTargetAutoCraftEnabled(player) then
			state.craftGuaranteeRollCount = math.min(
				TutorialConfig.CraftGuaranteeMaxRolls,
				state.craftGuaranteeRollCount + 1
			)
		end
		if ownsTargetAccessory(player) then
			state.stepId = TutorialConfig.Steps.EquipHolidayCrown
		end
		setState(player, state)
	end
end

function TutorialService:RecordRollTypeSelected(player: Player, rollTypeId: string)
	local state = getState(player)
	if state.stepId == TutorialConfig.Steps.SelectRoll2 and rollTypeId == TutorialConfig.TargetRollTypeId then
		advanceTo(player, TutorialConfig.Steps.PaidRolls)
		TutorialAnalyticsService:LogOnboardingStep(player, 5, state)
	end
end

function TutorialService:RecordBodyPartEquipped(player: Player, _payload: any?)
	local state = getState(player)
	if state.stepId == TutorialConfig.Steps.EquipBodyPart then
		advanceTo(player, TutorialConfig.Steps.SelectRoll2)
		TutorialAnalyticsService:LogOnboardingStep(player, 4, state)
	end
end

function TutorialService:GetAppraisalOverride(player: Player, _context: any?): any?
	if not isActive(player) then
		return nil
	end

	local state = getState(player)
	if state.completed == true
		or state.stepId ~= TutorialConfig.Steps.GoAppraise
		or state.appraisalGuaranteeConsumed == true
	then
		return nil
	end

	return {
		sizeId = TutorialConfig.AppraisalGuaranteedSizeId,
	}
end

function TutorialService:ShouldWaiveAppraisalCost(player: Player): boolean
	if not isActive(player) then
		return false
	end

	local state = getState(player)
	return state.completed ~= true and state.stepId == TutorialConfig.Steps.GoAppraise
end

function TutorialService:RecordAppraisalResult(player: Player, result: any)
	if not isActive(player) or typeof(result) ~= "table" then
		return
	end

	local state = getState(player)
	if state.completed == true or state.stepId ~= TutorialConfig.Steps.GoAppraise then
		return
	end

	if result.sizeId == TutorialConfig.AppraisalGuaranteedSizeId then
		state.appraisalGuaranteeConsumed = true
		state.stepId = TutorialConfig.Steps.GoCrafting
		TutorialAnalyticsService:LogOnboardingStep(player, 7, state)
		setState(player, state)
	end
end

function TutorialService:RecordAutoCraftChanged(player: Player, recipeId: string, enabled: boolean)
	local state = getState(player)
	if state.stepId == TutorialConfig.Steps.GoCrafting
		and recipeId == TutorialConfig.TargetRecipeId
		and enabled == true
	then
		advanceTo(player, TutorialConfig.Steps.CraftHolidayCrown)
		TutorialAnalyticsService:LogOnboardingStep(player, 8, state)
	end
end

function TutorialService:RecordCraftResult(player: Player, recipeId: string, result: any?)
	local state = getState(player)
	if state.stepId ~= TutorialConfig.Steps.CraftHolidayCrown or recipeId ~= TutorialConfig.TargetRecipeId then
		return
	end
	if typeof(result) == "table" and result.kind == "accessory" then
		advanceTo(player, TutorialConfig.Steps.EquipHolidayCrown)
		TutorialAnalyticsService:LogOnboardingStep(player, 9, state)
	end
end

function TutorialService:RecordAccessoryEquipped(player: Player, payload: any?)
	local state = getState(player)
	if state.stepId ~= TutorialConfig.Steps.EquipHolidayCrown
		or typeof(payload) ~= "table"
		or payload.accessoryId ~= TutorialConfig.TargetAccessoryId
	then
		return
	end

	advanceTo(player, TutorialConfig.Steps.ClaimDailyChest)
	TutorialAnalyticsService:LogOnboardingStep(player, 10, state)
end

function TutorialService:RecordPotionUsed(player: Player, potionId: string)
	if potionId ~= TutorialConfig.TutorialPotionId then
		return
	end

	local state = getState(player)
	if state.completed == true or state.stepId ~= TutorialConfig.Steps.UseLuckPotion then
		return
	end

	TutorialAnalyticsService:LogOnboardingStep(player, 12, state)
	state.completed = true
	state.stepId = TutorialConfig.Steps.Completed
	state.adminReplay = false
	setState(player, state)
end

function TutorialService:StartTutorialForAdmin(player: Player, stepId: string?): TutorialState.TutorialStateValue
	if not isActive(player) then
		return TutorialState.CreateCompletedState()
	end

	local state = TutorialState.CreateEmptyState()
	state.stepId = TutorialConfig.NormalizeStepId(stepId)
	if state.stepId == TutorialConfig.Steps.Completed then
		state = TutorialState.CreateCompletedState()
	else
		state.completed = false
		state.adminReplay = true
	end
	return setState(player, state)
end

function TutorialService:ClaimTutorialChest(player: Player, payload: any)
	if not isActive(player) then
		return response(false, "Player data is not loaded.", TutorialState.CreateCompletedState())
	end

	local state = self:RefreshProgress(player)
	if state.completed == true then
		return response(false, "Tutorial is already complete.", state)
	end
	if state.stepId ~= TutorialConfig.Steps.ClaimDailyChest then
		return response(false, "The tutorial chest is not ready yet.", state)
	end
	if state.tutorialChestClaimed == true then
		return response(false, "The tutorial chest has already been claimed.", state)
	end

	local DailyChestService = require(script.Parent.DailyChestService)
	local result = DailyChestService:ClaimTutorialDailyChest(player, {
		chestId = TutorialConfig.TutorialChestId,
		potionId = TutorialConfig.TutorialPotionId,
		localUtcOffsetMinutes = if typeof(payload) == "table" then payload.localUtcOffsetMinutes else nil,
		ignoreDailyClaimedToday = true,
	})
	if typeof(result) ~= "table" or result.ok ~= true then
		return response(false, tostring(result and result.message or "Failed to claim tutorial chest."), state)
	end

	state.tutorialChestClaimed = true
	state.stepId = TutorialConfig.Steps.UseLuckPotion
	TutorialAnalyticsService:LogOnboardingStep(player, 11, state)
	state = setState(player, state)
	return response(true, DailyChestConfig.GetReturnMessage(TutorialConfig.TutorialChestId), state, {
		chests = result.chests or {},
	})
end

function TutorialService:AdvanceTutorialStep(player: Player, payload: any)
	if not isActive(player) then
		return response(false, "Player data is not loaded.", TutorialState.CreateCompletedState())
	end
	if not RequestLimiter:Allow(player, "remote.tutorial.advance") then
		return response(false, "You're advancing tutorial too quickly.", getState(player))
	end

	local requestedStepId = if typeof(payload) == "table" then payload.stepId else nil
	local state = self:RefreshProgress(player)
	if state.stepId == TutorialConfig.Steps.Welcome and requestedStepId == TutorialConfig.Steps.RollFree then
		state = advanceTo(player, TutorialConfig.Steps.RollFree)
		TutorialAnalyticsService:LogOnboardingStep(player, 2, state)
		return response(true, "Tutorial started.", state)
	end

	if typeof(requestedStepId) == "string" and TutorialConfig.GetStepIndex(requestedStepId) <= TutorialConfig.GetStepIndex(state.stepId) then
		return response(true, "Tutorial state refreshed.", state)
	end

	return response(true, "Tutorial state refreshed.", state)
end

function TutorialService:OnStart()
	local folder = ensureTutorialFolder()
	getStateRemote = createOrGetRemoteFunction(folder, GET_STATE_REMOTE_NAME)
	advanceRemote = createOrGetRemoteFunction(folder, ADVANCE_REMOTE_NAME)
	claimChestRemote = createOrGetRemoteFunction(folder, CLAIM_CHEST_REMOTE_NAME)
	updatedRemote = createOrGetRemoteEvent(folder, UPDATED_REMOTE_NAME)

	getStateRemote.OnServerInvoke = function(player: Player)
		if not RequestLimiter:Allow(player, "remote.tutorial.get_state") then
			return response(false, "You're refreshing tutorial too quickly.", getState(player))
		end

		return response(true, "Loaded tutorial state.", self:GetState(player))
	end

	advanceRemote.OnServerInvoke = function(player: Player, payload: any)
		return self:AdvanceTutorialStep(player, payload)
	end

	claimChestRemote.OnServerInvoke = function(player: Player, payload: any)
		if not RequestLimiter:Allow(player, "remote.tutorial.claim_chest") then
			return response(false, "You're claiming tutorial chest too quickly.", getState(player))
		end

		return self:ClaimTutorialChest(player, payload)
	end
end

function TutorialService:OnPlayerAdded(player: Player)
	if not isActive(player) then
		return
	end
	local state = getState(player)
	if state.completed ~= true then
		TutorialAnalyticsService:LogOnboardingStep(player, 1, state)
	end
	self:RefreshProgress(player)
end

return TutorialService
