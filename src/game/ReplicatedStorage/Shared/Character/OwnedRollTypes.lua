local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RollTypes = require(ReplicatedStorage.Shared.Config.RollTypes)

local OwnedRollTypes = {}

function OwnedRollTypes.GetDefaultSelectedRollTypeId(): string
	return RollTypes.GetDefault().id
end

function OwnedRollTypes.NormalizeSelectedRollTypeId(value: any): string
	if typeof(value) == "string" and value ~= "" and RollTypes.Get(value) then
		return value
	end

	return OwnedRollTypes.GetDefaultSelectedRollTypeId()
end

return table.freeze(OwnedRollTypes)
