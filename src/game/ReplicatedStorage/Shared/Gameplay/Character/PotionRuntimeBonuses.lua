local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)

local PotionRuntimeBonuses = {}

export type MutationChanceBonusById = { [string]: number }

export type RuntimeBonuses = {
	passiveIncomeMultiplier: number,
	luckBonus: number,
	luckMultiplier: number,
	sizeLuckBonus: number,
	rollSpeedBonus: number,
	mutationChanceBonusById: MutationChanceBonusById,
	bodyPartScaleOverride: number?,
}

local DEFAULT_MUTATION_ID = MutationConfig.GetDefault().id

local function normalizeBonusValue(value: any): number?
	local resolvedValue = tonumber(value)
	if resolvedValue == nil or resolvedValue <= 0 then
		return nil
	end

	return resolvedValue
end

function PotionRuntimeBonuses.CloneMutationChanceBonusById(source: any): MutationChanceBonusById
	local cloned = {}
	if typeof(source) ~= "table" then
		return cloned
	end

	for mutationId, bonusValue in pairs(source) do
		local normalizedMutationId = MutationConfig.NormalizeId(mutationId)
		local resolvedBonusValue = normalizeBonusValue(bonusValue)
		if normalizedMutationId ~= DEFAULT_MUTATION_ID and resolvedBonusValue ~= nil then
			cloned[normalizedMutationId] = (cloned[normalizedMutationId] or 0) + resolvedBonusValue
		end
	end

	return cloned
end

function PotionRuntimeBonuses.CreateEmpty(): RuntimeBonuses
	return {
		passiveIncomeMultiplier = 1,
		luckBonus = 0,
		luckMultiplier = 1,
		sizeLuckBonus = 0,
		rollSpeedBonus = 0,
		mutationChanceBonusById = {},
		bodyPartScaleOverride = nil,
	}
end

function PotionRuntimeBonuses.ApplyConfigBonuses(bonuses: RuntimeBonuses, config: any)
	if typeof(config) ~= "table" then
		return bonuses
	end

	local passiveIncomeMultiplier = normalizeBonusValue(config.passiveIncomeMultiplier)
	if passiveIncomeMultiplier ~= nil and passiveIncomeMultiplier > 1 then
		bonuses.passiveIncomeMultiplier += passiveIncomeMultiplier - 1
	end

	bonuses.luckBonus += tonumber(config.luckBonus) or 0
	local luckMultiplier = normalizeBonusValue(config.luckMultiplier)
	if luckMultiplier ~= nil and luckMultiplier > 1 then
		bonuses.luckMultiplier = math.max(1, tonumber(bonuses.luckMultiplier) or 1) * luckMultiplier
	end
	bonuses.sizeLuckBonus += tonumber(config.sizeLuckBonus) or 0
	bonuses.rollSpeedBonus += tonumber(config.rollSpeedBonus) or 0

	for mutationId, bonusValue in pairs(PotionRuntimeBonuses.CloneMutationChanceBonusById(config.mutationChanceBonusById)) do
		bonuses.mutationChanceBonusById[mutationId] = (bonuses.mutationChanceBonusById[mutationId] or 0) + bonusValue
	end

	local bodyPartScaleOverride = normalizeBonusValue(config.bodyPartScaleOverride)
	if bodyPartScaleOverride ~= nil then
		local currentOverride = normalizeBonusValue(bonuses.bodyPartScaleOverride)
		bonuses.bodyPartScaleOverride = math.max(currentOverride or 0, bodyPartScaleOverride)
	end

	return bonuses
end

return table.freeze(PotionRuntimeBonuses)
