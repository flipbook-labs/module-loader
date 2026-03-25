local ScriptEditorService: ScriptEditorService?
pcall(function()
	ScriptEditorService = game:GetService("ScriptEditorService")
end)

local resolveInstancePath = require("@root/resolveInstancePath")

local function getModuleFunction(moduleScript: ModuleScript)
	local tmpScript = Instance.new("ModuleScript")
	tmpScript.Name = moduleScript.Name
	tmpScript.Archivable = false

	local mergedParams = { "script", "require" }

	local headers = {}
	local rawSource = if ScriptEditorService
		then ScriptEditorService:GetEditorSource(moduleScript)
		else moduleScript.Source
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

	local callback
	local ok, err = pcall(function()
		callback = require(tmpScript) :: (...any) -> ...any
	end)

	tmpScript:Destroy()

	if not ok then
		error(err)
	end

	return callback
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
	require: (moduleScript: ModuleScript | string) -> unknown,
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
	local function require(moduleScript: ModuleScript | string): ((() -> ())?, string?)
		local required = {}

		local loadModule
		function loadModule(module: ModuleScript | string)
			local resolvedModule: ModuleScript
			if typeof(module) == "string" then
				resolvedModule = resolveInstancePath((moduleScript :: any) :: Instance, module) :: ModuleScript
			else
				resolvedModule = module
			end

			if not required[resolvedModule] then
				local callback = getModuleFunction(resolvedModule)
				required[resolvedModule] = table.pack(callback(resolvedModule, loadModule))
			end
			local packed = required[resolvedModule]
			return table.unpack(packed, 1, packed.n)
		end

		-- TODO: When anything in `required` is Changed then fire
		-- `loadedModuleChanged` This includes ancestry changes and Source
		-- changes to any ModuleScript in `required`

		return loadModule(moduleScript)
	end

	return {
		require = require,
		loadedModuleChanged = loadedModuleChanged.Event,
	}
end

return createProxyModuleLoader
