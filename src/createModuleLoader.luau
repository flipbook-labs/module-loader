--[[
	Huge thanks to EgoMoose for the original implementation. Here's the original
	comment that sparked this approach:

	https://github.com/flipbook-labs/module-loader/pull/34#issuecomment-4082559439
]]

local ScriptEditorService: ScriptEditorService?
pcall(function()
	ScriptEditorService = game:GetService("ScriptEditorService")
end)

local createModuleRegistry = require("./createModuleRegistry")
local requireWithLoadstring = require("./requireWithLoadstring")
local resolveInstancePath = require("./resolveInstancePath")
local types = require("./types")

type LoadedModule = types.LoadedModule
type ModuleLoader = types.ModuleLoader
type ModuleRegistry = types.ModuleRegistry
type ModuleFunction = types.ModuleFunction

local function getModuleFunction(moduleScript: ModuleScript): ModuleFunction
	local tmpScript = Instance.new("ModuleScript")
	tmpScript.Name = moduleScript.Name
	tmpScript.Archivable = false

	local mergedParams = { "script", "require" }

	local source = if ScriptEditorService
		then ScriptEditorService:GetEditorSource(moduleScript)
		else moduleScript.Source

	-- The formatting is crazy here, but we retain line numbers
	local newSource = `return (function({table.concat(mergedParams, ", ")}) {source} end)`

	if ScriptEditorService then
		ScriptEditorService:UpdateSourceAsync(tmpScript, function()
			return newSource
		end)
	else
		tmpScript.Source = newSource
	end

	local moduleFunction
	local ok, err = pcall(function()
		moduleFunction = (require :: any)(tmpScript)
	end)

	tmpScript:Destroy()

	if not ok then
		local errorMessage: string?
		local _, syntaxErrorMessage = requireWithLoadstring(moduleScript)

		if syntaxErrorMessage then
			errorMessage = syntaxErrorMessage
		else
			errorMessage = err
		end

		error(errorMessage, 1)
	end

	return moduleFunction
end

--[[
	ModuleScript loader that bypasses Roblox's require cache.

	This class aims to solve a common problem where code needs to be run in
	Studio, but once a change is made to an already required module the whole
	place must be reloaded for the cache to be reset. With this class, the cache
	is ignored when requiring a module so you are able to load a module, make
	changes, and load it again without reloading the whole place.
]]
function createModuleLoader(): ModuleLoader
	local moduleRegistry = createModuleRegistry()
	local changedConnections: { [ModuleScript]: RBXScriptConnection } = {}

	local function _getModuleRegistry()
		return moduleRegistry
	end

	--[[
		Fired when any ModuleScript required through this class has its ancestry
		or `Source` property changed. This applies to the ModuleScript passed to
		`ModuleLoader:require()` and every module that it subsequently requirs.

		This event is useful for reloading a module when it or any of it
		dependencies change.

		```lua
		local loader = createModuleLoader()
		local result = loader.require(module)

		loader.loadedModuleChanged:Connect(function()
			loader.clear()
			result = loader.require(module)
		end)
		```
	]]
	local loadedModuleChanged = Instance.new("BindableEvent")

	--[[
		Set the cached value for a module before it is loaded.

		This is useful is very specific situations. For example, this method is
		used to cache a copy of Roact so that when a module is loaded with this
		class it uses the same table instance.

		```lua
		local moduleInstance = script.Parent.ModuleScript
		local moduleScript = require(moduleInstance)

		local loader = createModuleLoader()
		loader.cache(moduleInstance, moduleScript)
		```
	]]
	local function cache(moduleScript: ModuleScript, result: any)
		local loadedModule: LoadedModule = {
			instance = moduleScript,
			exports = result,
			isLoaded = true,
			dependencies = {},
			consumers = {},
		}

		moduleRegistry.add(moduleScript, loadedModule)
	end

	--[[
		Require a module with a fresh ModuleScript require cache.

		This method is functionally the same as running `require(script.Parent.ModuleScript)`,
		however in this case the module is not cached. As such, if a change occurs
		to the module you can call this method again to get the latest changes.

		```lua
		local loader = createModuleLoader()
		local module = loader.require(script.Parent.ModuleScript)
		```
	]]
	local function require(moduleScript: ModuleScript): unknown
		-- We must register the pre-allocated module object first so that any
		-- circular dependencies that may arise while evaluating the module can
		-- be satisfied.

		local weHaveRequireAtHome
		function weHaveRequireAtHome(module: ModuleScript | string, caller: ModuleScript?)
			local resolvedModule: ModuleScript
			if typeof(module) == "string" then
				local relativeTo: Instance = if caller then caller else moduleScript
				resolvedModule = resolveInstancePath(relativeTo, module) :: ModuleScript
			else
				resolvedModule = module
			end

			if resolvedModule.Name:find(".global$") then
				return (require :: any)(resolvedModule)
			end

			local existingModule = moduleRegistry.getByInstance(resolvedModule)
			if existingModule then
				if existingModule.exports then
					return table.unpack(existingModule.exports, 1, existingModule.exports.n)
				else
					return
				end
			else
				local loadedModule: LoadedModule = {
					instance = resolvedModule,
					exports = nil,
					isLoaded = false,
				}

				moduleRegistry.add(resolvedModule, loadedModule)

				local moduleFunction = getModuleFunction(resolvedModule)

				local function childRequire(childModule: ModuleScript | string)
					return weHaveRequireAtHome(childModule, resolvedModule)
				end

				if not changedConnections[resolvedModule] then
					changedConnections[resolvedModule] = resolvedModule.Changed:Connect(function()
						loadedModuleChanged:Fire(resolvedModule)
					end)
				end

				-- Notice how the arguments here map to `mergedParams` in
				-- `getModuleFunction`, which in this case is `script` and
				-- `require` in the context of the loaded module.
				local exports = table.pack(moduleFunction(resolvedModule, childRequire))

				loadedModule.exports = exports
				loadedModule.isLoaded = true

				return table.unpack(exports, 1, exports.n)
			end
		end

		return weHaveRequireAtHome(moduleScript, nil)
	end

	--[[
		Clears out the internal cache.

		While this module bypasses Roblox's ModuleScript cache, one is still
		maintained internally so that repeated requires to the same module return a
		cached value.

		This method should be called when you need to require a module again. i.e.
		if the module's Source has been changed.

		```lua
		local loader = createModuleLoader()
		loader.require(script.Parent.ModuleScript)

		-- Later...

		-- Clear the cache and require the module again
		loader.clear()
		loader.require(script.Parent.ModuleScript)
		```
	]]
	local function clear()
		moduleRegistry.reset()

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
