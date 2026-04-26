local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssetPaths = require(ReplicatedStorage.Shared.Assets.GameAssetPaths)
local GameAssetResolver = require(ReplicatedStorage.Shared.Assets.GameAssetResolver)
local Workspace = game:GetService("Workspace")

local RaycastUtil = require(ReplicatedStorage.Shared.Combat.CombatPhysics.Utilities.RaycastUtil)

local Methods = {}

local warnedMessages = {}

local function warnOnce(message: string)
	if warnedMessages[message] then
		return
	end

	warnedMessages[message] = true
	Logger.Warn(string.format("[RockDebris] %s", message))
end

local function shallowClone<T>(source: { T }): { T }
	local copy = {}
	for index, value in ipairs(source) do
		copy[index] = value
	end
	return copy
end

local function scaleNumberSequence(sequence: NumberSequence, scale: number): NumberSequence
	local keypoints = {}
	for _, keypoint in ipairs(sequence.Keypoints) do
		table.insert(keypoints, NumberSequenceKeypoint.new(
			keypoint.Time,
			keypoint.Value * scale,
			keypoint.Envelope * scale
		))
	end
	return NumberSequence.new(keypoints)
end

local function scaleNumberRange(range: NumberRange, scale: number): NumberRange
	return NumberRange.new(range.Min * scale, range.Max * scale)
end

local function getVisualRoot(): Folder
	local visuals = Workspace:FindFirstChild("Visuals")
	if visuals and visuals:IsA("Folder") then
		local folder = visuals:FindFirstChild("RockDebris")
		if folder and folder:IsA("Folder") then
			return folder
		end

		local created = Instance.new("Folder")
		created.Name = "RockDebris"
		created.Parent = visuals
		return created
	end

	if visuals and not visuals:IsA("Folder") then
		local folder = visuals:FindFirstChild("RockDebris")
		if folder and folder:IsA("Folder") then
			return folder
		end

		local created = Instance.new("Folder")
		created.Name = "RockDebris"
		created.Parent = visuals
		return created
	end

	local createdVisuals = Instance.new("Folder")
	createdVisuals.Name = "Visuals"
	createdVisuals.Parent = Workspace

	local created = Instance.new("Folder")
	created.Name = "RockDebris"
	created.Parent = createdVisuals
	return created
end

local function getRockDebriAssetFolder(): Folder?
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	if not (gameAssets and gameAssets:IsA("Folder")) then
		warnOnce("Missing ReplicatedStorage.GameAssets; RockDebri smoke templates are unavailable.")
		return nil
	end

	local vfxFolder = GameAssetResolver.FindFirst({ GameAssetPaths.Effects.Bosses, GameAssetPaths.Legacy.VFX })
	if not (vfxFolder and vfxFolder:IsA("Folder")) then
		warnOnce("Missing ReplicatedStorage.GameAssets.Effects.Bosses; RockDebri smoke templates are unavailable.")
		return nil
	end

	local rockDebriFolder = vfxFolder:FindFirstChild("RockDebri")
	if not (rockDebriFolder and rockDebriFolder:IsA("Folder")) then
		warnOnce("Missing ReplicatedStorage.GameAssets.Effects.Bosses.RockDebri; RockDebri smoke templates are unavailable.")
		return nil
	end

	return rockDebriFolder
end

local function getTerrainColor(material: Enum.Material): Color3
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		return terrain:GetMaterialColor(material)
	end
	return Color3.fromRGB(128, 128, 128)
end

function Methods.scaleNumberSequence(sequence: NumberSequence, scale: number): NumberSequence
	return scaleNumberSequence(sequence, scale)
end

function Methods.scaleNumberRange(range: NumberRange, scale: number): NumberRange
	return scaleNumberRange(range, scale)
end

function Methods.GetVisualRoot(): Folder
	return getVisualRoot()
end

function Methods.Lerp(startValue: number, goalValue: number, alpha: number): number
	return startValue + (goalValue - startValue) * alpha
end

function Methods.GetRandomAngle(minAngle: number, maxAngle: number): CFrame
	return CFrame.Angles(
		math.rad(math.random(minAngle, maxAngle)),
		math.rad(math.random(minAngle, maxAngle)),
		math.rad(math.random(minAngle, maxAngle))
	)
end

function Methods.ApplySurfaceAppearance(part: BasePart, groundInfo)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or type(groundInfo) ~= "table" then
		return
	end

	local groundInstance = groundInfo.Instance
	local groundMaterial = groundInfo.Material
	if groundInstance == Workspace.Terrain then
		part.Material = groundMaterial
		part.MaterialVariant = ""
		part.Color = getTerrainColor(groundMaterial)
		return
	end

	if groundInstance and groundInstance:IsA("BasePart") then
		part.Material = groundInstance.Material
		part.MaterialVariant = groundInstance.MaterialVariant
		part.Color = groundInstance.Color
		part.Transparency = groundInstance.Transparency
		return
	end

	part.Material = groundMaterial or Enum.Material.Slate
	part.MaterialVariant = ""
	part.Color = groundInfo.Color or Color3.fromRGB(100, 100, 100)
end

function Methods.FetchGround(position: Vector3, negativeY: number?)
	local result = Workspace:Raycast(
		position,
		Vector3.yAxis * -(negativeY or 8),
		RaycastUtil.getDeterministicGroundParams()
	)
	if not result then
		return nil
	end

	local instance = result.Instance
	local color = Color3.fromRGB(100, 100, 100)
	local material = result.Material
	local materialVariant = ""

	if instance == Workspace.Terrain then
		color = getTerrainColor(material)
	elseif instance and instance:IsA("BasePart") then
		color = instance.Color
		material = instance.Material
		materialVariant = instance.MaterialVariant
	end

	return {
		Position = result.Position,
		Normal = result.Normal,
		Color = color,
		Material = material,
		MaterialVariant = materialVariant,
		Instance = instance,
		Raw = result,
	}
end

function Methods.CreateSmoke(rootCFrame: CFrame, smokeSize: number, data)
	local rockDebriFolder = getRockDebriAssetFolder()
	if rockDebriFolder == nil then
		return nil
	end

	local smokeArea = rockDebriFolder:FindFirstChild("SmokeArea")
	if not (smokeArea and smokeArea:IsA("BasePart")) then
		warnOnce("Missing RockDebri.SmokeArea template.")
		return nil
	end

	local smokeFx = smokeArea:Clone()
	smokeFx.CFrame = rootCFrame
	smokeFx.Parent = getVisualRoot()

	local maxScale = math.max(0.05, smokeSize)
	local smokeLifetime = math.max(0.05, tonumber(data and (data.SmokeLifetime or data.LifeTime)) or 1)

	for _, descendant in ipairs(smokeFx:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant.Lifetime = NumberRange.new(smokeLifetime / 2, smokeLifetime * 1.76)
			descendant.Size = scaleNumberSequence(descendant.Size, maxScale)
			descendant.Speed = scaleNumberRange(descendant.Speed, maxScale)
			descendant.Acceleration = Vector3.new(0, -(maxScale / 5), 0)
			descendant:Emit(5)
		end
	end

	Debris:AddItem(smokeFx, smokeLifetime + 1)
	return smokeFx
end

function Methods.PlaceSmoke(params)
	local part = params and params.Part
	if not (part and part:IsA("BasePart")) then
		return nil
	end

	local rockDebriFolder = getRockDebriAssetFolder()
	if rockDebriFolder == nil then
		return nil
	end

	local smokePart = rockDebriFolder:FindFirstChild("Smoke")
	local smokeAttach = smokePart and smokePart:FindFirstChild("SmokeAttach")
	local particle = smokeAttach and smokeAttach:FindFirstChild("ParticleEmitter")
	if not (particle and particle:IsA("ParticleEmitter")) then
		warnOnce("Missing RockDebri.Smoke.SmokeAttach.ParticleEmitter template.")
		return nil
	end

	local smokeFx = particle:Clone()
	smokeFx.Parent = part

	local maxSize = math.max(part.Size.X, part.Size.Y, part.Size.Z) / 2
	local maxLife = math.max(0.05, tonumber(params.LifeTime) or 1) / 1.5

	local lifetimeMin = math.min(0.5, maxLife)
	local lifetimeMax = math.max(0.5, maxLife)
	smokeFx.Lifetime = NumberRange.new(lifetimeMin, lifetimeMax)
	smokeFx.Size = scaleNumberSequence(smokeFx.Size, maxSize)
	smokeFx.Speed = scaleNumberRange(smokeFx.Speed, maxSize)
	smokeFx.ZOffset = -1
	smokeFx.Acceleration = Vector3.new(0, maxSize / 10, 0)
	smokeFx:Emit(5)
	Debris:AddItem(smokeFx, maxLife)
	return smokeFx
end

function Methods.CreatePart(cframe: CFrame?, params)
	local createdParts = {}
	local visualRoot = getVisualRoot()

	local function configurePart(part: BasePart)
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = true
		part.CastShadow = false
		part.Parent = visualRoot
		table.insert(createdParts, part)
	end

	if params == nil then
		local part = Instance.new("Part")
		part.Name = "Main"
		part.Size = Vector3.one
		part.CFrame = cframe or CFrame.new()
		part.Material = Enum.Material.Concrete
		part.Color = Color3.fromRGB(100, 100, 100)
		configurePart(part)
	else
		local size = params.Size or Vector3.one
		local part = Instance.new("Part")
		part.Name = "Main"
		part.Size = size
		part.CFrame = cframe or CFrame.new()
		part.Material = Enum.Material.Concrete
		part.Color = Color3.fromRGB(100, 100, 100)
		configurePart(part)

		if params.Top then
			local topPart = Instance.new("Part")
			topPart.Name = "Top"
			topPart.Size = Vector3.new(size.X * 1.05, size.Y * 0.25, size.Z * 1.05)
			topPart.CFrame = part.CFrame * CFrame.new(0, part.Size.Y / 2, 0)
			topPart.Material = part.Material
			topPart.Color = part.Color
			configurePart(topPart)
		end
	end

	return {
		ReturnedRock = params and createdParts or createdParts[1],
		ReturnedToCache = function()
			for _, part in ipairs(createdParts) do
				if part.Parent then
					part:Destroy()
				end
			end
		end,
	}
end

return Methods
