local bind = require(script.bind)
local getEnv = require(script.getEnv)
local generateScriptHeader = require(script.generateScriptHeader)

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

--[=[
    Constructs a new ModuleLoader instance.
]=]
function ModuleLoader.new()
	local self = {}

	self._cache = {}

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

function ModuleLoader:_require(module: ModuleScript)
	if self._cache[module] then
		return self:_loadCachedModule(module)
	end

	local moduleFn = self.requireOnce(module)
	local returnValues = { pcall(moduleFn) }

	self._cache[module] = returnValues

	return self:_loadCachedModule(module)
end

--[=[
	Require a module with a fresh ModuleScript require cache.

	This function works similarly to `require()` in that the given module will
	be loaded, however the usual cache that Roblox keeps is not respected.
]=]
function ModuleLoader:load(module: ModuleScript)
	local moduleFn = loadstring(generateScriptHeader(module) .. module.Source)

	local env = getEnv(module)
	env.require = bind(self, self._require)

	setfenv(moduleFn, env)

	return moduleFn()
end

--[=[
	Clears out the cache.
]=]
function ModuleLoader:clear()
	self._cache = {}
end

return ModuleLoader
