--[[
	Huge thanks to EgoMoose for the original implementation. Here's the original
	comment that sparked this approach:

	https://github.com/flipbook-labs/module-loader/pull/34#issuecomment-4082559439
]]

local ScriptService = game:GetService("ScriptService")

local LoadError = require("@root/LoadError")
local bind = require("@root/bind")
local compileWithLoadstring = require("@root/compileWithLoadstring")
local createModuleRegistry = require("@root/createModuleRegistry")
local getModuleSource = require("@root/getModuleSource")
local loadWithLoadmodule = require("@root/loadWithLoadmodule")
local resolveInstancePath = require("@root/resolveInstancePath")
local setModuleSource = require("@root/setModuleSource")
local types = require("@root/types")

type ModuleFactory = (...unknown) -> () -> ...unknown

type LoadedModule = types.LoadedModule
type ModuleLoader = types.ModuleLoader
type ModuleRegistry = types.ModuleRegistry
type ModuleFunction = types.ModuleFunction
type ModuleLoaderDependencies = types.ModuleLoaderDependencies
type ResolveModulePath = types.ResolveModulePath

type LoaderContext = {
	dependencies: ModuleLoaderDependencies,

	--[[
		Set once a tmpScript require fails with NON_ROBLOXSCRIPT_REQUIRE_ERROR.
		All of a plugin's code runs at one security level, so every later
		tmpScript would fail the same way and later modules go straight to
		`debug.loadmodule`.
	]]
	shouldUseLoadmodule: boolean,

	loadmoduleCleanupFns: { () -> () },

	traceOnce: ErrorHandler,
}

-- Unique sentinel table for sandbox detection. When a loader evaluates modules,
-- it passes a proxy _G table with this sentinel; natively-required ModuleLoader
-- sees only the real _G and cannot find this sentinel.
local SANDBOX_MARKER = { __internal = true }

-- Code running at RobloxScript security, such as a built-in plugin, can't
-- require the tmpScript because the ModuleScripts it creates don't share that
-- security level.
local NON_ROBLOXSCRIPT_REQUIRE_ERROR = "Cannot require a non-RobloxScript module from a RobloxScript"

--[[
	ScriptService:ResolveModulePath resolves string requires the same way native
	`require` does, including aliases from `.config` modules. It's gated by
	DFFlagScriptServiceResolveModulePath, which user code can't read, so the
	method is probed instead. Once the flag rolls out, the probe and
	`resolveInstancePath` can be deleted.
]]
local isResolveModulePathEnabled = pcall(function()
	return ScriptService:ResolveModulePath(script, "@self")
end)

local DEFAULT_DEPENDENCIES: ModuleLoaderDependencies = {
	compile = compileWithLoadstring,
	require = require,
	-- debug.loadmodule only exists behind an engine flag, so Roblox's type
	-- definitions leave it out and `debug.loadmodule` fails analysis. rawget
	-- reads the same field without the type checker looking it up.
	loadmodule = rawget(debug, "loadmodule"),
	resolveModulePath = if isResolveModulePathEnabled
		then bind(ScriptService.ResolveModulePath, ScriptService)
		else nil,
}

--[[
	Every require runs its module inside `xpcall`, and a failed require re-raises
	the error into the module that required it. So an error deep in a chain of
	requires passes through one `xpcall` per module in the chain.

	The innermost handler runs while the failing module is still on the stack,
	so the traceback it adds already lists every require above it. The handler
	this creates turns the error into a LoadError carrying that traceback. Each
	re-raise uses `error(err, 0)`, which passes the LoadError on unchanged. The
	handler remembers the last LoadError it made and passes that one through as
	it is, so the stack appears once instead of once per module.

	Each loader creates its own handler, so a LoadError made by one loader is
	never skipped by another. When another loader's LoadError reaches this
	handler, it keeps the message and adds this loader's stack after the
	traceback the LoadError already has.

	Strings, numbers, and nil become a LoadError's message. Any other value a
	module raises, such as a table, passes through as it was raised, so code
	that catches its own error objects still gets them back.
]]
type ErrorHandler = (err: unknown) -> unknown

local function createTraceOnce(): ErrorHandler
	local lastLoadError: unknown

	return function(err: unknown): unknown
		-- `lastLoadError` starts out nil, so a nil error would otherwise look
		-- like one this handler already made.
		if err ~= nil and err == lastLoadError then
			return err
		end

		local loadError: unknown
		if LoadError.is(err) then
			local otherLoadError = err :: LoadError.LoadError
			local stack = debug.traceback(nil, 2)
			loadError = LoadError.new(
				otherLoadError.message,
				if otherLoadError.traceback == "" then stack else `{otherLoadError.traceback}\n{stack}`
			)
		elseif err == nil or type(err) == "string" or type(err) == "number" then
			loadError = LoadError.new(tostring(err), debug.traceback(nil, 2))
		else
			return err
		end

		lastLoadError = loadError
		return loadError
	end
end

local function makeModuleFunction(compiledOuter): ModuleFunction
	return function(...)
		return compiledOuter(...)()
	end
end

local function getModuleFunctionWithLoadmodule(moduleScript: ModuleScript, context: LoaderContext): ModuleFunction?
	local moduleFunction, err, cleanupFn = loadWithLoadmodule(context.dependencies.loadmodule, moduleScript)

	if err then
		error(err, 0)
	end

	if cleanupFn then
		table.insert(context.loadmoduleCleanupFns, cleanupFn)
	end

	return moduleFunction
end

local function getModuleFunction(
	moduleScript: ModuleScript,
	params: { string }?,
	context: LoaderContext
): ModuleFunction
	local nativeRequire: ModuleFunction = function()
		return context.dependencies.require(moduleScript)
	end

	local mergedParams = { "script", "require" }
	if params then
		for _, param in params do
			table.insert(mergedParams, param)
		end
	end

	local source = getModuleSource(moduleScript)

	-- If we can't read the source (e.g. client userspace), fall back to native
	-- require and skip the rest.
	if not source then
		return nativeRequire
	end

	-- This all gets collapsed onto a single line so we retain line numbers of
	-- the source.
	local newSource = table.concat({
		`return function({table.concat(mergedParams, ", ")})`,

		--[[
		    1. The source is wrapped in another anonymous function to ensure the
			   top-level function arguments do not contribute to the source's
			   200 locals limit.

			   Certain modules like React's `ReactFiberWorkLoop.new` bump up
		       against that limit, and us coming in with new allocations causes
		       an error when requiring.

			2. If the original source uses varargs we need to make sure we
		       include it in the function parameters, otherwise the source will
		       error when it tries to access the varargs. And for some reason,
		       it errors when varargs are used in a TYPE DEFINITION!! Fun.
		]]
		"return function(...)",
		source,
		"end",

		"end",
	}, " ")

	-- A nil chunkFn with a message means a real syntax error (surface it); a
	-- nil chunkFn with no message means loadstring is disabled (fall through to
	-- tmpScript).
	local chunkFn, syntaxErrorMessage = context.dependencies.compile(newSource, moduleScript:GetFullName())

	if chunkFn then
		local ok, result = xpcall(chunkFn, context.traceOnce)
		if ok and typeof(result) == "function" then
			-- I don't think there's a way to narrow this further but we know by
			-- this point we we're getting back the newSource result so I think
			-- this is fine
			return makeModuleFunction(result :: ModuleFactory)
		end
		error(result, 0)
	end

	if syntaxErrorMessage then
		error(syntaxErrorMessage, 0)
	end

	if context.shouldUseLoadmodule then
		local moduleFunction = getModuleFunctionWithLoadmodule(moduleScript, context)
		if moduleFunction then
			return moduleFunction
		end
	end

	local tmpScript = Instance.new("ModuleScript")
	tmpScript.Name = moduleScript.Name
	tmpScript.Archivable = false

	if not setModuleSource(tmpScript, newSource) then
		return nativeRequire
	end

	local createModuleFunction: ModuleFactory
	local ok, err = xpcall(function()
		createModuleFunction = context.dependencies.require(tmpScript) :: ModuleFactory
	end, context.traceOnce)

	tmpScript:Destroy()

	if not ok then
		if tostring(err):find(NON_ROBLOXSCRIPT_REQUIRE_ERROR, 1, true) then
			local moduleFunction = getModuleFunctionWithLoadmodule(moduleScript, context)
			if moduleFunction then
				context.shouldUseLoadmodule = true
				return moduleFunction
			end
		end

		error(err, 0)
	end

	return makeModuleFunction(createModuleFunction)
end

local function weak<K, V>(tab: { [K]: V }): { [K]: V }
	-- setmetatable's return type carries a metatable that generic for loops don't accept, so the
	-- result is passed through `unknown` and returned under the declared type.
	local weakTab: unknown = setmetatable(tab, { __mode = "k" })
	return weakTab :: { [K]: V }
end

function createModuleLoader(dependencies: ModuleLoaderDependencies?): ModuleLoader
	local moduleRegistry = createModuleRegistry()
	local changedConnections = weak<<ModuleScript, RBXScriptConnection>>({})
	local globals = setmetatable({}, { __index = _G }) :: typeof(_G)
	local context: LoaderContext = {
		dependencies = dependencies or DEFAULT_DEPENDENCIES,
		shouldUseLoadmodule = false,
		loadmoduleCleanupFns = {},
		traceOnce = createTraceOnce(),
	}

	-- Plant the sandbox marker on the proxy globals so code evaluated through
	-- this loader can detect they are running in a sandboxed context.
	rawset(globals, "__MODULE_LOADER_SANDBOX__", SANDBOX_MARKER)

	local function _getModuleRegistry()
		return moduleRegistry
	end

	local loadedModuleChanged = Instance.new("BindableEvent")

	local function cache(moduleScript: ModuleScript, ...: unknown)
		local loadedModule: LoadedModule = {
			instance = moduleScript,
			exports = table.pack(...),
			isLoaded = true,
		}

		moduleRegistry.add(moduleScript, loadedModule)
	end

	local function require(moduleScript: ModuleScript): ...unknown?
		local function weHaveRequireAtHome(module: ModuleScript | string, caller: ModuleScript?)
			local resolvedModule: ModuleScript
			if type(module) == "string" then
				local relativeTo: Instance = if caller then caller else moduleScript
				local resolve: ResolveModulePath = context.dependencies.resolveModulePath or resolveInstancePath
				resolvedModule = resolve(relativeTo, module) :: ModuleScript
			else
				resolvedModule = module
			end

			local existingModule = moduleRegistry.getByInstance(resolvedModule)
			if existingModule then
				if existingModule.isLoaded then
					assert(existingModule.exports, `exports of existing module {resolvedModule} were not set`)
					return table.unpack(existingModule.exports, 1, existingModule.exports.n)
				else
					error("Requested module was required recursively")
				end
			end

			local loadedModule: LoadedModule = {
				instance = resolvedModule,
				exports = nil,
				isLoaded = false,
			}

			moduleRegistry.add(resolvedModule, loadedModule)

			local moduleFunction = getModuleFunction(resolvedModule, { "_G" }, context)

			local function childRequire(childModule: ModuleScript | string)
				return weHaveRequireAtHome(childModule, resolvedModule)
			end

			local exports: types.Packed<unknown>
			local ok, err = xpcall(function()
				-- Notice how the arguments here map to the params in
				-- `getModuleFunction`, which in this case is `script`,
				-- `require`, and `_G` in the context of the loaded module.
				exports = table.pack(moduleFunction(resolvedModule, childRequire, globals))
			end, context.traceOnce)

			if not ok then
				moduleRegistry.remove(resolvedModule)
				error(err, 0)
			end

			if not changedConnections[resolvedModule] then
				changedConnections[resolvedModule] = resolvedModule.Changed:Connect(function()
					loadedModuleChanged:Fire(resolvedModule)
				end)
			end

			loadedModule.exports = exports
			loadedModule.isLoaded = true

			return table.unpack(exports, 1, exports.n)
		end

		--[=[
			A module's own syntax error is raised before anything traces it, so
			it reaches this point as a string. Wrapping it here means every
			string error a caller sees is a LoadError, traced or not.
		]=]
		local results = table.pack(pcall(weHaveRequireAtHome, moduleScript, nil))
		if not results[1] then
			local err = results[2]
			if type(err) == "string" then
				err = LoadError.new(err, "")
			end
			error(err, 0)
		end
		return table.unpack(results, 2, results.n)
	end

	local function clear()
		moduleRegistry.reset()

		-- Clearing user-defined globals also wipes the sandbox marker, so it
		-- has to be replanted for modules evaluated after the clear.
		table.clear(globals)
		rawset(globals, "__MODULE_LOADER_SANDBOX__", SANDBOX_MARKER)

		for _, connection in changedConnections do
			connection:Disconnect()
		end
		table.clear(changedConnections)

		for _, cleanupFn in context.loadmoduleCleanupFns do
			pcall(cleanupFn)
		end
		table.clear(context.loadmoduleCleanupFns)
	end

	return {
		_getModuleRegistry = _getModuleRegistry,

		cache = cache,
		loadModule = require,
		require = require,
		clear = clear,

		loadedModuleChanged = loadedModuleChanged.Event,
	}
end

return createModuleLoader
