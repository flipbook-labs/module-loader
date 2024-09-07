local GoodSignal = require("@pkg/GoodSignal")
local Janitor = require("@pkg/Janitor")

local bind = require("./bind")
local createTablePassthrough = require("./createTablePassthrough")
local getCallerPath = require("./getCallerPath")
local getEnv = require("./getEnv")
local getRobloxTsRuntime = require("./getRobloxTsRuntime")

type CachedModuleResult = any

type ModuleConsumers = {
	[string]: boolean,
}

-- Each module gets its own global table that it can modify via _G. This makes
-- it easy to clear out a module and the globals it defines without impacting
-- other modules. A module's function environment has all globals merged
-- together on _G
type ModuleGlobals = {
	[any]: any,
}

type CachedModule = {
	module: ModuleScript,
	isLoaded: boolean,
	result: CachedModuleResult,
	consumers: ModuleConsumers,
	globals: ModuleGlobals,
}

type ModuleLoaderProps = {
	_cache: { [string]: CachedModule },
	_loadstring: typeof(loadstring),
	_debugInfo: typeof(debug.info),
	_janitors: { [string]: typeof(Janitor.new()) },
	_globals: { [any]: any },

	loadedModuleChanged: RBXScriptSignal,
}

type ModuleLoaderImpl = {
	__index: ModuleLoaderImpl,

	new: () -> ModuleLoader,

	require: (self: ModuleLoader, module: ModuleScript) -> any,
	cache: (self: ModuleLoader, module: ModuleScript, result: any) -> (),
	clearModule: (self: ModuleLoader, module: ModuleScript) -> (),
	clear: (self: ModuleLoader) -> (),

	_loadCachedModule: (self: ModuleLoader, module: ModuleScript) -> CachedModuleResult,
	_getSource: (self: ModuleLoader, module: ModuleScript) -> string,
	_trackChanges: (self: ModuleLoader, module: ModuleScript) -> (),
	_getConsumers: (self: ModuleLoader, module: ModuleScript) -> { ModuleScript },
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

	self._cache = {}
	self._loadstring = loadstring
	self._debugInfo = debug.info
	self._janitors = {}
	self._globals = {}

	--[=[
		Fired when any ModuleScript required through this class has its ancestry
		or `Source` property changed. This applies to the ModuleScript passed to
		`ModuleLoader:require( )` and every module that it subsequently requirs.

		This event is useful for reloading a module when it or any of it
		dependencies change.

		```lua
		local loader = ModuleLoader.Instance.new("Accessory")new()
		local result = loader:require(module)

		loader.loadedModuleChanged:Connect(function()
			loader:clear()
			result = loader:require(module)
		end)
		```

		@prop loadedModuleChanged RBXScriptSignal
		@within ModuleLoader
	]=]
	self.loadedModuleChanged = GoodSignal.new()

	return setmetatable(self, ModuleLoader)
end

function ModuleLoader:_loadCachedModule(module: ModuleScript)
	local cachedModule: CachedModule = self._cache[module:GetFullName()]

	assert(
		cachedModule.isLoaded,
		"Requested module experienced an error while loading MODULE: "
			.. module:GetFullName()
			.. " - RESULT: "
			.. tostring(cachedModule.result)
	)

	return cachedModule.result
end

--[=[
	Gets the Source of a ModuleScript.

	This method exists primarily so we can better write unit tests. Attempting
	to index the Source property from a regular script context throws an error,
	so this method allows us to safely fallback in tests.

	@private
]=]
function ModuleLoader:_getSource(module: ModuleScript)
	local success, result = pcall(function()
		return module.Source
	end)

	return if success then result else ""
end

--[=[
	Tracks the changes to a required module's ancestry and `Source`.

	When ancestry or `Source` changes, the `loadedModuleChanged` event is fired.
	When this happens, the user should clear the cache and require the root
	module again to reload.

	@private
]=]
function ModuleLoader:_trackChanges(module: ModuleScript)
	local existingJanitor = self._janitors[module:GetFullName()]
	local janitor = if existingJanitor then existingJanitor else Janitor.new()

	janitor:Cleanup()

	janitor:Add(module.AncestryChanged:Connect(function()
		self:clearModule(module)
	end))

	janitor:Add(module.Changed:Connect(function(prop: string)
		if prop == "Source" then
			self:clearModule(module)
		end
	end))

	self._janitors[module:GetFullName()] = janitor
end

--[=[
	Set the cached value for a module before it is loaded.

	This is useful is very specific situations. For example, this method is
	used to cache a copy of Roact so that when a module is loaded with this
	class it uses the same table instance.

	```lua
	local moduleInstance = "./Parent".ModuleScript
	local module = require(moduleInstance)

	local loader = ModuleLoader.Instance.new("Accessory")new()
	loader:cache(moduleInstance, module)
	```
]=]
function ModuleLoader:cache(module: ModuleScript, result: any)
	local cachedModule: CachedModule = {
		module = module,
		result = result,
		isLoaded = true,
		consumers = {},
		globals = createTablePassthrough(self._globals),
	}

	self._cache[module:GetFullName()] = cachedModule
end

--[=[
	Require a module with a fresh ModuleScript require cache.

	This method is functionally the same as running `require("./Parent".ModuleScript)`,
	however in this case the module is not cached. As such, if a change occurs
	to the module you can call this method again to get the latest changes.

	```lua
	local loader = ModuleLoader.Instance.new("Accessory")new()
	local module = loader:require("./Parent".ModuleScript)
	```
]=]
function ModuleLoader:require(module: ModuleScript)
	local cachedModule = self._cache[module:GetFullName()]
	local callerPath = getCallerPath()

	if cachedModule then
		cachedModule.consumers[callerPath] = true
		return self:_loadCachedModule(module)
	end

	local source = self:_getSource(module)
	local moduleFn, parseError = self._loadstring(source, module:GetFullName())

	if not moduleFn then
		error(("Could not parse %s: %s"):format(module:GetFullName(), parseError))
	end

	local globals = createTablePassthrough(self._globals)

	local newCachedModule: CachedModule = {
		module = module,
		result = nil,
		isLoaded = false,
		consumers = {
			[callerPath] = true,
		},
		globals = globals,
	}
	self._cache[module:GetFullName()] = newCachedModule

	local env = getEnv(module, globals)
	env.require = bind(self, self.require)
	setfenv(moduleFn, env)

	local success, result = xpcall(moduleFn, debug.traceback)

	if success then
		newCachedModule.isLoaded = true
		newCachedModule.result = result
	else
		error(("Error requiring %s: %s"):format(module.Name, result))
	end

	self:_trackChanges(module)

	return self:_loadCachedModule(module)
end

function ModuleLoader:_getConsumers(module: ModuleScript)
	local function getConsumersRecursively(cachedModule: CachedModule, found: { [ModuleScript]: true })
		for consumer in cachedModule.consumers do
			local cachedConsumer = self._cache[consumer]

			if cachedConsumer then
				if not found[cachedConsumer.module] then
					found[cachedConsumer.module] = true
					getConsumersRecursively(cachedConsumer, found)
				end
			end
		end
	end

	local cachedModule: CachedModule = self._cache[module:GetFullName()]
	local found = {}

	getConsumersRecursively(cachedModule, found)

	local consumers = {}
	for consumer in found do
		table.insert(consumers, consumer)
	end

	return consumers
end

function ModuleLoader:clearModule(moduleToClear: ModuleScript)
	if not self._cache[moduleToClear:GetFullName()] then
		return
	end

	local consumers = self:_getConsumers(moduleToClear)
	local modulesToClear = { moduleToClear, table.unpack(consumers) }

	local index = table.find(modulesToClear, getRobloxTsRuntime())
	if index then
		table.remove(modulesToClear, index)
	end

	for _, module in modulesToClear do
		local fullName = module:GetFullName()

		local cachedModule = self._cache[fullName]

		if cachedModule then
			self._cache[fullName] = nil

			for key in cachedModule.globals do
				self._globals[key] = nil
			end

			local janitor = self._janitors[fullName]
			janitor:Cleanup()
		end
	end

	for _, module in modulesToClear do
		self.loadedModuleChanged:Fire(module)
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
	local loader = ModuleLoader.Instance.new("Accessory")new()
	loader:require("./Parent".ModuleScript)

	-- Later...

	-- Clear the cache and require the module again
	loader:clear()
	loader:require("./Parent".ModuleScript)
	```
]=]
function ModuleLoader:clear()
	self._cache = {}
	self._globals = {}

	for _, janitor in self._janitors do
		janitor:Cleanup()
	end
	self._janitors = {}
end

return ModuleLoader
