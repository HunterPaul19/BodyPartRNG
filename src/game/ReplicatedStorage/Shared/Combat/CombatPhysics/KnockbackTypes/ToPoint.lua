local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Trove = require(script.Parent.Parent.Utilities.Trove)
local BodyMoverUtil = require(script.Parent.Parent.Utilities.BodyMoverUtil)

return function(data, context)
	local moverDuration = data.Duration
	local ragdollDuration = data.RagdollDuration
	local targetPosition = data.Position
	local power = data.Power
	local maxForce = data.MaxForce or Vector3.new(math.huge, math.huge, math.huge)
	local follow = data.Follow

	if data.KnockbackStart then
		data.KnockbackStart()
	end

	context:clearBodymovers()
	if context.ragdoll then
		context.ragdoll:Disable(true)
	end

	if data.IFrames then
		context:createState("IFrames", data.IFrames)
	end

	if ragdollDuration and context.ragdoll then
		context.ragdoll:Enable(data.NetworkOwner or context.character, typeof(ragdollDuration) == "number" and ragdollDuration or nil)
	end

	local markerPart
	local trove = Trove.new()

	local function createBodyPosition(stiffness, position)
		if not follow then
			markerPart = Instance.new("Part")
			markerPart.Size = Vector3.new(1, 1, 1)
			markerPart.Position = position
			markerPart.Parent = workspace:FindFirstChild("Visuals") or workspace
			markerPart.Transparency = 1
			markerPart.Anchored = true
			markerPart.CanCollide = false
			if moverDuration then
				Debris:AddItem(markerPart, moverDuration)
			end
		end

		local bodyPosition = BodyMoverUtil.createPosition(context.rootPart)
		if not bodyPosition then
			return nil
		end

		bodyPosition.P = stiffness or 1850
		bodyPosition.MaxForce = maxForce

		if follow then
			trove:Connect(RunService.Heartbeat, function()
				if follow.Parent then
					bodyPosition.Position = follow.Position
				end
			end)
		else
			bodyPosition.Position = position
		end

		return bodyPosition
	end

	local bodyPosition = createBodyPosition(power, targetPosition)
	if not bodyPosition then
		return
	end

	local function cleanup()
		trove:Destroy()
		if bodyPosition and bodyPosition.Parent then
			bodyPosition:Destroy()
		end
	end

	if not follow then
		trove:Connect(RunService.Heartbeat, function()
			if not bodyPosition.Parent then
				cleanup()
				return
			end

			local currentPrimary = context.character.PrimaryPart or context.rootPart
			if markerPart and currentPrimary and (currentPrimary.Position - markerPart.Position).Magnitude <= (data.Radius or 5) then
				if ragdollDuration and typeof(ragdollDuration) == "boolean" and context.ragdoll then
					context.ragdoll:Disable()
				end
				cleanup()
				if data.Callback then
					data.Callback(context.character, targetPosition)
				end
			end
		end)
	else
		trove:Connect(follow.Destroying, function()
			if ragdollDuration and typeof(ragdollDuration) == "boolean" and context.ragdoll then
				context.ragdoll:Disable()
			end
			cleanup()
			if data.Callback then
				data.Callback(context.character, targetPosition)
			end
		end)
	end
end
