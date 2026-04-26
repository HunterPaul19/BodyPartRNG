local AppearanceRegionRules = {}

AppearanceRegionRules.ClothingClassNames = table.freeze({
	Shirt = true,
	Pants = true,
	ShirtGraphic = true,
	BodyColors = true,
})

AppearanceRegionRules.RegionClothingClasses = table.freeze({
	Head = table.freeze({
		BodyColors = true,
	}),
	Torso = table.freeze({
		Shirt = true,
		Pants = true,
		ShirtGraphic = true,
		BodyColors = true,
	}),
	LeftArm = table.freeze({
		Shirt = true,
		BodyColors = true,
	}),
	RightArm = table.freeze({
		Shirt = true,
		BodyColors = true,
	}),
	LeftLeg = table.freeze({
		Pants = true,
		BodyColors = true,
	}),
	RightLeg = table.freeze({
		Pants = true,
		BodyColors = true,
	}),
})

function AppearanceRegionRules.GetRelevantClasses(region: string): { [string]: boolean }
	return AppearanceRegionRules.RegionClothingClasses[region] or {}
end

return table.freeze(AppearanceRegionRules)
