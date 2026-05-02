local RemoteFunctionTimeout = {}

RemoteFunctionTimeout.DefaultTimeoutSeconds = 8

local function resolveTimeout(timeoutSeconds: number?): number
	local resolved = tonumber(timeoutSeconds) or RemoteFunctionTimeout.DefaultTimeoutSeconds
	return math.max(0.5, resolved)
end

function RemoteFunctionTimeout.Invoke(remote: RemoteFunction, payload: any?, timeoutSeconds: number?): (boolean, any, boolean)
	local timeout = resolveTimeout(timeoutSeconds)
	local completed = false
	local finished = Instance.new("BindableEvent")

	task.spawn(function()
		local ok, result = pcall(function()
			if payload ~= nil then
				return remote:InvokeServer(payload)
			end

			return remote:InvokeServer()
		end)

		if completed then
			return
		end

		completed = true
		finished:Fire({
			ok = ok,
			result = result,
			timedOut = false,
		})
	end)

	task.delay(timeout, function()
		if completed then
			return
		end

		completed = true
		finished:Fire({
			ok = false,
			result = string.format("Timed out after %.1f seconds.", timeout),
			timedOut = true,
		})
	end)

	local response = finished.Event:Wait()
	finished:Destroy()
	return response.ok == true, response.result, response.timedOut == true
end

return RemoteFunctionTimeout
