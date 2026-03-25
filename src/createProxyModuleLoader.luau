local ScriptEditorService: ScriptEditorService?
pcall(function()
	ScriptEditorService = game:GetService("ScriptEditorService")
end)

local requireWithLoadstring = require("@root/loading-strategies/requireWithLoadstring")
local resolveInstancePath = require("@root/resolveInstancePath")

local function getModuleFunction(moduleScript: ModuleScript): (...any) -> ()
	local tmpScript = Instance.new("ModuleScript")
	tmpScript.Name = moduleScript.Name
	tmpScript.Archivable = false

	local mergedParams = { "script", "require" }

	local rawSource = if ScriptEditorService
		then ScriptEditorService:GetEditorSource(moduleScript)
		else moduleScript.Source

	local headers = {}
	local lines = rawSource:split("\n")
	for i = 1, #lines do
		local line = lines[i]
		if line:sub(1, 3) == "--!" then
			table.insert(headers, line .. "\n")
		end
	end

	local source = table.concat(lines, "\n", #headers + 1)

	-- The formatting is crazy here, but we retain line numbers
	local newSource = `{table.concat(headers)}return (function({table.concat(mergedParams, ", ")}) {source} end)`

	if ScriptEditorService then
		ScriptEditorService:UpdateSourceAsync(tmpScript, function()
			return newSource
		end)
	else
		tmpScript.Source = newSource
	end

	local moduleFunction
	local ok, err = pcall(function()
		moduleFunction = require(tmpScript) :: (...any) -> ...any
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

		error(errorMessage)
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
function createProxyModuleLoader(): {
	require: (moduleScript: ModuleScript) -> unknown,
	loadedModuleChanged: RBXScriptSignal,
}
	--[[
		Fired when any ModuleScript required through this class has its ancestry
		or `Source` property changed. This applies to the ModuleScript passed to
		`ModuleLoader:require()` and every module that it subsequently requirs.

		This event is useful for reloading a module when it or any of it
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
		Require a module with a fresh ModuleScript require cache.

		This method is functionally the same as running `require(script.Parent.ModuleScript)`,
		however in this case the module is not cached. As such, if a change occurs
		to the module you can call this method again to get the latest changes.

		```lua
		local loader = createProxyModuleLoader()
		local module = loader.require(script.Parent.ModuleScript)
		```
	]]
	local function require(moduleScript: ModuleScript): unknown
		local required: { [ModuleScript]: { [number]: any, n: number } } = {}

		local weHaveRequireAtHome
		function weHaveRequireAtHome(module: ModuleScript | string, caller: ModuleScript?)
			local resolvedModule: ModuleScript
			if typeof(module) == "string" then
				local relativeTo: Instance = if caller then caller else moduleScript
				resolvedModule = resolveInstancePath(relativeTo, module) :: ModuleScript
			else
				resolvedModule = module
			end

			if not required[resolvedModule] then
				local moduleFunction = getModuleFunction(resolvedModule)

				local function childRequire(childModule: ModuleScript | string)
					return weHaveRequireAtHome(childModule, resolvedModule)
				end

				required[resolvedModule] = table.pack(
					-- Notice how the arguments here map to `mergedParams` in
					-- `getModuleFunction`, which in this case is `script` and
					-- `require` in the context of the loaded module.
					moduleFunction(resolvedModule, childRequire)
				)
			end
			local packed = required[resolvedModule]
			return table.unpack(packed, 1, packed.n)
		end

		-- TODO: When anything in `required` is Changed then fire
		-- `loadedModuleChanged` This includes ancestry changes and Source
		-- changes to any ModuleScript in `required`

		return weHaveRequireAtHome(moduleScript, nil)
	end

	return {
		require = require,
		loadedModuleChanged = loadedModuleChanged.Event,
	}
end

return createProxyModuleLoader
