local createModuleLoader = require("@self/createModuleLoader")
local isSandboxed = require("@self/isSandboxed")
local types = require("@self/types")

export type ModuleLoader = types.PublicModuleLoader
export type ModuleLoadError = types.ModuleLoadError

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
local function createPublicModuleLoader(): ModuleLoader
	-- Specs pass their own engine calls to the internal factory. Callers
	-- always get the real ones.
	return createModuleLoader()
end

return {
	createModuleLoader = createPublicModuleLoader,
	isSandboxed = isSandboxed,
}
