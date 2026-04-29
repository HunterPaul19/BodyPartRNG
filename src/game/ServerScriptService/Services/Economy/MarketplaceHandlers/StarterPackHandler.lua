local ReplicatedStorage = game:GetService("ReplicatedStorage")

local STARTER_PACK_SOURCE = "marketplace_starter_pack"
local FOUNDER_ACHIEVEMENT_ID = "starter_pack_founder"
local BODY_PART_GRANT_OPTIONS = table.freeze({
	ignoreInventoryLimit = true,
})

local POTION_REWARDS = table.freeze({
	"luck3",
	"rollSpeed3",
	"money3",
})

local StarterPackHandler = {}
local bodyPartsCatalog = nil
local potionConfig = nil
local rollingConfig = nil
local rollMath = nil
local dataService = nil
local achievementService = nil

local function getBodyPartsCatalog()
	if bodyPartsCatalog == nil then
		bodyPartsCatalog = require(ReplicatedStorage.Shared.Config.BodyParts.Catalog)
	end
	return bodyPartsCatalog
end

local function getPotionConfig()
	if potionConfig == nil then
		potionConfig = require(ReplicatedStorage.Shared.Config.PotionConfig)
	end
	return potionConfig
end

local function getRollingConfig()
	if rollingConfig == nil then
		rollingConfig = require(ReplicatedStorage.Shared.Config.RollingConfig)
	end
	return rollingConfig
end

local function getRollMath()
	if rollMath == nil then
		rollMath = require(ReplicatedStorage.Shared.Rolling.RollMath)
	end
	return rollMath
end

local function getDataService()
	if dataService == nil then
		dataService = require(script.Parent.Parent.DataService)
	end
	return dataService
end

local function getAchievementService()
	if achievementService == nil then
		achievementService = require(script.Parent.Parent.AchievementService)
	end
	return achievementService
end

local function buildRollEntryBySetId()
	local bySetId = {}
	for _, rollEntry in ipairs(getBodyPartsCatalog().GetRollEntries()) do
		bySetId[rollEntry.id] = rollEntry
	end
	return bySetId
end

local function buildRewardPool(displayRarity: string)
	local rollEntryBySetId = buildRollEntryBySetId()
	local pool = {}

	for _, piece in ipairs(getBodyPartsCatalog().GetRollEligiblePieces()) do
		local setConfig = getBodyPartsCatalog().GetSetForPiece(piece.id)
		local rollEntry = if setConfig then rollEntryBySetId[setConfig.id] else nil
		if setConfig and rollEntry then
			local normalizedRarity = getRollingConfig().NormalizeDisplayRarity(setConfig.rollDisplay.rarity)
			if normalizedRarity == displayRarity then
				table.insert(pool, {
					piece = piece,
					setConfig = setConfig,
					rollEntry = rollEntry,
				})
			end
		end
	end

	return pool
end

local function removePieceFromPool(pool: { any }, pieceId: string)
	for index = #pool, 1, -1 do
		if pool[index].piece.id == pieceId then
			table.remove(pool, index)
		end
	end
end

local function selectRewardEntries(displayRarity: string, amount: number, randomSource: Random)
	local pool = buildRewardPool(displayRarity)
	if #pool < amount then
		return nil, string.format("Starter Pack needs %d %s body parts, but only %d are configured.", amount, displayRarity, #pool)
	end

	local selected = table.create(amount)
	for _ = 1, amount do
		local index = randomSource:NextInteger(1, #pool)
		local entry = pool[index]
		table.insert(selected, entry)
		removePieceFromPool(pool, entry.piece.id)
	end

	return selected, nil
end

local function buildGrantPayload(entry: any)
	local piece = entry.piece
	local setConfig = entry.setConfig
	local rollEntry = entry.rollEntry
	local resolvedRollMath = getRollMath()
	local displayedDenominator = math.max(
		1,
		math.floor(tonumber(rollEntry.displayedDenominator) or tonumber(setConfig.rollDisplay.chance) or piece.rarity or 1)
	)
	local variantMultiplier = resolvedRollMath.ComputeVariantMultiplier(1, 1)

	return {
		pieceId = piece.id,
		rarityDenominator = displayedDenominator,
		rolledSetId = setConfig.id,
		rolledSetDisplayName = setConfig.rollDisplay.displayName,
		displayOddsDenominator = displayedDenominator,
		displayRarity = setConfig.rollDisplay.rarity,
		mutationId = "none",
		mutation = "None",
		mutationMultiplier = 1,
		sizeId = "normal",
		sizeMultiplier = 1,
		variantMultiplier = variantMultiplier,
		finalPassiveIncomePerSecond = resolvedRollMath.ComputeFinalPassiveIncome(piece.passiveIncomePerSecond, variantMultiplier),
	}
end

local function grantBodyPartRewards(player: Player): (boolean, string?)
	local randomSource = Random.new()
	local cleanEntries, cleanError = selectRewardEntries("Clean", 5, randomSource)
	if not cleanEntries then
		return false, cleanError
	end

	local primeEntries, primeError = selectRewardEntries("Prime", 1, randomSource)
	if not primeEntries then
		return false, primeError
	end

	for _, entry in ipairs(cleanEntries) do
		local _, grantError = getDataService():AddOwnedBodyPart(player, buildGrantPayload(entry), BODY_PART_GRANT_OPTIONS)
		if grantError ~= nil then
			return false, grantError
		end
	end

	for _, entry in ipairs(primeEntries) do
		local _, grantError = getDataService():AddOwnedBodyPart(player, buildGrantPayload(entry), BODY_PART_GRANT_OPTIONS)
		if grantError ~= nil then
			return false, grantError
		end
	end

	return true, nil
end

local function grantPotionRewards(player: Player): (boolean, string?)
	for _, potionId in ipairs(POTION_REWARDS) do
		local config = getPotionConfig().Get(potionId)
		if not config then
			return false, string.format("Starter Pack potion reward '%s' is not configured.", tostring(potionId))
		end

		local _, potionError = getDataService():AddOwnedPotionUses(player, config.id, 1)
		if potionError ~= nil then
			return false, potionError
		end
	end

	return true, nil
end

function StarterPackHandler.grant(player: Player, _context: any): (boolean, string?)
	local bodyPartsGranted, bodyPartError = grantBodyPartRewards(player)
	if not bodyPartsGranted then
		return false, bodyPartError
	end

	getDataService():AdjustTimeShardsBalance(player, 100, STARTER_PACK_SOURCE)
	getDataService():AddMoney(player, 25000, STARTER_PACK_SOURCE)

	local potionsGranted, potionError = grantPotionRewards(player)
	if not potionsGranted then
		return false, potionError
	end

	local titleGranted, titleError = getAchievementService():GrantDirectAward(player, FOUNDER_ACHIEVEMENT_ID)
	if not titleGranted then
		return false, titleError or "Failed to unlock Founder title."
	end

	player:SetAttribute("StarterPackOwned", true)
	return true, nil
end

function StarterPackHandler.reconcileOnJoin(player: Player, context: any)
	player:SetAttribute("StarterPackOwned", typeof(context) == "table" and context.isOwned == true)
end

return StarterPackHandler
