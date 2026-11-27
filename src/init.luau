local createModuleLoader = require("@self/createModuleLoader")
local isSandboxed = require("@self/isSandboxed")

--[=[
	A loader made by `createModuleLoader`.

	@interface ModuleLoader
	@within ModuleLoader
	.require (moduleScript: ModuleScript) -> ...unknown -- Requires a module, and every module it requires, without Roblox's require cache. Requiring it again returns the same result until `clear` is called.
	.cache (moduleScript: ModuleScript, ...unknown) -> () -- Sets the result `require` returns for a module before it loads, so loaded modules share a copy you already have, such as a UI library.
	.clear () -> () -- Empties the loader's cache, so the next `require` runs each module again.
	.loadedModuleChanged RBXScriptSignal -- Fires when a module required through this loader has its ancestry or `Source` changed.
]=]
-- `createModuleLoader` returns more than these fields, such as the module
-- registry its specs read. This type keeps those out of the public API.
export type ModuleLoader = {
	require: (moduleScript: ModuleScript) -> ...unknown?,
	cache: (moduleScript: ModuleScript, ...unknown?) -> (),
	clear: () -> (),

	loadedModuleChanged: RBXScriptSignal,
}

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
local ModuleLoader = {}

--[=[
	Creates a loader with its own cache.

	A loader keeps what each module it requires returns, so requiring a module
	twice through one loader runs it once. Two loaders never share results.

	```lua
	local loader = ModuleLoader.createModuleLoader()
	local result = loader.require(script.Parent.ModuleScript)
	```

	@function createModuleLoader
	@within ModuleLoader
	@return ModuleLoader
]=]
function ModuleLoader.createModuleLoader(): ModuleLoader
	return createModuleLoader()
end

ModuleLoader.isSandboxed = isSandboxed

return ModuleLoader
