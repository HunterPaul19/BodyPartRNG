local MutationConfig = {}

export type MutationEntry = {
	id: string,
	displayName: string,
	weight: number,
	multiplier: number,
}

local ORDERED: { MutationEntry } = {
	{
		id = "none",
		displayName = "None",
		weight = 72,
		multiplier = 1.0,
	},
	{
		id = "charged",
		displayName = "Charged",
		weight = 18,
		multiplier = 1.12,
	},
	{
		id = "prismatic",
		displayName = "Prismatic",
		weight = 7,
		multiplier = 1.28,
	},
	{
		id = "radiant",
		displayName = "Radiant",
		weight = 2.4,
		multiplier = 1.48,
	},
	{
		id = "celestial",
		displayName = "Celestial",
		weight = 0.6,
		multiplier = 1.75,
	},
}

local VISUALS = {
	Default = {},
}

local BY_ID: { [string]: MutationEntry } = {}
local BY_DISPLAY_NAME: { [string]: MutationEntry } = {}
local FROZEN_ORDERED = table.create(#ORDERED)

local function normalizeName(name: any): string?
	if typeof(name) ~= "string" then
		return nil
	end

	local trimmed = string.match(name, "%S.*%S") or string.match(name, "%S+")
	if not trimmed or trimmed == "" then
		return nil
	end

	return trimmed
end

for index, entry in ipairs(ORDERED) do
	local frozen = table.freeze(table.clone(entry))
	BY_ID[frozen.id] = frozen
	BY_DISPLAY_NAME[frozen.displayName] = frozen
	FROZEN_ORDERED[index] = frozen
end

table.freeze(BY_ID)
table.freeze(BY_DISPLAY_NAME)
table.freeze(FROZEN_ORDERED)

function MutationConfig.Get(id: string): MutationEntry?
	return BY_ID[id]
end

function MutationConfig.GetOrdered(): { MutationEntry }
	return FROZEN_ORDERED
end

function MutationConfig.GetDefault(): MutationEntry
	return BY_ID.none
end

function MutationConfig.NormalizeId(value: any): string
	if typeof(value) == "string" then
		if BY_ID[value] then
			return value
		end

		local normalized = normalizeName(value)
		local byDisplayName = normalized and BY_DISPLAY_NAME[normalized] or nil
		if byDisplayName then
			return byDisplayName.id
		end
	end

	return MutationConfig.GetDefault().id
end

function MutationConfig.NormalizeNames(input): { string }
	if typeof(input) == "string" then
		local entry = BY_ID[MutationConfig.NormalizeId(input)] or MutationConfig.GetDefault()
		return { entry.displayName }
	end

	if typeof(input) ~= "table" then
		return {}
	end

	local names = {}
	local seen = {}

	for _, value in ipairs(input) do
		local entry = BY_ID[MutationConfig.NormalizeId(value)] or MutationConfig.GetDefault()
		if not seen[entry.displayName] then
			seen[entry.displayName] = true
			table.insert(names, entry.displayName)
		end
	end

	return names
end

function MutationConfig.GetDisplayName(id: any): string
	local entry = BY_ID[MutationConfig.NormalizeId(id)] or MutationConfig.GetDefault()
	return entry.displayName
end

function MutationConfig.GetMultiplier(id: any): number
	local entry = BY_ID[MutationConfig.NormalizeId(id)] or MutationConfig.GetDefault()
	return entry.multiplier
end

function MutationConfig.GetVisual(name: string)
	return VISUALS[name] or VISUALS.Default
end

function MutationConfig.GetTextureVariant(name: string): string?
	local visual = MutationConfig.GetVisual(name)
	if typeof(visual) == "table" and typeof(visual.textureVariant) == "string" and visual.textureVariant ~= "" then
		return visual.textureVariant
	end

	return nil
end

return table.freeze(MutationConfig)
