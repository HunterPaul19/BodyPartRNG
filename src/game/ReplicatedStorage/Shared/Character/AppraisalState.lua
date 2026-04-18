local AppraisalState = {}

export type AppraisalStateValue = {
	isAvailable: boolean,
}

function AppraisalState.CreateEmptyState(): AppraisalStateValue
	return {
		isAvailable = false,
	}
end

function AppraisalState.CloneState(state: any): AppraisalStateValue
	local emptyState = AppraisalState.CreateEmptyState()
	if typeof(state) ~= "table" then
		return emptyState
	end

	return {
		isAvailable = state.isAvailable == true,
	}
end

function AppraisalState.AreEqual(a: any, b: any): boolean
	local left = AppraisalState.CloneState(a)
	local right = AppraisalState.CloneState(b)

	return left.isAvailable == right.isAvailable
end

return table.freeze(AppraisalState)
