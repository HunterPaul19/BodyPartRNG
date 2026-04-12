local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BodyPartRegions = require(ReplicatedStorage.Shared.Character.BodyPartRegions)

local RollTargetRegions = {}

RollTargetRegions.FullBody = "FullBody"
RollTargetRegions.Default = "RightArm"

RollTargetRegions.Order = {
	"Head",
	"Torso",
	"LeftArm",
	"RightArm",
	"LeftLeg",
	"RightLeg",
	RollTargetRegions.FullBody,
}

RollTargetRegions.Set = {}
for _, region in ipairs(RollTargetRegions.Order) do
	RollTargetRegions.Set[region] = true
end

function RollTargetRegions.IsValid(region: string): boolean
	return RollTargetRegions.Set[region] == true
end

function RollTargetRegions.IsExactBodyRegion(region: string): boolean
	return BodyPartRegions.IsValid(region)
end

function RollTargetRegions.Normalize(region: any): string
	if typeof(region) == "string" and RollTargetRegions.IsValid(region) then
		return region
	end

	return RollTargetRegions.Default
end

return table.freeze(RollTargetRegions)
