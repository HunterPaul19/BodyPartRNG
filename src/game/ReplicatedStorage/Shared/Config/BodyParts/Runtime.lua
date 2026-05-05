local SizeConfig = require(script.Parent.Parent.SizeConfig)

local Runtime = {}
local minScale, maxScale = SizeConfig.GetScaleBounds()

Runtime.DefaultScale = 1
Runtime.MinScale = minScale
Runtime.MaxScale = maxScale

function Runtime.GetScaleBounds(_pieceId: string): (number, number)
	return Runtime.MinScale, Runtime.MaxScale
end

function Runtime.ClampScale(pieceId: string, requestedScale: number?): number
	local minScale, maxScale = Runtime.GetScaleBounds(pieceId)
	local scale = if typeof(requestedScale) == "number" and requestedScale == requestedScale then requestedScale else Runtime.DefaultScale
	return math.clamp(scale, minScale, maxScale)
end

return table.freeze(Runtime)
