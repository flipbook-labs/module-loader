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

local requireAny = require :: any

type LoadedModule = types.LoadedModule
type ModuleLoader = types.ModuleLoader
type ModuleRegistry = types.ModuleRegistry
type ModuleFunction = types.ModuleFunction

-- Unique sentinel table for sandbox detection. When a loader evaluates modules,
-- it passes a proxy _G table with this sentinel; natively-required ModuleLoader
-- sees only the real _G and cannot find this sentinel.
local SANDBOX_MARKER = { __internal = true }

local function makeModuleFunction(compiledOuter): ModuleFunction
	return function(...)
		return compiledOuter(...)()
	end
end

local function getModuleFunction(moduleScript: ModuleScript, params: { string }?): ModuleFunction
	local nativeRequire: ModuleFunction = function()
		return requireAny(moduleScript)
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
	local chunkFn, syntaxErrorMessage = compileWithLoadstring(newSource, moduleScript:GetFullName())

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

	local tmpScript = Instance.new("ModuleScript")
	tmpScript.Name = moduleScript.Name
	tmpScript.Archivable = false

	if not setModuleSource(tmpScript, newSource) then
		return nativeRequire
	end

	local createModuleFunction
	local ok, err = xpcall(function()
		createModuleFunction = requireAny(tmpScript)
	end, debug.traceback)

	tmpScript:Destroy()

	if not ok then
		error(err, 0)
	end

	return makeModuleFunction(createModuleFunction)
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

	-- Plant the sandbox marker on the proxy globals so code evaluated through
	-- this loader can detect they are running in a sandboxed context.
	rawset(globals, "__MODULE_LOADER_SANDBOX__", SANDBOX_MARKER)

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

			local moduleFunction = getModuleFunction(resolvedModule, { "_G" })

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
		moduleRegistry.reset()

		-- Clearing user-defined globals also wipes the sandbox marker, so it
		-- has to be replanted for modules evaluated after the clear.
		table.clear(globals)
		rawset(globals, "__MODULE_LOADER_SANDBOX__", SANDBOX_MARKER)

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
