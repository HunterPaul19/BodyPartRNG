export type BodyPartIconEntry = {
	buttonName: string,
	image: string,
}

local rawIcons: { [string]: BodyPartIconEntry } = {
	Head = {
		buttonName = "Heads",
		image = "rbxassetid://121370555410150",
	},
	Torso = {
		buttonName = "Torsos",
		image = "rbxassetid://84936298281377",
	},
	LeftArm = {
		buttonName = "LeftArms",
		image = "rbxassetid://74125274020524",
	},
	RightArm = {
		buttonName = "RightArms",
		image = "rbxassetid://114930350339554",
	},
	LeftLeg = {
		buttonName = "LeftLegs",
		image = "rbxassetid://103215678671839",
	},
	RightLeg = {
		buttonName = "RightLegs",
		image = "rbxassetid://110119354613778",
	},
	FullBody = {
		buttonName = "FullBody",
		image = "rbxassetid://78587664168279",
	}
}

local BodyPartIcons: { [string]: BodyPartIconEntry } = {}

for region, entry in pairs(rawIcons) do
	BodyPartIcons[region] = table.freeze(table.clone(entry))
end

return table.freeze(BodyPartIcons)
