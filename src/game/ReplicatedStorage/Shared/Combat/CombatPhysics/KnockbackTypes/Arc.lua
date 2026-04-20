local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Combat.Constants)
local BodyMoverUtil = require(script.Parent.Parent.Utilities.BodyMoverUtil)
local CancelToken = require(script.Parent.Parent.Utilities.CancelToken)
local MathUtil = require(script.Parent.Parent.Utilities.MathUtil)
local DebugUtil = require(script.Parent.Parent.Utilities.DebugUtil)
local RaycastUtil = require(script.Parent.Parent.Utilities.RaycastUtil)
local AnimationUtil = require(script.Parent.Parent.Utilities.AnimationUtil)

local function getAnimation(name)
	local storage = AnimationUtil.getPathingFolders()
	if not storage then
		return nil
	end

	local animations = storage:FindFirstChild("Animations")
	local general = animations and animations:FindFirstChild("General")
	local folder = general and general:FindFirstChild("KnockbackFolder")
	return folder and folder:FindFirstChild(name) or nil
end

return function(data, context, knockbackID)
	local direction = data.Direction
	local distance = data.Distance
	if not direction or not distance then
		warn("Direction and Distance required when using Arc knockback")
		return
	end

	local character = context.character
	local rootPart = context.rootPart

	context:setCollisionGroup(Constants.COLLISION_GROUPS.HitboxNoCollide)
	if data.KnockbackStart then
		data.KnockbackStart()
	end

	rootPart.CFrame = CFrame.new(rootPart.Position, rootPart.Position + direction) * CFrame.Angles(0, math.rad(180), 0)

	local initialCF = rootPart.CFrame
	local nextCF = initialCF * CFrame.new(0, 0, distance)
	local raycastResult = workspace:Raycast(nextCF.Position, Vector3.new(0, -1000, 0), RaycastUtil.getParams("Map"))
	if not raycastResult then
		return
	end

	local headUpAnimation = getAnimation("HeadUp")
	if headUpAnimation then
		context:playAnimation(headUpAnimation)
	end

	local targetPos = raycastResult.Position
	local dist = (initialCF.Position - targetPos).Magnitude
	local coverage = dist / distance
	if coverage > 0.2 then
		targetPos += Vector3.new(0, 15, 0)
	end

	local height = data.Height or 80
	local increments = data.Increments or 1
	local delta = data.Delta or 0.0005
	local speed = data.Speed or 120

	local midpoint = CFrame.new(initialCF.Position, targetPos) * CFrame.new(0, 0, -dist / 2)
	local offset = midpoint * CFrame.new(0, height, -distance / 2)

	dist = math.clamp(dist, 20, math.huge)
	local points = {}
	for i = 0, dist, increments do
		local t = i / dist
		local position = MathUtil.curve(t, initialCF.Position, offset.Position, targetPos)
		if data.Debug then
			DebugUtil.createDebugPart(position, 1)
		end
		table.insert(points, position)
	end

	local bodyVelocity = BodyMoverUtil.createVelocity(rootPart)
	if not bodyVelocity then
		return
	end
	bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)

	local bodyGyro = BodyMoverUtil.createGyro(rootPart)
	if not bodyGyro then
		bodyVelocity:Destroy()
		return
	end
	bodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
	bodyGyro.P = 60000
	bodyGyro.D = 600

	context:createState("AutoRotate")
	context:createState("Stunned")
	context:createState("PlatformStanding")

	local localLanded = false
	local broken = false

	local cancelEvent = CancelToken.new(function()
		if bodyVelocity and bodyVelocity.Parent then
			bodyVelocity:Destroy()
		end
		if bodyGyro and bodyGyro.Parent then
			bodyGyro:Destroy()
		end
	end)

	for index, point in ipairs(points) do
		if character:GetAttribute("Evaded") or cancelEvent.Cancelled then
			broken = true
			break
		end

		if not bodyVelocity.Parent or localLanded then
			break
		end

		local nextPoint = points[index + 1] or targetPos
		task.wait(delta)

		local updateCFrame = CFrame.lookAt(nextPoint, point)
		bodyVelocity.Velocity = CFrame.new(point, nextPoint).LookVector * speed
		bodyGyro.CFrame = updateCFrame
	end

	local landedData = data.Landed
	local delayTime = landedData and (landedData.Delay or 0.2) or 0.2
	local distanceFromGround = landedData and (landedData.DistanceFromGround or 2) or 2
	local onLand = landedData and landedData.OnLand or nil

	task.delay(delayTime, function()
		BodyMoverUtil.anticipateLand(character, distanceFromGround, function()
			if not cancelEvent.Cancelled then
				cancelEvent.Cancel()
			end
			localLanded = true
			if character:GetAttribute("KnockbackID") == knockbackID then
				context:setCollisionGroup(Constants.COLLISION_GROUPS.Hitbox)
				context:createState("AntiStunned", data.AntiStun ~= nil and data.AntiStun or 0.4)
				if onLand then
					onLand()
				end
			end
		end, 5)
	end)

	if bodyVelocity and bodyVelocity.Parent then
		bodyVelocity:Destroy()
	end
	if bodyGyro and bodyGyro.Parent then
		bodyGyro:Destroy()
	end

	context:removeState("AutoRotate")
	context:removeState("Stunned")
	context:removeState("PlatformStanding")

	if headUpAnimation then
		context:stopAnimation(headUpAnimation)
	end

	if localLanded and not broken then
		local fallAnimation = getAnimation("Fall")
		if fallAnimation then
			context:playAnimation(fallAnimation)
		end
		context:createState("AutoRotate")
		context:createState("Stunned")
	end
end
