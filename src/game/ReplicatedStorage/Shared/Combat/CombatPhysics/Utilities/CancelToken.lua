local CancelToken = {}

function CancelToken.new(onCancel, timeout)
	local token = {
		Cancelled = false,
	}

	function token.Cancel()
		if token.Cancelled then
			return
		end
		token.Cancelled = true
		if onCancel then
			local ok, err = pcall(onCancel)
			if not ok then
				warn("[CombatPhysics.CancelToken] onCancel failed:", err)
			end
		end
	end

	if typeof(timeout) == "number" and timeout > 0 then
		task.delay(timeout, function()
			if not token.Cancelled then
				token.Cancel()
			end
		end)
	end

	return token
end

return CancelToken
