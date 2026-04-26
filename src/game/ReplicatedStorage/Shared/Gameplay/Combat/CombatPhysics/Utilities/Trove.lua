local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Trove = {}
Trove.__index = Trove

function Trove.new()
	return setmetatable({ _tasks = {} }, Trove)
end

function Trove:Add(task)
	table.insert(self._tasks, task)
	return task
end

function Trove:Connect(signal, callback)
	local connection = signal:Connect(callback)
	self:Add(connection)
	return connection
end

function Trove:Remove(taskToRemove)
	for index = #self._tasks, 1, -1 do
		if self._tasks[index] == taskToRemove then
			table.remove(self._tasks, index)
			return true
		end
	end

	return false
end

local function cleanupTask(task)
	local kind = typeof(task)
	if kind == "RBXScriptConnection" then
		if task.Connected then
			task:Disconnect()
		end
		return
	end

	if kind == "Instance" then
		if task.Parent ~= nil then
			task:Destroy()
		end
		return
	end

	if kind == "function" then
		task()
		return
	end

	if kind == "table" then
		if typeof(task.Destroy) == "function" then
			task:Destroy()
		elseif typeof(task.Cleanup) == "function" then
			task:Cleanup()
		elseif typeof(task.Disconnect) == "function" then
			task:Disconnect()
		end
	end
end

function Trove:Destroy()
	for i = #self._tasks, 1, -1 do
		local task = self._tasks[i]
		self._tasks[i] = nil
		local ok, err = pcall(cleanupTask, task)
		if not ok then
			Logger.Warn("[CombatPhysics.Trove] Cleanup failed:", err)
		end
	end
end

return Trove
