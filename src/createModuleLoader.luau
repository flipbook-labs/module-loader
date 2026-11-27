--[[
	Huge thanks to EgoMoose for the original implementation. Here's the original
	comment that sparked this approach:

	https://github.com/flipbook-labs/module-loader/pull/34#issuecomment-4082559439
]]

local ScriptService = game:GetService("ScriptService")

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
type ModuleLoadError = types.ModuleLoadError
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

	-- The error from the most recent failed `require`, kept for
	-- `getLastError`.
	lastError: ModuleLoadError?,
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
	so the stack it records already lists every require above it. The error
	itself passes on untouched: the handler returns it as it was raised, and
	each re-raise uses `error(err, 0)`, which adds nothing to a message. The
	outer handlers see the same error again and keep the record they already
	have, so it holds the deepest stack. A caller reads the record with
	`getLastError`.
]]
type ErrorHandler = (err: unknown) -> unknown

local function createErrorRecorder(context: LoaderContext): ErrorHandler
	return function(err: unknown): unknown
		local lastError = context.lastError
		if lastError and rawequal(lastError.err, err) then
			return err
		end
		-- Level 2 starts the stack at the code that raised the error, leaving
		-- out this handler.
		context.lastError = {
			err = err,
			traceback = debug.traceback(nil, 2),
		}
		return err
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
		local ok, result = pcall(chunkFn)
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
	local ok, err = pcall(function()
		createModuleFunction = context.dependencies.require(tmpScript) :: ModuleFactory
	end)

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

--[=[
	ModuleScript loader that bypasses Roblox's require cache.

	Roblox caches what a module returns the first time it's required, so a
	change to the module only takes effect after the place reloads. A loader
	ignores that cache: require a module, change it, clear the loader, and
	require it again to run the new code.

	```lua
	local ModuleLoader = require(ReplicatedStorage.Packages.ModuleLoader)

	local loader = ModuleLoader.createModuleLoader()
	local result = loader.require(module)

	loader.loadedModuleChanged:Connect(function()
		loader.clear()
		result = loader.require(module)
	end)
	```

	@class ModuleLoader
]=]

function createModuleLoader(dependencies: ModuleLoaderDependencies?): ModuleLoader
	local moduleRegistry = createModuleRegistry()
	local changedConnections = weak<<ModuleScript, RBXScriptConnection>>({})
	local globals = setmetatable({}, { __index = _G }) :: typeof(_G)
	local context: LoaderContext = {
		dependencies = dependencies or DEFAULT_DEPENDENCIES,
		shouldUseLoadmodule = false,
		loadmoduleCleanupFns = {},
		lastError = nil,
	}
	local recordError = createErrorRecorder(context)

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
		local weHaveRequireAtHome: (module: ModuleScript | string, caller: ModuleScript?) -> ...unknown

		--[[
			Some requires start a load of their own rather than continue one:
			the call to this `require`, and a require made by a module that has
			already finished loading, such as one inside a function the module
			returns. A record left from before would describe a different
			failure, and an equal error raised now would keep it, so each of
			these loads starts without one. One that succeeds ends without one
			too, even when a module inside it caught a failed require.

			An error raised before the first module runs, such as its syntax
			error, happens outside every module's `xpcall`. The `xpcall` here
			records those too.
		]]
		local function loadOnItsOwn(module: ModuleScript | string, caller: ModuleScript?): ...unknown
			context.lastError = nil
			local results = table.pack(xpcall(weHaveRequireAtHome, recordError, module, caller))
			if not results[1] then
				error(results[2], 0)
			end
			context.lastError = nil
			return table.unpack(results, 2, results.n)
		end

		weHaveRequireAtHome = function(module: ModuleScript | string, caller: ModuleScript?)
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
				if moduleRegistry.getByInstance(resolvedModule) then
					return loadOnItsOwn(childModule, resolvedModule)
				end
				return weHaveRequireAtHome(childModule, resolvedModule)
			end

			local exports: types.Packed<unknown>
			local ok, err = xpcall(function()
				-- Notice how the arguments here map to the params in
				-- `getModuleFunction`, which in this case is `script`,
				-- `require`, and `_G` in the context of the loaded module.
				exports = table.pack(moduleFunction(resolvedModule, childRequire, globals))
			end, recordError)

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

		return loadOnItsOwn(moduleScript, nil)
	end

	local function getLastError(): ModuleLoadError?
		return context.lastError
	end

	local function clear()
		moduleRegistry.reset()
		context.lastError = nil

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
		getLastError = getLastError,

		loadedModuleChanged = loadedModuleChanged.Event,
	}
end

return createModuleLoader
