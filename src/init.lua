local Janitor = require(script.Parent.Janitor)
local GoodSignal = require(script.Parent.GoodSignal)
local bind = require(script.bind)
local getEnv = require(script.getEnv)

--[=[
	Module loader class that bypasses Roblox's require cache.

	This class aims to solve a common problem where code needs to be run in
	Studio, but once a change is made to an already required module the whole
	place must be reloaded for the cache to be reset. With this class, the cache
	is ignored when requiring a module so you are able to load a module, make
	changes, and load it again without reloading.

	Parts of this class were taken verbatim from
	[OrbitalOwen/roblox-testservice-watcher](https://github.com/OrbitalOwen/roblox-testservice-watcher),
	and other parts were rewritten to allow the module loading code to be
	abstracted into a new package.

	@class ModuleLoader
]=]
local ModuleLoader = {}
ModuleLoader.__index = ModuleLoader

export type Class = typeof(ModuleLoader.new())

--[=[
    Constructs a new ModuleLoader instance.
]=]
function ModuleLoader.new()
	local self = {}

	self._cache = {}
	self._loadstring = loadstring
	self._janitor = Janitor.new()

	--[=[
		Fired when any ModuleScript required through this class has its ancestry
		or `Source` property changed. This applies to the ModuleScript passed to
		`ModuleLoader:require()` and every module that it subsequently requirs.

		This event is useful for reloading a module when it or any of it
		dependencies change.

		```lua
		local loader = ModuleLoader.new()
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

function ModuleLoader:_validateValues(returnValues: { any })
	for index in ipairs(returnValues) do
		if index ~= 1 and index ~= 2 then
			return false
		end
	end
	return returnValues[2] and true or false
end

function ModuleLoader:_loadCachedModule(module: ModuleScript)
	local returnValues = self._cache[module]
	local success = returnValues[1]
	local result = returnValues[2]

	assert(
		success,
		"Requested module experienced an error while loading MODULE: "
			.. module:GetFullName()
			.. " - RESULT: "
			.. tostring(result)
	)
	assert(self:_validateValues(returnValues), "Module code did not return exactly one value")

	return result
end

--[=[
	Gets the Source of a ModuleScript.

	This method exists primarily so we can better write unit tests. Attempting
	to index the Source property from a regular script context throws an error,
	so this method allows us to safely fallback in tests.
	
	@private
]=]
function ModuleLoader:_getSource(module: ModuleScript): any?
	local success, result = pcall(function()
		return module.Source
	end)

	return if success then result else nil
end

--[=[
	Tracks the changes to a required module's ancestry and `Source`.

	When ancestry or `Source` changes, the `loadedModuleChanged` event is fired.
	When this happens, the user should clear the cache and require the root
	module again to reload.

	@private
]=]
function ModuleLoader:_trackChanges(module: ModuleScript)
	self._janitor:Add(module.AncestryChanged:Connect(function()
		self.loadedModuleChanged:Fire(module)
	end))

	self._janitor:Add(module.Changed:Connect(function(prop: string)
		if prop == "Source" then
			self.loadedModuleChanged:Fire(module)
		end
	end))
end

--[=[
	Set the cached value for a module before it is loaded.

	This is useful is very specific situations. For example, this method is
	used to cache a copy of Roact so that when a module is loaded with this
	class it uses the same table instance.

	```lua
	local moduleInstance = script.Parent.ModuleScript
	local module = require(moduleInstance)

	local loader = ModuleLoader.new()
	loader:cache(moduleInstance, module)
	```
]=]
function ModuleLoader:cache(module: ModuleScript, source: any)
	self._cache[module] = { true, source }
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
function ModuleLoader:require(module: ModuleScript)
	if self._cache[module] then
		return self:_loadCachedModule(module)
	end

	local source = self:_getSource(module)
	local moduleFn = self._loadstring(source, module:GetFullName())

	local env = getEnv(module)
	env.require = bind(self, self.require)
	setfenv(moduleFn, env)

	local success, result = pcall(moduleFn)
	self._cache[module] = { success, result }

	self:_trackChanges(module)

	return self:_loadCachedModule(module)
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
	self._cache = {}
	self._janitor:Cleanup()
end

return ModuleLoader
