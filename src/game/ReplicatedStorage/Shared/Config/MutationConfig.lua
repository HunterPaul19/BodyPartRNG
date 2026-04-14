local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MutationConfig = {}

export type MutationEntry = {
	id: string,
	displayName: string,
	weight: number,
	multiplier: number,
	color: Color3,
}

local ORDERED: { MutationEntry } = {
	{
		id = "none",
		displayName = "None",
		weight = 72,
		multiplier = 1.0,
		color = Color3.fromRGB(170, 170, 170),
	},
	{
		id = "magma",
		displayName = "Magma",
		weight = 18,
		multiplier = 1.12,
		color = Color3.fromRGB(255, 122, 54),
	},
	{
		id = "prismatic",
		displayName = "Prismatic",
		weight = 7,
		multiplier = 1.28,
		color = Color3.fromRGB(180, 98, 255),
	},
	{
		id = "corrupted",
		displayName = "Corrupted",
		weight = 2.4,
		multiplier = 1.48,
		color = Color3.fromRGB(214, 46, 113),
	},
	{
		id = "diamond",
		displayName = "Diamond",
		weight = 0.6,
		multiplier = 1.75,
		color = Color3.fromRGB(94, 234, 255),
	},
}

local VISUALS = {
	Default = {},
}

local BY_ID: { [string]: MutationEntry } = {}
local BY_DISPLAY_NAME: { [string]: MutationEntry } = {}
local FROZEN_ORDERED = table.create(#ORDERED)

local function getMutationVFXFolder(): Folder?
	local gameAssets = ReplicatedStorage:WaitForChild("GameAssets", 10)
	if not (gameAssets and gameAssets:IsA("Folder")) then
		return nil
	end

	local mutationVFX = gameAssets:WaitForChild("MutationVFX", 10)
	if mutationVFX and mutationVFX:IsA("Folder") then
		return mutationVFX
	end

	return nil
end

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

function MutationConfig.GetColor(id: any): Color3
	local entry = BY_ID[MutationConfig.NormalizeId(id)] or MutationConfig.GetDefault()
	return entry.color
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

function MutationConfig.ResolveModel(value: any): Model?
	local mutationId = MutationConfig.NormalizeId(value)
	if mutationId == MutationConfig.GetDefault().id then
		return nil
	end

	local mutationEntry = BY_ID[mutationId]
	if mutationEntry == nil then
		return nil
	end

	local mutationVFXFolder = getMutationVFXFolder()
	if mutationVFXFolder == nil then
		return nil
	end

	local mutationModel = mutationVFXFolder:FindFirstChild(mutationEntry.displayName)
	if mutationModel and mutationModel:IsA("Model") then
		return mutationModel
	end

	return nil
end

return table.freeze(MutationConfig)
