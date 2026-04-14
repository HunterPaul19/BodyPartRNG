local Runtime = {}

Runtime.DefaultScale = 1
Runtime.MinScale = 0.5
Runtime.MaxScale = 3

function Runtime.GetScaleBounds(_pieceId: string): (number, number)
	return Runtime.MinScale, Runtime.MaxScale
end

function Runtime.ClampScale(pieceId: string, requestedScale: number?): number
	local minScale, maxScale = Runtime.GetScaleBounds(pieceId)
	local scale = if typeof(requestedScale) == "number" and requestedScale == requestedScale then requestedScale else Runtime.DefaultScale
	return math.clamp(scale, minScale, maxScale)
end

return table.freeze(Runtime)
