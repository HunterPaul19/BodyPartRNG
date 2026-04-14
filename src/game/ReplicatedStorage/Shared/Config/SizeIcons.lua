local function createStyle(
	image: string,
	color: ColorSequence,
	transparency: NumberSequence
)
	return table.freeze({
		image = image,
		gradient = table.freeze({
			rotation = 90,
			offset = Vector2.new(0, 0),
			color = color,
			transparency = transparency,
		}),
	})
end

local opaqueTransparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(1, 0),
})

local SizeIcons = {
	titanic = createStyle(
		"rbxassetid://138253672618308",
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
		}),
		opaqueTransparency
	),
	huge = createStyle(
		"rbxassetid://112504076266025",
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(162, 0, 255)),
		}),
		opaqueTransparency
	),
	large = createStyle(
		"rbxassetid://98715671311005",
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(184, 255, 228)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 136, 255)),
		}),
		opaqueTransparency
	),
	small = createStyle(
		"rbxassetid://136805363220821",
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 255, 139)),
		}),
		opaqueTransparency
	),
	tiny = createStyle(
		"rbxassetid://140049917449302",
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(0.4152249396, Color3.fromRGB(243, 243, 243)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(195, 195, 195)),
		}),
		opaqueTransparency
	),
}

return table.freeze(SizeIcons)
