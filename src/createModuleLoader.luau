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

-- Module-level flag: nil = unknown, true = in a non-RobloxScript context (require(tmpScript) will fail)
local isNonRobloxScriptContext: boolean? = nil

local NON_ROBLOXSCRIPT_ERROR = "Cannot require a non-RobloxScript module from a RobloxScript"

-- `debug.loadmodule` must be called on the **original** ModuleScript — not the
-- temporary wrapper ModuleScript used for `require`. Loading the wrapper yields a
-- compiled chunk shaped like a normal ModuleScript (`return …`), not the
-- double-factory shape produced by `require(tmpScript)`, which led to errors such
-- as indexing a returned table like a callable factory.
--
-- Roblox signature: (moduleScript) -> (moduleChunk?, errorMessage?, cleanupFn?)
-- `moduleChunk` runs the module body once (after `setfenv`) and returns its exports.
local function tryGetModuleFunctionWithLoadmodule(
	originalModuleScript: ModuleScript,
	cleanupAccumulator: { () -> () }?
): ModuleFunction?
	local loadmoduleFn = (debug :: any).loadmodule
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

local function getModuleFunction(
	moduleScript: ModuleScript,
	params: { string }?,
	loadmoduleCleanupAccumulator: { () -> () }?
): ModuleFunction
	-- Fast path: once we know `require(tmpScript)` fails in this context, skip
	-- creating a tmp script and yielding in `setModuleSource` entirely.
	if isNonRobloxScriptContext == true then
		local factoryFn = tryGetModuleFunctionWithLoadmodule(moduleScript, loadmoduleCleanupAccumulator)
		if not factoryFn then
			error("debug.loadmodule failed or is unavailable", 0)
		end
		return wrapModuleFactory(factoryFn)
	end

	local tmpScript = Instance.new("ModuleScript")
	tmpScript.Name = moduleScript.Name
	tmpScript.Archivable = false

	local mergedParams = { "script", "require" }
	if params then
		for _, param in params do
			table.insert(mergedParams, param)
		end
	end

	local source = getModuleSource(moduleScript)

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

	setModuleSource(tmpScript, newSource)

	-- After yielding (UpdateSourceAsync on parentless tmp scripts), skip the
	-- `require(tmp)` attempt if we already know it will fail in this context.
	if isNonRobloxScriptContext == true then
		tmpScript:Destroy()
		local factoryFn = tryGetModuleFunctionWithLoadmodule(moduleScript, loadmoduleCleanupAccumulator)
		if not factoryFn then
			error("debug.loadmodule failed or is unavailable", 0)
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
		createModuleFunction = (require :: any)(tmpScript)
	end, debug.traceback)

	if not ok or typeof(createModuleFunction) ~= "function" then
		if err and string.find(err, NON_ROBLOXSCRIPT_ERROR, 1, true) then
			isNonRobloxScriptContext = true
			createModuleFunction = tryGetModuleFunctionWithLoadmodule(moduleScript, loadmoduleCleanupAccumulator)
			ok = typeof(createModuleFunction) == "function"
			if ok then
				err = nil
			else
				err = "debug.loadmodule failed or is unavailable"
			end
		else
			ok = false
		end
	end

	tmpScript:Destroy()

	if not ok then
		local errorMessage: string?
		local _, syntaxErrorMessage = compileWithLoadstring(newSource, moduleScript:GetFullName())

		if syntaxErrorMessage then
			errorMessage = syntaxErrorMessage
		else
			errorMessage = err
		end

		error(errorMessage, 0)
	end

	return wrapModuleFactory(assert(createModuleFunction, "module factory missing") :: ModuleFunction)
end

local function weak<K, V>(tab: { [K]: V }): { [K]: V }
	-- We lie about the return type because having a metatable attached to the table means generic for loops don't work
	-- without wrapping the table with `pairs`
	return setmetatable(tab, { __mode = "k" }) :: any
end

function createModuleLoader(): ModuleLoader
	local moduleRegistry = createModuleRegistry()
	local changedConnections = weak({} :: { [ModuleScript]: RBXScriptConnection })
	local globals = setmetatable({} :: typeof(_G), { __index = _G })
	local loadmoduleCleanupFns: { () -> () } = {}

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

			local moduleFunction = getModuleFunction(resolvedModule, { "_G" }, loadmoduleCleanupFns)

			local function childRequire(childModule: ModuleScript | string)
				return weHaveRequireAtHome(childModule, resolvedModule)
			end

			local exports: types.Packed<unknown>
			local ok, err = xpcall(function()
				-- Notice how the arguments here map to the params in
				-- `getModuleFunction`, which in this case is `script`,
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
		for _, cleanupFn in loadmoduleCleanupFns do
			cleanupFn()
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
		loadModule = require,
		require = require,
		clear = clear,

		loadedModuleChanged = loadedModuleChanged.Event,
	}
end

return createModuleLoader
