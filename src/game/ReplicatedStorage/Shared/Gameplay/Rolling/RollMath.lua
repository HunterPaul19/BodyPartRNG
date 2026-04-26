local RollMath = {}

export type WeightedEntry = {
	id: string,
	weight: number,
	[any]: any,
}

function RollMath.RebuildExactBaseChances<T>(orderedEntries: { T }, getDisplayedDenominator: (T) -> number): { T & { baseChance: number, displayedDenominator: number } }
	local rebuilt = table.create(#orderedEntries)

	for index, entry in ipairs(orderedEntries) do
		local displayedDenominator = math.max(1, tonumber(getDisplayedDenominator(entry)) or 1)
		local displayedChance = 1 / displayedDenominator
		local nextEntry = orderedEntries[index + 1]
		local nextDisplayedChance = 0

		if nextEntry ~= nil then
			local nextDisplayedDenominator = math.max(1, tonumber(getDisplayedDenominator(nextEntry)) or 1)
			nextDisplayedChance = 1 / nextDisplayedDenominator
		end

		local baseChance = math.max(0, displayedChance - nextDisplayedChance)
		local copy = table.clone(entry)
		copy.displayedDenominator = displayedDenominator
		copy.baseChance = baseChance
		rebuilt[index] = copy
	end

	return rebuilt
end

function RollMath.IsBonusRoll(successfulRollCount: number, interval: number): boolean
	local safeInterval = math.max(1, math.floor(tonumber(interval) or 1))
	local safeSuccessfulRollCount = math.max(0, math.floor(tonumber(successfulRollCount) or 0))
	return safeSuccessfulRollCount % safeInterval == safeInterval - 1
end

function RollMath.GetBonusChargeProgress(successfulRollCount: number, interval: number): number
	local safeInterval = math.max(1, math.floor(tonumber(interval) or 1))
	local safeSuccessfulRollCount = math.max(0, math.floor(tonumber(successfulRollCount) or 0))
	return safeSuccessfulRollCount % safeInterval
end

function RollMath.IsBonusReady(successfulRollCount: number, interval: number): boolean
	local safeInterval = math.max(1, math.floor(tonumber(interval) or 1))
	return RollMath.GetBonusChargeProgress(successfulRollCount, safeInterval) == safeInterval - 1
end

function RollMath.GetListValue(baseValue: number, totalLuckCoefficient: number): number
	local safeBaseValue = math.max(1, tonumber(baseValue) or 1)
	local safeTotalLuckCoefficient = math.max(0.01, tonumber(totalLuckCoefficient) or 1)
	return math.max(0, math.floor(safeBaseValue / safeTotalLuckCoefficient))
end

function RollMath.RollDenominator(randomSource: Random, denominator: number): boolean
	local safeDenominator = math.max(1, math.floor(tonumber(denominator) or 1))
	return randomSource:NextInteger(1, safeDenominator) == 1
end

function RollMath.NormalizeWeights<T>(weightedEntries: { T }, getWeight: (T) -> number): ({ T & { probability: number } }, number)
	local normalized = table.create(#weightedEntries)
	local totalWeight = 0

	for _, entry in ipairs(weightedEntries) do
		totalWeight += math.max(0, tonumber(getWeight(entry)) or 0)
	end

	for index, entry in ipairs(weightedEntries) do
		local copy = table.clone(entry)
		local weight = math.max(0, tonumber(getWeight(entry)) or 0)
		copy.probability = if totalWeight > 0 then weight / totalWeight else 0
		normalized[index] = copy
	end

	return normalized, totalWeight
end

function RollMath.ChooseWeighted<T>(randomSource: Random, weightedEntries: { T }, getWeight: (T) -> number): T?
	local totalWeight = 0

	for _, entry in ipairs(weightedEntries) do
		totalWeight += math.max(0, tonumber(getWeight(entry)) or 0)
	end

	if totalWeight <= 0 then
		return nil
	end

	local threshold = randomSource:NextNumber(0, totalWeight)
	local running = 0

	for _, entry in ipairs(weightedEntries) do
		running += math.max(0, tonumber(getWeight(entry)) or 0)
		if threshold <= running then
			return entry
		end
	end

	return weightedEntries[#weightedEntries]
end

function RollMath.ApplyFlatWeightBonuses(weightedEntries: { WeightedEntry }, bonusById: any, neutralId: string?): { WeightedEntry }
	local adjustedEntries = table.create(#weightedEntries)
	local totalRequestedShift = 0
	local neutralEntry = nil

	for index, entry in ipairs(weightedEntries) do
		local copiedEntry = table.clone(entry)
		local bonusValue = if typeof(bonusById) == "table" then tonumber(bonusById[entry.id]) else nil
		if bonusValue and bonusValue > 0 then
			copiedEntry.weight = math.max(0, (tonumber(copiedEntry.weight) or 0) + bonusValue)
			totalRequestedShift += bonusValue
		end
		if neutralId ~= nil and entry.id == neutralId then
			neutralEntry = copiedEntry
		end
		adjustedEntries[index] = copiedEntry
	end

	if neutralEntry ~= nil and totalRequestedShift > 0 then
		neutralEntry.weight = math.max(0, (tonumber(neutralEntry.weight) or 0) - totalRequestedShift)
	end

	return adjustedEntries
end

function RollMath.ApplyDirectionalWeightShift(
	weightedEntries: { WeightedEntry },
	sourceIds: { string },
	targetIds: { string },
	shiftFraction: number
): { WeightedEntry }
	local resolvedShiftFraction = math.max(0, tonumber(shiftFraction) or 0)
	local adjustedEntries = table.create(#weightedEntries)
	if resolvedShiftFraction <= 0 then
		for index, entry in ipairs(weightedEntries) do
			adjustedEntries[index] = table.clone(entry)
		end
		return adjustedEntries
	end

	local sourceIdSet = {}
	for _, id in ipairs(sourceIds) do
		sourceIdSet[id] = true
	end

	local targetIdSet = {}
	for _, id in ipairs(targetIds) do
		targetIdSet[id] = true
	end

	local sourceTotalWeight = 0
	local targetTotalWeight = 0
	for _, entry in ipairs(weightedEntries) do
		local weight = math.max(0, tonumber(entry.weight) or 0)
		if sourceIdSet[entry.id] then
			sourceTotalWeight += weight
		elseif targetIdSet[entry.id] then
			targetTotalWeight += weight
		end
	end

	local shiftedWeight = math.min(sourceTotalWeight, sourceTotalWeight * resolvedShiftFraction)
	if shiftedWeight <= 0 or sourceTotalWeight <= 0 or targetTotalWeight <= 0 then
		for index, entry in ipairs(weightedEntries) do
			adjustedEntries[index] = table.clone(entry)
		end
		return adjustedEntries
	end

	for index, entry in ipairs(weightedEntries) do
		local copiedEntry = table.clone(entry)
		local weight = math.max(0, tonumber(copiedEntry.weight) or 0)
		if sourceIdSet[copiedEntry.id] then
			copiedEntry.weight = math.max(0, weight - (shiftedWeight * (weight / sourceTotalWeight)))
		elseif targetIdSet[copiedEntry.id] then
			copiedEntry.weight = weight + (shiftedWeight * (weight / targetTotalWeight))
		end
		adjustedEntries[index] = copiedEntry
	end

	return adjustedEntries
end

function RollMath.ComputeVariantMultiplier(mutationMultiplier: number, sizeMultiplier: number): number
	return math.max(0, (tonumber(mutationMultiplier) or 1) + (tonumber(sizeMultiplier) or 1) - 1)
end

function RollMath.ComputeFinalPassiveIncome(basePassiveIncomePerSecond: number, variantMultiplier: number): number
	return math.max(0, (tonumber(basePassiveIncomePerSecond) or 0) * math.max(0, tonumber(variantMultiplier) or 0))
end

return table.freeze(RollMath)
