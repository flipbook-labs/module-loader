--[[
	Huge thanks to EgoMoose for the original implementation. Here's the original
	comment that sparked this approach:

	https://github.com/flipbook-labs/module-loader/pull/34#issuecomment-4082559439
]]

local ScriptEditorService: ScriptEditorService?
pcall(function()
	ScriptEditorService = game:GetService("ScriptEditorService")
end)

local cleanLoadstringStack = require("@root/cleanLoadstringStack")
local createModuleRegistry = require("./createModuleRegistry")
local getModuleSource = require("@root/getModuleSource")
local resolveInstancePath = require("./resolveInstancePath")
local types = require("./types")

type LoadedModule = types.LoadedModule
type ModuleLoader = types.ModuleLoader
type ModuleRegistry = types.ModuleRegistry
type ModuleFunction = types.ModuleFunction

local function requireWithLoadstring(moduleScript: ModuleScript)
	local moduleFunction, errorMessage = loadstring(getModuleSource(moduleScript), moduleScript:GetFullName())
	if errorMessage then
		errorMessage = cleanLoadstringStack(errorMessage)
	end

	return moduleFunction, errorMessage
end

local function getModuleFunction(moduleScript: ModuleScript, params: { string }?): ModuleFunction
	local tmpScript = Instance.new("ModuleScript")
	tmpScript.Name = moduleScript.Name
	tmpScript.Archivable = false

	local mergedParams = { "script", "require" }
	if params then
		for _, param in params do
			table.insert(mergedParams, param)
		end
	end

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

function createModuleLoader(): ModuleLoader
	local moduleRegistry = createModuleRegistry()
	local changedConnections: { [ModuleScript]: RBXScriptConnection } = {}
	local globals = setmetatable({} :: typeof(_G), { __index = _G })

	local function _getModuleRegistry()
		return moduleRegistry
	end

	local loadedModuleChanged = Instance.new("BindableEvent")

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

	local function require(moduleScript: ModuleScript): unknown
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

				local moduleFunction = getModuleFunction(resolvedModule, { "_G" })

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
				local exports = table.pack(moduleFunction(resolvedModule, childRequire, globals))

				loadedModule.exports = exports
				loadedModule.isLoaded = true

				return table.unpack(exports, 1, exports.n)
			end
		end

		return weHaveRequireAtHome(moduleScript, nil)
	end

	local function clear()
		moduleRegistry.reset()
		table.clear(globals)

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
