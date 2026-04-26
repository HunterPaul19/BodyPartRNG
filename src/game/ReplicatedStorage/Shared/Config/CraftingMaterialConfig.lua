local CraftingMaterialConfig = {}

export type CraftingMaterialConfigEntry = {
	id: string,
	label: string,
	description: string,
	sortOrder: number,
	displayColor: Color3,
	iconTexture: string?,
}

local ENTRIES: { CraftingMaterialConfigEntry } = {
	{
		id = "scrap",
		label = "Scrap",
		description = "A common placeholder crafting material.",
		sortOrder = 10,
		displayColor = Color3.fromRGB(172, 180, 190),
		iconTexture = "",
	},
	{
		id = "lucky_thread",
		label = "Lucky Thread",
		description = "A placeholder material used for luck-focused recipes.",
		sortOrder = 20,
		displayColor = Color3.fromRGB(116, 192, 255),
		iconTexture = "",
	},
}

local entriesById: { [string]: CraftingMaterialConfigEntry } = {}
for _, entry in ipairs(ENTRIES) do
	entriesById[string.lower(entry.id)] = table.freeze(entry)
end
for index, entry in ipairs(ENTRIES) do
	ENTRIES[index] = entriesById[string.lower(entry.id)]
end
table.freeze(ENTRIES)

local function normalizeId(materialId: any): string?
	if typeof(materialId) ~= "string" then
		return nil
	end

	local trimmed = string.match(materialId, "^%s*(.-)%s*$")
	if not trimmed or trimmed == "" then
		return nil
	end

	local entry = entriesById[string.lower(trimmed)]
	return if entry then entry.id else nil
end

function CraftingMaterialConfig.NormalizeId(materialId: any): string?
	return normalizeId(materialId)
end

function CraftingMaterialConfig.Get(materialId: any): CraftingMaterialConfigEntry?
	local normalizedId = normalizeId(materialId)
	return if normalizedId then entriesById[string.lower(normalizedId)] else nil
end

function CraftingMaterialConfig.GetAll(): { CraftingMaterialConfigEntry }
	local results = table.create(#ENTRIES)
	for index, entry in ipairs(ENTRIES) do
		results[index] = entry
	end
	return results
end

return table.freeze(CraftingMaterialConfig)
