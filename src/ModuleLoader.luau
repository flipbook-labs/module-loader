local Janitor = require("@pkg/Janitor")
local LuauPolyfill = require("@pkg/LuauPolyfill")

local cleanLoadstringStack = require("./cleanLoadstringStack")
local createModuleRegistry = require("./createModuleRegistry")
local getCallerPath = require("./getCallerPath")
local getRobloxTsRuntime = require("./getRobloxTsRuntime")
local types = require("./types")

type ModuleRegistry = types.ModuleRegistry
type LoadedModule = types.LoadedModule

local Error = LuauPolyfill.Error

local loadmodule: (ModuleScript) -> (() -> unknown?, string?, () -> ()) = debug["loadmodule"]
local loadModuleEnabled = pcall(function()
	return loadmodule(Instance.new("ModuleScript"))
end)

local function getModuleSource(moduleScript: ModuleScript): string
	local success, result = pcall(function()
		return moduleScript.Source
	end)

	return if success then result else ""
end

type ModuleLoaderProps = {
	_moduleRegistry: ModuleRegistry,
	_loadedModuleFns: { [ModuleScript]: { any } },
	_cleanupFns: { () -> () },
	_forceLoadstring: boolean,
	_janitors: { [ModuleScript]: any },

	_loadedModuleChangedBindable: BindableEvent,
	loadedModuleChanged: RBXScriptSignal,
}

type ModuleLoaderImpl = {
	__index: ModuleLoaderImpl,

	new: () -> ModuleLoader,

	require: (self: ModuleLoader, moduleScript: ModuleScript) -> any,
	cache: (self: ModuleLoader, moduleScript: ModuleScript, result: any) -> (),
	clearModule: (self: ModuleLoader, moduleScript: ModuleScript) -> (),
	clear: (self: ModuleLoader) -> (),

	_execModule: (self: ModuleLoader, loadedModule: LoadedModule) -> (),
	_trackChanges: (self: ModuleLoader, moduleScript: ModuleScript) -> (),
	_getConsumers: (self: ModuleLoader, moduleScript: ModuleScript) -> { ModuleScript },
}

export type ModuleLoader = typeof(setmetatable({} :: ModuleLoaderProps, {} :: ModuleLoaderImpl))

--[=[
	ModuleScript loader that bypasses Roblox's require cache.

	This class aims to solve a common problem where code needs to be run in
	Studio, but once a change is made to an already required module the whole
	place must be reloaded for the cache to be reset. With this class, the cache
	is ignored when requiring a module so you are able to load a module, make
	changes, and load it again without reloading the whole place.

	@class ModuleLoader
]=]
local ModuleLoader = {} :: ModuleLoaderImpl
ModuleLoader.__index = ModuleLoader

--[=[
    Constructs a new ModuleLoader instance.
]=]
function ModuleLoader.new()
	local self = {}

	self._moduleRegistry = createModuleRegistry()
	self._loadedModuleFns = {}
	self._cleanupFns = {}
	self._forceLoadstring = false
	self._janitors = {}
	self._loadedModuleChangedBindable = Instance.new("BindableEvent")

	--[=[
		Fired when any ModuleScript required through this class has its ancestry
		or `Source` property changed. This applies to the ModuleScript passed to
		`ModuleLoader:require()` and every module that it subsequently requirs.

		This event is useful for reloading a module when it or any of it
		dependencies change.

		```lua
		local loader = ModuleLoader.new()
		local result = loader:require(moduleScript)

		loader.loadedModuleChanged:Connect(function()
			loader:clear()
			result = loader:require(moduleScript)
		end)
		```

		@prop loadedModuleChanged RBXScriptSignal
		@within ModuleLoader
	]=]
	self.loadedModuleChanged = self._loadedModuleChangedBindable.Event

	return setmetatable(self, ModuleLoader)
end

--[=[
	Tracks the changes to a required module's ancestry and `Source`.

	When ancestry or `Source` changes, the `loadedModuleChanged` event is fired.
	When this happens, the user should clear the cache and require the root
	module again to reload.

	@private
]=]
function ModuleLoader:_trackChanges(moduleScript: ModuleScript)
	local existingJanitor = self._janitors[moduleScript]
	local janitor = if existingJanitor then existingJanitor else Janitor.new()

	janitor:Cleanup()

	janitor:Add(moduleScript.AncestryChanged:Connect(function()
		self:clearModule(moduleScript)
	end))

	janitor:Add(moduleScript.Changed:Connect(function(prop: string)
		if prop == "Source" then
			self:clearModule(moduleScript)
		end
	end))

	self._janitors[moduleScript] = janitor
end

--[=[
	Set the cached value for a module before it is loaded.

	This is useful is very specific situations. For example, this method is
	used to cache a copy of Roact so that when a module is loaded with this
	class it uses the same table instance.

	```lua
	local moduleInstance = script.Parent.ModuleScript
	local moduleScript = require(moduleInstance)

	local loader = ModuleLoader.new()
	loader:cache(moduleInstance, moduleScript)
	```
]=]
function ModuleLoader:cache(moduleScript: ModuleScript, result: any)
	local loadedModule: LoadedModule = {
		instance = moduleScript,
		exports = result,
		isLoaded = true,
		dependencies = {},
		consumers = {},
	}

	self._moduleRegistry.add(moduleScript, loadedModule)
end

function ModuleLoader:_execModule(loadedModule: LoadedModule)
	local moduleFunction, defaultEnvironment, errorMessage, cleanupFn
	local moduleScript = loadedModule.instance

	local shouldUseLoadmodule = not self._forceLoadstring and loadModuleEnabled

	local loadedModuleFns = self._loadedModuleFns[moduleScript]
	if loadedModuleFns then
		moduleFunction = loadedModuleFns[1]
		defaultEnvironment = loadedModuleFns[2]
	else
		if shouldUseLoadmodule then
			moduleFunction, errorMessage, cleanupFn = loadmodule(moduleScript)
		else
			moduleFunction, errorMessage = loadstring(getModuleSource(moduleScript), moduleScript:GetFullName())

			if errorMessage then
				errorMessage = cleanLoadstringStack(errorMessage)
			end
		end

		if not moduleFunction then
			error(Error.new(errorMessage))
		end

		-- Cache initial environment table to inherit from later
		defaultEnvironment = getfenv(moduleFunction)

		if self._loadedModuleFns then
			self._loadedModuleFns[moduleScript] = { moduleFunction, defaultEnvironment, cleanupFn }
		else
			if cleanupFn ~= nil then
				table.insert(self._cleanupFns, cleanupFn)
			end
		end
	end

	-- The default behavior for function environments is to inherit the table
	-- instance from the parent environment. This means that each invocation of
	-- `moduleFunction()` will return a new module instance but with the same
	-- environment table as `moduleFunction` itself at the time of invocation.
	-- In order to properly sanbox module instances, we need to ensure that each
	-- instance has its own distinct environment table containing the specific
	-- overrides for it, but still inherits from the default parent environment
	-- for non-overriden environment goodies.

	-- This is the 'least mocked' environment that scripts will be able to see.
	-- The final function environment inherits from this sandbox. This is
	-- separate so that, in the future, `globalEnv` could expose these
	-- 'unmocked' functions instead of the ones in the global environment.
	local sandboxEnvironment = setmetatable({
		script = if shouldUseLoadmodule then defaultEnvironment.script else moduleScript,
		game = defaultEnvironment.game,
		workspace = defaultEnvironment.workspace,
		plugin = defaultEnvironment.plugin,

		-- legacy aliases for data model
		Game = defaultEnvironment.game,
		Workspace = defaultEnvironment.workspace,

		require = function(otherModule: ModuleScript | string)
			if typeof(otherModule) == "string" then
				-- Disabling this at the surface level of the API until we have
				-- deeper support in Jest.
				error("Require-by-string is not enabled for use inside Jest at this time.")
			end

			loadedModule.dependencies[otherModule] = true

			return self:require(otherModule)
		end,
	}, {
		__index = defaultEnvironment,
	})

	-- This is the environment actually passed to scripts, including all global
	-- mocks and other customisations the user might choose to apply.
	local mockedSandboxEnvironment = setmetatable({}, {
		__index = sandboxEnvironment,
	})

	setfenv(moduleFunction, mockedSandboxEnvironment :: any)
	local moduleResult = table.pack(moduleFunction())

	if moduleResult.n ~= 1 then
		error(
			string.format(
				"[Module Error]: %s did not return a valid result\n" .. "\tModuleScripts must return exactly one value",
				tostring(moduleScript)
			)
		)
	end

	self:_trackChanges(moduleScript)

	loadedModule.exports = moduleResult[1]
end

--[=[
	Require a module with a fresh ModuleScript require cache.

	This method is functionally the same as running `require(script.Parent.ModuleScript)`,
	however in this case the module is not cached. As such, if a change occurs
	to the module you can call this method again to get the latest changes.

	```lua
	local loader = ModuleLoader.new()
	local module = loader:require(script.Parent.ModuleScript)
	```
]=]
function ModuleLoader:require(moduleScript: ModuleScript): unknown
	if moduleScript.Name:find(".global$") then
		return (require :: any)(moduleScript)
	end

	local caller: ModuleScript?
	local callerPath = getCallerPath()
	if callerPath then
		local loadedCallerModule = self._moduleRegistry.getByFullName(callerPath)
		if loadedCallerModule and loadedCallerModule.instance then
			caller = loadedCallerModule.instance
		end
	end

	local existingModule = self._moduleRegistry.getByInstance(moduleScript)
	if existingModule then
		if caller then
			existingModule.consumers[caller] = true
		end

		return existingModule.exports
	end

	-- We must register the pre-allocated module object first so that any
	-- circular dependencies that may arise while evaluating the module can
	-- be satisfied.
	local loadedModule: LoadedModule = {
		instance = moduleScript,
		exports = nil,
		isLoaded = false,
		dependencies = {},
		consumers = if caller
			then {
				[caller] = true,
			}
			else {},
	}

	self._moduleRegistry.add(moduleScript, loadedModule)

	local success, result = pcall(function()
		self:_execModule(loadedModule)
		loadedModule.isLoaded = true
	end)
	if not success then
		self._moduleRegistry.remove(moduleScript)
		error(result)
	end

	return loadedModule.exports
end

function ModuleLoader:_getConsumers(moduleScript: ModuleScript): { ModuleScript }
	local function getConsumersRecursively(loadedModule: LoadedModule, found: { [ModuleScript]: true })
		for consumer in loadedModule.consumers do
			local loadedChildModule = self._moduleRegistry.getByInstance(consumer)

			if loadedChildModule then
				if not found[loadedChildModule.instance] then
					found[loadedChildModule.instance] = true
					getConsumersRecursively(loadedChildModule, found)
				end
			end
		end
	end

	local loadedModule: LoadedModule? = self._moduleRegistry.getByInstance(moduleScript)

	if loadedModule then
		local found = {}

		getConsumersRecursively(loadedModule, found)

		local consumers = {}
		for consumer in found do
			table.insert(consumers, consumer)
		end

		return consumers
	else
		return {}
	end
end

function ModuleLoader:clearModule(moduleToClear: ModuleScript)
	if not self._moduleRegistry.getByInstance(moduleToClear) then
		return
	end

	local consumers = self:_getConsumers(moduleToClear)
	local modulesToClear = { moduleToClear, table.unpack(consumers) }

	local index = table.find(modulesToClear, getRobloxTsRuntime())
	if index then
		table.remove(modulesToClear, index)
	end

	for _, moduleScript in modulesToClear do
		local loadedModule = self._moduleRegistry.getByInstance(moduleScript)

		if loadedModule then
			self._moduleRegistry.remove(moduleScript)

			local janitor = self._janitors[moduleScript]
			janitor:Cleanup()
		end
	end

	for _, moduleScript in modulesToClear do
		self._loadedModuleChangedBindable:Fire(moduleScript)
	end
end

--[=[
	Clears out the internal cache.

	While this module bypasses Roblox's ModuleScript cache, one is still
	maintained internally so that repeated requires to the same module return a
	cached value.

	This method should be called when you need to require a module again. i.e.
	if the module's Source has been changed.

	```lua
	local loader = ModuleLoader.new()
	loader:require(script.Parent.ModuleScript)

	-- Later...

	-- Clear the cache and require the module again
	loader:clear()
	loader:require(script.Parent.ModuleScript)
	```
]=]
function ModuleLoader:clear()
	for _, janitor in self._janitors do
		janitor:Cleanup()
	end

	for _, cleanupFn in self._cleanupFns do
		cleanupFn()
	end

	self._moduleRegistry.reset()
	self._loadedModuleFns = {}
	self._cleanupFns = {}
	self._janitors = {}
end

return ModuleLoader
