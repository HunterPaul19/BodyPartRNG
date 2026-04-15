local PremiumBenefits = {}

PremiumBenefits.Tiers = {
	none = "",
	vip = "vip",
	vip_plus = "vip_plus",
}

PremiumBenefits.Tags = {
	vip = "[VIP]",
	vip_plus = "[VIP+]",
}

PremiumBenefits.Colors = {
	vip = "#ff8c00",
	vip_plus = "#38d7ff",
}

PremiumBenefits.LuckMultipliers = {
	vip = 1.2,
	vip_plus = 1.2,
	combined = 1.3,
}

PremiumBenefits.MovementSpeedMultipliers = {
	vip = 1.10,
	vip_plus = 1.15,
}

function PremiumBenefits.NormalizeTier(value: any): string
	if value == true then
		return PremiumBenefits.Tiers.vip
	end
	if typeof(value) ~= "string" then
		return PremiumBenefits.Tiers.none
	end
	if value == PremiumBenefits.Tiers.vip or value == PremiumBenefits.Tiers.vip_plus then
		return value
	end

	return PremiumBenefits.Tiers.none
end

function PremiumBenefits.GetResolvedTier(hasVip: boolean, hasVipPlus: boolean): string
	if hasVipPlus == true then
		return PremiumBenefits.Tiers.vip_plus
	end
	if hasVip == true then
		return PremiumBenefits.Tiers.vip
	end

	return PremiumBenefits.Tiers.none
end

function PremiumBenefits.GetState(hasVip: boolean, hasVipPlus: boolean): any
	local resolvedTier = PremiumBenefits.GetResolvedTier(hasVip, hasVipPlus)
	local luckMultiplier = 1
	if hasVip == true and hasVipPlus == true then
		luckMultiplier = PremiumBenefits.LuckMultipliers.combined
	elseif hasVip == true then
		luckMultiplier = PremiumBenefits.LuckMultipliers.vip
	elseif hasVipPlus == true then
		luckMultiplier = PremiumBenefits.LuckMultipliers.vip_plus
	end

	local movementSpeedMultiplier = 1
	if hasVipPlus == true then
		movementSpeedMultiplier = PremiumBenefits.MovementSpeedMultipliers.vip_plus
	elseif hasVip == true then
		movementSpeedMultiplier = PremiumBenefits.MovementSpeedMultipliers.vip
	end

	local tagText = PremiumBenefits.Tags[resolvedTier] or ""

	return {
		hasVip = hasVip == true,
		hasVipPlus = hasVipPlus == true,
		premiumTag = resolvedTier,
		tagText = tagText,
		chatTagText = tagText,
		leaderboardTagText = tagText,
		colorHex = PremiumBenefits.Colors[resolvedTier] or "#ffffff",
		luckMultiplier = luckMultiplier,
		movementSpeedMultiplier = movementSpeedMultiplier,
	}
end

return table.freeze(PremiumBenefits)
