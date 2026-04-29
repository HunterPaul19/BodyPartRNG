local NumberFormatter = {}

local SUFFIXES = {
	{ value = 1e90, suffix = "TG" },
	{ value = 1e87, suffix = "NV" },
	{ value = 1e84, suffix = "OV" },
	{ value = 1e81, suffix = "SPV" },
	{ value = 1e78, suffix = "SXV" },
	{ value = 1e75, suffix = "PV" },
	{ value = 1e72, suffix = "QV" },
	{ value = 1e69, suffix = "TV" },
	{ value = 1e66, suffix = "DV" },
	{ value = 1e63, suffix = "UV" },
	{ value = 1e60, suffix = "VG" },
	{ value = 1e57, suffix = "ND" },
	{ value = 1e54, suffix = "OD" },
	{ value = 1e51, suffix = "SP" },
	{ value = 1e48, suffix = "SX" },
	{ value = 1e45, suffix = "QN" },
	{ value = 1e42, suffix = "QD" },
	{ value = 1e39, suffix = "TD" },
	{ value = 1e36, suffix = "DD" },
	{ value = 1e33, suffix = "UD" },
	{ value = 1e30, suffix = "DE" },
	{ value = 1e27, suffix = "NO" },
	{ value = 1e24, suffix = "OT" },
	{ value = 1e21, suffix = "ST" },
	{ value = 1e18, suffix = "QT" },
	{ value = 1e15, suffix = "QD" },
	{ value = 1e12, suffix = "T" },
	{ value = 1e9, suffix = "B" },
	{ value = 1e6, suffix = "M" },
	{ value = 1e3, suffix = "K" },
}

local function formatWithSuffix(n: number, shouldFloorDecimal: boolean?, lowerK: boolean?): string
	local negative = n < 0
	n = math.abs(n)

	for _, entry in ipairs(SUFFIXES) do
		if n >= entry.value then
			local short = n / entry.value
			if shouldFloorDecimal == true then
				short = math.floor(short * 10) / 10
			end

			local formatted = if short % 1 == 0 then ("%d"):format(short) else ("%.1f"):format(short)
			local suffix = if lowerK == true and entry.suffix == "K" then "k" else entry.suffix
			return (if negative then "-" else "") .. formatted .. suffix
		end
	end

	return (if negative then "-" else "") .. tostring(math.floor(n + 0.5))
end

function NumberFormatter.Format(n: number): string
	return formatWithSuffix(n, false, false)
end

function NumberFormatter.FormatExistenceCount(value: any): string
	local count = math.max(0, math.floor(tonumber(value) or 0))
	if count < 500 then
		return "<500"
	end
	if count < 1000 then
		return "<1k"
	end

	return formatWithSuffix(math.floor(count / 1000) * 1000, true, true)
end

return NumberFormatter
