local SizeConfig = {}

export type SizeEntry = {
	id: string,
	displayName: string,
	weight: number,
	multiplier: number,
}

local ORDERED: { SizeEntry } = {
	{
		id = "compact",
		displayName = "Compact",
		weight = 12,
		multiplier = 0.95,
	},
	{
		id = "normal",
		displayName = "Normal",
		weight = 72,
		multiplier = 1.0,
	},
	{
		id = "large",
		displayName = "Large",
		weight = 12,
		multiplier = 1.08,
	},
	{
		id = "massive",
		displayName = "Massive",
		weight = 3.2,
		multiplier = 1.18,
	},
	{
		id = "titanic",
		displayName = "Titanic",
		weight = 0.8,
		multiplier = 1.3,
	},
}

local BY_ID: { [string]: SizeEntry } = {}
local FROZEN_ORDERED = table.create(#ORDERED)

for index, entry in ipairs(ORDERED) do
	local frozen = table.freeze(table.clone(entry))
	BY_ID[frozen.id] = frozen
	FROZEN_ORDERED[index] = frozen
end

table.freeze(BY_ID)
table.freeze(FROZEN_ORDERED)

function SizeConfig.Get(id: string): SizeEntry?
	return BY_ID[id]
end

function SizeConfig.GetOrdered(): { SizeEntry }
	return FROZEN_ORDERED
end

function SizeConfig.GetDefault(): SizeEntry
	return BY_ID.normal
end

function SizeConfig.NormalizeId(value: any): string
	if typeof(value) == "string" and BY_ID[value] then
		return value
	end

	return SizeConfig.GetDefault().id
end

function SizeConfig.GetMultiplier(id: any): number
	local entry = BY_ID[SizeConfig.NormalizeId(id)] or SizeConfig.GetDefault()
	return entry.multiplier
end

return table.freeze(SizeConfig)
