local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Combat.Constants)
local BodyMoverUtil = require(script.Parent.Parent.Utilities.BodyMoverUtil)
local CancelToken = require(script.Parent.Parent.Utilities.CancelToken)
local DebugUtil = require(script.Parent.Parent.Utilities.DebugUtil)

local DEBUG_DEFAULT = true

local function shouldDebug(character)
	local workspaceDebug = workspace:GetAttribute("CombatPhysicsDebug")
	if workspaceDebug ~= nil then
		return workspaceDebug
	end
	if character then
		local charDebug = character:GetAttribute("CombatPhysicsDebug")
		if charDebug ~= nil then
			return charDebug
		end
	end
	return DEBUG_DEFAULT
end

local function label(character)
	if not character then
		return "nil"
	end

	local debugId = "?"
	local ok, id = pcall(function()
		return character:GetDebugId(0)
	end)
	if ok and id then
		debugId = id
	end

	return character:GetFullName() .. "|" .. debugId
end

local function log(character, ...)
	if not shouldDebug(character) then
		return
	end
	print("[CombatPhysics.Knockback.Default][" .. label(character) .. "]", ...)
end

return function(data, context, knockbackID)
	local character = context.character
	local moverDuration = data.Duration or 0.2
	local ragdollDuration = data.RagdollDuration or moverDuration + 2
	local groundMode = type(data.GroundMode) == "string" and data.GroundMode or "Default"

	local landedData = data.Landed
	local delayTime = landedData and (landedData.Delay or 0.2) or 0.15
	local distanceFromGround = landedData and (landedData.DistanceFromGround or 2) or 2
	local onLand = landedData and landedData.OnLand or nil

	local landedDisableRagdollDelay = landedData and landedData.DisableRagdollDelay or nil
	if landedDisableRagdollDelay ~= nil then
		if typeof(landedDisableRagdollDelay) ~= "number" then
			warn(
				"[CombatPhysics.Knockback.Default] Landed.DisableRagdollDelay must be number",
				character and character:GetFullName() or "nil"
			)
			landedDisableRagdollDelay = nil
		else
			landedDisableRagdollDelay = math.max(0, landedDisableRagdollDelay)
		end
	end

	local useLandedRagdollDisable = landedDisableRagdollDelay ~= nil
	local landedDisableTimeout = landedData and landedData.DisableRagdollTimeout or nil
	if useLandedRagdollDisable then
		if typeof(landedDisableTimeout) ~= "number" then
			landedDisableTimeout = math.max(ragdollDuration + 2, 4)
		else
			landedDisableTimeout = math.max(0.25, landedDisableTimeout)
		end
	end

	local direction = data.Direction
	if not direction then
		warn("[CombatPhysics.Knockback.Default] Direction required", character and character:GetFullName() or "nil")
		return
	end

	if data.KnockbackStart then
		data.KnockbackStart()
	end

	context:clearBodymovers()
	context:setCollisionGroup(Constants.COLLISION_GROUPS.HitboxNoCollide)

	if data.CanDashM1 then
		local stateDuration = typeof(data.CanDashM1) == "number" and data.CanDashM1 or ragdollDuration / 3
		context:createState("DashM1_Ragdoll", stateDuration)
		log(character, "DashM1_Ragdoll state", stateDuration)
	end

	local maxForce = data.VelocitySettings and data.VelocitySettings.MaxForce or Vector3.new(60000, 60000, 60000)
	if data.Debug then
		DebugUtil.createDebugPart(direction)
	end

	local bodyVelocity = BodyMoverUtil.createVelocity(context.rootPart, data.VelocityParent)
	if not bodyVelocity then
		warn("[CombatPhysics.Knockback.Default] Failed to create BodyVelocity", character and character:GetFullName() or "nil")
		return
	end
	bodyVelocity.MaxForce = maxForce
	bodyVelocity.Velocity = direction

	if context.ragdoll then
		if useLandedRagdollDisable then
			context.ragdoll:Enable(data.NetworkOwner)
		else
			context.ragdoll:Enable(data.NetworkOwner, ragdollDuration)
		end
	else
		warn("[CombatPhysics.Knockback.Default] Missing context.ragdoll", character and character:GetFullName() or "nil")
	end

	if character:GetAttribute("Owner") then
		context:createState("HardIFrames", ragdollDuration + 2)
	end

	local cancelEvent = CancelToken.new(function()
		if bodyVelocity and bodyVelocity.Parent then
			bodyVelocity:Destroy()
		end
	end)

	if data.Stun then
		context:createState("Stunned", data.Stun)
	end

	if useLandedRagdollDisable and context.ragdoll then
		task.delay(landedDisableTimeout, function()
			if not character or character.Parent == nil then
				return
			end
			if character:GetAttribute("KnockbackID") ~= knockbackID then
				return
			end
			if character:GetAttribute("Ragdoll") then
				context.ragdoll:Disable(true)
			end
		end)
	end

	local startTime = os.clock()
	repeat
		task.wait()
	until os.clock() - startTime >= moverDuration
		or cancelEvent.Cancelled
		or character:GetAttribute("KnockbackID") ~= knockbackID

	if bodyVelocity and bodyVelocity.Parent then
		bodyVelocity:Destroy()
	end
	if data.KnockbackEnd then
		data.KnockbackEnd()
	end

	local anticipateOptions = nil
	if groundMode == "DeterministicMap" then
		anticipateOptions = {
			groundMode = "DeterministicMap",
		}
	end

	task.delay(delayTime, function()
		BodyMoverUtil.anticipateLand(character, distanceFromGround, function()
			if not cancelEvent.Cancelled then
				cancelEvent.Cancel()
			end

			if character:GetAttribute("KnockbackID") == knockbackID then
				context:setCollisionGroup(Constants.COLLISION_GROUPS.Hitbox)
				context:createState("IFrames", data.IFrames or (character:GetAttribute("Owner") and 1 or 0.2))
				context:createState("AntiStunned", data.AntiStun ~= nil and data.AntiStun or 0.6)

				if useLandedRagdollDisable and context.ragdoll then
					task.delay(landedDisableRagdollDelay, function()
						if not character or character.Parent == nil then
							return
						end
						if character:GetAttribute("KnockbackID") ~= knockbackID then
							return
						end
						context.ragdoll:Disable(true)
					end)
				end

				if onLand then
					onLand()
				end
			end
		end, 5, anticipateOptions)
	end)
end
