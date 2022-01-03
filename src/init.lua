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
	Set the cached value for a module before it is loaded.

	This is useful is very specific situations. For example, this method is
	used to cache a copy of Roact so that when a module is loaded with this
	class it uses the same table instance.
]=]
function ModuleLoader:cache(module: ModuleScript, source: any)
	self._cache[module] = { true, source }
end

--[=[
	Require a module with a fresh ModuleScript require cache.

	This function works similarly to `require()` in that the given module will
	be loaded, however the usual cache that Roblox keeps is not respected.
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

	return self:_loadCachedModule(module)
end

--[=[
	Clears out the cache.
]=]
function ModuleLoader:clear()
	self._cache = {}
end

return ModuleLoader
