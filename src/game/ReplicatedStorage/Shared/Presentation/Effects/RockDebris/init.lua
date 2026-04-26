local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Methods = require(script.Methods)

local RockDebris = {}

local function resolveRootCFrame(root): CFrame?
	if typeof(root) == "CFrame" then
		return root
	end

	if typeof(root) == "Vector3" then
		return CFrame.new(root)
	end

	if typeof(root) == "Instance" and root:IsA("BasePart") then
		return root.CFrame
	end

	return nil
end

local function getTweenSettings(params)
	local tween = params.Tween or {}
	local tweenUp = tween.TweenUp or {
		Style = "Sine",
		Direction = "Out",
		Time = 0.01,
	}
	local tweenDown = tween.TweenDown or {
		Style = "Sine",
		Direction = "In",
		Time = 1,
	}

	return tweenUp, tweenDown
end

local function createTweenInfo(definition)
	local time = math.max(0, tonumber(definition.Time) or 0)
	local easingStyle = Enum.EasingStyle[definition.Style] or Enum.EasingStyle.Sine
	local easingDirection = Enum.EasingDirection[definition.Direction] or Enum.EasingDirection.Out
	return TweenInfo.new(time, easingStyle, easingDirection)
end

local function applyRockAppearance(part: BasePart, groundInfo, params, isTopMain: boolean?)
	if not groundInfo then
		return
	end

	if isTopMain and params.Top then
		local sourcePart = groundInfo.Instance
		if sourcePart and sourcePart:IsA("BasePart") then
			local loweredOrigin = sourcePart.CFrame.Position - Vector3.new(0, sourcePart.Size.Y / 2, 0)
			local lowerGround = Methods.FetchGround(loweredOrigin, 100)
			if lowerGround then
				Methods.ApplySurfaceAppearance(part, lowerGround)
				return
			end
		end
	end

	Methods.ApplySurfaceAppearance(part, groundInfo)
end

local function scheduleCleanup(partsResult, part: BasePart, params, lifetime: number, tweenDown)
	local extraLife = lifetime
	if params.DespawnTick ~= nil then
		local maxRandom = math.max(1, math.floor(lifetime))
		extraLife += Random.new():NextInteger(1, maxRandom)
	end

	task.delay(extraLife, function()
		if part.Parent == nil then
			return
		end

		local tween = TweenService:Create(
			part,
			createTweenInfo(tweenDown),
			{ Position = part.Position + Vector3.new(0, -(part.Size.Y * 2), 0) }
		)
		tween:Play()

		task.delay(math.max(0, tonumber(tweenDown.Time) or 0), function()
			partsResult.ReturnedToCache()
		end)
	end)
end

function RockDebris.Crater(settings, rows)
	local cache = {}
	if type(rows) ~= "table" then
		return {
			ReturnCache = cache,
		}
	end

	local orderedKeys = {}
	for key in pairs(rows) do
		table.insert(orderedKeys, key)
	end
	table.sort(orderedKeys, function(a, b)
		if type(a) == "number" and type(b) == "number" then
			return a < b
		end
		return tostring(a) < tostring(b)
	end)

	for _, key in ipairs(orderedKeys) do
		local crater = rows[key]
		if type(crater) == "table" then
			cache[string.format("Row %s", tostring(key))] = RockDebris.CreateCrater(crater[1], crater[2])
		end

		local delaySeconds = settings and settings.Delay or 0
		if type(delaySeconds) == "number" and delaySeconds > 0 then
			task.wait(delaySeconds)
		end
	end

	return {
		ReturnCache = cache,
	}
end

function RockDebris.CreateCrater(rootPart, params)
	params = type(params) == "table" and params or {}

	local rootCFrame = resolveRootCFrame(rootPart)
	if rootCFrame == nil then
		Logger.Warn("[RockDebris] CreateCrater requires a CFrame, Vector3, or BasePart root.")
		return {}
	end

	local numRocks = math.max(1, math.floor(tonumber(params.Count) or 1))
	local distance = params.Distance or 0
	local angleNumber = tonumber(params.AngleNumber) or 0
	local orientation = params.Orientation or 0
	local lifetime = math.max(0.05, tonumber(params.LifeTime) or 5)
	local heightOffset = tonumber(params.HeightOffset) or 0
	local tweenUp, tweenDown = getTweenSettings(params)

	local function createPart(targetCFrame: CFrame)
		local groundInfo = Methods.FetchGround(targetCFrame.Position, 20)
		if groundInfo == nil then
			return nil
		end

		local partsResult = Methods.CreatePart(targetCFrame, params)
		local returnedRock = partsResult.ReturnedRock
		local parts = if type(returnedRock) == "table" then returnedRock else { returnedRock }

		for _, rockPart in ipairs(parts) do
			if not (rockPart and rockPart:IsA("BasePart")) then
				continue
			end

			if rockPart.Name == "Main" then
				rockPart.Position = groundInfo.Position + Vector3.new(0, heightOffset, 0) + Vector3.new(0, -(rockPart.Size.Y * 2), 0)
				TweenService:Create(
					rockPart,
					createTweenInfo(tweenUp),
					{ Position = rockPart.Position + Vector3.new(0, rockPart.Size.Y * 2, 0) }
				):Play()
				applyRockAppearance(rockPart, groundInfo, params, true)
			else
				local mainSizeY = rockPart.Size.Y * 4
				rockPart.Position = groundInfo.Position + Vector3.new(0, heightOffset, 0)
				rockPart.CFrame = rockPart.CFrame * CFrame.new(0, mainSizeY / 2 - rockPart.Size.Y / 2.1, 0)
				rockPart.Position = rockPart.Position + Vector3.new(0, -(rockPart.Size.Y * 2), 0)
				TweenService:Create(
					rockPart,
					createTweenInfo(tweenUp),
					{ Position = rockPart.Position + Vector3.new(0, rockPart.Size.Y * 2, 0) }
				):Play()
				applyRockAppearance(rockPart, groundInfo, params, false)
			end

			if params.Smoke then
				Methods.PlaceSmoke({
					Part = rockPart,
					LifeTime = lifetime,
				})
			end

			scheduleCleanup(partsResult, rockPart, params, lifetime, tweenDown)
		end

		return parts
	end

	if params.Smoke then
		local smokeSize = params.SmokeSize
		if type(smokeSize) ~= "number" then
			if typeof(distance) == "table" then
				smokeSize = distance.max or distance.Max or distance.min or distance.Min or 1
			else
				smokeSize = tonumber(distance) or 1
			end
		end

		Methods.CreateSmoke(rootCFrame, smokeSize, params)
	end

	local angle = 0
	local rockTable = {}
	for index = 1, numRocks do
		local actualDistance = distance
		if typeof(distance) == "table" then
			local minDistance = tonumber(distance.min or distance.Min) or 0
			local maxDistance = tonumber(distance.max or distance.Max) or minDistance
			actualDistance = Random.new():NextNumber(minDistance, maxDistance)
		end

		local origin = CFrame.fromEulerAnglesXYZ(0, math.rad(angle), 0) * CFrame.new(actualDistance, 1, 0)
		local createdRocks

		if typeof(orientation) == "table" then
			local baseRotation = tonumber(orientation.Base) or 0
			local minAngle = tonumber(orientation.min or orientation.Min) or 0
			local maxAngle = tonumber(orientation.max or orientation.Max) or minAngle
			createdRocks = createPart(rootCFrame * origin * CFrame.Angles(0, 0, math.rad(baseRotation)))
			if createdRocks then
				for _, rockPart in ipairs(createdRocks) do
					rockPart.CFrame *= Methods.GetRandomAngle(minAngle, maxAngle)
				end
			end
		elseif typeof(orientation) == "function" then
			local orientationOffset = orientation()
			if typeof(orientationOffset) ~= "CFrame" then
				orientationOffset = CFrame.new()
			end
			createdRocks = createPart(rootCFrame * origin * orientationOffset)
		else
			createdRocks = createPart(
				rootCFrame
					* CFrame.fromEulerAnglesXYZ(0, math.rad(angle), 0)
					* CFrame.new(actualDistance, 1, 0)
					* CFrame.Angles(0, 0, math.rad(tonumber(orientation) or 0))
			)
		end

		rockTable[string.format("Rock%d", index)] = createdRocks

		if params.Full then
			angle += 360 / numRocks
		elseif params.Space then
			angle += (angleNumber / math.pi) * params.Space
		else
			angle += angleNumber
		end
	end

	return rockTable
end

RockDebris.Create_Crater = RockDebris.CreateCrater

function RockDebris.SideCrater(params)
	params = type(params) == "table" and params or {}
	local origin = resolveRootCFrame(params.Origin)
	if origin == nil then
		Logger.Warn("[RockDebris] SideCrater requires Params.Origin.")
		return
	end

	local randomGenerator = Random.new()
	local distance = tonumber(params.Distance) or 35
	local iterations = math.max(1, math.floor(tonumber(params.Iterations) or 10))
	local lifetime = math.max(0.05, tonumber(params.Lifetime) or 10)
	local spacedOut = tonumber(params.SpacedOut) or 13
	local scale = tonumber(params.Scale) or 1
	local disappearTime = math.max(0.05, tonumber(params.DisappearTime) or 1.5)
	local appearTime = math.max(0.01, tonumber(params.AppearTime) or 0.2)
	local hideFactor = params.HideFactor or { 0.3, 0.4 }
	local minHide = tonumber(hideFactor[1]) or 0.3
	local maxHide = tonumber(hideFactor[2]) or minHide
	local minSpace = spacedOut * 0.3
	local iterationDelay = tonumber(params.IterationDelay)
	local targetPoint = origin * CFrame.new(0, 0, -distance)

	local function createRock(groundInfo, section: CFrame, isRightSide: boolean, spaceDistance: number)
		if params.SpaceVariation then
			local minVariation = tonumber(params.SpaceVariation[1]) or 1
			local maxVariation = tonumber(params.SpaceVariation[2]) or minVariation
			spaceDistance *= randomGenerator:NextNumber(minVariation, maxVariation)
		end

		local rock = Instance.new("Part")
		rock.Anchored = true
		rock.CanCollide = false
		rock.CanTouch = false
		rock.CanQuery = false
		rock.Massless = true
		rock.CastShadow = false
		rock.Size = Vector3.new(
			randomGenerator:NextNumber(0.9, 1.1),
			randomGenerator:NextNumber(0.9, 1.1),
			randomGenerator:NextNumber(0.9, 1.4)
		) * scale

		local rotatedAngle = randomGenerator:NextNumber(13, 20)
		if not isRightSide then
			rotatedAngle = -rotatedAngle
		end

		local rockPosition = (section * CFrame.new((isRightSide and spaceDistance) or -spaceDistance, 0, 0)).Position
		local rockCFrame = (
			CFrame.new(rockPosition, section.Position)
			* CFrame.Angles(math.rad(randomGenerator:NextNumber(45, 60)), 0, math.rad(rotatedAngle))
		) - Vector3.new(0, rock.Size.Y * randomGenerator:NextNumber(minHide, maxHide), 0)

		rock.CFrame = rockCFrame
		rock.Position -= Vector3.new(0, rock.Size.Y * 2, 0)
		Methods.ApplySurfaceAppearance(rock, groundInfo)
		rock.Parent = Methods.GetVisualRoot()

		TweenService:Create(
			rock,
			TweenInfo.new(appearTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ CFrame = rockCFrame }
		):Play()

		task.wait(lifetime)
		TweenService:Create(
			rock,
			TweenInfo.new(disappearTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ Position = rockCFrame.Position - Vector3.new(0, rock.Size.Y * 2, 0) }
		):Play()
		Debris:AddItem(rock, disappearTime)
	end

	for index = 1, iterations do
		task.spawn(function()
			local alpha = index / iterations
			local section = origin:Lerp(targetPoint, alpha)
			local groundInfo = Methods.FetchGround(section.Position + Vector3.yAxis * 2, 10)
			if groundInfo == nil then
				return
			end

			local spaceDistance = Methods.Lerp(minSpace, spacedOut, alpha)
			local oriented = (section - section.Position) + groundInfo.Position
			for sideIndex = 1, 2 do
				task.spawn(createRock, groundInfo, oriented, sideIndex == 1, spaceDistance)
			end
		end)

		if iterationDelay then
			task.wait(iterationDelay)
		end
	end
end

function RockDebris.RockLevitate(params)
	params = type(params) == "table" and params or {}
	local centerCFrame = resolveRootCFrame(params.CenterCFrame)
	if centerCFrame == nil then
		return false
	end

	local innerRadius = tonumber(params.InnerRadius) or 10
	local outerRadius = tonumber(params.OuterRadius) or 15
	local lifetime = math.max(0.05, tonumber(params.Lifetime) or 7)
	local amount = math.max(1, math.floor(tonumber(params.Amount) or 12))
	local sizeSetting = params.Size or 0.5
	local groundAllowance = tonumber(params.GroundAllowance) or -20
	local velocity = type(params.Velocity) == "table" and params.Velocity or { Min = 20, Max = 40 }

	local rockArray = {}

	for angle = 1, 360, 360 / amount do
		local x = math.random(innerRadius, outerRadius) * math.cos(math.rad(angle))
		local z = math.random(innerRadius, outerRadius) * math.sin(math.rad(angle))
		local groundInfo = Methods.FetchGround((centerCFrame * CFrame.new(x, 10, z)).Position, math.abs(groundAllowance))
		if groundInfo == nil then
			continue
		end

		local actualSize = if typeof(sizeSetting) == "table"
			then Random.new():NextNumber(tonumber(sizeSetting.Min) or 0.5, tonumber(sizeSetting.Max or sizeSetting.Min) or 0.5)
			else tonumber(sizeSetting) or 0.5

		local rockResult = Methods.CreatePart(nil, nil)
		local rock = rockResult.ReturnedRock
		if not (rock and rock:IsA("BasePart")) then
			continue
		end

		rock.CFrame = CFrame.new(groundInfo.Position + Vector3.new(0, 0.2, 0))
			* CFrame.Angles(
				math.rad(math.random(-180, 180)),
				math.rad(math.random(-180, 180)),
				math.rad(math.random(-180, 180))
			)
		rock.Material = groundInfo.Material
		rock.MaterialVariant = groundInfo.MaterialVariant or ""
		rock.Color = groundInfo.Color
		rock.Size = Vector3.zero
		rock.Anchored = false
		rock.CanCollide = false
		rock.CanTouch = false
		rock.CanQuery = false
		rock.CastShadow = false

		local randomSize = Vector3.new(
			Random.new():NextNumber(0.25, 1),
			Random.new():NextNumber(0.25, 1),
			Random.new():NextNumber(0.25, 1)
		) * actualSize

		TweenService:Create(rock, TweenInfo.new(0.25), { Size = randomSize }):Play()
		table.insert(rockArray, rock)
	end

	local rockFunctionality = {
		Rise = function(information)
			information = type(information) == "table" and information or {}
			local minVelocity = tonumber(information.Min) or tonumber(velocity.Min) or 20
			local maxVelocity = tonumber(information.Max) or tonumber(velocity.Max) or minVelocity

			for _, rock in ipairs(rockArray) do
				local existingMover = rock:FindFirstChildOfClass("BodyVelocity")
				if existingMover then
					existingMover:Destroy()
				end

				local bodyVelocity = Instance.new("BodyVelocity")
				bodyVelocity.MaxForce = Vector3.new(1, 1, 1) * 40000
				bodyVelocity.Velocity = Vector3.new(0, 1, 0) * math.random(minVelocity, maxVelocity)
				bodyVelocity.Parent = rock
				Debris:AddItem(bodyVelocity, tonumber(information.FloatTime) or 0.25)
			end
		end,

		Repulse = function(information)
			information = type(information) == "table" and information or {}
			local minVelocity = tonumber(information.Min) or tonumber(velocity.Min) or 20
			local maxVelocity = tonumber(information.Max) or tonumber(velocity.Max) or minVelocity

			task.spawn(function()
				for _, rock in ipairs(rockArray) do
					local existingMover = rock:FindFirstChildOfClass("BodyVelocity")
					if existingMover then
						existingMover:Destroy()
					end

					local bodyVelocity = Instance.new("BodyVelocity")
					bodyVelocity.MaxForce = Vector3.new(1, 1, 1) * 40000
					bodyVelocity.Velocity = (
						CFrame.lookAt(centerCFrame.Position, rock.Position)
						* CFrame.Angles(math.rad(math.random(-360, 360)), 0, math.rad(math.random(-360, 360)))
					).LookVector * math.random(minVelocity, maxVelocity)
					bodyVelocity.Parent = rock
					Debris:AddItem(bodyVelocity, tonumber(information.VelocityLifetime) or 0.25)
				end
			end)
		end,

		DestroyMovers = function(information)
			information = type(information) == "table" and information or {}
			for _, rock in ipairs(rockArray) do
				local mover = rock:FindFirstChildOfClass("BodyVelocity")
				if mover == nil then
					continue
				end

				if information.Delay then
					task.delay(information.Delay, function()
						local delayedMover = rock:FindFirstChildOfClass("BodyVelocity")
						if delayedMover then
							delayedMover:Destroy()
						end
					end)
				else
					mover:Destroy()
				end
			end
		end,

		Cleanup = function(information)
			information = type(information) == "table" and information or {}
			local cleanupTime = tonumber(information.CleanupTime) or 0.5

			task.spawn(function()
				if information.CleanupDelay then
					task.wait(information.CleanupDelay)
				else
					task.wait(lifetime)
				end

				for _, rock in ipairs(rockArray) do
					TweenService:Create(rock, TweenInfo.new(cleanupTime), { Size = Vector3.zero }):Play()
					task.delay(cleanupTime, function()
						if rock.Parent then
							rock:Destroy()
						end
					end)
				end
			end)
		end,

		RockCache = rockArray,
	}

	return rockFunctionality
end

return RockDebris
