--[[
	Huge thanks to EgoMoose for the original implementation. Here's the original
	comment that sparked this approach:

	https://github.com/flipbook-labs/module-loader/pull/34#issuecomment-4082559439
]]

local ScriptEditorService: ScriptEditorService?
pcall(function()
	ScriptEditorService = game:GetService("ScriptEditorService")
end)

local requireWithLoadstring = require("@root/requireWithLoadstring")
local resolveInstancePath = require("@root/resolveInstancePath")
local types = require("@root/types")

type ProxyModuleLoader = types.ProxyModuleLoader

type ModuleFunction = (...any) -> ()

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

type Packed<T> = { [number]: T, n: number }

--[[
	ModuleScript loader that bypasses Roblox's require cache.

	This class aims to solve a common problem where code needs to be run in
	Studio, but once a change is made to an already required module the whole
	place must be reloaded for the cache to be reset. With this class, modules
	can either be loaded into a fresh sandbox with `loadModule()` or cached with
	`require()` and later refreshed with `clear()`.
]]
function createProxyModuleLoader(): ProxyModuleLoader
	local requireCache: { [ModuleScript]: Packed<any> } = {}
	local connections: { [ModuleScript]: RBXScriptConnection } = {}

	--[[
		Fired when any ModuleScript required through this class has its ancestry
		or `Source` property changed. This applies to the ModuleScript passed to
		`ModuleLoader:require()` and every module that it subsequently requirs.

		This event is useful for reloading a module when it or any of its
		dependencies change.

		```lua
		local loader = createProxyModuleLoader()
		local result = loader.require(module)

		loader.loadedModuleChanged:Connect(function()
			loader.clear()
			result = loader.require(module)
		end)
		```
	]]
	local loadedModuleChanged = Instance.new("BindableEvent")

	--[[
		Load a module with a fresh ModuleScript require cache.

		This method is functionally the same as running `require(script.Parent.ModuleScript)`,
		however in this case the result is not cached between calls. As such, each
		invocation gets its own sandbox.

		```lua
		local loader = createProxyModuleLoader()
		local module = loader.loadModule(script.Parent.ModuleScript)
		```
	]]
	local function load(moduleScript: ModuleScript, cache: { [ModuleScript]: Packed<any> }): unknown
		local required: { [ModuleScript]: true } = {}

		local weHaveRequireAtHome
		function weHaveRequireAtHome(module: ModuleScript | string, caller: ModuleScript?)
			local resolvedModule: ModuleScript
			if typeof(module) == "string" then
				local relativeTo: Instance = if caller then caller else moduleScript
				resolvedModule = resolveInstancePath(relativeTo, module) :: ModuleScript
			else
				resolvedModule = module
			end

			required[resolvedModule] = true

			if not cache[resolvedModule] then
				local moduleFunction = getModuleFunction(resolvedModule)

				local function childRequire(childModule: ModuleScript | string)
					return weHaveRequireAtHome(childModule, resolvedModule)
				end

				-- TODO: Do something about this so we pre-cache and _then_
				-- invoke moduleFunction, since that will implicitly require
				-- more modules and cause issues with circular deps

				cache[resolvedModule] = table.pack(
					-- Notice how the arguments here map to `mergedParams` in
					-- `getModuleFunction`, which in this case is `script` and
					-- `require` in the context of the loaded module.
					moduleFunction(resolvedModule, childRequire)
				)
			end
			local packed = cache[resolvedModule]
			return table.unpack(packed, 1, packed.n)
		end

		local result = table.pack(weHaveRequireAtHome(moduleScript, nil))

		for requiredModule in required do
			if not connections[requiredModule] then
				connections[requiredModule] = requiredModule.Changed:Connect(function()
					loadedModuleChanged:Fire(moduleScript)
				end)
			end
		end

		return table.unpack(result, 1, result.n)
	end

	local function loadModule(moduleScript: ModuleScript): ...unknown?
		return load(moduleScript, {})
	end

	--[[
		Require a module and cache the result of each loaded module.

		Subsequent calls will reuse cached exports until `clear()` is called.
	]]
	local function require(moduleScript: ModuleScript): ...unknown?
		return load(moduleScript, requireCache)
	end

	local function clear()
		table.clear(requireCache)

		for _, connection in connections do
			connection:Disconnect()
		end

		table.clear(connections)
	end

	return {
		require = require,
		loadModule = loadModule,
		clear = clear,
		loadedModuleChanged = loadedModuleChanged.Event,
	}
end

return createProxyModuleLoader
