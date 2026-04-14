local DayNightCycleConfig = {}

DayNightCycleConfig.LoopDurationSeconds = 12 * 60
DayNightCycleConfig.InitialNormalizedTime = 0.28

DayNightCycleConfig.Keyframes = {
	{
		Phase = "SUNRISE",
		LabelText = "SUNRISE",
		NormalizedTime = 0.00,
		ClockTime = 5.25,
		LabelColor = Color3.fromRGB(255, 201, 117),
		LabelStrokeColor = Color3.fromRGB(99, 55, 19),
		Lighting = {
			Brightness = 1.85,
			ExposureCompensation = -0.08,
			Ambient = Color3.fromRGB(168, 171, 188),
			OutdoorAmbient = Color3.fromRGB(142, 150, 170),
			ColorShift_Top = Color3.fromRGB(255, 204, 148),
			ColorShift_Bottom = Color3.fromRGB(255, 177, 115),
		},
		Atmosphere = {
			Density = 0.34,
			Offset = 0.58,
			Color = Color3.fromRGB(160, 214, 255),
			Decay = Color3.fromRGB(255, 191, 151),
			Glare = 0.03,
			Haze = 0.75,
		},
		ColorCorrection = {
			Brightness = 0.01,
			Contrast = 0.09,
			Saturation = 0.07,
			TintColor = Color3.fromRGB(255, 237, 219),
		},
		Bloom = {
			Intensity = 0.95,
			Size = 24,
			Threshold = 2,
		},
		SunRays = {
			Intensity = 0.065,
			Spread = 0.58,
		},
	},
	{
		Phase = "DAYTIME",
		LabelText = "DAYTIME",
		NormalizedTime = 0.18,
		ClockTime = 13.5,
		LabelColor = Color3.fromRGB(255, 226, 71),
		LabelStrokeColor = Color3.fromRGB(107, 73, 10),
		Lighting = {
			Brightness = 2.0,
			ExposureCompensation = 0.02,
			Ambient = Color3.fromRGB(182, 182, 182),
			OutdoorAmbient = Color3.fromRGB(145, 145, 145),
			ColorShift_Top = Color3.fromRGB(0, 0, 0),
			ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
		},
		Atmosphere = {
			Density = 0.345,
			Offset = 0.582,
			Color = Color3.fromRGB(134, 253, 255),
			Decay = Color3.fromRGB(56, 219, 255),
			Glare = 0.0,
			Haze = 0.0,
		},
		ColorCorrection = {
			Brightness = 0.0,
			Contrast = 0.10,
			Saturation = 0.10,
			TintColor = Color3.fromRGB(255, 255, 255),
		},
		Bloom = {
			Intensity = 1.0,
			Size = 24,
			Threshold = 2,
		},
		SunRays = {
			Intensity = 0.055,
			Spread = 0.564,
		},
	},
	{
		Phase = "SUNSET",
		LabelText = "SUNSET",
		NormalizedTime = 0.58,
		ClockTime = 18.35,
		LabelColor = Color3.fromRGB(255, 153, 82),
		LabelStrokeColor = Color3.fromRGB(122, 44, 20),
		Lighting = {
			Brightness = 1.72,
			ExposureCompensation = -0.02,
			Ambient = Color3.fromRGB(166, 150, 170),
			OutdoorAmbient = Color3.fromRGB(128, 118, 148),
			ColorShift_Top = Color3.fromRGB(255, 140, 82),
			ColorShift_Bottom = Color3.fromRGB(173, 87, 169),
		},
		Atmosphere = {
			Density = 0.355,
			Offset = 0.61,
			Color = Color3.fromRGB(255, 189, 143),
			Decay = Color3.fromRGB(255, 123, 157),
			Glare = 0.05,
			Haze = 1.15,
		},
		ColorCorrection = {
			Brightness = -0.01,
			Contrast = 0.14,
			Saturation = 0.12,
			TintColor = Color3.fromRGB(255, 224, 214),
		},
		Bloom = {
			Intensity = 1.15,
			Size = 28,
			Threshold = 1.85,
		},
		SunRays = {
			Intensity = 0.08,
			Spread = 0.64,
		},
	},
	{
		Phase = "NIGHTTIME",
		LabelText = "NIGHTTIME",
		NormalizedTime = 0.78,
		ClockTime = 21.9,
		LabelColor = Color3.fromRGB(193, 160, 255),
		LabelStrokeColor = Color3.fromRGB(70, 42, 112),
		Lighting = {
			Brightness = 1.15,
			ExposureCompensation = -0.22,
			Ambient = Color3.fromRGB(95, 108, 152),
			OutdoorAmbient = Color3.fromRGB(82, 96, 134),
			ColorShift_Top = Color3.fromRGB(57, 91, 166),
			ColorShift_Bottom = Color3.fromRGB(42, 71, 118),
		},
		Atmosphere = {
			Density = 0.36,
			Offset = 0.56,
			Color = Color3.fromRGB(88, 138, 216),
			Decay = Color3.fromRGB(26, 44, 88),
			Glare = 0.01,
			Haze = 1.85,
		},
		ColorCorrection = {
			Brightness = -0.04,
			Contrast = 0.16,
			Saturation = -0.02,
			TintColor = Color3.fromRGB(201, 224, 255),
		},
		Bloom = {
			Intensity = 0.72,
			Size = 20,
			Threshold = 2.25,
		},
		SunRays = {
			Intensity = 0.018,
			Spread = 0.4,
		},
	},
}

local function normalize01(value: number): number
	local wrapped = value % 1
	if wrapped < 0 then
		return wrapped + 1
	end

	return wrapped
end

local function wrapClockTime(clockTime: number): number
	local wrapped = clockTime % 24
	if wrapped < 0 then
		return wrapped + 24
	end

	return wrapped
end

local function getNextKeyframe(index: number)
	local keyframes = DayNightCycleConfig.Keyframes
	local nextIndex = index + 1
	if nextIndex > #keyframes then
		return keyframes[1]
	end

	return keyframes[nextIndex]
end

function DayNightCycleConfig.GetKeyframePairForNormalizedTime(normalizedTime: number)
	local keyframes = DayNightCycleConfig.Keyframes
	local wrappedTime = normalize01(normalizedTime)

	for index, keyframe in ipairs(keyframes) do
		local nextKeyframe = getNextKeyframe(index)
		local startTime = keyframe.NormalizedTime
		local endTime = nextKeyframe.NormalizedTime

		if endTime <= startTime then
			endTime += 1
		end

		local comparisonTime = wrappedTime
		if comparisonTime < startTime then
			comparisonTime += 1
		end

		if comparisonTime >= startTime and comparisonTime < endTime then
			local alpha = (comparisonTime - startTime) / (endTime - startTime)
			return keyframe, nextKeyframe, alpha
		end
	end

	return keyframes[#keyframes], keyframes[1], 0
end

function DayNightCycleConfig.GetKeyframePairForClockTime(clockTime: number)
	local keyframes = DayNightCycleConfig.Keyframes
	local wrappedClockTime = wrapClockTime(clockTime)

	for index, keyframe in ipairs(keyframes) do
		local nextKeyframe = getNextKeyframe(index)
		local startClockTime = keyframe.ClockTime
		local endClockTime = nextKeyframe.ClockTime

		if endClockTime <= startClockTime then
			endClockTime += 24
		end

		local comparisonClockTime = wrappedClockTime
		if comparisonClockTime < startClockTime then
			comparisonClockTime += 24
		end

		if comparisonClockTime >= startClockTime and comparisonClockTime < endClockTime then
			local alpha = (comparisonClockTime - startClockTime) / (endClockTime - startClockTime)
			return keyframe, nextKeyframe, alpha
		end
	end

	return keyframes[#keyframes], keyframes[1], 0
end

function DayNightCycleConfig.GetPhaseForNormalizedTime(normalizedTime: number)
	local currentKeyframe = DayNightCycleConfig.GetKeyframePairForNormalizedTime(normalizedTime)
	return currentKeyframe
end

function DayNightCycleConfig.GetPhaseForClockTime(clockTime: number)
	local currentKeyframe = DayNightCycleConfig.GetKeyframePairForClockTime(clockTime)
	return currentKeyframe
end

function DayNightCycleConfig.GetLabelPresentationForClockTime(clockTime: number)
	local currentKeyframe = DayNightCycleConfig.GetPhaseForClockTime(clockTime)
	return {
		Phase = currentKeyframe.Phase,
		Text = currentKeyframe.LabelText,
		TextColor3 = currentKeyframe.LabelColor,
		TextStrokeColor3 = currentKeyframe.LabelStrokeColor,
	}
end

function DayNightCycleConfig.NormalizeCycleTime(normalizedTime: number): number
	return normalize01(normalizedTime)
end

function DayNightCycleConfig.WrapClockTime(clockTime: number): number
	return wrapClockTime(clockTime)
end

return table.freeze(DayNightCycleConfig)
