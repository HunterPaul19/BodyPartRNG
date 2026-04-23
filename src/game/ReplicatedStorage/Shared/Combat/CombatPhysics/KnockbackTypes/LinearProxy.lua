local RunService = game:GetService("RunService")

local Constants = require(script.Parent.Parent.Parent.Constants)

local function withPosition(cframe: CFrame, position: Vector3): CFrame
	return CFrame.fromMatrix(position, cframe.XVector, cframe.YVector, cframe.ZVector)
end

return function(data, context, knockbackID)
	local startPosition = data.StartPosition
	local impactPosition = data.ImpactPosition
	local duration = math.max(0, tonumber(data.Duration) or 0)
	local ragdollDuration = tonumber(data.RagdollDuration)
	local rootPart = context.rootPart
	local character = context.character

	if typeof(startPosition) ~= "Vector3" or typeof(impactPosition) ~= "Vector3" then
		warn("[CombatPhysics.Knockback.LinearProxy] StartPosition and ImpactPosition are required")
		return
	end
	if rootPart == nil or rootPart.Parent == nil then
		return
	end

	if data.KnockbackStart then
		data.KnockbackStart()
	end

	context:clearBodymovers()
	local collisionGroupToken = context:pushCollisionGroup(Constants.COLLISION_GROUPS.BodyPhysics)
	local function restoreCollisionGroup()
		if collisionGroupToken then
			context:popCollisionGroup(collisionGroupToken)
			collisionGroupToken = nil
		end
	end

	if context.ragdoll then
		if character:GetAttribute("Ragdoll") then
			context.ragdoll:Disable(true)
		end
		context.ragdoll:Enable(data.NetworkOwner or context.character, ragdollDuration)
	end

	local travelVector = impactPosition - startPosition
	local travelVelocity = if duration > 0 and travelVector.Magnitude > 0.001
		then travelVector.Unit * (travelVector.Magnitude / duration)
		else Vector3.zero
	local baseCFrame = rootPart.CFrame
	local finished = false

	local function settleAt(position: Vector3)
		if rootPart.Parent == nil then
			return
		end
		rootPart.CFrame = withPosition(baseCFrame, position)
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
	end

	if duration <= 0 then
		settleAt(impactPosition)
		restoreCollisionGroup()
		if data.KnockbackEnd then
			data.KnockbackEnd()
		end
		return
	end

	local startTime = os.clock()
	while rootPart.Parent ~= nil and character.Parent ~= nil do
		if character:GetAttribute("KnockbackID") ~= knockbackID then
			settleAt(rootPart.Position)
			if context.ragdoll and character:GetAttribute("Ragdoll") then
				context.ragdoll:Disable(true)
			end
			restoreCollisionGroup()
			if data.KnockbackEnd then
				data.KnockbackEnd()
			end
			return
		end

		local alpha = math.clamp((os.clock() - startTime) / duration, 0, 1)
		local currentPosition = startPosition:Lerp(impactPosition, alpha)
		rootPart.CFrame = withPosition(baseCFrame, currentPosition)
		rootPart.AssemblyLinearVelocity = travelVelocity
		rootPart.AssemblyAngularVelocity = Vector3.zero

		if alpha >= 1 then
			finished = true
			break
		end

		RunService.Heartbeat:Wait()
	end

	if finished then
		settleAt(impactPosition)
	else
		settleAt(rootPart.Position)
	end

	restoreCollisionGroup()
	if data.KnockbackEnd then
		data.KnockbackEnd()
	end
end
