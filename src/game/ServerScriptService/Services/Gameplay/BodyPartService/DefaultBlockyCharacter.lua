local DefaultBlockyCharacter = {}

local BODY_PART_DESCRIPTION_PROPERTIES = {
	"Head",
	"Torso",
	"LeftArm",
	"RightArm",
	"LeftLeg",
	"RightLeg",
}

local CLASSIC_SCALE_DESCRIPTION_PROPERTIES = {
	HeightScale = 1,
	WidthScale = 1,
	DepthScale = 1,
	HeadScale = 1,
	BodyTypeScale = 0,
	ProportionScale = 0,
}

local EPSILON = 0.0001

local function nearlyEqual(left: number, right: number): boolean
	return math.abs(left - right) <= EPSILON
end

local function getNumericProperty(instance: Instance, propertyName: string): number?
	local success, value = pcall(function()
		return instance[propertyName]
	end)

	if not success then
		return nil
	end

	return tonumber(value)
end

local function setProperty(instance: Instance, propertyName: string, value: number): (boolean, string?)
	local success, err = pcall(function()
		instance[propertyName] = value
	end)

	if success then
		return true, nil
	end

	return false, tostring(err)
end

local function isBlockyDescription(description: HumanoidDescription): boolean
	for _, propertyName in ipairs(BODY_PART_DESCRIPTION_PROPERTIES) do
		local value = getNumericProperty(description, propertyName)
		if value == nil or value ~= 0 then
			return false
		end
	end

	for propertyName, expectedValue in pairs(CLASSIC_SCALE_DESCRIPTION_PROPERTIES) do
		local value = getNumericProperty(description, propertyName)
		if value == nil or not nearlyEqual(value, expectedValue) then
			return false
		end
	end

	return true
end

local function forceBlockyDescription(description: HumanoidDescription): (boolean, string?)
	for _, propertyName in ipairs(BODY_PART_DESCRIPTION_PROPERTIES) do
		local success, err = setProperty(description, propertyName, 0)
		if not success then
			return false, err
		end
	end

	for propertyName, value in pairs(CLASSIC_SCALE_DESCRIPTION_PROPERTIES) do
		local success, err = setProperty(description, propertyName, value)
		if not success then
			return false, err
		end
	end

	return true, nil
end

function DefaultBlockyCharacter.Ensure(character: Model): (boolean, string?, boolean)
	if not (character and character:IsA("Model")) then
		return false, "Character must be a Model.", false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "Character has no Humanoid.", false
	end

	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return false, "Character must use an R15 rig for default blocky enforcement.", false
	end

	local descriptionSuccess, descriptionOrError = pcall(function()
		return humanoid:GetAppliedDescription()
	end)
	if not descriptionSuccess then
		return false, tostring(descriptionOrError), false
	end

	local description = descriptionOrError
	if isBlockyDescription(description) then
		return true, nil, false
	end

	local configured, configureError = forceBlockyDescription(description)
	if not configured then
		return false, configureError or "Failed to configure the blocky HumanoidDescription.", false
	end

	local applySuccess, applyError = pcall(function()
		humanoid:ApplyDescriptionReset(description)
	end)
	if not applySuccess then
		return false, tostring(applyError), false
	end

	return true, nil, true
end

return table.freeze(DefaultBlockyCharacter)
