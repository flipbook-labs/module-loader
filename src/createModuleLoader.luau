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

local function getModuleFunction(moduleScript: ModuleScript, params: { string }?): ModuleFunction
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

		-- The extra anonymous function is to avoid allocations in the module
		-- scope. Certain modules like `ReactFiberWorkLoop.new` are specifically
		-- written to respect the 200 allocation limit in Luau, and us coming in
		-- with new allocations blows it up.
		"return function()",
		source,
		"end",

		"end",
	}, ";")

	setModuleSource(tmpScript, newSource)

	local moduleFactory
	local ok, err = xpcall(function()
		moduleFactory = (require :: any)(tmpScript)
	end, debug.traceback)

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

	return function(...)
		return moduleFactory(...)()
	end
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
