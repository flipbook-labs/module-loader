--[[
	Huge thanks to EgoMoose for the original implementation. Here's the original
	comment that sparked this approach:

	https://github.com/flipbook-labs/module-loader/pull/34#issuecomment-4082559439
]]

local compileWithLoadstring = require("@root/compileWithLoadstring")
local createModuleRegistry = require("@root/createModuleRegistry")
local getModuleSource = require("@root/getModuleSource")
local resolveInstancePath = require("@root/resolveInstancePath")
local setModuleSource = require("@root/setModuleSource")
local types = require("@root/types")

type LoadedModule = types.LoadedModule
type ModuleLoader = types.ModuleLoader
type ModuleRegistry = types.ModuleRegistry
type ModuleFunction = types.ModuleFunction

--[=[
	Injectable dependencies for testing. The public `createModuleLoader()` uses
	real implementations; tests can inject mocks/spies to simulate non-RobloxScript
	contexts and FFlag states.
]=]
type ResolverDeps = {
	require: (ModuleScript) -> ...unknown?,
	loadmodule: any?,
	getSource: (ModuleScript) -> string?,
	compile: ((string, string) -> (any?, string?))?,
}

local NON_ROBLOXSCRIPT_ERROR = "Cannot require a non-RobloxScript module from a RobloxScript"

--[=[
	`debug.loadmodule` must be called on the **original** ModuleScript — not the
	temporary wrapper ModuleScript used for `require`. Loading the wrapper yields a
	compiled chunk shaped like a normal ModuleScript (`return …`), not the
	double-factory shape produced by `require(tmpScript)`, which led to errors such
	as indexing a returned table like a callable factory.

	Roblox signature: (moduleScript) -> (moduleChunk?, errorMessage?, cleanupFn?)
	`moduleChunk` runs the module body once (after `setfenv`) and returns its exports.
]=]
local function tryGetModuleFunctionWithLoadmodule(
	originalModuleScript: ModuleScript,
	loadmoduleFn: any?,
	cleanupAccumulator: { () -> () }?
): ModuleFunction?
	if typeof(loadmoduleFn) ~= "function" then
		return nil
	end

	local loadOk, moduleChunk, _errorMessage, cleanupFn = pcall(loadmoduleFn :: any, originalModuleScript)
	if not loadOk or typeof(moduleChunk) ~= "function" then
		return nil
	end

	if cleanupFn ~= nil and cleanupAccumulator then
		table.insert(cleanupAccumulator, cleanupFn :: () -> ())
	end

	local defaultEnvironment = getfenv(moduleChunk :: any)

	-- Match the tmpScript/`require` path: a factory `(script, require, _G) -> () -> exports`.
	return function(resolvedScript: ModuleScript, childRequire: any, globalsTable: any)
		return function()
			local sandboxEnvironment = setmetatable({
				script = resolvedScript,
				game = defaultEnvironment.game,
				workspace = defaultEnvironment.workspace,
				plugin = defaultEnvironment.plugin,
				Game = defaultEnvironment.game,
				Workspace = defaultEnvironment.workspace,
				require = function(otherModule: ModuleScript | string)
					return childRequire(otherModule)
				end,
				_G = globalsTable,
			}, {
				__index = defaultEnvironment,
			})

			local mockedSandboxEnvironment = setmetatable({}, {
				__index = sandboxEnvironment,
			})

			setfenv(moduleChunk :: any, mockedSandboxEnvironment :: any)

			local runOk, runResult = pcall(moduleChunk :: any)
			if not runOk then
				error(runResult, 0)
			end

			return runResult
		end
	end
end

local function wrapModuleFactory(factoryFn: ModuleFunction): ModuleFunction
	return function(...)
		local moduleFunction = factoryFn(...)
		assert(typeof(moduleFunction) == "function", "inner module runner missing")
		return (moduleFunction :: any)()
	end
end

local function makeModuleFunction(compiledOuter): ModuleFunction
	return function(...)
		return compiledOuter(...)()
	end
end

--[=[
	Creates a resolver for a single `createModuleLoader()` instance. Per-loader
	because each loader may detect context independently in tests (via injected deps).
]=]
local function createResolver(deps: ResolverDeps?)
	local injectedRequire: (ModuleScript) -> ...unknown? = if deps then deps.require :: any else require :: any
	local injectedLoadmodule: any = if deps then deps.loadmodule else (debug :: any).loadmodule
	local injectedGetSource: (ModuleScript) -> string? = if deps then deps.getSource :: any else getModuleSource
	local injectedCompile: (string, string) -> (any?, string?) = if deps and deps.compile
		then deps.compile :: any
		else compileWithLoadstring

	--[=[
		Encapsulated context state for this resolver. If the deps are injected,
		this may flip independently from the module-level flag (used in tests).
	]=]
	local localIsNonRobloxScriptContext: boolean? = nil

	return {
		getModuleFunction = function(
			moduleScript: ModuleScript,
			params: { string }?,
			loadmoduleCleanupAccumulator: { () -> () }?
		): ModuleFunction
			local nativeRequire: ModuleFunction = function()
				return injectedRequire(moduleScript)
			end

			local mergedParams = { "script", "require" }
			if params then
				for _, param in params do
					table.insert(mergedParams, param)
				end
			end

			local source = injectedGetSource(moduleScript)

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
			local chunkFn, syntaxErrorMessage = injectedCompile(newSource, moduleScript:GetFullName())

			if chunkFn then
				local ok, result = xpcall(chunkFn, debug.traceback)
				if ok and typeof(result) == "function" then
					-- I don't think there's a way to narrow this further but we know by
					-- this point we we're getting back the newSource result so I think
					-- this is fine
					return makeModuleFunction(result :: any)
				end
				error(result, 0)
			end

			if syntaxErrorMessage then
				error(syntaxErrorMessage, 0)
			end

			-- Fast path: once we know `require(tmpScript)` fails in this context, skip
			-- creating a tmp script and yielding in `setModuleSource` entirely.
			if localIsNonRobloxScriptContext == true then
				local factoryFn =
					tryGetModuleFunctionWithLoadmodule(moduleScript, injectedLoadmodule, loadmoduleCleanupAccumulator)
				if not factoryFn then
					error("debug.loadmodule is required for this context but is unavailable", 0)
				end
				return wrapModuleFactory(factoryFn)
			end

			local tmpScript = Instance.new("ModuleScript")
			tmpScript.Name = moduleScript.Name
			tmpScript.Archivable = false

			if not setModuleSource(tmpScript, newSource) then
				return nativeRequire
			end

			-- After yielding (UpdateSourceAsync on parentless tmp scripts), skip the
			-- `require(tmp)` attempt if we already know it will fail in this context.
			if localIsNonRobloxScriptContext == true then
				tmpScript:Destroy()
				local factoryFn =
					tryGetModuleFunctionWithLoadmodule(moduleScript, injectedLoadmodule, loadmoduleCleanupAccumulator)
				if not factoryFn then
					error("debug.loadmodule is required for this context but is unavailable", 0)
				end
				return wrapModuleFactory(factoryFn)
			end

			-- Prefer ordinary `require(tmpScript)` so Flipbook's own modules load normally.
			-- Built-in plugins hit RobloxScript restrictions only when tmp scripts wrap
			-- LocalScript-context sources (e.g. lua-apps storybooks); then fall back to
			-- `debug.loadmodule`, which bypasses that check but has caused freezes when
			-- used for every module at startup. After the first such failure we remember
			-- the context so we omit the failing require attempt on every subsequent load.
			local createModuleFunction: ModuleFunction?
			local ok: boolean
			local err: string?

			ok, err = xpcall(function()
				createModuleFunction = (injectedRequire :: any)(tmpScript)
			end, debug.traceback)

			if not ok or typeof(createModuleFunction) ~= "function" then
				if err and string.find(err, NON_ROBLOXSCRIPT_ERROR, 1, true) then
					localIsNonRobloxScriptContext = true
					createModuleFunction = tryGetModuleFunctionWithLoadmodule(
						moduleScript,
						injectedLoadmodule,
						loadmoduleCleanupAccumulator
					)
					ok = typeof(createModuleFunction) == "function"
					if ok then
						err = nil
					else
						err = "debug.loadmodule is required for this context but is unavailable"
					end
				elseif err and string.find(err, "RobloxScript", 1, true) then
					-- Fragile: if the error message changed but still contains "RobloxScript",
					-- assume we are in the non-RobloxScript context and log a warning.
					warn(
						"Detected possible non-RobloxScript context via heuristic (error contains 'RobloxScript'); message: "
							.. err
					)
					localIsNonRobloxScriptContext = true
					createModuleFunction = tryGetModuleFunctionWithLoadmodule(
						moduleScript,
						injectedLoadmodule,
						loadmoduleCleanupAccumulator
					)
					ok = typeof(createModuleFunction) == "function"
					if ok then
						err = nil
					else
						err = "debug.loadmodule is required for this context but is unavailable"
					end
				else
					ok = false
				end
			end

			tmpScript:Destroy()

			if not ok then
				error(err, 0)
			end

			return wrapModuleFactory(assert(createModuleFunction, "module factory missing") :: ModuleFunction)
		end,
	}
end

local function weak<K, V>(tab: { [K]: V }): { [K]: V }
	-- We lie about the return type because having a metatable attached to the table means generic for loops don't work
	-- without wrapping the table with `pairs`
	return setmetatable(tab, { __mode = "k" }) :: any
end

--[=[
	Creates a new module loader. Optionally accepts injected dependencies for testing.
]=]
function createModuleLoader(injectDeps: ResolverDeps?): ModuleLoader
	local moduleRegistry = createModuleRegistry()
	local changedConnections = weak({} :: { [ModuleScript]: RBXScriptConnection })
	local globals = setmetatable({} :: typeof(_G), { __index = _G })
	local loadmoduleCleanupFns: { () -> () } = {}

	local resolver = createResolver(injectDeps)

	local function _getModuleRegistry()
		return moduleRegistry
	end

	local loadedModuleChanged = Instance.new("BindableEvent")

	local function cache(moduleScript: ModuleScript, ...: any)
		local loadedModule: LoadedModule = {
			instance = moduleScript,
			exports = table.pack(...),
			isLoaded = true,
		}

		moduleRegistry.add(moduleScript, loadedModule)
	end

	local function require(moduleScript: ModuleScript): ...unknown?
		local weHaveRequireAtHome
		function weHaveRequireAtHome(module: ModuleScript | string, caller: ModuleScript?)
			local resolvedModule: ModuleScript
			if type(module) == "string" then
				local relativeTo: Instance = if caller then caller else moduleScript
				resolvedModule = resolveInstancePath(relativeTo, module) :: ModuleScript
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

			local moduleFunction = resolver.getModuleFunction(resolvedModule, { "_G" }, loadmoduleCleanupFns)

			local function childRequire(childModule: ModuleScript | string)
				return weHaveRequireAtHome(childModule, resolvedModule)
			end

			local exports: types.Packed<unknown>
			local ok, err = xpcall(function()
				-- Notice how the arguments here map to the params in
				-- `resolver.getModuleFunction`, which in this case is `script`,
				-- `require`, and `_G` in the context of the loaded module.
				exports = table.pack(moduleFunction(resolvedModule, childRequire, globals))
			end, debug.traceback)

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

		return weHaveRequireAtHome(moduleScript, nil)
	end

	local function clear()
		-- Flush debug.loadmodule cleanup functions first.
		for _, cleanupFn in loadmoduleCleanupFns do
			pcall(cleanupFn)
		end
		table.clear(loadmoduleCleanupFns)

		moduleRegistry.reset()
		table.clear(globals)

		for _, connection in changedConnections do
			connection:Disconnect()
		end
		table.clear(changedConnections)
	end

	return {
		_getModuleRegistry = _getModuleRegistry,

		cache = cache,
		require = require,
		clear = clear,

		loadedModuleChanged = loadedModuleChanged.Event,
	}
end

return createModuleLoader
