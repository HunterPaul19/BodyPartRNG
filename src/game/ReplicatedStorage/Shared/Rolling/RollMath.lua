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
	local cycleLength = safeInterval + 1
	local safeSuccessfulRollCount = math.max(0, math.floor(tonumber(successfulRollCount) or 0))
	return safeSuccessfulRollCount % cycleLength == safeInterval
end

function RollMath.GetBonusChargeProgress(successfulRollCount: number, interval: number): number
	local safeInterval = math.max(1, math.floor(tonumber(interval) or 1))
	local cycleLength = safeInterval + 1
	local safeSuccessfulRollCount = math.max(0, math.floor(tonumber(successfulRollCount) or 0))
	return safeSuccessfulRollCount % cycleLength
end

function RollMath.IsBonusReady(successfulRollCount: number, interval: number): boolean
	local safeInterval = math.max(1, math.floor(tonumber(interval) or 1))
	return RollMath.GetBonusChargeProgress(successfulRollCount, safeInterval) == safeInterval
end

function RollMath.GetEffectiveLuck(rawLuck: number, rarityEffectiveness: number): number
	local safeRawLuck = math.max(0, tonumber(rawLuck) or 0)
	local safeEffectiveness = math.clamp(tonumber(rarityEffectiveness) or 0, 0, 1)
	return 1 + (safeRawLuck - 1) * safeEffectiveness
end

function RollMath.GetAdjustedWeight(baseChance: number, effectiveLuck: number): number
	local safeBaseChance = math.max(0, tonumber(baseChance) or 0)
	local safeEffectiveLuck = math.max(0, tonumber(effectiveLuck) or 0)
	return safeBaseChance * safeEffectiveLuck
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

function RollMath.ComputeVariantMultiplier(mutationMultiplier: number, sizeMultiplier: number): number
	return math.max(0, (tonumber(mutationMultiplier) or 1) + (tonumber(sizeMultiplier) or 1) - 1)
end

function RollMath.ComputeFinalPassiveIncome(basePassiveIncomePerSecond: number, variantMultiplier: number): number
	return math.max(0, (tonumber(basePassiveIncomePerSecond) or 0) * math.max(0, tonumber(variantMultiplier) or 0))
end

return table.freeze(RollMath)
