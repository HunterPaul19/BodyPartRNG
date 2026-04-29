local DailyChestConfig = {}

export type WeightedPotionTier = {
	tier: number,
	chance: number,
}

export type WeightedMaterialTier = {
	tier: "Common" | "Rare" | "Epic",
	chance: number,
}

export type ChestConfig = {
	id: string,
	displayName: string,
	visualChestId: string,
	timeShardRange: { min: number, max: number },
	incomeMinutesRange: { min: number, max: number },
	potionChances: { WeightedPotionTier },
	materialSlotCount: number,
	materialTierOdds: { WeightedMaterialTier },
	bossPool: { string }?,
}

DailyChestConfig.TimeShardIconTexture = "rbxassetid://109541558389249"

local CHEST_ORDER = table.freeze({
	"DailyFree",
	"VIP",
	"VIPPlus",
})

local CHESTS_BY_ID: { [string]: ChestConfig } = {
	DailyFree = table.freeze({
		id = "DailyFree",
		displayName = "Daily Free Chest",
		visualChestId = "Basic",
		timeShardRange = table.freeze({ min = 10, max = 25 }),
		incomeMinutesRange = table.freeze({ min = 10, max = 25 }),
		potionChances = table.freeze({
			table.freeze({ tier = 3, chance = 0.35 }),
			table.freeze({ tier = 4, chance = 0.03 }),
			table.freeze({ tier = 1, chance = 0.31 }),
			table.freeze({ tier = 2, chance = 0.31 }),
		}),
		materialSlotCount = 2,
		materialTierOdds = table.freeze({
			table.freeze({ tier = "Common", chance = 0.88 }),
			table.freeze({ tier = "Rare", chance = 0.11 }),
			table.freeze({ tier = "Epic", chance = 0.01 }),
		}),
		bossPool = table.freeze({
			"Flame Guard General",
			"Captain Squid",
		}),
	}),
	VIP = table.freeze({
		id = "VIP",
		displayName = "VIP Chest",
		visualChestId = "VIP",
		timeShardRange = table.freeze({ min = 25, max = 50 }),
		incomeMinutesRange = table.freeze({ min = 25, max = 50 }),
		potionChances = table.freeze({
			table.freeze({ tier = 3, chance = 0.60 }),
			table.freeze({ tier = 4, chance = 0.20 }),
			table.freeze({ tier = 1, chance = 0.10 }),
			table.freeze({ tier = 2, chance = 0.10 }),
		}),
		materialSlotCount = 5,
		materialTierOdds = table.freeze({
			table.freeze({ tier = "Common", chance = 0.75 }),
			table.freeze({ tier = "Rare", chance = 0.22 }),
			table.freeze({ tier = "Epic", chance = 0.03 }),
		}),
	}),
	VIPPlus = table.freeze({
		id = "VIPPlus",
		displayName = "VIP+ Chest",
		visualChestId = "VIP+",
		timeShardRange = table.freeze({ min = 50, max = 100 }),
		incomeMinutesRange = table.freeze({ min = 50, max = 100 }),
		potionChances = table.freeze({
			table.freeze({ tier = 3, chance = 1.00 }),
			table.freeze({ tier = 4, chance = 0.35 }),
			table.freeze({ tier = 5, chance = 0.05 }),
		}),
		materialSlotCount = 10,
		materialTierOdds = table.freeze({
			table.freeze({ tier = "Common", chance = 0.65 }),
			table.freeze({ tier = "Rare", chance = 0.30 }),
			table.freeze({ tier = "Epic", chance = 0.05 }),
		}),
	}),
}

function DailyChestConfig.Get(chestId: string): ChestConfig?
	if typeof(chestId) ~= "string" or chestId == "" then
		return nil
	end

	return CHESTS_BY_ID[chestId]
end

function DailyChestConfig.GetOrderedChestIds(): { string }
	local results = table.create(#CHEST_ORDER)
	for index, chestId in ipairs(CHEST_ORDER) do
		results[index] = chestId
	end
	return results
end

function DailyChestConfig.GetAll(): { ChestConfig }
	local results = {}
	for _, chestId in ipairs(CHEST_ORDER) do
		local config = CHESTS_BY_ID[chestId]
		if config then
			table.insert(results, config)
		end
	end
	return results
end

function DailyChestConfig.GetEligibleChestIds(hasVip: boolean, hasVipPlus: boolean): { string }
	local eligible = { "DailyFree" }
	if hasVip == true then
		table.insert(eligible, "VIP")
	end
	if hasVipPlus == true then
		table.insert(eligible, "VIPPlus")
	end
	return eligible
end

return table.freeze(DailyChestConfig)
