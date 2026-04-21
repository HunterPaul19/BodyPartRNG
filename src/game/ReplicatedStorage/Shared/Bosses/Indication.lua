local TweenService = game:GetService("TweenService")

local DEFAULT_COLOR = Color3.fromRGB(255, 25, 25)
local DEFAULT_TRANSPARENCY = 0.35
local DEFAULT_HEIGHT = 0.12
local DEFAULT_START_SCALE = 0.08
local DEFAULT_Y_OFFSET_PADDING = 0.03
local MIN_DIMENSION = 0.1

type CircleOptions = {
	parent: Instance,
	cframe: CFrame,
	diameter: number,
	duration: number,
	color: Color3?,
	transparency: number?,
	height: number?,
	startScale: number?,
	yOffset: number?,
}

type BoxOptions = {
	parent: Instance,
	cframe: CFrame,
	size: Vector3,
	duration: number,
	color: Color3?,
	transparency: number?,
	height: number?,
	startScale: number?,
	yOffset: number?,
}

type HandleData = {
	_part: BasePart?,
	_tween: Tween?,
	_destroyed: boolean,
}

local Handle = {}
Handle.__index = Handle

function Handle:Destroy()
	if self._destroyed then
		return
	end

	self._destroyed = true

	if self._tween ~= nil then
		self._tween:Cancel()
		self._tween = nil
	end

	local part = self._part
	self._part = nil
	if part ~= nil and part.Parent ~= nil then
		part:Destroy()
	end
end

local function asPositiveNumber(value: any, defaultValue: number): number
	local numberValue = tonumber(value)
	if numberValue == nil or numberValue ~= numberValue then
		return defaultValue
	end

	return math.max(MIN_DIMENSION, numberValue)
end

local function asUnitNumber(value: any, defaultValue: number): number
	local numberValue = tonumber(value)
	if numberValue == nil or numberValue ~= numberValue then
		return defaultValue
	end

	return math.clamp(numberValue, 0, 1)
end

local function getCommonOptions(options: { [string]: any })
	local parent = options.parent
	assert(typeof(parent) == "Instance", "Indication parent must be an Instance.")
	assert(typeof(options.cframe) == "CFrame", "Indication cframe must be a CFrame.")

	local height = asPositiveNumber(options.height, DEFAULT_HEIGHT)
	local duration = math.max(0, tonumber(options.duration) or 0)
	local color = if typeof(options.color) == "Color3" then options.color else DEFAULT_COLOR
	local transparency = asUnitNumber(options.transparency, DEFAULT_TRANSPARENCY)
	local startScale = asUnitNumber(options.startScale, DEFAULT_START_SCALE)
	local yOffset = if tonumber(options.yOffset) ~= nil then tonumber(options.yOffset) else (height * 0.5) + DEFAULT_Y_OFFSET_PADDING

	return parent :: Instance, options.cframe :: CFrame, height, duration, color, transparency, startScale, yOffset
end

local function createPart(
	parent: Instance,
	name: string,
	shape: Enum.PartType,
	cframe: CFrame,
	startSize: Vector3,
	finalSize: Vector3,
	duration: number,
	color: Color3,
	transparency: number
): HandleData
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency
	part.Size = startSize
	part.CFrame = cframe
	part.Parent = parent

	local handle = setmetatable({
		_part = part,
		_tween = nil,
		_destroyed = false,
	}, Handle)

	if duration <= 0 then
		part.Size = finalSize
		return handle
	end

	local tween = TweenService:Create(
		part,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = finalSize,
		}
	)
	handle._tween = tween
	tween:Play()

	return handle
end

local Indication = {}

function Indication.CreateCircle(options: CircleOptions): HandleData
	assert(typeof(options) == "table", "Indication.CreateCircle options must be a table.")

	local parent, baseCFrame, height, duration, color, transparency, startScale, yOffset = getCommonOptions(options)
	local diameter = asPositiveNumber(options.diameter, 1)
	local startDiameter = math.max(MIN_DIMENSION, diameter * startScale)
	local finalSize = Vector3.new(height, diameter, diameter)
	local startSize = Vector3.new(height, startDiameter, startDiameter)
	local cframe = baseCFrame * CFrame.new(0, yOffset, 0) * CFrame.Angles(0, 0, math.rad(90))

	return createPart(parent, "BossIndicationCircle", Enum.PartType.Cylinder, cframe, startSize, finalSize, duration, color, transparency)
end

function Indication.CreateBox(options: BoxOptions): HandleData
	assert(typeof(options) == "table", "Indication.CreateBox options must be a table.")

	local parent, baseCFrame, height, duration, color, transparency, startScale, yOffset = getCommonOptions(options)
	assert(typeof(options.size) == "Vector3", "Indication.CreateBox size must be a Vector3.")

	local size = options.size
	local finalSize = Vector3.new(asPositiveNumber(size.X, 1), height, asPositiveNumber(size.Z, 1))
	local startSize = Vector3.new(
		math.max(MIN_DIMENSION, finalSize.X * startScale),
		height,
		math.max(MIN_DIMENSION, finalSize.Z * startScale)
	)
	local cframe = baseCFrame * CFrame.new(0, yOffset, 0)

	return createPart(parent, "BossIndicationBox", Enum.PartType.Block, cframe, startSize, finalSize, duration, color, transparency)
end

return table.freeze(Indication)
