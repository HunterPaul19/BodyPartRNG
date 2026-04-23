export type RollTypeConfig = {
	id: string,
	displayName: string,
	moneyCost: number,
	luckMultiplier: number,
	bandLuckScalar: number,
	uiOrder: number,
}

local rawRollTypes: { RollTypeConfig } = {
	{
		id = "free",
		displayName = "Free",
		moneyCost = 0,
		luckMultiplier = 1.0,
		bandLuckScalar = 0.335,
		uiOrder = 1,
	},
	{
		id = "roll_2",
		displayName = "Roll 2",
		moneyCost = 100,
		luckMultiplier = 1.5,
		bandLuckScalar = 0.345,
		uiOrder = 2,
	},
	{
		id = "roll_3",
		displayName = "Roll 3",
		moneyCost = 500,
		luckMultiplier = 2,
		bandLuckScalar = 0.355,
		uiOrder = 3,
	},
	{
		id = "roll_4",
		displayName = "Roll 4",
		moneyCost = 2500,
		luckMultiplier = 3,
		bandLuckScalar = 0.364559,
		uiOrder = 4,
	},
	{
		id = "roll_5",
		displayName = "Roll 5",
		moneyCost = 12500,
		luckMultiplier = 4,
		bandLuckScalar = 0.374603,
		uiOrder = 5,
	},
	{
		id = "roll_6",
		displayName = "Roll 6",
		moneyCost = 75000,
		luckMultiplier = 5,
		bandLuckScalar = 0.487161,
		uiOrder = 6,
	},
	{
		id = "roll_7",
		displayName = "Roll 7",
		moneyCost = 500000,
		luckMultiplier = 6,
		bandLuckScalar = 0.579365,
		uiOrder = 7,
	},
	{
		id = "roll_8",
		displayName = "Roll 8",
		moneyCost = 2500000,
		luckMultiplier = 8,
		bandLuckScalar = 1.016461,
		uiOrder = 8,
	},
}

local byId: { [string]: RollTypeConfig } = {}
local ordered: { RollTypeConfig } = table.clone(rawRollTypes)

table.sort(ordered, function(a, b)
	if a.uiOrder ~= b.uiOrder then
		return a.uiOrder < b.uiOrder
	end
	return a.id < b.id
end)

for _, rollType in ipairs(ordered) do
	byId[rollType.id] = table.freeze(table.clone(rollType))
end

local frozenOrdered = table.create(#ordered)
for index, rollType in ipairs(ordered) do
	frozenOrdered[index] = byId[rollType.id]
end
table.freeze(frozenOrdered)
table.freeze(byId)

local RollTypes = {}

function RollTypes.Get(id: string): RollTypeConfig?
	return byId[id]
end

function RollTypes.GetOrdered(): { RollTypeConfig }
	return frozenOrdered
end

function RollTypes.GetDefault(): RollTypeConfig
	return frozenOrdered[1]
end

return table.freeze(RollTypes)
