local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local BodyMoverUtil = require(script.Parent.Parent.Utilities.BodyMoverUtil)
local CancelToken = require(script.Parent.Parent.Utilities.CancelToken)
local DebugUtil = require(script.Parent.Parent.Utilities.DebugUtil)
local RaycastUtil = require(script.Parent.Parent.Utilities.RaycastUtil)
local MathUtil = require(script.Parent.Parent.Utilities.MathUtil)
local AnimationUtil = require(script.Parent.Parent.Utilities.AnimationUtil)

local function getRollAnimation()
	local storage = AnimationUtil.getPathingFolders()
	if not storage then
		return nil
	end

	local animations = storage:FindFirstChild("Animations")
	local general = animations and animations:FindFirstChild("General")
	local folder = general and general:FindFirstChild("KnockbackFolder")
	return folder and folder:FindFirstChild("Roll") or nil
end

return function(data, context, knockbackID)
	local moverDuration = data.MoverDuration or 0.2
	local stunDuration = data.StunDuration or moverDuration + 0.25

	local direction = data.Direction
	local anchor = data.Anchor or context.rootPart.CFrame
	local force = data.Force or 40
	local spreadAngle = data.SpreadAngle or { 0, 0 }
	local maxForce = data.MaxForce or Vector3.new(60000, 0, 60000)
	local speed = data.Speed or 25000
	local params = data.RaycastParams or "Map"

	local primaryPart = context.character.PrimaryPart or context.rootPart
	if not primaryPart then
		return
	end

	local groundDetect = workspace:Raycast(primaryPart.Position, Vector3.new(0, -6, 0), RaycastUtil.getParams("Map"))
	if groundDetect then
		primaryPart.CFrame = CFrame.new(groundDetect.Position + Vector3.new(0, 2, 0), anchor.Position)
	end

	local finalDirection = primaryPart.Position + direction * force
	local endPosition = Vector3.new(finalDirection.X, primaryPart.Position.Y, finalDirection.Z)
	direction = MathUtil.calculateSpreadDirection(
		Vector3.new(anchor.Position.X, endPosition.Y, anchor.Position.Z),
		endPosition,
		spreadAngle[1],
		spreadAngle[2]
	)

	local castDirection = direction * force
	local raycastResult = workspace:Raycast(primaryPart.Position, castDirection, RaycastUtil.getParams(params))
	if raycastResult then
		endPosition = Vector3.new(raycastResult.Position.X, endPosition.Y, raycastResult.Position.Z)
	end

	if data.Debug then
		DebugUtil.createDebugPart(endPosition, 2)
	end

	if data.KnockbackStart then
		data.KnockbackStart()
	end

	context:createState("Stunned", stunDuration)
	context:createState("AutoRotate")
	context:createMovement("JumpPower", 0, stunDuration)
	context:createMovement("WalkSpeed", 0, stunDuration)

	local rollAnimation = getRollAnimation()
	local length = 1.25
	local perc = length / moverDuration
	if rollAnimation then
		context:playAnimation(rollAnimation, 0.1, perc)
	end

	local numberValue = Instance.new("NumberValue")
	numberValue.Value = data.Tween and data.Tween.Start or speed
	TweenService:Create(numberValue, TweenInfo.new(perc), { Value = 0 }):Play()

	context:clearBodymovers()
	if context.ragdoll then
		context.ragdoll:Disable(true)
	end

	local bodyPosition = BodyMoverUtil.createPosition(context.rootPart)
	if not bodyPosition then
		numberValue:Destroy()
		return
	end
	bodyPosition.MaxForce = maxForce
	bodyPosition.P = numberValue.Value
	bodyPosition.Position = endPosition

	local bodyGyro = BodyMoverUtil.createGyro(context.rootPart)
	if not bodyGyro then
		bodyPosition:Destroy()
		numberValue:Destroy()
		return
	end
	bodyGyro.P = 20000
	bodyGyro.CFrame = CFrame.lookAt(endPosition, Vector3.new(anchor.Position.X, endPosition.Y, anchor.Position.Z))
	bodyGyro.MaxTorque = Vector3.one * 9e9

	if data.Tween then
		TweenService:Create(numberValue, TweenInfo.new(moverDuration), { Value = data.Tween.End or 0 }):Play()
	end

	local cancelEvent = CancelToken.new(function()
		if bodyGyro and bodyGyro.Parent then
			bodyGyro:Destroy()
		end
		if bodyPosition and bodyPosition.Parent then
			bodyPosition:Destroy()
		end
		if numberValue and numberValue.Parent then
			numberValue:Destroy()
		end
	end, moverDuration)

	local startTime = os.clock()
	local characterPlayer = Players:GetPlayerFromCharacter(context.character)

	repeat
		task.wait()
		bodyGyro.CFrame = CFrame.lookAt(endPosition, Vector3.new(anchor.Position.X, endPosition.Y, anchor.Position.Z))
		bodyPosition.P = numberValue.Value
	until os.clock() - startTime >= moverDuration
		or cancelEvent.Cancelled
		or context.character:GetAttribute("KnockbackID") ~= knockbackID

	if bodyPosition and bodyPosition.Parent then
		bodyPosition:Destroy()
	end
	if bodyGyro and bodyGyro.Parent then
		bodyGyro:Destroy()
	end

	context:removeState("AutoRotate")

	if not characterPlayer then
		context:setNetworkOwner(nil)
	end

	if numberValue and numberValue.Parent then
		numberValue:Destroy()
	end
	if data.KnockbackEnd then
		data.KnockbackEnd()
	end
end
