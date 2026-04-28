local DashStateRules = {}

local BLOCKED_STATES = table.freeze({
	table.freeze({ attributeName = "Dashing", code = "DASHING" }),
	table.freeze({ attributeName = "DashStun", code = "DASH_STUN" }),
	table.freeze({ attributeName = "Stunned", code = "STUNNED" }),
	table.freeze({ attributeName = "Ragdoll", code = "RAGDOLLED" }),
	table.freeze({ attributeName = "RagdollRecovering", code = "RAGDOLL_RECOVERING" }),
	table.freeze({ attributeName = "CannotDash", code = "CANNOT_DASH" }),
})

function DashStateRules.GetBlockedState(character: Model?): (boolean, string)
	if character == nil then
		return false, ""
	end

	for _, state in ipairs(BLOCKED_STATES) do
		if character:GetAttribute(state.attributeName) == true then
			return true, state.code
		end
	end

	return false, ""
end

function DashStateRules.IsDashBlocked(character: Model?): boolean
	local blocked = DashStateRules.GetBlockedState(character)
	return blocked
end

return table.freeze(DashStateRules)
