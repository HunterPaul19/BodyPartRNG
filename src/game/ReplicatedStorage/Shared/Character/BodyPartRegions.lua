local BodyPartRegions = {}

BodyPartRegions.Order = {
	"Head",
	"Torso",
	"LeftArm",
	"RightArm",
	"LeftLeg",
	"RightLeg",
}

BodyPartRegions.Set = {}
for _, region in ipairs(BodyPartRegions.Order) do
	BodyPartRegions.Set[region] = true
end

function BodyPartRegions.IsValid(region: string): boolean
	return BodyPartRegions.Set[region] == true
end

return BodyPartRegions
