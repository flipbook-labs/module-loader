local createModuleLoader = require("./createModuleLoader")
local types = require("./types")

type ModuleLoader = types.ModuleLoader

type ModuleLoaderProps = {
	_loader: ModuleLoader,
	loadedModuleChanged: RBXScriptSignal,
}

type ModuleLoaderImpl = {
	__index: ModuleLoaderImpl,

	new: () -> ModuleLoaderClass,
	isLocked: (instance: Instance) -> boolean,
	isSandboxed: () -> boolean,

	require: (self: ModuleLoaderClass, moduleScript: ModuleScript) -> any,
	cache: (self: ModuleLoaderClass, moduleScript: ModuleScript, result: any) -> (),
	clearModule: (self: ModuleLoaderClass, moduleScript: ModuleScript) -> (),
	clear: (self: ModuleLoaderClass) -> (),
}

export type ModuleLoaderClass = typeof(setmetatable({} :: ModuleLoaderProps, {} :: ModuleLoaderImpl))

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

	self._loader = createModuleLoader()

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
	self.loadedModuleChanged = self._loader.loadedModuleChanged

	return setmetatable(self, ModuleLoader)
end

--[=[
	Detects whether the code calling this function is running in a ModuleLoader sandbox.

	When a module is evaluated through a ModuleLoader, it receives a proxy global
	environment (`_G`). Code running in that environment can call this method to
	detect if it is sandboxed. This is useful for modules that need to behave
	differently when loaded through a loader versus when loaded with native `require()`.

	Natively-required ModuleLoader always returns false, since it sees the real
	global environment without the sandbox marker. When called from code evaluated
	through a ModuleLoader, this function returns true.

	```lua
	local ModuleLoader = require(ReplicatedStorage.Packages.ModuleLoader)

	if ModuleLoader.isSandboxed() then
		print("Running in a sandbox!")
	else
		print("Running natively")
	end
	```

	@function isSandboxed
	@within ModuleLoader
	@return boolean
]=]
function ModuleLoader.isSandboxed(): boolean
	return _G.__MODULE_LOADER_SANDBOX__ ~= nil
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
	self._loader.cache(moduleScript, result)
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
function ModuleLoader:require(moduleScript: ModuleScript)
	return self._loader.require(moduleScript)
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
	self._loader.clear()
end

return ModuleLoader
