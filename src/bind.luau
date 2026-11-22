--[[
	A method such as `ScriptService.ResolveModulePath` takes the object it
	belongs to as its first argument. This returns a function that passes `self`
	as that argument, so the method can go where a plain function is expected.
]]
local function bind<Self, A..., R...>(fn: (self: Self, A...) -> R..., self: Self): (A...) -> R...
	return function(...: A...): R...
		return fn(self, ...)
	end
end

return bind
