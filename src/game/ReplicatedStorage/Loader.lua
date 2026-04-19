local Loader = {}

type PredicateFn = (module: ModuleScript) -> boolean

export type ExecutionContext = {
	phase: string?,
	runtime: string?,
	source: string?,
	logLifecycle: boolean?,
	watchdogSeconds: number?,
}

type LoadedModule = {
	name: string,
	moduleScript: ModuleScript,
	path: string,
	value: any,
	loadSource: string,
}

export type OrderedFatalGroup = {
	context: ExecutionContext?,
	names: { string },
}

local DEFAULT_EXECUTION_CONTEXT: ExecutionContext = {
	phase = "Runtime",
	runtime = "Unknown",
	source = "Unknown",
}

local function normalizeExecutionContext(context: ExecutionContext?): ExecutionContext
	if typeof(context) ~= "table" then
		return DEFAULT_EXECUTION_CONTEXT
	end

	return {
		phase = if typeof(context.phase) == "string" and context.phase ~= "" then context.phase else DEFAULT_EXECUTION_CONTEXT.phase,
		runtime = if typeof(context.runtime) == "string" and context.runtime ~= "" then context.runtime else DEFAULT_EXECUTION_CONTEXT.runtime,
		source = if typeof(context.source) == "string" and context.source ~= "" then context.source else DEFAULT_EXECUTION_CONTEXT.source,
		logLifecycle = context.logLifecycle == true,
		watchdogSeconds = if typeof(context.watchdogSeconds) == "number" and context.watchdogSeconds > 0
			then context.watchdogSeconds
			else nil,
	}
end

local function createTraceback(message: any): string
	return debug.traceback(tostring(message), 2)
end

local function formatPrefix(context: ExecutionContext): string
	return string.format("[Loader][%s][%s]", context.phase, context.runtime)
end

local function formatRequireError(context: ExecutionContext, moduleScript: ModuleScript, loadSource: string, trace: string): string
	return string.format(
		"%s %s require failed at %s under %s:\n%s",
		formatPrefix(context),
		moduleScript.Name,
		moduleScript:GetFullName(),
		loadSource,
		trace
	)
end

local function formatMethodError(
	context: ExecutionContext,
	loadedModule: LoadedModule,
	methodName: string,
	trace: string
): string
	return string.format(
		"%s %s.%s failed at %s under %s:\n%s",
		formatPrefix(context),
		loadedModule.name,
		methodName,
		loadedModule.path,
		loadedModule.loadSource,
		trace
	)
end

local function logLifecycleEvent(
	context: ExecutionContext,
	loadedModule: LoadedModule,
	methodName: string,
	status: string,
	elapsedSeconds: number?
)
	if context.logLifecycle ~= true then
		return
	end

	if elapsedSeconds ~= nil then
		print(string.format(
			"%s %s.%s %s in %.2fs at %s",
			formatPrefix(context),
			loadedModule.name,
			methodName,
			status,
			elapsedSeconds,
			loadedModule.path
		))
		return
	end

	print(string.format(
		"%s %s.%s %s at %s",
		formatPrefix(context),
		loadedModule.name,
		methodName,
		status,
		loadedModule.path
	))
end

local function scheduleLifecycleWatchdog(
	context: ExecutionContext,
	loadedModule: LoadedModule,
	methodName: string,
	completionState: { completed: boolean }
)
	local watchdogSeconds = context.watchdogSeconds
	if typeof(watchdogSeconds) ~= "number" or watchdogSeconds <= 0 then
		return
	end

	task.delay(watchdogSeconds, function()
		if completionState.completed then
			return
		end

		warn(string.format(
			"%s %s.%s is still running after %.2fs at %s",
			formatPrefix(context),
			loadedModule.name,
			methodName,
			watchdogSeconds,
			loadedModule.path
		))
	end)
end

local function requireWithContext(moduleScript: ModuleScript, loadSource: string, context: ExecutionContext): any
	local ok, result = xpcall(function()
		return require(moduleScript)
	end, createTraceback)

	if ok then
		return result
	end

	error(formatRequireError(context, moduleScript, loadSource, result), 0)
end

local function collectLoadedModules(
	instances: { Instance },
	parent: Instance,
	predicate: PredicateFn?,
	context: ExecutionContext?
): { LoadedModule }
	local loadedModules = {}
	local normalizedContext = normalizeExecutionContext(context)
	local loadSource = parent:GetFullName()

	for _, instance in ipairs(instances) do
		if not instance:IsA("ModuleScript") then
			continue
		end

		if predicate and not predicate(instance) then
			continue
		end

		table.insert(loadedModules, {
			name = instance.Name,
			moduleScript = instance,
			path = instance:GetFullName(),
			value = requireWithContext(instance, loadSource, normalizedContext),
			loadSource = loadSource,
		})
	end

	return loadedModules
end

local function invokeLifecycle(loadedModule: LoadedModule, methodName: string, args: { any }, context: ExecutionContext)
	local mod = loadedModule.value
	if typeof(mod) ~= "table" then
		return
	end

	local method = mod[methodName]
	if type(method) ~= "function" then
		return
	end

	local completionState = {
		completed = false,
	}
	local startedAt = os.clock()
	logLifecycleEvent(context, loadedModule, methodName, "starting")
	scheduleLifecycleWatchdog(context, loadedModule, methodName, completionState)

	debug.setmemorycategory(loadedModule.name)
	local ok, result = xpcall(function()
		method(mod, table.unpack(args))
	end, createTraceback)
	completionState.completed = true

	local elapsedSeconds = os.clock() - startedAt
	logLifecycleEvent(context, loadedModule, methodName, "completed", elapsedSeconds)
	if not ok then
		error(formatMethodError(context, loadedModule, methodName, result), 0)
	end
end

function Loader.LoadChildren(parent: Instance, predicate: PredicateFn?, context: ExecutionContext?): { LoadedModule }
	return collectLoadedModules(parent:GetChildren(), parent, predicate, context)
end

function Loader.LoadDescendants(parent: Instance, predicate: PredicateFn?, context: ExecutionContext?): { LoadedModule }
	return collectLoadedModules(parent:GetDescendants(), parent, predicate, context)
end

function Loader.MatchesName(matchName: string): (module: ModuleScript) -> boolean
	return function(moduleScript: ModuleScript): boolean
		return moduleScript.Name:match(matchName) ~= nil
	end
end

function Loader.RunAllFatal(
	loadedModules: { LoadedModule },
	methodName: string,
	context: ExecutionContext?,
	...
)
	local args = { ... }
	local normalizedContext = normalizeExecutionContext(context)

	for _, loadedModule in ipairs(loadedModules) do
		invokeLifecycle(loadedModule, methodName, args, normalizedContext)
	end
end

function Loader.RunOrderedFatal(
	loadedModules: { LoadedModule },
	methodName: string,
	groups: { OrderedFatalGroup },
	defaultContext: ExecutionContext?,
	...
)
	local args = { ... }
	local normalizedDefaultContext = normalizeExecutionContext(defaultContext)
	local remainingModulesByPath = {}

	for _, loadedModule in ipairs(loadedModules) do
		remainingModulesByPath[loadedModule.path] = loadedModule
	end

	for _, group in ipairs(groups) do
		local groupModules = {}
		for _, name in ipairs(group.names or {}) do
			for _, loadedModule in ipairs(loadedModules) do
				if loadedModule.name == name and remainingModulesByPath[loadedModule.path] then
					table.insert(groupModules, loadedModule)
					remainingModulesByPath[loadedModule.path] = nil
				end
			end
		end

		Loader.RunAllFatal(groupModules, methodName, group.context or normalizedDefaultContext, table.unpack(args))
	end
end

function Loader.RunAllReporting(
	loadedModules: { LoadedModule },
	methodName: string,
	context: ExecutionContext?,
	...
)
	local args = { ... }
	local normalizedContext = normalizeExecutionContext(context)

	for _, loadedModule in ipairs(loadedModules) do
		task.spawn(function()
			local ok, result = xpcall(function()
				invokeLifecycle(loadedModule, methodName, args, normalizedContext)
			end, createTraceback)
			if not ok then
				warn(result)
			end
		end)
	end
end

function Loader.ConnectFunctionsReporting(
	loadedModules: { LoadedModule },
	event: RBXScriptSignal,
	methodName: string,
	context: ExecutionContext?
)
	local normalizedContext = normalizeExecutionContext(context)
	event:Connect(function(...)
		Loader.RunAllReporting(loadedModules, methodName, normalizedContext, ...)
	end)
end

function Loader.SpawnAll(loadedModules: { LoadedModule }, methodName: string, ...)
	Loader.RunAllReporting(loadedModules, methodName, DEFAULT_EXECUTION_CONTEXT, ...)
end

function Loader.ConnectFunctions(loadedModules: { LoadedModule }, event: RBXScriptSignal, methodName: string)
	Loader.ConnectFunctionsReporting(loadedModules, event, methodName, DEFAULT_EXECUTION_CONTEXT)
end

return Loader
