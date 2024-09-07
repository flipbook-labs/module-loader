--[[
	Creates a table that can be indexed and added to while also adding to a base
	table.

	This is used for module globals so that a module can define variables on _G
	which are maintained in a dictionary of all globals AND a dictionary of the
	globals a given module has defined.

	This makes it easy to clear out the globals a modeule defines when removing
	it from the cache.
]]

type AnyTable = { [any]: any }

local function createTablePassthrough(base: AnyTable): AnyTable
	local proxy = {}

	setmetatable(proxy, {
		__index = function(self, key)
			local global = rawget(self, key)
			return if global then global else base[key]
		end,
		__newindex = function(self, key, value)
			base[key] = value
			rawset(self, key, value)
		end,
	})

	return proxy :: any
end

return createTablePassthrough
