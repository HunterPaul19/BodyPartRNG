local SizeConfig = {}

export type SizeEntry = {
	id: string,
	displayName: string,
	weight: number,
	minScale: number,
	maxScale: number,
	moneyMultiplier: number,
	combatMultiplier: number,
}

local ORDERED: { SizeEntry } = {
	{
		id = "tiny",
		displayName = "Tiny",
		weight = 12,
		minScale = 0.5,
		maxScale = 0.74,
		moneyMultiplier = 0.5,
		combatMultiplier = 0.95,
	},
	{
		id = "small",
		displayName = "Small",
		weight = 6,
		minScale = 0.75,
		maxScale = 0.99,
		moneyMultiplier = 0.75,
		combatMultiplier = 0.98,
	},
	{
		id = "normal",
		displayName = "Normal",
		weight = 72,
		minScale = 1.0,
		maxScale = 1.99,
		moneyMultiplier = 1.0,
		combatMultiplier = 1.0,
	},
	{
		id = "large",
		displayName = "Large",
		weight = 12,
		minScale = 2.0,
		maxScale = 2.99,
		moneyMultiplier = 1.5,
		combatMultiplier = 1.03,
	},
	{
		id = "huge",
		displayName = "Huge",
		weight = 3.2,
		minScale = 3.0,
		maxScale = 3.99,
		moneyMultiplier = 2.0,
		combatMultiplier = 1.06,
	},
	{
		id = "titanic",
		displayName = "Titanic",
		weight = 0.8,
		minScale = 4.0,
		maxScale = 5.0,
		moneyMultiplier = 3.0,
		combatMultiplier = 1.1,
	},
}

local BY_ID: { [string]: SizeEntry } = {}
local BY_DISPLAY_NAME: { [string]: SizeEntry } = {}
local FROZEN_ORDERED = table.create(#ORDERED)
local MIN_SCALE = ORDERED[1].minScale
local MAX_SCALE = ORDERED[#ORDERED].maxScale
local LEGACY_SCALE_BY_ID = {
	compact = 0.5,
	massive = 2.0,
}

local function roundToHundredths(value: number): number
	return math.floor((value * 100) + 0.5) / 100
end

for index, entry in ipairs(ORDERED) do
	local frozen = table.freeze(table.clone(entry))
	BY_ID[frozen.id] = frozen
	BY_DISPLAY_NAME[string.lower(frozen.displayName)] = frozen
	FROZEN_ORDERED[index] = frozen
end

table.freeze(BY_ID)
table.freeze(BY_DISPLAY_NAME)
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
	if typeof(value) == "string" then
		if BY_ID[value] then
			return value
		end

		local normalized = string.lower(value)
		local byDisplayName = BY_DISPLAY_NAME[normalized]
		if byDisplayName then
			return byDisplayName.id
		end

		local legacyScale = LEGACY_SCALE_BY_ID[value]
		if legacyScale ~= nil then
			local legacyEntry = SizeConfig.GetByScale(legacyScale)
			if legacyEntry then
				return legacyEntry.id
			end
		end
	end

	return SizeConfig.GetDefault().id
end

function SizeConfig.GetMultiplier(id: any): number
	return SizeConfig.GetMoneyMultiplier(id)
end

function SizeConfig.GetDisplayName(id: any): string
	if typeof(id) == "string" and not BY_ID[id] then
		local legacyScale = LEGACY_SCALE_BY_ID[id]
		if legacyScale ~= nil then
			local legacyEntry = SizeConfig.GetByScale(legacyScale)
			if legacyEntry then
				return legacyEntry.displayName
			end
		end

		if id ~= "" then
			local label = id:gsub("_", " ")
			return (label:gsub("(%a)([%w']*)", function(first, rest)
				return string.upper(first) .. string.lower(rest)
			end))
		end
	end

	local entry = BY_ID[SizeConfig.NormalizeId(id)] or SizeConfig.GetDefault()
	return entry.displayName
end

function SizeConfig.GetByScale(scale: any): SizeEntry?
	local numericScale = tonumber(scale)
	if numericScale == nil then
		return nil
	end

	local roundedScale = roundToHundredths(math.clamp(numericScale, MIN_SCALE, MAX_SCALE))
	for _, entry in ipairs(FROZEN_ORDERED) do
		if roundedScale >= entry.minScale and roundedScale <= entry.maxScale then
			return entry
		end
	end

	return nil
end

function SizeConfig.GetRepresentativeScale(id: any): number
	if typeof(id) == "string" and not BY_ID[id] then
		local legacyScale = LEGACY_SCALE_BY_ID[id]
		if legacyScale ~= nil then
			return legacyScale
		end
	end

	local entry = BY_ID[SizeConfig.NormalizeId(id)] or SizeConfig.GetDefault()
	if entry.minScale <= 1 and entry.maxScale >= 1 then
		return 1
	end

	return roundToHundredths((entry.minScale + entry.maxScale) * 0.5)
end

function SizeConfig.NormalizeScale(scale: any, fallbackId: any): number
	local numericScale = tonumber(scale)
	if numericScale == nil or numericScale <= 0 then
		return SizeConfig.GetRepresentativeScale(fallbackId)
	end

	local clampedScale = roundToHundredths(math.clamp(numericScale, MIN_SCALE, MAX_SCALE))
	local entry = SizeConfig.GetByScale(clampedScale)
	if entry then
		return clampedScale
	end

	return SizeConfig.GetRepresentativeScale(fallbackId)
end

function SizeConfig.GetMoneyMultiplier(id: any): number
	local entry = BY_ID[SizeConfig.NormalizeId(id)] or SizeConfig.GetDefault()
	return entry.moneyMultiplier
end

function SizeConfig.GetMoneyMultiplierForScale(scale: any): number
	local entry = SizeConfig.GetByScale(scale)
	if entry then
		return entry.moneyMultiplier
	end

	return SizeConfig.GetMoneyMultiplier(nil)
end

function SizeConfig.GetCombatMultiplier(id: any): number
	local entry = BY_ID[SizeConfig.NormalizeId(id)] or SizeConfig.GetDefault()
	return entry.combatMultiplier
end

function SizeConfig.GetCombatMultiplierForScale(scale: any): number
	local entry = SizeConfig.GetByScale(scale)
	if entry then
		return entry.combatMultiplier
	end

	return SizeConfig.GetCombatMultiplier(nil)
end

function SizeConfig.RollScale(randomSource: Random, size: any): number
	local entry = if typeof(size) == "table" and typeof(size.id) == "string"
		then BY_ID[SizeConfig.NormalizeId(size.id)] or SizeConfig.GetDefault()
		else BY_ID[SizeConfig.NormalizeId(size)] or SizeConfig.GetDefault()
	local minHundredths = math.floor((entry.minScale * 100) + 0.5)
	local maxHundredths = math.floor((entry.maxScale * 100) + 0.5)
	if minHundredths >= maxHundredths then
		return minHundredths / 100
	end

	return randomSource:NextInteger(minHundredths, maxHundredths) / 100
end

return table.freeze(SizeConfig)
