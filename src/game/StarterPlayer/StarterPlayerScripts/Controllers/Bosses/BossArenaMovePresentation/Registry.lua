local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Diagnostics"):WaitForChild("Logger"))

local Registry = {}

local HANDLERS_FOLDER_NAME = "Handlers"

local function warnWithPrefix(message: string)
	Logger.Warn(string.format("[BossArenaMovePresentationRegistry] %s", message))
end

local function bindHandler(handler, ctx)
	return setmetatable({}, {
		__index = function(_, key)
			local handlerValue = handler[key]
			if handlerValue ~= nil then
				return handlerValue
			end
			return ctx[key]
		end,
	})
end

local function collectHandlerModules(root: Instance): { ModuleScript }
	local modules = {}
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ModuleScript") then
			table.insert(modules, descendant)
		end
	end
	table.sort(modules, function(left, right)
		return left:GetFullName() < right:GetFullName()
	end)
	return modules
end

local function requireHandler(moduleScript: ModuleScript)
	local ok, handler = pcall(require, moduleScript)
	if not ok then
		warnWithPrefix(string.format("Failed to require handler %s: %s", moduleScript:GetFullName(), tostring(handler)))
		return nil
	end
	if type(handler) ~= "table" then
		warnWithPrefix(string.format("Handler %s returned %s instead of table.", moduleScript:GetFullName(), typeof(handler)))
		return nil
	end
	if type(handler.moduleIds) ~= "table" then
		warnWithPrefix(string.format("Handler %s is missing moduleIds.", moduleScript:GetFullName()))
		return nil
	end
	return handler
end

function Registry.new(ctx)
	local byModuleId = {}
	local handlersRoot = script.Parent:FindFirstChild(HANDLERS_FOLDER_NAME)
	if not handlersRoot then
		warnWithPrefix("Handlers folder is missing.")
		return byModuleId
	end

	for _, moduleScript in ipairs(collectHandlerModules(handlersRoot)) do
		local handler = requireHandler(moduleScript)
		if handler == nil then
			continue
		end

		local runtimeHandler = bindHandler(handler, ctx)
		for _, moduleId in ipairs(handler.moduleIds) do
			if type(moduleId) == "string" and moduleId ~= "" then
				byModuleId[moduleId] = runtimeHandler
			else
				warnWithPrefix(string.format("Handler %s has invalid moduleId %s.", moduleScript:GetFullName(), tostring(moduleId)))
			end
		end
	end

	return byModuleId
end

return Registry
